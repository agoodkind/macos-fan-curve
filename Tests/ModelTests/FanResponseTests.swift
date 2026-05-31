//
//  FanResponseTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-11.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

@testable import FanCurveModels

final class FanResponseTests: XCTestCase {
    func testValueClampsToUnitRange() {
        expect(FanResponse(value: -1).value) == 0
        expect(FanResponse(value: 2).value) == 1
    }

    func testDefaultsPreserveBalancedManualResponseAndInferenceOn() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FanResponseTests.defaults"))
        defaults.removePersistentDomain(forName: "FanResponseTests.defaults")

        let response = FanResponse.loadValue(defaults: defaults)
        let inferFromGraph = FanResponse.loadInferFromGraph(defaults: defaults)

        expect(response.value).to(beCloseTo(0.5, within: 0.001))
        expect(response.manualMultiplier.rawValue).to(beCloseTo(1.0, within: 0.001))
        expect(inferFromGraph) == true
    }

    func testStoredResponseAndInferenceSettingsAreLoaded() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FanResponseTests.stored"))
        defaults.removePersistentDomain(forName: "FanResponseTests.stored")
        defaults.set(0.25, forKey: SharedConfigKeys.fanResponseValue)
        defaults.set(false, forKey: SharedConfigKeys.inferFanResponseFromGraph)

        let response = FanResponse.loadValue(defaults: defaults)
        let inferFromGraph = FanResponse.loadInferFromGraph(defaults: defaults)

        expect(response.value).to(beCloseTo(0.25, within: 0.001))
        expect(inferFromGraph) == false
    }

    func testFinalMultiplierUsesManualResponseWhenInferenceIsOff() {
        let response = FanResponse.finalMultiplier(
            manualResponse: FanResponse(value: 1),
            inferredResponse: FanResponse(value: 0),
            inferFromGraph: false
        )

        expect(response.rawValue).to(beCloseTo(1.6, within: 0.001))
    }

    func testFinalMultiplierCombinesInferredResponseWithBiasWhenInferenceIsOn() {
        let response = FanResponse.finalMultiplier(
            manualResponse: FanResponse(value: 1),
            inferredResponse: FanResponse(value: 0.5),
            inferFromGraph: true
        )

        expect(response.rawValue).to(beCloseTo(1.25, within: 0.001))
    }
}
