//
//  FanResponse.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-11.
//  Copyright © 2026
//

import AppLog
import Foundation

private let fanResponseLog = AppLog.make(category: "FanResponse")

struct FanResponse: Sendable, Equatable {
    static let defaultValue: Double = 0.5
    static let defaultInferFromGraph = true

    let value: Double

    init(value: Double) {
        self.value = Self.clampedValue(value)
    }

    static var balanced: FanResponse {
        FanResponse(value: defaultValue)
    }

    var manualMultiplier: FanResponseMultiplier {
        FanResponseMultiplier(Self.rampMultiplier(for: value))
    }

    var biasMultiplier: FanResponseMultiplier {
        FanResponseMultiplier(Self.biasMultiplier(for: value))
    }

    static func loadValue(defaults: UserDefaults) -> FanResponse {
        guard defaults.object(forKey: SharedConfigKeys.fanResponseValue) != nil else {
            return .balanced
        }
        return FanResponse(value: defaults.double(forKey: SharedConfigKeys.fanResponseValue))
    }

    static func loadInferFromGraph(defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: SharedConfigKeys.inferFanResponseFromGraph) != nil else {
            return defaultInferFromGraph
        }
        return defaults.bool(forKey: SharedConfigKeys.inferFanResponseFromGraph)
    }

    static func finalMultiplier(
        manualResponse: FanResponse,
        inferredResponse: FanResponse?,
        inferFromGraph: Bool
    ) -> FanResponseMultiplier {
        guard inferFromGraph, let inferredResponse else {
            return manualResponse.manualMultiplier
        }

        return FanResponseMultiplier(
            inferredResponse.manualMultiplier.rawValue * manualResponse.biasMultiplier.rawValue
        )
    }

    static func responseValue(forSlopePercentPerC slopePercentPerC: Double) -> FanResponse {
        let gentleSlopePercentPerC = 0.002
        let fastSlopePercentPerC = 0.03
        let normalized =
            (abs(slopePercentPerC) - gentleSlopePercentPerC)
            / (fastSlopePercentPerC - gentleSlopePercentPerC)
        return FanResponse(value: normalized)
    }

    private static func clampedValue(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    private static func rampMultiplier(for value: Double) -> Double {
        let clampedValue = clampedValue(value)
        if clampedValue <= defaultValue {
            let progress = clampedValue / defaultValue
            return 0.55 + progress * 0.45
        }

        let progress = (clampedValue - defaultValue) / defaultValue
        return 1.0 + progress * 0.6
    }

    private static func biasMultiplier(for value: Double) -> Double {
        let clampedValue = clampedValue(value)
        if clampedValue <= defaultValue {
            let progress = clampedValue / defaultValue
            return 0.75 + progress * 0.25
        }

        let progress = (clampedValue - defaultValue) / defaultValue
        return 1.0 + progress * 0.25
    }
}

struct FanResponseMultiplier: Sendable, Equatable {
    static let balanced = FanResponseMultiplier(1.0)

    let rawValue: Double

    init(_ rawValue: Double) {
        self.rawValue = max(0.45, min(1.8, rawValue))
    }
}
