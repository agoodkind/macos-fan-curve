//
//  LoadAssistCurveEditor.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026
//

import SwiftUI

private enum LoadAssistCurveEditorConstants {
    // Control point dot
    static let controlPointDiameter: CGFloat = 10
    static let controlPointStrokeWidth: CGFloat = 2

    // Editor chrome
    static let editorVerticalPadding: CGFloat = 4
    static let backgroundCornerRadius: CGFloat = 10
    static let backgroundFillOpacity: Double = 0.035
    static let backgroundStrokeOpacity: Double = 0.08
    static let backgroundStrokeWidth: CGFloat = 0.5

    // Grid
    static let gridLoadTickQuarter: Double = 25.0
    static let gridLoadTickHalf: Double = 50.0
    static let gridLoadTickThreeQuarter: Double = 75.0
    static let gridLoadTicks: [Double] = [
        0.0, gridLoadTickQuarter, gridLoadTickHalf, gridLoadTickThreeQuarter, loadAxisMax,
    ]
    static let gridFanTickHalf: Double = 0.5
    static let gridFanTickFull: Double = 1.0
    static let gridFanTicks: [Double] = [0.0, gridFanTickHalf, gridFanTickFull]
    static let gridLineWidth: CGFloat = 1
    static let gridLabelYOffset: CGFloat = 12
    static let gridLabelXOffset: CGFloat = 6
    static let gridColorOpacity: Double = 0.05

    // Axis scale
    static let loadAxisMax: Double = 100

    // Curve drawing
    static let minimumPointsForCurve: Int = 2
    static let curveInterpolationSteps: Int = 80
    static let curveStrokeWidth: CGFloat = 3

    // Drag ripple
    static let dragRippleDecay: Double = 0.6
}

struct LoadAssistCurveEditor: View {
    @Binding var points: [CurvePoint]
    let minimumPointSpacing: Double

    private let topPad: CGFloat = 18
    private let bottomPad: CGFloat = 28
    private let leftPad: CGFloat = 40
    private let rightPad: CGFloat = 12
    private let accent = Color(nsColor: .systemTeal)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Canvas { context, canvasSize in
                    drawGrid(context: context, size: canvasSize)
                    drawCurve(context: context, size: canvasSize)
                }

                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    Circle()
                        .fill(Color(nsColor: .textBackgroundColor))
                        .frame(
                            width: LoadAssistCurveEditorConstants.controlPointDiameter,
                            height: LoadAssistCurveEditorConstants.controlPointDiameter
                        )
                        .overlay(
                            Circle().stroke(
                                accent,
                                lineWidth: LoadAssistCurveEditorConstants.controlPointStrokeWidth)
                        )
                        .position(
                            dataToPixel(
                                load: point.temperature, fanPercent: point.fanPercent, size: size)
                        )
                        .gesture(dragGesture(index: index, size: size))
                }
            }
        }
        .padding(.vertical, LoadAssistCurveEditorConstants.editorVerticalPadding)
        .background(
            RoundedRectangle(
                cornerRadius: LoadAssistCurveEditorConstants.backgroundCornerRadius
            )
            .fill(
                Color.primary.opacity(
                    LoadAssistCurveEditorConstants.backgroundFillOpacity))
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: LoadAssistCurveEditorConstants.backgroundCornerRadius
            )
            .stroke(
                Color.primary.opacity(
                    LoadAssistCurveEditorConstants.backgroundStrokeOpacity),
                lineWidth: LoadAssistCurveEditorConstants.backgroundStrokeWidth)
        )
    }

    private func dragGesture(index: Int, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                var point = pixelToData(value.location, size: size)
                point.x = max(0, min(LoadAssistCurveEditorConstants.loadAxisMax, point.x))
                point.y = max(0, min(1, point.y))

                if index == 0 || index == points.count - 1 {
                    point.x = points[index].temperature
                }
                if index > 0 {
                    point.x = max(points[index - 1].temperature + minimumPointSpacing, point.x)
                }
                if index < points.count - 1 {
                    point.x = min(points[index + 1].temperature - minimumPointSpacing, point.x)
                }

                applyDraggedPoint(index: index, load: point.x, proposedPercent: point.y)
            }
    }

    private func applyDraggedPoint(index: Int, load: Double, proposedPercent: Double) {
        let original = points
        let leftConstraint = index > 0 ? original[index - 1].fanPercent : 0
        let rightConstraint = index < original.count - 1 ? original[index + 1].fanPercent : 1
        let nextPercent = max(leftConstraint, min(rightConstraint, proposedPercent))
        let delta = nextPercent - original[index].fanPercent

        points[index].temperature = load
        points[index].fanPercent = nextPercent

        for earlierIndex in stride(from: index - 1, through: 0, by: -1) {
            let weight = pow(
                LoadAssistCurveEditorConstants.dragRippleDecay, Double(index - earlierIndex - 1))
            let desired = original[earlierIndex].fanPercent + delta * weight
            points[earlierIndex].fanPercent = max(
                0, min(points[earlierIndex + 1].fanPercent, desired))
        }

        for laterIndex in (index + 1)..<points.count {
            let weight = pow(
                LoadAssistCurveEditorConstants.dragRippleDecay, Double(laterIndex - index - 1))
            let desired = original[laterIndex].fanPercent + delta * weight
            points[laterIndex].fanPercent = max(points[laterIndex - 1].fanPercent, min(1, desired))
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let plotRect = plotFrame(size)
        let gridColor = Color.primary.opacity(LoadAssistCurveEditorConstants.gridColorOpacity)
        for tick in LoadAssistCurveEditorConstants.gridLoadTicks {
            let x =
                plotRect.minX + plotRect.width
                * CGFloat(
                    tick / LoadAssistCurveEditorConstants.loadAxisMax)
            var vertical = Path()
            vertical.move(to: CGPoint(x: x, y: plotRect.minY))
            vertical.addLine(to: CGPoint(x: x, y: plotRect.maxY))
            context.stroke(
                vertical,
                with: .color(gridColor),
                lineWidth: LoadAssistCurveEditorConstants.gridLineWidth)

            let label = context.resolve(
                Text("\(Int(tick))")
                    .font(.caption2)
            )
            context.draw(
                label,
                at: CGPoint(
                    x: x, y: plotRect.maxY + LoadAssistCurveEditorConstants.gridLabelYOffset),
                anchor: .top)
        }

        for tick in LoadAssistCurveEditorConstants.gridFanTicks {
            let y = plotRect.maxY - plotRect.height * CGFloat(tick)
            var horizontal = Path()
            horizontal.move(to: CGPoint(x: plotRect.minX, y: y))
            horizontal.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            context.stroke(
                horizontal,
                with: .color(gridColor),
                lineWidth: LoadAssistCurveEditorConstants.gridLineWidth)

            let label = context.resolve(
                Text("\(Int(tick * LoadAssistCurveEditorConstants.loadAxisMax))%")
                    .font(.caption2)
            )
            context.draw(
                label,
                at: CGPoint(
                    x: plotRect.minX - LoadAssistCurveEditorConstants.gridLabelXOffset,
                    y: y),
                anchor: .trailing)
        }
    }

    private func drawCurve(context: GraphicsContext, size: CGSize) {
        guard points.count >= LoadAssistCurveEditorConstants.minimumPointsForCurve else { return }
        let samples = CurveInterpolation.pathPoints(
            points: points,
            mode: .catmullRom,
            tempRange: 0...LoadAssistCurveEditorConstants.loadAxisMax,
            steps: LoadAssistCurveEditorConstants.curveInterpolationSteps)

        var path = Path()
        for (index, sample) in samples.enumerated() {
            let point = dataToPixel(
                load: sample.temperature, fanPercent: sample.fanPercent, size: size)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        context.stroke(
            path,
            with: .color(accent),
            style: StrokeStyle(
                lineWidth: LoadAssistCurveEditorConstants.curveStrokeWidth,
                lineCap: .round,
                lineJoin: .round)
        )
    }

    private func plotFrame(_ size: CGSize) -> CGRect {
        CGRect(
            x: leftPad,
            y: topPad,
            width: size.width - leftPad - rightPad,
            height: size.height - topPad - bottomPad)
    }

    private func dataToPixel(load: Double, fanPercent: Double, size: CGSize) -> CGPoint {
        let rect = plotFrame(size)
        return CGPoint(
            x: rect.minX + rect.width
                * CGFloat(
                    load / LoadAssistCurveEditorConstants.loadAxisMax),
            y: rect.maxY - rect.height * CGFloat(fanPercent))
    }

    private func pixelToData(_ point: CGPoint, size: CGSize) -> (x: Double, y: Double) {
        let rect = plotFrame(size)
        let x =
            Double((point.x - rect.minX) / rect.width) * LoadAssistCurveEditorConstants.loadAxisMax
        let y = 1 - Double((point.y - rect.minY) / rect.height)
        return (x, y)
    }
}
