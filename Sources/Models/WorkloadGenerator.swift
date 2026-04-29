//
//  WorkloadGenerator.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import AppLog
import Combine
import CryptoKit
import Foundation
import Metal
import MetalPerformanceShaders
import os.signpost

private let signposter = AppLog.signposter(category: "WorkloadGenerator")

/// Drives CPU and GPU under load so a fan curve sampler can observe how
/// thermalmonitord responds across the thermal band. Use `start` to begin,
/// `stop` to halt. Safe to call multiple times.
@MainActor
final class WorkloadGenerator: ObservableObject {
    @Published var isRunning = false

    private var cpuTask: Task<Void, Never>?
    private var gpuTask: Task<Void, Never>?

    func start(cpu: Bool, gpu: Bool) {
        if isRunning { return }
        isRunning = true
        if cpu { cpuTask = Task.detached(priority: .utility) { Self.runCPUStress() } }
        if gpu { gpuTask = Task.detached(priority: .utility) { Self.runGPUStress() } }
    }

    func stop() {
        cpuTask?.cancel()
        gpuTask?.cancel()
        cpuTask = nil
        gpuTask = nil
        isRunning = false
    }

    /// One SHA256 loop per logical core. Saturates the CPU quickly.
    nonisolated private static func runCPUStress() {
        let state = signposter.beginInterval("cpu.stress")
        defer { signposter.endInterval("cpu.stress", state) }
        let cores = max(2, ProcessInfo.processInfo.activeProcessorCount)
        DispatchQueue.concurrentPerform(iterations: cores) { _ in
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while !Task.isCancelled {
                for byteIndex in 0..<buffer.count { buffer[byteIndex] = UInt8.random(in: 0...255) }
                _ = SHA256.hash(data: buffer)
            }
        }
    }

    /// Repeated 1024x1024 matrix multiplies on the default Metal device.
    /// Cancels cleanly when the task is cancelled.
    nonisolated private static func runGPUStress() {
        let state = signposter.beginInterval("gpu.stress")
        defer { signposter.endInterval("gpu.stress", state) }
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let queue = device.makeCommandQueue()
        else { return }

        let matrixDimension = 1_024
        let bytes = matrixDimension * matrixDimension * MemoryLayout<Float>.stride
        guard
            let bufferA = device.makeBuffer(length: bytes, options: .storageModeShared),
            let bufferB = device.makeBuffer(length: bytes, options: .storageModeShared),
            let bufferC = device.makeBuffer(length: bytes, options: .storageModeShared)
        else { return }

        // Fill A and B with random floats once.
        let ptrA = bufferA.contents().bindMemory(to: Float.self, capacity: matrixDimension * matrixDimension)
        let ptrB = bufferB.contents().bindMemory(to: Float.self, capacity: matrixDimension * matrixDimension)
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

        while !Task.isCancelled {
            guard let cmd = queue.makeCommandBuffer() else { break }
            kernel.encode(commandBuffer: cmd, leftMatrix: matA, rightMatrix: matB, resultMatrix: matC)
            cmd.commit()
            cmd.waitUntilCompleted()
        }
    }
}
