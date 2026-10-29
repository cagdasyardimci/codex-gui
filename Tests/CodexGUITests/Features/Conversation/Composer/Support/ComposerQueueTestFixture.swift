import AppKit

@testable import CodexGUI

@MainActor
final class ComposerQueueTestFixture
{
	let window: TranscriptPointerTestWindow
	let queue = ComposerQueueView()
	let presentation: ConversationPresentation.Composer

	init(
		texts: [String] = [
			"Wait for 60 seconds and say hello",
			"Wait for 70 seconds and say hello",
			"Wait for 80 seconds and say hello"
		],
		queueFrame: NSRect? = nil
	)
	{
		window = TranscriptPointerTestWindow(
			contentRect: NSRect(
				x: 100,
				y: 200,
				width: 800,
				height: 600
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		let root = window.contentView!
		root.addSubview(queue)
		if let queueFrame
		{
			queue.frame = queueFrame
		}
		else
		{
			queue.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				queue.leadingAnchor.constraint(
					equalTo: root.leadingAnchor,
					constant: 20
				),
				queue.bottomAnchor.constraint(
					equalTo: root.bottomAnchor,
					constant: 180
				),
				queue.widthAnchor.constraint(equalToConstant: 700)
			])
		}

		let model = Self.model(
			messages: texts.map(Self.message),
			paused: true
		)
		presentation = ConversationPresentation(WorkspaceSelectors.snapshot(
			model: model,
			now: Date()
		)).composer
		queue.render(presentation)
		window.makeKeyAndOrderFront(nil)
		window.layoutIfNeeded()
	}

	func close()
	{
		queue.cancelReordering()
		queue.clearActionHovers()
		window.close()
	}

	static func message(_ text: String) -> QueuedComposerMessage
	{
		QueuedComposerMessage(
			id: UUID(),
			text: text,
			context: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			skills: [],
			collaborationMode: nil,
			serviceTier: nil
		)
	}

	static func model(
		messages: [QueuedComposerMessage],
		draft: String = "",
		paused: Bool = false
	) -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/queue-ui"
		))
		model.connection.isConnected = true
		model.conversations.selectedConversation = .thread("chat")
		model.composer.drafts[.thread("chat")] = ComposerDraft(
			text: draft,
			queuedMessages: messages,
			queuePaused: paused
		)
		return model
	}
}
