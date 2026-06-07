//
//  CurveInterpolationTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class CurveInterpolationTests: XCTestCase {

  private let testPoints: [CurvePoint] = [
    CurvePoint(temperature: 30, fanPercent: 0.0),
    CurvePoint(temperature: 55, fanPercent: 0.3),
    CurvePoint(temperature: 75, fanPercent: 0.5),
    CurvePoint(temperature: 100, fanPercent: 1.0),
  ]

  func testLinear_BelowRange() {
    let result = CurveInterpolation.linear(at: 20, points: testPoints)
    expect(result).to(beCloseTo(0.0, within: 0.01))
  }

  func testLinear_AboveRange() {
    let result = CurveInterpolation.linear(at: 110, points: testPoints)
    expect(result).to(beCloseTo(1.0, within: 0.01))
  }

  func testLinear_AtControlPoint() {
    let result = CurveInterpolation.linear(at: 55, points: testPoints)
    expect(result).to(beCloseTo(0.3, within: 0.01))
  }

  func testLinear_Midpoint() {
    let result = CurveInterpolation.linear(at: 42.5, points: testPoints)
    expect(result).to(beCloseTo(0.15, within: 0.01))
  }

  func testLinear_EmptyPoints() {
    let result = CurveInterpolation.linear(at: 50, points: [])
    expect(result) == 0.0
  }

  func testLinear_OutputClamped() {
    let badPoints = [
      CurvePoint(temperature: 30, fanPercent: -0.5),
      CurvePoint(temperature: 100, fanPercent: 1.5),
    ]
    let low = CurveInterpolation.linear(at: 30, points: badPoints)
    let high = CurveInterpolation.linear(at: 100, points: badPoints)
    expect(low).to(beCloseTo(0.0, within: 0.01))
    expect(high).to(beCloseTo(1.0, within: 0.01))
  }

  func testCatmullRom_AtControlPoint() {
    let result = CurveInterpolation.catmullRom(at: 55, points: testPoints)
    expect(result).to(beCloseTo(0.3, within: 0.001))
  }

  func testCatmullRom_OutputClamped() {
    let result = CurveInterpolation.catmullRom(at: 50, points: testPoints)
    expect(result) >= 0.0
    expect(result) <= 1.0
  }

  func testCatmullRom_UsesAxisFractionBetweenControlPoints() {
    let scale = TemperatureAxisScale.fanCurveDefault
    let points = [
      CurvePoint(temperature: scale.temperatureC(at: 0.0), fanPercent: 0.2),
      CurvePoint(temperature: scale.temperatureC(at: 0.5), fanPercent: 0.6),
      CurvePoint(temperature: scale.temperatureC(at: 1.0), fanPercent: 1.0),
    ]

    let result = CurveInterpolation.catmullRom(at: scale.temperatureC(at: 0.25), points: points)
    expect(result).to(beCloseTo(0.4, within: 0.001))
  }

  func testCatmullRom_SmoothsFlatShelfRiseWithoutOvershoot() {
    let shelfPoints = [
      CurvePoint(temperature: 35, fanPercent: 0.0),
      CurvePoint(temperature: 50, fanPercent: 0.0),
      CurvePoint(temperature: 70, fanPercent: 0.2),
      CurvePoint(temperature: 80, fanPercent: 0.7),
      CurvePoint(temperature: 120, fanPercent: 1.0),
    ]

    var previousPercent = CurveInterpolation.catmullRom(at: 50, points: shelfPoints)
    for temperature in stride(from: 52.5, through: 80.0, by: 2.5) {
      let percent = CurveInterpolation.catmullRom(at: temperature, points: shelfPoints)
      expect(percent) >= previousPercent - 0.001
      expect(percent) >= 0.0
      expect(percent) <= 0.7
      previousPercent = percent
    }
  }

  func testCatmullRom_ClampsControlPointOutputs() {
    let badPoints = [
      CurvePoint(temperature: 30, fanPercent: -0.5),
      CurvePoint(temperature: 100, fanPercent: 1.5),
    ]
    let low = CurveInterpolation.catmullRom(at: 30, points: badPoints)
    let high = CurveInterpolation.catmullRom(at: 100, points: badPoints)
    expect(low).to(beCloseTo(0.0, within: 0.001))
    expect(high).to(beCloseTo(1.0, within: 0.001))
  }

  func testCatmullRom_DoesNotDipOrOvershootCascadedPoints() {
    let cascadedPoints = [
      CurvePoint(temperature: 35, fanPercent: 0.0),
      CurvePoint(temperature: 50, fanPercent: 0.0),
      CurvePoint(temperature: 65, fanPercent: 0.65),
      CurvePoint(temperature: 80, fanPercent: 0.65),
      CurvePoint(temperature: 95, fanPercent: 0.82),
      CurvePoint(temperature: 120, fanPercent: 1.0),
    ]

    var previousPercent = 0.0
    for temperature in stride(from: 35.0, through: 120.0, by: 2.5) {
      let percent = CurveInterpolation.catmullRom(at: temperature, points: cascadedPoints)
      expect(percent) >= previousPercent - 0.001
      expect(percent) >= 0.0
      expect(percent) <= 1.0
      previousPercent = percent
    }
  }

  func testCatmullRom_KeepsFlatShelvesFlat() {
    let shelfPoints = [
      CurvePoint(temperature: 50, fanPercent: 0.2),
      CurvePoint(temperature: 70, fanPercent: 0.55),
      CurvePoint(temperature: 90, fanPercent: 0.55),
      CurvePoint(temperature: 110, fanPercent: 0.9),
    ]

    let midShelf = CurveInterpolation.catmullRom(at: 80, points: shelfPoints)
    expect(midShelf).to(beCloseTo(0.55, within: 0.001))
  }

  func testCatmullRom_FallsBackToLinearOutsideFanTemperatureAxisWithoutInjectedAxis() {
    let loadAssistPoints = [
      CurvePoint(temperature: 0, fanPercent: 0.1),
      CurvePoint(temperature: 100, fanPercent: 0.7),
    ]

    let result = CurveInterpolation.catmullRom(at: 50, points: loadAssistPoints)
    expect(result).to(beCloseTo(0.4, within: 0.001))
  }

  func testCatmullRom_UsesInjectedLinearAxisForLoadAssistSmoothing() {
    let loadAssistPoints = [
      CurvePoint(temperature: 0, fanPercent: 0.0),
      CurvePoint(temperature: 55, fanPercent: 0.0),
      CurvePoint(temperature: 70, fanPercent: 0.6),
      CurvePoint(temperature: 100, fanPercent: 0.6),
    ]

    let axisScale = CurveAxisScale.linear(range: LoadAssistCurveColumns.xRange)
    let result = CurveInterpolation.catmullRom(
      at: 62.5,
      points: loadAssistPoints,
      axisScale: axisScale
    )

    expect(result) > 0.0
    expect(result) < 0.6
  }

  func testEvaluate_DispatchesCorrectly() {
    let linear = CurveInterpolation.evaluate(at: 42.5, points: testPoints, mode: .linear)
    let catmull = CurveInterpolation.evaluate(at: 42.5, points: testPoints, mode: .catmullRom)
    expect(linear) >= 0.0
    expect(catmull) >= 0.0
    expect(linear) <= 1.0
    expect(catmull) <= 1.0
  }

  func testLocalResponseDetectsFlatCurveRegion() {
    let points = [
      CurvePoint(temperature: 40, fanPercent: 0.2),
      CurvePoint(temperature: 60, fanPercent: 0.2),
      CurvePoint(temperature: 80, fanPercent: 0.2),
    ]

    let response = CurveInterpolation.localResponse(at: 60, points: points, mode: .linear)

    expect(response.value).to(beCloseTo(0.0, within: 0.001))
  }

  func testLocalResponseDetectsModerateCurveRegion() {
    let points = [
      CurvePoint(temperature: 40, fanPercent: 0.2),
      CurvePoint(temperature: 60, fanPercent: 0.48),
      CurvePoint(temperature: 80, fanPercent: 0.76),
    ]

    let response = CurveInterpolation.localResponse(at: 60, points: points, mode: .linear)

    expect(response.value).to(beCloseTo(0.43, within: 0.02))
  }

  func testLocalResponseDetectsSteepCurveRegion() {
    let points = [
      CurvePoint(temperature: 40, fanPercent: 0.2),
      CurvePoint(temperature: 60, fanPercent: 0.8),
      CurvePoint(temperature: 80, fanPercent: 1.0),
    ]

    let response = CurveInterpolation.localResponse(at: 50, points: points, mode: .linear)

    expect(response.value).to(beCloseTo(1.0, within: 0.001))
  }

  func testPathPoints_GeneratesCorrectCount() {
    let points = CurveInterpolation.pathPoints(
      points: testPoints, mode: .linear, tempRange: 20...110, steps: 50)
    expect(points.count) == 51
  }

  func testPathPoints_UseInjectedAxisForLoadAssistCurve() {
    let loadAssistPoints = [
      CurvePoint(temperature: 0, fanPercent: 0.0),
      CurvePoint(temperature: 55, fanPercent: 0.0),
      CurvePoint(temperature: 70, fanPercent: 0.6),
      CurvePoint(temperature: 100, fanPercent: 0.6),
    ]

    let points = CurveInterpolation.pathPoints(
      points: loadAssistPoints,
      mode: .catmullRom,
      tempRange: LoadAssistCurveColumns.xRange,
      steps: 50,
      axisScale: .linear(range: LoadAssistCurveColumns.xRange)
    )

    let midpoint = points[points.count / 2]
    expect(midpoint.temperature).to(beCloseTo(50, within: 1.0))
    expect(midpoint.fanPercent) < 0.6
  }
}
