//
//  FanCurveUITestState.swift
//  FanCurveUITests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

private enum FanCurveUITestFixtureConstants {
  static let sensorTemperatureC = 64.0
  static let actualRPM: Float = 2_400
  static let targetRPM: Float = 2_600
  static let minimumRPM: Float = 1_200
  static let maximumRPM: Float = 5_800
  static let cpuLoadPercent = 42.0
  static let gpuLoadPercent = 18.0
  static let ownershipPriority = 50
}

// MARK: - FanCurveUITestState

struct FanCurveUITestState {
  let services: TestServiceState
  let hardware: TestHardwareState
  let xpcFault: TestXPCFault

  static func make(
    backgroundAgent: TestManagedServiceStatus = .enabled,
    helper: TestManagedServiceStatus = .enabled,
    serviceOperation: TestOperationDirective = .succeed,
    helperReachable: Bool = true,
    telemetryStale: Bool = false,
    ownershipPreempted: Bool = false,
    hardwareOperation: TestOperationDirective = .succeed,
    sensorTemperatures: [TestSensorTemperature] = [
      TestSensorTemperature(
        name: "TC0P",
        temperatureC: FanCurveUITestFixtureConstants.sensorTemperatureC
      )
    ],
    fanReadings: [TestFanReading] = [
      TestFanReading(
        fanIndex: 0,
        name: "Left Fan",
        actualRPM: FanCurveUITestFixtureConstants.actualRPM,
        targetRPM: FanCurveUITestFixtureConstants.targetRPM,
        minimumRPM: FanCurveUITestFixtureConstants.minimumRPM,
        maximumRPM: FanCurveUITestFixtureConstants.maximumRPM,
        isAutomatic: false
      )
    ],
    ownership: [TestFanOwnership] = [
      TestFanOwnership(
        fanIndex: 0,
        processName: "FanCurveAgent",
        priority: FanCurveUITestFixtureConstants.ownershipPriority
      )
    ],
    xpcFault: TestXPCFault = .noFault
  ) -> FanCurveUITestState {
    FanCurveUITestState(
      services: TestServiceState(
        backgroundAgentStatus: backgroundAgent,
        helperStatus: helper,
        nextOperation: serviceOperation
      ),
      hardware: TestHardwareState(
        sensorTemperatures: sensorTemperatures,
        fanReadings: fanReadings,
        ownership: ownership,
        cpuLoadPercent: FanCurveUITestFixtureConstants.cpuLoadPercent,
        gpuLoadPercent: FanCurveUITestFixtureConstants.gpuLoadPercent,
        runtimeFlags: TestRuntimeFlags(
          helperReachable: helperReachable,
          telemetryStale: telemetryStale,
          ownershipPreempted: ownershipPreempted
        ),
        nextOperation: hardwareOperation
      ),
      xpcFault: xpcFault
    )
  }
}
