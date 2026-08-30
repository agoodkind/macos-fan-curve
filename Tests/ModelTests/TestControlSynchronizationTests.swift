//
//  TestControlSynchronizationTests.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

@testable import FanCurveModels

final class TestControlSynchronizationTests: XCTestCase {
  private enum Fixture {
    static let initialSemaphoreValue = 0
    static let validIncrement = 1
    static let fanIndex = 0
    static let eventRevision: UInt64 = 8
    static let earlierEventRevision: UInt64 = 7
    static let timeoutRevision: UInt64 = 9
    static let exportRevision: UInt64 = 10
    static let exportedRevision: UInt64 = 11
    static let fanRPM: Float = 2_400
    static let fanPriority = 50
    static let standardTimeout: TimeInterval = 1
    static let timeoutUnderNoise: TimeInterval = 0.05
    static let producerCount = 4
    static let safetyDuration = Duration.milliseconds(300)
    static let maximumWaitDuration = Duration.milliseconds(200)
    static let exportBlockProbe = DispatchTimeInterval.milliseconds(100)
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

  func testWaitEventObservesAppendToExistingParticipantFile() throws {
    let directory = try makeTemporaryDirectory()
    let sessionID = UUID()
    let store = try TestControlSessionStore.initialize(
      at: directory,
      initialState: makeState(
        sessionID: sessionID,
        revision: Fixture.eventRevision
      )
    )
    try store.appendEvent(
      TestControlEvent(
        sessionID: sessionID,
        revision: Fixture.earlierEventRevision,
        participant: .agent,
        payload: .fanAutoReset(fanIndex: Fixture.fanIndex)
      )
    )
    let expectedEvent = TestControlEvent(
      sessionID: sessionID,
      revision: Fixture.eventRevision,
      participant: .agent,
      payload: .fanWrite(
        fanIndex: Fixture.fanIndex,
        rpm: Fixture.fanRPM,
        priority: Fixture.fanPriority
      )
    )
    let observationReady = DispatchSemaphore(
      value: Fixture.initialSemaphoreValue
    )
    let waitCompleted = DispatchSemaphore(
      value: Fixture.initialSemaphoreValue
    )
    nonisolated(unsafe) var waitResult: Result<TestControlEvent, Error>?

    DispatchQueue.global().async {
      waitResult = Result {
        try store.waitForEvent(
          participant: .agent,
          kind: .fanWrite,
          revision: Fixture.eventRevision,
          timeout: Fixture.standardTimeout
        ) {
          observationReady.signal()
        }
      }
      waitCompleted.signal()
    }

    expect(
      observationReady.wait(timeout: .now() + Fixture.standardTimeout)
    ) == .success
    try store.appendEvent(expectedEvent)
    expect(
      waitCompleted.wait(timeout: .now() + Fixture.standardTimeout)
    ) == .success
    expect(try waitResult?.get()) == expectedEvent
  }

  func testWaitTimeoutDoesNotExtendUnderUnrelatedFilesystemSignals() throws {
    let directory = try makeTemporaryDirectory()
    let sessionID = UUID()
    let store = try TestControlSessionStore.initialize(
      at: directory,
      initialState: makeState(
        sessionID: sessionID,
        revision: Fixture.timeoutRevision
      )
    )
    let observationReady = DispatchSemaphore(
      value: Fixture.initialSemaphoreValue
    )
    let waitCompleted = DispatchSemaphore(
      value: Fixture.initialSemaphoreValue
    )
    let stopNoise = DispatchSemaphore(
      value: Fixture.initialSemaphoreValue
    )
    let noiseGroup = DispatchGroup()
    nonisolated(unsafe) var waitResult: Result<TestControlAcknowledgment, Error>?
    nonisolated(unsafe) var elapsed: Duration?

    DispatchQueue.global().async {
      let clock = ContinuousClock()
      let startedAt = clock.now
      waitResult = Result {
        try store.waitForAcknowledgment(
          participant: .agent,
          revision: Fixture.timeoutRevision,
          timeout: Fixture.timeoutUnderNoise
        ) {
          observationReady.signal()
        }
      }
      elapsed = startedAt.duration(to: clock.now)
      waitCompleted.signal()
    }

    expect(
      observationReady.wait(timeout: .now() + Fixture.standardTimeout)
    ) == .success
    startNoise(
      in: directory,
      stopSignal: stopNoise,
      completionGroup: noiseGroup
    )
    expect(
      waitCompleted.wait(timeout: .now() + Fixture.standardTimeout)
    ) == .success
    stopNoiseProducers(stopNoise)
    expect(
      noiseGroup.wait(timeout: .now() + Fixture.standardTimeout)
    ) == .success
    expect {
      try waitResult?.get()
    }.to(throwError())
    let measuredElapsed = try XCTUnwrap(elapsed)
    expect(measuredElapsed < Fixture.maximumWaitDuration) == true
  }

  func testExportWaitsForWritersAndPublishesCoherentSnapshot() throws {
    let directory = try makeTemporaryDirectory()
    let destination = try makeTemporaryDirectory()
    let sessionID = UUID()
    let store = try TestControlSessionStore.initialize(
      at: directory,
      initialState: makeState(
        sessionID: sessionID,
        revision: Fixture.exportRevision
      )
    )
    let exportStarted = DispatchSemaphore(
      value: Fixture.initialSemaphoreValue
    )
    let exportCompleted = DispatchSemaphore(
      value: Fixture.initialSemaphoreValue
    )
    nonisolated(unsafe) var exportResult: Result<Void, Error>?
    let expectedState = makeState(
      sessionID: sessionID,
      revision: Fixture.exportedRevision
    )
    let expectedEvent = TestControlEvent(
      sessionID: sessionID,
      revision: Fixture.exportedRevision,
      participant: .agent,
      payload: .hardwareRead(operation: .fanBatch)
    )

    try store.withExclusiveLock(fileName: TestControlFile.sessionLock) {
      DispatchQueue.global().async {
        exportStarted.signal()
        exportResult = Result {
          try store.exportEvidence(to: destination)
        }
        exportCompleted.signal()
      }
      expect(
        exportStarted.wait(timeout: .now() + Fixture.standardTimeout)
      ) == .success
      expect(
        exportCompleted.wait(timeout: .now() + Fixture.exportBlockProbe)
      ) == .timedOut
      try store.writeAtomically(expectedState, to: store.controlURL)
      try store.appendEvent(expectedEvent)
    }

    expect(
      exportCompleted.wait(timeout: .now() + Fixture.standardTimeout)
    ) == .success
    try exportResult?.get()
    let exportedStore = try TestControlSessionStore.open(at: destination)
    expect(try exportedStore.loadState()) == expectedState
    expect(try exportedStore.loadEvents(for: .agent)) == [expectedEvent]
  }

  private func startNoise(
    in directory: URL,
    stopSignal: DispatchSemaphore,
    completionGroup: DispatchGroup
  ) {
    for producerIndex in 0..<Fixture.producerCount {
      completionGroup.enter()
      DispatchQueue.global().async {
        let clock = ContinuousClock()
        let safetyDeadline = clock.now.advanced(by: Fixture.safetyDuration)
        var sequence = Fixture.initialSemaphoreValue
        while clock.now < safetyDeadline,
          stopSignal.wait(timeout: .now()) == .timedOut
        {
          let noiseURL = directory.appendingPathComponent(
            "noise-\(producerIndex)-\(sequence % Fixture.producerCount)"
          )
          _ = FileManager.default.createFile(
            atPath: noiseURL.path,
            contents: Data()
          )
          sequence += Fixture.validIncrement
        }
        completionGroup.leave()
      }
    }
  }

  private func stopNoiseProducers(_ stopSignal: DispatchSemaphore) {
    for _ in 0..<Fixture.producerCount {
      stopSignal.signal()
    }
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

  private func makeState(
    sessionID: UUID,
    revision: UInt64
  ) -> TestControlState {
    let initialState = TestControlState.initial(sessionID: sessionID)
    return TestControlState(
      sessionID: sessionID,
      revision: revision,
      services: initialState.services,
      hardware: initialState.hardware,
      xpcFault: initialState.xpcFault
    )
  }
}
