//
//  AgentSnapshotStore.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026
//

import AppLog
import Foundation

private let agentSnapshotStoreLog = AppLog.make(category: "AgentSnapshotStore")

enum AgentSnapshotStore {
    private struct SnapshotHeader: Decodable {
        let schemaVersion: Int
    }

    static func load(defaults: UserDefaults) -> AgentSnapshot? {
        guard let data = defaults.data(forKey: SharedConfigKeys.agentSnapshot) else { return nil }
        let snapshot: AgentSnapshot
        do {
            snapshot = try JSONDecoder().decode(AgentSnapshot.self, from: data)
        } catch {
            agentSnapshotStoreLog.notice(
                "snapshot.decode_failed error=\(error.localizedDescription, privacy: .public) recovery=stale-ui"
            )
            return nil
        }
        guard snapshot.schemaVersion == AgentSnapshot.currentSchemaVersion else {
            agentSnapshotStoreLog.notice(
                "snapshot.schema_mismatch got=\(snapshot.schemaVersion, privacy: .public) want=\(AgentSnapshot.currentSchemaVersion, privacy: .public) recovery=stale-ui"
            )
            return nil
        }
        return snapshot
    }

    static func storedSchemaVersion(defaults: UserDefaults) -> Int? {
        guard let data = defaults.data(forKey: SharedConfigKeys.agentSnapshot) else { return nil }
        do {
            return try JSONDecoder().decode(SnapshotHeader.self, from: data).schemaVersion
        } catch {
            agentSnapshotStoreLog.notice(
                "snapshot.header_decode_failed error=\(error.localizedDescription, privacy: .public) recovery=treat-as-incompatible"
            )
            return nil
        }
    }

    static func save(_ snapshot: AgentSnapshot, defaults: UserDefaults) {
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            agentSnapshotStoreLog.error(
                "snapshot.encode_failed error=\(error.localizedDescription, privacy: .public) recovery=skip-write"
            )
            return
        }
        defaults.set(data, forKey: SharedConfigKeys.agentSnapshot)
    }

    static func clear(defaults: UserDefaults) {
        defaults.removeObject(forKey: SharedConfigKeys.agentSnapshot)
    }
}
