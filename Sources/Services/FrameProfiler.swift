//
//  FrameProfiler.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-27.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import AppLog
  import CoreVideo
  import Dispatch
  import Foundation
  import os.signpost

  private let frameLog = AppLog.make(category: "FrameProfiler")
  private let frameSignposter = AppLog.signposter(category: "FrameProfiler")

  private enum FrameProfilerConstants {
    static let nanosecondsPerMillisecond: Double = 1_000_000
    static let nanosecondsPerSecond: UInt64 = 1_000_000_000
  }

  /// Lightweight display-cadence profiler for Xcode/Instruments debug sessions.
  ///
  /// Enable from the Xcode scheme with either:
  /// - Environment variable: FANCURVE_FRAME_PROFILER=1
  /// - Launch argument: --profile-frames
  final class FrameProfiler: @unchecked Sendable {
    static let shared = FrameProfiler()

    private let lock = NSLock()
    private let signpostID = frameSignposter.makeSignpostID()
    private var displayLink: CVDisplayLink?
    private var running = false
    private var windowStartNs: UInt64 = 0
    private var previousTickNs: UInt64 = 0
    private var frameCount = 0

    private init() {
      // Singleton only.
    }

    static var isEnabledByLaunchConfiguration: Bool {
      let environment = ProcessInfo.processInfo.environment
      let arguments = ProcessInfo.processInfo.arguments
      return environment["FANCURVE_FRAME_PROFILER"] == "1"
        || environment["FANCURVE_FRAME_PROFILER"]?.lowercased() == "true"
        || arguments.contains("--profile-frames")
    }

    func startIfEnabled() {
      guard Self.isEnabledByLaunchConfiguration else { return }
      start()
    }

    func setSamplingActive(_ active: Bool) {
      guard Self.isEnabledByLaunchConfiguration else { return }
      if active {
        start()
      } else {
        stop()
      }
    }

    func start() {
      lock.lock()
      if running {
        lock.unlock()
        return
      }
      lock.unlock()

      var link: CVDisplayLink?
      let createResult = CVDisplayLinkCreateWithActiveCGDisplays(&link)
      guard createResult == kCVReturnSuccess, let link else {
        frameLog.error("frame_profiler.start_failed code=\(createResult, privacy: .public)")
        return
      }

      let context = Unmanaged.passUnretained(self).toOpaque()
      CVDisplayLinkSetOutputCallback(link, frameProfilerCallback, context)

      let startResult = CVDisplayLinkStart(link)
      guard startResult == kCVReturnSuccess else {
        frameLog.error("frame_profiler.start_failed code=\(startResult, privacy: .public)")
        return
      }

      lock.lock()
      displayLink = link
      running = true
      windowStartNs = 0
      previousTickNs = 0
      frameCount = 0
      lock.unlock()

      frameLog.notice("frame_profiler.started")
    }

    func stop() {
      lock.lock()
      let link = displayLink
      displayLink = nil
      running = false
      lock.unlock()

      if let link {
        CVDisplayLinkStop(link)
        frameLog.notice("frame_profiler.stopped")
      }
    }

    func tick() {
      let nowNs = DispatchTime.now().uptimeNanoseconds

      lock.lock()
      if windowStartNs == 0 {
        windowStartNs = nowNs
        previousTickNs = nowNs
      }

      let frameTimeMs =
        Double(nowNs - previousTickNs)
        / FrameProfilerConstants.nanosecondsPerMillisecond
      previousTickNs = nowNs
      frameCount += 1

      let elapsedNs = nowNs - windowStartNs
      guard elapsedNs >= FrameProfilerConstants.nanosecondsPerSecond else {
        lock.unlock()
        return
      }

      let fps =
        Double(frameCount)
        / (Double(elapsedNs) / Double(FrameProfilerConstants.nanosecondsPerSecond))
      frameCount = 0
      windowStartNs = nowNs
      lock.unlock()

      frameSignposter.emitEvent(
        "frame.sample",
        id: signpostID,
        "fps=\(fps) frame_ms=\(frameTimeMs)"
      )
      frameLog.info(
        "frame.sample fps=\(fps, privacy: .public) frame_ms=\(frameTimeMs, privacy: .public)"
      )
    }
  }

  private let frameProfilerCallback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo in
    guard let userInfo else { return kCVReturnSuccess }
    let profiler = Unmanaged<FrameProfiler>.fromOpaque(userInfo).takeUnretainedValue()
    profiler.tick()
    return kCVReturnSuccess
  }
#endif
