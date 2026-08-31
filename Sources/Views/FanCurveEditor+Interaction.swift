//
//  FanCurveEditor+Interaction.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

// MARK: - Interaction constants

private enum ControlPointSizeConstants {
  static let highlightedDiameter: CGFloat = 14
  static let normalDiameter: CGFloat = 11
}

private enum ControlPointStrokeConstants {
  static let highlightedWidth: CGFloat = 2.5
  static let activeWidth: CGFloat = 1.5
  static let defaultWidth: CGFloat = 2.0
}

private enum ControlPointOpacityConstants {
  static let fillBackground: Double = 0.98
  static let inactiveStroke: Double = 0.96
  static let activeShadow: Double = 0.25
  static let inactiveShadow: Double = 0.2
}

private enum ControlPointShadowConstants {
  static let highlightedRadius: CGFloat = 6
  static let defaultRadius: CGFloat = 2
}

private enum InteractionAnimationConstants {
  static let activeToggleDuration: Double = 0.35
}

extension FanCurveEditor {
  var graphLayout: CurveGraphLayout {
    CurveGraphLayout(
      topPadding: topPad,
      bottomPadding: bottomPad,
      leftPadding: leftPad,
      rightPadding: rightPad
    )
  }

  func graphContext(size: CGSize) -> CurveGraphDrawingContext {
    CurveGraphDrawingContext(
      size: size,
      layout: graphLayout,
      xAxis: dashboardXAxis
    )
  }

  var controlPointStyle: CurveGraphControlPointStyle {
    let strokeColor: Color =
      effectiveActive
      ? curveColor
      : Color.secondary.opacity(ControlPointOpacityConstants.inactiveStroke)
    let shadowOpacity =
      effectiveActive
      ? ControlPointOpacityConstants.activeShadow
      : ControlPointOpacityConstants.inactiveShadow

    return CurveGraphControlPointStyle(
      fillColor: Color(nsColor: .windowBackgroundColor).opacity(
        ControlPointOpacityConstants.fillBackground
      ),
      strokeColor: strokeColor,
      normalDiameter: ControlPointSizeConstants.normalDiameter,
      highlightedDiameter: ControlPointSizeConstants.highlightedDiameter,
      normalLineWidth: effectiveActive
        ? ControlPointStrokeConstants.activeWidth
        : ControlPointStrokeConstants.defaultWidth,
      highlightedLineWidth: ControlPointStrokeConstants.highlightedWidth,
      shadowColor: strokeColor.opacity(shadowOpacity),
      normalShadowRadius: ControlPointShadowConstants.defaultRadius,
      highlightedShadowRadius: ControlPointShadowConstants.highlightedRadius
    )
  }

  func controlPointsOverlay(size: CGSize) -> some View {
    CurveGraphControlPointsOverlay(
      points: model.controlPoints,
      size: size,
      graph: graphContext(size: size),
      style: controlPointStyle,
      hitRadius: controlPointHitRadius,
      hoveredIndex: hoveredIndex,
      draggedIndex: draggedIndex,
      makeGesture: dragGesture,
      rendersHitTargets: false
    )
    .allowsHitTesting(false)
    .animation(
      .easeInOut(duration: InteractionAnimationConstants.activeToggleDuration),
      value: effectiveActive
    )
  }

  func controlPointHitTargetsOverlay(size: CGSize) -> some View {
    CurveGraphControlPointsOverlay(
      points: model.controlPoints,
      size: size,
      graph: graphContext(size: size),
      style: controlPointStyle,
      hitRadius: controlPointHitRadius,
      hoveredIndex: hoveredIndex,
      draggedIndex: draggedIndex,
      makeGesture: dragGesture,
      rendersVisiblePoints: false
    )
    .allowsHitTesting(true)
    .animation(
      .easeInOut(duration: InteractionAnimationConstants.activeToggleDuration),
      value: effectiveActive
    )
  }

  func dragGesture(index: Int, size: CGSize) -> AnyGesture<DragGesture.Value> {
    AnyGesture(
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
    )
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
    model.controlPoints = FixedColumnCurve.updatedPoints(
      model.controlPoints,
      draggedIndex: index,
      proposedPercent: proposedPercent
    )
  }

  func dataToPixel(temp: Double, percent: Double, in size: CGSize) -> CGPoint {
    graphContext(size: size).point(x: temp, y: percent)
  }

  func pixelToData(_ point: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
    graphContext(size: size).data(at: point)
  }
}
