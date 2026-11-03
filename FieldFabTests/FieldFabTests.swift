//
//  FieldFabTests.swift
//  FieldFabTests
//
//  Created by Robert Sale on 9/4/20.
//  Copyright © 2020 Robert Sale. All rights reserved.
//

import XCTest
@testable import FieldFab

class FieldFabTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testTopDownTransitionWithMatchingHeights() throws {
        var fitting = FabFitting.new(shape: .rectTransition, areaID: nil)
        fitting.inletWidth = 24
        fitting.inletHeight = 18
        fitting.outletWidth = 18
        fitting.outletHeight = 18
        fitting.verticalAlignment = .topDown
        fitting.verticalValue = 2
        XCTAssertEqual(fitting.offsetY, -2, accuracy: 0.00001)
        XCTAssertEqual(fitting.topChange, 2, accuracy: 0.00001)
        XCTAssertEqual(fitting.bottomChange, -2, accuracy: 0.00001)
    }

    func testTopDownTransitionWithHeightReduction() throws {
        var fitting = FabFitting.new(shape: .rectTransition, areaID: nil)
        fitting.inletHeight = 18
        fitting.outletHeight = 12
        fitting.verticalAlignment = .topDown
        fitting.verticalValue = 2
        XCTAssertEqual(fitting.offsetY, 1, accuracy: 0.00001)
        XCTAssertEqual(fitting.topChange, 2, accuracy: 0.00001)
        XCTAssertEqual(fitting.bottomChange, 4, accuracy: 0.00001)
    }

    func testAreaInsulationOverrides() throws {
        var area = FabArea(name: "Second Floor", rectangularLiner: .one,
                           roundInsulation: .doubleWall, roundThickness: .one)
        var fitting = FabFitting.new(shape: .roundReducer, areaID: area.id)
        XCTAssertEqual(fitting.effectiveRoundInsulation(in: area), .doubleWall)
        fitting.roundInsulationOverride = .spiracoustic
        fitting.roundThicknessOverride = .two
        area.roundInsulation = .none
        area.roundThickness = .half
        XCTAssertEqual(fitting.effectiveRoundInsulation(in: area), .spiracoustic)
        XCTAssertEqual(fitting.effectiveRoundThickness(in: area), .two)
    }

    func testJobPersistence() throws {
        let area = FabArea(name: "Roof", roundInsulation: .spiracoustic,
                           roundThickness: .oneHalf)
        let fitting = FabFitting.new(shape: .roundStraight, areaID: area.id)
        let job = FabJob(name: "Test Job", areas: [area], fittings: [fitting])
        let restored = try JSONDecoder().decode(FabJob.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(restored, job)
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
