import XCTest
@testable import SimCore

final class DetourTests: XCTestCase {
    private func detourJob() -> DeliveryJob {
        var rng = SeededRandom(seed: 7)
        for _ in 0..<500 {
            for town in WorldMap.standard.towns {
                let job = JobBoard.makeJob(using: &rng, from: town.id)
                if job.closedRoad != nil { return job }
            }
        }
        XCTFail("no detour jobs")
        return JobBoard.makeJob(using: &rng, from: "millbrook")
    }

    func testSomeJobsHaveDetoursAndTheirDistanceIncludesIt() throws {
        var rng = SeededRandom(seed: 3)
        let jobs = (0..<300).map { _ in JobBoard.makeJob(using: &rng, from: "millbrook") }
        let share = Double(jobs.filter { $0.closedRoad != nil }.count) / Double(jobs.count)
        XCTAssertGreaterThan(share, 0.05)
        XCTAssertLessThan(share, 0.3)

        let job = detourJob()
        let map = WorldMap.standard
        let closed = try XCTUnwrap(job.closedRoad)
        let normal = try XCTUnwrap(map.route(from: job.origin!, to: job.destination!))
        XCTAssertTrue(normal.contains { $0.index == closed }, "the closed road was on the usual way")
        XCTAssertGreaterThan(job.distance, map.length(of: normal))
        XCTAssertTrue(Phrases(units: .metric).job(job).contains("is closed"))
        XCTAssertTrue(Phrases(units: .metric).jobIntro(job).contains("detour"))
    }

    func testTheGPSGoesAroundAndTheClosedRoadIsBlocked() throws {
        let job = detourJob()
        let closed = try XCTUnwrap(job.closedRoad)
        let nav = try XCTUnwrap(Navigator(map: .standard, origin: job.origin!, destination: job.destination!, closed: [closed]))
        XCTAssertNotEqual(nav.edge.index, closed)
        XCTAssertFalse(nav.route.contains { $0.index == closed })
        XCTAssertEqual(nav.remaining(at: 0)!, job.distance, accuracy: 1)
        // Whatever you signal at each junction, you never end up on the closed road.
        for signal in [SignalState.off, .on(.left), .on(.right)] {
            let n = Navigator(map: .standard, origin: job.origin!, destination: job.destination!, closed: [closed])!
            for _ in 0..<6 {
                XCTAssertFalse(n.junctionChoices.contains { $0.edge.index == closed && n.junctionChoices.count > 1 })
                n.takeJunction(signal: signal)
                XCTAssertNotEqual(n.edge.index, closed)
            }
        }
    }

    func testOldSavedJobsHaveNoDetour() throws {
        var rng = SeededRandom(seed: 11)
        let job = JobBoard.makeJob(using: &rng, from: "millbrook")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as! [String: Any]
        json.removeValue(forKey: "closedRoad")
        let old = try JSONDecoder().decode(DeliveryJob.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.closedRoad)
    }
}
