//
//  CPULoadSampler.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026, all rights reserved.
//

import Darwin
import Foundation
import IOKit

/// Reads the GPU utilization percent from the IOAccelerator IORegistry
/// node. Returns zero if unavailable. Safe to call from any thread.
func readGPULoadPercent() -> Double {
    readIOAcceleratorDeviceUtilizationPercent(defaultValue: 0)
}

/// Lightweight CPU load sampler for the Agent-owned runtime snapshot.
/// Each instance keeps its own baseline and returns a smoothed percent
/// (0 to 100) based on the diff between successive ticks. Callers are
/// expected to call sample() on a steady cadence (once per second or so).
final class CPULoadSampler: @unchecked Sendable {
    private struct CPUTick {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32
    }

    private var prev: CPUTick?
    private var ema: Double = 0
    private let emaAlpha: Double

    /// emaAlpha controls smoothing. 0.3 responds in a few seconds and
    /// damps out short compile spikes.
    init(emaAlpha: Double = 0.3) {
        self.emaAlpha = emaAlpha
    }

    /// Returns the instantaneous CPU percent (unfiltered). Use smoothed()
    /// for the EMA-smoothed value that is safer for fan control decisions.
    @discardableResult
    func sample() -> Double {
        var numCpus: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let err = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCpus,
            &cpuInfo,
            &numCpuInfo)
        guard err == KERN_SUCCESS, let cpuInfo else { return ema }

        var user: UInt32 = 0
        var system: UInt32 = 0
        var idle: UInt32 = 0
        var nice: UInt32 = 0

        for cpuIndex in 0..<Int(numCpus) {
            let base = Int(CPU_STATE_MAX) * cpuIndex
            user &+= UInt32(cpuInfo[base + Int(CPU_STATE_USER)])
            system &+= UInt32(cpuInfo[base + Int(CPU_STATE_SYSTEM)])
            idle &+= UInt32(cpuInfo[base + Int(CPU_STATE_IDLE)])
            nice &+= UInt32(cpuInfo[base + Int(CPU_STATE_NICE)])
        }

        let size = vm_size_t(Int(numCpuInfo) * MemoryLayout<integer_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)

        defer { prev = CPUTick(user: user, system: system, idle: idle, nice: nice) }

        guard let prev else { return 0 }
        let dUser = Double(user &- prev.user)
        let dSys = Double(system &- prev.system)
        let dIdle = Double(idle &- prev.idle)
        let dNice = Double(nice &- prev.nice)
        let total = dUser + dSys + dIdle + dNice
        guard total > 0 else { return ema }
        let used = dUser + dSys + dNice
        let instant = min(100, max(0, used / total * 100))

        ema = emaAlpha * instant + (1 - emaAlpha) * ema
        return instant
    }

    /// EMA smoothed load percent (0 to 100). Prefer this over sample() for
    /// fan control so short load bursts do not trigger the floor.
    var smoothed: Double { ema }
}
