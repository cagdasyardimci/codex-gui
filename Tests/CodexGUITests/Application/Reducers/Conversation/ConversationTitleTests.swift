import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ConversationTitleTests
{
	@Test func newSubmissionGetsTitleBeforeAnyAgentResponse()
	{
		var model = workspace()
		model.conversations.selectedConversation = .newChat
		let submission = ComposerSubmission(
			context: context(model),
			conversation: .newChat,
			draft: ComposerDraft(text: "wait for 30 seconds and create a placeholder"),
			inputs: [.text("wait for 30 seconds and create a placeholder")],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		let prepared = PreparedSubmission(
			submission: submission,
			thread: ThreadDetail(
				summary: ThreadSummary(json: ["id": "thread", "cwd": "/tmp/titles"])!,
				turns: [],
				nextTurnsCursor: nil
			)
		)
		_ = ConversationReducer.reduceDomainEvent(
			&model,
			.submissionPrepared(prepared)
		)
		#expect(model.conversations.threads.first?.preview == submission.draft.text)
		#expect(model.conversations.threads.first?.name == nil)
	}

	@Test func notificationUpdatesUnselectedChatAndSurvivesOlderListResponse()
	{
		var model = workspace()
		model.conversations.threads = [summary()]
		let operation = ConversationListOperation(
			context: context(model),
			archived: false,
			boundThreadID: nil
		)
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.threadListRequested(operation))
		)
		observeTitle(
			"Create placeholder",
			model: &model
		)
		#expect(model.conversations.threads.first?.name == "Create placeholder")
		#expect(model.conversations.selectedConversation == .newChat)
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.threadListReceived(
				operation,
				.succeeded([summary()])
			))
		)
		#expect(model.conversations.threads.first?.name == "Create placeholder")
		observeTitle(
			nil,
			model: &model
		)
		#expect(model.conversations.threads.first?.name == nil)
	}

	@Test func aFreshListCanReplacePreviouslyObservedTitleMetadata()
	{
		var model = workspace()
		model.conversations.threads = [summary()]
		observeTitle(
			"Generated title",
			model: &model
		)
		let operation = ConversationListOperation(
			context: context(model),
			archived: false,
			boundThreadID: nil
		)
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.threadListRequested(operation))
		)
		var renamed = summary()
		renamed.name = "My chosen name"
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.threadListReceived(
				operation,
				.succeeded([renamed])
			))
		)
		#expect(model.conversations.threads.first?.name == "My chosen name")
	}

	@Test func notificationsRefreshAndPersistPinnedMetadataBeforeAListRefresh() throws
	{
		var model = workspace()
		model.conversations.threads = [summary()]
		model.preferences.pinnedTasks = [summary()]
		for name in ["Generated title", "External rename"]
		{
			let result = observeTitle(
				name,
				model: &model
			)
			let live = try #require(model.conversations.threads.first)
			let pin = try #require(model.preferences.pinnedTasks.first)
			#expect(live.displayTitle == name)
			#expect(pin.displayTitle == live.displayTitle)
			#expect(model.conversations.pendingList == nil)
			let write = try #require(result.effects.compactMap
			{
				if case .persistPreference(let write) = $0
				{
					return write
				}
				return nil
			}.first)
			#expect(write.context.workspace == model.identity)
			#expect(write.context.generation == model.connection.generation)
			#expect(model.preferences.pendingPreferenceWrites[.taskPin("thread")] == write.context)
			guard case .taskPin(
				let persisted,
				pinned: true
			) = write.value
			else
			{
				Issue.record("Expected the renamed task pin to be persisted")
				return
			}
			#expect(persisted.name == name)
		}
	}

	@Test func notificationsRefreshPinsOutsideTheCurrentList() throws
	{
		var model = workspace()
		model.preferences.pinnedTasks = [summary()]
		let result = observeTitle(
			"Renamed archived task",
			model: &model
		)
		#expect(model.conversations.threads.isEmpty)
		#expect(model.preferences.pinnedTasks.first?.displayTitle == "Renamed archived task")
		#expect(result.effects.count == 1)
	}

	@Test(arguments: [nil, "Cafe\u{301}"] as [String?])
	func notificationsPreserveClearedNamesAndExactUnicodeSpelling(name: String?) throws
	{
		var model = workspace()
		var old = summary()
		old.name = "Café"
		model.conversations.threads = [old]
		model.preferences.pinnedTasks = [old]
		let result = observeTitle(
			name,
			model: &model
		)
		let pin = try #require(model.preferences.pinnedTasks.first)
		let actualBytes = pin.name.map
		{
			Array($0.utf8)
		}
		let expectedBytes = name.map
		{
			Array($0.utf8)
		}
		#expect(actualBytes == expectedBytes)
		#expect(pin.displayTitle == model.conversations.threads.first?.displayTitle)
		#expect(result.effects.count == 1)
	}

	@Test func successfulManualRenameUpdatesLiveAndPinnedTitlesBeforeListRefresh() throws
	{
		var model = workspace()
		model.conversations.threads = [summary()]
		model.preferences.pinnedTasks = [summary()]
		var captured = context(model)
		captured.threadID = "thread"
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.managementRequested(.rename(
				context: captured,
				name: "Chosen title"
			)))
		)
		let result = ConversationReducer.reduce(
			&model,
			.conversations(.managementFinished(
				captured,
				.succeeded(())
			))
		)
		#expect(model.conversations.threads.first?.displayTitle == "Chosen title")
		#expect(model.preferences.pinnedTasks.first?.displayTitle == "Chosen title")
		#expect(result.effects.contains
		{
			if case .persistPreference(let write) = $0
			{
				return write.context == captured && write.key == .taskPin("thread")
			}
			return false
		})
		let list = try #require(model.conversations.pendingList)
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.threadListReceived(
				list,
				.succeeded([summary()])
			))
		)
		#expect(model.conversations.threads.first?.displayTitle == "Chosen title")
		#expect(model.preferences.pinnedTasks.first?.displayTitle == "Chosen title")
	}

	@Test func obsoleteNotificationsCannotRewritePinnedTitles()
	{
		var model = workspace()
		model.conversations.threads = [summary()]
		model.preferences.pinnedTasks = [summary()]
		let obsolete = OperationContext(
			workspace: model.identity,
			generation: 0,
			requestID: UUID()
		)
		let result = ConversationReducer.reduce(
			&model,
			.execution(.backendObserved(
				obsolete,
				.threadNameUpdated(
					threadId: "thread",
					name: "Obsolete title"
				)
			))
		)
		#expect(model.conversations.threads.first?.name == nil)
		#expect(model.preferences.pinnedTasks.first?.name == nil)
		#expect(result.effects.isEmpty)
	}

	@discardableResult
	private func observeTitle(
		_ name: String?,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		ConversationReducer.reduce(
			&model,
			.execution(.backendObserved(
				context(model),
				.threadNameUpdated(
					threadId: "thread",
					name: name
				)
			))
		)
	}

	private func workspace() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/titles"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.execution.state = .ready
		return model
	}

	private func context(_ model: WorkspaceModel) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID()
		)
	}

	private func summary() -> ThreadSummary
	{
		ThreadSummary(json: ["id": "thread", "cwd": "/tmp/titles", "preview": "Original prompt"])!
	}
}
