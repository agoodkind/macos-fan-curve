//
//  DashboardPresentationState.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-09.
//  Copyright © 2026
//

import SwiftUI

struct DashboardPresentationState: Equatable {
    enum Layout: Equatable {
        case setup
        case dashboard
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

    let layout: Layout
    let chartState: ChartState
    let controlState: ControlState
    let installationStep: InstallationState.Step
    let telemetryFresh: Bool
    let helperActionVisible: Bool

    var showsDashboardSidebar: Bool {
        layout == .dashboard
    }

    var showsFanControlToggle: Bool {
        controlState == .fanControl
    }

    var showsBoostControl: Bool {
        controlState == .fanControl
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

    static func make(
        installationStep: InstallationState.Step,
        telemetryFresh: Bool,
        runtimeTelemetryAvailable: Bool,
        curveActive: Bool,
        boostEnabled: Bool,
        helperSetupPending: Bool = false
    ) -> DashboardPresentationState {
        if installationStep == .checking {
            return DashboardPresentationState(
                layout: .setup,
                chartState: .degraded,
                controlState: .setup,
                installationStep: installationStep,
                telemetryFresh: telemetryFresh,
                helperActionVisible: false
            )
        }

        if helperSetupPending {
            return DashboardPresentationState(
                layout: .dashboard,
                chartState: telemetryFresh ? .preview : .degraded,
                controlState: .monitorOnly,
                installationStep: .helperMissing,
                telemetryFresh: telemetryFresh,
                helperActionVisible: true
            )
        }

        let helperNeedsSetup = installationStep == .helperMissing
            || installationStep == .helperAwaitingApproval
        let backgroundControlNeedsSetup = installationStep == .agentMissing
            || installationStep == .agentAwaitingApproval
        if helperNeedsSetup || backgroundControlNeedsSetup {
            return DashboardPresentationState(
                layout: .dashboard,
                chartState: telemetryFresh ? .preview : .degraded,
                controlState: .monitorOnly,
                installationStep: installationStep,
                telemetryFresh: telemetryFresh,
                helperActionVisible: true
            )
        }

        if !telemetryFresh || !runtimeTelemetryAvailable {
            return DashboardPresentationState(
                layout: .dashboard,
                chartState: .degraded,
                controlState: .fanControl,
                installationStep: installationStep,
                telemetryFresh: telemetryFresh,
                helperActionVisible: false
            )
        }

        let active = curveActive || boostEnabled
        return DashboardPresentationState(
            layout: .dashboard,
            chartState: active ? .active : .preview,
            controlState: .fanControl,
            installationStep: installationStep,
            telemetryFresh: telemetryFresh,
            helperActionVisible: false
        )
    }
}
