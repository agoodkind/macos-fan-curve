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

    var usesActiveMarkerStyling: Bool {
        chartState == .active
    }

    static func make(
        installationStep: InstallationState.Step,
        telemetryFresh: Bool,
        curveActive: Bool,
        boostEnabled: Bool
    ) -> DashboardPresentationState {
        if installationStep == .checking
            || installationStep == .agentMissing
            || installationStep == .agentAwaitingApproval
        {
            return DashboardPresentationState(
                layout: .setup,
                chartState: .degraded,
                controlState: .setup,
                installationStep: installationStep,
                telemetryFresh: telemetryFresh,
                helperActionVisible: false
            )
        }

        let helperNeedsSetup = installationStep == .helperMissing
            || installationStep == .helperAwaitingApproval
        if helperNeedsSetup {
            return DashboardPresentationState(
                layout: .dashboard,
                chartState: telemetryFresh ? .preview : .degraded,
                controlState: .monitorOnly,
                installationStep: installationStep,
                telemetryFresh: telemetryFresh,
                helperActionVisible: true
            )
        }

        if !telemetryFresh {
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

