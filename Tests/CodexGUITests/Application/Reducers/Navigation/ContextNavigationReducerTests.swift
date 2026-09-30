import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ContextNavigationReducerTests
{
	private func fixture() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/context"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.execution.state = .ready
		model.conversations.selectedConversation = .thread("thread")
		model.conversations.content[.thread("thread")] = ConversationContentModel(
			hasLoadedHistory: true,
			nextTurnsCursor: "0"
		)
		return model
	}

	private func context(
		_ model: WorkspaceModel,
		threadID: String? = nil
	) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: threadID
		)
	}

	private func edit(_ text: String) -> ProjectContext
	{
		var value = ProjectContext()
		value.savedPrompts = [SavedPrompt(
			title: text,
			instructions: text
		)]
		return value
	}

	@discardableResult
	private func reduce(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		for reducer in [
			ConnectionReducer.reducer,
			ConversationReducer.reducer,
			ContextNavigationReducer.reducer
		]
		{
			let next = reducer.reduce(
				&model,
				action
			)
			result.effects.append(contentsOf: next.effects)
			result.domainEvents.append(contentsOf: next.domainEvents)
		}
		var index = 0
		while index < result.domainEvents.count
		{
			let change = result.domainEvents[index]
			index += 1
			for next in [ConversationReducer.reduceDomainEvent(
				&model,
				change
			),
			ContextNavigationReducer.reduceDomainEvent(
				&model,
				change
			)]
			{
				result.effects.append(contentsOf: next.effects)
				result.domainEvents.append(contentsOf: next.domainEvents)
			}
		}
		return result
	}

	@Test func lateLoadCannotReplaceAnEditOrAnotherProjectsPendingLoad()
	{
		var model = fixture()
		let old = ContextLoadOperation(
			context: context(model),
			revision: 0
		)
		reduce(
			&model,
			.contextNavigation(.contextLoadRequested(old))
		)
		let saved = ContextSaveOperation(
			context: context(model),
			revision: 1,
			value: edit("Edit")
		)
		reduce(
			&model,
			.contextNavigation(.contextEdited(saved))
		)
		for result in [OperationResult.succeeded(edit("Old disk")),
						.failed(OperationFailure(
						message: "Old failure",
						outcomeIsUncertain: false
						))]
		{
			reduce(
				&model,
				.contextNavigation(.contextReceived(
					old,
					result
				))
			)
			#expect(model.contextNavigation.projectContext == saved.value)
			#expect(model.contextNavigation.pendingContextSave?.context == saved.context)
			#expect(model.contextNavigation.contextError == nil)
		}
		model.identity = WorkspaceIdentity(
			sessionID: model.identity.sessionID,
			canonicalCheckoutPath: "/tmp/other-context"
		)
		reduce(
			&model,
			.connection(.projectOpened(
				model.identity,
				selectedThreadID: nil
			))
		)
		let newer = ContextLoadOperation(
			context: context(model),
			revision: 0
		)
		reduce(
			&model,
			.contextNavigation(.contextLoadRequested(newer))
		)
		for result in [OperationResult.succeeded(edit("Wrong project")),
						.failed(OperationFailure(
						message: "Wrong failure",
						outcomeIsUncertain: false
						))]
		{
			reduce(
				&model,
				.contextNavigation(.contextReceived(
					old,
					result
				))
			)
			#expect(model.contextNavigation.pendingContextLoad?.context == newer.context)
			#expect(model.contextNavigation.contextError == nil)
			#expect(model.contextNavigation.projectContext == ProjectContext())
		}
		let newProject = edit("New project")
		reduce(
			&model,
			.contextNavigation(.contextReceived(
				newer,
				.succeeded(newProject)
			))
		)
		#expect(model.contextNavigation.projectContext == newProject)
	}

	@Test func staleSaveFailureCannotRetireOrHideTheNewerEdit()
	{
		var model = fixture()
		let first = ContextSaveOperation(
			context: context(model),
			revision: 1,
			value: edit("First")
		)
		let second = ContextSaveOperation(
			context: context(model),
			revision: 2,
			value: edit("Second")
		)
		reduce(
			&model,
			.contextNavigation(.contextEdited(first))
		)
		reduce(
			&model,
			.contextNavigation(.contextEdited(second))
		)
		reduce(
			&model,
			.contextNavigation(.contextPersistenceFinished(
				first,
				.failed(OperationFailure(
					message: "Stale save",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.contextNavigation.pendingContextSave?.context == second.context)
		#expect(model.contextNavigation.contextError == nil)
		#expect(model.contextNavigation.projectContext == second.value)
		reduce(
			&model,
			.contextNavigation(.contextPersistenceFinished(
				second,
				.failed(OperationFailure(
					message: "Current save",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.contextNavigation.projectContext == second.value)
		#expect(model.contextNavigation.contextError == "Current save")
		#expect(model.contextNavigation.pendingContextSave == nil)
	}

	@Test func acceptedReconnectRenewsOnlyCurrentRevisionContextWork()
	{
		for saving in [false, true]
		{
			var model = fixture()
			let request = context(model)
			let load = ContextLoadOperation(
				context: request,
				revision: 0
			)
			let save = ContextSaveOperation(
				context: request,
				revision: 1,
				value: edit("Visible")
			)
			if saving
			{
				reduce(
					&model,
					.contextNavigation(.contextEdited(save))
				)
			}
			else
			{
				reduce(
					&model,
					.contextNavigation(.contextLoadRequested(load))
				)
			}
			reduce(
				&model,
				.connection(.connectRequested(context(model)))
			)
			let failure = OperationFailure(
				message: "Current disk failure",
				outcomeIsUncertain: false
			)
			if saving
			{
				let renewed = model.contextNavigation.pendingContextSave!
				#expect(renewed.context.requestID == request.requestID)
				#expect(renewed.context.generation == 2)
				#expect(renewed.value == save.value)
				reduce(
					&model,
					.contextNavigation(.contextPersistenceFinished(
						save,
						.failed(failure)
					))
				)
				#expect(model.contextNavigation.pendingContextSave?.context == renewed.context)
				reduce(
					&model,
					.contextNavigation(.contextPersistenceFinished(
						renewed,
						.failed(failure)
					))
				)
				#expect(model.contextNavigation.projectContext == save.value)
			}
			else
			{
				let renewed = model.contextNavigation.pendingContextLoad!
				#expect(renewed.context.requestID == request.requestID)
				#expect(renewed.context.generation == 2)
				reduce(
					&model,
					.contextNavigation(.contextReceived(
						load,
						.failed(failure)
					))
				)
				#expect(model.contextNavigation.pendingContextLoad?.context == renewed.context)
				reduce(
					&model,
					.contextNavigation(.contextReceived(
						renewed,
						.failed(failure)
					))
				)
			}
			#expect(model.contextNavigation.contextError == failure.message)
		}
	}

	@Test func obsoleteSkillScopeAndAttemptCannotReplaceTheCurrentCatalogRequest()
	{
		var model = fixture()
		let old = SkillsRefreshOperation(
			context: context(model),
			attempt: 0
		)
		reduce(
			&model,
			.contextNavigation(.skillsRefreshRequested(old))
		)
		model.identity = WorkspaceIdentity(
			sessionID: model.identity.sessionID,
			canonicalCheckoutPath: "/tmp/other-context"
		)
		reduce(
			&model,
			.connection(.projectOpened(
				model.identity,
				selectedThreadID: nil
			))
		)
		let current = SkillsRefreshOperation(
			context: context(model),
			attempt: 0
		)
		reduce(
			&model,
			.contextNavigation(.skillsRefreshRequested(current))
		)
		let catalog = SkillCatalog(
			skills: [],
			errors: []
		)
		let wrongAttempt = SkillsRefreshOperation(
			context: current.context,
			attempt: 1
		)
		var previousGeneration = current.context
		previousGeneration = OperationContext(
			workspace: previousGeneration.workspace,
			generation: previousGeneration.generation - 1,
			requestID: previousGeneration.requestID
		)
		for operation in [old,
							wrongAttempt,
							SkillsRefreshOperation(
							context: previousGeneration,
							attempt: 0
							)]
		{
			for result in [OperationResult.succeeded(catalog),
							.failed(OperationFailure(
							message: "Obsolete skill failure",
							outcomeIsUncertain: false
							))]
			{
				reduce(
					&model,
					.contextNavigation(.skillsReceived(
						operation,
						result
					))
				)
				#expect(model.contextNavigation.pendingSkillRefresh?.context == current.context)
				#expect(model.contextNavigation.pendingSkillRefresh?.attempt == 0)
				#expect(model.contextNavigation.skillCatalog == nil)
				#expect(model.contextNavigation.skillError == nil)
			}
		}
		let invalid = SkillsRefreshOperation(
			context: context(model),
			attempt: 2
		)
		#expect(reduce(
			&model,
			.contextNavigation(.skillsRefreshRequested(invalid))
		).effects
			.isEmpty)
		#expect(!model.contextNavigation.skillRefreshPending)
	}

	@Test func replacedPageFailuresCannotClearCurrentSearchOrJump()
	{
		var model = fixture()
		reduce(
			&model,
			.contextNavigation(.searchRequested(
				context(model),
				query: "needle"
			))
		)
		reduce(
			&model,
			.contextNavigation(.moreSearchHistoryRequested(context(model)))
		)
		reduce(
			&model,
			.contextNavigation(.jumpRequested(ConversationJumpOperation(
				context: context(
					model,
					threadID: "thread"
				),
				turnID: "missing",
				itemID: "answer"
			)))
		)
		let old = model.conversations.historyLoads["thread"]!
		model.execution.commandEventRevisions["thread"] = 1
		let newer = HistoryLoadOperation(
			context: context(
				model,
				threadID: "thread"
			),
			pageScope: old.pageScope,
			commandRevision: 1
		)
		reduce(
			&model,
			.conversations(.earlierTurnsRequested(newer))
		)
		#expect(model.contextNavigation.pendingSearch?.read?.context == newer.context)
		#expect(model.contextNavigation.pendingJump?.pendingRead?.context == newer.context)
		reduce(
			&model,
			.conversations(.earlierTurnsReceived(
				old,
				.failed(OperationFailure(
					message: "Old page",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.contextNavigation.pendingSearch?.read?.context == newer.context)
		#expect(model.contextNavigation.pendingJump?.pendingRead?.context == newer.context)
		#expect(model.contextNavigation.searchError == nil)
		#expect(model.contextNavigation.jumpError == nil)
		reduce(
			&model,
			.conversations(.earlierTurnsReceived(
				newer,
				.failed(OperationFailure(
					message: "Current page",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.contextNavigation.pendingSearch == nil)
		#expect(model.contextNavigation.pendingJump?.pendingRead == nil)
		#expect(model.contextNavigation.searchError == "Could not load more messages: Current page")
		#expect(model.contextNavigation
			.jumpError == "Could not load the referenced message: Current page")
	}

	@Test func jumpStopsAfterTwentyPreciselyChainedPages()
	{
		var model = fixture()
		reduce(
			&model,
			.contextNavigation(.jumpRequested(ConversationJumpOperation(
				context: context(
					model,
					threadID: "thread"
				),
				turnID: "missing",
				itemID: "answer"
			)))
		)
		for number in 0 ..< 20
		{
			let operation = model.conversations.historyLoads["thread"]!
			#expect(operation.pageScope.cursor == String(number))
			reduce(
				&model,
				.conversations(.earlierTurnsReceived(
					operation,
					.succeeded(HistoryPage(
						turns: [],
						nextCursor: String(number + 1)
					))
				))
			)
		}
		#expect(model.contextNavigation.pendingJump?.pagesLoaded == 20)
		#expect(model.contextNavigation.pendingJump?.pendingRead == nil)
		#expect(model.conversations.historyLoads.isEmpty)
		#expect(model.contextNavigation.jumpError ==
			"The referenced message is in older history. Load more messages and try again.")
	}

	@Test func inspectedPromptUpdatesOnlyTheCurrentDraftWithoutSubmitting()
	{
		var model = fixture()
		model.contextNavigation.projectContext = edit("Find regressions")
		let promptID = model.contextNavigation.projectContext.savedPrompts[0].id
		model.composer.drafts[.thread("thread")] = ComposerDraft(
			text: "Implement it",
			revision: 3
		)
		model.composer.drafts[.thread("other")] = ComposerDraft(text: "Independent")
		let result = reduce(
			&model,
			.contextNavigation(.savedPromptInserted(
				context(
					model,
					threadID: "thread"
				),
				promptID: promptID
			))
		)
		#expect(model.composer.drafts[.thread("thread")]?
			.text == "Implement it\n\nFind regressions")
		#expect(model.composer.drafts[.thread("thread")]?.revision == 4)
		#expect(model.composer.drafts[.thread("other")]?.text == "Independent")
		#expect(model.execution.state == .ready)
		#expect(model.execution.owner == nil)
		#expect(model.composer.pendingSubmissions.isEmpty)
		#expect(result.effects.count == 1)
		if case .persistDraft? = result.effects.first
		{
		}
		else
		{
			Issue.record("Expected draft persistence")
		}
	}
}
