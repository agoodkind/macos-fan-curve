//
//  TestControlSessionStore.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import AppLog
  import Darwin
  import Foundation

  let testControlStoreLog = AppLog.make(category: "TestControlStore")

  enum TestControlFilePermissions {
    static let directory = 0o700
    static let regularFile = 0o600
  }

  enum TestControlJSONLines {
    static let delimiter: UInt8 = 0x0A
  }

  enum TestControlError: Error, Equatable, LocalizedError {
    case acknowledgmentParticipantMismatch(
      expected: TestControlParticipant,
      actual: TestControlParticipant
    )
    case controlStateAlreadyExists(String)
    case evidenceDestinationNotEmpty(String)
    case futureRevision(current: UInt64, proposed: UInt64)
    case invalidArguments(String)
    case invalidControlValue(String)
    case invalidSession(expected: UUID, actual: UUID)
    case missingControlState(String)
    case revisionNotIncreasing(current: UInt64, proposed: UInt64)
    case timeout(String)
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
      switch self {
      case let .acknowledgmentParticipantMismatch(expected, actual):
        return
          "Acknowledgment participant \(actual.rawValue) does not match \(expected.rawValue)"
      case .controlStateAlreadyExists(let path):
        return "A control session already exists at \(path)"
      case .evidenceDestinationNotEmpty(let path):
        return "Evidence destination is not empty: \(path)"
      case let .futureRevision(current, proposed):
        return "Revision \(proposed) is newer than control revision \(current)"
      case .invalidArguments(let message):
        return message
      case .invalidControlValue(let message):
        return message
      case let .invalidSession(expected, actual):
        return "Session \(actual.uuidString) does not match \(expected.uuidString)"
      case .missingControlState(let path):
        return "Control state is missing at \(path)"
      case let .revisionNotIncreasing(current, proposed):
        return "Revision \(proposed) must be greater than \(current)"
      case .timeout(let condition):
        return "Timed out waiting for \(condition)"
      case .unsupportedSchemaVersion(let version):
        return "Unsupported test control schema version \(version)"
      }
    }
  }

  enum TestControlFile {
    static let control = "control.json"
    static let sessionLock = ".session.lock"

    static func acknowledgment(for participant: TestControlParticipant) -> String {
      "\(participant.rawValue).ack.json"
    }

    static func acknowledgmentLock(for participant: TestControlParticipant) -> String {
      ".\(participant.rawValue).ack.lock"
    }

    static func events(for participant: TestControlParticipant) -> String {
      "\(participant.rawValue).events.jsonl"
    }

    static func eventsLock(for participant: TestControlParticipant) -> String {
      ".\(participant.rawValue).events.lock"
    }

    static var evidenceFiles: [String] {
      [
        control,
        acknowledgment(for: .app),
        acknowledgment(for: .agent),
        events(for: .app),
        events(for: .agent),
      ]
    }

    static var evidenceLocksInOrder: [String] {
      [
        sessionLock,
        acknowledgmentLock(for: .app),
        acknowledgmentLock(for: .agent),
        eventsLock(for: .app),
        eventsLock(for: .agent),
      ]
    }
  }

  enum TestControlCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
      try JSONDecoder().decode(type, from: data)
    }
  }

  struct TestControlSessionStore: Equatable, Sendable {
    let directory: URL

    static func initialize(
      at directory: URL,
      initialState: TestControlState = .initial()
    ) throws -> TestControlSessionStore {
      testControlStoreLog.info(
        "test_control.session.initialize.started path=\(directory.path, privacy: .public) session=\(initialState.sessionID.uuidString, privacy: .public) revision=\(initialState.revision.value, privacy: .public)"
      )
      try createSessionDirectory(at: directory)
      let store = TestControlSessionStore(directory: directory.standardizedFileURL)
      try store.withExclusiveLock(fileName: TestControlFile.sessionLock) {
        guard !FileManager.default.fileExists(atPath: store.controlURL.path) else {
          throw TestControlError.controlStateAlreadyExists(store.controlURL.path)
        }
        try store.validate(state: initialState)
        try store.writeAtomically(initialState, to: store.controlURL)
      }
      testControlStoreLog.info(
        "test_control.session.initialize.completed path=\(store.directory.path, privacy: .public) session=\(initialState.sessionID.uuidString, privacy: .public) revision=\(initialState.revision.value, privacy: .public)"
      )
      return store
    }

    static func open(at directory: URL) throws -> TestControlSessionStore {
      let store = TestControlSessionStore(directory: directory.standardizedFileURL)
      testControlStoreLog.info(
        "test_control.session.open.started path=\(store.directory.path, privacy: .public)"
      )
      _ = try store.loadState()
      testControlStoreLog.info(
        "test_control.session.open.completed path=\(store.directory.path, privacy: .public)"
      )
      return store
    }

    var controlURL: URL {
      directory.appendingPathComponent(TestControlFile.control)
    }

    func loadState() throws -> TestControlState {
      guard FileManager.default.fileExists(atPath: controlURL.path) else {
        testControlStoreLog.error(
          "test_control.state.missing path=\(controlURL.path, privacy: .public) recovery=refuse-session"
        )
        throw TestControlError.missingControlState(controlURL.path)
      }
      do {
        let data = try Data(contentsOf: controlURL)
        let state = try TestControlCodec.decode(TestControlState.self, from: data)
        try validate(state: state)
        testControlStoreLog.debug(
          "test_control.state.loaded session=\(state.sessionID.uuidString, privacy: .public) revision=\(state.revision.value, privacy: .public)"
        )
        return state
      } catch {
        testControlStoreLog.error(
          "test_control.state.load_failed path=\(controlURL.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=refuse-session"
        )
        throw error
      }
    }

    func apply(_ proposedState: TestControlState) throws {
      testControlStoreLog.info(
        "test_control.state.apply.started session=\(proposedState.sessionID.uuidString, privacy: .public) revision=\(proposedState.revision.value, privacy: .public)"
      )
      try withExclusiveLock(fileName: TestControlFile.sessionLock) {
        let currentState = try loadState()
        try validateSession(proposedState.sessionID, expected: currentState.sessionID)
        guard proposedState.revision > currentState.revision else {
          testControlStoreLog.error(
            "test_control.revision.rejected current=\(currentState.revision.value, privacy: .public) proposed=\(proposedState.revision.value, privacy: .public) recovery=preserve-current-state"
          )
          throw TestControlError.revisionNotIncreasing(
            current: currentState.revision.value,
            proposed: proposedState.revision.value
          )
        }
        try validate(state: proposedState)
        try writeAtomically(proposedState, to: controlURL)
      }
      testControlStoreLog.info(
        "test_control.state.apply.completed session=\(proposedState.sessionID.uuidString, privacy: .public) revision=\(proposedState.revision.value, privacy: .public)"
      )
    }

    static func createSessionDirectory(at directory: URL) throws {
      do {
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: TestControlFilePermissions.directory]
        )
      } catch {
        testControlStoreLog.error(
          "test_control.directory.create_failed path=\(directory.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=abort-operation"
        )
        throw error
      }
    }

    func acknowledgmentURL(for participant: TestControlParticipant) -> URL {
      directory.appendingPathComponent(TestControlFile.acknowledgment(for: participant))
    }

    func eventsURL(for participant: TestControlParticipant) -> URL {
      directory.appendingPathComponent(TestControlFile.events(for: participant))
    }

    func validate(state: TestControlState) throws {
      guard state.revision.value > 0 else {
        throw TestControlError.invalidControlValue("Revision must be greater than zero")
      }
      try validatePercentage(state.hardware.cpuLoadPercent, name: "CPU load")
      try validatePercentage(state.hardware.gpuLoadPercent, name: "GPU load")
      var fanIndices = Set<Int>()
      for fan in state.hardware.fanReadings {
        guard fan.fanIndex >= 0 else {
          throw TestControlError.invalidControlValue("Fan index cannot be negative")
        }
        guard fanIndices.insert(fan.fanIndex).inserted else {
          throw TestControlError.invalidControlValue(
            "Fan index \(fan.fanIndex) appears more than once"
          )
        }
        guard fan.minimumRPM.isFinite, fan.maximumRPM.isFinite,
          fan.actualRPM.isFinite, fan.targetRPM.isFinite
        else {
          throw TestControlError.invalidControlValue("Fan RPM values must be finite")
        }
        guard fan.minimumRPM <= fan.maximumRPM else {
          throw TestControlError.invalidControlValue(
            "Fan minimum RPM cannot exceed maximum RPM"
          )
        }
      }
      for sensor in state.hardware.sensorTemperatures {
        guard !sensor.name.isEmpty, sensor.temperatureC.isFinite else {
          throw TestControlError.invalidControlValue(
            "Sensor names cannot be empty and temperatures must be finite"
          )
        }
      }
      testControlStoreLog.debug(
        "test_control.state.validated session=\(state.sessionID.uuidString, privacy: .public) revision=\(state.revision.value, privacy: .public)"
      )
    }

    private func validatePercentage(_ value: Double, name: String) throws {
      guard value.isFinite, (0...100).contains(value) else {
        throw TestControlError.invalidControlValue("\(name) must be between 0 and 100")
      }
    }

    func validateEnvelope(
      sessionID: UUID,
      revision: TestControlRevision,
      against state: TestControlState
    ) throws {
      try validateSession(sessionID, expected: state.sessionID)
      guard revision.value > 0 else {
        throw TestControlError.invalidControlValue(
          "Revision must be greater than zero"
        )
      }
      guard revision <= state.revision else {
        throw TestControlError.futureRevision(
          current: state.revision.value,
          proposed: revision.value
        )
      }
    }

    private func validateSession(_ actual: UUID, expected: UUID) throws {
      guard actual == expected else {
        throw TestControlError.invalidSession(expected: expected, actual: actual)
      }
    }

    func writeAtomically<T: Encodable>(_ value: T, to url: URL) throws {
      do {
        let data = try TestControlCodec.encode(value)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
          [.posixPermissions: TestControlFilePermissions.regularFile],
          ofItemAtPath: url.path
        )
        testControlStoreLog.debug(
          "test_control.file.atomic_replace.completed path=\(url.path, privacy: .public)"
        )
      } catch {
        testControlStoreLog.error(
          "test_control.file.atomic_replace.failed path=\(url.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=preserve-previous-file"
        )
        throw error
      }
    }

    func append(_ data: Data, to url: URL) throws {
      if !FileManager.default.fileExists(atPath: url.path) {
        guard
          FileManager.default.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.posixPermissions: TestControlFilePermissions.regularFile]
          )
        else {
          throw TestControlError.invalidControlValue(
            "Could not create evidence file at \(url.path)"
          )
        }
      }
      let handle = try FileHandle(forWritingTo: url)
      defer {
        do {
          try handle.close()
        } catch {
          testControlStoreLog.notice(
            "test_control.file.close_failed path=\(url.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=retain-written-evidence"
          )
        }
      }
      do {
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
      } catch {
        testControlStoreLog.error(
          "test_control.file.append_failed path=\(url.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=abort-operation"
        )
        throw error
      }
    }

    func withExclusiveLock<T>(
      fileName: String,
      operation: () throws -> T
    ) throws -> T {
      let lockURL = directory.appendingPathComponent(fileName)
      let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
      guard descriptor >= 0 else {
        throw POSIXError(.init(rawValue: errno) ?? .EIO)
      }
      defer {
        _ = flock(descriptor, LOCK_UN)
        _ = Darwin.close(descriptor)
      }
      guard flock(descriptor, LOCK_EX) == 0 else {
        let error = POSIXError(.init(rawValue: errno) ?? .EIO)
        testControlStoreLog.error(
          "test_control.lock.acquire_failed path=\(lockURL.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=abort-operation"
        )
        throw error
      }
      testControlStoreLog.debug(
        "test_control.lock.acquired path=\(lockURL.lastPathComponent, privacy: .public)"
      )
      return try operation()
    }

    func withExclusiveLocks<T>(
      fileNames: ArraySlice<String>,
      operation: () throws -> T
    ) throws -> T {
      guard let fileName = fileNames.first else {
        return try operation()
      }
      return try withExclusiveLock(fileName: fileName) {
        try withExclusiveLocks(
          fileNames: fileNames.dropFirst(),
          operation: operation
        )
      }
    }
  }
#endif
