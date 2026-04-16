//
//  CurveInterpolationTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import XCTest

@testable import FanCurveModels

final class CurveInterpolationTests: XCTestCase {

  let testPoints: [CurvePoint] = [
    CurvePoint(temperature: 30, fanPercent: 0.0),
    CurvePoint(temperature: 55, fanPercent: 0.3),
    CurvePoint(temperature: 75, fanPercent: 0.5),
    CurvePoint(temperature: 100, fanPercent: 1.0),
  ]

  func testLinear_BelowRange() {
    let result = CurveInterpolation.linear(at: 20, points: testPoints)
    XCTAssertEqual(result, 0.0, accuracy: 0.01)
  }

  func testLinear_AboveRange() {
    let result = CurveInterpolation.linear(at: 110, points: testPoints)
    XCTAssertEqual(result, 1.0, accuracy: 0.01)
  }

  func testLinear_AtControlPoint() {
    let result = CurveInterpolation.linear(at: 55, points: testPoints)
    XCTAssertEqual(result, 0.3, accuracy: 0.01)
  }

  func testLinear_Midpoint() {
    let result = CurveInterpolation.linear(at: 42.5, points: testPoints)
    XCTAssertEqual(result, 0.15, accuracy: 0.01)
  }

  func testLinear_EmptyPoints() {
    let result = CurveInterpolation.linear(at: 50, points: [])
    XCTAssertEqual(result, 0.0)
  }

  func testLinear_OutputClamped() {
    let badPoints = [
      CurvePoint(temperature: 30, fanPercent: -0.5),
      CurvePoint(temperature: 100, fanPercent: 1.5),
    ]
    let low = CurveInterpolation.linear(at: 30, points: badPoints)
    let high = CurveInterpolation.linear(at: 100, points: badPoints)
    XCTAssertEqual(low, 0.0, accuracy: 0.01)
    XCTAssertEqual(high, 1.0, accuracy: 0.01)
  }

  func testCatmullRom_AtControlPoint() {
    let result = CurveInterpolation.catmullRom(at: 55, points: testPoints)
    XCTAssertEqual(result, 0.3, accuracy: 0.05)
  }

  func testCatmullRom_OutputClamped() {
    let result = CurveInterpolation.catmullRom(at: 50, points: testPoints)
    XCTAssertGreaterThanOrEqual(result, 0.0)
    XCTAssertLessThanOrEqual(result, 1.0)
  }

  func testEvaluate_DispatchesCorrectly() {
    let linear = CurveInterpolation.evaluate(at: 42.5, points: testPoints, mode: .linear)
    let catmull = CurveInterpolation.evaluate(at: 42.5, points: testPoints, mode: .catmullRom)
    XCTAssertGreaterThanOrEqual(linear, 0.0)
    XCTAssertGreaterThanOrEqual(catmull, 0.0)
    XCTAssertLessThanOrEqual(linear, 1.0)
    XCTAssertLessThanOrEqual(catmull, 1.0)
  }

  func testPathPoints_GeneratesCorrectCount() {
    let points = CurveInterpolation.pathPoints(
      points: testPoints, mode: .linear, tempRange: 20...110, steps: 50)
    XCTAssertEqual(points.count, 51)
  }
}
