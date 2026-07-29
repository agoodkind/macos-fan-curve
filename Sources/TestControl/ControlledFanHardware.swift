//
//  ControlledFanHardware.swift
//  FanCurveAgent
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import AppLog
  import Foundation

  private let controlledHardwareLog = AppLog.make(category: "ControlledFanHardware")

  final class ControlledFanHardware: FanHardware, @unchecked Sendable {
    private let runtime: TestControlRuntime

    init(runtime: TestControlRuntime) {
      self.runtime = runtime
    }

    func shutdown() {
      controlledHardwareLog.info("test_control.hardware.shutdown")
    }

    func readAndApply(
      fanCount: UInt,
      tempKeys: [String],
      setFans: [(index: UInt, rpm: Float)],
      autoFans: [UInt],
      priority: Int?
    ) -> FanHardwareBatchRead {
      do {
        let state = try runtime.refresh()
        try runtime.record(.hardwareRead(operation: .fanBatch), state: state)
        guard case .succeed = state.hardware.nextOperation else {
          controlledHardwareLog.error(
            "test_control.hardware.batch_failed revision=\(state.revision.value, privacy: .public) recovery=return-empty-batch"
          )
          return FanHardwareBatchRead(fans: [], temps: [:])
        }
        guard state.hardware.runtimeFlags.helperReachable else {
          controlledHardwareLog.notice(
            "test_control.hardware.batch_unreachable revision=\(state.revision.value, privacy: .public) recovery=return-empty-batch"
          )
          return FanHardwareBatchRead(fans: [], temps: [:])
        }
        for fan in setFans {
          try runtime.record(
            .fanWrite(
              fanIndex: Int(fan.index),
              rpm: fan.rpm,
              priority: priority ?? 0
            ),
            state: state
          )
        }
        for fanIndex in autoFans {
          try runtime.record(
            .fanAutoReset(fanIndex: Int(fanIndex)),
            state: state
          )
        }
        controlledHardwareLog.debug(
          "test_control.hardware.batch_returned fans=\(fanCount, privacy: .public) temperatures=\(tempKeys.count, privacy: .public) revision=\(state.revision.value, privacy: .public)"
        )
        return makeBatch(
          state: state.hardware,
          fanCount: fanCount,
          tempKeys: tempKeys
        )
      } catch {
        controlledHardwareLog.error(
          "test_control.hardware.batch_refused error=\(error.localizedDescription, privacy: .public) recovery=return-empty-batch"
        )
        return FanHardwareBatchRead(fans: [], temps: [:])
      }
    }

    func getOwnership() throws -> [AgentOwnershipEntry] {
      let state = try runtime.refresh()
      try runtime.record(.hardwareRead(operation: .ownership), state: state)
      try requireSuccess(state.hardware.nextOperation)
      controlledHardwareLog.debug(
        "test_control.hardware.ownership_returned revision=\(state.revision.value, privacy: .public)"
      )
      return state.hardware.ownership.compactMap { ownership in
        guard
          ownership.fanIndex >= 0,
          let processName = ownership.processName,
          let priority = ownership.priority
        else {
          return nil
        }
        let fanIndex = UInt(ownership.fanIndex)
        return AgentOwnershipEntry(
          id: fanIndex,
          fanIndex: fanIndex,
          clientName: processName,
          priority: priority,
          ageSeconds: 0
        )
      }
    }

    func setFanRPM(
      _ index: UInt,
      rpm: Float,
      priority: Int?
    ) throws {
      let state = try runtime.refresh()
      try runtime.record(
        .fanWrite(
          fanIndex: Int(index),
          rpm: rpm,
          priority: priority ?? 0
        ),
        state: state
      )
      try requireSuccess(state.hardware.nextOperation)
      controlledHardwareLog.info(
        "test_control.hardware.rpm_written fan=\(index, privacy: .public) rpm=\(rpm, privacy: .public) revision=\(state.revision.value, privacy: .public)"
      )
    }

    func setFanAuto(
      _ index: UInt,
      priority _: Int?
    ) throws {
      let state = try runtime.refresh()
      try runtime.record(
        .fanAutoReset(fanIndex: Int(index)),
        state: state
      )
      try requireSuccess(state.hardware.nextOperation)
      controlledHardwareLog.info(
        "test_control.hardware.auto_reset fan=\(index, privacy: .public) revision=\(state.revision.value, privacy: .public)"
      )
    }

    private func requireSuccess(_ directive: TestOperationDirective) throws {
      if case let .fail(code, message) = directive {
        controlledHardwareLog.error(
          "test_control.hardware.operation_failed code=\(code, privacy: .public) recovery=return-controlled-error"
        )
        throw TestControlOperationError(code: code, message: message)
      }
    }

    private func makeBatch(
      state: TestHardwareState,
      fanCount: UInt,
      tempKeys: [String]
    ) -> FanHardwareBatchRead {
      let fans = state.fanReadings
        .filter { $0.fanIndex >= 0 && UInt($0.fanIndex) < fanCount }
        .sorted { $0.fanIndex < $1.fanIndex }
        .map { fan in
          FanInfo(
            actualRPM: fan.actualRPM,
            targetRPM: fan.targetRPM,
            minRPM: fan.minimumRPM,
            maxRPM: fan.maximumRPM,
            manualMode: !fan.isAutomatic
          )
        }
      let requestedKeys = Set(tempKeys)
      var temperatures: [String: Float] = [:]
      for sensor in state.sensorTemperatures where requestedKeys.contains(sensor.name) {
        temperatures[sensor.name] = Float(sensor.temperatureC)
      }
      return FanHardwareBatchRead(fans: fans, temps: temperatures)
    }
  }
#endif
