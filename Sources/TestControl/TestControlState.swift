//
//  TestControlState.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
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

  struct TestSystemHelperIdentity: Codable, Equatable, Sendable {
    let version: String
    let build: String
    let commit: String
    let executableHash: String
    let protocolVersion: UInt
  }

  enum TestHelperIdentityResult: Codable, Equatable, Sendable {
    case identity(TestSystemHelperIdentity)
    case legacy
    case unreachable(message: String)
  }

  struct TestHelperLifecycleState: Codable, Equatable, Sendable {
    let active: TestHelperIdentityResult
    let bundled: TestSystemHelperIdentity
    let verificationBlocked: Bool

    static let bundledIdentity = TestSystemHelperIdentity(
      version: "0.4.2",
      build: "42",
      commit: "bundled-helper-commit",
      executableHash: "bundled-helper-full-hash",
      protocolVersion: 1
    )

    static let defaultState = TestHelperLifecycleState(
      active: .identity(bundledIdentity),
      bundled: bundledIdentity,
      verificationBlocked: false
    )
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
    let ownershipPreempted: Bool

    init(
      helperReachable: Bool,
      telemetryStale: Bool,
      ownershipPreempted: Bool = false
    ) {
      self.helperReachable = helperReachable
      self.telemetryStale = telemetryStale
      self.ownershipPreempted = ownershipPreempted
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      helperReachable = try container.decode(Bool.self, forKey: .helperReachable)
      telemetryStale = try container.decode(Bool.self, forKey: .telemetryStale)
      ownershipPreempted =
        try container.decodeIfPresent(Bool.self, forKey: .ownershipPreempted) ?? false
    }

    private enum CodingKeys: String, CodingKey {
      case helperReachable
      case telemetryStale
      case ownershipPreempted
    }
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

  enum TestXPCFault: String, Codable, Equatable, Hashable, Sendable {
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
    let helperLifecycle: TestHelperLifecycleState
    let xpcFault: TestXPCFault

    init(
      sessionID: UUID,
      revision: UInt64,
      services: TestServiceState,
      hardware: TestHardwareState,
      xpcFault: TestXPCFault,
      helperLifecycle: TestHelperLifecycleState = .defaultState
    ) {
      self.schemaVersion = .current
      self.sessionID = sessionID
      self.revision = TestControlRevision(revision)
      self.services = services
      self.hardware = hardware
      self.helperLifecycle = helperLifecycle
      self.xpcFault = xpcFault
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      schemaVersion = try container.decode(
        TestControlSchemaVersion.self,
        forKey: .schemaVersion
      )
      sessionID = try container.decode(UUID.self, forKey: .sessionID)
      revision = try container.decode(TestControlRevision.self, forKey: .revision)
      services = try container.decode(TestServiceState.self, forKey: .services)
      hardware = try container.decode(TestHardwareState.self, forKey: .hardware)
      helperLifecycle =
        try container.decodeIfPresent(
          TestHelperLifecycleState.self,
          forKey: .helperLifecycle
        ) ?? .defaultState
      xpcFault = try container.decode(TestXPCFault.self, forKey: .xpcFault)
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

  enum TestXPCStateEvent: String, Codable, Equatable, Sendable {
    case commandRejected = "command_rejected"
    case commandReplyMalformed = "command_reply_malformed"
    case connected
    case connecting
    case connectionAttemptGated = "connection_attempt_gated"
    case disconnected
    case initialStateRejected = "initial_state_rejected"
    case reconnectScheduled = "reconnect_scheduled"
    case runtimeEventAccepted = "runtime_event_accepted"
    case runtimeEventRejected = "runtime_event_rejected"
  }

  enum TestAppToAgentCommand: Codable, Equatable, Sendable {
    case installOrRepairHelper
    case openSystemSettings
    case requestFanAuto
    case requestFanRPM
    case setApplyInBackground
    case setBoostEnabled
    case setCurve
    case setFanControlEnabled

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      let rawValue = try container.decode(String.self)
      switch rawValue {
      case "installOrRepairHelper":
        self = .installOrRepairHelper
      case "openSystemSettings":
        self = .openSystemSettings
      case "requestFanAuto":
        self = .requestFanAuto
      case "requestFanRPM":
        self = .requestFanRPM
      case "setApplyInBackground":
        self = .setApplyInBackground
      case "setBoostEnabled":
        self = .setBoostEnabled
      case "setCurve":
        self = .setCurve
      case "setFanControlEnabled":
        self = .setFanControlEnabled
      default:
        testControlModelsLog.error(
          "test_control.app_command.decode_failed raw_value=\(rawValue, privacy: .public) recovery=reject-event"
        )
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Unknown app command: \(rawValue)"
        )
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(encodedValue)
    }

    private var encodedValue: String {
      switch self {
      case .installOrRepairHelper:
        return "installOrRepairHelper"
      case .openSystemSettings:
        return "openSystemSettings"
      case .requestFanAuto:
        return "requestFanAuto"
      case .requestFanRPM:
        return "requestFanRPM"
      case .setApplyInBackground:
        return "setApplyInBackground"
      case .setBoostEnabled:
        return "setBoostEnabled"
      case .setCurve:
        return "setCurve"
      case .setFanControlEnabled:
        return "setFanControlEnabled"
      }
    }
  }

  enum TestHardwareReadOperation: Codable, Equatable, Sendable {
    case fanBatch
    case ownership

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      let rawValue = try container.decode(String.self)
      switch rawValue {
      case "fanBatch":
        self = .fanBatch
      case "ownership":
        self = .ownership
      default:
        testControlModelsLog.error(
          "test_control.hardware_operation.decode_failed raw_value=\(rawValue, privacy: .public) recovery=reject-event"
        )
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Unknown hardware read operation: \(rawValue)"
        )
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .fanBatch:
        try container.encode("fanBatch")
      case .ownership:
        try container.encode("ownership")
      }
    }
  }

#endif
