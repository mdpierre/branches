import XCTest
@testable import BranchesKit

final class JSONLTailReaderTests: XCTestCase {
    func testReadsOnlyNewCompleteLines() {
        let home = TempHome()
        let file = home.write("a.jsonl", "{\"n\":1}\n{\"n\":2}\n")
        let reader = JSONLTailReader(url: file)
        XCTAssertEqual(reader.readNewLines().count, 2)
        XCTAssertEqual(reader.readNewLines().count, 0)

        home.append("a.jsonl", "{\"n\":3}\n")
        XCTAssertEqual(strings(reader.readNewLines()), ["{\"n\":3}"])
    }

    func testHoldsBackPartialLineUntilCompleted() {
        let home = TempHome()
        let file = home.write("a.jsonl", "{\"n\":1}\n{\"n\":")
        let reader = JSONLTailReader(url: file)
        XCTAssertEqual(strings(reader.readNewLines()), ["{\"n\":1}"])

        home.append("a.jsonl", "2}\n")
        XCTAssertEqual(strings(reader.readNewLines()), ["{\"n\":2}"])
    }

    func testTruncationResetsToStart() {
        let home = TempHome()
        let file = home.write("a.jsonl", "{\"n\":1}\n{\"n\":2}\n{\"n\":3}\n")
        let reader = JSONLTailReader(url: file)
        _ = reader.readNewLines()

        home.write("a.jsonl", "{\"x\":1}\n")
        XCTAssertEqual(strings(reader.readNewLines()), ["{\"x\":1}"])
    }

    func testInitialTailSkipsTheCutLine() {
        let home = TempHome()
        let body = (1...100).map { "{\"n\":\($0)}\n" }.joined()
        let file = home.write("a.jsonl", body)
        let reader = JSONLTailReader(url: file)
        let lines = strings(reader.readNewLines(initialTail: 30))
        XCTAssertEqual(lines.last, "{\"n\":100}")
        XCTAssertTrue(lines.allSatisfy { $0.hasPrefix("{") && $0.hasSuffix("}") }, "no half lines: \(lines)")
        XCTAssertLessThan(lines.count, 5)
    }

    func testSkipsBlankLinesAndHandlesCRLF() {
        let home = TempHome()
        let file = home.write("a.jsonl", "{\"n\":1}\r\n\n  \n{\"n\":2}\n")
        XCTAssertEqual(JSONLTailReader(url: file).readNewLines().count, 2)
    }

    func testFirstLine() {
        let home = TempHome()
        let file = home.write("a.jsonl", "{\"meta\":true}\n{\"n\":1}\n")
        XCTAssertEqual(JSONLTailReader.firstLine(of: file).map { String(decoding: $0, as: UTF8.self) }, "{\"meta\":true}")
    }

    private func strings(_ lines: [Data]) -> [String] {
        lines.map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
