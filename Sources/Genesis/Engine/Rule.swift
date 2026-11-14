import Foundation

/// A "Life-like" rule in B/S notation (birth / survival) on the Moore neighborhood.
struct Rule: Hashable, Codable {
    /// Bit n set ⇒ a dead cell with n neighbors is born.
    var birth: UInt16
    /// Bit n set ⇒ a live cell with n neighbors survives.
    var survive: UInt16

    init(birth: UInt16, survive: UInt16) {
        self.birth = birth & 0x1FF
        self.survive = survive & 0x1FF
    }

    init(birth: [Int], survive: [Int]) {
        var b: UInt16 = 0
        var s: UInt16 = 0
        for n in birth where (0...8).contains(n) { b |= 1 << UInt16(n) }
        for n in survive where (0...8).contains(n) { s |= 1 << UInt16(n) }
        self.init(birth: b, survive: s)
    }

    /// Accepts "B3/S23", "b3s23", "S23/B3" and the legacy "23/3" (S/B) form.
    /// Golly topology suffixes (":T100,100") are ignored.
    init?(_ raw: String) {
        let head = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? raw
        let s = head.uppercased().filter { !$0.isWhitespace }
        guard !s.isEmpty else { return nil }
        var b: UInt16 = 0
        var sv: UInt16 = 0
        if s.contains("B") || s.contains("S") {
            var mode: Character? = nil
            for ch in s {
                switch ch {
                case "B", "S":
                    mode = ch
                case "/", "_", ",":
                    continue
                default:
                    guard ch.isASCII, let d = ch.wholeNumberValue, d <= 8, let m = mode else { return nil }
                    if m == "B" { b |= 1 << UInt16(d) } else { sv |= 1 << UInt16(d) }
                }
            }
        } else {
            let parts = s.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            for ch in parts[0] {
                guard ch.isASCII, let d = ch.wholeNumberValue, d <= 8 else { return nil }
                sv |= 1 << UInt16(d)
            }
            for ch in parts[1] {
                guard ch.isASCII, let d = ch.wholeNumberValue, d <= 8 else { return nil }
                b |= 1 << UInt16(d)
            }
        }
        self.init(birth: b, survive: sv)
    }

    func births(_ n: Int) -> Bool { birth & (UInt16(1) << UInt16(n)) != 0 }
    func survives(_ n: Int) -> Bool { survive & (UInt16(1) << UInt16(n)) != 0 }

    func togglingBirth(_ n: Int) -> Rule { Rule(birth: birth ^ (UInt16(1) << UInt16(n)), survive: survive) }
    func togglingSurvive(_ n: Int) -> Rule { Rule(birth: birth, survive: survive ^ (UInt16(1) << UInt16(n))) }

    var notation: String { "B" + Rule.digits(birth) + "/S" + Rule.digits(survive) }

    private static func digits(_ mask: UInt16) -> String {
        (0...8).filter { mask & (UInt16(1) << UInt16($0)) != 0 }.map { String($0) }.joined()
    }

    /// The rule's name if it is one of the presets.
    var presetName: String? { RulePreset.all.first { $0.rule == self }?.name }

    static let conway = Rule(birth: [3], survive: [2, 3])

    /// Generates a random rule, slightly biased towards "lively" rules.
    static func random() -> Rule {
        var b: UInt16 = 0
        var s: UInt16 = 0
        for n in 1...8 where Double.random(in: 0..<1) < (n <= 4 ? 0.35 : 0.22) { b |= UInt16(1) << UInt16(n) }
        for n in 0...8 where Double.random(in: 0..<1) < (n >= 2 && n <= 5 ? 0.5 : 0.25) { s |= UInt16(1) << UInt16(n) }
        if b & 0b0001_1100 == 0 { b |= UInt16(1) << UInt16(Int.random(in: 2...4)) }
        return Rule(birth: b, survive: s)
    }
}

struct RulePreset: Identifiable, Hashable {
    let name: String
    let rule: Rule
    let summary: String
    var id: String { rule.notation }

    init(_ name: String, _ notation: String, _ summary: String) {
        self.name = name
        self.rule = Rule(notation) ?? .conway
        self.summary = summary
    }

    static let all: [RulePreset] = [
        RulePreset("Conway's Life", "B3/S23", "John Conway's classic rule (1970): gliders, oscillators and orderly chaos."),
        RulePreset("HighLife", "B36/S23", "Like Life, but cells are also born with 6 neighbors: home of a famous replicator."),
        RulePreset("Day & Night", "B3678/S34678", "Symmetric under on/off reversal: islands of cells behave like their negatives."),
        RulePreset("Seeds", "B2/S", "No cell ever survives: chaotic, fractal explosions."),
        RulePreset("Life without Death", "B3/S012345678", "Cells never die: ladder-like growth and crystalline structures."),
        RulePreset("Maze", "B3/S12345", "Grows corridors and mazes that slowly settle down."),
        RulePreset("Mazectric", "B3/S1234", "A Maze variant with longer, straighter corridors."),
        RulePreset("Replicator", "B1357/S1357", "Every pattern gets copied over and over: Sierpiński-style fractals."),
        RulePreset("2×2", "B36/S125", "The world breaks into 2×2 blocks with their own dynamics."),
        RulePreset("Diamoeba", "B35678/S5678", "Large diamond-shaped amoebas that grow or shrink."),
        RulePreset("Morley (Move)", "B368/S245", "Rich in spaceships and small moving objects."),
        RulePreset("Anneal", "B4678/S35678", "Regions separate like cooling metals."),
        RulePreset("Coral", "B3/S45678", "Slow growth of coral-like structures."),
        RulePreset("Amoeba", "B357/S1358", "Chaotic blobs with ragged edges."),
        RulePreset("Stains", "B3678/S235678", "Stains that spread out and then stabilize."),
        RulePreset("Walled Cities", "B45678/S2345", "Cities with thick walls and busy interiors."),
        RulePreset("Gnarl", "B1/S1", "A single cell grows into an exploding tangle."),
        RulePreset("Long Life", "B345/S5", "Oscillators with extremely long periods."),
        RulePreset("Serviettes", "B234/S", "Expanding symmetric, napkin-like motifs."),
    ]
}
