import XCTest
@testable import FlightCore
final class VoiceLinesTests: XCTestCase {
    func testLinesAndExport() throws {
        XCTAssertEqual(Set(VoiceLines.all.map(\.id)).count, VoiceLines.all.count, "unique ids")
        XCTAssertEqual(VoiceLines.line(for: Phrases.event(.liftoff)!)?.id, "liftoff")
        XCTAssertEqual(VoiceLines.line(for: Tutorial.instruction(.flapsDown))?.speaker, .instructor)
        guard let path = ProcessInfo.processInfo.environment["DUMP_PATH"] else { return }
        let rows = VoiceLines.all.map { ["id": $0.id, "speaker": $0.speaker.rawValue, "text": $0.text] }
        try JSONSerialization.data(withJSONObject: rows).write(to: URL(fileURLWithPath: path))
    }
}
