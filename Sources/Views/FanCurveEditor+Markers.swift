//
//  FanCurveEditor+Markers.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

// MARK: - Marker layout and style constants

private enum MarkerConstants {
  // Fan Now dot (filled orange dot with crosshair)
  static let fanDot: CGFloat = 10
  static let fanFillOn: Double = 1.0
  static let fanFillOff: Double = 0.52
  static let fanShadowOn: Double = 0.5
  static let fanShadowOff: Double = 0.16
  static let fanShadowRadOn: CGFloat = 6
  static let fanShadowRadOff: CGFloat = 2

  // Thermal Demand dot (hollow orange dot, no crosshair)
  static let demandDot: CGFloat = 9
  static let demandBg: Double = 0.96
  static let demandStroke: Double = 0.58
  static let demandStrokeW: CGFloat = 1.4
  static let demandShadow: Double = 0.12
  static let demandShadowRad: CGFloat = 2

  // Crosshair guide stroke (Fan Now guides)
  static let crossOn: Double = 0.25
  static let crossOff: Double = 0.18
  static let crossDashOn: CGFloat = 4
  static let crossDashOff: CGFloat = 4

  // Demand leash stroke
  static let leashOn: Double = 0.24
  static let leashOff: Double = 0.2
  static let leashDashOn: CGFloat = 2
  static let leashDashOff: CGFloat = 3

  // Demand position vertical clamp inset from plot edges
  static let demandPositionEdgeInset: CGFloat = 10

  // Reference temperature for the zero-percent Y coordinate (°C)
  static let zeroPercentReferenceTemperatureC: Double = 20

  // Legend pill
  static let legendItemSpacing: CGFloat = 12
  static let legendDotDiameter: CGFloat = 8
  static let legendDotSpacing: CGFloat = 5
  static let legendDotStrokeLineWidth: CGFloat = 1.25
  static let legendPillHorizontalPadding: CGFloat = 10
  static let legendPillVerticalPadding: CGFloat = 6
  static let legendPillBackgroundOpacity: Double = 0.92
  static let legendTopPadding: CGFloat = 10
  static let legendTrailingPadding: CGFloat = 12

  // Shared opacity used in both the legend and the marker ring
  static let inactiveSecondaryOpacity: Double = 0.52
}

extension FanCurveEditor {
  func currentPositionOverlay(
    size: CGSize,
    values: LiveMarkerPresentation.Values?
  ) -> some View {
    ZStack(alignment: .topLeading) {
      if let geometry = runtimeMarkerGeometry(size: size, values: values) {
        runtimeMarkerOverlay(geometry: geometry)
          .animation(
            renderMode.allowsLiveAnimation ? runtimeMarkerAnimation : nil,
            value: geometry
          )
      }
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .allowsHitTesting(false)
  }

  func runtimeMarkerOverlay(geometry: RuntimeMarkerOverlay.Geometry) -> some View {
    let active = presentation.usesActiveMarkerStyling
    let markerColor = active ? Color(nsColor: .systemOrange) : Color.secondary
    let crossOpacity = active ? MarkerConstants.crossOn : MarkerConstants.crossOff
    let leashOpacity = active ? MarkerConstants.leashOn : MarkerConstants.leashOff
    let crossColor = markerColor.opacity(crossOpacity)
    let leashColor = markerColor.opacity(leashOpacity)
    return ZStack(alignment: .topLeading) {
      FanNowGuidesShape(geometry: geometry)
        .stroke(
          crossColor,
          style: StrokeStyle(
            lineWidth: 1,
            dash: [MarkerConstants.crossDashOn, MarkerConstants.crossDashOff]
          )
        )

      DemandLeashShape(geometry: geometry)
        .stroke(
          leashColor,
          style: StrokeStyle(
            lineWidth: 1,
            dash: [MarkerConstants.leashDashOn, MarkerConstants.leashDashOff]
          )
        )

      thermalDemandDot(markerColor: markerColor).position(geometry.demandPosition)
      fanNowDot(markerColor: markerColor, active: active).position(geometry.fanPosition)
    }
    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
    .allowsHitTesting(false)
  }

  private func thermalDemandDot(markerColor: Color) -> some View {
    Circle()
      .fill(Color(nsColor: .windowBackgroundColor).opacity(MarkerConstants.demandBg))
      .overlay(
        Circle().stroke(
          markerColor.opacity(MarkerConstants.demandStroke),
          lineWidth: MarkerConstants.demandStrokeW
        )
      )
      .frame(width: MarkerConstants.demandDot, height: MarkerConstants.demandDot)
      .shadow(
        color: markerColor.opacity(MarkerConstants.demandShadow),
        radius: MarkerConstants.demandShadowRad
      )
  }

  private func fanNowDot(markerColor: Color, active: Bool) -> some View {
    let fillOpacity = active ? MarkerConstants.fanFillOn : MarkerConstants.fanFillOff
    return Circle()
      .fill(markerColor.opacity(fillOpacity))
      .frame(width: MarkerConstants.fanDot, height: MarkerConstants.fanDot)
      .shadow(
        color: markerColor.opacity(
          active ? MarkerConstants.fanShadowOn : MarkerConstants.fanShadowOff
        ),
        radius: active ? MarkerConstants.fanShadowRadOn : MarkerConstants.fanShadowRadOff
      )
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
      y: max(
        topPad + MarkerConstants.demandPositionEdgeInset,
        min(
          size.height - bottomPad - MarkerConstants.demandPositionEdgeInset,
          demandPosition.y
        )
      )
    )

    return RuntimeMarkerOverlay.Geometry(
      size: size,
      fanPosition: fanPosition,
      demandPosition: clampedDemandPosition,
      zeroY: dataToPixel(
        temp: MarkerConstants.zeroPercentReferenceTemperatureC,
        percent: 0,
        in: size
      ).y,
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
    guard presentation.showsRuntimeMarkers else { return nil }

    let liveTemperature =
      runtime.semanticDemandTemperature
      ?? runtime.rawPressureTemperature
      ?? (runtime.committedTemperature > 0
        ? runtime.committedTemperature : runtime.governingTemperature)
    guard liveTemperature > 0 else { return nil }

    let clampedTemperature = max(
      plotTempRange.lowerBound, min(plotTempRange.upperBound, liveTemperature))
    let previewPercent = CurveInterpolation.evaluate(
      at: clampedTemperature,
      points: model.controlPoints,
      mode: model.interpolationMode
    )
    return LiveMarkerPresentation.makeTarget(
      from: LiveMarkerPresentation.TargetInput(
        curveActive: presentation.usesActiveCurveStyling,
        boostEnabled: boostEnabled,
        governingTemperatureC: runtime.governingTemperature,
        committedTemperatureC: runtime.committedTemperature,
        rawPressureTemperatureC: runtime.rawPressureTemperature,
        semanticDemandTemperatureC: clampedTemperature,
        baseCurvePercent: presentation.usesActiveCurveStyling
          ? runtime.baseCurvePercent : previewPercent,
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
        HStack(spacing: MarkerConstants.legendItemSpacing) {
          legendItem(
            fill: presentation.usesActiveMarkerStyling
              ? Color(nsColor: .systemOrange)
              : Color.secondary.opacity(MarkerConstants.inactiveSecondaryOpacity),
            stroke: nil,
            label: "Fan Now"
          )
          legendItem(
            fill: Color(nsColor: .windowBackgroundColor)
              .opacity(MarkerConstants.demandBg),
            stroke: presentation.usesActiveMarkerStyling
              ? Color(nsColor: .systemOrange).opacity(MarkerConstants.demandStroke)
              : Color.secondary.opacity(MarkerConstants.demandStroke),
            label: "Thermal Demand"
          )
        }
        .padding(.horizontal, MarkerConstants.legendPillHorizontalPadding)
        .padding(.vertical, MarkerConstants.legendPillVerticalPadding)
        .fancurveGlassPill(
          in: Capsule(),
          fallbackFill: Color(nsColor: .windowBackgroundColor)
            .opacity(MarkerConstants.legendPillBackgroundOpacity)
        )
      }
      Spacer()
    }
    .padding(.top, MarkerConstants.legendTopPadding)
    .padding(.trailing, MarkerConstants.legendTrailingPadding)
    .allowsHitTesting(false)
  }

  func legendItem(fill: Color, stroke: Color?, label: String) -> some View {
    HStack(spacing: MarkerConstants.legendDotSpacing) {
      Circle()
        .fill(fill)
        .overlay(
          Circle().stroke(
            stroke ?? .clear,
            lineWidth: stroke == nil ? 0 : MarkerConstants.legendDotStrokeLineWidth
          )
        )
        .frame(
          width: MarkerConstants.legendDotDiameter,
          height: MarkerConstants.legendDotDiameter
        )
      Text(label)
        .font(.system(.caption2, design: .rounded).weight(.medium))
        .foregroundStyle(.secondary)
    }
  }
}
