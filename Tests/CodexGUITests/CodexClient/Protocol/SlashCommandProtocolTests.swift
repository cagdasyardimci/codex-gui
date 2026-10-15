import Foundation
import Testing

@testable import CodexGUI

@Suite
struct SlashCommandProtocolTests
{
	@Test func reviewItemsReadReviewPayloadAndCompactionItemsKeepTheirLifecycleIdentity()
	{
		for type in ["enteredReviewMode", "exitedReviewMode"]
		{
			let item = CodexItem(json: [
				"id": "review",
				"type": type,
				"review": "Review findings",
				"text": "Wrong field",
			])
			#expect(item?.text == "Review findings")
		}
		let item = CodexItem(json: ["id": "compact", "type": "contextCompaction"])
		#expect(item?.id == "compact")
		#expect(item?.type == "contextCompaction")
		#expect(item?.text == nil)
	}

	@Test func serviceTiersUseCatalogMetadataWithoutAssumingPriority()
	{
		let model = ModelOption(json: [
			"model": "custom-model",
			"supportsPersonality": true,
			"defaultServiceTier": "standard",
			"serviceTiers": [["id": "express", "name": "Fast", "description": "Faster replies"]],
			"additionalSpeedTiers": ["priority"],
		])
		#expect(model?.serviceTiers.map(\.id) == ["express"])
		#expect(model?.defaultServiceTier == "standard")
		#expect(model?.supportsPersonality == true)
		let unavailable = ModelOption(json: ["model": "old-model"])
		#expect(unavailable?.serviceTiers.isEmpty == true)
		#expect(unavailable?.supportsPersonality == false)
		#expect(unavailable?.defaultServiceTier == nil)
	}

	@Test func reviewTargetsAndSettingsPreserveWireSemantics()
	{
		#expect(ReviewTarget.baseBranch(branch: "main")
			.protocolValue["branch"] as? String == "main")
		#expect(ReviewTarget.baseBranch(branch: "main")
			.protocolValue["type"] as? String == "baseBranch")
		#expect(ReviewTarget.custom(instructions: "Inspect cancellation")
			.protocolValue as? [String: String] == [
				"type": "custom",
				"instructions": "Inspect cancellation"
			])
		let commit = ReviewTarget.commit(
			sha: "abc",
			title: nil
		).protocolValue
		#expect(commit["type"] as? String == "commit")
		#expect(commit["sha"] as? String == "abc")
		#expect(commit["title"] == nil)
		let mode = CollaborationMode(
			mode: .plan,
			model: "model",
			reasoningEffort: nil
		)
		let settings = mode.protocolValue["settings"] as? [String: Any]
		#expect(settings?["developer_instructions"] is NSNull)
		#expect(settings?["reasoning_effort"] is NSNull)
		#expect(settings?["model"] as? String == "model")
		#expect(ThreadSettingsUpdate().protocolValue["serviceTier"] == nil)
		#expect(ThreadSettingsUpdate(serviceTier: .clear).protocolValue["serviceTier"] is NSNull)
		#expect(ThreadSettingsUpdate(serviceTier: .tier("express"))
			.protocolValue["serviceTier"] as? String == "express")
	}

	@MainActor
	@Test func tokenSettingsStatusAndLegacyCompactionNotificationsKeepOwnerIDs()
	{
		let server = AppServer()
		var events: [AppServerEvent] = []
		server.onEvent =
		{
			events.append($0)
		}
		let counts: [String: Any] = [
			"inputTokens": 9_000_000_000,
			"cachedInputTokens": 12,
			"outputTokens": 20,
			"reasoningOutputTokens": 3,
			"totalTokens": 9_000_000_020,
		]
		server.receiveNotification(
			method: "thread/tokenUsage/updated",
			parameters: [
				"threadId": "owner",
				"turnId": "turn",
				"tokenUsage": [
					"last": counts,
					"total": counts,
					"modelContextWindow": 100_000,
				],
			]
		)
		server.receiveNotification(
			method: "thread/settings/updated",
			parameters: [
				"threadId": "owner",
				"threadSettings": [
					"model": "model",
					"cwd": "/tmp/project",
					"effort": "high",
					"serviceTier": "express",
					"collaborationMode": CollaborationMode(
						mode: .plan,
						model: "model",
						reasoningEffort: "high"
					).protocolValue,
				],
			]
		)
		server.receiveNotification(
			method: "thread/status/changed",
			parameters: [
				"threadId": "owner",
				"status": ["type": "active", "activeFlags": ["waitingOnApproval"]],
			]
		)
		server.receiveNotification(
			method: "thread/compacted",
			parameters: [
				"threadId": "owner",
				"turnId": "turn",
			]
		)
		#expect(events.count == 4)
		if case .tokenUsageUpdated(
			let threadID,
			let turnID,
			let usage
		) = events[0]
		{
			#expect(threadID == "owner")
			#expect(turnID == "turn")
			#expect(usage.total.totalTokens == 9_000_000_020)
			#expect(usage.last.cacheWriteInputTokens == 0)
			#expect(usage.modelContextWindow == 100_000)
		}
		else
		{
			Issue.record("Expected token usage notification")
		}
		if case .threadSettingsUpdated(
			let threadID,
			let settings
		) = events[1]
		{
			#expect(threadID == "owner")
			#expect(settings.collaborationMode?.mode == .plan)
			#expect(settings.reasoningEffort == "high")
			#expect(settings.serviceTier == "express")
		}
		else
		{
			Issue.record("Expected settings notification")
		}
		if case .threadStatusChanged(
			let threadID,
			let status
		) = events[2]
		{
			#expect(threadID == "owner")
			#expect(status.activeFlags == ["waitingOnApproval"])
		}
		else
		{
			Issue.record("Expected status notification")
		}
		if case .contextCompacted(
			let threadID,
			let turnID
		) = events[3]
		{
			#expect(threadID == "owner")
			#expect(turnID == "turn")
		}
		else
		{
			Issue.record("Expected compaction notification")
		}

		server.receiveNotification(
			method: "thread/tokenUsage/updated",
			parameters: [
				"threadId": "owner",
				"turnId": "turn",
				"tokenUsage": ["last": counts],
			]
		)
		server.receiveNotification(
			method: "thread/status/changed",
			parameters: [
				"threadId": "owner",
				"status": ["type": "active"],
			]
		)
		server.receiveNotification(
			method: "thread/compacted",
			parameters: ["threadId": "owner"]
		)
		#expect(events.count == 4)
	}
}
