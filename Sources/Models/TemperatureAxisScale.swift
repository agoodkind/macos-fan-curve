//
//  TemperatureAxisScale.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-01.
//  Copyright © 2026
//

import Foundation

struct TemperatureAxisScale: Sendable {
    static let fanCurveDefault = TemperatureAxisScale(
        controlPointTemperaturesC: [35, 78, 84, 90, 96, 101, 106, 110],
        minorTickStepC: 2.5,
        majorTickStepC: 10
    )

    let temperatureRangeC: ClosedRange<Double>
    let controlPointTemperaturesC: [Double]
    let minorTickTemperaturesC: [Double]
    let majorTickTemperaturesC: [Double]

    init(
        controlPointTemperaturesC: [Double],
        minorTickStepC: Double,
        majorTickStepC: Double
    ) {
        let safeControlPointTemperatures = Self.sanitizedControlPointTemperatures(
            controlPointTemperaturesC
        )
        let safeTemperatureRange =
            safeControlPointTemperatures[
                0]...safeControlPointTemperatures[safeControlPointTemperatures.count - 1]
        self.temperatureRangeC = safeTemperatureRange
        self.controlPointTemperaturesC = safeControlPointTemperatures
        self.minorTickTemperaturesC = Self.intervalTicks(
            in: safeTemperatureRange,
            stepC: minorTickStepC
        )
        self.majorTickTemperaturesC = Self.intervalTicks(
            in: safeTemperatureRange,
            stepC: majorTickStepC
        )
    }

    func fraction(for temperatureC: Double) -> Double {
        let clampedTemperature = max(
            temperatureRangeC.lowerBound, min(temperatureRangeC.upperBound, temperatureC))
        guard let firstTemperature = controlPointTemperaturesC.first else { return 0 }
        guard let lastTemperature = controlPointTemperaturesC.last else { return 0 }

        if clampedTemperature <= firstTemperature { return 0 }
        if clampedTemperature >= lastTemperature { return 1 }

        for pointIndex in 0..<(controlPointTemperaturesC.count - 1) {
            let leftTemperature = controlPointTemperaturesC[pointIndex]
            let rightTemperature = controlPointTemperaturesC[pointIndex + 1]
            if clampedTemperature >= leftTemperature, clampedTemperature <= rightTemperature {
                return fraction(
                    temperatureC: clampedTemperature,
                    pointIndex: pointIndex,
                    leftTemperature: leftTemperature,
                    rightTemperature: rightTemperature
                )
            }
        }

        return 1
    }

    func temperatureC(at fraction: Double) -> Double {
        let clampedFraction = max(0, min(1, fraction))
        guard clampedFraction > 0 else { return temperatureRangeC.lowerBound }
        guard clampedFraction < 1 else { return temperatureRangeC.upperBound }
        let scaledFraction = clampedFraction * Double(controlPointTemperaturesC.count - 1)
        let pointIndex = min(
            controlPointTemperaturesC.count - 2,
            max(0, Int(scaledFraction.rounded(.down)))
        )
        let localFraction = scaledFraction - Double(pointIndex)
        return Self.interpolate(
            lowerBound: controlPointTemperaturesC[pointIndex],
            upperBound: controlPointTemperaturesC[pointIndex + 1],
            progress: localFraction
        )
    }

    private static func intervalTicks(
        in temperatureRangeC: ClosedRange<Double>,
        stepC: Double
    ) -> [Double] {
        let safeStep = max(1, stepC)
        var ticks = [temperatureRangeC.lowerBound]
        var nextTick = ceil(temperatureRangeC.lowerBound / safeStep) * safeStep
        if nextTick <= temperatureRangeC.lowerBound {
            nextTick += safeStep
        }
        while nextTick < temperatureRangeC.upperBound {
            ticks.append(nextTick)
            nextTick += safeStep
        }
        if ticks.last != temperatureRangeC.upperBound {
            ticks.append(temperatureRangeC.upperBound)
        }
        return ticks
    }

    private static func sanitizedControlPointTemperatures(_ temperatures: [Double]) -> [Double] {
        let sortedTemperatures = temperatures.sorted()
        guard sortedTemperatures.count >= 2 else { return [20, 120] }
        return sortedTemperatures
    }

    private static func interpolate(
        lowerBound: Double,
        upperBound: Double,
        progress: Double
    ) -> Double {
        lowerBound + max(0, min(1, progress)) * (upperBound - lowerBound)
    }

    private func fraction(
        temperatureC: Double,
        pointIndex: Int,
        leftTemperature: Double,
        rightTemperature: Double
    ) -> Double {
        let leftFraction = Double(pointIndex) / Double(controlPointTemperaturesC.count - 1)
        let rightFraction = Double(pointIndex + 1) / Double(controlPointTemperaturesC.count - 1)
        let localFraction =
            (temperatureC - leftTemperature) / (rightTemperature - leftTemperature)
        return Self.interpolate(
            lowerBound: leftFraction, upperBound: rightFraction, progress: localFraction)
    }
}
