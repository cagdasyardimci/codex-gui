/// Compares the literal text used by native menus as well as their semantic values.
enum NavigationMenuContent
{
	static func sameWorkspaces(
		_ left: [TaskWorkspaceChoice],
		_ right: [TaskWorkspaceChoice]
	) -> Bool
	{
		guard left == right
		else
		{
			return false
		}
		return zip(
			left,
			right
		).allSatisfy
		{
			left, right in
			sameText(
				left.title,
				right.title
			)
				&& sameText(
					left.checkoutPath,
					right.checkoutPath
				)
				&& sameText(
					left.branch,
					right.branch
				)
				&& sameText(
					left.issue,
					right.issue
				)
		}
	}

	static func sameProjectNames(
		_ left: [String: String],
		_ right: [String: String]
	) -> Bool
	{
		guard left == right
		else
		{
			return false
		}
		return left.allSatisfy
		{
			path, name in
			sameText(
				name,
				right[path]
			)
		}
	}

	private static func sameText(
		_ left: String?,
		_ right: String?
	) -> Bool
	{
		switch (left, right)
		{
		case (nil, nil): true
		case (.some(let left), .some(let right)): left.utf8.elementsEqual(right.utf8)
		default: false
		}
	}
}
