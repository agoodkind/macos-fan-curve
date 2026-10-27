//
//  ScratchDefaultsSweepTests.swift
//  ModelTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-10-27.
//  Copyright © 2026, all rights reserved.
//

import Darwin
import Foundation
import Nimble
import XCTest

// MARK: - ScratchDefaultsSweepTestValues

private enum ScratchDefaultsSweepTestValues {
  static let exitedProcessPath = "/usr/bin/true"
  static let successfulExitStatus: Int32 = 0
  static let existenceProbeSignal: Int32 = 0
  static let failedProbeResult: Int32 = -1
  static let label = "ScratchDefaultsSweepTests"
  static let defaultsPlistName = "defaults.plist"
  static let recordedKey = "agentExecutableHash"
  static let recordedValue = "exited-process"
}

// MARK: - ScratchDefaultsSweepSetupError

private enum ScratchDefaultsSweepSetupError: Error {
  case childProcessExitedWithFailure(pid_t, Int32)
  case exitedProcessStillReported(pid_t, Int32, Int32)
  case stalePlistMissing(String)
}

// MARK: - ScratchDefaultsSweepTests

final class ScratchDefaultsSweepTests: XCTestCase {
  func testCreatingScratchDefaultsRemovesFolderOfExitedProcess() throws {
    let exitedProcessID = try Self.runProcessToCompletion()
    try Self.requireProcessExited(exitedProcessID)

    let staleProcessDirectory = ScratchDefaults.rootDirectory
      .appendingPathComponent(String(exitedProcessID), isDirectory: true)
    let stalePlist = try Self.writeStaleDefaults(in: staleProcessDirectory)
    guard FileManager.default.fileExists(atPath: stalePlist.path) else {
      throw ScratchDefaultsSweepSetupError.stalePlistMissing(stalePlist.path)
    }

    let scratch = try ScratchDefaults(label: ScratchDefaultsSweepTestValues.label)
    defer { scratch.remove() }

    expect(FileManager.default.fileExists(atPath: staleProcessDirectory.path)) == false
    expect(FileManager.default.fileExists(atPath: scratch.directory.path)) == true

    scratch.remove()

    expect(FileManager.default.fileExists(atPath: scratch.directory.path)) == false
  }

  private static func runProcessToCompletion() throws -> pid_t {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ScratchDefaultsSweepTestValues.exitedProcessPath)
    try process.run()
    process.waitUntilExit()
    let processID = process.processIdentifier
    let terminationStatus = process.terminationStatus
    guard terminationStatus == ScratchDefaultsSweepTestValues.successfulExitStatus else {
      throw ScratchDefaultsSweepSetupError.childProcessExitedWithFailure(
        processID,
        terminationStatus
      )
    }
    return processID
  }

  private static func requireProcessExited(_ processID: pid_t) throws {
    let probeResult = kill(processID, ScratchDefaultsSweepTestValues.existenceProbeSignal)
    let probeError = errno
    guard
      probeResult == ScratchDefaultsSweepTestValues.failedProbeResult,
      probeError == ESRCH
    else {
      throw ScratchDefaultsSweepSetupError.exitedProcessStillReported(
        processID,
        probeResult,
        probeError
      )
    }
  }

  private static func writeStaleDefaults(in processDirectory: URL) throws -> URL {
    let scratchDirectory = processDirectory.appendingPathComponent(
      "\(ScratchDefaultsSweepTestValues.label)-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: scratchDirectory,
      withIntermediateDirectories: true
    )
    let plist = scratchDirectory.appendingPathComponent(
      ScratchDefaultsSweepTestValues.defaultsPlistName
    )
    let contents = [
      ScratchDefaultsSweepTestValues.recordedKey: ScratchDefaultsSweepTestValues.recordedValue
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: contents,
      format: .binary,
      options: 0
    )
    try data.write(to: plist)
    return plist
  }
}
