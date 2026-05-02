//
//  TemperatureAxisScale.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-01.
//  Copyright © 2026
//

import Darwin
import Foundation

struct TemperatureAxisScale: Sendable {
    static let fanCurveDefault = TemperatureAxisScale(
        temperatureRangeC: 20...110,
        reversalCenterTemperatureC: 80,
        exponentialShape: 25,
        controlPointCount: 8,
        minorTickStepC: 2.5,
        majorTickStepC: 10
    )

    let temperatureRangeC: ClosedRange<Double>
    let reversalCenterTemperatureC: Double
    let exponentialShape: Double
    let controlPointTemperaturesC: [Double]
    let minorTickStepC: Double
    let majorTickStepC: Double
    let minorTickTemperaturesC: [Double]
    let majorTickTemperaturesC: [Double]

    init(
        temperatureRangeC: ClosedRange<Double>,
        reversalCenterTemperatureC: Double,
        exponentialShape: Double,
        controlPointCount: Int,
        minorTickStepC: Double,
        majorTickStepC: Double
    ) {
        let safeReversalCenterTemperature = max(
            temperatureRangeC.lowerBound,
            min(temperatureRangeC.upperBound, reversalCenterTemperatureC)
        )
        let safeExponentialShape = max(0.001, exponentialShape)

        self.temperatureRangeC = temperatureRangeC
        self.reversalCenterTemperatureC = safeReversalCenterTemperature
        self.exponentialShape = safeExponentialShape
        self.controlPointTemperaturesC = Self.evenlySpacedControlPointTemperatures(
            count: controlPointCount,
            temperatureRangeC: temperatureRangeC,
            reversalCenterTemperatureC: safeReversalCenterTemperature,
            exponentialShape: safeExponentialShape
        )
        self.minorTickStepC = minorTickStepC
        self.majorTickStepC = majorTickStepC
        self.minorTickTemperaturesC = Self.intervalTicks(
            in: temperatureRangeC,
            stepC: minorTickStepC
        )
        self.majorTickTemperaturesC = Self.intervalTicks(
            in: temperatureRangeC,
            stepC: majorTickStepC
        )
    }

    func fraction(for temperatureC: Double) -> Double {
        let clampedTemperature = max(temperatureRangeC.lowerBound, min(temperatureRangeC.upperBound, temperatureC))
        let centerFraction = normalizedProgress(
            value: reversalCenterTemperatureC,
            lowerBound: temperatureRangeC.lowerBound,
            upperBound: temperatureRangeC.upperBound
        )

        if clampedTemperature <= reversalCenterTemperatureC {
            let progress = normalizedProgress(
                value: clampedTemperature,
                lowerBound: temperatureRangeC.lowerBound,
                upperBound: reversalCenterTemperatureC
            )
            return centerFraction * exponentialApproachFraction(progress)
        }

        let progress = normalizedProgress(
            value: clampedTemperature,
            lowerBound: reversalCenterTemperatureC,
            upperBound: temperatureRangeC.upperBound
        )
        return centerFraction + (1 - centerFraction) * exponentialReleaseFraction(progress)
    }

    func temperatureC(at fraction: Double) -> Double {
        let clampedFraction = max(0, min(1, fraction))
        guard clampedFraction > 0 else { return temperatureRangeC.lowerBound }
        guard clampedFraction < 1 else { return temperatureRangeC.upperBound }
        let centerFraction = normalizedProgress(
            value: reversalCenterTemperatureC,
            lowerBound: temperatureRangeC.lowerBound,
            upperBound: temperatureRangeC.upperBound
        )

        if clampedFraction <= centerFraction {
            let progress = inverseExponentialApproachFraction(clampedFraction / centerFraction)
            return interpolate(
                lowerBound: temperatureRangeC.lowerBound,
                upperBound: reversalCenterTemperatureC,
                progress: progress
            )
        }

        let progress = inverseExponentialReleaseFraction(
            (clampedFraction - centerFraction) / (1 - centerFraction)
        )
        return interpolate(
            lowerBound: reversalCenterTemperatureC,
            upperBound: temperatureRangeC.upperBound,
            progress: progress
        )
    }

    private func normalizedProgress(
        value: Double,
        lowerBound: Double,
        upperBound: Double
    ) -> Double {
        let span = upperBound - lowerBound
        guard span > 0 else { return 0 }
        return max(0, min(1, (value - lowerBound) / span))
    }

    private func interpolate(
        lowerBound: Double,
        upperBound: Double,
        progress: Double
    ) -> Double {
        lowerBound + max(0, min(1, progress)) * (upperBound - lowerBound)
    }

    private func exponentialApproachFraction(_ progress: Double) -> Double {
        let normalized = max(0, min(1, progress))
        let logBase = log1p(exponentialShape)
        return 1 - (log1p(exponentialShape * (1 - normalized)) / logBase)
    }

    private func exponentialReleaseFraction(_ progress: Double) -> Double {
        let normalized = max(0, min(1, progress))
        let logBase = log1p(exponentialShape)
        return log1p(exponentialShape * normalized) / logBase
    }

    private func inverseExponentialApproachFraction(_ fraction: Double) -> Double {
        let normalized = max(0, min(1, fraction))
        let logBase = log1p(exponentialShape)
        let distanceFromCenter = (exp(logBase * (1 - normalized)) - 1) / exponentialShape
        return 1 - distanceFromCenter
    }

    private func inverseExponentialReleaseFraction(_ fraction: Double) -> Double {
        let normalized = max(0, min(1, fraction))
        let logBase = log1p(exponentialShape)
        return (exp(logBase * normalized) - 1) / exponentialShape
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

    private static func evenlySpacedControlPointTemperatures(
        count: Int,
        temperatureRangeC: ClosedRange<Double>,
        reversalCenterTemperatureC: Double,
        exponentialShape: Double
    ) -> [Double] {
        guard count > 1 else { return [temperatureRangeC.lowerBound] }
        return (0..<count).map { pointIndex in
            let fraction = Double(pointIndex) / Double(count - 1)
            return temperatureC(
                at: fraction,
                temperatureRangeC: temperatureRangeC,
                reversalCenterTemperatureC: reversalCenterTemperatureC,
                exponentialShape: exponentialShape
            )
        }
    }

    private static func temperatureC(
        at fraction: Double,
        temperatureRangeC: ClosedRange<Double>,
        reversalCenterTemperatureC: Double,
        exponentialShape: Double
    ) -> Double {
        let clampedFraction = max(0, min(1, fraction))
        guard clampedFraction > 0 else { return temperatureRangeC.lowerBound }
        guard clampedFraction < 1 else { return temperatureRangeC.upperBound }

        let centerFraction = normalizedProgress(
            value: reversalCenterTemperatureC,
            lowerBound: temperatureRangeC.lowerBound,
            upperBound: temperatureRangeC.upperBound
        )
        if clampedFraction <= centerFraction {
            let progress = inverseExponentialApproachFraction(
                clampedFraction / centerFraction,
                exponentialShape: exponentialShape
            )
            return interpolate(
                lowerBound: temperatureRangeC.lowerBound,
                upperBound: reversalCenterTemperatureC,
                progress: progress
            )
        }

        let progress = inverseExponentialReleaseFraction(
            (clampedFraction - centerFraction) / (1 - centerFraction),
            exponentialShape: exponentialShape
        )
        return interpolate(
            lowerBound: reversalCenterTemperatureC,
            upperBound: temperatureRangeC.upperBound,
            progress: progress
        )
    }

    private static func normalizedProgress(
        value: Double,
        lowerBound: Double,
        upperBound: Double
    ) -> Double {
        let span = upperBound - lowerBound
        guard span > 0 else { return 0 }
        return max(0, min(1, (value - lowerBound) / span))
    }

    private static func interpolate(
        lowerBound: Double,
        upperBound: Double,
        progress: Double
    ) -> Double {
        lowerBound + max(0, min(1, progress)) * (upperBound - lowerBound)
    }

    private static func inverseExponentialApproachFraction(
        _ fraction: Double,
        exponentialShape: Double
    ) -> Double {
        let normalized = max(0, min(1, fraction))
        let logBase = log1p(exponentialShape)
        let distanceFromCenter = (exp(logBase * (1 - normalized)) - 1) / exponentialShape
        return 1 - distanceFromCenter
    }

    private static func inverseExponentialReleaseFraction(
        _ fraction: Double,
        exponentialShape: Double
    ) -> Double {
        let normalized = max(0, min(1, fraction))
        let logBase = log1p(exponentialShape)
        return (exp(logBase * normalized) - 1) / exponentialShape
    }
}
