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
    private static let verificationPollMilliseconds: Int64 = 50
    private static let verificationPollInterval = Duration.milliseconds(
      verificationPollMilliseconds
    )

    private let identityLock = NSLock()
    private let runtime: TestControlRuntime
    private var identityRequestCount = 0

    init(runtime: TestControlRuntime) {
      self.runtime = runtime
    }

    func shutdown() {
      controlledHardwareLog.info("test_control.hardware.shutdown")
    }

    func getHelperIdentity() async throws -> SystemHelperIdentity {
      var state = try runtime.refresh()
      let isVerification = identityLock.withLock {
        identityRequestCount += 1
        return identityRequestCount > 1
      }
      let verificationWasBlocked =
        isVerification && state.helperLifecycle.verificationBlocked
      if verificationWasBlocked {
        controlledHardwareLog.debug(
          "test_control.helper.verification_blocked revision=\(state.revision.value, privacy: .public) recovery=wait-for-control-revision"
        )
      }
      while isVerification, state.helperLifecycle.verificationBlocked {
        try await ContinuousClock().sleep(for: Self.verificationPollInterval)
        state = try runtime.refresh()
      }
      if verificationWasBlocked {
        controlledHardwareLog.debug(
          "test_control.helper.verification_resumed revision=\(state.revision.value, privacy: .public)"
        )
      }
      if !isVerification {
        try runtime.record(
          .helperClassification(
            active: state.helperLifecycle.active,
            bundled: state.helperLifecycle.bundled
          ),
          state: state
        )
      }
      switch state.helperLifecycle.active {
      case .identity(let identity):
        if isVerification,
          identity.executableHash == state.helperLifecycle.bundled.executableHash
        {
          try runtime.record(.helperIdentityVerified(identity), state: state)
        }
        controlledHardwareLog.debug(
          "test_control.helper.identity_returned version=\(identity.version, privacy: .public) build=\(identity.build, privacy: .public) revision=\(state.revision.value, privacy: .public)"
        )
        return SystemHelperIdentity(identity)
      case .legacy:
        throw TestControlOperationError(
          code: "legacy-helper",
          message: "System Helper does not support identity"
        )
      case .unreachable(let message):
        throw TestControlOperationError(
          code: "helper-unreachable",
          message: message
        )
      }
    }

    func probeLegacyHelperReachability() async throws {
      await Task.yield()
      let state = try runtime.refresh()
      guard case .legacy = state.helperLifecycle.active else {
        throw TestControlOperationError(
          code: "legacy-helper-unreachable",
          message: "Legacy System Helper is unreachable"
        )
      }
      controlledHardwareLog.debug(
        "test_control.helper.legacy_probe_completed revision=\(state.revision.value, privacy: .public)"
      )
    }

    func resetAllDiscoveredFansToAuto() async throws {
      await Task.yield()
      let state = try runtime.refresh()
      if case .fail = state.hardware.nextOperation {
        try runtime.record(
          .helperFanReset(result: state.hardware.nextOperation),
          state: state
        )
      }
      try requireSuccess(state.hardware.nextOperation)
      let fanIndices = Set(
        state.hardware.fanReadings.compactMap { reading in
          reading.fanIndex >= 0 ? reading.fanIndex : nil
        }
      )
      for fanIndex in fanIndices.sorted() {
        try runtime.record(.fanAutoReset(fanIndex: fanIndex), state: state)
      }
      try runtime.record(.helperFanReset(result: .succeed), state: state)
      controlledHardwareLog.info(
        "test_control.helper.fan_reset_completed count=\(fanIndices.count, privacy: .public) revision=\(state.revision.value, privacy: .public)"
      )
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

    /// Reports the sensor names the controlled session defines, so key
    /// discovery is drivable from a test session the same way readings are.
    ///
    /// Returns an empty array on any failure. Callers read that as "could not
    /// enumerate" rather than "this machine has no keys", so a controlled
    /// failure never prunes the sensor catalog.
    func enumerateKeys() -> [String] {
      do {
        let state = try runtime.refresh()
        try runtime.record(.hardwareRead(operation: .fanBatch), state: state)
        guard case .succeed = state.hardware.nextOperation else {
          controlledHardwareLog.error(
            "test_control.hardware.enumerate_failed revision=\(state.revision.value, privacy: .public) recovery=return-empty-keys"
          )
          return []
        }
        // Mirrors the batch read's guard. An unreachable helper cannot have
        // answered, so returning the configured names would let the resolver
        // prune the catalog from a failure. That pruning is permanent for the
        // process, because `sensorKeysResolved` stops it retrying once the
        // helper comes back.
        guard state.hardware.runtimeFlags.helperReachable else {
          controlledHardwareLog.notice(
            "test_control.hardware.enumerate_unreachable revision=\(state.revision.value, privacy: .public) recovery=return-empty-keys"
          )
          return []
        }
        let keys = state.hardware.sensorTemperatures.map(\.name)
        controlledHardwareLog.debug(
          "test_control.hardware.enumerate_returned count=\(keys.count, privacy: .public) revision=\(state.revision.value, privacy: .public)"
        )
        return keys
      } catch {
        controlledHardwareLog.error(
          "test_control.hardware.enumerate_refused error=\(error.localizedDescription, privacy: .public) recovery=return-empty-keys"
        )
        return []
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
