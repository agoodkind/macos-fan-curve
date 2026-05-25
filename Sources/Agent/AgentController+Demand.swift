//
//  AgentController+Demand.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026
//

import Foundation

extension AgentController {
    func bandControlledState(
        input: AgentControllerDemandTypes.BandControlInput
    ) -> AgentControllerDemandTypes.RuntimeBandState {
        let fastTrend = previousFastTemperature.map { input.fastTemperatureC - $0 } ?? 0
        let slowTrend = previousSlowTemperature.map { input.slowTemperatureC - $0 } ?? 0
        let baselinePercent = max(0, min(1, input.rawBaselinePercent))
        let committedPercent = max(0, min(1, input.conditionedDemandPercent))
        let observedPercent = input.observedFanPercent ?? committedPercent

        if observedPercent < committedPercent - 0.006 {
            controllerMode = .rampingUp
        } else if observedPercent > committedPercent + 0.006 {
            controllerMode = .rampingDown
        } else {
            controllerMode = .holding
        }

        updateThermalDebt(
            input: AgentControllerDemandTypes.ThermalDebtInput(
                rawTemperatureC: input.rawTemperatureC,
                fastTemperatureC: input.fastTemperatureC,
                slowTemperatureC: input.slowTemperatureC,
                fastTrend: fastTrend,
                slowTrend: slowTrend,
                cpuLoad: input.cpuLoad,
                rawBaselinePercent: input.rawBaselinePercent,
                committedPercent: committedPercent,
                steppedUp: observedPercent < committedPercent
            )
        )

        return AgentControllerDemandTypes.RuntimeBandState(
            committedPercent: committedPercent,
            commandedTargetTemperatureC: input.conditionedDemandTemperatureC,
            bandIndex: bandIndex(for: committedPercent),
            committedTemperatureC: input.slowTemperatureC,
            baseCurvePercent: input.baseCurvePercent,
            rawBaselinePercent: baselinePercent,
            semanticDemandPercent: baselinePercent,
            thermalDemandSource: input.demandSource,
            semanticDemandTemperatureC: input.semanticDemandTemperatureC,
            mode: controllerMode,
            holdRemainingSeconds: 0
        )
    }

    func observedCurvePercent(fans: [FanInfo]) -> Double? {
        let percents = fans.compactMap { fan -> Double? in
            guard fan.maxRPM > fan.minRPM, fan.actualRPM > 0 else { return nil }
            let percent = Double((fan.actualRPM - fan.minRPM) / (fan.maxRPM - fan.minRPM))
            return max(0, min(1, percent))
        }
        guard !percents.isEmpty else { return nil }
        return percents.reduce(0, +) / Double(percents.count)
    }

    func bandIndex(for percent: Double) -> Int {
        let clamped = max(0, min(1, percent))
        guard clamped > 0 else { return 0 }
        let bands = Int((1.0 / runtimeBandSize).rounded())
        return min(bands, Int(ceil(clamped / runtimeBandSize)))
    }

    func thermalPressureTemperature(fastTemperatureC: Double, slowTemperatureC: Double) -> Double {
        let fastTrend = previousFastTemperature.map { fastTemperatureC - $0 } ?? 0
        let trendLead = max(0, min(maximumThermalLeadC, fastTrend * thermalLeadSeconds))
        let ledTemperature = fastTemperatureC + trendLead
        return max(slowTemperatureC, ledTemperature)
    }

    func conditionedThermalDemand(
        rawPercent: Double,
        rawTemperatureC: Double,
        now: Date
    ) -> (percent: Double, temperatureC: Double) {
        let targetPercent = max(0, min(1, rawPercent))
        guard
            let currentPercent = conditionedDemandPercent,
            let currentTemperature = conditionedDemandTemperatureC,
            let lastTime = lastDemandConditioningTime
        else {
            conditionedDemandPercent = targetPercent
            conditionedDemandPercentVelocity = 0
            conditionedDemandTemperatureC = rawTemperatureC
            conditionedDemandTemperatureVelocityC = 0
            lastDemandConditioningTime = now
            return (targetPercent, rawTemperatureC)
        }

        let dt = max(0.001, min(5.0, now.timeIntervalSince(lastTime)))
        let maxPercentVelocity =
            targetPercent >= currentPercent
            ? demandNormalRiseVelocityPerSecond
            : demandNormalFallVelocityPerSecond
        let nextPercent = accelerationLimitedStep(
            input: AgentControllerDemandTypes.AccelerationStepInput(
                current: currentPercent,
                target: targetPercent,
                velocity: conditionedDemandPercentVelocity,
                maxVelocity: maxPercentVelocity,
                maxAcceleration: demandNormalAccelerationPerSecond,
                elapsedSeconds: dt
            )
        )

        let maxTemperatureVelocity =
            rawTemperatureC >= currentTemperature
            ? demandTemperatureRiseVelocityCPerSecond
            : demandTemperatureFallVelocityCPerSecond
        let nextTemperature = accelerationLimitedStep(
            input: AgentControllerDemandTypes.AccelerationStepInput(
                current: currentTemperature,
                target: rawTemperatureC,
                velocity: conditionedDemandTemperatureVelocityC,
                maxVelocity: maxTemperatureVelocity,
                maxAcceleration: demandTemperatureAccelerationCPerSecond,
                elapsedSeconds: dt
            )
        )

        conditionedDemandPercent = nextPercent.value
        conditionedDemandPercentVelocity = nextPercent.velocity
        conditionedDemandTemperatureC = nextTemperature.value
        conditionedDemandTemperatureVelocityC = nextTemperature.velocity
        lastDemandConditioningTime = now
        return (nextPercent.value, nextTemperature.value)
    }

    func accelerationLimitedStep(
        input: AgentControllerDemandTypes.AccelerationStepInput
    ) -> (value: Double, velocity: Double) {
        let delta = input.target - input.current
        guard delta != 0, input.elapsedSeconds > 0 else {
            return (input.target, 0)
        }

        let direction = delta > 0 ? 1.0 : -1.0
        let clampedMaxVelocity = max(0, input.maxVelocity)
        let clampedAcceleration = max(0, input.maxAcceleration)
        let stoppingVelocity = sqrt(2 * clampedAcceleration * abs(delta))
        let desiredVelocity = direction * min(clampedMaxVelocity, stoppingVelocity)
        let nextVelocity = limitedStep(
            current: input.velocity,
            target: desiredVelocity,
            maximumDelta: clampedAcceleration * input.elapsedSeconds
        )
        let nextValue = input.current + nextVelocity * input.elapsedSeconds

        let reachedTarget =
            (input.target - nextValue).sign != delta.sign
            || abs(input.target - nextValue) < 0.0001
        if reachedTarget {
            return (input.target, 0)
        }
        return (nextValue, nextVelocity)
    }

    func limitedStep(current: Double, target: Double, maximumDelta: Double) -> Double {
        let delta = target - current
        guard abs(delta) > maximumDelta else { return target }
        return current + maximumDelta * (delta > 0 ? 1 : -1)
    }

    func updateThermalDebt(input: AgentControllerDemandTypes.ThermalDebtInput) {
        let comfortOverTemp = max(0, input.slowTemperatureC - 58.0) / 22.0
        let risePressure = max(0, input.fastTemperatureC - input.slowTemperatureC - 0.25) / 3.0
        let fastTrendPressure = max(0, input.fastTrend - 0.04) * 2.8
        let sustainedLoadPressure = max(0, input.cpuLoad - 45.0) / 55.0 * 0.35
        let bandEscalationPressure = input.steppedUp ? 0.06 : 0.0

        let stableCooling =
            input.fastTrend <= 0.01
            && input.slowTrend <= -0.02
            && input.rawBaselinePercent <= input.committedPercent + 0.001
        let coolingPressure = stableCooling ? 1.0 : 0.0
        let lowLoadPressure = input.cpuLoad < 25.0 ? 0.4 : 0.0
        let coolTempPressure =
            input.slowTemperatureC < 52.0
                && input.rawTemperatureC < 55.0 ? 0.35 : 0.0

        let heatContribution =
            comfortOverTemp
            + risePressure
            + fastTrendPressure
            + sustainedLoadPressure
            + bandEscalationPressure
        let coolingContribution = coolingPressure + lowLoadPressure + coolTempPressure

        thermalDebt = max(
            0,
            min(
                1,
                thermalDebt
                    + thermalDebtRiseRatePerTick * heatContribution
                    - thermalDebtFallRatePerTick * coolingContribution
            )
        )
    }
}
