import Foundation

/// Builds ordered rows without mutating controls or navigation selection.
enum NavigationSidebarItemsBuilder
{
	static func build(
		recentProjects: [URL],
		currentProject: URL?,
		pinnedProjectPaths: Set<String>,
		visibleThreads: [ThreadSummary],
		pinnedTasks: [ThreadSummary] = [],
		isCurrentProjectCollapsed: Bool = false,
		projectTaskLimit: Int = 5,
		removedProjectPaths: Set<String> = [],
		organization: SidebarPreferences.Organization = .byProject,
		sortOrder: SidebarPreferences.SortOrder = .lastUpdated,
		manualThreadIDs: [String] = []
	) -> [NavigationSidebarItem]
	{
		let projects = orderedProjects(
			recentProjects: recentProjects,
			currentProject: currentProject,
			pinnedProjectPaths: pinnedProjectPaths
		)
		let visibleProjects = projects.filter
		{
			!removedProjectPaths.contains($0.path)
		}
		let pinnedProjects = visibleProjects.filter
		{
			pinnedProjectPaths.contains($0.path)
		}
		let unpinnedProjects = visibleProjects.filter
		{
			!pinnedProjectPaths.contains($0.path)
		}
		let pinnedIDs = Set(pinnedTasks.map(\.id))
		let projectThreads = orderedThreads(
			visibleThreads,
			sortOrder: sortOrder,
			manualThreadIDs: manualThreadIDs
		).filter
		{
			!pinnedIDs.contains($0.id)
		}
		var items: [NavigationSidebarItem] = []
		if !pinnedTasks.isEmpty || !pinnedProjects.isEmpty
		{
			items.append(.sectionHeader("Pinned"))
			items.append(contentsOf: pinnedTasks.map
			{
				.pinnedThread($0)
			})
		}
		if organization == .oneList
		{
			items.append(contentsOf: pinnedProjects.map
			{
				.project($0)
			})
			if !items.isEmpty
			{
				items.append(.sectionHeader("Recents"))
			}
			items.append(contentsOf: projectThreads.map
			{
				.thread($0)
			})
			return items
		}
		for project in pinnedProjects + unpinnedProjects
		{
			if !pinnedTasks.isEmpty || !pinnedProjects.isEmpty,
				project == unpinnedProjects.first
			{
				items.append(.sectionHeader("Projects"))
			}
			items.append(.project(project))
			let shouldShowProjectTasks = project == currentProject && !isCurrentProjectCollapsed
			if shouldShowProjectTasks
			{
				let recentThreads = projectThreads
				items.append(contentsOf: recentThreads.prefix(projectTaskLimit).map
				{
					.thread($0)
				})
				if recentThreads.count > projectTaskLimit
				{
					items.append(.showMore)
				}
			}
		}
		if currentProject == nil
		{
			items.append(contentsOf: projectThreads.map
			{
				.thread($0)
			})
		}
		return items
	}

	private static func orderedProjects(
		recentProjects: [URL],
		currentProject: URL?,
		pinnedProjectPaths: Set<String>
	) -> [URL]
	{
		var candidates = recentProjects
		if let currentProject, !candidates.contains(currentProject)
		{
			candidates.insert(
				currentProject,
				at: 0
			)
		}
		candidates.append(contentsOf: pinnedProjectPaths.sorted().map
		{
			URL(fileURLWithPath: $0)
		})
		var seenPaths: Set<String> = []
		let uniqueProjects = candidates.compactMap
		{
			project -> URL? in
			let key = project.standardizedFileURL.resolvingSymlinksInPath().path
			guard seenPaths.insert(key).inserted
			else
			{
				return nil
			}
			return URL(fileURLWithPath: key)
		}
		let pinnedProjects = uniqueProjects.filter
		{
			pinnedProjectPaths.contains($0.path)
		}
		let unpinnedProjects = uniqueProjects.filter
		{
			!pinnedProjectPaths.contains($0.path)
		}
		return pinnedProjects + unpinnedProjects
	}

	static func orderedThreads(
		_ threads: [ThreadSummary],
		sortOrder: SidebarPreferences.SortOrder,
		manualThreadIDs: [String]
	) -> [ThreadSummary]
	{
		var ranks: [String: Int] = [:]
		for (index, id) in manualThreadIDs.enumerated() where ranks[id] == nil
		{
			ranks[id] = index
		}
		return threads.enumerated().sorted
		{
			lhs, rhs in
			if sortOrder == .manual
			{
				let leftRank = ranks[lhs.element.id] ?? Int.max
				let rightRank = ranks[rhs.element.id] ?? Int.max
				if leftRank != rightRank
				{
					return leftRank < rightRank
				}
			}
			let leftDate = lhs.element.updatedAt ?? .distantPast
			let rightDate = rhs.element.updatedAt ?? .distantPast
			return leftDate == rightDate ? lhs.offset < rhs.offset : leftDate > rightDate
		}.map(\.element)
	}

}
