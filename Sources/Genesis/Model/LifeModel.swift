import SwiftUI
import AppKit
import QuartzCore
import UniformTypeIdentifiers

enum Tool: String, CaseIterable, Identifiable {
    case draw
    case erase
    case select
    case pan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draw: return "Draw"
        case .erase: return "Erase"
        case .select: return "Select"
        case .pan: return "Pan"
        }
    }

    var symbol: String {
        switch self {
        case .draw: return "pencil.tip"
        case .erase: return "eraser"
        case .select: return "rectangle.dashed"
        case .pan: return "hand.raised"
        }
    }

    var key: String {
        switch self {
        case .draw: return "1"
        case .erase: return "2"
        case .select: return "3"
        case .pan: return "4"
        }
    }
}

/// Application state: settings, statistics and commands.
/// The canvas syncs the engine and the view on every frame.
@MainActor
@Observable
final class LifeModel {
    static let shared = LifeModel()

    static let speeds: [Double] = [1, 2, 4, 8, 15, 30, 60, 120, 250, 500, 1000, 1_000_000]
    static let gridSizes = [128, 256, 512, 1024, 2048]

    let engine: LifeEngine
    let renderer = CellRenderer()
    @ObservationIgnored weak var canvas: LifeCanvasView?

    // MARK: Simulation
    var isRunning = false
    var speedIndex = 6
    var rule: Rule = .conway
    var ruleText = Rule.conway.notation
    var topology: Topology = .torus
    var gridSize = 512
    var autoPause = true

    // MARK: Appearance
    var paletteID = Palette.default.id
    var ageColoring = true
    var trailLength = 14.0
    var showGrid = true
    var glow = false

    // MARK: Tools
    var tool: Tool = .draw
    var placing: Pattern? = nil
    var placingName: String? = nil
    var selection: GridRect? = nil
    var density = 0.3
    var symmetry: Symmetry = .none
    var hoverCell: CellPoint? = nil

    // MARK: Interface
    var showInspector = true
    var showHelp = false
    var toast: String? = nil

    // MARK: Published statistics
    var generation = 0
    var population = 0
    var births = 0
    var deaths = 0
    var measuredSpeed = 0.0
    var cycleStart: Int? = nil
    var cyclePeriod: Int? = nil
    var popHistory: [Int] = []
    var canStepBack = false
    var hasStartSnapshot = false

    // MARK: Internal state
    @ObservationIgnored private(set) var placingVersion = 0
    @ObservationIgnored private var accumulator = 0.0
    @ObservationIgnored private var lastPublish = 0.0
    @ObservationIgnored private var speedWindowStart = 0.0
    @ObservationIgnored private var speedWindowGens = 0
    @ObservationIgnored private var startSnapshot: LifeEngine.Snapshot? = nil
    @ObservationIgnored private var editedSinceStart = true
    @ObservationIgnored private var autoPausedCycle: Int? = nil
    @ObservationIgnored private var toastToken = 0

    init() {
        engine = LifeEngine(width: 512, height: 512)
        engine.trailDecay = LifeModel.decay(for: trailLength)
        engine.randomize(in: GridRect(x: 0, y: 0, width: 512, height: 512),
                         density: 0.3, symmetry: .none, seed: UInt64.random(in: 0...UInt64.max))
        engine.resetGeneration()
        engine.clearHistory()
        startSnapshot = engine.makeSnapshot()
        hasStartSnapshot = true
        editedSinceStart = false
        isRunning = true
        speedIndex = 5
        // On small screens the inspector starts closed to leave room for the world.
        showInspector = (NSScreen.main?.visibleFrame.width ?? 1600) >= 1440
        publishStats(force: true)
    }

    var palette: Palette { Palette.all.first { $0.id == paletteID } ?? .default }

    var speedLabel: String { LifeModel.speedLabel(speedIndex) }

    static func speedLabel(_ index: Int) -> String {
        let v = speeds[max(0, min(speeds.count - 1, index))]
        return v >= 100_000 ? "Max" : "\(Int(v)) gen/s"
    }

    static func decay(for length: Double) -> UInt8 {
        if length < 1 { return 255 }
        return UInt8(max(1, min(255, Int((255 / length).rounded(.up)))))
    }

    var statusText: String {
        if population == 0 { return generation == 0 ? "Empty world" : "Extinct" }
        if let p = cyclePeriod { return p == 1 ? "Stable" : "Cycle of period \(p)" }
        return "Evolving"
    }

    var statusSymbol: String {
        if population == 0 { return "circle.dashed" }
        if let p = cyclePeriod { return p == 1 ? "pause.circle" : "arrow.triangle.2.circlepath" }
        return "sparkles"
    }

    // MARK: - Per-frame loop

    /// Pushes the interface settings into the engine.
    func syncSettings() {
        if engine.rule != rule {
            engine.rule = rule
            engine.resetCycleDetection()
            autoPausedCycle = nil
        }
        if engine.topology != topology {
            engine.topology = topology
            engine.resetCycleDetection()
            autoPausedCycle = nil
        }
        let d = LifeModel.decay(for: trailLength)
        if engine.trailDecay != d { engine.trailDecay = d }
        if engine.width != gridSize {
            engine.resize(width: gridSize, height: gridSize)
            selection = nil
            markEdited()
            publishStats(force: true)
            canvas?.zoomToFit(contentOnly: false)
        }
    }

    func tick(dt: Double) {
        let now = CACurrentMediaTime()
        defer { updateMeasuredSpeed(now: now) }
        guard isRunning else { return }
        accumulator += min(dt, 0.1) * LifeModel.speeds[speedIndex]
        guard accumulator >= 1 else { return }
        let target = Int(accumulator)
        let start = CACurrentMediaTime()
        var done = 0
        while done < target {
            engine.step()
            done += 1
            if engine.population == 0 { break }
            if autoPause, let cs = engine.cycleStart, cs != autoPausedCycle { break }
            if CACurrentMediaTime() - start > 0.014 { break }
        }
        accumulator -= Double(done)
        if accumulator > 1 { accumulator = accumulator.truncatingRemainder(dividingBy: 1) }
        speedWindowGens += done
        checkAutoPause()
        publishStats()
    }

    private func checkAutoPause() {
        if engine.population == 0 {
            isRunning = false
            showToast(engine.generation == 0 ? "The world is empty: draw something or generate a random soup"
                                             : "Population went extinct at generation \(engine.generation)")
            publishStats(force: true)
            return
        }
        guard autoPause, let cs = engine.cycleStart, let p = engine.cyclePeriod, cs != autoPausedCycle else { return }
        autoPausedCycle = cs
        isRunning = false
        if p == 1 {
            showToast("Stabilized at generation \(cs)")
        } else {
            showToast("Cycle of period \(p) reached at generation \(cs)")
        }
        publishStats(force: true)
    }

    private func updateMeasuredSpeed(now: Double) {
        if speedWindowStart == 0 { speedWindowStart = now }
        let elapsed = now - speedWindowStart
        if elapsed >= 0.5 {
            let v = isRunning ? Double(speedWindowGens) / elapsed : 0
            if abs(v - measuredSpeed) > 0.05 { measuredSpeed = v }
            speedWindowGens = 0
            speedWindowStart = now
        }
    }

    func publishStats(force: Bool = false) {
        let now = CACurrentMediaTime()
        if !force && now - lastPublish < 1.0 / 20.0 { return }
        lastPublish = now
        if generation != engine.generation { generation = engine.generation }
        if population != engine.population { population = engine.population }
        if births != engine.lastBirths { births = engine.lastBirths }
        if deaths != engine.lastDeaths { deaths = engine.lastDeaths }
        if cycleStart != engine.cycleStart { cycleStart = engine.cycleStart }
        if cyclePeriod != engine.cyclePeriod { cyclePeriod = engine.cyclePeriod }
        if canStepBack != engine.canStepBack { canStepBack = engine.canStepBack }
        let hist = engine.populationHistory.suffix(400).map { $0.population }
        if hist != popHistory { popHistory = hist }
    }

    private func markEdited() {
        editedSinceStart = true
        autoPausedCycle = nil
    }

    // MARK: - Simulation commands

    func togglePlay() {
        isRunning ? pause() : play()
    }

    func play() {
        syncSettings()
        if engine.population == 0 {
            showToast("The world is empty: draw something or generate a random soup")
            return
        }
        if editedSinceStart || startSnapshot == nil {
            startSnapshot = engine.makeSnapshot()
            hasStartSnapshot = true
            editedSinceStart = false
        }
        if let cs = engine.cycleStart { autoPausedCycle = cs }
        accumulator = 0
        isRunning = true
    }

    func pause() {
        isRunning = false
        publishStats(force: true)
    }

    func step() {
        syncSettings()
        if isRunning { isRunning = false }
        engine.step()
        publishStats(force: true)
    }

    func stepBack() {
        if isRunning { isRunning = false }
        if !engine.stepBack() {
            showToast("You reached the beginning of the recorded history")
        }
        markEdited()
        publishStats(force: true)
    }

    func resetToStart() {
        guard let snap = startSnapshot else { return }
        isRunning = false
        engine.checkpoint()
        engine.restore(snap)
        if gridSize != engine.width { gridSize = engine.width }
        editedSinceStart = false
        autoPausedCycle = nil
        publishStats(force: true)
        showToast("Restored the starting state (generation \(snap.generation))")
    }

    func faster() { speedIndex = min(LifeModel.speeds.count - 1, speedIndex + 1) }
    func slower() { speedIndex = max(0, speedIndex - 1) }

    func clearAll() {
        isRunning = false
        engine.checkpoint()
        engine.clear()
        engine.resetGeneration()
        selection = nil
        markEdited()
        publishStats(force: true)
    }

    /// Fills the selection (or the whole world) with a random soup.
    func randomFill() {
        syncSettings()
        engine.checkpoint()
        let full = GridRect(x: 0, y: 0, width: engine.width, height: engine.height)
        let rect = selection ?? full
        engine.randomize(in: rect, density: density, symmetry: symmetry, seed: UInt64.random(in: 0...UInt64.max))
        if selection == nil { engine.resetGeneration() }
        markEdited()
        publishStats(force: true)
    }

    // MARK: - Rules

    func setRule(_ r: Rule) {
        rule = r
        ruleText = r.notation
        markEdited()
    }

    func applyRuleText() {
        if let r = Rule(ruleText) {
            setRule(r)
            showToast("Rule: \(r.presetName ?? r.notation)")
        } else {
            showToast("Invalid rule: use the form B3/S23")
            ruleText = rule.notation
        }
    }

    func randomRule() {
        let r = Rule.random()
        setRule(r)
        showToast("Random rule: \(r.notation)")
    }

    // MARK: - Drawing

    func beginStroke() {
        engine.checkpoint()
        markEdited()
    }

    func paint(_ points: [CellPoint], alive: Bool) {
        engine.setCells(points, alive: alive)
        publishStats()
    }

    func endStroke() {
        publishStats(force: true)
    }

    // MARK: - Pattern placement

    func beginPlacing(_ item: LibraryItem) {
        beginPlacing(item.pattern, name: item.name)
    }

    func beginPlacing(_ p: Pattern, name: String) {
        guard !p.isEmpty else { return }
        placing = p
        placingName = name
        placingVersion += 1
        if let r = p.rule, r != rule {
            setRule(r)
            showToast("“\(name)”: rule set to \(r.presetName ?? r.notation)")
        } else {
            showToast("“\(name)”: click to place · R rotate · F flip · Esc cancel")
        }
        canvas?.focus()
    }

    func cancelPlacing() {
        guard placing != nil else { return }
        placing = nil
        placingName = nil
        placingVersion += 1
    }

    func rotatePlacing() {
        guard let p = placing else { return }
        placing = p.rotatedClockwise()
        placingVersion += 1
    }

    func flipPlacing() {
        guard let p = placing else { return }
        placing = p.flippedHorizontally()
        placingVersion += 1
    }

    func placePattern(at cell: CellPoint) {
        guard let p = placing else { return }
        syncSettings()
        engine.checkpoint()
        engine.place(p, atX: cell.x - p.width / 2, y: cell.y - p.height / 2)
        markEdited()
        publishStats(force: true)
    }

    /// Replaces the world with the pattern, centered, enlarging the grid if needed.
    func loadPattern(_ p: Pattern, name: String) {
        guard !p.isEmpty else {
            showToast("The pattern is empty")
            return
        }
        isRunning = false
        if let r = p.rule { setRule(r) }
        let needed = max(p.width, p.height) + 48
        let size = LifeModel.gridSizes.first { $0 >= needed } ?? LifeModel.gridSizes[LifeModel.gridSizes.count - 1]
        engine.checkpoint()
        if size > gridSize { gridSize = size }
        syncSettings()
        engine.clear()
        engine.place(p, atX: (engine.width - p.width) / 2, y: (engine.height - p.height) / 2)
        engine.resetGeneration()
        selection = nil
        cancelPlacing()
        markEdited()
        publishStats(force: true)
        canvas?.zoomToFit(contentOnly: true)
        showToast("Loaded “\(name)” · \(p.population) cells")
    }

    // MARK: - Selection

    func selectAll() {
        selection = GridRect(x: 0, y: 0, width: engine.width, height: engine.height)
    }

    func deselect() { selection = nil }

    func deleteSelection() {
        guard let sel = selection else { return }
        engine.checkpoint()
        engine.clear(rect: sel)
        markEdited()
        publishStats(force: true)
    }

    func clearOutsideSelection() {
        guard let sel = selection else { return }
        engine.checkpoint()
        let keep = engine.extract(rect: sel)
        engine.clear()
        engine.place(keep, atX: sel.x, y: sel.y)
        markEdited()
        publishStats(force: true)
    }

    func copySelection(cut: Bool = false) {
        guard let sel = selection else {
            showToast("First select an area with the Select tool (3)")
            return
        }
        let p = engine.extract(rect: sel)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(p.rleString(rule: rule), forType: .string)
        if cut {
            engine.checkpoint()
            engine.clear(rect: sel)
            markEdited()
            publishStats(force: true)
        }
        showToast(cut ? "Cut: \(p.population) cells to the clipboard (RLE)"
                      : "Copied: \(p.population) cells to the clipboard (RLE)")
    }

    func paste() {
        guard let s = NSPasteboard.general.string(forType: .string),
              let p = Pattern.parse(s), !p.isEmpty else {
            showToast("The clipboard does not contain a valid pattern (RLE or plaintext)")
            return
        }
        beginPlacing(p, name: p.name ?? "Pasted pattern")
    }

    // MARK: - Edit menu (forwarded to text fields when editing)

    private var isEditingText: Bool { NSApp.keyWindow?.firstResponder is NSText }

    func menuCopy() {
        if isEditingText { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) } else { copySelection() }
    }

    func menuCut() {
        if isEditingText { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) } else { copySelection(cut: true) }
    }

    func menuPaste() {
        if isEditingText { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) } else { paste() }
    }

    func menuSelectAll() {
        if isEditingText { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) } else { selectAll() }
    }

    func menuUndo() {
        if isEditingText { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) } else { stepBack() }
    }

    // MARK: - File

    static var patternTypes: [UTType] {
        [UTType(filenameExtension: "rle"), UTType(filenameExtension: "cells"), UTType.plainText].compactMap { $0 }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Open a pattern"
        panel.message = "Supported formats: RLE (.rle) and plaintext (.cells, .txt)"
        panel.allowedContentTypes = LifeModel.patternTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFile(url)
    }

    func loadFile(_ url: URL) {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        guard let text, let p = Pattern.parse(text) else {
            showToast("Could not read “\(url.lastPathComponent)”: unrecognized format")
            return
        }
        loadPattern(p, name: p.name ?? url.deletingPathExtension().lastPathComponent)
    }

    func saveFile() {
        guard let rect = selection ?? engine.boundingBox() else {
            showToast("Nothing to save: the world is empty")
            return
        }
        let p = engine.extract(rect: rect)
        let panel = NSSavePanel()
        panel.title = selection != nil ? "Save Selection as RLE" : "Save Pattern as RLE"
        panel.allowedContentTypes = [UTType(filenameExtension: "rle") ?? .plainText]
        panel.nameFieldStringValue = "pattern.rle"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try p.rleString(rule: rule).write(to: url, atomically: true, encoding: .utf8)
            showToast("Saved “\(url.lastPathComponent)” · \(p.population) cells")
        } catch {
            showToast("Save failed: \(error.localizedDescription)")
        }
    }

    func exportPNG() {
        let full = GridRect(x: 0, y: 0, width: engine.width, height: engine.height)
        let rect = selection ?? engine.boundingBox()?.expanded(by: 6).clamped(width: engine.width, height: engine.height) ?? full
        let pal = palette
        let exporter = CellRenderer()
        exporter.update(palette: pal, ageColoring: ageColoring, trails: trailLength >= 1)
        guard let img = exporter.image(of: engine, rect: rect) else { return }
        let scale = max(1, min(16, 4096 / max(rect.width, rect.height)))
        let w = rect.width * scale
        let h = rect.height * scale
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(pal.background.cgColor())
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.title = "Export Image"
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "genesis-gen\(engine.generation).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            showToast("Image exported (\(w)×\(h) px)")
        } catch {
            showToast("Export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - View

    func zoomIn() { canvas?.zoom(by: 1.4) }
    func zoomOut() { canvas?.zoom(by: 1 / 1.4) }
    func zoomToFit() { canvas?.zoomToFit(contentOnly: true) }
    func zoomToWorld() { canvas?.zoomToFit(contentOnly: false) }

    // MARK: - Notifications

    func showToast(_ message: String) {
        toastToken += 1
        let token = toastToken
        withAnimation(.spring(duration: 0.3)) { toast = message }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard let self, self.toastToken == token else { return }
            withAnimation(.easeOut(duration: 0.4)) { self.toast = nil }
        }
    }
}
