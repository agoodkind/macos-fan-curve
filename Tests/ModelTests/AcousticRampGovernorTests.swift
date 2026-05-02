//
//  AcousticRampGovernorTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-30.
//  Copyright © 2026
//

import Nimble
import XCTest

@testable import FanCurveModels

final class AcousticRampGovernorTests: XCTestCase {
    private let governor = AcousticRampGovernor()

    func testDecisionLimitsNormalRiseByElapsedTime() {
        let decision = governor.decision(
            for: AcousticRampGovernor.Input(
                requestedRPM: 6_000,
                baselineRPM: 4_000,
                elapsedSeconds: 1,
                currentTemperatureC: 65,
                fastTrendCPerTick: 0,
                slowTrendCPerTick: 0,
                thermalDebt: 0))

        expect(decision.commandedRPM).to(beCloseTo(4_028, within: 0.1))
        expect(decision.limited) == true
        expect(decision.emergencyOverride) == false
    }

    func testDecisionUsesElapsedTimeForLongerRiseBudget() {
        let decision = governor.decision(
            for: AcousticRampGovernor.Input(
                requestedRPM: 6_000,
                baselineRPM: 4_000,
                elapsedSeconds: 10,
                currentTemperatureC: 65,
                fastTrendCPerTick: 0,
                slowTrendCPerTick: 0,
                thermalDebt: 0))

        expect(decision.commandedRPM).to(beCloseTo(4_280, within: 0.1))
        expect(decision.limited) == true
    }

    func testDecisionDoesNotStackImmediateTicks() {
        let decision = governor.decision(
            for: AcousticRampGovernor.Input(
                requestedRPM: 6_000,
                baselineRPM: 4_000,
                elapsedSeconds: 0,
                currentTemperatureC: 65,
                fastTrendCPerTick: 0,
                slowTrendCPerTick: 0,
                thermalDebt: 0))

        expect(decision.commandedRPM).to(beCloseTo(4_000, within: 0.1))
        expect(decision.limited) == true
    }

    func testDecisionRaisesRateForEmergencyTemperature() {
        let decision = governor.decision(
            for: AcousticRampGovernor.Input(
                requestedRPM: 6_000,
                baselineRPM: 4_000,
                elapsedSeconds: 1,
                currentTemperatureC: 92,
                fastTrendCPerTick: 0,
                slowTrendCPerTick: 0,
                thermalDebt: 0))

        expect(decision.commandedRPM).to(beCloseTo(4_360, within: 0.1))
        expect(decision.rateRPMPerSecond).to(beCloseTo(360, within: 0.1))
        expect(decision.emergencyOverride) == true
    }

    func testDecisionSlowsFallWhenThermalDebtIsHigh() {
        let decision = governor.decision(
            for: AcousticRampGovernor.Input(
                requestedRPM: 4_000,
                baselineRPM: 6_000,
                elapsedSeconds: 1,
                currentTemperatureC: 75,
                fastTrendCPerTick: 0,
                slowTrendCPerTick: 0,
                thermalDebt: 1))

        expect(decision.commandedRPM).to(beCloseTo(5_985, within: 0.1))
        expect(decision.rateRPMPerSecond).to(beCloseTo(15, within: 0.1))
        expect(decision.limited) == true
    }
}
