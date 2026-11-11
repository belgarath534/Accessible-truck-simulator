import XCTest
@testable import BeatCore

final class ChartTests: XCTestCase {
    func testChartsAreStableAndCallAndResponse() {
        for song in Song.all {
            for d in Difficulty.allCases {
                let chart = Chart(song: song, difficulty: d)
                XCTAssertEqual(chart, Chart(song: song, difficulty: d), "same chart every time")
                XCTAssertFalse(chart.notes.isEmpty)
                for note in chart.notes {
                    XCTAssertEqual(note.time - note.cueTime, song.barLength, accuracy: 1e-9)
                    XCTAssertGreaterThanOrEqual(note.cueTime, Double(Song.introBars) * song.barLength - 1e-9)
                    XCTAssertLessThan(note.time, Double(song.bars - Song.outroBars) * song.barLength)
                    // Notes land in response bars only (odd bars after the intro).
                    let bar = Int((note.time / song.barLength + 1e-6).rounded(.down))
                    XCTAssertEqual((bar - Song.introBars) % 2, 1)
                }
                XCTAssertEqual(chart.notes.map(\.time), chart.notes.map(\.time).sorted())
            }
        }
    }

    func testEasyStartsWithTapsAndHardHasMoreNotes() {
        let song = Song.all[0]
        let easy = Chart(song: song, difficulty: .easy), hard = Chart(song: song, difficulty: .hard)
        XCTAssertTrue(easy.notes.prefix(4).allSatisfy { $0.move == .tap })
        XCTAssertGreaterThan(hard.notes.count, easy.notes.count)
    }

    func testStableHashDoesNotChange() {
        XCTAssertEqual(SeededRandom.stableHash("abc"), 0xE71F_A219_0541_574B)
    }
}

final class JudgeTests: XCTestCase {
    let chart = Chart(song: Song.all[0], difficulty: .easy)

    func testPerfectGoodWrongAndMiss() {
        var judge = Judge(chart: chart)
        let n = chart.notes
        XCTAssertEqual(judge.input(n[0].move, at: n[0].time + 0.02)?.judgement, .perfect)
        XCTAssertEqual(judge.input(n[1].move, at: n[1].time - 0.1)?.judgement, .good)
        XCTAssertEqual(judge.combo, 2)
        let wrong: Move = n[2].move == .tap ? .left : .tap
        XCTAssertEqual(judge.input(wrong, at: n[2].time)?.judgement, .wrongMove)
        XCTAssertEqual(judge.combo, 0)
        XCTAssertEqual(judge.update(time: n[3].time + 0.3), [3])
        XCTAssertEqual(judge.results[3], .miss)
        XCTAssertNil(judge.input(.tap, at: n[3].time + 0.5), "nothing near: no penalty")
        XCTAssertEqual(judge.bestCombo, 2)
    }

    func testPerfectRunScoresSWithMultiplier() {
        var judge = Judge(chart: chart)
        for note in chart.notes { _ = judge.input(note.move, at: note.time) }
        XCTAssertTrue(judge.isFinished)
        XCTAssertEqual(judge.accuracy, 100)
        XCTAssertEqual(judge.grade, "S")
        XCTAssertGreaterThan(judge.score, 300 * chart.notes.count, "combo multiplier")
        XCTAssertTrue(judge.spokenResults.contains("grade S"))
    }
}

final class SynthTests: XCTestCase {
    func testRenderIsSongLengthAndNotSilentOrClipping() {
        let chart = Chart(song: Song.all[0], difficulty: .easy)
        let buffer = Synth(sampleRate: 22_050).render(chart)
        XCTAssertEqual(Double(buffer.frames) / 22_050, chart.song.duration + 1, accuracy: 0.01)
        XCTAssertGreaterThan(buffer.left.map(abs).max() ?? 0, 0.2)
        XCTAssertLessThanOrEqual(buffer.left.map(abs).max() ?? 2, 1)
    }

    func testLeftAndRightCuesArePanned() {
        let synth = Synth()
        XCTAssertLessThan(synth.cue(.left).pan, 0)
        XCTAssertGreaterThan(synth.cue(.right).pan, 0)
    }
}
