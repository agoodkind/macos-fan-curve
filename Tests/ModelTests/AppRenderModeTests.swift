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
    func testVisibleModesAllowLiveAnimation() {
        expect(AppRenderMode.interactive.allowsLiveAnimation) == true
        expect(AppRenderMode.backgroundVisible.allowsLiveAnimation) == true
    }

    func testOccludedModeSuppressesLiveAnimation() {
        expect(AppRenderMode.occluded.allowsLiveAnimation) == false
    }
}
