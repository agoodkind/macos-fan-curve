//
//  AgentController+Tick.swift
//  FanCurveAgent
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let agentControllerTickLog = AppLog.make(category: "AgentControllerTick")

private enum AgentControllerTickConstants {
  /// Tick duration is logged in milliseconds so a stalled tick is legible
  /// without reading fractional seconds.
  static let millisecondsPerSecond: Double = 1_000
}

// MARK: - AgentController

extension AgentController {
  func requestTick() {
    Task { [weak self] in
      guard let self else { return }
      guard await tickCoordinator.requestTick() else { return }
      await runTickLoop()
    }
  }

  func runTickLoop() async {
    while true {
      await tick()
      if await tickCoordinator.finishTick() {
        continue
      }
      return
    }
  }

  func tick() async {
    let tickStart = Date()
    defer { logTickCompleted(start: tickStart) }

    await resolveSensorKeysIfNeeded()
    let telemetry = await readTickTelemetry()
    guard await handleInactiveTickIfNeeded(telemetry) else { return }
    guard let context = makeActiveTickContext(from: telemetry) else { return }

    let runtimeState = resolveRuntimeState(from: context)
    let fanActions = buildFanActions(from: context, runtimeState: runtimeState)
    await applyFanActions(fanActions)
    publishTickOutputs(
      context: context,
      runtimeState: runtimeState,
      fanActions: fanActions
    )
  }

  /// Pruning removes the failed key reads that previously served as an
  /// accidental tick clock. This line keeps tick latency measurable now
  /// that those doomed reads are gone.
  func logTickCompleted(start: Date) {
    let durationMs =
      Date().timeIntervalSince(start)
      * AgentControllerTickConstants.millisecondsPerSecond
    agentControllerTickLog.notice(
      "agent.tick.completed durationMs=\(String(format: "%.1f", durationMs), privacy: .public)"
    )
  }

  func readTickTelemetry() async -> AgentControllerTickTypes.TickTelemetry {
    let active = sharedConfig.loadIsActive()
    let result = await fanHardware.readAndApply(
      fanCount: cachedFanCount,
      tempKeys: tempKeys
    )
    if !result.fans.isEmpty {
      cachedFanCount = UInt(result.fans.count)
    }

    // Liveness is reported by `heartbeatScheduler` on its own cadence, not
    // here, so a stalled read above cannot make a healthy process look dead.
    sharedConfig.writeAgentLastError(nil)

    let activityState: ActivityState = active ? .active : .inactive
    let transitioned = lastActivityState != activityState
    lastActivityState = activityState

    var maxCPUTemp: Double = 0
    for (key, value) in result.temps where cpuTempKeys.contains(key) {
      maxCPUTemp = max(maxCPUTemp, Double(value))
    }
    loadSampler.sample()

    return AgentControllerTickTypes.TickTelemetry(
      active: active,
      result: result,
      transitioned: transitioned,
      maxCPUTemp: maxCPUTemp,
      cpuLoad: loadSampler.smoothed,
      gpuLoad: readGPULoadPercent()
    )
  }

  func handleInactiveTickIfNeeded(
    _ telemetry: AgentControllerTickTypes.TickTelemetry
  ) async -> Bool {
    guard telemetry.active else {
      resetInactiveControllerState()
      publishSnapshotIfNeeded(inactiveSnapshot(from: telemetry))
      if telemetry.transitioned, !telemetry.result.fans.isEmpty {
        _ = await fanHardware.readAndApply(
          fanCount: 0,
          tempKeys: [],
          autoFans: Array(0..<UInt(telemetry.result.fans.count))
        )
        agentControllerTickLog.notice("agent.curve.deactivated fans=auto")
      }
      return false
    }
    if telemetry.transitioned {
      // Leaving the inactive state already cleared the demand conditioner.
      beginRampSnap(resettingDemand: false)
      agentControllerTickLog.notice("agent.curve.activated fans=snap-to-curve")
    }
    if telemetry.result.fans.isEmpty {
      agentControllerTickLog.debug(
        "agent.tick.fan_telemetry_unavailable recovery=publish-monitor-snapshot"
      )
    }
    guard telemetry.maxCPUTemp > 0 else {
      resetInactiveControllerState()
      publishSnapshotIfNeeded(activeTemperatureUnavailableSnapshot(from: telemetry))
      agentControllerTickLog.debug(
        "agent.tick.temperature_unavailable fanCount=\(telemetry.result.fans.count, privacy: .public) recovery=publish-holding-snapshot"
      )
      return false
    }
    return true
  }

  func resetInactiveControllerState() {
    filteredTemperatureFast = nil
    filteredTemperatureSlow = nil
    previousFastTemperature = nil
    previousSlowTemperature = nil
    rampStateByFan.removeAll()
    rampSnapRequested = false
    resetObservedCurveShapes()
    lastBoostObservation = .unobserved
    lastCommandLogPercentByFan.removeAll()
    conditionedDemandPercent = nil
    conditionedDemandPercentVelocity = 0
    conditionedDemandTemperatureC = nil
    conditionedDemandTemperatureVelocityC = 0
    lastDemandConditioningTime = nil
    controllerMode = .holding
    thermalDebt = 0
  }

  func helperReachable(from telemetry: AgentControllerTickTypes.TickTelemetry) -> Bool {
    !telemetry.result.fans.isEmpty || !telemetry.result.temps.isEmpty
  }

  func inactiveSnapshot(from telemetry: AgentControllerTickTypes.TickTelemetry) -> AgentSnapshot {
    AgentSnapshot(
      timestamp: Date(),
      helperReachable: helperReachable(from: telemetry),
      curveActive: false,
      boostEnabled: false,
      governingTemperatureC: telemetry.maxCPUTemp,
      committedTemperatureC: telemetry.maxCPUTemp,
      rawPressureTemperatureC: telemetry.maxCPUTemp > 0 ? telemetry.maxCPUTemp : nil,
      cpuLoadPercent: telemetry.cpuLoad,
      gpuLoadPercent: telemetry.gpuLoad,
      effectiveCurvePercent: 0,
      baseCurvePercent: 0,
      rawBaselinePercent: 0,
      semanticDemandPercent: 0,
      thermalDemandSource: .curve,
      semanticDemandTemperatureC: telemetry.maxCPUTemp > 0 ? telemetry.maxCPUTemp : nil,
      commandedTargetPercent: 0,
      commandedTargetTemperatureC: nil,
      committedPercent: 0,
      controllerMode: .holding,
      bandIndex: 0,
      holdRemainingSeconds: 0,
      assistFloorPercent: nil,
      activeAssistKinds: [],
      fans: telemetry.result.fans.enumerated().map { index, fan in
        AgentFanSnapshot(
          index: index,
          actualRPM: fan.actualRPM,
          targetRPM: fan.targetRPM,
          minRPM: fan.minRPM,
          maxRPM: fan.maxRPM,
          manualMode: fan.manualMode
        )
      }
    )
  }

  func activeTemperatureUnavailableSnapshot(
    from telemetry: AgentControllerTickTypes.TickTelemetry
  ) -> AgentSnapshot {
    AgentSnapshot(
      timestamp: Date(),
      helperReachable: helperReachable(from: telemetry),
      curveActive: true,
      boostEnabled: sharedConfig.loadBoostEnabled(),
      governingTemperatureC: 0,
      committedTemperatureC: 0,
      rawPressureTemperatureC: nil,
      cpuLoadPercent: telemetry.cpuLoad,
      gpuLoadPercent: telemetry.gpuLoad,
      effectiveCurvePercent: 0,
      baseCurvePercent: 0,
      rawBaselinePercent: 0,
      semanticDemandPercent: 0,
      thermalDemandSource: .curve,
      semanticDemandTemperatureC: nil,
      commandedTargetPercent: 0,
      commandedTargetTemperatureC: nil,
      committedPercent: 0,
      controllerMode: .holding,
      bandIndex: 0,
      holdRemainingSeconds: 0,
      assistFloorPercent: nil,
      activeAssistKinds: [],
      fans: telemetry.result.fans.enumerated().map { index, fan in
        AgentFanSnapshot(
          index: index,
          actualRPM: fan.actualRPM,
          targetRPM: fan.targetRPM,
          minRPM: fan.minRPM,
          maxRPM: fan.maxRPM,
          manualMode: fan.manualMode
        )
      }
    )
  }

  func resolveAssistState(
    boost: Bool,
    curvePercent: Double,
    cpuLoad: Double,
    gpuLoad: Double
  ) -> AgentControllerTickTypes.AssistState {
    var assistAppliedKinds: [LoadAssistKind] = []
    var assistFloorPercent: Double?
    var rawBaselinePercent = curvePercent
    var demandSource: ThermalDemandSource = .curve

    if !boost {
      for kind in LoadAssistKind.allCases where sharedConfig.loadLoadAssistEnabled(kind) {
        let loadPercent = kind == .cpu ? cpuLoad : gpuLoad
        let assistFloor = CurveInterpolation.evaluate(
          at: loadPercent,
          points: sharedConfig.loadLoadAssistCurve(kind),
          mode: .catmullRom,
          axisScale: .linear(range: LoadAssistCurveColumns.xRange)
        )
        if assistFloor > rawBaselinePercent {
          rawBaselinePercent = assistFloor
          assistFloorPercent = assistFloor
          assistAppliedKinds = [kind]
          demandSource = .assist
        } else if assistFloor == rawBaselinePercent, assistFloor > 0 {
          assistFloorPercent = assistFloor
          assistAppliedKinds.append(kind)
          demandSource = .assist
        }
      }
    }

    return AgentControllerTickTypes.AssistState(
      rawBaselinePercent: max(0, min(1, rawBaselinePercent)),
      assistFloorPercent: assistFloorPercent,
      assistAppliedKinds: assistAppliedKinds,
      demandSource: demandSource
    )
  }

  func resolveRuntimeState(
    from context: AgentControllerTickTypes.ActiveTickContext
  ) -> AgentControllerDemandTypes.RuntimeBandState {
    if context.boost {
      return AgentControllerDemandTypes.RuntimeBandState(
        committedPercent: context.conditionedDemand.percent,
        commandedTargetTemperatureC: context.conditionedDemand.temperatureC,
        bandIndex: bandIndex(for: context.conditionedDemand.percent),
        committedTemperatureC: context.telemetry.maxCPUTemp,
        baseCurvePercent: context.baseCurvePercent,
        rawBaselinePercent: 1.0,
        semanticDemandPercent: 1.0,
        thermalDemandSource: .boost,
        semanticDemandTemperatureC: context.pressureTemperature,
        mode: .rampingUp,
        holdRemainingSeconds: 0
      )
    }

    let observedFanPercent = observedCurvePercent(fans: context.telemetry.result.fans)
    return bandControlledState(
      input: AgentControllerDemandTypes.BandControlInput(
        rawBaselinePercent: context.rawBaselinePercent,
        semanticDemandTemperatureC: context.pressureTemperature,
        conditionedDemandPercent: context.conditionedDemand.percent,
        conditionedDemandTemperatureC: context.conditionedDemand.temperatureC,
        baseCurvePercent: context.baseCurvePercent,
        demandSource: context.demandSource,
        rawTemperatureC: context.telemetry.maxCPUTemp,
        fastTemperatureC: context.fastTemp,
        slowTemperatureC: context.slowTemp,
        cpuLoad: context.telemetry.cpuLoad,
        observedFanPercent: observedFanPercent
      )
    )
  }

  func buildFanActions(
    from context: AgentControllerTickTypes.ActiveTickContext,
    runtimeState: AgentControllerDemandTypes.RuntimeBandState
  ) -> AgentControllerTickTypes.FanActions {
    let assistSummary = context.assistAppliedKinds.map(\.rawValue).joined(separator: ",")
    agentControllerTickLog.debug(
      "agent.tick cpuTemp=\(Int(context.telemetry.maxCPUTemp), privacy: .public)C cpuLoad=\(Int(context.telemetry.cpuLoad), privacy: .public)% gpuLoad=\(Int(context.telemetry.gpuLoad), privacy: .public)% raw=\(Int(runtimeState.rawBaselinePercent * 100), privacy: .public)% semantic=\(Int(runtimeState.semanticDemandPercent * 100), privacy: .public)% commanded=\(Int(runtimeState.committedPercent * 100), privacy: .public)% demandSource=\(runtimeState.thermalDemandSource.rawValue, privacy: .public) mode=\(runtimeState.mode.rawValue, privacy: .public) debt=\(Int(thermalDebt * 100), privacy: .public)% responseMultiplier=\(Int(context.fanResponseMultiplier.rawValue * 100), privacy: .public)% responseInferred=\(context.fanResponseInferred, privacy: .public) boost=\(context.boost, privacy: .public) assist=\(assistSummary, privacy: .public)"
    )

    var setFans: [(index: UInt, rpm: Float)] = []
    var autoFans: [UInt] = []
    for (fanIndex, fan) in context.telemetry.result.fans.enumerated() {
      let command = fanCommandFor(
        percent: runtimeState.committedPercent,
        minRPM: fan.minRPM,
        maxRPM: fan.maxRPM
      )
      let smoothedCommand = rampGovernedCommand(
        input: RampCommandInput(
          command: command,
          index: UInt(fanIndex),
          currentFan: fan,
          currentTemperatureC: context.telemetry.maxCPUTemp,
          fastTrendCPerTick: context.fastTrend,
          slowTrendCPerTick: context.slowTrend,
          fanResponseMultiplier: context.fanResponseMultiplier,
          now: context.now
        )
      )

      switch command {
      case .setRPM:
        if case .setRPM(let rpm) = smoothedCommand {
          setFans.append((index: UInt(fanIndex), rpm: rpm))
        }
      case .auto:
        rampStateByFan.removeValue(forKey: UInt(fanIndex))
        autoFans.append(UInt(fanIndex))
      }
    }
    // Every fan has now had its chance to snap, so the request is spent.
    rampSnapRequested = false

    let tickPriority =
      context.boost
      ? sharedConfig.loadUserBoostPriority()
      : sharedConfig.loadCurveNormalPriority()

    return AgentControllerTickTypes.FanActions(
      setFans: setFans,
      autoFans: autoFans,
      tickPriority: tickPriority,
      assistSummary: assistSummary
    )
  }

  func applyFanActions(_ actions: AgentControllerTickTypes.FanActions) async {
    _ = await fanHardware.readAndApply(
      fanCount: 0,
      tempKeys: [],
      setFans: actions.setFans,
      autoFans: actions.autoFans,
      priority: actions.tickPriority
    )
  }

  func publishTickOutputs(
    context: AgentControllerTickTypes.ActiveTickContext,
    runtimeState: AgentControllerDemandTypes.RuntimeBandState,
    fanActions: AgentControllerTickTypes.FanActions
  ) {
    publishSnapshotIfNeeded(snapshot(from: context, runtimeState: runtimeState))
    appendEventArtifact(context: context, runtimeState: runtimeState, fanActions: fanActions)
  }

  func snapshot(
    from context: AgentControllerTickTypes.ActiveTickContext,
    runtimeState: AgentControllerDemandTypes.RuntimeBandState
  ) -> AgentSnapshot {
    let fans = context.telemetry.result.fans
    return AgentSnapshot(
      timestamp: context.now,
      helperReachable: helperReachable(from: context.telemetry),
      curveActive: context.telemetry.active,
      boostEnabled: context.boost,
      governingTemperatureC: context.telemetry.maxCPUTemp,
      committedTemperatureC: runtimeState.committedTemperatureC,
      rawPressureTemperatureC: context.pressureTemperature,
      cpuLoadPercent: context.telemetry.cpuLoad,
      gpuLoadPercent: context.telemetry.gpuLoad,
      effectiveCurvePercent: runtimeState.committedPercent,
      baseCurvePercent: runtimeState.baseCurvePercent,
      rawBaselinePercent: runtimeState.rawBaselinePercent,
      semanticDemandPercent: runtimeState.semanticDemandPercent,
      thermalDemandSource: runtimeState.thermalDemandSource,
      semanticDemandTemperatureC: runtimeState.semanticDemandTemperatureC,
      commandedTargetPercent: runtimeState.committedPercent,
      commandedTargetTemperatureC: runtimeState.commandedTargetTemperatureC,
      committedPercent: runtimeState.committedPercent,
      controllerMode: runtimeState.mode,
      bandIndex: runtimeState.bandIndex,
      holdRemainingSeconds: runtimeState.holdRemainingSeconds,
      assistFloorPercent: context.assistFloorPercent,
      activeAssistKinds: context.assistAppliedKinds,
      fans: fans.enumerated().map { index, fan in
        AgentFanSnapshot(
          index: index,
          actualRPM: fan.actualRPM,
          targetRPM: fan.targetRPM,
          minRPM: fan.minRPM,
          maxRPM: fan.maxRPM,
          manualMode: fan.manualMode
        )
      }
    )
  }

  func appendEventArtifact(
    context: AgentControllerTickTypes.ActiveTickContext,
    runtimeState: AgentControllerDemandTypes.RuntimeBandState,
    fanActions: AgentControllerTickTypes.FanActions
  ) {
    let fans = context.telemetry.result.fans
    let artifactKind =
      if context.boost {
        "boost"
      } else if context.assistAppliedKinds.isEmpty {
        "curve"
      } else {
        "assist:\(fanActions.assistSummary)"
      }

    eventWriter.append(
      EventArtifactWriter.AppendRequest(
        timestamp: context.now,
        kind: artifactKind,
        governingTempC: context.telemetry.maxCPUTemp,
        rawTemperatureC: context.telemetry.maxCPUTemp,
        fastTemperatureC: context.fastTemp,
        slowTemperatureC: context.slowTemp,
        cpuLoadPercent: context.telemetry.cpuLoad,
        gpuLoadPercent: context.telemetry.gpuLoad,
        effectiveCurvePercent: runtimeState.committedPercent,
        rawBaselinePercent: runtimeState.rawBaselinePercent,
        committedPercent: runtimeState.committedPercent,
        bandIndex: runtimeState.bandIndex,
        holdRemainingSeconds: runtimeState.holdRemainingSeconds,
        thermalDebt: thermalDebt,
        controllerMode: runtimeState.mode.rawValue,
        assistFloorPercent: context.assistFloorPercent,
        activeAssistKinds: context.assistAppliedKinds.map(\.rawValue),
        fanActualRPM: fans.map(\.actualRPM),
        fanTargetRPM: fans.map(\.targetRPM),
        fanMinRPM: fans.map(\.minRPM),
        fanMaxRPM: fans.map(\.maxRPM),
        fanManualMode: fans.map(\.manualMode)
      )
    )
  }

  func publishSnapshotIfNeeded(_ snapshot: AgentSnapshot) {
    sharedConfig.writeAgentSnapshot(snapshot)
    if lastPublishedSnapshot != snapshot {
      lastPublishedSnapshot = snapshot
      AgentSnapshotPush.post()
      runtimeStateDidChange?(currentRuntimeStateForXPC())
    }
  }

  func smoothedTemperature(
    rawTemp: Double,
    current: Double?,
    previous: inout Double?,
    alpha: Double
  ) -> Double {
    guard let current else {
      previous = nil
      return rawTemp
    }

    previous = current
    return alpha * rawTemp + (1.0 - alpha) * current
  }
}
