//
//  RPMFanIcon.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026
//

import SwiftUI

struct RPMFanIcon: View {
    let rpm: Float
    let minRPM: Float
    let maxRPM: Float
    let renderMode: AppRenderMode

    private var isSpinning: Bool { rpm > 0 }

    private var rotationsPerSecond: Double {
        guard maxRPM > minRPM else { return 0.8 }
        let normalized = max(0, min(1, Double((rpm - minRPM) / (maxRPM - minRPM))))
        return 0.35 + normalized * 1.8
    }

    var body: some View {
        if renderMode.isVisible, isSpinning {
            TimelineView(renderMode.frameProfilerSchedule) { context in
                Image(systemName: "fan.fill")
                    .font(.caption)
                    .foregroundColor(Color.accentColor)
                    .rotationEffect(
                        .degrees(
                            context.date.timeIntervalSinceReferenceDate
                                * rotationsPerSecond * 360.0
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
