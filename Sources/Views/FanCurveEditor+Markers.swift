//
//  FanCurveEditor+Markers.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026
//

import SwiftUI

extension FanCurveEditor {
    var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if model.isActive {
                Circle()
                    .fill(Color(nsColor: .systemGreen))
                    .frame(width: 6, height: 6)
                Text("Fans are following this curve")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 6, height: 6)
                Text("Preview only. Turn on Fan Control to apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    func currentPositionOverlay(
        size: CGSize,
        values: LiveMarkerPresentation.Values?
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if let geometry = runtimeMarkerGeometry(size: size, values: values) {
                RuntimeMarkerOverlay(geometry: geometry)
                    .animation(runtimeMarkerAnimation, value: geometry)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    func runtimeMarkerGeometry(
        size: CGSize,
        values: LiveMarkerPresentation.Values?
    ) -> RuntimeMarkerOverlay.Geometry? {
        guard let values else { return nil }
        let fanTemperature = values.fanTemperatureC
        let demandTemperature = values.demandTemperatureC
        guard fanTemperature > 0, demandTemperature > 0 else { return nil }

        let fanPosition = dataToPixel(
            temp: fanTemperature,
            percent: values.fanPercent,
            in: size
        )
        let demandPercent = max(0, min(1, values.demandPercent))
        let demandPosition = dataToPixel(
            temp: demandTemperature,
            percent: demandPercent,
            in: size
        )
        let clampedDemandPosition = CGPoint(
            x: demandPosition.x,
            y: max(topPad + 10, min(size.height - bottomPad - 10, demandPosition.y))
        )

        return RuntimeMarkerOverlay.Geometry(
            size: size,
            fanPosition: fanPosition,
            demandPosition: clampedDemandPosition,
            zeroY: dataToPixel(temp: 20, percent: 0, in: size).y,
            plotLeft: leftPad
        )
    }

    func refreshRuntimeMarkerTarget() {
        let semanticTarget = runtimeMarkerTarget()
        let nextTarget = demandPresentationTarget(from: semanticTarget)
        if nextTarget != markerPresenterTarget {
            fanCurveEditorLog.debug(
                "curve_editor.marker_target.changed active=\(runtime.curveActive, privacy: .public)"
            )
        }
        markerPresenterTarget = nextTarget
    }

    func demandPresentationTarget(
        from semanticTarget: LiveMarkerPresentation.Target?
    ) -> LiveMarkerPresentation.Target? {
        guard var semanticTarget else {
            previousMarkerGeneration = nil
            return nil
        }

        guard
            let currentTarget = markerPresenterTarget,
            isSameMarkerPresentationContext(semanticTarget.generation, currentTarget.generation)
        else {
            previousMarkerGeneration = semanticTarget.generation
            return semanticTarget
        }

        semanticTarget.values.fanTemperatureC = dampedMarkerTarget(
            currentTarget: currentTarget.values.fanTemperatureC,
            proposedTarget: semanticTarget.values.fanTemperatureC,
            alpha: fanPresentationTemperatureAlpha,
            maximumStep: fanPresentationMaxTemperatureStepC
        )
        semanticTarget.values.demandTemperatureC = dampedMarkerTarget(
            currentTarget: currentTarget.values.demandTemperatureC,
            proposedTarget: semanticTarget.values.demandTemperatureC,
            alpha: demandPresentationTemperatureAlpha,
            maximumStep: demandPresentationMaxTemperatureStepC
        )
        semanticTarget.values.demandPercent = LiveMarkerPresentation.presentDemandPercent(
            currentPercent: currentTarget.values.demandPercent,
            proposedPercent: semanticTarget.values.demandPercent,
            alpha: demandPresentationPercentAlpha,
            maximumStep: demandPresentationMaxPercentStep
        )
        semanticTarget.values.demandBasePercent = dampedMarkerTarget(
            currentTarget: currentTarget.values.demandBasePercent,
            proposedTarget: semanticTarget.values.demandBasePercent,
            alpha: demandPresentationPercentAlpha,
            maximumStep: demandPresentationMaxPercentStep
        )
        previousMarkerGeneration = semanticTarget.generation
        return semanticTarget
    }

    func isSameMarkerPresentationContext(
        _ lhs: LiveMarkerPresentation.Target.Generation,
        _ rhs: LiveMarkerPresentation.Target.Generation
    ) -> Bool {
        lhs.curveActive == rhs.curveActive
            && lhs.boostEnabled == rhs.boostEnabled
            && lhs.fanSignature == rhs.fanSignature
            && lhs.rpmRangeMin == rhs.rpmRangeMin
            && lhs.rpmRangeMax == rhs.rpmRangeMax
    }

    func dampedMarkerTarget(
        currentTarget: Double,
        proposedTarget: Double,
        alpha: Double,
        maximumStep: Double
    ) -> Double {
        let delta = proposedTarget - currentTarget
        let easedStep = delta * max(0, min(1, alpha))
        let clampedStep = max(-maximumStep, min(maximumStep, easedStep))
        return currentTarget + clampedStep
    }

    func runtimeMarkerTarget() -> LiveMarkerPresentation.Target? {
        guard runtime.isFresh else { return nil }

        let liveTemperature =
            runtime.semanticDemandTemperature
            ?? runtime.rawPressureTemperature
            ?? (runtime.committedTemperature > 0 ? runtime.committedTemperature : runtime.governingTemperature)
        guard liveTemperature > 0 else { return nil }

        let clampedTemperature = max(plotTempRange.lowerBound, min(plotTempRange.upperBound, liveTemperature))
        let previewPercent = CurveInterpolation.evaluate(
            at: clampedTemperature,
            points: model.controlPoints,
            mode: model.interpolationMode
        )
        return LiveMarkerPresentation.makeTarget(
            from: LiveMarkerPresentation.TargetInput(
                snapshotEpoch: runtime.snapshot?.timestampEpoch ?? 0,
                curveActive: runtime.curveActive,
                boostEnabled: runtime.boostEnabled,
                governingTemperatureC: runtime.governingTemperature,
                committedTemperatureC: runtime.committedTemperature,
                rawPressureTemperatureC: runtime.rawPressureTemperature,
                semanticDemandTemperatureC: clampedTemperature,
                baseCurvePercent: runtime.curveActive ? runtime.baseCurvePercent : previewPercent,
                semanticDemandPercent: runtime.semanticDemandPercent,
                commandedTargetPercent: runtime.commandedTargetPercent,
                rawBaselinePercent: runtime.rawBaselinePercent,
                fans: runtime.fans,
                rpmRange: rpmRange,
                previewPercent: previewPercent,
                fanTemperatureC: nil
            )
        )
    }

    var chartLegendOverlay: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    legendItem(
                        fill: Color(nsColor: .systemOrange),
                        stroke: nil,
                        label: "Fan Now"
                    )
                    legendItem(
                        fill: Color(nsColor: .windowBackgroundColor).opacity(0.96),
                        stroke: Color(nsColor: .systemOrange).opacity(0.58),
                        label: "Thermal Demand"
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .fancurveGlassPill(
                    in: Capsule(),
                    fallbackFill: Color(nsColor: .windowBackgroundColor).opacity(0.92)
                )
            }
            Spacer()
        }
        .padding(.top, 10)
        .padding(.trailing, 12)
        .allowsHitTesting(false)
    }

    func legendItem(fill: Color, stroke: Color?, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(fill)
                .overlay(
                    Circle().stroke(stroke ?? .clear, lineWidth: stroke == nil ? 0 : 1.25)
                )
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
