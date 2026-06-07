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

  var body: some View {
    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
      let isHighlighted = hoveredIndex == index || draggedIndex == index
      let diameter = isHighlighted ? style.highlightedDiameter : style.normalDiameter
      let lineWidth = isHighlighted ? style.highlightedLineWidth : style.normalLineWidth
      let shadowRadius =
        isHighlighted ? style.highlightedShadowRadius : style.normalShadowRadius
      let hitPadding =
        hitRadius
        - (diameter / CurveGraphSharedConstants.diameterToRadiusDivisor)

      Circle()
        .fill(style.fillColor)
        .frame(width: diameter, height: diameter)
        .overlay(Circle().stroke(style.strokeColor, lineWidth: lineWidth))
        .shadow(color: style.shadowColor, radius: shadowRadius)
        .padding(hitPadding)
        .contentShape(Circle())
        .position(graph.point(x: point.temperature, y: point.fanPercent))
        .animation(
          .spring(
            response: CurveGraphSharedConstants.pointSpringResponse,
            dampingFraction: CurveGraphSharedConstants.pointSpringDampingFraction
          ),
          value: isHighlighted
        )
        .gesture(makeGesture(index, size))
    }
  }
}
