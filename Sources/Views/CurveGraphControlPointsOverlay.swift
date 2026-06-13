//
//  CurveGraphControlPointsOverlay.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-06-04.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

struct CurveGraphControlPointsOverlay: View {
  let points: [CurvePoint]
  let size: CGSize
  let graph: CurveGraphDrawingContext
  let style: CurveGraphControlPointStyle
  let hitRadius: CGFloat
  let hoveredIndex: Int?
  let draggedIndex: Int?
  let makeGesture: (Int, CGSize) -> AnyGesture<DragGesture.Value>
  let rendersVisiblePoints: Bool
  let rendersHitTargets: Bool

  init(
    points: [CurvePoint],
    size: CGSize,
    graph: CurveGraphDrawingContext,
    style: CurveGraphControlPointStyle,
    hitRadius: CGFloat,
    hoveredIndex: Int?,
    draggedIndex: Int?,
    makeGesture: @escaping (Int, CGSize) -> AnyGesture<DragGesture.Value>,
    rendersVisiblePoints: Bool = true,
    rendersHitTargets: Bool = true
  ) {
    self.points = points
    self.size = size
    self.graph = graph
    self.style = style
    self.hitRadius = hitRadius
    self.hoveredIndex = hoveredIndex
    self.draggedIndex = draggedIndex
    self.makeGesture = makeGesture
    self.rendersVisiblePoints = rendersVisiblePoints
    self.rendersHitTargets = rendersHitTargets
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      if rendersVisiblePoints {
        visiblePoints.allowsHitTesting(false)
      }
      if rendersHitTargets {
        hitTargets
      }
    }
  }

  private var visiblePoints: some View {
    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
      let isHighlighted = hoveredIndex == index || draggedIndex == index
      let diameter = isHighlighted ? style.highlightedDiameter : style.normalDiameter
      let lineWidth = isHighlighted ? style.highlightedLineWidth : style.normalLineWidth
      let shadowRadius =
        isHighlighted ? style.highlightedShadowRadius : style.normalShadowRadius

      Circle()
        .fill(style.fillColor)
        .frame(width: diameter, height: diameter)
        .overlay(Circle().stroke(style.strokeColor, lineWidth: lineWidth))
        .shadow(color: style.shadowColor, radius: shadowRadius)
        .position(graph.point(x: point.temperature, y: point.fanPercent))
        .animation(
          .spring(
            response: CurveGraphSharedConstants.pointSpringResponse,
            dampingFraction: CurveGraphSharedConstants.pointSpringDampingFraction
          ),
          value: isHighlighted
        )
    }
  }

  private var hitTargets: some View {
    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
      let diameter = hitRadius * CurveGraphSharedConstants.diameterToRadiusDivisor

      Circle()
        .fill(Color.clear)
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .position(graph.point(x: point.temperature, y: point.fanPercent))
        .gesture(makeGesture(index, size))
    }
  }
}
