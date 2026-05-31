//
//  RPMFanIcon.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

private enum RPMFanIconConstants {
    static let fallbackRotationsPerSecond: Double = 0.8
    static let minRotationsPerSecond: Double = 0.35
    static let rotationsPerSecondRange: Double = 1.8
    static let degreesPerRotation: Double = 360.0
}

struct RPMFanIcon: View {
    let rpm: Float
    let minRPM: Float
    let maxRPM: Float
    let renderMode: AppRenderMode

    private var isSpinning: Bool { rpm > 0 }

    private var rotationsPerSecond: Double {
        guard maxRPM > minRPM else { return RPMFanIconConstants.fallbackRotationsPerSecond }
        let normalized = max(0, min(1, Double((rpm - minRPM) / (maxRPM - minRPM))))
        return RPMFanIconConstants.minRotationsPerSecond
            + normalized * RPMFanIconConstants.rotationsPerSecondRange
    }

    var body: some View {
        if renderMode.allowsLiveAnimation, isSpinning {
            TimelineView(renderMode.frameProfilerSchedule) { context in
                Image(systemName: "fan.fill")
                    .font(.caption)
                    .foregroundColor(Color.accentColor)
                    .rotationEffect(
                        .degrees(
                            context.date.timeIntervalSinceReferenceDate
                                * rotationsPerSecond
                                * RPMFanIconConstants.degreesPerRotation
                        )
                    )
            }
            .id(renderMode)
        } else {
            Image(systemName: "fan.fill")
                .font(.caption)
                .foregroundColor(isSpinning ? Color.accentColor : .secondary)
        }
    }
}
