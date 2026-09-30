import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite("Usage refresh ownership")
struct UsageRefreshCoordinatorTests
{
	@Test func invalidationsCoalesceAndThreeDistinctAttemptsFinishOneGroup()
	{
		var model = fixture()
		let context = context(model)
		_ = UsageReducer.reduce(
			&model,
			.usage(.refreshRequested(context))
		)
		for attempt in 1 ... 3
		{
			_ = UsageReducer.reduce(
				&model,
				.usage(.refreshRequested(context))
			)
			_ = UsageReducer.reduce(
				&model,
				.usage(.refreshRequested(context))
			)
			let result = UsageReducer.reduce(
				&model,
				.usage(.limitsReceived(
					UsageReadOperation(
						context: context,
						attempt: attempt
					),
					.succeeded(observation())
				))
			)
			let reads = result.effects.compactMap
			{
				effect -> UsageReadOperation? in
				if case .readUsage(let read) = effect
				{
					return read
				}
				return nil
			}
			#expect(reads.map(\.attempt) == (attempt < 3 ? [attempt + 1] : []))
			#expect(model.usage.needsRefresh)
		}
		#expect(model.usage.pendingRefresh == nil)
		#expect(model.usage.error?.contains("repeatedly") == true)
	}

	@Test func oldAttemptFailureAndDeadlineCannotReplaceNewSnapshot()
	{
		var model = fixture()
		let old = context(model)
		_ = UsageReducer.reduce(
			&model,
			.usage(.refreshRequested(old))
		)
		_ = UsageReducer.reduce(
			&model,
			.usage(.limitsReceived(
				UsageReadOperation(
					context: old,
					attempt: 1
				),
				.succeeded(observation())
			))
		)
		let deadline = model.usage.pendingDeadline!
		let newer = context(model)
		_ = UsageReducer.reduce(
			&model,
			.usage(.refreshRequested(newer))
		)
		#expect(model.usage.needsRefresh)
		_ = UsageReducer.reduce(
			&model,
			.usage(.limitsReceived(
				UsageReadOperation(
					context: newer,
					attempt: 1
				),
				.succeeded(observation(percent: 80))
			))
		)
		_ = UsageReducer.reduce(
			&model,
			.usage(.limitsReceived(
				UsageReadOperation(
					context: old,
					attempt: 1
				),
				.failed(OperationFailure(
					message: "Old failure",
					outcomeIsUncertain: false
				))
			))
		)
		_ = UsageReducer.reduce(
			&model,
			.usage(.freshnessDeadlineElapsed(
				deadline,
				now: deadline.deadline
			))
		)
		#expect(model.usage.snapshot?.rateLimits.primary?.usedPercent == 80)
		#expect(model.usage.error == nil)
		#expect(!model.usage.needsRefresh)
		#expect(model.usage.pendingDeadline?.read.context == newer)
	}

	@Test func invalidatedFailurePreservesPriorLimitsAndStaleness()
	{
		var model = fixture()
		let first = context(model)
		_ = UsageReducer.reduce(
			&model,
			.usage(.refreshRequested(first))
		)
		_ = UsageReducer.reduce(
			&model,
			.usage(.limitsReceived(
				UsageReadOperation(
					context: first,
					attempt: 1
				),
				.succeeded(observation())
			))
		)
		let next = context(model)
		_ = UsageReducer.reduce(
			&model,
			.usage(.refreshRequested(next))
		)
		#expect(model.usage.pendingDeadline == nil)
		#expect(model.usage.needsRefresh)
		_ = UsageReducer.reduce(
			&model,
			.usage(.limitsReceived(
				UsageReadOperation(
					context: next,
					attempt: 1
				),
				.failed(OperationFailure(
					message: "Offline",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.usage.snapshot?.rateLimits.primary?.usedPercent == 20)
		#expect(model.usage.error == "Usage unavailable: Offline")
		#expect(model.usage.needsRefresh)
		#expect(model.usage.pendingDeadline == nil)
	}

	@Test func sessionLimitsSurviveSourceCheckoutBindingButRejectAnotherTransport()
	{
		var model = fixture()
		let read = UsageReadOperation(
			context: context(model),
			attempt: 1
		)
		_ = UsageReducer.reduce(
			&model,
			.usage(.refreshRequested(read.context))
		)
		model.identity = WorkspaceIdentity(
			sessionID: model.identity.sessionID,
			canonicalCheckoutPath: "/tmp/selected"
		)
		_ = UsageReducer.reduce(
			&model,
			.usage(.limitsReceived(
				read,
				.succeeded(observation())
			))
		)
		#expect(!model.usage.needsRefresh)
		model.connection.generation += 1
		_ = UsageReducer.reduce(
			&model,
			.usage(.limitsReceived(
				read,
				.succeeded(observation(percent: 90))
			))
		)
		#expect(model.usage.snapshot?.rateLimits.primary?.usedPercent == 20)
	}

	private func fixture() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: nil
		))
		model.connection.isConnected = true
		return model
	}

	private func context(_ model: WorkspaceModel) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID()
		)
	}

	private func observation(percent: Double = 20) -> UsageObservation
	{
		let fetchedAt = Date(timeIntervalSince1970: 100)
		return UsageObservation(
			snapshot: AccountRateLimitsSnapshot(json: [
				"rateLimits": ["primary": ["usedPercent": percent]]
			])!,
			fetchedAt: fetchedAt,
			freshnessDeadline: fetchedAt.addingTimeInterval(50)
		)
	}
}
