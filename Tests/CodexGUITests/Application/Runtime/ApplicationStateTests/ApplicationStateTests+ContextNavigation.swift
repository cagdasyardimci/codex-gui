import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{
	@Test func skillsInvalidationsShareOneFiniteTwoAttemptGroup() async throws
	{
		let service = MockCodexService()
		service.suspendedSkillReadNumbers = [1, 2]
		let firstCatalog = SkillCatalog(
			skills: [try #require(AvailableSkill(json: [
				"name": "old-review",
				"description": "First discovered skill",
				"path": "/skills/old-review/SKILL.md",
				"scope": "repo",
				"enabled": true
			]))],
			errors: []
		)
		let secondCatalog = SkillCatalog(
			skills: [try #require(AvailableSkill(json: [
				"name": "current-review",
				"description": "Replacement discovered skill",
				"path": "/skills/current-review/SKILL.md",
				"scope": "user",
				"enabled": false
			]))],
			errors: [try #require(SkillDiscoveryError(json: [
				"path": "/skills/broken/SKILL.md",
				"message": "Missing description"
			]))]
		)
		let store = contextStore(
			model: contextModel(),
			service: service
		)
		defer
		{
			store.shutdown()
			let suspended = Array(service.pendingSkillReads.values)
			service.pendingSkillReads.removeAll()
			for continuation in suspended
			{
				continuation.resume(throwing: CancellationError())
			}
		}
		let context = store.operationContext()
		store.dispatch(.contextNavigation(.skillsInvalidated(context)))
		let handle = try #require(store.operation(for: context))
		await service.waitForSkillRead(1)
		for _ in 0 ..< 20
		{
			store.dispatch(.contextNavigation(.skillsInvalidated(store.operationContext())))
		}
		let first = try #require(store.model.contextNavigation.pendingSkillRefresh)
		let firstContinuation = service.pendingSkillReads.removeValue(forKey: 1)
		let firstRead = try #require(firstContinuation)
		firstRead.resume(returning: firstCatalog)
		await service.waitForSkillRead(2)
		#expect(store.model.contextNavigation.pendingSkillRefresh?.attempt == 1)
		#expect(store.model.contextNavigation.pendingSkillRefresh?.context == context)
		#expect(store.model.contextNavigation.skillCatalog == firstCatalog)
		#expect(store.model.contextNavigation.skillError == nil)
		store.dispatch(.contextNavigation(.skillsReceived(
			first,
			.failed(OperationFailure(
				message: "Late first failure",
				outcomeIsUncertain: false
			))
		)))
		#expect(store.model.contextNavigation.pendingSkillRefresh?.attempt == 1)
		#expect(store.model.contextNavigation.skillCatalog == firstCatalog)
		#expect(store.model.contextNavigation.skillError == nil)
		for _ in 0 ..< 20
		{
			store.dispatch(.contextNavigation(.skillsInvalidated(store.operationContext())))
		}
		let secondContinuation = service.pendingSkillReads.removeValue(forKey: 2)
		let secondRead = try #require(secondContinuation)
		secondRead.resume(returning: secondCatalog)
		#expect(await handle.wait() == .finished)
		#expect(service.skillReadCount == 2)
		#expect(store.model.contextNavigation.skillCatalog == secondCatalog)
		#expect(store.model.contextNavigation.skillError
			== "/skills/broken/SKILL.md: Missing description")
		#expect(store.model.contextNavigation.pendingSkillRefresh == nil)
		#expect(!store.model.contextNavigation.skillRefreshPending)
	}
}
