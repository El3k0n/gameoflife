import Foundation

enum PatternCategory: String, CaseIterable, Identifiable {
    case spaceships
    case oscillators
    case stillLifes
    case guns
    case methuselahs
    case growth
    case otherRules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spaceships: return "Spaceships"
        case .oscillators: return "Oscillators"
        case .stillLifes: return "Still Lifes"
        case .guns: return "Guns"
        case .methuselahs: return "Methuselahs"
        case .growth: return "Infinite Growth"
        case .otherRules: return "Other Rules"
        }
    }

    var symbol: String {
        switch self {
        case .spaceships: return "paperplane"
        case .oscillators: return "waveform.path"
        case .stillLifes: return "square.grid.2x2"
        case .guns: return "scope"
        case .methuselahs: return "hourglass"
        case .growth: return "arrow.up.right.and.arrow.down.left"
        case .otherRules: return "function"
        }
    }
}

struct LibraryItem: Identifiable, Hashable {
    let id: String
    let name: String
    let category: PatternCategory
    let summary: String
    let pattern: Pattern

    init(_ id: String, _ name: String, _ category: PatternCategory, _ summary: String, rle: String, rule: String? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.summary = summary
        var p = Pattern.parseRLE(rle) ?? .empty
        if let rule { p.rule = Rule(rule) }
        p.name = name
        self.pattern = p
    }
}

/// Famous patterns (all verified by simulation).
enum PatternLibrary {
    static let items: [LibraryItem] = [
        // Spaceships
        LibraryItem("glider", "Glider", .spaceships,
                    "The smallest spaceship: 5 cells travelling diagonally at c/4. The hacker emblem.",
                    rle: "bo$2bo$3o!"),
        LibraryItem("lwss", "Lightweight spaceship (LWSS)", .spaceships,
                    "Travels orthogonally at c/2 with period 4.",
                    rle: "bo2bo$o$o3bo$4o!"),
        LibraryItem("mwss", "Middleweight spaceship (MWSS)", .spaceships,
                    "The LWSS's bigger sibling.",
                    rle: "3bo$bo3bo$o$o4bo$5o!"),
        LibraryItem("hwss", "Heavyweight spaceship (HWSS)", .spaceships,
                    "The largest member of the classic family.",
                    rle: "3b2o$bo4bo$o$o5bo$6o!"),
        LibraryItem("copperhead", "Copperhead", .spaceships,
                    "Discovered in 2016: a very slow orthogonal spaceship, speed c/10.",
                    rle: "b2o2b2o$3b2o$3b2o$obo2bobo$o6bo2$o6bo$b2o2b2o$2b4o2$3b2o$3b2o!"),
        LibraryItem("loafer", "Loafer", .spaceships,
                    "A surprisingly small c/7 spaceship discovered in 2013.",
                    rle: "b2o2bob2o$o2bo2b2o$bobo$2bo$8bo$6b3o$5bo$6bo$7b2o!"),

        // Oscillators
        LibraryItem("blinker", "Blinker", .oscillators,
                    "The most common oscillator: three cells in a row, period 2.",
                    rle: "3o!"),
        LibraryItem("toad", "Toad", .oscillators,
                    "A period-2 oscillator made of two staggered rows.",
                    rle: "b3o$3o!"),
        LibraryItem("beacon", "Beacon", .oscillators,
                    "Two blocks that touch and separate: period 2.",
                    rle: "2o$2o$2b2o$2b2o!"),
        LibraryItem("pulsar", "Pulsar", .oscillators,
                    "The most famous period-3 oscillator, with fourfold symmetry.",
                    rle: "2b3o3b3o2$o4bobo4bo$o4bobo4bo$o4bobo4bo$2b3o3b3o2$2b3o3b3o$o4bobo4bo$o4bobo4bo$o4bobo4bo2$2b3o3b3o!"),
        LibraryItem("pentadecathlon", "Pentadecathlon", .oscillators,
                    "A period-15 oscillator that evolves from a simple row of 10 cells.",
                    rle: "2bo4bo$2ob4ob2o$2bo4bo!"),
        LibraryItem("figure8", "Figure eight", .oscillators,
                    "Two 3×3 squares dancing with period 8.",
                    rle: "3o$3o$3o$3b3o$3b3o$3b3o!"),
        LibraryItem("kok", "Kok's galaxy", .oscillators,
                    "Four arms spinning like a spiral galaxy: period 8.",
                    rle: "6ob2o$6ob2o$7b2o$2o5b2o$2o5b2o$2o5b2o$2o$2ob6o$2ob6o!"),
        LibraryItem("queenbee", "Queen bee shuttle", .oscillators,
                    "A queen bee bouncing between two blocks: period 30.",
                    rle: "9bo$7bobo$6bobo$2o3bo2bo11b2o$2o4bobo11b2o$7bobo$9bo!"),

        // Still lifes
        LibraryItem("block", "Block", .stillLifes, "The simplest and most common still life.", rle: "2o$2o!"),
        LibraryItem("beehive", "Beehive", .stillLifes, "The second most frequent still life in random soups.", rle: "b2o$o2bo$b2o!"),
        LibraryItem("loaf", "Loaf", .stillLifes, "A 7-cell still life.", rle: "b2o$o2bo$bobo$2bo!"),
        LibraryItem("boat", "Boat", .stillLifes, "The only 5-cell still life.", rle: "2o$obo$bo!"),
        LibraryItem("tub", "Tub", .stillLifes, "Four cells arranged in a diamond.", rle: "bo$obo$bo!"),
        LibraryItem("ship", "Ship", .stillLifes, "A stretched, symmetric boat.", rle: "2o$obo$b2o!"),
        LibraryItem("pond", "Pond", .stillLifes, "A ring of 8 cells.", rle: "b2o$o2bo$o2bo$b2o!"),

        // Guns
        LibraryItem("gosper", "Gosper glider gun", .guns,
                    "The first pattern with infinite growth (1970): fires a glider every 30 generations.",
                    rle: "24bo$22bobo$12b2o6b2o12b2o$11bo3bo4b2o12b2o$2o8bo5bo3b2o$2o8bo3bob2o4bobo$10bo5bo7bo$11bo3bo$12b2o!"),

        // Methuselahs
        LibraryItem("rpentomino", "R-pentomino", .methuselahs,
                    "Just 5 cells, yet it takes 1103 generations to settle, releasing 6 gliders.",
                    rle: "b2o$2o$bo!"),
        LibraryItem("diehard", "Diehard", .methuselahs,
                    "Vanishes completely after exactly 130 generations.",
                    rle: "6bo$2o$bo3b3o!"),
        LibraryItem("acorn", "Acorn", .methuselahs,
                    "7 cells that grow for 5206 generations, ending with 633 cells.",
                    rle: "bo$3bo$2o2b3o!"),
        LibraryItem("rabbits", "Rabbits", .methuselahs,
                    "9 cells that keep evolving for 17331 generations.",
                    rle: "o3b3o$3o2bo$bo!"),
        LibraryItem("pi", "Pi-heptomino", .methuselahs,
                    "Seven cells shaped like π: settles after 173 generations.",
                    rle: "3o$obo$obo!"),
        LibraryItem("bheptomino", "B-heptomino", .methuselahs,
                    "Settles in 148 generations; a key building block of many mechanisms.",
                    rle: "ob2o$3o$bo!"),
        LibraryItem("thunderbird", "Thunderbird", .methuselahs,
                    "An upside-down T that explodes and settles after 243 generations.",
                    rle: "3o2$bo$bo$bo!"),

        // Infinite growth
        LibraryItem("switch10", "Switch engine (10 cells)", .growth,
                    "The smallest infinitely growing pattern: it lays blocks forever.",
                    rle: "6bo$4bob2o$4bobo$4bo$2bo$obo!"),
        LibraryItem("growth5x5", "5×5 infinite growth", .growth,
                    "The only infinitely growing pattern that fits in a 5×5 square.",
                    rle: "3obo$o$3b2o$b2obo$obobo!"),
        LibraryItem("line", "One-line infinite growth", .growth,
                    "A single row of cells that grows forever.",
                    rle: "8ob5o3b3o6b7ob5o!"),

        // Other rules
        LibraryItem("replicator", "Replicator (HighLife)", .otherRules,
                    "In HighLife this pattern copies itself forever, drawing a Sierpiński triangle.",
                    rle: "2b3o$bo2bo$o3bo$o2bo$3o!", rule: "B36/S23"),
        LibraryItem("seedsburst", "Explosion (Seeds)", .otherRules,
                    "In Seeds a plain 2×2 block sets off a fractal explosion.",
                    rle: "2o$2o!", rule: "B2/S"),
        LibraryItem("gnarl", "Seed (Gnarl)", .otherRules,
                    "In Gnarl (B1/S1) a single cell produces an expanding tangle.",
                    rle: "o!", rule: "B1/S1"),
        LibraryItem("replicator1357", "Copies (Replicator)", .otherRules,
                    "Under the Replicator rule every shape is copied over and over, forever.",
                    rle: "b2o$2o$bo!", rule: "B1357/S1357"),
    ]

    static func items(in category: PatternCategory) -> [LibraryItem] {
        items.filter { $0.category == category }
    }
}
