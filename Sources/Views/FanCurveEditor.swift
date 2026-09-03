//
//  FanCurveEditor.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import SwiftUI

let fanCurveEditorLog = AppLog.make(category: "FanCurveEditor")

private enum FanCurveEditorConstants {
  // Layout padding insets
  static let topPad: CGFloat = 56
  static let bottomPad: CGFloat = 44
  static let leftPad: CGFloat = 72
  static let rightPad: CGFloat = 24

  // Control-point interaction
  static let controlPointHitRadius: CGFloat = 14

  // Card corner radius (shared by glass card and clip shape)
  static let cardCornerRadius: CGFloat = 12

  // Active-phase animation
  static let activePhaseAnimationDuration: Double = 0.35

  // Runtime marker animation
  static let runtimeMarkerAnimationDuration: Double = 1.4

  // Fan-now presentation smoothing
  static let fanPresentationTemperatureAlpha: Double = 0.06
  static let fanPresentationMaxTemperatureStepC: Double = 0.35

  // Thermal-demand presentation smoothing
  static let demandPresentationTemperatureAlpha: Double = 0.10
  static let demandPresentationPercentAlpha: Double = 0.10
  static let demandPresentationMaxTemperatureStepC: Double = 0.7
  static let demandPresentationMaxPercentStep: Double = 0.007

  // Fallback RPM range
  static let fallbackMaxRPM: Float = 8_000

  // Degraded-chart overlay layout
  static let degradedIconSize: CGFloat = 34
  static let degradedSpacing: CGFloat = 12
  static let degradedMaxWidth: CGFloat = 360
  static let degradedPadding: CGFloat = 32
}

struct FanCurveEditor: View {
  @ObservedObject var model: FanCurveModel
  @ObservedObject var runtime: FanCurveAgentClient
  let renderMode: AppRenderMode
  let presentation: DashboardPresentationState
  @State private var hoveredIndexState: Int?
  @State private var draggedIndexState: Int?
  @State private var dragBaselinePercentsState: [Double] = []
  @State private var mouseLocationState: CGPoint?
  @State private var markerPresenterTargetState: LiveMarkerPresentation.Target?
  @State private var previousMarkerGenerationState: LiveMarkerPresentation.Target.Generation?
  let controlPointHitRadius: CGFloat = FanCurveEditorConstants.controlPointHitRadius

  @AppStorage("temperatureUnit") var unitRaw: String = "celsius"

  var unit: TemperatureUnit {
    TemperatureUnit(rawValue: unitRaw) ?? .celsius
  }

  func displayTemp(_ celsius: Double) -> Int {
    Int(unit.convert(fromCelsius: celsius).rounded())
  }

  var hoveredIndex: Int? {
    get { hoveredIndexState }
    nonmutating set { hoveredIndexState = newValue }
  }

  var draggedIndex: Int? {
    get { draggedIndexState }
    nonmutating set { draggedIndexState = newValue }
  }

  var dragBaselinePercents: [Double] {
    get { dragBaselinePercentsState }
    nonmutating set { dragBaselinePercentsState = newValue }
  }

  var mouseLocation: CGPoint? {
    get { mouseLocationState }
    nonmutating set { mouseLocationState = newValue }
  }

  var markerPresenterTarget: LiveMarkerPresentation.Target? {
    get { markerPresenterTargetState }
    nonmutating set { markerPresenterTargetState = newValue }
  }

  var previousMarkerGeneration: LiveMarkerPresentation.Target.Generation? {
    get { previousMarkerGenerationState }
    nonmutating set { previousMarkerGenerationState = newValue }
  }

  var activePhase: Double {
    get { activePhaseState }
    nonmutating set { activePhaseState = newValue }
  }

  @State private var activePhaseState: Double = 1.0

  let topPad: CGFloat = FanCurveEditorConstants.topPad
  let bottomPad: CGFloat = FanCurveEditorConstants.bottomPad
  let leftPad: CGFloat = FanCurveEditorConstants.leftPad
  let rightPad: CGFloat = FanCurveEditorConstants.rightPad

  let plotTempRange: ClosedRange<Double> = CurveColumns.tempRange
  let temperatureAxisScale = CurveColumns.axisScale
  let curveColor = Color.accentColor

  var effectiveActive: Bool {
    presentation.usesActiveCurveStyling
  }

  var targetActivePhase: Double {
    effectiveActive ? 1.0 : 0.0
  }

  @AppStorage(SharedConfigKeys.overdriveEnabled, store: Self.suite)
  var overdriveEnabled: Bool = false

  @AppStorage(SharedConfigKeys.underdriveEnabled, store: Self.suite)
  var underdriveEnabled: Bool = false

  @AppStorage(SharedConfigKeys.boostEnabled, store: Self.suite)
  var boostEnabled: Bool = false

  // Tracks the Overdrive/Underdrive flags as of the last applied RPM-range
  // rescale, so a toggle can diff against the range it actually replaces
  // rather than the range implied by the flags' new values alone.
  @State private var previousOverdriveEnabled: Bool = false
  @State private var previousUnderdriveEnabled: Bool = false

  static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
  let runtimeMarkerAnimation = Animation.easeInOut(
    duration: FanCurveEditorConstants.runtimeMarkerAnimationDuration
  )
  let fanPresentationTemperatureAlpha: Double = FanCurveEditorConstants
    .fanPresentationTemperatureAlpha
  let fanPresentationMaxTemperatureStepC: Double = FanCurveEditorConstants
    .fanPresentationMaxTemperatureStepC
  let demandPresentationTemperatureAlpha: Double = FanCurveEditorConstants
    .demandPresentationTemperatureAlpha
  let demandPresentationPercentAlpha: Double = FanCurveEditorConstants
    .demandPresentationPercentAlpha
  let demandPresentationMaxTemperatureStepC: Double = FanCurveEditorConstants
    .demandPresentationMaxTemperatureStepC
  let demandPresentationMaxPercentStep: Double = FanCurveEditorConstants
    .demandPresentationMaxPercentStep

  func rpmRange(overdrive: Bool, underdrive: Bool) -> (min: Float, max: Float) {
    guard let fan = runtime.fans.first else {
      return (0, FanCurveEditorConstants.fallbackMaxRPM)
    }
    let minRPM: Float = underdrive ? 0 : fan.minRPM
    let maxRPM: Float = overdrive ? max(fan.maxRPM, overdriveTargetRPM) : fan.maxRPM
    return (minRPM, maxRPM)
  }

  var rpmRange: (min: Float, max: Float) {
    rpmRange(overdrive: overdriveEnabled, underdrive: underdriveEnabled)
  }

  /// Overdrive and Underdrive change the effective RPM range, so a control
  /// point that keeps its stored percent would silently command a different
  /// RPM once the toggle lands. Rescale stored percents against the range
  /// that was actually in effect before the toggle so the curve holds its
  /// commanded RPM and its plotted height shrinks or grows to match.
  func applyExtendedRangeRescale(overdrive: Bool, underdrive: Bool) {
    let oldRange = rpmRange(
      overdrive: previousOverdriveEnabled,
      underdrive: previousUnderdriveEnabled
    )
    let newRange = rpmRange(overdrive: overdrive, underdrive: underdrive)
    model.rescaleForRPMRangeChange(from: oldRange, to: newRange)
    previousOverdriveEnabled = overdrive
    previousUnderdriveEnabled = underdrive
  }

  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size

      ZStack {
        if presentation.chartState == .degraded {
          degradedChartOverlay
        } else {
          Canvas { context, canvasSize in
            drawGrid(context: context, size: canvasSize)
            drawCurve(context: context, size: canvasSize)
            drawHoverLine(context: context, size: canvasSize)
            drawAxisTitles(context: context, size: canvasSize)
          }
          .contentShape(Rectangle())

          controlPointsOverlay(size: size)
          currentPositionOverlay(size: size, values: markerPresenterTarget?.values)
          hoverTooltipOverlay(size: size)
          chartLegendOverlay
          appleAutoLabelOverlay(size: size)
          controlPointHitTargetsOverlay(size: size)
        }
      }
      .onContinuousHover { phase in
        handleHoverPhase(phase, size: size)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .fancurveGlassCard(cornerRadius: FanCurveEditorConstants.cardCornerRadius)
    .clipShape(RoundedRectangle(cornerRadius: FanCurveEditorConstants.cardCornerRadius))
    .accessibilityIdentifier(AppAccessibilityIdentifier.Curve.editor)
    .onAppear { activePhase = targetActivePhase }
    .onChange(of: model.isActive) { _ in
      withAnimation(
        .easeInOut(duration: FanCurveEditorConstants.activePhaseAnimationDuration)
      ) {
        activePhase = targetActivePhase
      }
    }
    .onChange(of: presentation) { _ in
      withAnimation(
        .easeInOut(duration: FanCurveEditorConstants.activePhaseAnimationDuration)
      ) {
        activePhase = targetActivePhase
      }
      refreshRuntimeMarkerTarget()
    }
    .onAppear {
      refreshRuntimeMarkerTarget()
    }
    .onAppear {
      previousOverdriveEnabled = overdriveEnabled
      previousUnderdriveEnabled = underdriveEnabled
    }
    .onChange(of: runtime.snapshot) { _ in refreshRuntimeMarkerTarget() }
    .onChange(of: boostEnabled) { _ in
      refreshRuntimeMarkerTarget()
    }
    .onChange(of: overdriveEnabled) { newValue in
      applyExtendedRangeRescale(overdrive: newValue, underdrive: underdriveEnabled)
    }
    .onChange(of: underdriveEnabled) { newValue in
      applyExtendedRangeRescale(overdrive: overdriveEnabled, underdrive: newValue)
    }
  }

  private var degradedChartOverlay: some View {
    let title: String
    let message: String

    switch presentation.installationStep {
    case .helperMissing:
      title = "System Helper Required"
      message =
        "Fan Curve needs the System Helper before it can show live temperature and fan telemetry in this state."
    case .helperAwaitingApproval:
      title = "System Helper Needs Approval"
      message =
        "Approve the System Helper in System Settings before Fan Curve can resume live temperature "
        + "and fan telemetry."
    default:
      title = "Runtime telemetry is unavailable"
      message =
        "Fan Curve is waiting for a fresh agent snapshot before drawing live fan demand."
    }

    return VStack(spacing: FanCurveEditorConstants.degradedSpacing) {
      Image(systemName: "waveform.path.ecg.rectangle")
        .font(.system(size: FanCurveEditorConstants.degradedIconSize, weight: .regular))
        .foregroundStyle(.secondary)
      Text(title)
        .font(.title3.weight(.semibold))
        .foregroundStyle(.primary)
      Text(message)
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: FanCurveEditorConstants.degradedMaxWidth)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(FanCurveEditorConstants.degradedPadding)
    .accessibilityIdentifier(AppAccessibilityIdentifier.Dashboard.degraded)
  }

  func handleHoverPhase(_ phase: HoverPhase, size: CGSize) {
    switch phase {
    case .active(let location):
      mouseLocation = location
      if draggedIndex == nil {
        hoveredIndex = hoveredControlPointIndex(at: location, in: size)
      }
    case .ended:
      mouseLocation = nil
      if draggedIndex == nil {
        hoveredIndex = nil
      }
    }
  }
}
