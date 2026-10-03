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
		let displayMenu: Selector
		let fileJump: Selector
		let refresh: Selector
		let wordWrap: Selector
		let collapseAll: Selector
		let diffLayout: Selector
		let navigator: Selector
	}

	let scopeButton = NSButton(
		title: "Uncommitted ▾",
		target: nil,
		action: nil
	)
	let optionsButton = NSButton(
		title: "Display ▾",
		target: nil,
		action: nil
	)
	let baseField = NSTextField(string: "HEAD^")
	let targetField = NSTextField(string: "HEAD")
	let additionsLabel = NSTextField(labelWithString: "+0")
	let deletionsLabel = NSTextField(labelWithString: "-0")
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
		static let baseRevisionWidth: CGFloat = 190
		static let targetRevisionWidth: CGFloat = 130
		static let compactBaseRevisionWidth: CGFloat = 140
		static let compactTargetRevisionWidth: CGFloat = 100
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
		scopeButton.font = .systemFont(ofSize: 14)
		scopeButton.image = GitReviewReferenceIcons.image(
			.chevronDown,
			size: 12
		)
		scopeButton.imagePosition = .imageTrailing
		additionsLabel.textColor = .systemGreen
		deletionsLabel.textColor = .systemRed
		for count in [additionsLabel, deletionsLabel]
		{
			count.font = .systemFont(ofSize: 14)
		}
		let scope = pill(AppKitLayout.horizontalStack(
			[scopeButton, additionsLabel, deletionsLabel],
			spacing: 6
		))
		return scope
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
			field.font = .systemFont(ofSize: 14)
			let width = field === baseField
				? Layout.baseRevisionWidth : Layout.targetRevisionWidth
			let constraint = field.widthAnchor.constraint(equalToConstant: width)
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
		let arrow = NSImageView(image: DesktopIcons.image(.arrowRight))
		arrow.contentTintColor = .secondaryLabelColor
		arrow.setAccessibilityElement(false)
		let revisionMenu = referenceButton(
			"Revision options",
			image: GitReviewReferenceIcons.image(
				.chevronDown,
				size: 12
			),
			action: actions.revisionMenu
		)
		let refs = pill(AppKitLayout.horizontalStack(
			[baseField, arrow, targetField, revisionMenu],
			spacing: 8
		))
		refs.setAccessibilityElement(true)
		refs.setAccessibilityLabel("Revision comparison")
		revisionComparison = refs
		return refs
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
		GitReviewControls.styleReferenceButton(optionsButton)
		optionsButton.setAccessibilityLabel("Diff display options")
		optionsButton.toolTip = "Diff display options and reported turn changes"
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
		refreshButton = refresh
		let boundary = referenceButton(
			"Wrap code lines",
			image: GitReviewReferenceIcons.image(.returnToBoundary),
			action: actions.wordWrap
		)
		wordWrapButton = boundary
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
		let tools = pill(
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
			horizontalInset: 6,
			verticalInset: 2.5
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
		guard shouldUseCompactRevisions != usesCompactRevisions
			|| shouldUseCompactToolbar != usesCompactLayout
		else
		{
			return nil
		}
		usesCompactRevisions = shouldUseCompactRevisions
		usesCompactLayout = shouldUseCompactToolbar
		for control in [refreshButton, wordWrapButton, collapseDiffsButton, diffLayoutButton]
		{
			control?.isHidden = shouldUseCompactToolbar
		}
		optionsButton.setAccessibilityLabel(
			shouldUseCompactToolbar ? "More comparison actions" : "Diff display options"
		)
		optionsButton.toolTip = shouldUseCompactToolbar
			? "More display and comparison actions"
			: "Diff display options and reported turn changes"
		baseRevisionWidth?.constant = shouldUseCompactRevisions
			? Layout.compactBaseRevisionWidth : Layout.baseRevisionWidth
		targetRevisionWidth?.constant = shouldUseCompactRevisions
			? Layout.compactTargetRevisionWidth : Layout.targetRevisionWidth
		return shouldUseCompactRevisions
	}

	private func pill(
		_ content: NSView,
		radius: CGFloat = 20,
		horizontalInset: CGFloat = 10,
		verticalInset: CGFloat = 10
	) -> NSView
	{
		let surface = DesktopSurface(
			DesktopTheme.elevated,
			cornerRadius: radius
		)
		surface.addSubview(content)
		content.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			content.leadingAnchor.constraint(
				equalTo: surface.leadingAnchor,
				constant: horizontalInset
			),
			content.trailingAnchor.constraint(
				equalTo: surface.trailingAnchor,
				constant: -horizontalInset
			),
			content.topAnchor.constraint(
				equalTo: surface.topAnchor,
				constant: verticalInset
			),
			content.bottomAnchor.constraint(
				equalTo: surface.bottomAnchor,
				constant: -verticalInset
			),
		])
		return surface
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
