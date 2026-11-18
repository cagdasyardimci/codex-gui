import AppKit

/// Owns the comparison controls and their responsive presentation.
@MainActor
final class GitComparisonToolbarView: NSStackView
{
	struct Actions
	{
		let scope: Selector
		let revisions: Selector
		let revisionMenu: Selector
		let branchMenu: Selector
		let displayMenu: Selector
		let fileJump: Selector
		let refresh: Selector
		let wordWrap: Selector
		let collapseAll: Selector
		let diffLayout: Selector
		let navigator: Selector
	}

	let scopeButton = ViewerToolbarButton(
		title: "Uncommitted",
		target: nil,
		action: nil
	)
	let optionsButton = ViewerToolbarButton.icon(
		"Diff display options",
		image: GitReviewReferenceIcons.image(.ellipsis),
		target: nil,
		action: nil
	)
	let baseField = NSTextField(string: "HEAD^")
	let targetField = NSTextField(string: "HEAD")
	let branchTargetButton = ViewerToolbarButton(
		title: "HEAD",
		target: nil,
		action: nil
	)
	private var revisionMenuButton: NSButton?
	let diffStats = DesktopDiffStats(
		counts: .init(
			additions: 0,
			deletions: 0
		),
		presentation: .toolbar
	)
	var additionsLabel: NSTextField
	{
		diffStats.additionsLabel
	}
	var deletionsLabel: NSTextField
	{
		diffStats.deletionsLabel
	}
	private(set) var revisionComparison: NSView?
	private(set) var diffLayoutButton: NSButton?
	private(set) var fileJumpButton: NSButton?
	private(set) var refreshButton: NSButton?
	private(set) var wordWrapButton: NSButton?
	private(set) var collapseDiffsButton: NSButton?
	private(set) var navigatorToggle: NSButton?
	private(set) var usesCompactLayout = false
	private enum Layout
	{
		static let compactRevisionThreshold: CGFloat = 520
		static let compactToolbarThreshold: CGFloat = 640
		static let minimumRevisionWidth: CGFloat = 28
		static let maximumRevisionWidth: CGFloat = 160
		static let compactMaximumRevisionWidth: CGFloat = 80
	}

	private var usesCompactRevisions = false
	private var baseRevisionWidth: NSLayoutConstraint?
	private var targetRevisionWidth: NSLayoutConstraint?
	private weak var actionTarget: AnyObject?

	func configure(
		target: AnyObject,
		actions: Actions
	)
	{
		actionTarget = target
		let scope = makeScopeControls(
			target: target,
			action: actions.scope
		)
		let refs = makeRevisionControls(
			target: target,
			actions: actions
		)
		let tools = makeComparisonActions(
			target: target,
			actions: actions
		)
		orientation = .horizontal
		alignment = .centerY
		spacing = 3.5
		edgeInsets = NSEdgeInsets(
			top: 0,
			left: 8,
			bottom: 0,
			right: 8
		)
		for control in [scope, refs, GitReviewControls.spacer(), tools]
		{
			addArrangedSubview(control)
		}
	}

	private func makeScopeControls(
		target: AnyObject,
		action: Selector
	) -> NSView
	{
		scopeButton.target = target
		scopeButton.action = action
		scopeButton.isBordered = false
		scopeButton.setTypographyRole(TypographyTokens.Toolbar.control)
		scopeButton.trailingImage = GitReviewReferenceIcons.image(
			.chevronDown,
			size: 12
		)
		scopeButton.imagePosition = .noImage
		scopeButton.contentTintColor = AppKitColorTokens.primaryText
		scopeButton.presentation = .groupedDropdown
		let scope = AppKitLayout.horizontalStack(
			[scopeButton, diffStats],
			spacing: 2,
			alignment: .firstBaseline
		)
		return ViewerToolbarGroup(
			scope,
			presentation: .comparisonScope
		)
	}

	private func makeRevisionControls(
		target: AnyObject,
		actions: Actions
	) -> NSView
	{
		for field in [baseField, targetField]
		{
			field.target = target
			field.action = actions.revisions
			field.isBezeled = false
			field.drawsBackground = false
			field.setTypographyRole(TypographyTokens.Toolbar.control)
			field.cell?.usesSingleLineMode = true
			field.cell?.isScrollable = true
			field.lineBreakMode = .byTruncatingTail
			let constraint = field.widthAnchor
				.constraint(equalToConstant: Layout.minimumRevisionWidth)
			constraint.isActive = true
			if field === baseField
			{
				baseRevisionWidth = constraint
			}
			else
			{
				targetRevisionWidth = constraint
			}
			field.setContentCompressionResistancePriority(
				.defaultLow,
				for: .horizontal
			)
		}
		baseField.placeholderString = "Base revision"
		targetField.placeholderString = "Target revision"
		let arrow = NSTextField(labelWithString: "→")
		arrow.setTypographyRole(TypographyTokens.Toolbar.control)
		arrow.textColor = AppKitColorTokens.secondaryText
		arrow.setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
		arrow.setAccessibilityElement(false)
		let revisionMenu = referenceButton(
			"Revision options",
			image: GitReviewReferenceIcons.image(
				.chevronDown,
				size: 12
			),
			action: actions.revisionMenu
		)
		revisionMenuButton = revisionMenu
		branchTargetButton.target = target
		branchTargetButton.action = actions.branchMenu
		branchTargetButton.presentation = .groupedDropdown
		branchTargetButton.trailingImage = GitReviewReferenceIcons.image(
			.chevronDown,
			size: 12
		)
		branchTargetButton.lineBreakMode = .byTruncatingTail
		branchTargetButton.setContentCompressionResistancePriority(
			.defaultHigh,
			for: .horizontal
		)
		branchTargetButton.widthAnchor
			.constraint(lessThanOrEqualToConstant: Layout.maximumRevisionWidth)
			.isActive = true
		branchTargetButton.isHidden = true
		let revisionRow = AppKitLayout.horizontalStack(
			[baseField, arrow, targetField, revisionMenu, branchTargetButton],
			spacing: 2
		)
		// The target dropdown supplies its own leading text inset.
		revisionRow.setCustomSpacing(
			6,
			after: baseField
		)
		revisionRow.setCustomSpacing(
			0,
			after: arrow
		)
		let refs = ViewerToolbarGroup(
			revisionRow,
			presentation: .revisions
		)
		refs.setAccessibilityElement(true)
		refs.setAccessibilityLabel("Revision comparison")
		revisionComparison = refs
		updateRevisionWidths()
		return refs
	}

	func showBranchTarget(_ selected: Bool)
	{
		guard targetField.isHidden != selected
		else
		{
			return
		}
		baseField.isEditable = !selected
		baseField.isSelectable = true
		targetField.isHidden = selected
		revisionMenuButton?.isHidden = selected
		branchTargetButton.isHidden = !selected
	}

	func updateRevisionWidths()
	{
		let maximumWidth = usesCompactRevisions
			? Layout.compactMaximumRevisionWidth : Layout.maximumRevisionWidth
		for (field, constraint) in [
			(baseField, baseRevisionWidth),
			(targetField, targetRevisionWidth)
		]
		{
			guard let constraint, let cell = field.cell
			else
			{
				continue
			}
			let width = min(
				maximumWidth,
				max(
					Layout.minimumRevisionWidth,
					ceil(cell.cellSize.width)
				)
			)
			if constraint.constant != width
			{
				constraint.constant = width
			}
		}
	}

	private func makeComparisonActions(
		target: AnyObject,
		actions: Actions
	) -> NSView
	{
		optionsButton.title = ""
		optionsButton.image = GitReviewReferenceIcons.image(.ellipsis)
		optionsButton.target = target
		optionsButton.action = actions.displayMenu
		optionsButton.setAccessibilityLabel("Diff display options")
		optionsButton.toolTip = "Changes options"
		let search = referenceButton(
			"Jump to file",
			image: GitReviewReferenceIcons.image(.documentSearch),
			action: actions.fileJump
		)
		fileJumpButton = search
		let refresh = referenceButton(
			"Refresh comparison",
			image: GitReviewReferenceIcons.image(.refresh),
			action: actions.refresh
		)
		refresh.toolTip = "Refresh"
		refreshButton = refresh
		let boundary = referenceButton(
			"Wrap code lines",
			image: GitReviewReferenceIcons.image(.returnToBoundary),
			action: actions.wordWrap
		)
		boundary.toolTip = "Word wrap"
		wordWrapButton = boundary
		(boundary as? ViewerToolbarButton)?.showsSelection = true
		let collapse = referenceButton(
			"Collapse all diffs",
			image: GitReviewReferenceIcons.image(.collapse),
			action: actions.collapseAll
		)
		collapseDiffsButton = collapse
		let display = referenceButton(
			"Switch diff layout",
			image: GitReviewReferenceIcons.image(.displayMode),
			action: actions.diffLayout
		)
		diffLayoutButton = display
		let toggle = referenceButton(
			"Toggle changed-file navigator",
			image: DesktopIcons.image(.folders),
			action: actions.navigator
		)
		navigatorToggle = toggle
		(toggle as? ViewerToolbarButton)?.showsSelection = true
		let tools = ViewerToolbarGroup(
			AppKitLayout.horizontalStack(
				[optionsButton,
					search,
					refresh,
					boundary,
					collapse,
					display,
					toggle],
				spacing: 2
			),
			presentation: .tools
		)
		return tools
	}

	func updateLayout(for width: CGFloat) -> Bool?
	{
		guard width > 0
		else
		{
			return nil
		}
		let shouldUseCompactRevisions = width < Layout.compactRevisionThreshold
		let shouldUseCompactToolbar = width < Layout.compactToolbarThreshold
		let compactRevisionsChanged = shouldUseCompactRevisions != usesCompactRevisions
		usesCompactRevisions = shouldUseCompactRevisions
		updateRevisionWidths()
		guard compactRevisionsChanged
			|| shouldUseCompactToolbar != usesCompactLayout
		else
		{
			return nil
		}
		usesCompactLayout = shouldUseCompactToolbar
		for control in [refreshButton, wordWrapButton, collapseDiffsButton, diffLayoutButton]
		{
			control?.isHidden = shouldUseCompactToolbar
		}
		optionsButton.setAccessibilityLabel(
			shouldUseCompactToolbar ? "More comparison actions" : "Diff display options"
		)
		optionsButton.toolTip = "Changes options"
		return shouldUseCompactRevisions
	}

	private func referenceButton(
		_ title: String,
		image: NSImage,
		action: Selector?
	) -> NSButton
	{
		GitReviewControls.referenceButton(
			title,
			image: image,
			target: actionTarget,
			action: action
		)
	}

}
