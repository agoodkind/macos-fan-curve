//
//  FrameProfilerMetalProbe.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-27.
//  Copyright © 2026
//

#if DEBUG
    import MetalKit
    import SwiftUI

    struct FrameProfilerMetalProbe: NSViewRepresentable {
        let renderMode: AppRenderMode

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeNSView(context: Context) -> MTKView {
            let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
            view.delegate = context.coordinator
            view.isPaused = !renderMode.isVisible
            view.enableSetNeedsDisplay = false
            view.preferredFramesPerSecond = renderMode.preferredFramesPerSecond
            view.framebufferOnly = true
            view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            view.wantsLayer = true
            return view
        }

        func updateNSView(_ nsView: MTKView, context _: Context) {
            nsView.isPaused = !renderMode.isVisible
            nsView.preferredFramesPerSecond = renderMode.preferredFramesPerSecond
        }

        final class Coordinator: NSObject, MTKViewDelegate {
            private let commandQueue = MTLCreateSystemDefaultDevice()?.makeCommandQueue()

            func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {
                // The probe renders a constant clear pass, so size changes need no extra work.
            }

            func draw(in view: MTKView) {
                guard
                    let commandQueue,
                    let descriptor = view.currentRenderPassDescriptor,
                    let drawable = view.currentDrawable,
                    let commandBuffer = commandQueue.makeCommandBuffer(),
                    let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
                else {
                    return
                }

                encoder.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
            }
        }
    }
#endif
