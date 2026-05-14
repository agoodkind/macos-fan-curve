//
//  AppRenderModeTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-14.
//  Copyright © 2026
//

import Nimble
import XCTest

@testable import FanCurveModels

final class AppRenderModeTests: XCTestCase {
    func testInteractiveModeShowsLiveDashboard() {
        expect(AppRenderMode.interactive.showsLiveDashboard) == true
        expect(AppRenderMode.interactive.showsPausedDashboard) == false
    }

    func testBackgroundVisibleModeShowsPausedDashboard() {
        expect(AppRenderMode.backgroundVisible.showsLiveDashboard) == false
        expect(AppRenderMode.backgroundVisible.showsPausedDashboard) == true
    }

    func testOccludedModeShowsPausedDashboard() {
        expect(AppRenderMode.occluded.showsLiveDashboard) == false
        expect(AppRenderMode.occluded.showsPausedDashboard) == true
    }

    func testVisibleModesAllowLiveAnimation() {
        expect(AppRenderMode.interactive.allowsLiveAnimation) == true
        expect(AppRenderMode.backgroundVisible.allowsLiveAnimation) == true
    }

    func testOccludedModeSuppressesLiveAnimation() {
        expect(AppRenderMode.occluded.allowsLiveAnimation) == false
    }
}
