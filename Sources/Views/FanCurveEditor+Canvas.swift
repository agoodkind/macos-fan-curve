//
//  FanCurveEditor+Canvas.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026
//

import SwiftUI

extension FanCurveEditor {
    func drawGrid(context: GraphicsContext, size: CGSize) {
        let gridColor = Color.primary.opacity(0.05)
        let minorGridColor = Color.primary.opacity(0.025)
        let majorGridColor = Color.primary.opacity(0.065)
        let labelColor = Color.secondary

        let plotLeft = leftPad
        let plotRight = size.width - rightPad
        let plotTop = topPad
        let plotBottom = size.height - bottomPad

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
        where !temperatureAxisScale.majorTickTemperaturesC.contains(temp) {
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

        for temp in labeledTemperatureTicks() {
            let x = dataToPixel(temp: temp, percent: 0, in: size).x
            let text = Text("\(displayTemp(temp))\(unit.symbol)")
                .font(.system(size: 10, design: .rounded).weight(.medium))
                .foregroundColor(labelColor)
            context.draw(text, at: CGPoint(x: x, y: plotBottom + 14), anchor: .center)
        }
    }

    func labeledTemperatureTicks() -> [Double] {
        temperatureAxisScale.controlPointTemperaturesC
    }

    func drawAxisTitles(context: GraphicsContext, size: CGSize) {
        let titleColor = Color.secondary.opacity(0.8)

        let xTitle = Text("Temperature (\(unit.symbol))")
            .font(.system(.caption2, design: .rounded).weight(.medium))
            .foregroundColor(titleColor)
        context.draw(
            xTitle,
            at: CGPoint(x: (leftPad + size.width - rightPad) / 2, y: size.height - 12),
            anchor: .center
        )

        let yTitle = Text("Fan Speed (% / RPM)")
            .font(.system(.caption2, design: .rounded).weight(.medium))
            .foregroundColor(titleColor)
        context.draw(
            yTitle,
            at: CGPoint(x: leftPad - 48, y: topPad - 24),
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
        let zeroY = dataToPixel(temp: 20, percent: 0, in: size).y

        let line = curvePath(through: pixelPoints)
        var fill = line
        fill.addLine(to: CGPoint(x: lastPoint.x, y: zeroY))
        fill.addLine(to: CGPoint(x: firstPoint.x, y: zeroY))
        fill.closeSubpath()

        let phase = activePhase
        let inversePhase = 1.0 - activePhase

        if phase > 0.01 {
            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [curveColor.opacity(0.18 * phase), curveColor.opacity(0.0)]),
                    startPoint: CGPoint(x: 0, y: topPad),
                    endPoint: CGPoint(x: 0, y: size.height - bottomPad)
                )
            )

            context.stroke(
                line,
                with: .color(curveColor.opacity(0.15 * phase)),
                style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                line,
                with: .color(curveColor.opacity(phase)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
        }

        if inversePhase > 0.01 {
            context.stroke(
                line,
                with: .color(Color.secondary.opacity(0.56 * inversePhase)),
                style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
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
        guard opacity > 0.01 else { return }
        let ghostPoints = CurvePresets.appleSilent.curvePoints()
        let pixelPoints = curvePixelPoints(points: ghostPoints, mode: .catmullRom, size: size)
        let line = curvePath(through: pixelPoints)
        context.stroke(
            line,
            with: .color(curveColor.opacity(0.72 * opacity)),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round, dash: [5, 4])
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
            steps: 180
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
        context.stroke(verticalLine, with: .color(Color.primary.opacity(0.08)), lineWidth: 0.5)

        let dotRect = CGRect(x: position.x - 4, y: position.y - 4, width: 8, height: 8)
        context.fill(Circle().path(in: dotRect), with: .color(curveColor.opacity(0.6)))
    }

    func appleAutoLabelOverlay(size: CGSize) -> some View {
        let inverse = presentation.showsSystemDefault ? 1.0 - activePhase : 0.0
        return Group {
            if inverse > 0.01 {
                let ghostAt = CurveInterpolation.evaluate(
                    at: 92,
                    points: CurvePresets.appleSilent.curvePoints(),
                    mode: .catmullRom
                )
                let anchor = dataToPixel(temp: 92, percent: ghostAt, in: size)
                let text = Text("System Default")
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)

                text
                    .fancurveGlassPill(
                        in: RoundedRectangle(cornerRadius: 4),
                        fallbackFill: Color(nsColor: .windowBackgroundColor),
                        stroke: Color.secondary.opacity(0.28)
                    )
                    .opacity(inverse)
                    .position(x: anchor.x - 34, y: anchor.y + 16)
                    .allowsHitTesting(false)
            }
        }
    }

    func tooltipPill(temp: Double, percent: Double, rpm: Int) -> some View {
        let label = Text("\(displayTemp(temp))\(unit.symbol)  \(Int(percent * 100))%  \(rpm.formatted()) RPM")
            .font(.system(.caption2, design: .rounded).weight(.medium))
            .foregroundColor(Color.primary.opacity(0.95))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)

        return
            label
            .fancurveGlassPill(
                in: RoundedRectangle(cornerRadius: 5),
                fallbackFill: Color(nsColor: .windowBackgroundColor).opacity(0.92)
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
                    let tooltipY = position.y > topPad + 32 ? position.y - 26 : position.y + 26
                    let distanceFromCurve = mouse.y - position.y
                    let showTooltip = distanceFromCurve > -30

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
