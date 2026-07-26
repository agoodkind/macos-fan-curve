//
//  TestControlSessionStore+Evidence.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import AppLog
  import Darwin
  import Foundation

  extension TestControlSessionStore {
    func writeAcknowledgment(_ acknowledgment: TestControlAcknowledgment) throws {
      let participant = acknowledgment.participant
      try withExclusiveLock(fileName: TestControlFile.acknowledgmentLock(for: participant)) {
        let state = try loadState()
        try validateEnvelope(
          sessionID: acknowledgment.sessionID,
          revision: acknowledgment.revision,
          against: state
        )
        if let current = try loadAcknowledgment(for: participant),
          acknowledgment.revision < current.revision
        {
          throw TestControlError.revisionNotIncreasing(
            current: current.revision.value,
            proposed: acknowledgment.revision.value
          )
        }
        let url = acknowledgmentURL(for: participant)
        try writeAtomically(acknowledgment, to: url)
        testControlStoreLog.info(
          "test_control.ack.written participant=\(participant.rawValue, privacy: .public) session=\(acknowledgment.sessionID.uuidString, privacy: .public) revision=\(acknowledgment.revision.value, privacy: .public)"
        )
      }
    }

    func loadAcknowledgment(
      for participant: TestControlParticipant
    ) throws -> TestControlAcknowledgment? {
      let url = acknowledgmentURL(for: participant)
      guard FileManager.default.fileExists(atPath: url.path) else {
        return nil
      }
      do {
        let data = try Data(contentsOf: url)
        let acknowledgment = try TestControlCodec.decode(
          TestControlAcknowledgment.self,
          from: data
        )
        guard acknowledgment.participant == participant else {
          throw TestControlError.acknowledgmentParticipantMismatch(
            expected: participant,
            actual: acknowledgment.participant
          )
        }
        let state = try loadState()
        try validateAcknowledgmentEnvelope(
          acknowledgment,
          against: state
        )
        return acknowledgment
      } catch {
        testControlStoreLog.error(
          "test_control.ack.load_failed participant=\(participant.rawValue, privacy: .public) path=\(url.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=reject-acknowledgment"
        )
        throw error
      }
    }

    func appendEvent(_ event: TestControlEvent) throws {
      try withExclusiveLock(fileName: TestControlFile.eventsLock(for: event.participant)) {
        let state = try loadState()
        try appendEventLocked(event, validatingAgainst: state)
      }
    }

    func appendRuntimeEvent(
      _ event: TestControlEvent,
      validatingAgainst appliedState: TestControlState
    ) throws {
      try withExclusiveLock(fileName: TestControlFile.eventsLock(for: event.participant)) {
        try appendEventLocked(event, validatingAgainst: appliedState)
      }
    }

    func loadEvents(for participant: TestControlParticipant) throws -> [TestControlEvent] {
      let url = eventsURL(for: participant)
      guard FileManager.default.fileExists(atPath: url.path) else {
        return []
      }
      do {
        let data = try Data(contentsOf: url)
        let lines = data.split(separator: TestControlJSONLines.delimiter)
        let state = try loadState()
        var events: [TestControlEvent] = []
        var lastRevision: TestControlRevision?
        for line in lines {
          let event = try TestControlCodec.decode(TestControlEvent.self, from: Data(line))
          guard event.participant == participant else {
            throw TestControlError.acknowledgmentParticipantMismatch(
              expected: participant,
              actual: event.participant
            )
          }
          try validateEventEnvelope(event, against: state)
          if let lastRevision, event.revision < lastRevision {
            throw TestControlError.revisionNotIncreasing(
              current: lastRevision.value,
              proposed: event.revision.value
            )
          }
          events.append(event)
          lastRevision = event.revision
        }
        return events
      } catch {
        testControlStoreLog.error(
          "test_control.events.load_failed participant=\(participant.rawValue, privacy: .public) path=\(url.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=reject-evidence"
        )
        throw error
      }
    }

    func exportEvidence(to destination: URL) throws {
      let publishedDestination = destination.standardizedFileURL
      testControlStoreLog.info(
        "test_control.evidence.export.started source=\(directory.path, privacy: .public) destination=\(publishedDestination.path, privacy: .public)"
      )
      try Self.createSessionDirectory(at: publishedDestination)
      let contents = try FileManager.default.contentsOfDirectory(
        at: publishedDestination,
        includingPropertiesForKeys: nil
      )
      guard contents.isEmpty else {
        throw TestControlError.evidenceDestinationNotEmpty(
          publishedDestination.path
        )
      }
      let snapshotDirectory =
        publishedDestination
        .deletingLastPathComponent()
        .appendingPathComponent(
          ".\(publishedDestination.lastPathComponent).snapshot-\(UUID().uuidString)",
          isDirectory: true
        )
      try Self.createSessionDirectory(at: snapshotDirectory)
      defer {
        if FileManager.default.fileExists(atPath: snapshotDirectory.path) {
          do {
            try FileManager.default.removeItem(at: snapshotDirectory)
          } catch {
            testControlStoreLog.notice(
              "test_control.evidence.snapshot_cleanup_failed path=\(snapshotDirectory.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=retain-temporary-snapshot"
            )
          }
        }
      }

      try withExclusiveLocks(
        fileNames: TestControlFile.evidenceLocksInOrder[...]
      ) {
        try copyEvidenceFiles(to: snapshotDirectory)
        try validateEvidenceSnapshot(at: snapshotDirectory)
        try publishEvidenceSnapshot(
          snapshotDirectory,
          to: publishedDestination
        )
      }
      testControlStoreLog.info(
        "test_control.evidence.export.completed destination=\(publishedDestination.path, privacy: .public)"
      )
    }

    private func copyEvidenceFiles(to snapshotDirectory: URL) throws {
      for fileName in TestControlFile.evidenceFiles {
        let source = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: source.path) else {
          continue
        }
        try FileManager.default.copyItem(
          at: source,
          to: snapshotDirectory.appendingPathComponent(fileName)
        )
      }
      testControlStoreLog.debug(
        "test_control.evidence.snapshot_copied path=\(snapshotDirectory.path, privacy: .public)"
      )
    }

    private func appendEventLocked(
      _ event: TestControlEvent,
      validatingAgainst state: TestControlState
    ) throws {
      try validateEventEnvelope(event, against: state)
      let existingEvents = try decodeEvents(
        for: event.participant,
        validatingAgainst: state
      )
      if let current = existingEvents.last, event.revision < current.revision {
        throw TestControlError.revisionNotIncreasing(
          current: current.revision.value,
          proposed: event.revision.value
        )
      }
      var data = try TestControlCodec.encode(event)
      data.append(TestControlJSONLines.delimiter)
      try append(data, to: eventsURL(for: event.participant))
      testControlStoreLog.info(
        "test_control.event.appended participant=\(event.participant.rawValue, privacy: .public) kind=\(event.kind.rawValue, privacy: .public) session=\(event.sessionID.uuidString, privacy: .public) revision=\(event.revision.value, privacy: .public)"
      )
    }

    private func decodeEvents(
      for participant: TestControlParticipant,
      validatingAgainst state: TestControlState
    ) throws -> [TestControlEvent] {
      let url = eventsURL(for: participant)
      guard FileManager.default.fileExists(atPath: url.path) else {
        return []
      }
      let data = try Data(contentsOf: url)
      let lines = data.split(separator: TestControlJSONLines.delimiter)
      var events: [TestControlEvent] = []
      var lastRevision: TestControlRevision?
      for line in lines {
        let event = try TestControlCodec.decode(TestControlEvent.self, from: Data(line))
        guard event.participant == participant else {
          throw TestControlError.acknowledgmentParticipantMismatch(
            expected: participant,
            actual: event.participant
          )
        }
        try validateEventEnvelope(event, against: state)
        if let lastRevision, event.revision < lastRevision {
          throw TestControlError.revisionNotIncreasing(
            current: lastRevision.value,
            proposed: event.revision.value
          )
        }
        events.append(event)
        lastRevision = event.revision
      }
      return events
    }

    private func validateAcknowledgmentEnvelope(
      _ acknowledgment: TestControlAcknowledgment,
      against state: TestControlState
    ) throws {
      do {
        try validateEnvelope(
          sessionID: acknowledgment.sessionID,
          revision: acknowledgment.revision,
          against: state
        )
      } catch let error as TestControlError {
        guard case .futureRevision = error else {
          throw error
        }
        guard
          try hasRevisionRejectionEvidence(
            participant: acknowledgment.participant,
            sessionID: acknowledgment.sessionID,
            appliedRevision: acknowledgment.revision,
            proposedRevision: state.revision
          )
        else {
          throw error
        }
        testControlStoreLog.notice(
          "test_control.ack.regressed_control_validated participant=\(acknowledgment.participant.rawValue, privacy: .public) applied=\(acknowledgment.revision.value, privacy: .public) proposed=\(state.revision.value, privacy: .public) recovery=retain-rejection-evidence"
        )
      }
    }

    private func validateEventEnvelope(
      _ event: TestControlEvent,
      against state: TestControlState
    ) throws {
      if case let .revisionRejected(applied, proposed) = event.payload,
        event.revision.value == applied,
        proposed < applied,
        state.revision.value == proposed
      {
        try validateEnvelope(
          sessionID: event.sessionID,
          revision: state.revision,
          against: state
        )
        return
      }
      try validateEnvelope(
        sessionID: event.sessionID,
        revision: event.revision,
        against: state
      )
    }

    private func hasRevisionRejectionEvidence(
      participant: TestControlParticipant,
      sessionID: UUID,
      appliedRevision: TestControlRevision,
      proposedRevision: TestControlRevision
    ) throws -> Bool {
      let url = eventsURL(for: participant)
      guard FileManager.default.fileExists(atPath: url.path) else {
        return false
      }
      let data = try Data(contentsOf: url)
      let lines = data.split(separator: TestControlJSONLines.delimiter)
      for line in lines {
        let event = try TestControlCodec.decode(
          TestControlEvent.self,
          from: Data(line)
        )
        guard event.participant == participant else {
          continue
        }
        guard event.sessionID == sessionID else {
          continue
        }
        guard event.revision == appliedRevision else {
          continue
        }
        guard
          event.payload
            == .revisionRejected(
              applied: appliedRevision.value,
              proposed: proposedRevision.value
            )
        else {
          continue
        }
        return true
      }
      return false
    }

    private func validateEvidenceSnapshot(at snapshotDirectory: URL) throws {
      let snapshotStore = try TestControlSessionStore.open(
        at: snapshotDirectory
      )
      for participant in TestControlParticipant.allCases {
        _ = try snapshotStore.loadAcknowledgment(for: participant)
        _ = try snapshotStore.loadEvents(for: participant)
      }
      testControlStoreLog.debug(
        "test_control.evidence.snapshot_validated path=\(snapshotDirectory.path, privacy: .public)"
      )
    }

    private func publishEvidenceSnapshot(
      _ snapshotDirectory: URL,
      to destination: URL
    ) throws {
      guard Darwin.rename(snapshotDirectory.path, destination.path) == 0 else {
        let error = POSIXError(.init(rawValue: errno) ?? .EIO)
        testControlStoreLog.error(
          "test_control.evidence.publish_failed snapshot=\(snapshotDirectory.path, privacy: .public) destination=\(destination.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=preserve-empty-destination"
        )
        throw error
      }
      testControlStoreLog.info(
        "test_control.evidence.published destination=\(destination.path, privacy: .public)"
      )
    }
  }
#endif
