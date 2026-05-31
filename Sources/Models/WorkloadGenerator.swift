//
//  WorkloadGenerator.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Combine
import CryptoKit
import Foundation
import Metal
import MetalPerformanceShaders
import os.signpost

private let signposter = AppLog.signposter(category: "WorkloadGenerator")

// MARK: - Constants

private enum WorkloadGeneratorConstants {
    // CPU stress: minimum cores hashed and per-core scratch buffer size in bytes
    static let minimumStressCores: Int = 2
    static let cpuBufferBytes: Int = 4_096
    static let randomByteUpperBound: UInt8 = 255

    // GPU stress: square matrix edge length for repeated multiplies
    static let matrixDimension: Int = 1_024
}

/// Drives CPU and GPU under load so a fan curve sampler can observe how
/// thermalmonitord responds across the thermal band. Use `start` to begin,
/// `stop` to halt. Safe to call multiple times.
@MainActor
final class WorkloadGenerator: ObservableObject {
    @Published var isRunning = false

    private var cpuCancellation: StressCancellation?
    private var gpuCancellation: StressCancellation?

    func start(cpu: Bool, gpu: Bool) {
        if isRunning { return }
        isRunning = true
        if cpu {
            let cancellation = StressCancellation()
            cpuCancellation = cancellation
            DispatchQueue.global(qos: .utility).async {
                Self.runCPUStress(cancellation: cancellation)
            }
        }
        if gpu {
            let cancellation = StressCancellation()
            gpuCancellation = cancellation
            DispatchQueue.global(qos: .utility).async {
                Self.runGPUStress(cancellation: cancellation)
            }
        }
    }

    func stop() {
        cpuCancellation?.cancel()
        gpuCancellation?.cancel()
        cpuCancellation = nil
        gpuCancellation = nil
        isRunning = false
    }

    /// One SHA256 loop per logical core. Saturates the CPU quickly.
    nonisolated private static func runCPUStress(cancellation: StressCancellation) {
        let state = signposter.beginInterval("cpu.stress")
        defer { signposter.endInterval("cpu.stress", state) }
        let cores = max(
            WorkloadGeneratorConstants.minimumStressCores,
            ProcessInfo.processInfo.activeProcessorCount)
        DispatchQueue.concurrentPerform(iterations: cores) { _ in
            var buffer = [UInt8](repeating: 0, count: WorkloadGeneratorConstants.cpuBufferBytes)
            while !cancellation.isCancelled {
                for byteIndex in 0..<buffer.count {
                    buffer[byteIndex] = UInt8.random(
                        in: 0...WorkloadGeneratorConstants.randomByteUpperBound)
                }
                _ = SHA256.hash(data: buffer)
            }
        }
    }

    /// Repeated 1024x1024 matrix multiplies on the default Metal device.
    /// Cancels cleanly when the task is cancelled.
    nonisolated private static func runGPUStress(cancellation: StressCancellation) {
        let state = signposter.beginInterval("gpu.stress")
        defer { signposter.endInterval("gpu.stress", state) }
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let queue = device.makeCommandQueue()
        else { return }

        let matrixDimension = WorkloadGeneratorConstants.matrixDimension
        let bytes = matrixDimension * matrixDimension * MemoryLayout<Float>.stride
        guard
            let bufferA = device.makeBuffer(length: bytes, options: .storageModeShared),
            let bufferB = device.makeBuffer(length: bytes, options: .storageModeShared),
            let bufferC = device.makeBuffer(length: bytes, options: .storageModeShared)
        else { return }

        // Fill A and B with random floats once.
        let ptrA = bufferA.contents().bindMemory(
            to: Float.self, capacity: matrixDimension * matrixDimension)
        let ptrB = bufferB.contents().bindMemory(
            to: Float.self, capacity: matrixDimension * matrixDimension)
        for valueIndex in 0..<(matrixDimension * matrixDimension) {
            ptrA[valueIndex] = Float.random(in: 0...1)
            ptrB[valueIndex] = Float.random(in: 0...1)
        }

        let descA = MPSMatrixDescriptor(
            rows: matrixDimension,
            columns: matrixDimension,
            rowBytes: matrixDimension * MemoryLayout<Float>.stride,
            dataType: .float32)
        let descB = descA
        let descC = descA
        let matA = MPSMatrix(buffer: bufferA, descriptor: descA)
        let matB = MPSMatrix(buffer: bufferB, descriptor: descB)
        let matC = MPSMatrix(buffer: bufferC, descriptor: descC)

        let kernel = MPSMatrixMultiplication(
            device: device,
            transposeLeft: false,
            transposeRight: false,
            resultRows: matrixDimension,
            resultColumns: matrixDimension,
            interiorColumns: matrixDimension,
            alpha: 1.0,
            beta: 0.0)

        while !cancellation.isCancelled {
            guard let cmd = queue.makeCommandBuffer() else { break }
            kernel.encode(
                commandBuffer: cmd, leftMatrix: matA, rightMatrix: matB, resultMatrix: matC)
            cmd.commit()
            cmd.waitUntilCompleted()
        }
    }
}

private final class StressCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
