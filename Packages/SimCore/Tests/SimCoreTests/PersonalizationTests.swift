import XCTest
@testable import SimCore

final class PersonalizationTests: XCTestCase {
    func testBuyingAndSwitchingHorns() {
        var c = CareerState(seed: 1)
        XCTAssertEqual(c.horn, .air)
        XCTAssertTrue(c.ownsHorn(.air))
        XCTAssertEqual(c.buyHorn(.train), .notEnoughMoney(short: Horn.train.price - c.money))
        c.money = 5_000
        XCTAssertEqual(c.buyHorn(.train), .bought)
        XCTAssertEqual(c.money, 5_000 - Horn.train.price)
        XCTAssertEqual(c.horn, .train)
        XCTAssertEqual(c.buyHorn(.train), .alreadyOwned)
        XCTAssertFalse(c.selectHorn(.ship))
        XCTAssertTrue(c.selectHorn(.air))
        XCTAssertEqual(c.horn, .air)
        XCTAssertTrue(c.checkAchievements().contains(.newHorn))
    }

    func testHornFiles() {
        XCTAssertEqual(Horn.air.soundFile, "horn")
        XCTAssertEqual(Horn.train.soundFile, "horn_train")
        XCTAssertEqual(Horn.allCases.filter { $0.price == 0 }, [.air])
    }

    func testNames() {
        var c = CareerState(seed: 1)
        XCTAssertEqual(c.companyDisplayName, "Your Trucking Company")
        c.setCompanyName("  Leo's Hauling\n ")
        XCTAssertEqual(c.companyName, "Leo's Hauling")
        c.setNickname("Big Bertha", for: .starter)
        XCTAssertEqual(c.displayName(for: .starter), "Big Bertha, your \(TruckSpec.starter.name)")
        c.setNickname("   ", for: .starter)
        XCTAssertNil(c.nickname(for: .starter))
        c.setCompanyName(String(repeating: "x", count: 80))
        XCTAssertEqual(c.companyName?.count, CareerState.maxNameLength)
    }

    func testNamesAndHornsAreSavedAndOldSavesLoad() throws {
        var c = CareerState(seed: 2)
        c.money = 9_000
        c.buyHorn(.ship)
        c.setCompanyName("Night Owl Freight")
        c.setNickname("Rusty", for: .starter)
        let back = try JSONDecoder().decode(CareerState.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.horn, .ship)
        XCTAssertEqual(back.companyName, "Night Owl Freight")
        XCTAssertEqual(back.nickname(for: .starter), "Rusty")

        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CareerState(seed: 3))) as! [String: Any]
        for k in ["companyName", "truckNames", "ownedHorns", "selectedHorn"] { json.removeValue(forKey: k) }
        let old = try JSONDecoder().decode(CareerState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.horn, .air)
        XCTAssertNil(old.companyName)
    }

    func testAchievementPointsStayWithinGameCenterLimit() {
        XCTAssertLessThanOrEqual(Achievement.allCases.reduce(0) { $0 + $1.points }, 1_000)
    }
}
