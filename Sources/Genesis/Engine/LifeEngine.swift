import Foundation

enum Topology: String, CaseIterable, Identifiable {
    case torus
    case bounded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .torus: return "Torus (wrapping edges)"
        case .bounded: return "Bounded (dead edges)"
        }
    }
}

enum Symmetry: String, CaseIterable, Identifiable {
    case none
    case mirror
    case quad
    case rotational

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .mirror: return "Mirror"
        case .quad: return "Fourfold"
        case .rotational: return "Rotational"
        }
    }
}

struct PopulationSample: Hashable {
    var generation: Int
    var population: Int
}

/// Game of Life engine on a finite grid (toroidal or bounded).
///
/// Cells live in manually managed contiguous buffers for maximum speed;
/// each generation is computed in parallel over bands of rows.
final class LifeEngine {
    struct Snapshot {
        let generation: Int
        let population: Int
        let width: Int
        let height: Int
        let bits: [UInt64]
    }

    private(set) var width: Int
    private(set) var height: Int
    private(set) var cells: UnsafeMutablePointer<UInt8>
    private var next: UnsafeMutablePointer<UInt8>
    /// Age of live cells (1...255), 0 for dead ones.
    private(set) var age: UnsafeMutablePointer<UInt8>
    /// Glowing trail of recently dead cells (255 → 0).
    private(set) var trail: UnsafeMutablePointer<UInt8>

    var rule: Rule { didSet { rebuildTable() } }
    var topology: Topology = .torus
    /// How much the trail fades each generation.
    var trailDecay: UInt8 = 18

    private(set) var generation = 0
    private(set) var population = 0
    private(set) var lastBirths = 0
    private(set) var lastDeaths = 0
    /// Bumped on every state change so the renderer knows when to redraw.
    private(set) var version = 0

    private var table = [UInt8](repeating: 0, count: 18)

    // History for rewinding (ring buffer).
    private var history: [Snapshot?] = []
    private var historyHead = 0   // index of the next free slot
    private var historyCount = 0
    private var historyCapacity = 0

    // Bit-packed state of the current generation (cached).
    private var packed: [UInt64]? = nil
    private var packedHash: UInt64 = 0

    // Cycle detection.
    private var seenHashes: [UInt64: Int] = [:]
    private(set) var cycleStart: Int? = nil
    private(set) var cyclePeriod: Int? = nil

    private(set) var populationHistory: [PopulationSample] = []

    init(width: Int, height: Int, rule: Rule = .conway) {
        self.width = width
        self.height = height
        self.rule = rule
        let n = width * height
        cells = LifeEngine.allocate(n)
        next = LifeEngine.allocate(n)
        age = LifeEngine.allocate(n)
        trail = LifeEngine.allocate(n)
        rebuildTable()
        configureHistory()
        recordPopulation()
    }

    deinit {
        cells.deallocate()
        next.deallocate()
        age.deallocate()
        trail.deallocate()
    }

    private static func allocate(_ n: Int) -> UnsafeMutablePointer<UInt8> {
        let p = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, n))
        p.initialize(repeating: 0, count: max(1, n))
        return p
    }

    var cellCount: Int { width * height }
    private var wordsPerRow: Int { (width + 63) / 64 }

    private func rebuildTable() {
        for n in 0...8 {
            table[n] = rule.births(n) ? 1 : 0
            table[9 + n] = rule.survives(n) ? 1 : 0
        }
    }

    private func configureHistory() {
        let bytesPerSnapshot = max(1, wordsPerRow * height * 8)
        let budget = 160 * 1024 * 1024
        historyCapacity = max(32, min(3000, budget / bytesPerSnapshot))
        history = Array(repeating: nil, count: historyCapacity)
        historyHead = 0
        historyCount = 0
    }

    private func chunkCount(rows: Int) -> Int {
        if width * rows < 64 * 1024 { return 1 }
        return max(1, min(rows, ProcessInfo.processInfo.activeProcessorCount * 4))
    }

    // MARK: - Access

    @inline(__always) func index(_ x: Int, _ y: Int) -> Int { y * width + x }

    func isAlive(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return cells[y * width + x] != 0
    }

    var canStepBack: Bool { historyCount > 0 }

    // MARK: - Evolution

    func step() {
        pushHistory()

        let w = width
        let h = height
        let wrap = topology == .torus
        let decay = trailDecay
        let chunks = chunkCount(rows: h)
        let cur = UnsafePointer(cells)
        let out = next
        let ag = age
        let tr = trail

        let zeroRow = UnsafeMutablePointer<UInt8>.allocate(capacity: w)
        zeroRow.initialize(repeating: 0, count: w)
        let zero = UnsafePointer(zeroRow)
        let results = UnsafeMutablePointer<Int>.allocate(capacity: chunks * 3)
        results.initialize(repeating: 0, count: chunks * 3)

        table.withUnsafeBufferPointer { tb in
            let lut = tb.baseAddress!
            DispatchQueue.concurrentPerform(iterations: chunks) { ci in
                let y0 = ci * h / chunks
                let y1 = (ci + 1) * h / chunks
                let colSum = UnsafeMutablePointer<UInt8>.allocate(capacity: w + 2)
                defer { colSum.deallocate() }
                var pop = 0, births = 0, deaths = 0
                for y in y0..<y1 {
                    let mid = cur + y * w
                    let up: UnsafePointer<UInt8>
                    let down: UnsafePointer<UInt8>
                    if y > 0 { up = cur + (y - 1) * w } else { up = wrap ? cur + (h - 1) * w : zero }
                    if y < h - 1 { down = cur + (y + 1) * w } else { down = wrap ? cur : zero }

                    for x in 0..<w {
                        colSum[x + 1] = up[x] &+ mid[x] &+ down[x]
                    }
                    if wrap {
                        colSum[0] = colSum[w]
                        colSum[w + 1] = colSum[1]
                    } else {
                        colSum[0] = 0
                        colSum[w + 1] = 0
                    }

                    let rowBase = y * w
                    let rowOut = out + rowBase
                    for x in 0..<w {
                        let alive = mid[x]
                        let n = colSum[x] &+ colSum[x + 1] &+ colSum[x + 2] &- alive
                        let v = lut[Int(alive) &* 9 &+ Int(n)]
                        rowOut[x] = v
                        let i = rowBase + x
                        if v != 0 {
                            pop += 1
                            if alive == 0 {
                                births += 1
                                ag[i] = 1
                                tr[i] = 0
                            } else {
                                let a = ag[i]
                                if a < 255 { ag[i] = a &+ 1 }
                            }
                        } else if alive != 0 {
                            deaths += 1
                            ag[i] = 0
                            tr[i] = 255
                        } else {
                            let t = tr[i]
                            if t != 0 { tr[i] = t > decay ? t &- decay : 0 }
                        }
                    }
                }
                results[ci * 3] = pop
                results[ci * 3 + 1] = births
                results[ci * 3 + 2] = deaths
            }
        }

        var pop = 0, births = 0, deaths = 0
        for ci in 0..<chunks {
            pop += results[ci * 3]
            births += results[ci * 3 + 1]
            deaths += results[ci * 3 + 2]
        }
        results.deallocate()
        zeroRow.deallocate()

        swap(&cells, &next)
        population = pop
        lastBirths = births
        lastDeaths = deaths
        generation += 1
        version &+= 1
        packed = nil
        recordPopulation()
        detectCycle()
    }

    /// Goes back to the previous state (generation or edit). Returns false if the history is empty.
    @discardableResult
    func stepBack() -> Bool {
        guard historyCount > 0 else { return false }
        historyHead = (historyHead - 1 + historyCapacity) % historyCapacity
        historyCount -= 1
        guard let snap = history[historyHead] else { return false }
        history[historyHead] = nil
        restore(snap)
        return true
    }

    /// Saves the current state to the history: call before a manual edit (acts as an "Undo" point).
    func checkpoint() {
        pushHistory()
    }

    func makeSnapshot() -> Snapshot {
        let bits = currentPacked()
        return Snapshot(generation: generation, population: population, width: width, height: height, bits: bits)
    }

    func restore(_ snap: Snapshot) {
        if snap.width != width || snap.height != height {
            reallocate(width: snap.width, height: snap.height)
        }
        let w = width
        let h = height
        let wpr = wordsPerRow
        let c = cells
        let ag = age
        let tr = trail
        snap.bits.withUnsafeBufferPointer { bp in
            let bits = bp.baseAddress!
            let chunks = chunkCount(rows: h)
            DispatchQueue.concurrentPerform(iterations: chunks) { ci in
                let y0 = ci * h / chunks
                let y1 = (ci + 1) * h / chunks
                for y in y0..<y1 {
                    let row = bits + y * wpr
                    for x in 0..<w {
                        let i = y * w + x
                        let v = UInt8(truncatingIfNeeded: (row[x >> 6] >> UInt64(x & 63)) & 1)
                        if v != 0 {
                            if c[i] == 0 { ag[i] = 1 }
                        } else {
                            ag[i] = 0
                        }
                        tr[i] = 0
                        c[i] = v
                    }
                }
            }
        }
        generation = snap.generation
        population = snap.population
        lastBirths = 0
        lastDeaths = 0
        packed = snap.bits
        packedHash = LifeEngine.hash(snap.bits)
        version &+= 1
        resetCycleDetection()
        recordPopulation()
    }

    private func pushHistory() {
        guard historyCapacity > 0 else { return }
        let snap = makeSnapshot()
        history[historyHead] = snap
        historyHead = (historyHead + 1) % historyCapacity
        historyCount = min(historyCount + 1, historyCapacity)
    }

    func clearHistory() {
        for i in 0..<history.count { history[i] = nil }
        historyHead = 0
        historyCount = 0
    }

    // MARK: - Packing and cycles

    private func currentPacked() -> [UInt64] {
        if let p = packed { return p }
        let w = width
        let h = height
        let wpr = wordsPerRow
        var bits = [UInt64](repeating: 0, count: wpr * h)
        let c = UnsafePointer(cells)
        let chunks = chunkCount(rows: h)
        bits.withUnsafeMutableBufferPointer { bp in
            let base = bp.baseAddress!
            DispatchQueue.concurrentPerform(iterations: chunks) { ci in
                let y0 = ci * h / chunks
                let y1 = (ci + 1) * h / chunks
                for y in y0..<y1 {
                    let row = c + y * w
                    let outRow = base + y * wpr
                    for wi in 0..<wpr {
                        let x0 = wi << 6
                        let n = min(64, w - x0)
                        var word: UInt64 = 0
                        for b in 0..<n {
                            word |= UInt64(row[x0 + b] & 1) << UInt64(b)
                        }
                        outRow[wi] = word
                    }
                }
            }
        }
        packed = bits
        packedHash = LifeEngine.hash(bits)
        return bits
    }

    private static func hash(_ bits: [UInt64]) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for word in bits {
            h ^= word
            h = h &* 0x0000_0100_0000_01B3
            h ^= h >> 29
        }
        return h
    }

    private func detectCycle() {
        _ = currentPacked()
        if let seen = seenHashes[packedHash] {
            if cyclePeriod == nil {
                cycleStart = seen
                cyclePeriod = generation - seen
            }
        } else {
            seenHashes[packedHash] = generation
            if seenHashes.count > 12_000 {
                let limit = generation - 6_000
                seenHashes = seenHashes.filter { $0.value > limit }
            }
        }
    }

    func resetCycleDetection() {
        seenHashes.removeAll(keepingCapacity: true)
        cycleStart = nil
        cyclePeriod = nil
        if population > 0 || generation > 0 {
            _ = currentPacked()
            seenHashes[packedHash] = generation
        }
    }

    private func recordPopulation() {
        while let last = populationHistory.last, last.generation >= generation {
            populationHistory.removeLast()
        }
        populationHistory.append(PopulationSample(generation: generation, population: population))
        if populationHistory.count > 900 {
            populationHistory.removeFirst(populationHistory.count - 600)
        }
    }

    // MARK: - Editing

    private func didEdit(recount: Bool) {
        if recount { recountPopulation() }
        packed = nil
        version &+= 1
        resetCycleDetection()
        recordPopulation()
    }

    private func recountPopulation() {
        var n = 0
        let c = cells
        for i in 0..<cellCount where c[i] != 0 { n += 1 }
        population = n
    }

    func setCell(_ x: Int, _ y: Int, alive: Bool) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let i = y * width + x
        let v: UInt8 = alive ? 1 : 0
        if cells[i] == v { return }
        cells[i] = v
        age[i] = v
        trail[i] = 0
        population += alive ? 1 : -1
        didEdit(recount: false)
    }

    /// Sets many cells at once (for drawing strokes).
    func setCells(_ points: [CellPoint], alive: Bool) {
        let v: UInt8 = alive ? 1 : 0
        var changed = false
        for p in points where p.x >= 0 && p.y >= 0 && p.x < width && p.y < height {
            let i = p.y * width + p.x
            if cells[i] != v {
                cells[i] = v
                age[i] = v
                trail[i] = 0
                population += alive ? 1 : -1
                changed = true
            }
        }
        if changed { didEdit(recount: false) }
    }

    func clear() {
        let n = cellCount
        cells.update(repeating: 0, count: n)
        age.update(repeating: 0, count: n)
        trail.update(repeating: 0, count: n)
        population = 0
        lastBirths = 0
        lastDeaths = 0
        didEdit(recount: false)
    }

    func resetGeneration() {
        generation = 0
        populationHistory.removeAll()
        didEdit(recount: false)
    }

    func clear(rect: GridRect) {
        let r = rect.clamped(width: width, height: height)
        guard !r.isEmpty else { return }
        for y in r.y..<r.maxY {
            let base = y * width
            for x in r.x..<r.maxX {
                cells[base + x] = 0
                age[base + x] = 0
                trail[base + x] = 0
            }
        }
        didEdit(recount: true)
    }

    func randomize(in rect: GridRect, density: Double, symmetry: Symmetry, seed: UInt64) {
        let r = rect.clamped(width: width, height: height)
        guard !r.isEmpty else { return }
        let threshold = UInt64(max(0, min(1, density)) * Double(UInt64(1) << 53))
        let rw = r.width
        let rh = r.height
        for ly in 0..<rh {
            for lx in 0..<rw {
                var fx = lx
                var fy = ly
                switch symmetry {
                case .none:
                    break
                case .mirror:
                    fx = min(lx, rw - 1 - lx)
                case .quad:
                    fx = min(lx, rw - 1 - lx)
                    fy = min(ly, rh - 1 - ly)
                case .rotational:
                    let ox = rw - 1 - lx
                    let oy = rh - 1 - ly
                    if ly * rw + lx > oy * rw + ox {
                        fx = ox
                        fy = oy
                    }
                }
                let h = LifeEngine.mix(UInt64(truncatingIfNeeded: fx) << 32 ^ UInt64(truncatingIfNeeded: fy) ^ seed)
                let alive = (h >> 11) < threshold
                let i = (r.y + ly) * width + (r.x + lx)
                let v: UInt8 = alive ? 1 : 0
                cells[i] = v
                age[i] = v
                trail[i] = 0
            }
        }
        didEdit(recount: true)
    }

    private static func mix(_ z0: UInt64) -> UInt64 {
        var z = z0 &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Adds the pattern (OR-ed) with its top-left corner at (x0, y0).
    func place(_ pattern: Pattern, atX x0: Int, y y0: Int) {
        let wrap = topology == .torus
        for c in pattern.cells {
            var x = x0 + c.x
            var y = y0 + c.y
            if wrap {
                x = ((x % width) + width) % width
                y = ((y % height) + height) % height
            } else if x < 0 || y < 0 || x >= width || y >= height {
                continue
            }
            let i = y * width + x
            if cells[i] == 0 {
                cells[i] = 1
                age[i] = 1
                trail[i] = 0
            }
        }
        didEdit(recount: true)
    }

    func extract(rect: GridRect) -> Pattern {
        let r = rect.clamped(width: width, height: height)
        guard !r.isEmpty else { return .empty }
        var pts: [CellPoint] = []
        for y in r.y..<r.maxY {
            let base = y * width
            for x in r.x..<r.maxX where cells[base + x] != 0 {
                pts.append(CellPoint(x: x - r.x, y: y - r.y))
            }
        }
        return Pattern(width: r.width, height: r.height, cells: pts)
    }

    /// The smallest rectangle containing every live cell.
    func boundingBox() -> GridRect? {
        guard population > 0 else { return nil }
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for y in 0..<height {
            let row = cells + y * width
            var first = -1
            var last = -1
            for x in 0..<width where row[x] != 0 {
                if first < 0 { first = x }
                last = x
            }
            if first >= 0 {
                minY = min(minY, y)
                maxY = max(maxY, y)
                minX = min(minX, first)
                maxX = max(maxX, last)
            }
        }
        guard minX <= maxX else { return nil }
        return GridRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Resizes the grid, keeping the content centered.
    func resize(width newW: Int, height newH: Int) {
        guard newW != width || newH != height else { return }
        let oldW = width
        let oldH = height
        let oldCells = cells
        let oldAge = age
        let newCells = LifeEngine.allocate(newW * newH)
        let newAge = LifeEngine.allocate(newW * newH)
        let dx = (newW - oldW) / 2
        let dy = (newH - oldH) / 2
        for y in 0..<oldH {
            let ny = y + dy
            guard ny >= 0 && ny < newH else { continue }
            for x in 0..<oldW {
                let nx = x + dx
                guard nx >= 0 && nx < newW else { continue }
                newCells[ny * newW + nx] = oldCells[y * oldW + x]
                newAge[ny * newW + nx] = oldAge[y * oldW + x]
            }
        }
        cells.deallocate()
        next.deallocate()
        age.deallocate()
        trail.deallocate()
        width = newW
        height = newH
        cells = newCells
        age = newAge
        next = LifeEngine.allocate(newW * newH)
        trail = LifeEngine.allocate(newW * newH)
        configureHistory()
        didEdit(recount: true)
    }

    private func reallocate(width newW: Int, height newH: Int) {
        cells.deallocate()
        next.deallocate()
        age.deallocate()
        trail.deallocate()
        width = newW
        height = newH
        cells = LifeEngine.allocate(newW * newH)
        next = LifeEngine.allocate(newW * newH)
        age = LifeEngine.allocate(newW * newH)
        trail = LifeEngine.allocate(newW * newH)
        // History stays valid: snapshots carry their own dimensions.
    }
}
