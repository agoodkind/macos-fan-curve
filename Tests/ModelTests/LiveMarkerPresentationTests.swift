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
    func testDemandPercentRiseTracksSemanticTargetImmediately() {
        let presented = LiveMarkerPresentation.presentDemandPercent(
            currentPercent: 0.23,
            proposedPercent: 0.50,
            alpha: 0.10,
            maximumStep: 0.007
        )

        expect(presented).to(beCloseTo(0.50, within: 0.001))
    }

    func testDemandPercentFallRemainsDamped() {
        let presented = LiveMarkerPresentation.presentDemandPercent(
            currentPercent: 0.50,
            proposedPercent: 0.23,
            alpha: 0.10,
            maximumStep: 0.007
        )

        expect(presented).to(beCloseTo(0.493, within: 0.001))
    }

    func testCurveDemandUsesBaseCurveAnchorAndActualFanPercent() {
        let target = LiveMarkerPresentation.makeTarget(
            from: LiveMarkerPresentation.TargetInput(
                snapshotEpoch: 1,
                curveActive: true,
                boostEnabled: false,
                governingTemperatureC: 72,
                committedTemperatureC: 71,
                rawPressureTemperatureC: 72,
                semanticDemandTemperatureC: 72,
                baseCurvePercent: 0.25,
                semanticDemandPercent: 0.25,
                commandedTargetPercent: 0.25,
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
                previewPercent: 0.25,
                fanTemperatureC: nil
            )
        )

        expect(target?.values.fanTemperatureC) == 72
        expect(target?.values.fanPercent).to(beCloseTo(0.5, within: 0.001))
        expect(target?.values.demandPercent).to(beCloseTo(0.25, within: 0.001))
        expect(target?.values.demandBasePercent).to(beCloseTo(0.25, within: 0.001))
    }

    func testAssistDemandCanRenderAboveBaseCurveAnchor() {
        let target = LiveMarkerPresentation.makeTarget(
            from: LiveMarkerPresentation.TargetInput(
                snapshotEpoch: 1,
                curveActive: true,
                boostEnabled: false,
                governingTemperatureC: 72,
                committedTemperatureC: 71,
                rawPressureTemperatureC: 72,
                semanticDemandTemperatureC: 72,
                baseCurvePercent: 0.25,
                semanticDemandPercent: 0.55,
                commandedTargetPercent: 0.55,
                rawBaselinePercent: 0.55,
                fans: [],
                rpmRange: (min: 2_000, max: 6_000),
                previewPercent: 0.25,
                fanTemperatureC: nil
            )
        )

        expect(target?.values.demandTemperatureC) == 72
        expect(target?.values.demandPercent).to(beCloseTo(0.55, within: 0.001))
        expect(target?.values.demandBasePercent).to(beCloseTo(0.25, within: 0.001))
    }

    func testDemandUsesSemanticStreamWhenCommandedTargetLags() {
        let target = LiveMarkerPresentation.makeTarget(
            from: LiveMarkerPresentation.TargetInput(
                snapshotEpoch: 1,
                curveActive: true,
                boostEnabled: false,
                governingTemperatureC: 92,
                committedTemperatureC: 88,
                rawPressureTemperatureC: 92,
                semanticDemandTemperatureC: 92,
                baseCurvePercent: 0.40,
                semanticDemandPercent: 0.90,
                commandedTargetPercent: 0.62,
                rawBaselinePercent: 0.90,
                fans: [],
                rpmRange: (min: 2_000, max: 6_000),
                previewPercent: 0.40,
                fanTemperatureC: nil
            )
        )

        expect(target?.values.demandTemperatureC) == 92
        expect(target?.values.demandPercent).to(beCloseTo(0.90, within: 0.001))
        expect(target?.values.fanPercent).to(beCloseTo(0.62, within: 0.001))
    }
}
