//
//  CurveGraphRenderer.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-06-04.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

// MARK: - CurveGraphRenderer

struct CurveGraphRenderer {
    private let graph: CurveGraphDrawingContext

    init(graph: CurveGraphDrawingContext) {
        self.graph = graph
    }

    func drawGrid(
        in context: GraphicsContext,
        xAxis: CurveGraphXAxis,
        yAxis: CurveGraphYAxis,
        style: CurveGraphGridStyle
    ) {
        CurveGraphGridRenderer(
            context: context,
            graph: graph,
            xAxis: xAxis,
            yAxis: yAxis,
            style: style
        )
        .draw()
    }

    func curvePixelPoints(series: CurveGraphSeries) -> [CGPoint] {
        CurveInterpolation.pathPoints(
            points: series.points,
            mode: series.mode,
            tempRange: graph.xAxis.range,
            steps: series.steps,
            axisScale: series.axisScale
        )
        .map { sample in
            graph.point(x: sample.temperature, y: sample.fanPercent)
        }
    }

    func curvePath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let firstPoint = points.first else { return path }

        path.move(to: firstPoint)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        return path
    }

    func drawCurve(
        in context: GraphicsContext,
        series: CurveGraphSeries,
        style: CurveGraphCurveStyle
    ) {
        let pixelPoints = curvePixelPoints(series: series)
        guard let firstPoint = pixelPoints.first, let lastPoint = pixelPoints.last else { return }

        let line = curvePath(through: pixelPoints)
        drawFill(
            in: context,
            line: line,
            firstPoint: firstPoint,
            lastPoint: lastPoint,
            fill: style.fill
        )

        if let glowColor = style.glowColor {
            context.stroke(
                line,
                with: .color(glowColor),
                style: StrokeStyle(
                    lineWidth: style.glowLineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }

        context.stroke(
            line,
            with: .color(style.lineColor),
            style: StrokeStyle(
                lineWidth: style.lineWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    private func drawFill(
        in context: GraphicsContext,
        line: Path,
        firstPoint: CGPoint,
        lastPoint: CGPoint,
        fill: CurveGraphFillStyle?
    ) {
        guard let fill else { return }

        var fillPath = line
        fillPath.addLine(to: CGPoint(x: lastPoint.x, y: graph.zeroY))
        fillPath.addLine(to: CGPoint(x: firstPoint.x, y: graph.zeroY))
        fillPath.closeSubpath()

        context.fill(
            fillPath,
            with: .linearGradient(
                Gradient(colors: [fill.startColor, fill.endColor]),
                startPoint: CGPoint(x: 0, y: graph.plotTop),
                endPoint: CGPoint(x: 0, y: graph.plotBottom)
            )
        )
    }
}

// MARK: - CurveGraphGridRenderer

private struct CurveGraphGridRenderer {
    let context: GraphicsContext
    let graph: CurveGraphDrawingContext
    let xAxis: CurveGraphXAxis
    let yAxis: CurveGraphYAxis
    let style: CurveGraphGridStyle

    private var horizontalGridColor: Color {
        Color.primary.opacity(style.gridLineOpacity)
    }

    private var minorVerticalGridColor: Color {
        Color.primary.opacity(style.minorGridLineOpacity)
    }

    private var majorVerticalGridColor: Color {
        Color.primary.opacity(style.majorGridLineOpacity)
    }

    private var labelColor: Color {
        Color.secondary
    }

    func draw() {
        drawHorizontalGridLines()
        drawVerticalGridLines()
        drawLabeledXTicks()
        drawAxisTitles()
    }

    private func drawHorizontalGridLines() {
        for tick in yAxis.ticks {
            let yPosition = graph.point(x: xAxis.range.lowerBound, y: tick).y
            drawHorizontalGridLine(yPosition: yPosition)
            drawYAxisLabels(tick: tick, yPosition: yPosition)
        }
    }

    private func drawVerticalGridLines() {
        for tick in xAxis.minorTicks where !contains(xAxis.majorTicks, tick: tick) {
            drawVerticalTick(
                tick: tick,
                color: minorVerticalGridColor,
                lineWidth: style.minorGridLineWidth
            )
        }

        for tick in xAxis.majorTicks {
            drawVerticalTick(
                tick: tick,
                color: majorVerticalGridColor,
                lineWidth: style.majorGridLineWidth
            )
        }
    }

    private func drawLabeledXTicks() {
        for tick in xAxis.labeledTicks {
            let xPosition = graph.point(x: tick, y: 0).x
            let labelY = graph.plotBottom + style.xLabelYOffset
            let label = Text(xAxis.label(tick))
                .font(.system(size: style.xLabelFontSize, design: .rounded).weight(.medium))
                .foregroundColor(labelColor)
            context.draw(
                label,
                at: CGPoint(x: xPosition, y: labelY),
                anchor: .center
            )
        }
    }

    private func drawAxisTitles() {
        let titleColor = Color.secondary.opacity(style.axisTitleOpacity)
        let xTitleY = graph.size.height - style.xAxisTitleYInset
        let yTitleX = graph.layout.leftPadding - style.yAxisTitleXInset
        let yTitleY = graph.layout.topPadding - style.yAxisTitleYInset
        let xTitleX =
            (graph.plotLeft + graph.plotRight) / CurveGraphSharedConstants.titleCenterDivisor

        let xTitle = Text(xAxis.title)
            .font(.system(.caption2, design: .rounded).weight(.medium))
            .foregroundColor(titleColor)
        context.draw(
            xTitle,
            at: CGPoint(x: xTitleX, y: xTitleY),
            anchor: .center
        )

        let yTitle = Text(yAxis.title)
            .font(.system(.caption2, design: .rounded).weight(.medium))
            .foregroundColor(titleColor)
        context.draw(
            yTitle,
            at: CGPoint(x: yTitleX, y: yTitleY),
            anchor: .leading
        )
    }

    private func drawHorizontalGridLine(yPosition: CGFloat) {
        var line = Path()
        line.move(to: CGPoint(x: graph.plotLeft, y: yPosition))
        line.addLine(to: CGPoint(x: graph.plotRight, y: yPosition))
        context.stroke(line, with: .color(horizontalGridColor), lineWidth: style.minorGridLineWidth)
    }

    private func drawYAxisLabels(tick: Double, yPosition: CGFloat) {
        let labelX = graph.plotLeft - style.yPrimaryLabelXOffset
        let primaryLabel = Text(yAxis.label(tick))
            .font(.system(.caption2, design: .rounded))
            .foregroundColor(labelColor)
        context.draw(
            primaryLabel,
            at: CGPoint(x: labelX, y: yPosition),
            anchor: .center
        )

        if let secondaryLabel = yAxis.secondaryLabel, style.ySecondaryLabelOpacity > 0 {
            let detailY = yPosition + style.ySecondaryLabelYOffset
            let detailLabel = Text(secondaryLabel(tick))
                .font(.system(size: style.ySecondaryLabelFontSize, design: .rounded))
                .foregroundColor(labelColor.opacity(style.ySecondaryLabelOpacity))
            context.draw(
                detailLabel,
                at: CGPoint(x: labelX, y: detailY),
                anchor: .center
            )
        }
    }

    private func drawVerticalTick(
        tick: Double,
        color: Color,
        lineWidth: CGFloat
    ) {
        let xPosition = graph.point(x: tick, y: 0).x
        var line = Path()
        line.move(to: CGPoint(x: xPosition, y: graph.plotTop))
        line.addLine(to: CGPoint(x: xPosition, y: graph.plotBottom))
        context.stroke(line, with: .color(color), lineWidth: lineWidth)
    }

    private func contains(_ ticks: [Double], tick: Double) -> Bool {
        ticks.contains { candidate in
            abs(candidate - tick) < CurveGraphSharedConstants.tickTolerance
        }
    }
}
