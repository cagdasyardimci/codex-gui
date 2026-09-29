import Foundation

/// Builds ordered rows without mutating controls or navigation selection.
enum NavigationSidebarItemsBuilder
{
	static func build(
		recentProjects: [URL],
		currentProject: URL?,
		pinnedProjectPaths: Set<String>,
		visibleThreads: [ThreadSummary]
	) -> [NavigationSidebarItem]
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
		let projects =
			uniqueProjects.filter
				{
					pinnedProjectPaths.contains($0.path)
				}
				+ uniqueProjects.filter
				{
					!pinnedProjectPaths.contains($0.path)
				}
		var items: [NavigationSidebarItem] = []
		for project in projects
		{
			items.append(.project(project))
			if project == currentProject
			{
				items.append(contentsOf: visibleThreads.map
				{
					.thread($0)
				})
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
}
