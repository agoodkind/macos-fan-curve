//
//  SettingsMonitoringGateTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-24.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class SettingsMonitoringGateTests: XCTestCase {
    func testGeneralTabInInteractiveModeEnablesMonitoring() {
        let gate = SettingsMonitoringGate(
            selectedTab: .general,
            renderMode: .interactive
        )

        expect(gate.isMonitoringEnabled) == true
    }

    func testNonGeneralTabDisablesMonitoring() {
        let gate = SettingsMonitoringGate(
            selectedTab: .advanced,
            renderMode: .interactive
        )

        expect(gate.isMonitoringEnabled) == false
    }

    func testBackgroundVisibleModeDisablesMonitoring() {
        let gate = SettingsMonitoringGate(
            selectedTab: .general,
            renderMode: .backgroundVisible
        )

        expect(gate.isMonitoringEnabled) == false
    }

    func testOccludedModeDisablesMonitoring() {
        let gate = SettingsMonitoringGate(
            selectedTab: .general,
            renderMode: .occluded
        )

        expect(gate.isMonitoringEnabled) == false
    }
}
