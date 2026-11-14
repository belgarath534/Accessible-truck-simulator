import XCTest
@testable import SimCore

final class RoadTrainTests: XCTestCase {
    func testNewTrucksAreInTheGarage() {
        let ids = TruckSpec.catalog.map(\.id)
        XCTAssertTrue(ids.contains("road_train"))
        XCTAssertTrue(ids.contains("silver_arrow"))
        XCTAssertEqual(TruckSpec.withID("road_train").trailers, 2)
        XCTAssertEqual(TruckSpec.withID("silver_arrow").trailers, 1)
        XCTAssertLessThan(TruckSpec.silverArrow.fuelEfficiency, TruckSpec.starter.fuelEfficiency)
    }

    func testDoubleLoadAndPay() {
        let job = DeliveryJob(cargo: Cargo.catalog[0], distance: 10_000, pay: 1_000, timeLimit: 3_600)
        let s = DrivingSession(spec: .roadTrain, goal: job.goal, cargoMassKg: job.cargo.massKg)
        XCTAssertEqual(s.cargoMassKg, job.cargo.massKg * 2)

        var c = CareerState()
        c.ownedTrucks.append("road_train")
        c.selectedTruck = "road_train"
        let pay = c.deliveryPayout(job, summary: TripSummary(goalName: "x", stats: TripStats(), stopError: 0))
        XCTAssertTrue(pay.lines.contains { $0.label == "Second trailer" && $0.amount == 600 })
        c.selectedTruck = TruckSpec.starter.id
        XCTAssertFalse(c.deliveryPayout(job, summary: TripSummary(goalName: "x", stats: TripStats(), stopError: 0))
                        .lines.contains { $0.label == "Second trailer" })
    }

    func testARoadTrainIsLongerToPass() {
        XCTAssertEqual(TruckSpec.roadTrain.length, 26)
        XCTAssertEqual(TruckSpec.starter.length, 16)
    }
}
