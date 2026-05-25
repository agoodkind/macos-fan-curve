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

        expect(decision.commandedRPM).to(beCloseTo(4_016, within: 0.1))
        expect(decision.limited) == true
    }

    func testBalancedResponsePreservesCurrentRampDecision() {
        let input = AcousticRampGovernor.Input(
            requestedRPM: 6_000,
            baselineRPM: 4_000,
            elapsedSeconds: 1,
            currentTemperatureC: 65,
            fastTrendCPerTick: 0,
            slowTrendCPerTick: 0,
            thermalDebt: 0)
        let defaultDecision = governor.decision(for: input)
        let balancedPolicy = governor.policy.scalingRPMRates(
            by: FanResponse(value: 0.5).manualMultiplier
        )
        let balancedDecision = governor.decision(for: input, policy: balancedPolicy)

        expect(balancedDecision.commandedRPM).to(
            beCloseTo(defaultDecision.commandedRPM, within: 0.1))
        expect(balancedDecision.rateRPMPerSecond)
            .to(beCloseTo(defaultDecision.rateRPMPerSecond, within: 0.1))
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

        expect(decision.commandedRPM).to(beCloseTo(4_160, within: 0.1))
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

    func testDecisionUsesHotRateAtHighTemperature() {
        let decision = governor.decision(
            for: AcousticRampGovernor.Input(
                requestedRPM: 6_000,
                baselineRPM: 4_000,
                elapsedSeconds: 1,
                currentTemperatureC: 92,
                fastTrendCPerTick: 0,
                slowTrendCPerTick: 0,
                thermalDebt: 0))

        expect(decision.commandedRPM).to(beCloseTo(4_038, within: 0.1))
        expect(decision.rateRPMPerSecond).to(beCloseTo(38, within: 0.1))
        expect(decision.limited) == true
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

        expect(decision.commandedRPM).to(beCloseTo(5_992, within: 0.1))
        expect(decision.rateRPMPerSecond).to(beCloseTo(8, within: 0.1))
        expect(decision.limited) == true
    }
}
