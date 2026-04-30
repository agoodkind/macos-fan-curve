//
//  AgentSnapshot.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-24.
//  Copyright © 2026
//

import Foundation

struct AgentSnapshot: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let timestampEpoch: Double
    let helperReachable: Bool
    let curveActive: Bool
    let boostEnabled: Bool
    let governingTemperatureC: Double
    let committedTemperatureC: Double
    let rawPressureTemperatureC: Double?
    let cpuLoadPercent: Double
    let gpuLoadPercent: Double
    let effectiveCurvePercent: Double
    let rawBaselinePercent: Double
    let committedPercent: Double
    let controllerMode: AgentControllerMode
    let bandIndex: Int
    let holdRemainingSeconds: Double
    let assistFloorPercent: Double?
    let activeAssistKinds: [LoadAssistKind]
    let fans: [AgentFanSnapshot]

    init(
        timestamp: Date,
        helperReachable: Bool,
        curveActive: Bool,
        boostEnabled: Bool,
        governingTemperatureC: Double,
        committedTemperatureC: Double,
        rawPressureTemperatureC: Double?,
        cpuLoadPercent: Double,
        gpuLoadPercent: Double,
        effectiveCurvePercent: Double,
        rawBaselinePercent: Double,
        committedPercent: Double,
        controllerMode: AgentControllerMode,
        bandIndex: Int,
        holdRemainingSeconds: Double,
        assistFloorPercent: Double?,
        activeAssistKinds: [LoadAssistKind],
        fans: [AgentFanSnapshot]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.timestampEpoch = timestamp.timeIntervalSince1970
        self.helperReachable = helperReachable
        self.curveActive = curveActive
        self.boostEnabled = boostEnabled
        self.governingTemperatureC = governingTemperatureC
        self.committedTemperatureC = committedTemperatureC
        self.rawPressureTemperatureC = rawPressureTemperatureC
        self.cpuLoadPercent = cpuLoadPercent
        self.gpuLoadPercent = gpuLoadPercent
        self.effectiveCurvePercent = effectiveCurvePercent
        self.rawBaselinePercent = rawBaselinePercent
        self.committedPercent = committedPercent
        self.controllerMode = controllerMode
        self.bandIndex = bandIndex
        self.holdRemainingSeconds = holdRemainingSeconds
        self.assistFloorPercent = assistFloorPercent
        self.activeAssistKinds = activeAssistKinds
        self.fans = fans
    }

    var timestamp: Date { Date(timeIntervalSince1970: timestampEpoch) }
}
