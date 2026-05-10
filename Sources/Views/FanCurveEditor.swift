//
//  FanCurveEditor.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import AppLog
import SwiftUI

let fanCurveEditorLog = AppLog.make(category: "FanCurveEditor")

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
    let controlPointHitRadius: CGFloat = 14

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

    let topPad: CGFloat = 56
    let bottomPad: CGFloat = 44
    let leftPad: CGFloat = 72
    let rightPad: CGFloat = 24

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

    static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
    let runtimeMarkerAnimation = Animation.easeInOut(duration: 1.4)
    let fanPresentationTemperatureAlpha: Double = 0.06
    let fanPresentationMaxTemperatureStepC: Double = 0.35
    let demandPresentationTemperatureAlpha: Double = 0.10
    let demandPresentationPercentAlpha: Double = 0.10
    let demandPresentationMaxTemperatureStepC: Double = 0.7
    let demandPresentationMaxPercentStep: Double = 0.007

    var rpmRange: (min: Float, max: Float) {
        guard let fan = runtime.fans.first else { return (0, 8_000) }
        let minRPM: Float = underdriveEnabled ? 0 : fan.minRPM
        let maxRPM: Float = overdriveEnabled ? max(fan.maxRPM, overdriveTargetRPM) : fan.maxRPM
        return (minRPM, maxRPM)
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
                }
            }
            .onContinuousHover { phase in
                handleHoverPhase(phase, size: size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fancurveGlassCard(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { activePhase = targetActivePhase }
        .onChange(of: model.isActive) { _ in
            withAnimation(.easeInOut(duration: 0.35)) {
                activePhase = targetActivePhase
            }
        }
        .onChange(of: presentation) { _ in
            withAnimation(.easeInOut(duration: 0.35)) {
                activePhase = targetActivePhase
            }
            refreshRuntimeMarkerTarget()
        }
        .onAppear {
            refreshRuntimeMarkerTarget()
        }
        .onChange(of: runtime.snapshot) { _ in refreshRuntimeMarkerTarget() }
        .onChange(of: boostEnabled) { _ in
            refreshRuntimeMarkerTarget()
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

        return VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
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
