//
//  FanCurveTestControlCommand.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import AppLog
  import Foundation

  private let testControlCommandLog = AppLog.make(category: "TestControlCommand")

  struct TestControlAcknowledgmentWait: Equatable, Sendable {
    let participant: TestControlParticipant
    let revision: UInt64
    let timeout: TimeInterval
  }

  struct TestControlEventWait: Equatable, Sendable {
    let participant: TestControlParticipant
    let kind: TestControlEventKind
    let revision: UInt64
    let timeout: TimeInterval
  }

  enum FanCurveTestControlCommand: Equatable, Sendable {
    private static let optionPairSize = 2
    private static let firstOptionValueIndex = 1

    case apply(sessionPath: String, statePath: String)
    case exportEvidence(sessionPath: String, outputPath: String)
    case initialize(sessionPath: String)
    case waitAcknowledgment(sessionPath: String, wait: TestControlAcknowledgmentWait)
    case waitEvent(sessionPath: String, wait: TestControlEventWait)

    static func parse(_ arguments: [String]) throws -> FanCurveTestControlCommand {
      guard let name = arguments.first else {
        throw TestControlError.invalidArguments(Self.usage)
      }
      let options = try parseOptions(Array(arguments.dropFirst()))
      switch name {
      case "initialize":
        try options.requireExactly(["--session"])
        return .initialize(sessionPath: try options.required("--session"))
      case "apply":
        try options.requireExactly(["--session", "--state"])
        return .apply(
          sessionPath: try options.required("--session"),
          statePath: try options.required("--state")
        )
      case "wait-ack":
        try options.requireExactly([
          "--participant", "--revision", "--session", "--timeout",
        ])
        return .waitAcknowledgment(
          sessionPath: try options.required("--session"),
          wait: try options.acknowledgmentWait()
        )
      case "wait-event":
        try options.requireExactly([
          "--kind", "--participant", "--revision", "--session", "--timeout",
        ])
        return .waitEvent(
          sessionPath: try options.required("--session"),
          wait: try options.eventWait()
        )
      case "export-evidence":
        try options.requireExactly(["--output", "--session"])
        return .exportEvidence(
          sessionPath: try options.required("--session"),
          outputPath: try options.required("--output")
        )
      default:
        throw TestControlError.invalidArguments(
          "Unknown command \(name)\n\(Self.usage)"
        )
      }
    }

    func run() throws -> String {
      switch self {
      case let .initialize(sessionPath):
        let store = try TestControlSessionStore.initialize(
          at: URL(fileURLWithPath: sessionPath, isDirectory: true)
        )
        let state = try store.loadState()
        testControlCommandLog.info(
          "test_control.command.initialize.completed session=\(state.sessionID.uuidString, privacy: .public) revision=\(state.revision.value, privacy: .public)"
        )
        return
          "initialized session=\(state.sessionID.uuidString) revision=\(state.revision.value)"
      case let .apply(sessionPath, statePath):
        let store = try Self.openStore(sessionPath: sessionPath)
        let data = try Data(contentsOf: URL(fileURLWithPath: statePath))
        let state = try TestControlCodec.decode(TestControlState.self, from: data)
        try store.apply(state)
        testControlCommandLog.info(
          "test_control.command.apply.completed session=\(state.sessionID.uuidString, privacy: .public) revision=\(state.revision.value, privacy: .public)"
        )
        return "applied session=\(state.sessionID.uuidString) revision=\(state.revision.value)"
      case let .waitAcknowledgment(sessionPath, wait):
        let acknowledgment = try Self.openStore(sessionPath: sessionPath)
          .waitForAcknowledgment(
            participant: wait.participant,
            revision: wait.revision,
            timeout: wait.timeout
          )
        return
          "ack participant=\(wait.participant.rawValue) session=\(acknowledgment.sessionID.uuidString) revision=\(acknowledgment.revision.value)"
      case let .waitEvent(sessionPath, wait):
        let event = try Self.openStore(sessionPath: sessionPath)
          .waitForEvent(
            participant: wait.participant,
            kind: wait.kind,
            revision: wait.revision,
            timeout: wait.timeout
          )
        return
          "event participant=\(wait.participant.rawValue) kind=\(wait.kind.rawValue) session=\(event.sessionID.uuidString) revision=\(event.revision.value) event=\(event.eventID.uuidString)"
      case let .exportEvidence(sessionPath, outputPath):
        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
        try Self.openStore(sessionPath: sessionPath).exportEvidence(to: outputURL)
        return "exported path=\(outputURL.standardizedFileURL.path)"
      }
    }

    static let usage = """
      usage:
        FanCurveTestControl initialize --session PATH
        FanCurveTestControl apply --session PATH --state STATE_JSON
        FanCurveTestControl wait-ack --session PATH --participant app|agent --revision N --timeout SECONDS
        FanCurveTestControl wait-event --session PATH --participant app|agent --kind KIND --revision N --timeout SECONDS
        FanCurveTestControl export-evidence --session PATH --output PATH
      """

    private static func parseOptions(_ arguments: [String]) throws -> ParsedOptions {
      guard arguments.count.isMultiple(of: optionPairSize) else {
        throw TestControlError.invalidArguments(Self.usage)
      }
      var values: [String: String] = [:]
      var index = 0
      while index < arguments.count {
        let name = arguments[index]
        let value = arguments[index + firstOptionValueIndex]
        guard name.hasPrefix("--"), values[name] == nil else {
          throw TestControlError.invalidArguments("Invalid or duplicate option \(name)")
        }
        values[name] = value
        index += optionPairSize
      }
      return ParsedOptions(values: values)
    }

    private static func openStore(sessionPath: String) throws -> TestControlSessionStore {
      testControlCommandLog.debug(
        "test_control.command.session.open path=\(sessionPath, privacy: .public)"
      )
      return try TestControlSessionStore.open(
        at: URL(fileURLWithPath: sessionPath, isDirectory: true)
      )
    }
  }

  private struct ParsedOptions {
    let values: [String: String]

    func required(_ name: String) throws -> String {
      guard let value = values[name], !value.isEmpty else {
        throw TestControlError.invalidArguments("Missing required option \(name)")
      }
      return value
    }

    func requireExactly(_ names: Set<String>) throws {
      guard Set(values.keys) == names else {
        let expected = names.sorted().joined(separator: ", ")
        throw TestControlError.invalidArguments("Expected options: \(expected)")
      }
    }

    func participant() throws -> TestControlParticipant {
      let rawValue = try required("--participant")
      guard let participant = TestControlParticipant(rawValue: rawValue) else {
        throw TestControlError.invalidArguments(
          "Participant must be app or agent"
        )
      }
      return participant
    }

    func acknowledgmentWait() throws -> TestControlAcknowledgmentWait {
      try TestControlAcknowledgmentWait(
        participant: participant(),
        revision: revision(),
        timeout: timeout()
      )
    }

    func eventWait() throws -> TestControlEventWait {
      try TestControlEventWait(
        participant: participant(),
        kind: eventKind(),
        revision: revision(),
        timeout: timeout()
      )
    }

    func revision() throws -> UInt64 {
      let rawValue = try required("--revision")
      guard let revision = UInt64(rawValue), revision > 0 else {
        throw TestControlError.invalidArguments(
          "Revision must be a positive integer"
        )
      }
      return revision
    }

    func timeout() throws -> TimeInterval {
      let rawValue = try required("--timeout")
      guard let timeout = TimeInterval(rawValue), timeout > 0, timeout.isFinite else {
        throw TestControlError.invalidArguments(
          "Timeout must be a positive finite number of seconds"
        )
      }
      return timeout
    }

    func eventKind() throws -> TestControlEventKind {
      let rawValue = try required("--kind")
      guard let kind = TestControlEventKind(rawValue: rawValue) else {
        throw TestControlError.invalidArguments("Unknown event kind \(rawValue)")
      }
      return kind
    }
  }
#endif
