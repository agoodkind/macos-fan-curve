//
//  LoadAssistCurveEditor.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

private enum LoadAssistCurveEditorConstants {
  static let editorVerticalPadding: CGFloat = 4
  static let backgroundCornerRadius: CGFloat = 10
  static let backgroundFillOpacity: Double = 0.035
  static let backgroundStrokeOpacity: Double = 0.08
  static let backgroundStrokeWidth: CGFloat = 0.5
  static let topPad: CGFloat = 24
  static let bottomPad: CGFloat = 34
  static let leftPad: CGFloat = 56
  static let rightPad: CGFloat = 14
  static let controlPointHitRadius: CGFloat = 12
  static let curveInterpolationSteps: Int = 120
  static let pointNormalDiameter: CGFloat = 10
  static let pointHighlightedDiameter: CGFloat = 12
  static let pointNormalLineWidth: CGFloat = 1.5
  static let pointHighlightedLineWidth: CGFloat = 2.5
  static let pointNormalShadowRadius: CGFloat = 2
  static let pointHighlightedShadowRadius: CGFloat = 5
  static let pointShadowOpacity: Double = 0.22
  static let pointFillOpacity: Double = 0.98
  static let fillStartOpacity: Double = 0.34
  static let fillEndOpacity: Double = 0.16
  static let glowOpacity: Double = 0.16
  static let glowLineWidth: CGFloat = 7
  static let lineWidth: CGFloat = 2.5
  static let quarterPercent: Double = 0.25
  static let halfPercent: Double = 0.5
  static let threeQuarterPercent: Double = 0.75
  static let fullPercent: Double = 1.0
  static let quarterLoad: Double = 25
  static let halfLoad: Double = 50
  static let threeQuarterLoad: Double = 75
  static let fullLoad: Double = 100
  static let percentTicks: [Double] = [
    0,
    quarterPercent,
    halfPercent,
    threeQuarterPercent,
    fullPercent,
  ]
  static let usageTicks: [Double] = [0, quarterLoad, halfLoad, threeQuarterLoad, fullLoad]
}

struct LoadAssistCurveEditor: View {
  @Binding var points: [CurvePoint]
  @State private var hoveredIndex: Int?
  @State private var draggedIndex: Int?

  private let accent = Color(nsColor: .systemTeal)

  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size

      ZStack {
        Canvas { context, canvasSize in
          drawGrid(context: context, size: canvasSize)
          drawCurve(context: context, size: canvasSize)
        }

        CurveGraphControlPointsOverlay(
          points: points,
          size: size,
          graph: graphContext(size: size),
          style: controlPointStyle,
          hitRadius: LoadAssistCurveEditorConstants.controlPointHitRadius,
          hoveredIndex: hoveredIndex,
          draggedIndex: draggedIndex,
          makeGesture: dragGesture
        )
      }
      .onContinuousHover { phase in
        handleHoverPhase(phase, size: size)
      }
    }
    .padding(.vertical, LoadAssistCurveEditorConstants.editorVerticalPadding)
    .background(
      RoundedRectangle(cornerRadius: LoadAssistCurveEditorConstants.backgroundCornerRadius)
        .fill(Color.primary.opacity(LoadAssistCurveEditorConstants.backgroundFillOpacity))
    )
    .overlay(
      RoundedRectangle(cornerRadius: LoadAssistCurveEditorConstants.backgroundCornerRadius)
        .stroke(
          Color.primary.opacity(LoadAssistCurveEditorConstants.backgroundStrokeOpacity),
          lineWidth: LoadAssistCurveEditorConstants.backgroundStrokeWidth
        )
    )
  }

  private var graphLayout: CurveGraphLayout {
    CurveGraphLayout(
      topPadding: LoadAssistCurveEditorConstants.topPad,
      bottomPadding: LoadAssistCurveEditorConstants.bottomPad,
      leftPadding: LoadAssistCurveEditorConstants.leftPad,
      rightPadding: LoadAssistCurveEditorConstants.rightPad
    )
  }

  private var xAxis: CurveGraphXAxis {
    let axisScale = CurveAxisScale.linear(range: LoadAssistCurveColumns.xRange)
    return CurveGraphXAxis(
      range: LoadAssistCurveColumns.xRange,
      minorTicks: LoadAssistCurveEditorConstants.usageTicks,
      majorTicks: LoadAssistCurveEditorConstants.usageTicks,
      labeledTicks: LoadAssistCurveEditorConstants.usageTicks,
      title: "Usage %",
      label: { load in
        "\(Int(load))%"
      },
      fractionForValue: { load in
        axisScale.fraction(for: load)
      },
      valueAtFraction: { fraction in
        axisScale.value(at: fraction)
      }
    )
  }

  private var yAxis: CurveGraphYAxis {
    CurveGraphYAxis(
      ticks: LoadAssistCurveEditorConstants.percentTicks,
      title: "Fan speed %",
      label: { percent in
        "\(Int(percent * 100))%"
      },
      secondaryLabel: nil
    )
  }

  private var curveStyle: CurveGraphCurveStyle {
    CurveGraphCurveStyle(
      lineColor: accent,
      lineWidth: LoadAssistCurveEditorConstants.lineWidth,
      glowColor: accent.opacity(LoadAssistCurveEditorConstants.glowOpacity),
      glowLineWidth: LoadAssistCurveEditorConstants.glowLineWidth,
      fill: CurveGraphFillStyle(
        startColor: accent.opacity(LoadAssistCurveEditorConstants.fillStartOpacity),
        endColor: accent.opacity(LoadAssistCurveEditorConstants.fillEndOpacity)
      )
    )
  }

  private var controlPointStyle: CurveGraphControlPointStyle {
    CurveGraphControlPointStyle(
      fillColor: Color(nsColor: .windowBackgroundColor).opacity(
        LoadAssistCurveEditorConstants.pointFillOpacity
      ),
      strokeColor: accent,
      normalDiameter: LoadAssistCurveEditorConstants.pointNormalDiameter,
      highlightedDiameter: LoadAssistCurveEditorConstants.pointHighlightedDiameter,
      normalLineWidth: LoadAssistCurveEditorConstants.pointNormalLineWidth,
      highlightedLineWidth: LoadAssistCurveEditorConstants.pointHighlightedLineWidth,
      shadowColor: accent.opacity(LoadAssistCurveEditorConstants.pointShadowOpacity),
      normalShadowRadius: LoadAssistCurveEditorConstants.pointNormalShadowRadius,
      highlightedShadowRadius: LoadAssistCurveEditorConstants.pointHighlightedShadowRadius
    )
  }

  private func graphContext(size: CGSize) -> CurveGraphDrawingContext {
    CurveGraphDrawingContext(size: size, layout: graphLayout, xAxis: xAxis)
  }

  private func handleHoverPhase(_ phase: HoverPhase, size: CGSize) {
    switch phase {
    case .active(let location):
      if draggedIndex == nil {
        hoveredIndex = hoveredControlPointIndex(at: location, in: size)
      }
    case .ended:
      if draggedIndex == nil {
        hoveredIndex = nil
      }
    }
  }

  private func dragGesture(index: Int, size: CGSize) -> AnyGesture<DragGesture.Value> {
    AnyGesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          draggedIndex = index
          hoveredIndex = index
          let graph = graphContext(size: size)
          var data = graph.data(at: value.location)
          data.y = max(0.0, min(1.0, data.y))
          applyDraggedPoint(
            index: index,
            proposedLoad: data.x,
            proposedPercent: data.y
          )
        }
        .onEnded { value in
          draggedIndex = nil
          hoveredIndex = hoveredControlPointIndex(at: value.location, in: size)
        }
    )
  }

  private func hoveredControlPointIndex(at location: CGPoint, in size: CGSize) -> Int? {
    let graph = graphContext(size: size)

    return points.enumerated()
      .compactMap { index, point -> (index: Int, distance: CGFloat)? in
        let position = graph.point(x: point.temperature, y: point.fanPercent)
        let distance = hypot(position.x - location.x, position.y - location.y)
        guard distance <= LoadAssistCurveEditorConstants.controlPointHitRadius else {
          return nil
        }
        return (index, distance)
      }
      .min { lhs, rhs in lhs.distance < rhs.distance }?
      .index
  }

  private func applyDraggedPoint(
    index: Int,
    proposedLoad: Double,
    proposedPercent: Double
  ) {
    points = LoadAssistStore.updatedPoints(
      points,
      draggedIndex: index,
      proposedLoad: proposedLoad,
      proposedPercent: proposedPercent
    )
  }

  private func drawGrid(context: GraphicsContext, size: CGSize) {
    let renderer = CurveGraphRenderer(graph: graphContext(size: size))
    renderer.drawGrid(
      in: context,
      xAxis: xAxis,
      yAxis: yAxis,
      style: .compact
    )
  }

  private func drawCurve(context: GraphicsContext, size: CGSize) {
    let renderer = CurveGraphRenderer(graph: graphContext(size: size))
    renderer.drawCurve(
      in: context,
      series: CurveGraphSeries(
        points: points,
        mode: .catmullRom,
        steps: LoadAssistCurveEditorConstants.curveInterpolationSteps,
        axisScale: .linear(range: LoadAssistCurveColumns.xRange)
      ),
      style: curveStyle
    )
  }
}
