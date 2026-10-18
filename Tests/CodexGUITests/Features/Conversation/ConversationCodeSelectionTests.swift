import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ConversationCodeSelectionTests
{
	@Test(.timeLimit(.minutes(1)))
	func replacedSourceReadCannotPresentOrRetireItsReplacement() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let controller = ConversationViewController()
			let window = NSWindow(contentViewController: controller)
			window.isReleasedWhenClosed = false
			defer
			{
				window.close()
			}
			let gate = CodeSelectionLoadGate()
			controller.codeSourceLoader =
			{
				_, _ in await gate.load()
			}
			var snapshot = WorkspaceSelectors.snapshot(
				model: WorkspaceModel(identity: WorkspaceIdentity(
					sessionID: UUID(),
					canonicalCheckoutPath: nil
				)),
				now: .distantPast
			)
			controller.render(snapshot)
			var operations: [Task<Void, Never>] = []
			do
			{
				var requests = gate.requests.makeAsyncIterator()
				controller.loadCodeSelection(
					projectPath: "/fixture",
					file: URL(fileURLWithPath: "/fixture/old.swift")
				)
				let previous = try #require(controller.codeSelectionTask)
				operations.append(previous)
				try #require(await requests.next() == 1)
				#expect(!controller.attachmentsAreReady)
				snapshot.workspaceSelectionEpoch += 1
				controller.render(snapshot)
				#expect(previous.isCancelled)
				#expect(controller.codeSelectionTask == nil)
				controller.loadCodeSelection(
					projectPath: "/fixture",
					file: URL(fileURLWithPath: "/fixture/new.swift")
				)
				let replacement = try #require(controller.codeSelectionTask)
				operations.append(replacement)
				let requestID = controller.codeSelectionRequestID
				try #require(await requests.next() == 2)
				await gate.releaseNext("stale")
				await previous.value
				#expect(window.attachedSheet == nil)
				#expect(controller.codeSelectionRequestID == requestID)
				#expect(!controller.attachmentsAreReady)
				await gate.releaseNext("fresh")
				await replacement.value
				#expect(controller.codeSelectionTask == nil)
				#expect(controller.attachmentsAreReady)
				let sheet = try #require(window.attachedSheet)
				window.endSheet(
					sheet,
					returnCode: .alertSecondButtonReturn
				)
				await gate.releaseAll()
			}
			catch
			{
				controller.cancelCodeSelection()
				await gate.releaseAll()
				for operation in operations
				{
					await operation.value
				}
				if let sheet = window.attachedSheet
				{
					window.endSheet(
						sheet,
						returnCode: .alertSecondButtonReturn
					)
				}
				throw error
			}
		}
	}
}

private actor CodeSelectionLoadGate
{
	nonisolated let requests: AsyncStream<Int>
	private let continuation: AsyncStream<Int>.Continuation
	private var pending: [CheckedContinuation<CodeSelectionSourceLoader.Source, Never>] = []
	private var count = 0
	private var isReleased = false

	init()
	{
		(requests, continuation) = AsyncStream<Int>.makeStream()
	}

	func load() async -> CodeSelectionSourceLoader.Source
	{
		guard !isReleased
		else
		{
			return CodeSelectionSourceLoader.Source(
				relativePath: "code.swift",
				contents: ""
			)
		}
		return await withCheckedContinuation
		{
			waiter in
			pending.append(waiter)
			count += 1
			continuation.yield(count)
		}
	}

	func releaseNext(_ contents: String)
	{
		guard !pending.isEmpty
		else
		{
			return
		}
		pending.removeFirst().resume(returning: CodeSelectionSourceLoader.Source(
			relativePath: "code.swift",
			contents: contents
		))
	}

	func releaseAll()
	{
		isReleased = true
		while !pending.isEmpty
		{
			releaseNext("")
		}
		continuation.finish()
	}
}
