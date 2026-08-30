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

// MARK: - CurveShape

/// The shape of the line the user sees: the control points and how they are
/// joined. Two ticks that produce the same shape describe the same curve,
/// whatever identifiers the stored points carry.
struct CurveShape: Equatable {
  private let temperatures: [Double]
  private let fanPercents: [Double]
  private let interpolationMode: InterpolationMode

  init(points: [CurvePoint], interpolationMode: InterpolationMode) {
    self.temperatures = points.map(\.temperature)
    self.fanPercents = points.map(\.fanPercent)
    self.interpolationMode = interpolationMode
  }

  static func == (lhs: CurveShape, rhs: CurveShape) -> Bool {
    lhs.temperatures == rhs.temperatures
      && lhs.fanPercents == rhs.fanPercents
      && lhs.interpolationMode == rhs.interpolationMode
  }
}

// MARK: - BoostObservation

/// Boost as a tick last saw it.
///
/// The state before the first active tick is not the same as Boost being off:
/// a tick that has never seen Boost has no earlier value to compare against,
/// and must not treat its first reading as a user press.
enum BoostObservation: Equatable {
  case observed(Bool)
  case unobserved
}

// MARK: - ExpandedRangeState

struct ExpandedRangeState: Equatable {
  let overdriveEnabled: Bool
  let underdriveEnabled: Bool
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

  /// Snaps onto the line when the user edits the curve. The first observed
  /// shape only records a starting point: activation has already snapped by
  /// the time this runs, so treating it as an edit would snap twice.
  private func snapIfCurveChanged(to shape: CurveShape) {
    defer { lastCurveShape = shape }
    guard let lastCurveShape, lastCurveShape != shape else { return }
    beginRampSnap(resettingDemand: true)
    agentControllerLog.notice("agent.curve.edited fans=snap-to-curve")
  }

  func resetObservedCurveShapes() {
    lastCurveShape = nil
    lastLoadAssistCurveShape = nil
  }

  private func snapIfLoadAssistCurveChanged(to shape: CurveShape) {
    defer { lastLoadAssistCurveShape = shape }
    guard let lastLoadAssistCurveShape, lastLoadAssistCurveShape != shape else { return }
    beginRampSnap(resettingDemand: true)
    agentControllerLog.notice("agent.load_assist_curve.edited fans=snap-to-curve")
  }

  private func loadAssistCurveShape() -> CurveShape {
    let cpuPoints = sharedConfig.loadLoadAssistCurve(.cpu)
    let gpuPoints = sharedConfig.loadLoadAssistCurve(.gpu)
    return CurveShape(
      points: cpuPoints + gpuPoints,
      interpolationMode: .catmullRom
    )
  }

  /// Snaps onto the new target when the user presses Boost, in either
  /// direction. Boost is a direct request for a fan speed, so damping it the
  /// way ambient temperature drift is damped would take about a minute to
  /// reach full speed.
  ///
  /// The first observed value only records a starting point, since activation
  /// has already snapped by the time this runs.
  private func snapIfBoostChanged(to boost: Bool) {
    defer { lastBoostObservation = .observed(boost) }
    guard case .observed(let previous) = lastBoostObservation, previous != boost else {
      return
    }
    beginRampSnap(resettingDemand: true)
    agentControllerLog.notice(
      "agent.boost.changed enabled=\(boost, privacy: .public) fans=snap-to-curve"
    )
  }

  private func snapIfExpandedRangeChanged(to state: ExpandedRangeState) {
    defer { lastExpandedRangeState = state }
    guard let lastExpandedRangeState, lastExpandedRangeState != state else { return }
    beginRampSnap(resettingDemand: false)
    agentControllerLog.notice(
      "agent.expanded_range.changed overdrive=\(state.overdriveEnabled, privacy: .public) underdrive=\(state.underdriveEnabled, privacy: .public) fans=snap-to-curve"
    )
  }

  private func activeTickCurveState(at pressureTemperature: Double)
    -> ActiveTickCurveState
  {
    let boost = sharedConfig.loadBoostEnabled()
    snapIfBoostChanged(to: boost)
    snapIfExpandedRangeChanged(to: sharedConfig.loadExpandedRangeState())
    let points = sharedConfig.loadCurve()
    let mode = sharedConfig.loadInterpolationMode()
    snapIfCurveChanged(to: CurveShape(points: points, interpolationMode: mode))
    snapIfLoadAssistCurveChanged(to: loadAssistCurveShape())
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
