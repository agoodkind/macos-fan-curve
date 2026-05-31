//
//  FanCurveEditor+Canvas.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

// MARK: - Canvas Drawing Constants

private enum CanvasConstants {
    // Grid opacity levels
    static let gridLineOpacity: Double = 0.05
    static let minorGridLineOpacity: Double = 0.025
    static let majorGridLineOpacity: Double = 0.065

    // Grid line widths
    static let minorGridLineWidth: CGFloat = 0.5
    static let majorGridLineWidth: CGFloat = 0.65

    // Percent axis stride
    static let percentGridStride: Double = 0.2

    // Reference temperature used only for Y-pixel lookup (value unused for domain logic)
    static let yAxisReferenceTempC: Double = 20

    // Y-axis label layout
    static let yLabelXOff: CGFloat = 30
    static let rpmLabelFontSize: CGFloat = 9
    static let rpmLabelOpacity: Double = 0.6
    static let rpmLabelYOffset: CGFloat = 11

    // X-axis temperature label layout
    static let tempLabelFontSize: CGFloat = 10
    static let tempLabelYOff: CGFloat = 14

    // Axis title layout
    static let axisTitleOpacity: Double = 0.8
    static let xAxisTitleCenterDivisor: CGFloat = 2
    static let xAxisTitleYInset: CGFloat = 12
    static let yAxisTitleXInset: CGFloat = 48
    static let yAxisTitleYInset: CGFloat = 24

    // Curve fill gradient opacities
    static let curveFillGradientStartOpacity: Double = 0.18
    static let curveFillGradientEndOpacity: Double = 0.0

    // Curve stroke widths and opacities
    static let curveGlowLineWidth: CGFloat = 10
    static let curveGlowOpacity: Double = 0.15
    static let curveMainLineWidth: CGFloat = 2.5
    static let curveInactiveWidth: CGFloat = 2.0
    static let curveInactiveOpacity: Double = 0.56

    // Ghost (system default) curve
    static let ghostMinVisibleOpacity: Double = 0.01
    static let ghostOpacityMul: Double = 0.75
    static let ghostCurveWidth: CGFloat = 2.0
    static let ghostDashLen: CGFloat = 5
    static let ghostDashGap: CGFloat = 4

    // Curve interpolation
    static let curveInterpolationSteps: Int = 180

    // Hover cross-hair line
    static let hoverLineOpacity: Double = 0.08
    static let hoverLineWidth: CGFloat = 0.5
    static let hoverDotRadius: CGFloat = 4
    static let hoverDotDiameter: CGFloat = 8
    static let hoverDotOpacity: Double = 0.6

    // Apple Auto label overlay
    static let overlayMinVisibleOpacity: Double = 0.01
    static let overlayReferenceTempC: Double = 92
    static let overlayHorizontalPadding: CGFloat = 6
    static let overlayVerticalPadding: CGFloat = 2
    static let overlayCornerRadius: CGFloat = 4
    static let overlayStrokeOpacity: Double = 0.28
    static let overlayLabelXOffset: CGFloat = 34
    static let overlayLabelYOffset: CGFloat = 16

    // Tooltip pill
    static let tooltipTextOpacity: Double = 0.95
    static let tooltipHorizontalPadding: CGFloat = 7
    static let tooltipVerticalPadding: CGFloat = 3
    static let tooltipCornerRadius: CGFloat = 5
    static let tooltipBackgroundOpacity: Double = 0.92

    // Hover tooltip overlay positioning
    static let tooltipCurveProximityThreshold: CGFloat = -30
    static let tooltipYOffset: CGFloat = 26
    static let tooltipFlipThreshold: CGFloat = 32
}

extension FanCurveEditor {
    func drawGrid(context: GraphicsContext, size: CGSize) {
        let gridColor = Color.primary.opacity(CanvasConstants.gridLineOpacity)
        let minorGridColor = Color.primary.opacity(CanvasConstants.minorGridLineOpacity)
        let majorGridColor = Color.primary.opacity(CanvasConstants.majorGridLineOpacity)
        let labelColor = Color.secondary

        let plotTop = topPad
        let plotBottom = size.height - bottomPad

        drawPercentGridlines(
            context: context,
            size: size,
            gridColor: gridColor,
            labelColor: labelColor
        )

        for temp in temperatureAxisScale.minorTickTemperaturesC
        where !temperatureAxisScale.majorTickTemperaturesC.contains(temp) {
            let x = dataToPixel(temp: temp, percent: 0, in: size).x
            var line = Path()
            line.move(to: CGPoint(x: x, y: plotTop))
            line.addLine(to: CGPoint(x: x, y: plotBottom))
            context.stroke(
                line, with: .color(minorGridColor), lineWidth: CanvasConstants.minorGridLineWidth)
        }

        for temp in temperatureAxisScale.majorTickTemperaturesC {
            let x = dataToPixel(temp: temp, percent: 0, in: size).x
            var line = Path()
            line.move(to: CGPoint(x: x, y: plotTop))
            line.addLine(to: CGPoint(x: x, y: plotBottom))
            context.stroke(
                line, with: .color(majorGridColor), lineWidth: CanvasConstants.majorGridLineWidth)
        }

        for temp in labeledTemperatureTicks() {
            let x = dataToPixel(temp: temp, percent: 0, in: size).x
            let text = Text("\(displayTemp(temp))\(unit.symbol)")
                .font(
                    .system(size: CanvasConstants.tempLabelFontSize, design: .rounded).weight(
                        .medium)
                )
                .foregroundColor(labelColor)
            context.draw(
                text,
                at: CGPoint(x: x, y: plotBottom + CanvasConstants.tempLabelYOff),
                anchor: .center)
        }
    }

    private func drawPercentGridlines(
        context: GraphicsContext,
        size: CGSize,
        gridColor: Color,
        labelColor: Color
    ) {
        let plotLeft = leftPad
        let plotRight = size.width - rightPad
        for pct in stride(from: 0.0, through: 1.0, by: CanvasConstants.percentGridStride) {
            let y = dataToPixel(temp: CanvasConstants.yAxisReferenceTempC, percent: pct, in: size).y
            var line = Path()
            line.move(to: CGPoint(x: plotLeft, y: y))
            line.addLine(to: CGPoint(x: plotRight, y: y))
            context.stroke(
                line, with: .color(gridColor), lineWidth: CanvasConstants.minorGridLineWidth)

            let pctText = Text("\(Int(pct * 100))%")
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(labelColor)
            context.draw(
                pctText,
                at: CGPoint(x: plotLeft - CanvasConstants.yLabelXOff, y: y),
                anchor: .center)

            let rpm = Int(rpmRange.min + Float(pct) * (rpmRange.max - rpmRange.min))
            let rpmText = Text(rpm.formatted())
                .font(.system(size: CanvasConstants.rpmLabelFontSize, design: .rounded))
                .foregroundColor(labelColor.opacity(CanvasConstants.rpmLabelOpacity))
            context.draw(
                rpmText,
                at: CGPoint(
                    x: plotLeft - CanvasConstants.yLabelXOff,
                    y: y + CanvasConstants.rpmLabelYOffset),
                anchor: .center)
        }
    }

    func labeledTemperatureTicks() -> [Double] {
        temperatureAxisScale.controlPointTemperaturesC
    }

    func drawAxisTitles(context: GraphicsContext, size: CGSize) {
        let titleColor = Color.secondary.opacity(CanvasConstants.axisTitleOpacity)

        let xTitle = Text("Temperature (\(unit.symbol))")
            .font(.system(.caption2, design: .rounded).weight(.medium))
            .foregroundColor(titleColor)
        context.draw(
            xTitle,
            at: CGPoint(
                x: (leftPad + size.width - rightPad) / CanvasConstants.xAxisTitleCenterDivisor,
                y: size.height - CanvasConstants.xAxisTitleYInset),
            anchor: .center
        )

        let yTitle = Text("Fan Speed (% / RPM)")
            .font(.system(.caption2, design: .rounded).weight(.medium))
            .foregroundColor(titleColor)
        context.draw(
            yTitle,
            at: CGPoint(
                x: leftPad - CanvasConstants.yAxisTitleXInset,
                y: topPad - CanvasConstants.yAxisTitleYInset),
            anchor: .leading
        )
    }

    func drawCurve(context: GraphicsContext, size: CGSize) {
        if presentation.showsSystemDefault {
            drawGhostCurve(context: context, size: size, opacity: 1.0 - activePhase)
        }

        let pixelPoints = curvePixelPoints(
            points: model.controlPoints,
            mode: model.interpolationMode,
            size: size
        )
        guard let firstPoint = pixelPoints.first, let lastPoint = pixelPoints.last else { return }
        let zeroY = dataToPixel(temp: CanvasConstants.yAxisReferenceTempC, percent: 0, in: size).y

        let line = curvePath(through: pixelPoints)
        var fill = line
        fill.addLine(to: CGPoint(x: lastPoint.x, y: zeroY))
        fill.addLine(to: CGPoint(x: firstPoint.x, y: zeroY))
        fill.closeSubpath()

        if effectiveActive {
            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [
                        curveColor.opacity(CanvasConstants.curveFillGradientStartOpacity),
                        curveColor.opacity(CanvasConstants.curveFillGradientEndOpacity),
                    ]),
                    startPoint: CGPoint(x: 0, y: topPad),
                    endPoint: CGPoint(x: 0, y: size.height - bottomPad)
                )
            )

            context.stroke(
                line,
                with: .color(curveColor.opacity(CanvasConstants.curveGlowOpacity)),
                style: StrokeStyle(
                    lineWidth: CanvasConstants.curveGlowLineWidth, lineCap: .round, lineJoin: .round
                )
            )
            context.stroke(
                line,
                with: .color(curveColor),
                style: StrokeStyle(
                    lineWidth: CanvasConstants.curveMainLineWidth, lineCap: .round, lineJoin: .round
                )
            )
        } else {
            context.stroke(
                line,
                with: .color(Color.secondary.opacity(CanvasConstants.curveInactiveOpacity)),
                style: StrokeStyle(
                    lineWidth: CanvasConstants.curveInactiveWidth,
                    lineCap: .round,
                    lineJoin: .round)
            )
        }
    }

    func curvePath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    func drawGhostCurve(context: GraphicsContext, size: CGSize, opacity: Double) {
        guard opacity > CanvasConstants.ghostMinVisibleOpacity else { return }
        let ghostPoints = CurvePresets.appleSilent.curvePoints()
        let pixelPoints = curvePixelPoints(points: ghostPoints, mode: .catmullRom, size: size)
        let line = curvePath(through: pixelPoints)
        context.stroke(
            line,
            with: .color(curveColor.opacity(CanvasConstants.ghostOpacityMul * opacity)),
            style: StrokeStyle(
                lineWidth: CanvasConstants.ghostCurveWidth,
                lineCap: .round,
                lineJoin: .round,
                dash: [CanvasConstants.ghostDashLen, CanvasConstants.ghostDashGap])
        )
    }

    private func curvePixelPoints(
        points: [CurvePoint],
        mode: InterpolationMode,
        size: CGSize
    ) -> [CGPoint] {
        CurveInterpolation.pathPoints(
            points: points,
            mode: mode,
            tempRange: plotTempRange,
            steps: CanvasConstants.curveInterpolationSteps
        )
        .map { dataToPixel(temp: $0.temperature, percent: $0.fanPercent, in: size) }
    }

    func drawHoverLine(context: GraphicsContext, size: CGSize) {
        guard let mouse = mouseLocation else { return }
        guard draggedIndex == nil, hoveredIndex == nil else { return }
        let data = pixelToData(mouse, in: size)
        guard data.x >= plotTempRange.lowerBound, data.x <= plotTempRange.upperBound else { return }

        let percent = model.evaluate(at: data.x)
        let position = dataToPixel(temp: data.x, percent: percent, in: size)
        let plotTop = topPad
        let plotBottom = size.height - bottomPad

        var verticalLine = Path()
        verticalLine.move(to: CGPoint(x: position.x, y: plotTop))
        verticalLine.addLine(to: CGPoint(x: position.x, y: plotBottom))
        context.stroke(
            verticalLine,
            with: .color(Color.primary.opacity(CanvasConstants.hoverLineOpacity)),
            lineWidth: CanvasConstants.hoverLineWidth)

        let dotRect = CGRect(
            x: position.x - CanvasConstants.hoverDotRadius,
            y: position.y - CanvasConstants.hoverDotRadius,
            width: CanvasConstants.hoverDotDiameter,
            height: CanvasConstants.hoverDotDiameter
        )
        context.fill(
            Circle().path(in: dotRect),
            with: .color(curveColor.opacity(CanvasConstants.hoverDotOpacity)))
    }

    func appleAutoLabelOverlay(size: CGSize) -> some View {
        let inverse = presentation.showsSystemDefault ? 1.0 - activePhase : 0.0
        return Group {
            if inverse > CanvasConstants.overlayMinVisibleOpacity {
                let ghostAt = CurveInterpolation.evaluate(
                    at: CanvasConstants.overlayReferenceTempC,
                    points: CurvePresets.appleSilent.curvePoints(),
                    mode: .catmullRom
                )
                let anchor = dataToPixel(
                    temp: CanvasConstants.overlayReferenceTempC, percent: ghostAt, in: size)
                let text = Text("System Default")
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, CanvasConstants.overlayHorizontalPadding)
                    .padding(.vertical, CanvasConstants.overlayVerticalPadding)

                text
                    .fancurveGlassPill(
                        in: RoundedRectangle(cornerRadius: CanvasConstants.overlayCornerRadius),
                        fallbackFill: Color(nsColor: .windowBackgroundColor),
                        stroke: Color.secondary.opacity(CanvasConstants.overlayStrokeOpacity)
                    )
                    .opacity(inverse)
                    .position(
                        x: anchor.x - CanvasConstants.overlayLabelXOffset,
                        y: anchor.y + CanvasConstants.overlayLabelYOffset
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    func tooltipPill(temp: Double, percent: Double, rpm: Int) -> some View {
        let label = Text(
            "\(displayTemp(temp))\(unit.symbol)  \(Int(percent * 100))%  \(rpm.formatted()) RPM"
        )
        .font(.system(.caption2, design: .rounded).weight(.medium))
        .foregroundColor(Color.primary.opacity(CanvasConstants.tooltipTextOpacity))
        .padding(.horizontal, CanvasConstants.tooltipHorizontalPadding)
        .padding(.vertical, CanvasConstants.tooltipVerticalPadding)

        return
            label
            .fancurveGlassPill(
                in: RoundedRectangle(cornerRadius: CanvasConstants.tooltipCornerRadius),
                fallbackFill: Color(nsColor: .windowBackgroundColor).opacity(
                    CanvasConstants.tooltipBackgroundOpacity)
            )
    }

    func hoverTooltipOverlay(size: CGSize) -> some View {
        Group {
            if let mouse = mouseLocation, draggedIndex == nil, hoveredIndex == nil {
                let data = pixelToData(mouse, in: size)
                if data.x >= plotTempRange.lowerBound, data.x <= plotTempRange.upperBound {
                    let percent = model.evaluate(at: data.x)
                    let position = dataToPixel(temp: data.x, percent: percent, in: size)
                    let rpm = Int(rpmRange.min + Float(percent) * (rpmRange.max - rpmRange.min))
                    let tooltipY =
                        position.y > topPad + CanvasConstants.tooltipFlipThreshold
                        ? position.y - CanvasConstants.tooltipYOffset
                        : position.y + CanvasConstants.tooltipYOffset
                    let distanceFromCurve = mouse.y - position.y
                    let showTooltip =
                        distanceFromCurve > CanvasConstants.tooltipCurveProximityThreshold

                    if showTooltip {
                        tooltipPill(temp: data.x, percent: percent, rpm: rpm)
                            .position(x: position.x, y: tooltipY)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }
}
