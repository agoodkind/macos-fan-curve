//
//  AgentController+ActiveTickContext.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-24.
//  Copyright © 2026, all rights reserved.
//

import Foundation

private struct ActiveTickTemperatureState {
    let now: Date
    let fastTemperature: Double
    let slowTemperature: Double
    let fastTrend: Double
    let slowTrend: Double
    let pressureTemperature: Double
}

private struct ActiveTickCurveState {
    let boost: Bool
    let baseCurvePercent: Double
    let fanResponseMultiplier: FanResponseMultiplier
    let fanResponseInferred: Bool
    let curvePercent: Double
}

extension AgentController {
    func makeActiveTickContext(
        from telemetry: AgentControllerTickTypes.TickTelemetry
    ) -> AgentControllerTickTypes.ActiveTickContext? {
        let temperatureState = updateActiveTickTemperatureState(from: telemetry)
        let curveState = activeTickCurveState(
            at: temperatureState.pressureTemperature
        )
        let assistState = resolveAssistState(
            boost: curveState.boost,
            curvePercent: curveState.curvePercent,
            cpuLoad: telemetry.cpuLoad,
            gpuLoad: telemetry.gpuLoad
        )
        let conditionedDemand = conditionedThermalDemand(
            rawPercent: curveState.boost ? 1.0 : assistState.rawBaselinePercent,
            rawTemperatureC: temperatureState.pressureTemperature,
            now: temperatureState.now
        )

        return AgentControllerTickTypes.ActiveTickContext(
            telemetry: telemetry,
            now: temperatureState.now,
            fastTemp: temperatureState.fastTemperature,
            slowTemp: temperatureState.slowTemperature,
            fastTrend: temperatureState.fastTrend,
            slowTrend: temperatureState.slowTrend,
            boost: curveState.boost,
            pressureTemperature: temperatureState.pressureTemperature,
            baseCurvePercent: curveState.baseCurvePercent,
            fanResponseMultiplier: curveState.fanResponseMultiplier,
            fanResponseInferred: curveState.fanResponseInferred,
            rawBaselinePercent: assistState.rawBaselinePercent,
            assistFloorPercent: assistState.assistFloorPercent,
            assistAppliedKinds: assistState.assistAppliedKinds,
            demandSource: assistState.demandSource,
            conditionedDemand: conditionedDemand
        )
    }

    private func updateActiveTickTemperatureState(
        from telemetry: AgentControllerTickTypes.TickTelemetry
    ) -> ActiveTickTemperatureState {
        let now = Date()
        let fastTemperature = smoothedTemperature(
            rawTemp: telemetry.maxCPUTemp,
            current: filteredTemperatureFast,
            previous: &previousFastTemperature,
            alpha: fastTemperatureEMAAlpha
        )
        filteredTemperatureFast = fastTemperature

        let slowTemperature = smoothedTemperature(
            rawTemp: telemetry.maxCPUTemp,
            current: filteredTemperatureSlow,
            previous: &previousSlowTemperature,
            alpha: slowTemperatureEMAAlpha
        )
        filteredTemperatureSlow = slowTemperature

        let pressureTemperature = thermalPressureTemperature(
            fastTemperatureC: fastTemperature,
            slowTemperatureC: slowTemperature
        )

        return ActiveTickTemperatureState(
            now: now,
            fastTemperature: fastTemperature,
            slowTemperature: slowTemperature,
            fastTrend: previousFastTemperature.map { fastTemperature - $0 } ?? 0,
            slowTrend: previousSlowTemperature.map { slowTemperature - $0 } ?? 0,
            pressureTemperature: pressureTemperature
        )
    }

    private func activeTickCurveState(at pressureTemperature: Double) -> ActiveTickCurveState {
        let boost = sharedConfig.loadBoostEnabled()
        let points = sharedConfig.loadCurve()
        let mode = sharedConfig.loadInterpolationMode()
        let baseCurvePercent = CurveInterpolation.evaluate(
            at: pressureTemperature,
            points: points,
            mode: mode
        )
        let fanResponseInferred = sharedConfig.loadInferFanResponseFromGraph()
        let inferredFanResponse = CurveInterpolation.localResponse(
            at: pressureTemperature,
            points: points,
            mode: mode
        )
        let fanResponseMultiplier = FanResponse.finalMultiplier(
            manualResponse: sharedConfig.loadFanResponse(),
            inferredResponse: inferredFanResponse,
            inferFromGraph: fanResponseInferred
        )

        return ActiveTickCurveState(
            boost: boost,
            baseCurvePercent: baseCurvePercent,
            fanResponseMultiplier: fanResponseMultiplier,
            fanResponseInferred: fanResponseInferred,
            curvePercent: boost ? 1.0 : baseCurvePercent
        )
    }
}
