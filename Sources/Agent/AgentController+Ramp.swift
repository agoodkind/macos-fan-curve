//
//  AgentController+Ramp.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026
//

import Foundation

struct RampCommandState {
    let rpm: Float
    let timestamp: Date
}

struct RampCommandInput {
    let command: FanCommand
    let index: UInt
    let currentFan: FanInfo
    let currentTemperatureC: Double
    let fastTrendCPerTick: Double
    let slowTrendCPerTick: Double
    let fanResponseMultiplier: FanResponseMultiplier
    let now: Date
}

extension AgentController {
    func rampGovernedCommand(input: RampCommandInput) -> FanCommand {
        switch input.command {
        case .auto:
            rampStateByFan.removeValue(forKey: input.index)
            return .auto
        case .setRPM(let requestedRPM):
            let baseline = commandBaselineRPM(
                fanIndex: input.index,
                requestedRPM: requestedRPM,
                currentFan: input.currentFan
            )
            let previousTimestamp = rampStateByFan[input.index]?.timestamp ?? input.now
            let decision = acousticRampGovernor.decision(
                for: AcousticRampGovernor.Input(
                    requestedRPM: requestedRPM,
                    baselineRPM: baseline,
                    elapsedSeconds: input.now.timeIntervalSince(previousTimestamp),
                    currentTemperatureC: input.currentTemperatureC,
                    fastTrendCPerTick: input.fastTrendCPerTick,
                    slowTrendCPerTick: input.slowTrendCPerTick,
                    thermalDebt: thermalDebt
                ),
                policy: acousticRampGovernor.policy.scalingRPMRates(
                    by: input.fanResponseMultiplier
                )
            )
            rampStateByFan[input.index] = RampCommandState(rpm: decision.commandedRPM, timestamp: input.now)
            logRampDecisionIfNeeded(
                fanIndex: input.index,
                decision: decision,
                currentFan: input.currentFan,
                currentTemperatureC: input.currentTemperatureC,
                fanResponseMultiplier: input.fanResponseMultiplier
            )
            logCommandChangeIfNeeded(
                fanIndex: input.index,
                requestedRPM: requestedRPM,
                commandedRPM: decision.commandedRPM,
                currentFan: input.currentFan,
                currentTemperatureC: input.currentTemperatureC
            )
            return .setRPM(decision.commandedRPM)
        }
    }

    func commandBaselineRPM(
        fanIndex: UInt,
        requestedRPM: Float,
        currentFan: FanInfo
    ) -> Float {
        if let previous = rampStateByFan[fanIndex] {
            return previous.rpm
        }

        let observedRPM = currentFan.actualRPM > 0 ? currentFan.actualRPM : currentFan.targetRPM
        guard currentFan.targetRPM > 0 else { return observedRPM }
        if requestedRPM < currentFan.targetRPM {
            return min(currentFan.targetRPM, observedRPM)
        }
        return max(currentFan.targetRPM, observedRPM)
    }

    func logCommandChangeIfNeeded(
        fanIndex: UInt,
        requestedRPM: Float,
        commandedRPM: Float,
        currentFan: FanInfo,
        currentTemperatureC: Double
    ) {
        guard currentFan.maxRPM > currentFan.minRPM else { return }
        let commandedPercent = Double((commandedRPM - currentFan.minRPM) / (currentFan.maxRPM - currentFan.minRPM))
        let previousPercent = lastCommandLogPercentByFan[fanIndex]
        guard previousPercent == nil || abs((previousPercent ?? 0) - commandedPercent) >= minimumCommandPercentDelta
        else {
            return
        }
        lastCommandLogPercentByFan[fanIndex] = commandedPercent
        agentControllerLog.info(
            "agent.fan.command fan=\(fanIndex, privacy: .public) requestedRPM=\(Int(requestedRPM), privacy: .public) commandedRPM=\(Int(commandedRPM), privacy: .public) actualRPM=\(Int(currentFan.actualRPM), privacy: .public) tempC=\(Int(currentTemperatureC), privacy: .public) mode=\(controllerMode.rawValue, privacy: .public)"
        )
    }

    func logRampDecisionIfNeeded(
        fanIndex: UInt,
        decision: AcousticRampGovernor.Decision,
        currentFan: FanInfo,
        currentTemperatureC: Double,
        fanResponseMultiplier: FanResponseMultiplier
    ) {
        guard decision.limited else { return }
        agentControllerLog.info(
            "agent.fan.ramp_governor fan=\(fanIndex, privacy: .public) requestedRPM=\(Int(decision.requestedRPM), privacy: .public) commandedRPM=\(Int(decision.commandedRPM), privacy: .public) baselineRPM=\(Int(decision.baselineRPM), privacy: .public) actualRPM=\(Int(currentFan.actualRPM), privacy: .public) elapsedMs=\(Int(decision.elapsedSeconds * 1_000), privacy: .public) rateRPMPerSecond=\(Int(decision.rateRPMPerSecond), privacy: .public) responseMultiplier=\(Int(fanResponseMultiplier.rawValue * 100), privacy: .public)% tempC=\(Int(currentTemperatureC), privacy: .public) debt=\(Int(thermalDebt * 100), privacy: .public)% mode=\(controllerMode.rawValue, privacy: .public)"
        )
    }
}
