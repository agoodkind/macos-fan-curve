//
//  TestControlEvent.swift
//  FanCurve
//
//  Created by Codex <noreply@openai.com> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import Foundation

  enum TestControlEventPayload: Codable, Equatable, Sendable {
    case appToAgentCommand(command: TestAppToAgentCommand)
    case fanAutoReset(fanIndex: Int)
    case fanWrite(fanIndex: Int, rpm: Float, priority: Int)
    case hardwareRead(operation: TestHardwareReadOperation)
    case helperClassification(
      active: TestHelperIdentityResult,
      bundled: TestSystemHelperIdentity
    )
    case helperFanReset(result: TestOperationDirective)
    case helperIdentityVerified(TestSystemHelperIdentity)
    case processLifecycle(process: TestControlParticipant, phase: TestProcessLifecyclePhase)
    case revisionRejected(applied: UInt64, proposed: UInt64)
    case serviceMutation(
      service: TestServiceName,
      operation: TestServiceOperation,
      result: TestOperationDirective
    )
    case xpcFault(TestXPCFault)
    case xpcState(TestXPCStateEvent)

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
      case .helperClassification:
        return .helperClassification
      case .helperFanReset:
        return .helperFanReset
      case .helperIdentityVerified:
        return .helperIdentityVerified
      case .processLifecycle:
        return .processLifecycle
      case .revisionRejected:
        return .revisionRejected
      case .serviceMutation:
        return .serviceMutation
      case .xpcFault:
        return .xpcFault
      case .xpcState:
        return .xpcState
      }
    }
  }

  enum TestControlEventKind: String, Codable, Equatable, Sendable {
    case appToAgentCommand = "app_to_agent_command"
    case fanAutoReset = "fan_auto_reset"
    case fanWrite = "fan_write"
    case hardwareRead = "hardware_read"
    case helperClassification = "helper_classification"
    case helperFanReset = "helper_fan_reset"
    case helperIdentityVerified = "helper_identity_verified"
    case processLifecycle = "process_lifecycle"
    case revisionRejected = "revision_rejected"
    case serviceMutation = "service_mutation"
    case xpcFault = "xpc_fault"
    case xpcState = "xpc_state"
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
