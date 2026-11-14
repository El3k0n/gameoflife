import XCTest
@testable import Genesis

final class RuleTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(Rule("B3/S23"), .conway)
        XCTAssertEqual(Rule("b3s23"), .conway)
        XCTAssertEqual(Rule("23/3"), .conway)
        XCTAssertEqual(Rule("S23/B3"), .conway)
        XCTAssertEqual(Rule("B3/S23:T100,100"), .conway)
        XCTAssertEqual(Rule("B36/S23")?.notation, "B36/S23")
        XCTAssertEqual(Rule("B2/S")?.notation, "B2/S")
        XCTAssertNil(Rule("ciao"))
        XCTAssertNil(Rule("B9/S23"))
    }

    func testPresetsAreValid() {
        for preset in RulePreset.all {
            XCTAssertEqual(Rule(preset.rule.notation), preset.rule, preset.name)
        }
    }
}

final class PatternTests: XCTestCase {
    func testRLERoundTrip() {
        for item in PatternLibrary.items {
            XCTAssertFalse(item.pattern.isEmpty, item.name)
            let text = item.pattern.rleString(rule: .conway)
            let parsed = Pattern.parse(text)
            XCTAssertEqual(Set(parsed?.cells ?? []), Set(item.pattern.cells), item.name)
        }
    }

    func testPlaintext() {
        let p = Pattern.parse("!Name: Glider\n.O.\n..O\nOOO\n")
        XCTAssertEqual(p?.population, 5)
        XCTAssertEqual(p?.name, "Glider")
    }

    func testRLEHeaderRule() {
        let p = Pattern.parse("#N Test\nx = 3, y = 1, rule = B36/S23\n3o!")
        XCTAssertEqual(p?.rule?.notation, "B36/S23")
        XCTAssertEqual(p?.population, 3)
    }

    func testRotation() {
        let glider = Pattern.parseRLE("bo$2bo$3o!")!
        var p = glider
        for _ in 0..<4 { p = p.rotatedClockwise() }
        XCTAssertEqual(Set(p.cells), Set(glider.cells))
    }
}

final class EngineTests: XCTestCase {
    private func engine(with rle: String, size: Int = 64, rule: Rule = .conway) -> LifeEngine {
        let e = LifeEngine(width: size, height: size, rule: rule)
        let p = Pattern.parseRLE(rle)!
        e.place(p, atX: size / 2 - p.width / 2, y: size / 2 - p.height / 2)
        return e
    }

    func testBlinkerOscillates() {
        let e = engine(with: "3o!")
        XCTAssertTrue(e.isAlive(31, 32))
        e.step()
        XCTAssertEqual(e.population, 3)
        XCTAssertTrue(e.isAlive(32, 31))
        XCTAssertTrue(e.isAlive(32, 33))
        e.step()
        XCTAssertEqual(e.cyclePeriod, 2)
    }

    func testBlockIsStable() {
        let e = engine(with: "2o$2o!")
        e.step()
        XCTAssertEqual(e.population, 4)
        XCTAssertEqual(e.cyclePeriod, 1)
    }

    func testDiehardDiesAt130() {
        let e = engine(with: "6bo$2o$bo3b3o!", size: 128)
        for _ in 0..<129 { e.step() }
        XCTAssertGreaterThan(e.population, 0)
        e.step()
        XCTAssertEqual(e.population, 0)
    }

    func testGliderWrapsAroundTorus() {
        let e = engine(with: "bo$2bo$3o!", size: 32)
        let start = Set(e.extract(rect: GridRect(x: 0, y: 0, width: 32, height: 32)).cells)
        for _ in 0..<(32 * 4) { e.step() }
        let end = Set(e.extract(rect: GridRect(x: 0, y: 0, width: 32, height: 32)).cells)
        XCTAssertEqual(start, end)
        XCTAssertEqual(e.population, 5)
    }

    func testBoundedWorldKillsAtEdge() {
        let e = LifeEngine(width: 16, height: 16)
        e.topology = .bounded
        e.place(Pattern.parseRLE("bo$2bo$3o!")!, atX: 10, y: 10)
        for _ in 0..<40 { e.step() }
        // The glider crashes into the edge and turns into a block.
        XCTAssertEqual(e.population, 4)
    }

    func testStepBackRestoresState() {
        let e = engine(with: "b2o$2o$bo!")
        let before = Set(e.extract(rect: GridRect(x: 0, y: 0, width: 64, height: 64)).cells)
        for _ in 0..<10 { e.step() }
        for _ in 0..<10 { XCTAssertTrue(e.stepBack()) }
        let after = Set(e.extract(rect: GridRect(x: 0, y: 0, width: 64, height: 64)).cells)
        XCTAssertEqual(before, after)
        XCTAssertEqual(e.generation, 0)
    }

    func testRPentominoMatchesKnownPopulation() {
        // On a large enough torus the R-pentomino reaches 116 cells at generation 1103.
        let e = engine(with: "b2o$2o$bo!", size: 512)
        for _ in 0..<1103 { e.step() }
        XCTAssertEqual(e.population, 116)
    }

    func testHighLifeReplicator() {
        let e = engine(with: "2b3o$bo2bo$o3bo$o2bo$3o!", rule: Rule("B36/S23")!)
        for _ in 0..<12 { e.step() }
        XCTAssertEqual(e.population, 24)
    }

    func testResizeKeepsContentCentered() {
        let e = engine(with: "2o$2o!", size: 64)
        e.resize(width: 128, height: 128)
        XCTAssertEqual(e.population, 4)
        XCTAssertEqual(e.boundingBox(), GridRect(x: 63, y: 63, width: 2, height: 2))
    }

    func testRandomSymmetry() {
        let e = LifeEngine(width: 64, height: 64)
        e.randomize(in: GridRect(x: 0, y: 0, width: 64, height: 64), density: 0.4, symmetry: .quad, seed: 42)
        for y in 0..<64 {
            for x in 0..<64 {
                XCTAssertEqual(e.isAlive(x, y), e.isAlive(63 - x, y))
                XCTAssertEqual(e.isAlive(x, y), e.isAlive(x, 63 - y))
            }
        }
    }
}
