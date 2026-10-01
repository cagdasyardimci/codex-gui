import Foundation

/// Builds ordered rows without mutating controls or navigation selection.
enum NavigationSidebarItemsBuilder
{
	static func build(
		recentProjects: [URL],
		currentProject: URL?,
		pinnedProjectPaths: Set<String>,
		visibleThreads: [ThreadSummary],
		isCurrentProjectCollapsed: Bool = false,
		projectTaskLimit: Int = 5
	) -> [NavigationSidebarItem]
	{
		let projects = orderedProjects(
			recentProjects: recentProjects,
			currentProject: currentProject,
			pinnedProjectPaths: pinnedProjectPaths
		)
		var items: [NavigationSidebarItem] = []
		for project in projects
		{
			items.append(.project(project))
			let shouldShowProjectTasks = project == currentProject && !isCurrentProjectCollapsed
			if shouldShowProjectTasks
			{
				let recentThreads = threadsInRecentOrder(visibleThreads)
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
			items.append(contentsOf: visibleThreads.map
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

	private static func threadsInRecentOrder(_ threads: [ThreadSummary]) -> [ThreadSummary]
	{
		threads.enumerated().sorted
		{
			lhs, rhs in
			let leftDate = lhs.element.updatedAt ?? .distantPast
			let rightDate = rhs.element.updatedAt ?? .distantPast
			return leftDate == rightDate ? lhs.offset < rhs.offset : leftDate > rightDate
		}.map(\.element)
	}

}
