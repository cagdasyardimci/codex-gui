import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{
	@Test func skillsInvalidationsShareOneFiniteTwoAttemptGroup() async throws
	{
		let service = MockCodexService()
		service.suspendedSkillReadNumbers = [1, 2]
		let store = contextStore(
			model: contextModel(),
			service: service
		)
		let context = store.operationContext()
		store.dispatch(.contextNavigation(.skillsInvalidated(context)))
		let handle = try #require(store.operation(for: context))
		await service.waitForSkillRead(1)
		for _ in 0 ..< 20
		{
			store.dispatch(.contextNavigation(.skillsInvalidated(store.operationContext())))
		}
		let first = try #require(store.model.contextNavigation.pendingSkillRefresh)
		service.pendingSkillReads.removeValue(forKey: 1)?.resume(returning:
			SkillCatalog(
				skills: [],
				errors: []
			))
		await service.waitForSkillRead(2)
		#expect(store.model.contextNavigation.pendingSkillRefresh?.attempt == 1)
		#expect(store.model.contextNavigation.pendingSkillRefresh?.context == context)
		store.dispatch(.contextNavigation(.skillsReceived(
			first,
			.failed(OperationFailure(
				message: "Late first failure",
				outcomeIsUncertain: false
			))
		)))
		#expect(store.model.contextNavigation.pendingSkillRefresh?.attempt == 1)
		#expect(store.model.contextNavigation.skillError == nil)
		for _ in 0 ..< 20
		{
			store.dispatch(.contextNavigation(.skillsInvalidated(store.operationContext())))
		}
		service.pendingSkillReads.removeValue(forKey: 2)?.resume(returning:
			SkillCatalog(
				skills: [],
				errors: []
			))
		#expect(await handle.wait() == .finished)
		#expect(service.skillReadCount == 2)
		#expect(store.model.contextNavigation.pendingSkillRefresh == nil)
		#expect(!store.model.contextNavigation.skillRefreshPending)
	}
}
