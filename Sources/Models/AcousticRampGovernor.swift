//
//  AcousticRampGovernor.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-30.
//  Copyright © 2026
//

import Foundation

struct AcousticRampGovernor: Sendable {
    struct Policy: Sendable {
        let quietRiseRPMPerSecond: Float
        let warmRiseRPMPerSecond: Float
        let hotRiseRPMPerSecond: Float
        let quietFallRPMPerSecond: Float
        let thermalDebtMinimumFallRPMPerSecond: Float
        let warmTemperatureC: Double
        let hotTemperatureC: Double
        let risingFastTrendCPerTick: Double
        let risingSlowTrendCPerTick: Double
        let minimumSnapRPMDelta: Float

        static let fanCurveDefault = Policy(
            quietRiseRPMPerSecond: 16,
            warmRiseRPMPerSecond: 24,
            hotRiseRPMPerSecond: 38,
            quietFallRPMPerSecond: 18,
            thermalDebtMinimumFallRPMPerSecond: 8,
            warmTemperatureC: 80,
            hotTemperatureC: 86,
            risingFastTrendCPerTick: 0.14,
            risingSlowTrendCPerTick: 0.06,
            minimumSnapRPMDelta: 35)
    }

    struct Input: Sendable {
        let requestedRPM: Float
        let baselineRPM: Float
        let elapsedSeconds: TimeInterval
        let currentTemperatureC: Double
        let fastTrendCPerTick: Double
        let slowTrendCPerTick: Double
        let thermalDebt: Double
    }

    struct Decision: Sendable, Equatable {
        let requestedRPM: Float
        let commandedRPM: Float
        let baselineRPM: Float
        let elapsedSeconds: TimeInterval
        let rateRPMPerSecond: Float
        let limited: Bool
    }

    let policy: Policy

    init(policy: Policy = .fanCurveDefault) {
        self.policy = policy
    }

    func decision(for input: Input) -> Decision {
        let delta = input.requestedRPM - input.baselineRPM
        guard delta != 0 else {
            return Decision(
                requestedRPM: input.requestedRPM,
                commandedRPM: input.requestedRPM,
                baselineRPM: input.baselineRPM,
                elapsedSeconds: normalizedElapsedSeconds(input.elapsedSeconds),
                rateRPMPerSecond: 0,
                limited: false)
        }

        let elapsedSeconds = normalizedElapsedSeconds(input.elapsedSeconds)
        let rateRPMPerSecond = selectedRateRPMPerSecond(input: input, delta: delta)
        let allowedDelta = rateRPMPerSecond * Float(elapsedSeconds)
        let candidateRPM: Float
        if delta > 0 {
            candidateRPM = input.baselineRPM + min(delta, allowedDelta)
        } else {
            candidateRPM = input.baselineRPM + max(delta, -allowedDelta)
        }
        let commandedRPM = snappedCommandRPM(
            requestedRPM: input.requestedRPM,
            candidateRPM: max(0, candidateRPM),
            delta: delta)

        return Decision(
            requestedRPM: input.requestedRPM,
            commandedRPM: commandedRPM,
            baselineRPM: input.baselineRPM,
            elapsedSeconds: elapsedSeconds,
            rateRPMPerSecond: rateRPMPerSecond,
            limited: commandedRPM != input.requestedRPM)
    }

    private func selectedRateRPMPerSecond(input: Input, delta: Float) -> Float {
        if delta > 0 {
            return selectedRiseRateRPMPerSecond(input: input)
        }

        let thermalDebt = max(0, min(1, input.thermalDebt))
        return policy.quietFallRPMPerSecond
            - Float(thermalDebt) * (policy.quietFallRPMPerSecond - policy.thermalDebtMinimumFallRPMPerSecond)
    }

    private func selectedRiseRateRPMPerSecond(input: Input) -> Float {
        let thermalDebt = max(0, min(1, input.thermalDebt))
        let thermalDebtRate =
            policy.quietRiseRPMPerSecond
            + Float(thermalDebt) * (policy.hotRiseRPMPerSecond - policy.quietRiseRPMPerSecond)
        let isTemperatureRising =
            input.fastTrendCPerTick >= policy.risingFastTrendCPerTick
            || input.slowTrendCPerTick >= policy.risingSlowTrendCPerTick
        let trendRate: Float
        if isTemperatureRising {
            trendRate = policy.warmRiseRPMPerSecond
        } else {
            trendRate = policy.quietRiseRPMPerSecond
        }
        let temperatureRate: Float
        if input.currentTemperatureC >= policy.hotTemperatureC {
            temperatureRate = policy.hotRiseRPMPerSecond
        } else if input.currentTemperatureC >= policy.warmTemperatureC {
            temperatureRate = policy.warmRiseRPMPerSecond
        } else {
            temperatureRate = policy.quietRiseRPMPerSecond
        }

        return max(thermalDebtRate, trendRate, temperatureRate)
    }

    private func snappedCommandRPM(
        requestedRPM: Float,
        candidateRPM: Float,
        delta: Float
    ) -> Float {
        guard abs(delta) > policy.minimumSnapRPMDelta else {
            return requestedRPM
        }
        if delta > 0 {
            return min(requestedRPM, candidateRPM)
        }
        return max(requestedRPM, candidateRPM)
    }

    private func normalizedElapsedSeconds(_ elapsedSeconds: TimeInterval) -> TimeInterval {
        max(0, min(10, elapsedSeconds))
    }
}
