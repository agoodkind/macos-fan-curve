//
//  SystemUsage.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import Combine
import Darwin
import Foundation
import IOKit

/// Polls live CPU and GPU utilization as a percent in zero to one hundred.
@MainActor
final class SystemUsage: ObservableObject {
    @Published var cpuPercent: Double = 0
    @Published var gpuPercent: Double = 0

    private struct CPUTick {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32
    }

    private var prev: CPUTick?
    private var timer: Timer?

    func start() {
        stop()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        cpuPercent = readCPU()
        gpuPercent = readGPU()
    }

    /// Aggregate CPU usage. Uses host_processor_info and diffs against the
    /// previous sample. The very first sample returns zero until a baseline
    /// exists.
    private func readCPU() -> Double {
        var numCpus: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let err = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCpus,
            &cpuInfo,
            &numCpuInfo)
        guard err == KERN_SUCCESS, let cpuInfo else { return cpuPercent }

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
        guard total > 0 else { return cpuPercent }
        let used = dUser + dSys + dNice
        return min(100, max(0, used / total * 100))
    }

    /// GPU utilization on Apple Silicon. Reads the "Device Utilization %"
    /// performance statistic from the IOAccelerator IORegistry node.
    private func readGPU() -> Double {
        var iter: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iter)
        guard result == KERN_SUCCESS else { return gpuPercent }
        defer { IOObjectRelease(iter) }

        while case let entry = IOIteratorNext(iter), entry != 0 {
            defer { IOObjectRelease(entry) }

            var props: Unmanaged<CFMutableDictionary>?
            guard
                IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                let dict = props?.takeRetainedValue() as? [String: Any],
                let perf = dict["PerformanceStatistics"] as? [String: Any]
            else { continue }

            if let utilization = perf["Device Utilization %"] as? Double {
                return min(100, max(0, utilization))
            }
            if let utilization = perf["Device Utilization %"] as? Int {
                return min(100, max(0, Double(utilization)))
            }
        }
        return 0
    }
}
