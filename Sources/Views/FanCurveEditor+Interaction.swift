//
//  FanCurveEditor+Interaction.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026
//

import SwiftUI

extension FanCurveEditor {
    func controlPointsOverlay(size: CGSize) -> some View {
        ForEach(Array(model.controlPoints.enumerated()), id: \.element.id) { index, point in
            controlPointView(index: index, point: point, size: size)
        }
    }

    func controlPointView(index: Int, point: CurvePoint, size: CGSize) -> some View {
        let position = dataToPixel(temp: point.temperature, percent: point.fanPercent, in: size)
        let isHighlighted = hoveredIndex == index || draggedIndex == index
        let strokeColor: Color = effectiveActive ? curveColor : Color.secondary.opacity(0.96)
        let strokeWidth: CGFloat = isHighlighted ? 2.5 : effectiveActive ? 1.5 : 2.0

        return Circle()
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
            .frame(width: isHighlighted ? 14 : 11, height: isHighlighted ? 14 : 11)
            .overlay(Circle().stroke(strokeColor, lineWidth: strokeWidth))
            .shadow(
                color: strokeColor.opacity(effectiveActive ? 0.25 : 0.2),
                radius: isHighlighted ? 6 : 2
            )
            .padding(controlPointHitRadius - ((isHighlighted ? 14 : 11) / 2))
            .contentShape(Circle())
            .position(position)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHighlighted)
            .animation(.easeInOut(duration: 0.35), value: effectiveActive)
            .gesture(dragGesture(index: index, size: size))
    }

    func dragGesture(index: Int, size: CGSize) -> some Gesture {
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

    func hoveredControlPointIndex(at location: CGPoint, in size: CGSize) -> Int? {
        model.controlPoints.enumerated()
            .compactMap { index, point -> (index: Int, distance: CGFloat)? in
                let position = dataToPixel(
                    temp: point.temperature, percent: point.fanPercent, in: size)
                let distance = hypot(position.x - location.x, position.y - location.y)
                guard distance <= controlPointHitRadius else { return nil }
                return (index, distance)
            }
            .min { lhs, rhs in lhs.distance < rhs.distance }?
            .index
    }

    func applyDraggedPoint(at index: Int, proposedPercent: Double) {
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

    func dataToPixel(temp: Double, percent: Double, in size: CGSize) -> CGPoint {
        let plotWidth = size.width - leftPad - rightPad
        let plotHeight = size.height - topPad - bottomPad
        let clampedTemp = max(plotTempRange.lowerBound, min(plotTempRange.upperBound, temp))
        let clampedPercent = max(0, min(1, percent))
        let x = leftPad + CGFloat(temperatureFraction(for: clampedTemp)) * plotWidth
        let y = topPad + CGFloat(1 - clampedPercent) * plotHeight
        return CGPoint(x: x, y: y)
    }

    func pixelToData(_ point: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
        let plotWidth = size.width - leftPad - rightPad
        let plotHeight = size.height - topPad - bottomPad
        let fraction = max(0, min(1, Double((point.x - leftPad) / plotWidth)))
        let temp = temperature(at: fraction)
        let percent = 1.0 - Double((point.y - topPad) / plotHeight)
        return (temp, percent)
    }

    func temperatureFraction(for temp: Double) -> Double {
        temperatureAxisScale.fraction(for: temp)
    }

    func temperature(at fraction: Double) -> Double {
        temperatureAxisScale.temperatureC(at: fraction)
    }
}
