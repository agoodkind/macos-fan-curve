//
//  FanCurveEditor.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import AppLog
import SwiftUI

private let fanCurveEditorLog = AppLog.make(category: "FanCurveEditor")

struct FanCurveEditor: View {
    @ObservedObject var model: FanCurveModel
    @ObservedObject var runtime: AgentSnapshotState
    let renderMode: AppRenderMode
    @State private var hoveredIndex: Int?
    @State private var draggedIndex: Int?
    @State private var dragBaselinePercents: [Double] = []
    @State private var mouseLocation: CGPoint?
    @State private var targetMarkers = MarkerValues.zero
    private let controlPointHitRadius: CGFloat = 14

    private struct MarkerValues: Equatable {
        var committedTemperature: Double
        var committedPercent: Double
        var rawTemperature: Double
        var rawPercent: Double

        static let zero = MarkerValues(
            committedTemperature: 0,
            committedPercent: 0,
            rawTemperature: 0,
            rawPercent: 0)
    }

    @AppStorage("temperatureUnit") private var unitRaw: String = "celsius"

    private var unit: TemperatureUnit {
        TemperatureUnit(rawValue: unitRaw) ?? .celsius
    }

    private func displayTemp(_ celsius: Double) -> Int {
        Int(unit.convert(fromCelsius: celsius).rounded())
    }

    /// Crossfade driver between active and inactive curve rendering. 1 is
    /// fully active (blue solid user curve, no ghost). 0 is fully inactive
    /// (gray dashed user curve, accent-colored Apple ghost). SwiftUI
    /// animates this on toggle so Canvas redraws with interpolated opacity
    /// each frame, giving a smooth transition.
    @State private var activePhase: Double = 1.0

    private let topPad: CGFloat = 56
    private let bottomPad: CGFloat = 44
    private let leftPad: CGFloat = 72
    private let rightPad: CGFloat = 24

    private let plotTempRange: ClosedRange<Double> = CurveColumns.tempRange
    private let temperatureAxisScale = CurveColumns.axisScale
    private let curveColor = Color.accentColor

    @AppStorage(SharedConfigKeys.overdriveEnabled, store: Self.suite)
    private var overdriveEnabled: Bool = false

    @AppStorage(SharedConfigKeys.underdriveEnabled, store: Self.suite)
    private var underdriveEnabled: Bool = false

    @AppStorage(SharedConfigKeys.boostEnabled, store: Self.suite)
    private var boostEnabled: Bool = false

    private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

    /// Visual scale for the Y axis follows the effective fan control range.
    /// Overdrive extends the top to the configured target. Underdrive drops
    /// the bottom to zero. When neither is on the axis uses the firmware
    /// reported minimum and maximum.
    private var rpmRange: (min: Float, max: Float) {
        guard let fan = runtime.fans.first else { return (0, 8_000) }
        let minR: Float = underdriveEnabled ? 0 : fan.minRPM
        let maxR: Float = overdriveEnabled ? max(fan.maxRPM, overdriveTargetRPM) : fan.maxRPM
        return (minR, maxR)
    }

    private let runtimeMarkerAnimation = Animation.easeInOut(duration: 2.4)
    private let markerTemperatureDeadbandC: Double = 0.25
    private let markerPercentDeadband: Double = 0.006
    private let demandMarkerTemperatureDeadbandC: Double = 0.6
    private let demandMarkerPercentDeadband: Double = 0.012
    private let demandMarkerTemperatureAlpha: Double = 0.22
    private let demandMarkerPercentAlpha: Double = 0.18
    private let demandMarkerMaximumTemperatureStepC: Double = 1.2
    private let demandMarkerMaximumPercentStep: Double = 0.015

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                Canvas { context, canvasSize in
                    drawGrid(context: context, size: canvasSize)
                    drawCurve(context: context, size: canvasSize)
                    drawHoverLine(context: context, size: canvasSize)
                    drawAxisTitles(context: context, size: canvasSize)
                }
                .contentShape(Rectangle())
                // Point dragging is the only editing mode in this pass.
                // Disabling segment dragging keeps the monotonic rules
                // predictable while we tighten the core curve behavior.

                controlPointsOverlay(size: size)
                // Current position and Now label render last so they sit on top
                // of the curve line and all control points.
                currentPositionOverlay(size: size, values: targetMarkers)
                hoverTooltipOverlay(size: size)
                chartLegendOverlay
                appleAutoLabelOverlay(size: size)
            }
            .onContinuousHover { phase in
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fancurveGlassCard(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { activePhase = model.isActive ? 1.0 : 0.0 }
        .onChange(of: model.isActive) { newActive in
            withAnimation(.easeInOut(duration: 0.35)) {
                activePhase = newActive ? 1.0 : 0.0
            }
        }
        .onAppear {
            refreshRuntimeMarkerTargets()
        }
        .onChange(of: runtime.snapshot) { _ in refreshRuntimeMarkerTargets() }
        .onChange(of: boostEnabled) { _ in
            refreshRuntimeMarkerTargets()
        }
    }

    // MARK: - Header

    /// Compact caption above the chart. The window title already says
    /// FanCurve, so a second H1 here would be redundant. A single caption
    /// line carries the operational state and keeps the chart as the hero.
    private var header: some View {
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

    // MARK: - Current Position Overlay

    private func currentPositionOverlay(size: CGSize, values: MarkerValues) -> some View {
        ZStack(alignment: .topLeading) {
            if let geometry = runtimeMarkerGeometry(size: size, values: values) {
                RuntimeMarkerOverlay(geometry: geometry)
                    .animation(runtimeMarkerAnimation, value: geometry)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func runtimeMarkerGeometry(
        size: CGSize,
        values: MarkerValues
    ) -> RuntimeMarkerOverlay.Geometry? {
        let committedTemp = values.committedTemperature
        let rawTemp = values.rawTemperature
        guard committedTemp > 0, rawTemp > 0 else { return nil }

        let committedPos = dataToPixel(
            temp: committedTemp,
            percent: values.committedPercent,
            in: size
        )
        let demandPercent = max(0, min(1, values.rawPercent))
        let demandPos = dataToPixel(
            temp: rawTemp,
            percent: demandPercent,
            in: size
        )
        let rawPos = CGPoint(
            x: demandPos.x,
            y: max(topPad + 10, min(size.height - bottomPad - 10, demandPos.y))
        )
        return RuntimeMarkerOverlay.Geometry(
            size: size,
            committedPosition: committedPos,
            demandPosition: rawPos,
            zeroY: dataToPixel(temp: 20, percent: 0, in: size).y,
            plotLeft: leftPad
        )
    }

    private func refreshRuntimeMarkerTargets() {
        let nextTarget = runtimeMarkerTarget()
        if nextTarget != targetMarkers {
            fanCurveEditorLog.debug(
                "curve_editor.marker_target.changed active=\(runtime.curveActive, privacy: .public)"
            )
        }
        targetMarkers = nextTarget
    }

    private func runtimeMarkerTarget() -> MarkerValues {
        if runtime.curveActive {
            let controllerTemperature =
                runtime.committedTemperature > 0
                ? runtime.committedTemperature
                : runtime.governingTemperature
            let demandTemperature = runtime.rawPressureTemperature ?? runtime.governingTemperature
            let actualFanPercent = currentFanPercent() ?? runtime.committedPercent

            let clampedControllerTemperature = max(
                plotTempRange.lowerBound, min(plotTempRange.upperBound, controllerTemperature))
            let committedTemperature = stableMarkerTemperatureTarget(
                currentTarget: targetMarkers.committedTemperature,
                proposedTemperature: clampedControllerTemperature,
                proposedPercent: actualFanPercent
            )
            let clampedDemandTemperature = max(plotTempRange.lowerBound, min(plotTempRange.upperBound, demandTemperature))
            let committedPercent = stabilizedMarkerTarget(
                currentTarget: targetMarkers.committedPercent,
                proposedTarget: actualFanPercent,
                deadband: markerPercentDeadband
            )
            let rawTemperature = dampedMarkerTarget(
                currentTarget: targetMarkers.rawTemperature,
                proposedTarget: clampedDemandTemperature,
                deadband: demandMarkerTemperatureDeadbandC,
                alpha: demandMarkerTemperatureAlpha,
                maximumStep: demandMarkerMaximumTemperatureStepC
            )
            let rawDemandPercent = max(0, min(1, runtime.rawBaselinePercent))
            let rawPercent = dampedMarkerTarget(
                currentTarget: targetMarkers.rawPercent,
                proposedTarget: rawDemandPercent,
                deadband: demandMarkerPercentDeadband,
                alpha: demandMarkerPercentAlpha,
                maximumStep: demandMarkerMaximumPercentStep
            )

            return MarkerValues(
                committedTemperature: committedTemperature,
                committedPercent: committedPercent,
                rawTemperature: rawTemperature,
                rawPercent: rawPercent)
        } else {
            let liveTemperature =
                runtime.committedTemperature > 0
                ? runtime.committedTemperature
                : runtime.rawPressureTemperature ?? runtime.governingTemperature
            guard liveTemperature > 0 else {
                return .zero
            }

            let clampedTemperature = max(plotTempRange.lowerBound, min(plotTempRange.upperBound, liveTemperature))
            let previewPercent = CurveInterpolation.evaluate(
                at: clampedTemperature,
                points: model.controlPoints,
                mode: model.interpolationMode
            )

            // Fan Control off means the app is not commanding a target, but the
            // chart should still preview where the visible curve would land for
            // the current CPU temperature. Actual fan RPM can legitimately read as
            // zero in system-auto mode, so using RPM here incorrectly parks the
            // markers at the origin.
            let committedTemperature = stableMarkerTemperatureTarget(
                currentTarget: targetMarkers.committedTemperature,
                proposedTemperature: clampedTemperature,
                proposedPercent: previewPercent
            )
            return MarkerValues(
                committedTemperature: committedTemperature,
                committedPercent: currentFanPercent() ?? previewPercent,
                rawTemperature: committedTemperature,
                rawPercent: previewPercent)
        }
    }

    private func currentFanPercent() -> Double? {
        let percents = runtime.fans.compactMap { fan -> Double? in
            guard fan.maxRPM > fan.minRPM, fan.actualRPM > 0 else { return nil }
            let percent = Double((fan.actualRPM - rpmRange.min) / (rpmRange.max - rpmRange.min))
            return max(0, min(1, percent))
        }
        guard !percents.isEmpty else { return nil }
        return percents.reduce(0, +) / Double(percents.count)
    }

    private func stabilizedMarkerTarget(
        currentTarget: Double,
        proposedTarget: Double,
        deadband: Double
    ) -> Double {
        guard currentTarget > 0 else { return proposedTarget }
        guard abs(currentTarget - proposedTarget) >= deadband else { return currentTarget }
        return proposedTarget
    }

    private func dampedMarkerTarget(
        currentTarget: Double,
        proposedTarget: Double,
        deadband: Double,
        alpha: Double,
        maximumStep: Double
    ) -> Double {
        guard currentTarget > 0 else { return proposedTarget }
        let delta = proposedTarget - currentTarget
        guard abs(delta) >= deadband else { return currentTarget }

        let easedStep = delta * max(0, min(1, alpha))
        let clampedStep = max(-maximumStep, min(maximumStep, easedStep))
        return currentTarget + clampedStep
    }

    private func stableMarkerTemperatureTarget(
        currentTarget: Double,
        proposedTemperature: Double,
        proposedPercent: Double
    ) -> Double {
        guard currentTarget > 0 else { return proposedTemperature }
        let currentPercent = CurveInterpolation.evaluate(
            at: currentTarget,
            points: model.controlPoints,
            mode: model.interpolationMode
        )
        // Flat or near-flat spans do not have a meaningful unique X position for
        // a fan-speed target. Keep the target anchored unless the fan percent
        // materially changes; otherwise tiny CPU temp jitter turns into stressful
        // horizontal marker motion.
        if abs(currentPercent - proposedPercent) < 0.006 {
            return currentTarget
        }
        return proposedTemperature
    }

    @ViewBuilder
    private var chartLegendOverlay: some View {
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

    private func legendItem(fill: Color, stroke: Color?, label: String) -> some View {
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

    // MARK: - Grid and Axes

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let gridColor = Color.primary.opacity(0.05)
        let minorGridColor = Color.primary.opacity(0.025)
        let majorGridColor = Color.primary.opacity(0.065)
        let labelColor = Color.secondary

        let plotLeft = leftPad
        let plotRight = size.width - rightPad
        let plotTop = topPad
        let plotBottom = size.height - bottomPad

        // Horizontal gridlines and Y axis labels (percent plus RPM)
        for pct in stride(from: 0.0, through: 1.0, by: 0.2) {
            let y = dataToPixel(temp: 20, percent: pct, in: size).y
            var line = Path()
            line.move(to: CGPoint(x: plotLeft, y: y))
            line.addLine(to: CGPoint(x: plotRight, y: y))
            context.stroke(line, with: .color(gridColor), lineWidth: 0.5)

            let pctText = Text("\(Int(pct * 100))%")
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(labelColor)
            context.draw(pctText, at: CGPoint(x: plotLeft - 30, y: y), anchor: .center)

            let rpm = Int(rpmRange.min + Float(pct) * (rpmRange.max - rpmRange.min))
            let rpmText = Text(rpm.formatted())
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(labelColor.opacity(0.6))
            context.draw(rpmText, at: CGPoint(x: plotLeft - 30, y: y + 11), anchor: .center)
        }

        for temp in temperatureAxisScale.minorTickTemperaturesC
            where !temperatureAxisScale.majorTickTemperaturesC.contains(temp)
        {
            let x = dataToPixel(temp: temp, percent: 0, in: size).x
            var line = Path()
            line.move(to: CGPoint(x: x, y: plotTop))
            line.addLine(to: CGPoint(x: x, y: plotBottom))
            context.stroke(line, with: .color(minorGridColor), lineWidth: 0.5)
        }

        for temp in temperatureAxisScale.majorTickTemperaturesC {
            let x = dataToPixel(temp: temp, percent: 0, in: size).x
            var line = Path()
            line.move(to: CGPoint(x: x, y: plotTop))
            line.addLine(to: CGPoint(x: x, y: plotBottom))
            context.stroke(line, with: .color(majorGridColor), lineWidth: 0.65)
        }

        for temp in labeledTemperatureTicks(in: size) {
            let x = dataToPixel(temp: temp, percent: 0, in: size).x
            let text = Text("\(displayTemp(temp))\(unit.symbol)")
                .font(.system(size: 10, design: .rounded).weight(.medium))
                .foregroundColor(labelColor)
            context.draw(text, at: CGPoint(x: x, y: plotBottom + 14), anchor: .center)
        }
    }

    private func labeledTemperatureTicks(in size: CGSize) -> [Double] {
        let minimumLabelGap: CGFloat = 52
        let majorTicks = temperatureAxisScale.majorTickTemperaturesC
        guard let firstTick = majorTicks.first else { return [] }

        var labels = [firstTick]
        var lastLabelX = dataToPixel(temp: firstTick, percent: 0, in: size).x

        for temp in majorTicks.dropFirst() {
            let x = dataToPixel(temp: temp, percent: 0, in: size).x
            if x - lastLabelX >= minimumLabelGap {
                labels.append(temp)
                lastLabelX = x
            } else if temp == majorTicks.last {
                labels[labels.count - 1] = temp
            }
        }

        return labels
    }

    private func drawAxisTitles(context: GraphicsContext, size: CGSize) {
        let titleColor = Color.secondary.opacity(0.8)

        let xTitle = Text("Temperature (\(unit.symbol))")
            .font(.system(.caption2, design: .rounded).weight(.medium))
            .foregroundColor(titleColor)
        context.draw(
            xTitle,
            at: CGPoint(x: (leftPad + size.width - rightPad) / 2, y: size.height - 12),
            anchor: .center)

        // Y axis title sits above the top tick. topPad leaves 16pt of space
        // above the 100% tick for this label so the two do not overlap.
        let yTitle = Text("Fan Speed (% / RPM)")
            .font(.system(.caption2, design: .rounded).weight(.medium))
            .foregroundColor(titleColor)
        context.draw(
            yTitle,
            at: CGPoint(x: leftPad - 48, y: topPad - 24),
            anchor: .leading)
    }

    // MARK: - Curve

    private func drawCurve(context: GraphicsContext, size: CGSize) {
        // Ghost always drawn but scaled by (1 - activePhase) so it fades in
        // as fan control turns off.
        drawGhostCurve(context: context, size: size, opacity: 1.0 - activePhase)

        let pathPoints = CurveInterpolation.pathPoints(
            points: model.controlPoints,
            mode: model.interpolationMode,
            tempRange: plotTempRange,
            steps: 300)
        guard !pathPoints.isEmpty else { return }

        let pixelPoints = pathPoints.map { dataToPixel(temp: $0.0, percent: $0.1, in: size) }
        guard let firstPt = pixelPoints.first, let lastPt = pixelPoints.last else { return }
        let zeroY = dataToPixel(temp: 20, percent: 0, in: size).y

        // Line is the smoothed polyline. Fill reuses the line path but
        // closes back to the baseline so the gradient under the curve is
        // bounded by the same smoothed shape.
        let line = smoothedPath(through: pixelPoints)
        var fill = line
        fill.addLine(to: CGPoint(x: lastPt.x, y: zeroY))
        fill.addLine(to: CGPoint(x: firstPt.x, y: zeroY))
        fill.closeSubpath()

        let phase = activePhase
        let inversePhase = 1.0 - activePhase

        if phase > 0.01 {
            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [curveColor.opacity(0.18 * phase), curveColor.opacity(0.0)]),
                    startPoint: CGPoint(x: 0, y: topPad),
                    endPoint: CGPoint(x: 0, y: size.height - bottomPad)))

            context.stroke(
                line,
                with: .color(curveColor.opacity(0.15 * phase)),
                style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
            context.stroke(
                line,
                with: .color(curveColor.opacity(phase)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }

        if inversePhase > 0.01 {
            context.stroke(
                line,
                with: .color(Color.secondary.opacity(0.3 * inversePhase)),
                style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round, dash: [4, 5]))
        }
    }

    /// Builds a visually-smoothed path through a sampled polyline by
    /// replacing straight segments with quadratic Beziers through the
    /// midpoint of each pair. This rounds micro-corners that appear when
    /// adjacent control points sit close in temperature with a big
    /// percent jump. Evaluation stays authoritative; only rendering is
    /// smoothed.
    private func smoothedPath(through pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        guard pts.count >= 3 else {
            for point in pts.dropFirst() { path.addLine(to: point) }
            return path
        }
        for pointIndex in 1..<(pts.count - 1) {
            let mid = CGPoint(
                x: (pts[pointIndex].x + pts[pointIndex + 1].x) / 2,
                y: (pts[pointIndex].y + pts[pointIndex + 1].y) / 2)
            path.addQuadCurve(to: mid, control: pts[pointIndex])
        }
        if let lastPoint = pts.last {
            path.addLine(to: lastPoint)
        }
        return path
    }

    /// Renders the Apple Silent preset as a dashed accent-colored guide
    /// showing roughly what macOS governs when the user curve is off. The
    /// `opacity` parameter drives the crossfade from active to inactive.
    private func drawGhostCurve(context: GraphicsContext, size: CGSize, opacity: Double) {
        guard opacity > 0.01 else { return }
        let ghostPoints = CurvePresets.appleSilent.curvePoints()
        let pathPoints = CurveInterpolation.pathPoints(
            points: ghostPoints,
            mode: .catmullRom,
            tempRange: plotTempRange,
            steps: 300)
        guard !pathPoints.isEmpty else { return }

        let pixelPoints = pathPoints.map { dataToPixel(temp: $0.0, percent: $0.1, in: size) }
        let line = smoothedPath(through: pixelPoints)
        context.stroke(
            line,
            with: .color(curveColor.opacity(0.75 * opacity)),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round, dash: [5, 4]))
    }

    // MARK: - Hover Tooltip

    private func drawHoverLine(context: GraphicsContext, size: CGSize) {
        guard let mouse = mouseLocation else { return }
        guard draggedIndex == nil, hoveredIndex == nil else { return }
        let data = pixelToData(mouse, in: size)
        guard data.x >= plotTempRange.lowerBound, data.x <= plotTempRange.upperBound else { return }

        let percent = model.evaluate(at: data.x)
        let pos = dataToPixel(temp: data.x, percent: percent, in: size)
        let plotTop = topPad
        let plotBottom = size.height - bottomPad

        var vLine = Path()
        vLine.move(to: CGPoint(x: pos.x, y: plotTop))
        vLine.addLine(to: CGPoint(x: pos.x, y: plotBottom))
        context.stroke(vLine, with: .color(Color.primary.opacity(0.08)), lineWidth: 0.5)

        let dotRect = CGRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8)
        context.fill(Circle().path(in: dotRect), with: .color(curveColor.opacity(0.6)))

        // Tooltip text and pill are rendered outside of Canvas by
        // `hoverTooltipOverlay`. This keeps the pill position animatable.
        _ = plotTop
        _ = plotBottom
        _ = percent
        _ = pos
    }

    /// "System Default" pill placed just below the ghost line in the open
    /// triangle under the rising portion of the curve. Fades with
    /// activePhase so it only shows when Fan Control is off. Uses the
    /// same pill treatment as the Now label.
    @ViewBuilder
    private func appleAutoLabelOverlay(size: CGSize) -> some View {
        let inverse = 1.0 - activePhase
        if inverse > 0.01 {
            // Anchor at the midpoint of the rising ramp, offset slightly
            // below the line so it sits in the open area beneath the dash.
            let ghostAt = CurveInterpolation.evaluate(
                at: 92,
                points: CurvePresets.appleSilent.curvePoints(),
                mode: .catmullRom)
            let anchor = dataToPixel(temp: 92, percent: ghostAt, in: size)
            let text = Text("System Default")
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundColor(curveColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)

            text
                .fancurveGlassPill(
                    in: RoundedRectangle(cornerRadius: 4),
                    fallbackFill: Color(nsColor: .windowBackgroundColor),
                    stroke: curveColor.opacity(0.35)
                )
                .opacity(inverse)
                .position(x: anchor.x - 34, y: anchor.y + 16)
                .allowsHitTesting(false)
        }
    }

    /// Tooltip pill with Liquid Glass when available.
    @ViewBuilder
    private func tooltipPill(temp: Double, percent: Double, rpm: Int) -> some View {
        let label = Text("\(displayTemp(temp))\(unit.symbol)  \(Int(percent * 100))%  \(rpm.formatted()) RPM")
            .font(.system(.caption2, design: .rounded).weight(.medium))
            .foregroundColor(Color.primary.opacity(0.95))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)

        label
            .fancurveGlassPill(
                in: RoundedRectangle(cornerRadius: 5),
                fallbackFill: Color(nsColor: .windowBackgroundColor).opacity(0.92))
    }

    /// Tooltip rendered as a real SwiftUI view so its .position animates
    /// between frames instead of snapping on every mouse sample.
    @ViewBuilder
    private func hoverTooltipOverlay(size: CGSize) -> some View {
        if let mouse = mouseLocation, draggedIndex == nil, hoveredIndex == nil {
            let data = pixelToData(mouse, in: size)
            if data.x >= plotTempRange.lowerBound, data.x <= plotTempRange.upperBound {
                let percent = model.evaluate(at: data.x)
                let pos = dataToPixel(temp: data.x, percent: percent, in: size)
                let rpm = Int(rpmRange.min + Float(percent) * (rpmRange.max - rpmRange.min))
                let tooltipY = pos.y > topPad + 32 ? pos.y - 26 : pos.y + 26

                // Only show the tooltip when the mouse is close to (or below) the
                // curve line. Far above it the user is not actually probing the
                // curve and a floating pill just adds noise.
                let distanceFromCurve = mouse.y - pos.y
                let showTooltip = distanceFromCurve > -30

                if showTooltip {
                    tooltipPill(temp: data.x, percent: percent, rpm: rpm)
                        .position(x: pos.x, y: tooltipY)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Control Points

    @ViewBuilder
    private func controlPointsOverlay(size: CGSize) -> some View {
        ForEach(Array(model.controlPoints.enumerated()), id: \.element.id) { index, point in
            controlPointView(index: index, point: point, size: size)
        }
    }

    private func controlPointView(index: Int, point: CurvePoint, size: CGSize) -> some View {
        let pos = dataToPixel(temp: point.temperature, percent: point.fanPercent, in: size)
        let isHighlighted = hoveredIndex == index || draggedIndex == index

        let strokeColor: Color = model.isActive ? curveColor : Color.secondary
        return Circle()
            .fill(Color(nsColor: .textBackgroundColor))
            .frame(width: isHighlighted ? 14 : 10, height: isHighlighted ? 14 : 10)
            .overlay(Circle().stroke(strokeColor, lineWidth: isHighlighted ? 2.5 : 1.5))
            .shadow(color: strokeColor.opacity(0.25), radius: isHighlighted ? 6 : 2)
            .padding(controlPointHitRadius - ((isHighlighted ? 14 : 10) / 2))
            .contentShape(Circle())
            .position(pos)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHighlighted)
            .animation(.easeInOut(duration: 0.35), value: model.isActive)
            .gesture(dragGesture(index: index, size: size))
    }

    // MARK: - Gestures

    private func dragGesture(index: Int, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if draggedIndex != index || dragBaselinePercents.isEmpty {
                    dragBaselinePercents = model.controlPoints.map(\.fanPercent)
                }
                draggedIndex = index
                hoveredIndex = index
                var data = pixelToData(value.location, in: size)
                data.y = max(0, min(1, data.y))
                applyDraggedPoint(at: index, proposedPercent: data.y)
            }
            .onEnded { value in
                draggedIndex = nil
                dragBaselinePercents = []
                hoveredIndex = hoveredControlPointIndex(at: value.location, in: size)
            }
    }

    private func hoveredControlPointIndex(at location: CGPoint, in size: CGSize) -> Int? {
        model.controlPoints.enumerated()
            .compactMap { index, point -> (index: Int, distance: CGFloat)? in
                let pos = dataToPixel(temp: point.temperature, percent: point.fanPercent, in: size)
                let distance = hypot(pos.x - location.x, pos.y - location.y)
                guard distance <= controlPointHitRadius else { return nil }
                return (index, distance)
            }
            .min { lhs, rhs in lhs.distance < rhs.distance }?
            .index
    }

    /// Fixed-column monotonic editor:
    /// only Y values move. Dragging a point upward cascades rightward as needed;
    /// dragging downward cascades leftward as needed.
    private func applyDraggedPoint(at index: Int, proposedPercent: Double) {
        var percents = model.controlPoints.map(\.fanPercent)
        percents[index] = proposedPercent

        if index > 0 {
            for pointIndex in stride(from: index - 1, through: 0, by: -1) {
                percents[pointIndex] = min(percents[pointIndex], percents[pointIndex + 1])
            }
        }

        if index < percents.count - 1 {
            for pointIndex in (index + 1)..<percents.count {
                percents[pointIndex] = max(percents[pointIndex], percents[pointIndex - 1])
            }
        }

        for pointIndex in model.controlPoints.indices {
            model.controlPoints[pointIndex].fanPercent = max(0.0, min(1.0, percents[pointIndex]))
        }
    }

    // MARK: - Coordinate Mapping

    private func dataToPixel(temp: Double, percent: Double, in size: CGSize) -> CGPoint {
        let plotWidth = size.width - leftPad - rightPad
        let plotHeight = size.height - topPad - bottomPad
        let clampedTemp = max(plotTempRange.lowerBound, min(plotTempRange.upperBound, temp))
        let clampedPercent = max(0, min(1, percent))
        let x = leftPad + CGFloat(temperatureFraction(for: clampedTemp)) * plotWidth
        let y = topPad + CGFloat(1 - clampedPercent) * plotHeight
        return CGPoint(x: x, y: y)
    }

    private func pixelToData(_ pt: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
        let plotWidth = size.width - leftPad - rightPad
        let plotHeight = size.height - topPad - bottomPad
        let fraction = max(0, min(1, Double((pt.x - leftPad) / plotWidth)))
        let temp = temperature(at: fraction)
        let percent = 1.0 - Double((pt.y - topPad) / plotHeight)
        return (temp, percent)
    }

    private func temperatureFraction(for temp: Double) -> Double {
        temperatureAxisScale.fraction(for: temp)
    }

    private func temperature(at fraction: Double) -> Double {
        temperatureAxisScale.temperatureC(at: fraction)
    }

}
