import AppKit

/// Chooses review visibility and width from the current split geometry and saved preference.
enum WindowPaneLayoutPolicy
{
	struct ReviewLayout
	{
		let collapsed: Bool
		let width: CGFloat
	}

	static func reviewLayout(
		width: CGFloat,
		navigationCollapsed: Bool,
		navigationWidth: CGFloat,
		dividerThickness: CGFloat,
		isToolsExpanded: Bool,
		usesToolsSizing: Bool,
		workspaceFilesExpanded: Bool,
		expandedToolsWidth: CGFloat,
		workspaceFilesWidth: CGFloat,
		expandedReviewWidth: CGFloat,
		reviewVisibility: WindowReviewVisibility
	) -> ReviewLayout
	{
		let visibleNavigationWidth = navigationCollapsed ? 0 : navigationWidth
		let conversationWidth = isToolsExpanded ? 0 :
			(usesToolsSizing ? WindowPaneLayout.toolsConversationMinimumWidth :
				WindowPaneLayout.conversationMinimumWidth)
		let dividerCount = (visibleNavigationWidth > 0 ? 1 : 0) + (isToolsExpanded ? 0 : 1)
		let dividerSpace = dividerThickness * CGFloat(dividerCount)
		let availableReviewWidth = width - visibleNavigationWidth - dividerSpace - conversationWidth
		let preferredReviewWidth = usesToolsSizing ? expandedToolsWidth :
			(workspaceFilesExpanded ? workspaceFilesWidth : expandedReviewWidth)

		let minimumReviewWidth = usesToolsSizing
			? WindowPaneLayout.toolsMinimumWidth : WindowPaneLayout.reviewMinimumWidth
		let collapsed: Bool
		switch reviewVisibility
		{
		case .collapsed: collapsed = true
		case .automatic:
			collapsed = width - visibleNavigationWidth - dividerSpace - preferredReviewWidth
				< WindowPaneLayout.conversationComfortableWidth
		case .expanded:
			collapsed = availableReviewWidth < minimumReviewWidth
		}
		return ReviewLayout(
			collapsed: collapsed,
			width: isToolsExpanded ? availableReviewWidth : min(
				preferredReviewWidth,
				availableReviewWidth
			)
		)
	}
}
