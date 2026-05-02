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

    func testDefaultScaleExpandsTowardReversalCenterAndCompressesTails() {
        let coldTailGap = self.scale.fraction(for: 30) - self.scale.fraction(for: 20)
        let nearCenterLeftGap = self.scale.fraction(for: 80) - self.scale.fraction(for: 70)
        let nearCenterRightGap = self.scale.fraction(for: 90) - self.scale.fraction(for: 80)
        let hotTailGap = self.scale.fraction(for: 110) - self.scale.fraction(for: 100)

        expect(nearCenterLeftGap).to(beGreaterThan(coldTailGap))
        expect(nearCenterRightGap).to(beGreaterThan(hotTailGap))
        expect(self.scale.fraction(for: 80)).to(beCloseTo(2.0 / 3.0, within: 0.001))
    }

    func testDefaultScaleRoundTripsRepresentativeTemperatures() {
        for temperature in [20.0, 60, 70, 75, 80, 90, 100, 110] {
            let fraction = self.scale.fraction(for: temperature)
            let roundTrippedTemperature = self.scale.temperatureC(at: fraction)
            expect(roundTrippedTemperature).to(beCloseTo(temperature, within: 0.05))
        }
    }

    func testCurveColumnsUseSharedAxisScale() {
        expect(CurveColumns.tempRange.lowerBound).to(equal(self.scale.temperatureRangeC.lowerBound))
        expect(CurveColumns.tempRange.upperBound).to(equal(self.scale.temperatureRangeC.upperBound))
        expect(CurveColumns.temperatures()).to(equal(self.scale.controlPointTemperaturesC))
    }

    func testDefaultControlPointsAreEvenlySpacedOnAxis() {
        let controlPointFractions = self.scale.controlPointTemperaturesC.map { self.scale.fraction(for: $0) }

        expect(controlPointFractions.count).to(equal(8))
        for (index, fraction) in controlPointFractions.enumerated() {
            let expectedFraction = Double(index) / Double(controlPointFractions.count - 1)
            expect(fraction).to(beCloseTo(expectedFraction, within: 0.001))
        }
    }

    func testDefaultTicksIncludeRegularMajorAndMinorCandidates() {
        expect(self.scale.majorTickTemperaturesC).to(equal([20, 30, 40, 50, 60, 70, 80, 90, 100, 110]))

        expect(self.scale.majorTickTemperaturesC).to(contain(40))
        expect(self.scale.minorTickTemperaturesC).to(contain(102.5))
        expect(self.scale.minorTickTemperaturesC).to(contain(75))
        expect(self.scale.minorTickTemperaturesC).to(contain(107.5))
    }
}
