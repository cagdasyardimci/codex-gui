import Foundation
import Testing

@testable import CodexGUI

struct SettingsArchivedChatCatalogTests
{
	@Test func canonicalPathsKeepSameNamedProjectsDistinctAndGroupManagedWorktrees()
	{
		let catalog = SettingsArchivedChatCatalog(
			threads: [
				thread(
					"source",
					title: "Source",
					cwd: "/work/one/project/"
				),
				thread(
					"worktree",
					title: "Worktree",
					cwd: "/managed/checkout/Sources"
				),
				thread(
					"second",
					title: "Second",
					cwd: "/work/two/project"
				),
			],
			checkoutProjects: ["/managed/checkout": "/work/one/project"],
			projectNames: ["/work/one/project": "project", "/work/two/project": "project"]
		)
		let groups = catalog.filter()
		#expect(groups.count == 2)
		#expect(groups.map(\.id) == ["path:/work/one/project", "path:/work/two/project"])
		#expect(Set(groups[0].chats.map(\.id)) == ["source", "worktree"])
		#expect(groups[1].chats.map(\.id) == ["second"])
		#expect(groups.map(\.title) == ["project", "project"])
	}

	@Test func explicitBackendMembershipOutranksCheckoutPathsAndKeepsUnknownProjectsDistinct()
	{
		var first = thread(
			"one",
			title: "One",
			cwd: "/same/checkout"
		)
		first["projectId"] = "first"
		var second = thread(
			"two",
			title: "Two",
			cwd: "/same/checkout"
		)
		second["projectId"] = "second"
		var unknown = thread(
			"unknown",
			title: "Unknown",
			cwd: "/same/checkout"
		)
		unknown["projectId"] = "missing"
		let catalog = SettingsArchivedChatCatalog(
			threads: [
				first,
				second,
				unknown,
				thread(
					"unassigned",
					title: "Local",
					cwd: "/same/checkout"
				)
			],
			projects: [
				["id": "first", "name": "First project", "roots": [["path": "/same/checkout"]]],
				["id": "second", "name": "Second project", "roots": [["path": "/same/checkout"]]],
			],
			checkoutProjects: ["/same/checkout": "/source/project"],
			projectNames: ["/source/project": "Local project"]
		)
		#expect(catalog.chats.map(\.projectID) == [
			"project:first",
			"project:second",
			"project:missing",
			"path:/source/project",
		])
		#expect(catalog.chats.map(\.projectName) == [
			"First project",
			"Second project",
			"Project missing",
			"Local project",
		])
		#expect(catalog.filter(projectID: "project:second").flatMap(\.chats).map(\.id) == ["two"])
	}

	@Test func missingProjectRowsRemainSearchableAndExplicitlyFilterable()
	{
		let catalog = SettingsArchivedChatCatalog(threads: [
			thread(
				"missing",
				title: "Missing",
				cwd: nil
			),
			thread(
				"empty",
				title: "Empty",
				cwd: "  "
			),
			thread(
				"relative",
				title: "Relative",
				cwd: "relative/path"
			),
			thread(
				"project",
				title: "Project",
				cwd: "/work/project"
			),
		])
		let groups = catalog.filter()
		#expect(groups.first?.id == nil)
		#expect(groups.first?.title == "No project")
		#expect(groups.map(\.id) == [nil, "path:/work/project"])
		#expect(Set(groups.first?.chats.map(\.id) ?? []) == ["missing", "empty", "relative"])
		let unassigned = catalog.filter(projectID: SettingsArchivedChatCatalog.noProjectID)
		#expect(unassigned.count == 1)
		#expect(unassigned[0].chats.count == 3)
		#expect(catalog.filter(query: "EMPTY").flatMap(\.chats).map(\.id) == ["empty"])
	}

	@Test func titleAndPreviewSearchComposeWithProjectAndLocalFilters()
	{
		var preview = thread(
			"preview",
			title: "Other title",
			cwd: "/one"
		)
		preview["preview"] = "Investigate LOCAL rendering"
		let catalog = SettingsArchivedChatCatalog(threads: [
			preview,
			thread(
				"title",
				title: "Local settings",
				cwd: "/two"
			),
			thread(
				"other",
				title: "Unrelated",
				cwd: "/one"
			),
		])
		#expect(Set(catalog.filter(query: " local ").flatMap(\.chats).map(\.id)) == [
			"preview",
			"title"
		])
		#expect(catalog.filter(
			query: "LOCAL",
			projectID: "path:/one",
			kind: .local
		)
		.flatMap(\.chats).map(\.id) == ["preview"])
		#expect(catalog.filter(
			query: "LOCAL",
			projectID: "path:/one",
			kind: .cloud
		).isEmpty)
		#expect(catalog.filter(query: "no matching title").isEmpty)
	}

	@Test func sortDatesFallbackAndTiesRemainStableIndependentOfInputOrder()
	{
		let entries = [
			thread(
				"a",
				title: "zebra",
				cwd: "/project",
				created: 300,
				updated: 100
			),
			thread(
				"b",
				title: "Alpha",
				cwd: "/project",
				created: 100,
				updated: 300
			),
			thread(
				"c",
				title: "alpha",
				cwd: "/project",
				created: 200,
				updated: nil
			),
			thread(
				"d",
				title: "Missing dates",
				cwd: "/project",
				created: nil,
				updated: nil
			),
		]
		let catalog = SettingsArchivedChatCatalog(threads: Array(entries.reversed()))
		#expect(catalog.filter(sort: .updated).flatMap(\.chats).map(\.id) == ["b", "c", "a", "d"])
		#expect(catalog.filter(sort: .created).flatMap(\.chats).map(\.id) == ["a", "c", "b", "d"])
		#expect(catalog.filter(sort: .alphabetical).flatMap(\.chats).map(\.id) == [
			"b",
			"c",
			"d",
			"a"
		])
		let tied = SettingsArchivedChatCatalog(threads: [
			thread(
				"z",
				title: "Same",
				cwd: "/project"
			),
			thread(
				"a",
				title: "Same",
				cwd: "/project"
			),
		])
		#expect(tied.filter(sort: .updated).flatMap(\.chats).map(\.id) == ["a", "z"])
	}

	@Test func sessionSourceDoesNotInventCloudClassificationAndDuplicateIDsAreIgnored()
	{
		var custom = thread(
			"custom",
			title: "Custom",
			cwd: nil
		)
		custom["source"] = ["custom": "remote-looking-client"]
		var subagent = thread(
			"agent",
			title: "Agent",
			cwd: nil
		)
		subagent["source"] = ["subAgent": ["thread_spawn": [
			"parent_thread_id": "parent",
			"depth": 1
		]]]
		let catalog = SettingsArchivedChatCatalog(threads: [custom, subagent, custom, [:]])
		#expect(catalog.chats.count == 2)
		#expect(catalog.chats[0].source == .custom("remote-looking-client"))
		#expect(catalog.chats[1].source == .subAgent)
		#expect(catalog.filter(kind: .local).flatMap(\.chats).count == 2)
		#expect(catalog.filter(kind: .cloud).isEmpty)
	}

	private func thread(
		_ id: String,
		title: String,
		cwd: String?,
		created: Double? = 100,
		updated: Double? = 200
	) -> [String: Any]
	{
		var json: [String: Any] = ["id": id, "name": title, "preview": "", "source": "appServer"]
		if let cwd
		{
			json["cwd"] = cwd
		}
		if let created
		{
			json["createdAt"] = created
		}
		if let updated
		{
			json["updatedAt"] = updated
		}
		return json
	}
}
