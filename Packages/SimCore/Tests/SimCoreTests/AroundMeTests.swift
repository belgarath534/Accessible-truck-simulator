import XCTest
@testable import SimCore

final class AroundMeTests: XCTestCase {
    func testDescribesTrafficHillsWeighStationsAndWeather() {
        var road = Road(segments: [.straight(5_000)], loops: false)
        road.weighStations = [2_000]
        road.hills = [Hill(start: 0, end: 1_000, grade: 0.05)]
        let s = DrivingSession(road: road, seed: 1)
        s.truck.position = 500
        s.weather = .rain
        s.traffic = [TrafficVehicle(id: 1, kind: .truck, oncoming: false, lane: 0, position: 620, speed: 20),
                     TrafficVehicle(id: 2, kind: .car, oncoming: true, lane: -3.5, position: 900, speed: 25)]
        let text = Phrases(units: .metric).surroundings(s.surroundings)
        XCTAssertTrue(text.contains("A truck ahead in your lane"), text)
        XCTAssertTrue(text.contains("Oncoming car"), text)
        XCTAssertTrue(text.contains("uphill, 5 percent"), text)
        XCTAssertTrue(text.contains("Weigh station in 1.5 kilometers"), text)
        XCTAssertTrue(text.contains("raining"), text)
        XCTAssertEqual(s.perform(.speakAroundMe), [.aroundMe(s.surroundings)])
    }

    func testEmptyRoad() {
        let s = DrivingSession(road: Road(segments: [.straight(5_000)], loops: false), seed: 1)
        XCTAssertEqual(Phrases(units: .metric).surroundings(s.surroundings), "Your lane is clear ahead.")
        XCTAssertEqual(GestureMap.action(for: .swipe(fingers: 3, direction: .down)), .speakAroundMe)
    }
}
