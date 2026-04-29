//
//  FrameProfilerOverlay.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-27.
//  Copyright © 2026
//

#if DEBUG
    import SwiftUI

    struct FrameProfilerOverlay: View {
        let renderMode: AppRenderMode

        @State private var lastFrameDate: Date?
        @State private var windowStartDate: Date?
        @State private var framesInWindow = 0
        @State private var fps: Double = 0
        @State private var frameMilliseconds: Double = 0

        var body: some View {
            TimelineView(renderMode.frameProfilerSchedule) { context in
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.72), in: Capsule())
                    .allowsHitTesting(false)
                    .onAppear {
                        sampleFrame(at: context.date)
                    }
                    .onChange(of: context.date) { date in
                        sampleFrame(at: date)
                    }
            }
            .onChange(of: renderMode) { _ in
                resetSamples()
            }
        }

        private var label: String {
            String(format: "FPS %.0f  %.1f ms", fps, frameMilliseconds)
        }

        private func sampleFrame(at date: Date) {
            if let lastFrameDate {
                frameMilliseconds = date.timeIntervalSince(lastFrameDate) * 1_000
            }
            lastFrameDate = date

            if windowStartDate == nil {
                windowStartDate = date
            }

            framesInWindow += 1
            guard let windowStartDate else { return }

            let elapsed = date.timeIntervalSince(windowStartDate)
            guard elapsed >= 1 else { return }

            fps = Double(framesInWindow) / elapsed
            framesInWindow = 0
            self.windowStartDate = date
        }

        private func resetSamples() {
            lastFrameDate = nil
            windowStartDate = nil
            framesInWindow = 0
            fps = 0
            frameMilliseconds = 0
        }
    }
#endif
