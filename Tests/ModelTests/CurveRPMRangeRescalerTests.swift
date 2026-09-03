//
//  CurveRPMRangeRescalerTests.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-09-02.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class CurveRPMRangeRescalerTests: XCTestCase {
  func testEnablingOverdriveShrinksPercentToHoldRPMConstant() {
    // 50% of a 0...6000 range commands 3000 RPM. After Overdrive raises the
    // range to 0...10000, holding 3000 RPM means dropping to 30%.
    let rescaler = CurveRPMRangeRescaler(
      oldRange: (min: 0, max: 6_000),
      newRange: (min: 0, max: 10_000)
    )

    let rescaled = rescaler.rescale([point(percent: 0.5)])

    expect(rescaled[0].fanPercent).to(beCloseTo(0.3, within: 0.0001))
  }

  func testEnablingUnderdriveGrowsPercentToHoldRPMConstant() {
    // 50% of a 1200...6000 range commands 3600 RPM. After Underdrive drops
    // the floor to 0, holding 3600 RPM means rising to 60%.
    let rescaler = CurveRPMRangeRescaler(
      oldRange: (min: 1_200, max: 6_000),
      newRange: (min: 0, max: 6_000)
    )

    let rescaled = rescaler.rescale([point(percent: 0.5)])

    expect(rescaled[0].fanPercent).to(beCloseTo(0.6, within: 0.0001))
  }

  func testDisablingOverdriveClampsRPMBeyondTheRestoredRangeTo100Percent() {
    // 80% of a 0...10000 Overdrive range commands 8000 RPM, which exceeds
    // the restored 0...6000 range, so the point clamps to 100%.
    let rescaler = CurveRPMRangeRescaler(
      oldRange: (min: 0, max: 10_000),
      newRange: (min: 0, max: 6_000)
    )

    let rescaled = rescaler.rescale([point(percent: 0.8)])

    expect(rescaled[0].fanPercent) == 1.0
  }

  func testZeroPercentPointsStayAtTheFloorRegardlessOfRangeChange() {
    // FanCommandMapping treats 0% as a floor marker, not an interpolated
    // RPM: Underdrive off commands the reported minimum RPM, Underdrive on
    // commands true 0. Moving a 0% point onto some above-zero percent to
    // "hold" its prior RPM would erase that floor, defeating the entire
    // purpose of the Underdrive toggle. This case must stay untouched even
    // when the old minimum RPM was nonzero.
    let rescaler = CurveRPMRangeRescaler(
      oldRange: (min: 1_200, max: 6_000),
      newRange: (min: 0, max: 6_000)
    )

    let rescaled = rescaler.rescale([point(percent: 0)])

    expect(rescaled[0].fanPercent) == 0
  }

  func testUnchangedRangeLeavesPercentsUntouched() {
    let rescaler = CurveRPMRangeRescaler(
      oldRange: (min: 0, max: 6_000),
      newRange: (min: 0, max: 6_000)
    )

    let rescaled = rescaler.rescale([point(percent: 0.5)])

    expect(rescaled[0].fanPercent) == 0.5
  }

  private func point(percent: Double) -> CurvePoint {
    CurvePoint(temperature: 80, fanPercent: percent)
  }
}
