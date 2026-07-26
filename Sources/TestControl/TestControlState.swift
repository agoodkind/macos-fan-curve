//
//  TestControlState.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import AppLog
  import Foundation

  private let testControlModelsLog = AppLog.make(category: "TestControlModels")

  struct TestControlSchemaVersion: Codable, Equatable, Sendable {
    static let current = TestControlSchemaVersion(validatedValue: 1)

    let value: Int

    private init(validatedValue: Int) {
      self.value = validatedValue
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      let decodedValue = try container.decode(Int.self)
      guard decodedValue == Self.current.value else {
        testControlModelsLog.error(
          "test_control.schema.unsupported value=\(decodedValue, privacy: .public) recovery=refuse-session"
        )
        throw TestControlError.unsupportedSchemaVersion(decodedValue)
      }
      self.init(validatedValue: decodedValue)
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(value)
    }
  }

  struct TestControlRevision:
    Codable,
    Comparable,
    Equatable,
    ExpressibleByIntegerLiteral,
    Sendable
  {
    let value: UInt64

    init(_ value: UInt64) {
      self.value = value
    }

    init(integerLiteral value: UInt64) {
      self.init(value)
    }

    static func < (lhs: TestControlRevision, rhs: TestControlRevision) -> Bool {
      lhs.value < rhs.value
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      self.init(try container.decode(UInt64.self))
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(value)
    }
  }

  enum TestManagedServiceStatus: String, Codable, Equatable, Sendable {
    case approvalRequired = "approval_required"
    case enabled
    case notRegistered = "not_registered"
  }

  enum TestOperationDirective: Codable, Equatable, Sendable {
    case fail(code: String, message: String)
    case succeed
  }

  struct TestServiceState: Codable, Equatable, Sendable {
    let backgroundAgentStatus: TestManagedServiceStatus
    let helperStatus: TestManagedServiceStatus
    let nextOperation: TestOperationDirective
  }

  struct TestSensorTemperature: Codable, Equatable, Sendable {
    let name: String
    let temperatureC: Double
  }

  struct TestFanReading: Codable, Equatable, Sendable {
    let fanIndex: Int
    let name: String
    let actualRPM: Float
    let targetRPM: Float
    let minimumRPM: Float
    let maximumRPM: Float
    let isAutomatic: Bool
  }

  struct TestFanOwnership: Codable, Equatable, Sendable {
    let fanIndex: Int
    let processName: String?
    let priority: Int?
  }

  struct TestRuntimeFlags: Codable, Equatable, Sendable {
    let helperReachable: Bool
    let telemetryStale: Bool
  }

  struct TestHardwareState: Codable, Equatable, Sendable {
    let sensorTemperatures: [TestSensorTemperature]
    let fanReadings: [TestFanReading]
    let ownership: [TestFanOwnership]
    let cpuLoadPercent: Double
    let gpuLoadPercent: Double
    let runtimeFlags: TestRuntimeFlags
    let nextOperation: TestOperationDirective
  }

  enum TestXPCFault: String, Codable, Equatable, Sendable {
    case duplicateEvent = "duplicate_event"
    case interruption
    case invalidation
    case malformedEvent = "malformed_event"
    case malformedInitialState = "malformed_initial_state"
    case malformedReply = "malformed_reply"
    case noFault = "none"
    case reconnect
    case rejectedCommand = "rejected_command"
  }

  struct TestControlState: Codable, Equatable, Sendable {
    let schemaVersion: TestControlSchemaVersion
    let sessionID: UUID
    let revision: TestControlRevision
    let services: TestServiceState
    let hardware: TestHardwareState
    let xpcFault: TestXPCFault

    init(
      sessionID: UUID,
      revision: UInt64,
      services: TestServiceState,
      hardware: TestHardwareState,
      xpcFault: TestXPCFault
    ) {
      self.schemaVersion = .current
      self.sessionID = sessionID
      self.revision = TestControlRevision(revision)
      self.services = services
      self.hardware = hardware
      self.xpcFault = xpcFault
    }

    static func initial(sessionID: UUID = UUID()) -> TestControlState {
      TestControlState(
        sessionID: sessionID,
        revision: 1,
        services: TestServiceState(
          backgroundAgentStatus: .enabled,
          helperStatus: .enabled,
          nextOperation: .succeed
        ),
        hardware: TestHardwareState(
          sensorTemperatures: [],
          fanReadings: [],
          ownership: [],
          cpuLoadPercent: 0,
          gpuLoadPercent: 0,
          runtimeFlags: TestRuntimeFlags(
            helperReachable: true,
            telemetryStale: false
          ),
          nextOperation: .succeed
        ),
        xpcFault: .noFault
      )
    }
  }

  enum TestControlParticipant: String, Codable, CaseIterable, Equatable, Sendable {
    case agent
    case app
  }

  struct TestControlAcknowledgment: Codable, Equatable, Sendable {
    let schemaVersion: TestControlSchemaVersion
    let sessionID: UUID
    let revision: TestControlRevision
    let participant: TestControlParticipant
    let recordedAt: Date

    init(
      sessionID: UUID,
      revision: UInt64,
      participant: TestControlParticipant,
      recordedAt: Date = Date()
    ) {
      self.schemaVersion = .current
      self.sessionID = sessionID
      self.revision = TestControlRevision(revision)
      self.participant = participant
      self.recordedAt = recordedAt
    }
  }

  enum TestServiceName: String, Codable, Equatable, Sendable {
    case backgroundAgent = "background_agent"
    case helper
  }

  enum TestServiceOperation: String, Codable, Equatable, Sendable {
    case openSystemSettings = "open_system_settings"
    case register
    case status
    case unregister
  }

  enum TestProcessLifecyclePhase: String, Codable, Equatable, Sendable {
    case launched
    case ready
    case terminated
  }

  enum TestControlEventPayload: Codable, Equatable, Sendable {
    case appToAgentCommand(command: String)
    case fanAutoReset(fanIndex: Int)
    case fanWrite(fanIndex: Int, rpm: Float, priority: Int)
    case hardwareRead(operation: String)
    case processLifecycle(process: TestControlParticipant, phase: TestProcessLifecyclePhase)
    case serviceMutation(
      service: TestServiceName,
      operation: TestServiceOperation,
      result: TestOperationDirective
    )
    case xpcFault(TestXPCFault)

    var kind: TestControlEventKind {
      switch self {
      case .appToAgentCommand:
        return .appToAgentCommand
      case .fanAutoReset:
        return .fanAutoReset
      case .fanWrite:
        return .fanWrite
      case .hardwareRead:
        return .hardwareRead
      case .processLifecycle:
        return .processLifecycle
      case .serviceMutation:
        return .serviceMutation
      case .xpcFault:
        return .xpcFault
      }
    }
  }

  enum TestControlEventKind: String, Codable, Equatable, Sendable {
    case appToAgentCommand = "app_to_agent_command"
    case fanAutoReset = "fan_auto_reset"
    case fanWrite = "fan_write"
    case hardwareRead = "hardware_read"
    case processLifecycle = "process_lifecycle"
    case serviceMutation = "service_mutation"
    case xpcFault = "xpc_fault"
  }

  struct TestControlEvent: Codable, Equatable, Sendable {
    let schemaVersion: TestControlSchemaVersion
    let sessionID: UUID
    let revision: TestControlRevision
    let participant: TestControlParticipant
    let eventID: UUID
    let recordedAt: Date
    let payload: TestControlEventPayload

    var kind: TestControlEventKind {
      payload.kind
    }

    init(
      sessionID: UUID,
      revision: UInt64,
      participant: TestControlParticipant,
      payload: TestControlEventPayload,
      eventID: UUID = UUID(),
      recordedAt: Date = Date()
    ) {
      self.schemaVersion = .current
      self.sessionID = sessionID
      self.revision = TestControlRevision(revision)
      self.participant = participant
      self.eventID = eventID
      self.recordedAt = recordedAt
      self.payload = payload
    }
  }
#endif
