//
//  CurveGraphLayout.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-06-04.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

// MARK: - CurveGraphSharedConstants

enum CurveGraphSharedConstants {
  static let tickTolerance: Double = 0.001
  static let pointSpringResponse: Double = 0.25
  static let pointSpringDampingFraction: Double = 0.7
  static let diameterToRadiusDivisor: CGFloat = 2
  static let titleCenterDivisor: CGFloat = 2
  static let minimumDimension: CGFloat = 1
}

// MARK: - DashboardGridStyleConstants

private enum DashboardGridStyleConstants {
  static let gridLineOpacity: Double = 0.05
  static let minorGridLineOpacity: Double = 0.025
  static let majorGridLineOpacity: Double = 0.065
  static let minorGridLineWidth: CGFloat = 0.5
  static let majorGridLineWidth: CGFloat = 0.65
  static let yPrimaryLabelXOffset: CGFloat = 30
  static let ySecondaryLabelFontSize: CGFloat = 9
  static let ySecondaryLabelOpacity: Double = 0.6
  static let ySecondaryLabelYOffset: CGFloat = 11
  static let xLabelFontSize: CGFloat = 10
  static let xLabelYOffset: CGFloat = 14
  static let axisTitleOpacity: Double = 0.8
  static let xAxisTitleYInset: CGFloat = 12
  static let yAxisTitleXInset: CGFloat = 48
  static let yAxisTitleYInset: CGFloat = 24
}

// MARK: - CompactGridStyleConstants

private enum CompactGridStyleConstants {
  static let gridLineOpacity: Double = 0.05
  static let minorGridLineOpacity: Double = 0.025
  static let majorGridLineOpacity: Double = 0.065
  static let gridLineWidth: CGFloat = 0.75
  static let yPrimaryLabelXOffset: CGFloat = 22
  static let ySecondaryLabelFontSize: CGFloat = 9
  static let ySecondaryLabelOpacity: Double = 0.0
  static let ySecondaryLabelYOffset: CGFloat = 0
  static let xLabelFontSize: CGFloat = 9
  static let xLabelYOffset: CGFloat = 10
  static let axisTitleOpacity: Double = 0.8
  static let xAxisTitleYInset: CGFloat = 10
  static let yAxisTitleXInset: CGFloat = 40
  static let yAxisTitleYInset: CGFloat = 16
}

// MARK: - CurveGraphLayout

struct CurveGraphLayout {
  let topPadding: CGFloat
  let bottomPadding: CGFloat
  let leftPadding: CGFloat
  let rightPadding: CGFloat

  func plotFrame(in size: CGSize) -> CGRect {
    let horizontalPadding = leftPadding + rightPadding
    let verticalPadding = topPadding + bottomPadding
    let plotWidth = size.width - horizontalPadding
    let plotHeight = size.height - verticalPadding

    return CGRect(
      x: leftPadding,
      y: topPadding,
      width: plotWidth,
      height: plotHeight
    )
  }
}

// MARK: - CurveGraphXAxis

struct CurveGraphXAxis {
  let range: ClosedRange<Double>
  let minorTicks: [Double]
  let majorTicks: [Double]
  let labeledTicks: [Double]
  let title: String
  let label: (Double) -> String
  let fractionForValue: (Double) -> Double
  let valueAtFraction: (Double) -> Double
}

// MARK: - CurveGraphYAxis

struct CurveGraphYAxis {
  let ticks: [Double]
  let title: String
  let label: (Double) -> String
  let secondaryLabel: ((Double) -> String)?
}

// MARK: - CurveGraphGridStyle

struct CurveGraphGridStyle {
  let gridLineOpacity: Double
  let minorGridLineOpacity: Double
  let majorGridLineOpacity: Double
  let minorGridLineWidth: CGFloat
  let majorGridLineWidth: CGFloat
  let yPrimaryLabelXOffset: CGFloat
  let ySecondaryLabelFontSize: CGFloat
  let ySecondaryLabelOpacity: Double
  let ySecondaryLabelYOffset: CGFloat
  let xLabelFontSize: CGFloat
  let xLabelYOffset: CGFloat
  let axisTitleOpacity: Double
  let xAxisTitleYInset: CGFloat
  let yAxisTitleXInset: CGFloat
  let yAxisTitleYInset: CGFloat

  static let dashboard = CurveGraphGridStyle(
    gridLineOpacity: DashboardGridStyleConstants.gridLineOpacity,
    minorGridLineOpacity: DashboardGridStyleConstants.minorGridLineOpacity,
    majorGridLineOpacity: DashboardGridStyleConstants.majorGridLineOpacity,
    minorGridLineWidth: DashboardGridStyleConstants.minorGridLineWidth,
    majorGridLineWidth: DashboardGridStyleConstants.majorGridLineWidth,
    yPrimaryLabelXOffset: DashboardGridStyleConstants.yPrimaryLabelXOffset,
    ySecondaryLabelFontSize: DashboardGridStyleConstants.ySecondaryLabelFontSize,
    ySecondaryLabelOpacity: DashboardGridStyleConstants.ySecondaryLabelOpacity,
    ySecondaryLabelYOffset: DashboardGridStyleConstants.ySecondaryLabelYOffset,
    xLabelFontSize: DashboardGridStyleConstants.xLabelFontSize,
    xLabelYOffset: DashboardGridStyleConstants.xLabelYOffset,
    axisTitleOpacity: DashboardGridStyleConstants.axisTitleOpacity,
    xAxisTitleYInset: DashboardGridStyleConstants.xAxisTitleYInset,
    yAxisTitleXInset: DashboardGridStyleConstants.yAxisTitleXInset,
    yAxisTitleYInset: DashboardGridStyleConstants.yAxisTitleYInset
  )

  static let compact = CurveGraphGridStyle(
    gridLineOpacity: CompactGridStyleConstants.gridLineOpacity,
    minorGridLineOpacity: CompactGridStyleConstants.minorGridLineOpacity,
    majorGridLineOpacity: CompactGridStyleConstants.majorGridLineOpacity,
    minorGridLineWidth: CompactGridStyleConstants.gridLineWidth,
    majorGridLineWidth: CompactGridStyleConstants.gridLineWidth,
    yPrimaryLabelXOffset: CompactGridStyleConstants.yPrimaryLabelXOffset,
    ySecondaryLabelFontSize: CompactGridStyleConstants.ySecondaryLabelFontSize,
    ySecondaryLabelOpacity: CompactGridStyleConstants.ySecondaryLabelOpacity,
    ySecondaryLabelYOffset: CompactGridStyleConstants.ySecondaryLabelYOffset,
    xLabelFontSize: CompactGridStyleConstants.xLabelFontSize,
    xLabelYOffset: CompactGridStyleConstants.xLabelYOffset,
    axisTitleOpacity: CompactGridStyleConstants.axisTitleOpacity,
    xAxisTitleYInset: CompactGridStyleConstants.xAxisTitleYInset,
    yAxisTitleXInset: CompactGridStyleConstants.yAxisTitleXInset,
    yAxisTitleYInset: CompactGridStyleConstants.yAxisTitleYInset
  )
}

// MARK: - CurveGraphFillStyle

struct CurveGraphFillStyle {
  let startColor: Color
  let endColor: Color
}

// MARK: - CurveGraphCurveStyle

struct CurveGraphCurveStyle {
  let lineColor: Color
  let lineWidth: CGFloat
  let glowColor: Color?
  let glowLineWidth: CGFloat
  let fill: CurveGraphFillStyle?
}

// MARK: - CurveGraphControlPointStyle

struct CurveGraphControlPointStyle {
  let fillColor: Color
  let strokeColor: Color
  let normalDiameter: CGFloat
  let highlightedDiameter: CGFloat
  let normalLineWidth: CGFloat
  let highlightedLineWidth: CGFloat
  let shadowColor: Color
  let normalShadowRadius: CGFloat
  let highlightedShadowRadius: CGFloat
}

// MARK: - CurveGraphSeries

struct CurveGraphSeries {
  let points: [CurvePoint]
  let mode: InterpolationMode
  let steps: Int
  let axisScale: CurveAxisScale?
}

// MARK: - CurveGraphDrawingContext

struct CurveGraphDrawingContext {
  let size: CGSize
  let layout: CurveGraphLayout
  let xAxis: CurveGraphXAxis

  var plotFrame: CGRect {
    layout.plotFrame(in: size)
  }

  var plotLeft: CGFloat {
    plotFrame.minX
  }

  var plotRight: CGFloat {
    plotFrame.maxX
  }

  var plotTop: CGFloat {
    plotFrame.minY
  }

  var plotBottom: CGFloat {
    plotFrame.maxY
  }

  var zeroY: CGFloat {
    point(x: xAxis.range.lowerBound, y: 0).y
  }

  func point(x: Double, y: Double) -> CGPoint {
    let rect = plotFrame
    let clampedX = max(xAxis.range.lowerBound, min(xAxis.range.upperBound, x))
    let clampedY = max(0.0, min(1.0, y))
    let fraction = xAxis.fractionForValue(clampedX)
    let xPosition = rect.minX + (rect.width * CGFloat(fraction))
    let heightOffset = rect.height * CGFloat(clampedY)
    let yPosition = rect.maxY - heightOffset

    return CGPoint(x: xPosition, y: yPosition)
  }

  func data(at point: CGPoint) -> (x: Double, y: Double) {
    let rect = plotFrame
    let width = max(CurveGraphSharedConstants.minimumDimension, rect.width)
    let height = max(CurveGraphSharedConstants.minimumDimension, rect.height)
    let xOffset = point.x - rect.minX
    let yOffset = point.y - rect.minY
    let fraction = max(0.0, min(1.0, Double(xOffset / width)))
    let xValue = xAxis.valueAtFraction(fraction)
    let yValue = 1.0 - Double(yOffset / height)

    return (xValue, yValue)
  }
}
