import Foundation

struct CellPoint: Hashable {
    var x: Int
    var y: Int
}

/// A rectangle of cells (integer coordinates, y pointing down).
struct GridRect: Hashable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Rectangle spanning both corners (inclusive).
    init(corner a: CellPoint, _ b: CellPoint) {
        x = min(a.x, b.x)
        y = min(a.y, b.y)
        width = abs(a.x - b.x) + 1
        height = abs(a.y - b.y) + 1
    }

    var maxX: Int { x + width }
    var maxY: Int { y + height }
    var isEmpty: Bool { width <= 0 || height <= 0 }
    var area: Int { max(0, width) * max(0, height) }

    func clamped(width w: Int, height h: Int) -> GridRect {
        let x0 = max(0, x), y0 = max(0, y)
        let x1 = min(w, maxX), y1 = min(h, maxY)
        return GridRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    func expanded(by d: Int) -> GridRect {
        GridRect(x: x - d, y: y - d, width: width + 2 * d, height: height + 2 * d)
    }
}

/// A finite set of live cells, normalized so the top-left corner is (0,0).
struct Pattern: Hashable {
    var width: Int
    var height: Int
    var cells: [CellPoint]
    var rule: Rule? = nil
    var name: String? = nil

    static let empty = Pattern(width: 0, height: 0, cells: [])

    var population: Int { cells.count }
    var isEmpty: Bool { cells.isEmpty }

    init(width: Int, height: Int, cells: [CellPoint], rule: Rule? = nil, name: String? = nil) {
        self.width = width
        self.height = height
        self.cells = cells
        self.rule = rule
        self.name = name
    }

    /// Builds a pattern, translating the points so the minimum is (0,0).
    init(normalizing points: [CellPoint], rule: Rule? = nil, name: String? = nil) {
        guard let minX = points.map({ $0.x }).min(),
              let minY = points.map({ $0.y }).min(),
              let maxX = points.map({ $0.x }).max(),
              let maxY = points.map({ $0.y }).max() else {
            self.init(width: 0, height: 0, cells: [], rule: rule, name: name)
            return
        }
        self.init(width: maxX - minX + 1,
                  height: maxY - minY + 1,
                  cells: points.map { CellPoint(x: $0.x - minX, y: $0.y - minY) },
                  rule: rule,
                  name: name)
    }

    // MARK: Transforms

    func rotatedClockwise() -> Pattern {
        Pattern(width: height, height: width,
                cells: cells.map { CellPoint(x: height - 1 - $0.y, y: $0.x) },
                rule: rule, name: name)
    }

    func flippedHorizontally() -> Pattern {
        Pattern(width: width, height: height,
                cells: cells.map { CellPoint(x: width - 1 - $0.x, y: $0.y) },
                rule: rule, name: name)
    }

    func flippedVertically() -> Pattern {
        Pattern(width: width, height: height,
                cells: cells.map { CellPoint(x: $0.x, y: height - 1 - $0.y) },
                rule: rule, name: name)
    }

    // MARK: Parsing

    /// Auto-detects RLE or plaintext (.cells).
    static func parse(_ text: String) -> Pattern? {
        let lines = normalizedLines(text)
        let content = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("!") && !$0.hasPrefix("#") }
        guard !content.isEmpty else { return nil }
        let plainChars: Set<Character> = [".", "O", "*"]
        if content.allSatisfy({ line in line.allSatisfy { plainChars.contains($0) } }) {
            return parsePlaintext(lines)
        }
        return parseRLE(text)
    }

    static func parsePlaintext(_ lines: [String]) -> Pattern? {
        var points: [CellPoint] = []
        var name: String? = nil
        var y = 0
        var started = false
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("!") {
                if line.hasPrefix("!Name:") {
                    let n = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { name = n }
                }
                continue
            }
            if line.isEmpty && !started { continue }
            started = true
            for (x, ch) in line.enumerated() where ch == "O" || ch == "*" {
                points.append(CellPoint(x: x, y: y))
            }
            y += 1
        }
        guard !points.isEmpty else { return nil }
        return Pattern(normalizing: points, name: name)
    }

    static func parseRLE(_ text: String) -> Pattern? {
        var rule: Rule? = nil
        var name: String? = nil
        var body = ""
        var sawHeader = false
        for raw in normalizedLines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                if line.hasPrefix("#N") {
                    let n = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { name = n }
                } else if line.hasPrefix("#r") {
                    rule = Rule(String(line.dropFirst(2)))
                }
                continue
            }
            if !sawHeader && line.hasPrefix("x") && line.contains("=") {
                sawHeader = true
                for field in line.split(separator: ",") {
                    let kv = field.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if kv.count == 2 && kv[0].lowercased() == "rule" {
                        rule = Rule(kv[1])
                    }
                }
                continue
            }
            body += line
            if line.contains("!") { break }
        }

        var points: [CellPoint] = []
        var x = 0
        var y = 0
        var count = 0
        loop: for ch in body {
            if ch.isASCII, let d = ch.wholeNumberValue {
                count = count * 10 + d
                continue
            }
            let n = max(count, 1)
            count = 0
            switch ch {
            case "b", ".":
                x += n
            case "$":
                y += n
                x = 0
            case "!":
                break loop
            default:
                if ch.isLetter {
                    for i in 0..<n { points.append(CellPoint(x: x + i, y: y)) }
                    x += n
                }
            }
        }
        guard !points.isEmpty else { return nil }
        return Pattern(normalizing: points, rule: rule, name: name)
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    // MARK: Writing

    func rleString(rule: Rule) -> String {
        guard width > 0, height > 0 else {
            return "x = 0, y = 0, rule = \(rule.notation)\n!\n"
        }
        var grid = [Bool](repeating: false, count: width * height)
        for c in cells where c.x >= 0 && c.y >= 0 && c.x < width && c.y < height {
            grid[c.y * width + c.x] = true
        }
        var tokens: [String] = []
        var pendingRows = 0
        for y in 0..<height {
            if y > 0 { pendingRows += 1 }
            var last = -1
            for x in 0..<width where grid[y * width + x] { last = x }
            if last < 0 { continue }
            if pendingRows > 0 {
                tokens.append(pendingRows == 1 ? "$" : "\(pendingRows)$")
                pendingRows = 0
            }
            var x = 0
            while x <= last {
                let v = grid[y * width + x]
                var n = 0
                while x <= last && grid[y * width + x] == v {
                    n += 1
                    x += 1
                }
                tokens.append((n == 1 ? "" : String(n)) + (v ? "o" : "b"))
            }
        }
        tokens.append("!")

        var out = ""
        if let name { out += "#N \(name)\n" }
        out += "#C Created with Genesis\n"
        out += "x = \(width), y = \(height), rule = \(rule.notation)\n"
        var line = ""
        for t in tokens {
            if line.count + t.count > 70 {
                out += line + "\n"
                line = ""
            }
            line += t
        }
        out += line + "\n"
        return out
    }
}
