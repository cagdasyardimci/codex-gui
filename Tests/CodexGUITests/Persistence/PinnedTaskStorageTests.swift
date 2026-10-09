import Foundation
import Testing

@testable import CodexGUI

@Suite("Pinned task storage")
struct PinnedTaskStorageTests
{
	@Test("Pinned summaries persist across projects and storage instances")
	@MainActor
	func persistsGlobalPins() throws
	{
		let fixture = try IsolatedUserDefaultsFixture(prefix: "PinnedTaskStorageTests")
		defer
		{
			fixture.cleanup()
		}
		let storage = LocalStorage(defaults: fixture.defaults)
		let first = try #require(ThreadSummary(json: [
			"id": "first",
			"cwd": "/project-a",
			"name": "First task"
		]))
		let second = try #require(ThreadSummary(json: [
			"id": "second",
			"cwd": "/project-b",
			"preview": "Second task"
		]))
		storage.setTaskPinned(
			first,
			pinned: true
		)
		storage.setTaskPinned(
			second,
			pinned: true
		)
		let restored = LocalStorage(defaults: fixture.defaults)
		#expect(restored.pinnedTasks == [first, second])
		#expect(restored.preferenceRestoration.pinnedTasks == [first, second])
		var renamed = first
		renamed.name = "Renamed"
		restored.setTaskPinned(
			renamed,
			pinned: true
		)
		#expect(restored.pinnedTasks == [renamed, second])
		restored.setTaskPinned(
			renamed,
			pinned: false
		)
		#expect(storage.pinnedTasks == [second])
	}

	@Test("Pin writes publish preferences to every workspace observer")
	@MainActor
	func publishesPinChanges() throws
	{
		let fixture = try IsolatedUserDefaultsFixture(prefix: "PinnedTaskStorageTests")
		defer
		{
			fixture.cleanup()
		}
		let storage = LocalStorage(defaults: fixture.defaults)
		var firstObserver: [ThreadSummary] = []
		var secondObserver: [ThreadSummary] = []
		let firstID = storage.observePreferences
		{
			firstObserver = $0.pinnedTasks
		}
		let secondID = storage.observePreferences
		{
			secondObserver = $0.pinnedTasks
		}
		defer
		{
			storage.removePreferenceObserver(firstID)
			storage.removePreferenceObserver(secondID)
		}
		let task = try #require(ThreadSummary(json: ["id": "task", "cwd": "/project"]))
		storage.setTaskPinned(
			task,
			pinned: true
		)
		#expect(firstObserver == [task])
		#expect(secondObserver == [task])
		storage.setTaskPinned(
			task,
			pinned: false
		)
		#expect(firstObserver.isEmpty)
		#expect(secondObserver.isEmpty)
	}
}
