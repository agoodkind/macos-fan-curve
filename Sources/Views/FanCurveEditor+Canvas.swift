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
  // Percent axis stride
  static let percentGridStride: Double = 0.2

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
  var dashboardXAxis: CurveGraphXAxis {
    CurveGraphXAxis(
      range: plotTempRange,
      minorTicks: temperatureAxisScale.minorTickTemperaturesC,
      majorTicks: temperatureAxisScale.majorTickTemperaturesC,
      labeledTicks: labeledTemperatureTicks(),
      title: "Temperature (\(unit.symbol))",
      label: { temperature in
        "\(self.displayTemp(temperature))\(self.unit.symbol)"
      },
      fractionForValue: { temperature in
        self.temperatureAxisScale.fraction(for: temperature)
      },
      valueAtFraction: { fraction in
        self.temperatureAxisScale.temperatureC(at: fraction)
      }
    )
  }

  var dashboardYAxis: CurveGraphYAxis {
    CurveGraphYAxis(
      ticks: Array(stride(from: 0.0, through: 1.0, by: CanvasConstants.percentGridStride)),
      title: "Fan Speed (% / RPM)",
      label: { percent in
        "\(Int(percent * 100))%"
      },
      secondaryLabel: { percent in
        let rpmRange = self.rpmRange
        let rpm = Int(
          rpmRange.min + Float(percent) * (rpmRange.max - rpmRange.min)
        )
        return rpm.formatted()
      }
    )
  }

  var activeCurveStyle: CurveGraphCurveStyle {
    CurveGraphCurveStyle(
      lineColor: curveColor,
      lineWidth: CanvasConstants.curveMainLineWidth,
      glowColor: curveColor.opacity(CanvasConstants.curveGlowOpacity),
      glowLineWidth: CanvasConstants.curveGlowLineWidth,
      fill: CurveGraphFillStyle(
        startColor: curveColor.opacity(CanvasConstants.curveFillGradientStartOpacity),
        endColor: curveColor.opacity(CanvasConstants.curveFillGradientEndOpacity)
      )
    )
  }

  var inactiveCurveStyle: CurveGraphCurveStyle {
    CurveGraphCurveStyle(
      lineColor: Color.secondary.opacity(CanvasConstants.curveInactiveOpacity),
      lineWidth: CanvasConstants.curveInactiveWidth,
      glowColor: nil,
      glowLineWidth: 0,
      fill: nil
    )
  }

  func drawGrid(context: GraphicsContext, size: CGSize) {
    let renderer = CurveGraphRenderer(graph: graphContext(size: size))
    renderer.drawGrid(
      in: context,
      xAxis: dashboardXAxis,
      yAxis: dashboardYAxis,
      style: .dashboard
    )
  }

  func labeledTemperatureTicks() -> [Double] {
    temperatureAxisScale.controlPointTemperaturesC
  }

  func drawAxisTitles(context: GraphicsContext, size: CGSize) {
    _ = context
    _ = size
  }

  func drawCurve(context: GraphicsContext, size: CGSize) {
    if presentation.showsSystemDefault {
      drawGhostCurve(context: context, size: size, opacity: 1.0 - activePhase)
    }

    let style = effectiveActive ? activeCurveStyle : inactiveCurveStyle
    let renderer = CurveGraphRenderer(graph: graphContext(size: size))
    renderer.drawCurve(
      in: context,
      series: CurveGraphSeries(
        points: model.controlPoints,
        mode: model.interpolationMode,
        steps: CanvasConstants.curveInterpolationSteps,
        axisScale: .fanCurveDefault
      ),
      style: style
    )
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
    CurveGraphRenderer(graph: graphContext(size: size)).curvePixelPoints(
      series: CurveGraphSeries(
        points: points,
        mode: mode,
        steps: CanvasConstants.curveInterpolationSteps,
        axisScale: .fanCurveDefault
      )
    )
  }

  func drawHoverLine(context: GraphicsContext, size: CGSize) {
    guard let mouse = mouseLocation else { return }
    guard draggedIndex == nil, hoveredIndex == nil else { return }
    let graph = graphContext(size: size)
    let data = pixelToData(mouse, in: size)
    guard data.x >= plotTempRange.lowerBound, data.x <= plotTempRange.upperBound else { return }

    let percent = model.evaluate(at: data.x)
    let position = graph.point(x: data.x, y: percent)

    var verticalLine = Path()
    verticalLine.move(to: CGPoint(x: position.x, y: graph.plotTop))
    verticalLine.addLine(to: CGPoint(x: position.x, y: graph.plotBottom))
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
        let anchor = graphContext(size: size).point(
          x: CanvasConstants.overlayReferenceTempC,
          y: ghostAt
        )
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
