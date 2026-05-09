//
//  TemperatureAxisScaleTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-01.
//  Copyright © 2026
//

import Nimble
import XCTest

@testable import FanCurveModels

final class TemperatureAxisScaleTests: XCTestCase {
    private let scale = TemperatureAxisScale.fanCurveDefault

    func testDefaultControlPointTemperaturesCompressLowRangeAndDensifyHotRange() {
        expect(self.scale.controlPointTemperaturesC) == [35, 65, 78, 88, 97, 105, 112, 120]

        let controlPointSpans = zip(
            self.scale.controlPointTemperaturesC,
            self.scale.controlPointTemperaturesC.dropFirst()
        )
        .map { leftTemperature, rightTemperature in rightTemperature - leftTemperature }

        expect(controlPointSpans.first) == 30
        expect(controlPointSpans.dropFirst().max()) == 13
        expect(controlPointSpans.last) == 8
    }

    func testDefaultScaleRoundTripsRepresentativeTemperatures() {
        for temperature in [35.0, 60, 65, 75, 80, 90, 100, 110, 120] {
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
        let controlPointFractions = self.scale.controlPointTemperaturesC.map { self.scale.fraction(for: $0) }

        expect(controlPointFractions.count) == 8
        for (index, fraction) in controlPointFractions.enumerated() {
            let expectedFraction = Double(index) / Double(controlPointFractions.count - 1)
            expect(fraction).to(beCloseTo(expectedFraction, within: 0.001))
        }
    }

    func testDefaultTicksIncludeRegularMajorAndMinorCandidates() {
        expect(self.scale.majorTickTemperaturesC) == [35, 40, 50, 60, 70, 80, 90, 100, 110, 120]

        expect(self.scale.majorTickTemperaturesC).to(contain(40))
        expect(self.scale.minorTickTemperaturesC).to(contain(117.5))
        expect(self.scale.minorTickTemperaturesC).to(contain(102.5))
        expect(self.scale.minorTickTemperaturesC).to(contain(75))
    }
}
