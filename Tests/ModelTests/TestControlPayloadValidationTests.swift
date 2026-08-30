//
//  TestControlPayloadValidationTests.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

@testable import FanCurveModels

final class TestControlPayloadValidationTests: XCTestCase {
  private enum Fixture {
    static let validRevision: UInt64 = 1
    static let zeroRevision: UInt64 = 0
    static let fanIndex = 0
  }

  private var temporaryDirectories: [URL] = []

  override func setUpWithError() throws {
    try super.setUpWithError()
    temporaryDirectories.removeAll()
  }

  override func tearDownWithError() throws {
    for directory in temporaryDirectories
    where FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
    temporaryDirectories.removeAll()
    try super.tearDownWithError()
  }

  func testEventPayloadRejectsUnknownAppCommand() throws {
    let event = TestControlEvent(
      sessionID: UUID(),
      revision: Fixture.validRevision,
      participant: .app,
      payload: .appToAgentCommand(command: .installOrRepairHelper)
    )
    let encodedEvent = try XCTUnwrap(
      String(data: TestControlCodec.encode(event), encoding: .utf8)
    )
    let malformedEvent = encodedEvent.replacingOccurrences(
      of: "installOrRepairHelper",
      with: "installOrRepairHelpr"
    )

    expect {
      try TestControlCodec.decode(
        TestControlEvent.self,
        from: Data(malformedEvent.utf8)
      )
    }.to(throwError())
  }

  func testEventPayloadRejectsUnknownHardwareReadOperation() throws {
    let event = TestControlEvent(
      sessionID: UUID(),
      revision: Fixture.validRevision,
      participant: .agent,
      payload: .hardwareRead(operation: .fanBatch)
    )
    let encodedEvent = try XCTUnwrap(
      String(data: TestControlCodec.encode(event), encoding: .utf8)
    )
    let malformedEvent = encodedEvent.replacingOccurrences(
      of: "fanBatch",
      with: "fanBtch"
    )

    expect {
      try TestControlCodec.decode(
        TestControlEvent.self,
        from: Data(malformedEvent.utf8)
      )
    }.to(throwError())
  }

  func testAcknowledgmentRejectsZeroRevision() throws {
    let directory = try makeTemporaryDirectory()
    let store = try TestControlSessionStore.initialize(at: directory)
    let state = try store.loadState()

    expect {
      try store.writeAcknowledgment(
        TestControlAcknowledgment(
          sessionID: state.sessionID,
          revision: Fixture.zeroRevision,
          participant: .app
        )
      )
    }.to(
      throwError(
        TestControlError.invalidControlValue(
          "Revision must be greater than zero"
        )
      )
    )
  }

  func testEventRejectsZeroRevision() throws {
    let directory = try makeTemporaryDirectory()
    let store = try TestControlSessionStore.initialize(at: directory)
    let state = try store.loadState()

    expect {
      try store.appendEvent(
        TestControlEvent(
          sessionID: state.sessionID,
          revision: Fixture.zeroRevision,
          participant: .agent,
          payload: .fanAutoReset(fanIndex: Fixture.fanIndex)
        )
      )
    }.to(
      throwError(
        TestControlError.invalidControlValue(
          "Revision must be greater than zero"
        )
      )
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "FanCurveTestControl-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false
    )
    temporaryDirectories.append(directory)
    return directory
  }
}
