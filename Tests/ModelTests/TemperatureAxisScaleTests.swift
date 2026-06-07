//
//  TemperatureAxisScaleTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-01.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class TemperatureAxisScaleTests: XCTestCase {
  private let scale = TemperatureAxisScale.fanCurveDefault

  func testDefaultControlPointTemperaturesCompressLowRangeAndDensifyHotRange() {
    expect(self.scale.controlPointTemperaturesC) == [35, 78, 84, 90, 96, 101, 106, 110]

    let controlPointSpans = zip(
      self.scale.controlPointTemperaturesC,
      self.scale.controlPointTemperaturesC.dropFirst()
    )
    .map { leftTemperature, rightTemperature in rightTemperature - leftTemperature }

    expect(controlPointSpans.first) == 43
    expect(controlPointSpans.dropFirst().max()) == 6
    expect(controlPointSpans.last) == 4
    expect(Array(controlPointSpans.dropFirst())) == [6, 6, 6, 5, 5, 4]
  }

  func testDefaultScaleRoundTripsRepresentativeTemperatures() {
    for temperature in [35.0, 50, 65, 70, 78, 90, 100, 106, 110] {
      let fraction = self.scale.fraction(for: temperature)
      let roundTrippedTemperature = self.scale.temperatureC(at: fraction)
      expect(roundTrippedTemperature).to(beCloseTo(temperature, within: 0.05))
    }
  }

  func testCurveColumnsUseSharedAxisScale() {
    expect(CurveColumns.tempRange.lowerBound) == self.scale.temperatureRangeC.lowerBound
    expect(CurveColumns.tempRange.upperBound) == self.scale.temperatureRangeC.upperBound
    expect(CurveColumns.temperatures()) == self.scale.controlPointTemperaturesC
  }

  func testDefaultControlPointsAreEvenlySpacedOnAxis() {
    let controlPointFractions = self.scale.controlPointTemperaturesC.map { temperature in
      self.scale.fraction(for: temperature)
    }

    expect(controlPointFractions.count) == 8
    for (index, fraction) in controlPointFractions.enumerated() {
      let expectedFraction = Double(index) / Double(controlPointFractions.count - 1)
      expect(fraction).to(beCloseTo(expectedFraction, within: 0.001))
    }
  }

  func testDefaultTicksIncludeRegularMajorAndMinorCandidates() {
    expect(self.scale.majorTickTemperaturesC) == [35, 40, 50, 60, 70, 80, 90, 100, 110]

    expect(self.scale.majorTickTemperaturesC).to(contain(40))
    expect(self.scale.minorTickTemperaturesC).to(contain(107.5))
    expect(self.scale.minorTickTemperaturesC).to(contain(102.5))
    expect(self.scale.minorTickTemperaturesC).to(contain(75))
  }
}
