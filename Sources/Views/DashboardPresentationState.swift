//
//  DashboardPresentationState.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-05-09.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

struct DashboardPresentationState: Equatable {
  struct Inputs: Equatable {
    let installationStep: InstallationState.Step
    let telemetryFresh: Bool
    let runtimeTelemetryAvailable: Bool
    let helperReachable: Bool
    let curveActive: Bool
    let boostEnabled: Bool
  }

  enum ChartState: Equatable {
    case active
    case preview
    case degraded
  }

  enum ControlState: Equatable {
    case setup
    case monitorOnly
    case fanControl
  }

  let chartState: ChartState
  let controlState: ControlState
  let installationStep: InstallationState.Step
  let telemetryFresh: Bool
  let helperActionVisible: Bool

  var showsFanControlToggle: Bool {
    controlState == .fanControl && chartState != .degraded
  }

  var showsBoostControl: Bool {
    controlState == .fanControl && chartState == .active
  }

  var usesActiveCurveStyling: Bool {
    chartState == .active
  }

  var showsSystemDefault: Bool {
    chartState == .preview
  }

  var showsRuntimeMarkers: Bool {
    telemetryFresh && chartState != .degraded
  }

  var showsRuntimeStats: Bool {
    telemetryFresh && chartState != .degraded
  }

  var usesActiveMarkerStyling: Bool {
    chartState == .active
  }

  static func make(_ inputs: Inputs) -> DashboardPresentationState {
    let backgroundControlNeedsSetup =
      inputs.installationStep == .agentMissing
      || inputs.installationStep == .agentAwaitingApproval
    if inputs.installationStep == .checking || backgroundControlNeedsSetup {
      return DashboardPresentationState(
        chartState: .degraded,
        controlState: .setup,
        installationStep: inputs.installationStep,
        telemetryFresh: inputs.telemetryFresh,
        helperActionVisible: false
      )
    }

    let helperNeedsSetup =
      inputs.installationStep == .helperMissing
      || inputs.installationStep == .helperAwaitingApproval
    let helperRepairIsNonBlocking =
      inputs.installationStep == .helperMissing
      && inputs.helperReachable
      && inputs.telemetryFresh
      && inputs.runtimeTelemetryAvailable
    if helperNeedsSetup, !helperRepairIsNonBlocking {
      return DashboardPresentationState(
        chartState: inputs.telemetryFresh && inputs.runtimeTelemetryAvailable
          ? .preview
          : .degraded,
        controlState: .monitorOnly,
        installationStep: inputs.installationStep,
        telemetryFresh: inputs.telemetryFresh,
        helperActionVisible: true
      )
    }

    if !inputs.telemetryFresh || !inputs.runtimeTelemetryAvailable {
      return DashboardPresentationState(
        chartState: .degraded,
        controlState: .fanControl,
        installationStep: inputs.installationStep,
        telemetryFresh: inputs.telemetryFresh,
        helperActionVisible: false
      )
    }

    let active = inputs.curveActive || inputs.boostEnabled
    return DashboardPresentationState(
      chartState: active ? .active : .preview,
      controlState: .fanControl,
      installationStep: inputs.installationStep,
      telemetryFresh: inputs.telemetryFresh,
      helperActionVisible: false
    )
  }
}
