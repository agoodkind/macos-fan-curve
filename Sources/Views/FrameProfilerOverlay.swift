//
//  FrameProfilerOverlay.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-27.
//  Copyright © 2026
//

#if DEBUG
    import SwiftUI

    private enum FrameProfilerOverlayConstants {
        static let labelFontSize: CGFloat = 11
        static let labelHorizontalPadding: CGFloat = 8
        static let labelVerticalPadding: CGFloat = 5
        static let labelBackgroundOpacity: Double = 0.72
        static let millisecondsPerSecond: Double = 1_000
    }

    struct FrameProfilerOverlay: View {
        let renderMode: AppRenderMode

        @State private var lastFrameDate: Date?
        @State private var windowStartDate: Date?
        @State private var framesInWindow = 0
        @State private var fps: Double = 0
        @State private var frameMilliseconds: Double = 0

        var body: some View {
            timelineBody
                .id(renderMode)
                .onChange(of: renderMode) { _ in
                    resetSamples()
                }
        }

        @ViewBuilder
        private var timelineBody: some View {
            switch renderMode {
            case .interactive:
                TimelineView(
                    .animation(minimumInterval: 1.0 / Double(renderMode.preferredFramesPerSecond))
                ) { context in
                    labelView(date: context.date)
                }
            case .backgroundVisible, .occluded:
                TimelineView(renderMode.frameProfilerSchedule) { context in
                    labelView(date: context.date)
                }
            }
        }

        private func labelView(date: Date) -> some View {
            Text(label)
                .font(
                    .system(
                        size: FrameProfilerOverlayConstants.labelFontSize,
                        weight: .medium,
                        design: .monospaced)
                )
                .foregroundStyle(.white)
                .padding(.horizontal, FrameProfilerOverlayConstants.labelHorizontalPadding)
                .padding(.vertical, FrameProfilerOverlayConstants.labelVerticalPadding)
                .background(
                    .black.opacity(FrameProfilerOverlayConstants.labelBackgroundOpacity),
                    in: Capsule()
                )
                .allowsHitTesting(false)
                .onAppear {
                    sampleFrame(at: date)
                }
                .onChange(of: date) { nextDate in
                    sampleFrame(at: nextDate)
                }
        }

        private var label: String {
            String(format: "FPS %.0f  %.1f ms", fps, frameMilliseconds)
        }

        private func sampleFrame(at date: Date) {
            if let lastFrameDate {
                frameMilliseconds =
                    date.timeIntervalSince(lastFrameDate)
                    * FrameProfilerOverlayConstants.millisecondsPerSecond
            }
            lastFrameDate = date

            if windowStartDate == nil {
                windowStartDate = date
            }

            framesInWindow += 1
            guard let sampleWindowStartDate = windowStartDate else { return }

            let elapsed = date.timeIntervalSince(sampleWindowStartDate)
            guard elapsed >= 1 else { return }

            fps = Double(framesInWindow) / elapsed
            framesInWindow = 0
            windowStartDate = date
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
