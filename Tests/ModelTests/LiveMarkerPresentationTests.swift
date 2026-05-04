//
//  LiveMarkerPresentationTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-01.
//  Copyright © 2026
//

import Nimble
import XCTest

@testable import FanCurveModels

final class LiveMarkerPresentationTests: XCTestCase {
    func testCurveDemandUsesBaseCurveAnchorAndActualFanPercent() {
        let target = LiveMarkerTargetFactory.make(
            snapshotEpoch: 1,
            curveActive: true,
            boostEnabled: false,
            governingTemperatureC: 72,
            committedTemperatureC: 71,
            rawPressureTemperatureC: 72,
            thermalDemandTemperatureC: 72,
            baseCurvePercent: 0.25,
            thermalDemandPercent: 0.25,
            committedPercent: 0.25,
            rawBaselinePercent: 0.25,
            fans: [
                AgentFanSnapshot(
                    index: 0,
                    actualRPM: 4_000,
                    targetRPM: 4_000,
                    minRPM: 2_000,
                    maxRPM: 6_000,
                    manualMode: true)
            ],
            rpmRange: (min: 2_000, max: 6_000),
            previewPercent: 0.25)

        expect(target?.values.fanTemperatureC).to(equal(72))
        expect(target?.values.fanPercent).to(beCloseTo(0.5, within: 0.001))
        expect(target?.values.demandPercent).to(beCloseTo(0.25, within: 0.001))
        expect(target?.values.demandBasePercent).to(beCloseTo(0.25, within: 0.001))
    }

    func testAssistDemandCanRenderAboveBaseCurveAnchor() {
        let target = LiveMarkerTargetFactory.make(
            snapshotEpoch: 1,
            curveActive: true,
            boostEnabled: false,
            governingTemperatureC: 72,
            committedTemperatureC: 71,
            rawPressureTemperatureC: 72,
            thermalDemandTemperatureC: 72,
            baseCurvePercent: 0.25,
            thermalDemandPercent: 0.55,
            committedPercent: 0.55,
            rawBaselinePercent: 0.55,
            fans: [],
            rpmRange: (min: 2_000, max: 6_000),
            previewPercent: 0.25)

        expect(target?.values.demandTemperatureC).to(equal(72))
        expect(target?.values.demandPercent).to(beCloseTo(0.55, within: 0.001))
        expect(target?.values.demandBasePercent).to(beCloseTo(0.25, within: 0.001))
    }
}
