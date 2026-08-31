//
//  XPCClientStrictResetTests.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-04.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import SMCFanProtocol
import XCTest

@testable import SMCFanXPCClient

final class XPCClientStrictResetTests: XCTestCase {
  func testStrictResetPropagatesUpstreamFanConflict() async {
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

    let error = await captureError {
      try await client.resetAllDiscoveredFansToAuto()
    }

    expect(error is SMCXPCConflictError) == true
    expect(helper.autoResetCallCount) == 1
  }

  func testCancellingStrictResetBeforeFanCountDispatchSendsNoRequest() async {
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
    let dispatchGate = LifecycleRequestDispatchGate()
    defer { Task { await dispatchGate.resumeAll() } }
    let client = XPCClient(upstreamClient: upstreamClient) {
      await dispatchGate.suspend()
    }
    let resetTask = Task { [client] in
      do {
        try await client.resetAllDiscoveredFansToAuto()
        return nil as Error?
      } catch {
        return error
      }
    }
    await dispatchGate.waitForArrival(1)

    resetTask.cancel()
    await dispatchGate.resumeNext()
    let error = await resetTask.value

    expect(error is CancellationError) == true
    expect(helper.fanCountCallCount) == 0
    expect(connectionFactory.connectionCount) == 0
  }

  func testCancellingStrictResetBeforeFanAutoDispatchSendsNoFanAutoRequest() async {
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
    let dispatchGate = LifecycleRequestDispatchGate()
    defer { Task { await dispatchGate.resumeAll() } }
    let client = XPCClient(upstreamClient: upstreamClient) {
      await dispatchGate.suspend()
    }
    let resetTask = Task { [client] in
      do {
        try await client.resetAllDiscoveredFansToAuto()
        return nil as Error?
      } catch {
        return error
      }
    }
    await dispatchGate.waitForArrival(1)
    await dispatchGate.resumeNext()
    await dispatchGate.waitForArrival(2)

    resetTask.cancel()
    await dispatchGate.resumeNext()
    let error = await resetTask.value

    expect(error is CancellationError) == true
    expect(helper.fanCountCallCount) == 1
    expect(helper.autoResetCallCount) == 0
    expect(connectionFactory.connectionCount) == 1
  }

  func testCancellingLegacyProbeBeforeDispatchSendsNoRequest() async {
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
    let dispatchGate = LifecycleRequestDispatchGate()
    defer { Task { await dispatchGate.resumeAll() } }
    let client = XPCClient(upstreamClient: upstreamClient) {
      await dispatchGate.suspend()
    }
    let probeTask = Task { [client] in
      do {
        try await client.probeLegacyHelperReachability()
        return nil as Error?
      } catch {
        return error
      }
    }
    await dispatchGate.waitForArrival(1)

    probeTask.cancel()
    await dispatchGate.resumeNext()
    let error = await probeTask.value
    let requestObserved = await helper.fanCountRequestObserved(
      timeout: XPCClientStrictResetFixtures.requestObservationTimeout
    )

    expect(error is CancellationError) == true
    expect(requestObserved) == false
    expect(helper.fanCountCallCount) == 0
    expect(connectionFactory.connectionCount) == 0
  }

  func testCancellingLegacyProbeStopsUpstreamFanCountRequest() async {
    let connectionInvalidated = expectation(description: "connection invalidated")
    let helper = ConflictingFanResetHelper(
      fanCountReply: .withhold,
      connectionInvalidated: connectionInvalidated
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
    let probeTask = Task { [client] in
      do {
        try await client.probeLegacyHelperReachability()
        return nil as Error?
      } catch {
        return error
      }
    }
    await helper.waitForFanCountRequest()

    let cancellationStarted = ContinuousClock.now
    probeTask.cancel()
    let error = await probeTask.value
    let cancellationDuration = cancellationStarted.duration(to: .now)
    await fulfillment(of: [connectionInvalidated], timeout: 0.25)

    expect(error is CancellationError) == true
    expect(cancellationDuration) < .milliseconds(250)
  }

  func testLegacyProbeTimeoutInvalidatesWithheldFanCountConnection() async {
    let connectionInvalidated = expectation(description: "connection invalidated")
    let helper = ConflictingFanResetHelper(
      fanCountReply: .withhold,
      connectionInvalidated: connectionInvalidated
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
    let client = XPCClient(
      upstreamClient: upstreamClient,
      legacyProbeTimeoutSeconds: 0.02
    )

    let error = await captureError {
      try await client.probeLegacyHelperReachability()
    }
    await fulfillment(of: [connectionInvalidated], timeout: 0.25)

    expect(error is SMCXPCTimeoutError) == true
  }

  func testCancellingStrictResetInvalidatesWithheldFanCountConnection() async {
    let connectionInvalidated = expectation(description: "connection invalidated")
    let additionalFanCountRequest = expectation(
      description: "additional fan count request"
    )
    additionalFanCountRequest.isInverted = true
    let helper = ConflictingFanResetHelper(
      fanCountReply: .withhold,
      connectionInvalidated: connectionInvalidated,
      additionalFanCountRequest: additionalFanCountRequest
    )
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
    let resetTask = Task { [client] in
      do {
        try await client.resetAllDiscoveredFansToAuto()
        return nil as Error?
      } catch {
        return error
      }
    }
    await helper.waitForFanCountRequest()

    let cancellationStarted = ContinuousClock.now
    resetTask.cancel()
    let error = await resetTask.value
    let cancellationDuration = cancellationStarted.duration(to: .now)
    await fulfillment(of: [connectionInvalidated], timeout: 0.25)
    let fanCountCallCount = helper.fanCountCallCount
    await fulfillment(
      of: [additionalFanCountRequest],
      timeout: XPCClientStrictResetFixtures.requestObservationTimeout
    )

    expect(error is CancellationError) == true
    expect(cancellationDuration) < .milliseconds(250)
    expect(helper.fanCountCallCount) == fanCountCallCount
    expect(helper.autoResetCallCount) == 0
    expect(connectionFactory.connectionCount) == 1
  }

  func testCancellingStrictResetInvalidatesWithheldSetAutoConnection() async {
    let connectionInvalidated = expectation(description: "connection invalidated")
    let additionalFanAutoRequest = expectation(
      description: "additional fan auto request"
    )
    additionalFanAutoRequest.isInverted = true
    let helper = ConflictingFanResetHelper(
      fanAutoReply: .withhold,
      connectionInvalidated: connectionInvalidated,
      additionalFanAutoRequest: additionalFanAutoRequest
    )
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
    let resetTask = Task { [client] in
      do {
        try await client.resetAllDiscoveredFansToAuto()
        return nil as Error?
      } catch {
        return error
      }
    }
    await helper.waitForFanAutoRequest()

    let cancellationStarted = ContinuousClock.now
    resetTask.cancel()
    let error = await resetTask.value
    let cancellationDuration = cancellationStarted.duration(to: .now)
    await fulfillment(of: [connectionInvalidated], timeout: 0.25)
    let autoResetCallCount = helper.autoResetCallCount
    await fulfillment(
      of: [additionalFanAutoRequest],
      timeout: XPCClientStrictResetFixtures.requestObservationTimeout
    )

    expect(error is CancellationError) == true
    expect(cancellationDuration) < .milliseconds(250)
    expect(helper.fanCountCallCount) == 1
    expect(helper.autoResetCallCount) == autoResetCallCount
    expect(connectionFactory.connectionCount) == 1
  }
}
