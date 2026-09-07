//
//  ReleaseVersionCommandTests.swift
//  ModelTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-09-06.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

final class ReleaseVersionCommandTests: XCTestCase {
  func testVersionCommandPrintsBuildVersionAndExits() throws {
    let productsDirectory = Bundle(for: Self.self).bundleURL
      .deletingLastPathComponent()

    let executableURL =
      productsDirectory
      .appendingPathComponent("Fan Curve.app", isDirectory: true)
      .appendingPathComponent("Contents/MacOS/FanCurve")

    expect(FileManager.default.isExecutableFile(atPath: executableURL.path)) == true

    let standardOutput = Pipe()
    let standardError = Pipe()
    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["version"]
    process.standardOutput = standardOutput
    process.standardError = standardError

    let termination = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in termination.signal() }
    try process.run()

    let waitResult = termination.wait(timeout: .now() + 2)
    if waitResult == .timedOut {
      process.terminate()
      process.waitUntilExit()
      XCTFail("FanCurve version did not exit within two seconds")
      return
    }

    let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: outputData, encoding: .utf8) else {
      XCTFail("FanCurve version output was not UTF-8")
      return
    }

    expect(process.terminationStatus) == 0
    expect(output).to(beginWith("version: "))
    expect(output.trimmingCharacters(in: .whitespacesAndNewlines)) != "version:"
  }
}
