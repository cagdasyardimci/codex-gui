import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct AccountSignOutCompositionTests
{
	@Test func acceptedSignOutRetiresSensitiveReadsAndRejectsTheirLateResults() throws
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/account-sign-out"
		))
		model.connection.isConnected = true
		let context = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID()
		)
		let now = Date(timeIntervalSince1970: 1000)
		let snapshot = try #require(AccountRateLimitsSnapshot(json: ["rateLimits": [:]]))
		let read = UsageReadOperation(
			context: context,
			attempt: 1
		)
		let deadline = UsageDeadlineOperation(
			read: read,
			fetchedAt: now,
			deadline: now.addingTimeInterval(60)
		)
		model.usage.snapshot = snapshot
		model.usage.pendingRefresh = UsageRefreshOperation(
			context: context,
			readsStarted: 1
		)
		model.usage.pendingDeadline = deadline
		let pairing = RemoteControlPairing(
			pairingCode: "synthetic-secret",
			manualPairingCode: "ABCD-EFGH",
			environmentId: "environment",
			expiresAt: 2000
		)
		let remoteContext = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID()
		)
		let operation = RemoteAccessOperation(
			context: remoteContext,
			command: .pair,
			statusRevision: 0
		)
		model.remoteAccess.desiredEnabled = true
		model.remoteAccess.pairing = pairing
		model.remoteAccess.pending = operation

		let result = WorkspaceDomainComposition.reduceDomainEvent(
			&model,
			.accountSignedOut
		)
		#expect(model.usage.snapshot == nil)
		#expect(model.usage.pendingRefresh == nil)
		#expect(model.usage.pendingDeadline == nil)
		#expect(model.remoteAccess.pairing == nil)
		#expect(model.remoteAccess.pending == nil)
		#expect(model.remoteAccess.desiredEnabled)
		#expect(result.effects.count == 3)
		#expect(result.effects.contains
		{
			if case .cancel(let value) = $0
			{
				return value == remoteContext
			}
			return false
		})
		#expect(result.effects.contains
		{
			if case .cancelUsageRefresh(let value) = $0
			{
				return value == context
			}
			return false
		})
		#expect(result.effects.contains
		{
			if case .cancelUsageDeadline(let value) = $0
			{
				return value == deadline
			}
			return false
		})

		_ = UsageReducer.reduce(
			&model,
			.usage(.limitsReceived(
				read,
				.succeeded(UsageObservation(
					snapshot: snapshot,
					fetchedAt: now,
					freshnessDeadline: deadline.deadline
				))
			))
		)
		_ = RemoteAccessReducer.reduce(
			&model,
			.remoteAccess(.finished(
				operation,
				.succeeded(RemoteAccessUpdate(pairing: pairing)),
				now
			))
		)
		#expect(model.usage.snapshot == nil)
		#expect(model.remoteAccess.pairing == nil)
	}
}
