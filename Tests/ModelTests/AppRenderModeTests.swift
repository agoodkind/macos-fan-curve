//
//  AppRenderModeTests.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-05-14.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class AppRenderModeTests: XCTestCase {
  func testInteractiveModeShowsLiveDashboard() {
    expect(AppRenderMode.interactive.showsLiveDashboard) == true
  }

  func testBackgroundVisibleModeHidesLiveDashboard() {
    expect(AppRenderMode.backgroundVisible.showsLiveDashboard) == false
  }

  func testOccludedModeHidesLiveDashboard() {
    expect(AppRenderMode.occluded.showsLiveDashboard) == false
  }

  func testVisibleModesAllowLiveAnimation() {
    expect(AppRenderMode.interactive.allowsLiveAnimation) == true
    expect(AppRenderMode.backgroundVisible.allowsLiveAnimation) == true
  }

  func testOccludedModeSuppressesLiveAnimation() {
    expect(AppRenderMode.occluded.allowsLiveAnimation) == false
  }
}
