//
//  XPCClientLegacyProbeClassificationTests.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import SMCFanProtocol
import XCTest

@testable import SMCFanXPCClient

// MARK: - XPCClientLegacyProbeClassificationTests

final class XPCClientLegacyProbeClassificationTests: XCTestCase {
  func testLegacyProbeAcceptsHelperApplicationFailureAsReachable() async throws {
    let helper = ConflictingFanResetHelper(
      fanCountReply: .fail("Failed to open AppleSMC")
    )
    let listener = NSXPCListener.anonymous()
    let listenerDelegate = ConflictingFanResetListenerDelegate(helper: helper)
    listener.delegate = listenerDelegate
    listener.resume()
    defer { listener.invalidate() }
    let upstreamClient = SMCFanXPCClient {
      NSXPCConnection(listenerEndpoint: listener.endpoint)
    }
    defer { upstreamClient.shutdown() }
    let client = XPCClient(upstreamClient: upstreamClient)

    try await client.probeLegacyHelperReachability()

    expect(helper.fanCountCallCount) == 1
  }

  func testLegacyProbePropagatesTransportFailure() async {
    let helper = ConflictingFanResetHelper()
    let listener = NSXPCListener.anonymous()
    defer { listener.invalidate() }
    let upstreamClient = SMCFanXPCClient(
      remoteProxyFactory: { _, errorHandler in
        errorHandler(
          NSError(
            domain: NSCocoaErrorDomain,
            code: NSXPCConnectionInterrupted,
            userInfo: [NSLocalizedDescriptionKey: "Connection interrupted"]
          )
        )
        return helper
      },
      connectionFactory: { NSXPCConnection(listenerEndpoint: listener.endpoint) }
    )
    defer { upstreamClient.shutdown() }
    let client = XPCClient(upstreamClient: upstreamClient)

    let error = await captureError {
      try await client.probeLegacyHelperReachability()
    }

    expect(error is SMCXPCTransportError) == true
    expect(helper.fanCountCallCount) == 0
  }
}
