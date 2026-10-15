import Foundation
import Testing
@testable import CodexGUI

@MainActor
@Suite
struct WorkspaceInteractionResponseRuntimeTests
{
	@Test(arguments: [false, true])
	func cancelledResponseNeverStartsTheService(shutsDown: Bool) async throws
	{
		let service = MockCodexService()
		let runner = makeResponseRunner(service: service)
		defer
		{
			runner.shutdown()
		}
		let context = makeResponseContext()
		runner.accept(
			[.respond(InteractionResponseOperation(
				context: context,
				interactionID: "approval",
				response: .approval(.accept)
			))],
			workspace: context.workspace
		)
		let handle = try #require(runner.operation(for: context))
		let pending = try #require(runner.tasks.values.first)

		// Cancellation happens before the queued MainActor task can enter the service.
		if shutsDown
		{
			runner.shutdown()
		}
		else
		{
			runner.cancel(context)
		}
		#expect(await handle.wait() == .cancelled)
		await pending.task.value
		#expect(service.respondedRequestIDs.isEmpty)
		#expect(runner.runningOperationCount == 0)
	}

	@Test(arguments: ["generation", "checkout", "detached"])
	func queuedResponseRejectsRetiredTransport(scope: String) async throws
	{
		let service = MockCodexService()
		let runner = makeResponseRunner(service: service)
		defer
		{
			runner.shutdown()
		}
		let context = makeResponseContext()
		runner.accept(
			[
				.subscribe(context),
				.respond(InteractionResponseOperation(
					context: context,
					interactionID: "reused-approval",
					response: .approval(.accept)
				)),
			],
			workspace: context.workspace
		)
		let handle = try #require(runner.operation(for: context))

		if scope == "detached"
		{
			runner.accept(
				[.detachSubscription],
				workspace: context.workspace
			)
		}
		else
		{
			let replacementWorkspace = scope == "checkout"
				? WorkspaceIdentity(
					sessionID: context.workspace.sessionID,
					canonicalCheckoutPath: "/tmp/replacement-response"
				) : context.workspace
			let replacementGeneration = scope == "generation"
				? context.generation + 1 : context.generation
			runner.accept(
				[.subscribe(OperationContext(
					workspace: replacementWorkspace,
					generation: replacementGeneration,
					requestID: UUID()
				))],
				workspace: replacementWorkspace
			)
		}

		if case .failed(let failure) = await handle.wait()
		{
			#expect(failure.message == AppServerError.disconnected.localizedDescription)
			#expect(!failure.outcomeIsUncertain)
		}
		else
		{
			Issue.record("Expected the retired response to fail before entering the service.")
		}
		#expect(service.respondedRequestIDs.isEmpty)
		#expect(runner.runningOperationCount == 0)
	}

	@Test
	func responseFallbackChecksCancellationBeforeCallingSynchronousService() async
	{
		let service = MockCodexService()
		let response = Task
		{
			try await service.respondAndWait(
				to: "approval",
				with: .approval(.accept)
			)
		}
		response.cancel()

		do
		{
			try await response.value
			Issue.record("Expected cancellation before the synchronous response fallback.")
		}
		catch
		{
			#expect(error is CancellationError)
		}
		#expect(service.respondedRequestIDs.isEmpty)
	}

	@Test(arguments: [false, true])
	func responseFailurePreservesPhysicalWriteUncertainty(mayHaveBeenSent: Bool) async throws
	{
		let service = MockCodexService()
		service.responseError = ProtocolWriteFailure(
			cause: AppServerError.requestTimedOut("request/respond"),
			mayHaveBeenSent: mayHaveBeenSent,
			requiresDisconnect: false
		)
		let runner = makeResponseRunner(service: service)
		defer
		{
			runner.shutdown()
		}
		let context = makeResponseContext()
		runner.accept(
			[.respond(InteractionResponseOperation(
				context: context,
				interactionID: "approval",
				response: .approval(.accept)
			))],
			workspace: context.workspace
		)
		let handle = try #require(runner.operation(for: context))

		if case .failed(let failure) = await handle.wait()
		{
			#expect(failure.outcomeIsUncertain == mayHaveBeenSent)
			#expect(failure.message == service.responseError?.localizedDescription)
		}
		else
		{
			Issue.record("Expected physical response failure to settle the operation.")
		}
		#expect(service.respondedRequestIDs == ["approval"])
		#expect(runner.runningOperationCount == 0)
	}

	@Test(arguments: [false, true, nil] as [Bool?])
	func cancelledStartedResponseUsesDeliveryEvidence(evidence: Bool?) async throws
	{
		let service = RuntimeService()
		service.responseDeliveryEvidence = evidence
		var failures: [OperationFailure] = []
		let runner = makeResponseRunner(
			service: service,
			onAction:
			{
				if case .execution(.interactionResponseFinished(
					_,
					.failed(let failure)
				)) = $0
				{
					failures.append(failure)
				}
			}
		)
		defer
		{
			service.completeResponse()
			runner.shutdown()
		}
		let context = makeResponseContext()
		runner.accept(
			[
				.subscribe(context),
				.respond(InteractionResponseOperation(
					context: context,
					interactionID: "approval",
					response: .approval(.accept)
				)),
			],
			workspace: context.workspace
		)
		let handle = try #require(runner.operation(for: context))
		await service.responseStarted.wait()
		let pending = try #require(runner.tasks.values.first)

		runner.cancel(context)
		#expect(await handle.wait() == .cancelled)
		#expect(runner.runningOperationCount == 0)
		#expect(service.responseRequests == ["approval"])
		#expect(service.responseEvidenceQueries == ["approval"])
		let failure = try #require(failures.first)
		#expect(failure.outcomeIsUncertain == (evidence ?? true))

		// The service ignores cancellation; local completion cannot wait for it to return.
		service.completeResponse()
		await pending.task.value
		#expect(failures.count == 1)
	}

	@Test
	func cancellingRetiredResponseDoesNotReadReplacementTransportEvidence() async throws
	{
		let service = RuntimeService()
		service.responseDeliveryEvidence = false
		let runner = makeResponseRunner(service: service)
		defer
		{
			service.completeResponse()
			runner.shutdown()
		}
		let context = makeResponseContext()
		runner.accept(
			[
				.subscribe(context),
				.respond(InteractionResponseOperation(
					context: context,
					interactionID: "reused-approval",
					response: .approval(.accept)
				)),
			],
			workspace: context.workspace
		)
		let handle = try #require(runner.operation(for: context))
		await service.responseStarted.wait()
		let pending = try #require(runner.tasks.values.first)
		runner.accept(
			[.subscribe(OperationContext(
				workspace: context.workspace,
				generation: context.generation + 1,
				requestID: UUID()
			))],
			workspace: context.workspace
		)

		runner.cancel(context)
		#expect(await handle.wait() == .cancelled)
		#expect(service.responseEvidenceQueries.isEmpty)
		service.completeResponse()
		await pending.task.value
		#expect(runner.runningOperationCount == 0)
	}

	private func makeResponseContext() -> OperationContext
	{
		OperationContext(
			workspace: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: "/tmp/runtime-response"
			),
			generation: 1,
			requestID: UUID(),
			threadID: "thread",
			turnID: "turn"
		)
	}

	private func makeResponseRunner(
		service: any CodexService,
		onAction: ((WorkspaceAction) -> Void)? = nil
	) -> WorkspaceEffectRunner
	{
		WorkspaceEffectRunner(
			service: service,
			persistence: WorkspacePersistenceScheduler
			{
				_ in
			},
			mapEvent:
			{
				_, _ in []
			},
			deliver:
			{
				action, complete in
				onAction?(action)
				complete()
			}
		)
	}
}
