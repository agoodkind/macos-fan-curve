//
//  LiveMarkerPresentation.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-01.
//  Copyright © 2026
//

import Foundation

struct LiveMarkerDemandPresentation {
    static func presentPercent(
        currentPercent: Double,
        proposedPercent: Double,
        alpha: Double,
        maximumStep: Double
    ) -> Double {
        guard proposedPercent < currentPercent else { return proposedPercent }

        let delta = proposedPercent - currentPercent
        let easedStep = delta * max(0, min(1, alpha))
        let clampedStep = max(-maximumStep, min(maximumStep, easedStep))
        return currentPercent + clampedStep
    }
}

struct LiveMarkerValues: Sendable, Equatable {
    var fanTemperatureC: Double
    var fanPercent: Double
    var demandTemperatureC: Double
    var demandPercent: Double
    var demandBasePercent: Double

    static let zero = LiveMarkerValues(
        fanTemperatureC: 0,
        fanPercent: 0,
        demandTemperatureC: 0,
        demandPercent: 0,
        demandBasePercent: 0)
}

struct LiveMarkerTarget: Sendable, Equatable {
    var values: LiveMarkerValues
    var generation: Generation

    struct Generation: Sendable, Equatable {
        var snapshotEpoch: Double
        var curveActive: Bool
        var boostEnabled: Bool
        var fanSignature: String
        var rpmRangeMin: Float
        var rpmRangeMax: Float
    }
}

struct LiveMarkerTargetFactory {
    static func make(
        snapshotEpoch: Double,
        curveActive: Bool,
        boostEnabled: Bool,
        fanTemperatureC: Double? = nil,
        governingTemperatureC: Double,
        committedTemperatureC: Double,
        rawPressureTemperatureC: Double?,
        thermalDemandTemperatureC: Double?,
        baseCurvePercent: Double?,
        thermalDemandPercent: Double?,
        committedPercent: Double,
        rawBaselinePercent: Double,
        fans: [AgentFanSnapshot],
        rpmRange: (min: Float, max: Float),
        previewPercent: Double
    ) -> LiveMarkerTarget? {
        let liveTemperature =
            thermalDemandTemperatureC
            ?? rawPressureTemperatureC
            ?? (committedTemperatureC > 0 ? committedTemperatureC : governingTemperatureC)
        guard liveTemperature > 0 else { return nil }

        let fanPercent = actualFanPercent(fans: fans, rpmRange: rpmRange)
            ?? (curveActive ? committedPercent : previewPercent)
        let fanTemperature = fanTemperatureC ?? liveTemperature
        let demandPercent = curveActive
            ? clampedPercent(thermalDemandPercent ?? rawBaselinePercent)
            : previewPercent
        let basePercent = clampedPercent(baseCurvePercent ?? previewPercent)

        return LiveMarkerTarget(
            values: LiveMarkerValues(
                fanTemperatureC: fanTemperature,
                fanPercent: clampedPercent(fanPercent),
                demandTemperatureC: liveTemperature,
                demandPercent: demandPercent,
                demandBasePercent: basePercent),
            generation: LiveMarkerTarget.Generation(
                snapshotEpoch: snapshotEpoch,
                curveActive: curveActive,
                boostEnabled: boostEnabled,
                fanSignature: fanSignature(fans),
                rpmRangeMin: rpmRange.min,
                rpmRangeMax: rpmRange.max))
    }

    private static func actualFanPercent(
        fans: [AgentFanSnapshot],
        rpmRange: (min: Float, max: Float)
    ) -> Double? {
        guard rpmRange.max > rpmRange.min else { return nil }
        let percents = fans.compactMap { fan -> Double? in
            guard fan.actualRPM >= 0 else { return nil }
            let percent = Double((fan.actualRPM - rpmRange.min) / (rpmRange.max - rpmRange.min))
            return clampedPercent(percent)
        }
        guard !percents.isEmpty else { return nil }
        return percents.reduce(0, +) / Double(percents.count)
    }

    private static func fanSignature(_ fans: [AgentFanSnapshot]) -> String {
        fans.map { "\($0.index):\(Int($0.minRPM)):\(Int($0.maxRPM))" }.joined(separator: "|")
    }

    private static func clampedPercent(_ percent: Double) -> Double {
        max(0, min(1, percent))
    }
}
