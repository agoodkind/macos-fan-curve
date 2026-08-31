//
//  XPCClientRequestScopeTests.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

@testable import SMCFanXPCClient

final class XPCClientRequestScopeTests: XCTestCase {
  func testCancellingLegacyProbePreservesSharedConnection() async throws {
    try await assertCancellingLifecycleOperationPreservesSharedConnection { client in
      try await client.probeLegacyHelperReachability()
    }
  }

  func testCancellingStrictResetPreservesSharedConnection() async throws {
    try await assertCancellingLifecycleOperationPreservesSharedConnection { client in
      try await client.resetAllDiscoveredFansToAuto()
    }
  }

  private func assertCancellingLifecycleOperationPreservesSharedConnection(
    operation: @escaping @Sendable (XPCClient) async throws -> Void
  ) async throws {
    let helper = ConflictingFanResetHelper()
    let listener = NSXPCListener.anonymous()
    let listenerDelegate = ConflictingFanResetListenerDelegate(helper: helper)
    listener.delegate = listenerDelegate
    listener.resume()
    defer { listener.invalidate() }
    let connectionFactory = CountingXPCConnectionFactory(endpoint: listener.endpoint)
    let upstreamClient = SMCFanXPCClient {
      connectionFactory.makeConnection()
    }
    defer { upstreamClient.shutdown() }
    let client = XPCClient(upstreamClient: upstreamClient)
    let initialFanCount = try await upstreamClient.getFanCount()
    expect(initialFanCount) == 1
    await helper.waitForFanCountRequest()
    helper.setFanCountReply(.withhold)
    let operationTask = Task { [client] in
      do {
        try await operation(client)
        return nil as Error?
      } catch {
        return error
      }
    }
    await helper.waitForFanCountRequest()

    expect(connectionFactory.connectionCount) == 2

    operationTask.cancel()
    let error = await operationTask.value
    helper.setFanCountReply(.succeed)

    let fanCount = try await upstreamClient.getFanCount()

    expect(error is CancellationError) == true
    expect(fanCount) == 1
    expect(connectionFactory.connectionCount) == 2
  }
}
