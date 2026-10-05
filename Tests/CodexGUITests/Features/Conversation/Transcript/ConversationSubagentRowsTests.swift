import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationSubagentRowsTests
{
	@Test func referenceAuditEventsSurviveDecodingAndKeepTheirConversationOrder() throws
	{
		let paths = ["client",
						"runtime",
						"state_integration",
						"reducers",
						"services",
						"storage_workspaces",
						"app_ui",
						"transcript",
						"composer_navigation",
						"changes_ui"]
		let starts = try paths.enumerated().map
		{
			index, path in
			try entry(
				id: "start-\(index)",
				kind: "started",
				path: path
			)
		}
		let comment = ConversationEntry(
			id: "turn:comment",
			kind: .agent,
			title: "Codex",
			body: "Ten subagents now have areas."
		)
		let finish = try entry(
			id: "finish",
			kind: "completed",
			path: "services"
		)
		let rows = ConversationTranscriptRow.make(
			entries: starts + [comment, finish],
			projectPath: nil
		)
		#expect(rows.count == 3)
		let first = try #require(activity(rows[0]))
		#expect(first.kind == .subagent)
		#expect(first.title == "Client, Runtime and 8 more started working")
		#expect(first.subagents.count == 10)
		#expect(first.subagents.map(\.name) == ["Client",
												"Runtime",
												"State Integration",
												"Reducers",
												"Services",
												"Storage Workspaces",
												"App Ui",
												"Transcript",
												"Composer Navigation",
												"Changes Ui"])
		#expect(rows[1] == .message(comment))
		#expect(activity(rows[2])?.title == "Services finished")
		#expect(activity(rows[2])?.subagents.first?.threadID == "agent-services")
	}

	@Test func lifecycleChangesAndTurnBoundariesSplitGroups() throws
	{
		let start = try entry(
			id: "start",
			kind: "started",
			path: "client"
		)
		let input = try entry(
			id: "input",
			kind: "interacted",
			path: "client"
		)
		let finish = try entry(
			id: "finish",
			kind: "completed",
			path: "client"
		)
		let otherTurn = try entry(
			id: "finish",
			kind: "completed",
			path: "runtime",
			turn: "other"
		)
		let rows = ConversationTranscriptRow.make(
			entries: [start, input, finish, otherTurn],
			projectPath: nil
		)
		#expect(rows.compactMap(activity).map(\.title) == [
			"Client started working",
			"Client received input",
			"Client finished",
			"Runtime finished"
		])
		#expect(rows.map(\.sourceEntryID) == [
			"turn:start",
			"turn:input",
			"turn:finish",
			"other:finish"
		])
	}

	@Test func nativeRowShowsBadgesAndLabelAndClearsBadgesOnReuse() throws
	{
		let agents = ["client", "runtime", "services", "transcript", "reducers"].map
		{
			CodexSubagentActivity(json: ["kind": "started", "agentPath": "/root/\($0)"])
		}
		let row = ConversationSubagentRows.row(
			id: "turn:start",
			agents: agents
		)
		let item = ConversationActivityCollectionItem()
		item.configure(
			row,
			onToggle:
			{
			},
			onOpenFile:
			{
				_ in
			}
		)
		#expect(descendants(item.view).compactMap
		{
			$0 as? NSTextField
		}.contains
		{
			$0.stringValue == "Client, Runtime and 3 more started working"
		})
		#expect(item.view.accessibilityLabel()?.contains("Reducers started working") == true)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 700,
				height: 30
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentView = item.view
		defer
		{
			window.close()
		}
		item.view.layoutSubtreeIfNeeded()
		item.viewDidLayout()
		item.view.layoutSubtreeIfNeeded()
		let badges = descendants(item.view).compactMap
		{
			$0 as? NSImageView
		}
		#expect(badges.count == 4)
		#expect(badges.first?.superview?.frame.width == 87)
		for badge in badges
		{
			let alignment = badge.alignmentRect(forFrame: badge.frame)
			#expect(alignment.width == 18)
			#expect(alignment.height == 18)
		}
		#expect(badges.allSatisfy
		{
			$0.image?.isTemplate == false && $0.contentTintColor == nil
		})
		#expect(badges.map(\.toolTip) == ["Client", "Runtime", "Services", "Transcript"])
		item.configure(
			ConversationActivityRow(
				id: "turn:command",
				sourceEntryID: "turn:command",
				groupID: "turn:command",
				kind: .command,
				title: "Ran a command"
			),
			onToggle:
			{
			},
			onOpenFile:
			{
				_ in
			}
		)
		#expect(descendants(item.view).compactMap
		{
			$0 as? NSImageView
		}.count == 1)
	}

	@Test func missingAgentIdentityStillProducesAVisibleRow() throws
	{
		let item = try #require(CodexItem(json: [
			"id": "unknown",
			"type": "subAgentActivity",
			"kind": "completed"
		]))
		let entry = ConversationContentReducer.entry(
			for: item,
			id: "turn:unknown"
		)
		let rows = ConversationTranscriptRow.make(
			entries: [entry],
			projectPath: nil
		)
		#expect(rows.compactMap(activity).map(\.title) == ["Subagent finished"])
	}

	private func entry(
		id: String,
		kind: String,
		path: String,
		turn: String = "turn"
	) throws -> ConversationEntry
	{
		let item = try #require(CodexItem(json: [
			"id": id,
			"type": "subAgentActivity",
			"kind": kind,
			"agentThreadId": "agent-\(path)",
			"agentPath": "/root/\(path)"
		]))
		return ConversationContentReducer.entry(
			for: item,
			id: "\(turn):\(id)"
		)
	}

	private func activity(_ row: ConversationTranscriptRow) -> ConversationActivityRow?
	{
		guard case .activity(let activity) = row
		else
		{
			return nil
		}
		return activity
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}
}
