import AppKit

@MainActor
final class FileBreadcrumbView: NSView
{
	var onNavigate: ((FileLocation) -> Void)?
	var onOpenFile: ((FileLocation) -> Void)?
	var onRequestDirectory: ((FileLocation) -> Void)?

	private let scroll = NSScrollView()
	private lazy var capsule = ViewerToolbarGroup(
		scroll,
		presentation: .actions
	)
	private let pathContent = NSView()
	private let stack = NSStackView()
	private var state = FileViewerState()
	private var location: FileLocation?
	private var pendingMenu: (parent: FileLocation, child: FileLocation, generation: Int)?
	private var menuGeneration = -1
	private var viewportWidth: CGFloat = 0
	private var revealLastSegment = true
	private var colorObservation: ThemeColorObservation?

	override init(frame frameRect: NSRect = .zero)
	{
		super.init(frame: frameRect)
		colorObservation = ThemeColorObservation
		{
			[weak self] in self?.refreshSegmentColors()
		}
		stack.orientation = .horizontal
		stack.alignment = .centerY
		stack.distribution = .fill
		stack.spacing = 6
		stack.translatesAutoresizingMaskIntoConstraints = false
		pathContent.addSubview(stack)
		// Rebuilding can temporarily require more space than the old document frame.
		let preferredWidth = stack.widthAnchor.constraint(equalTo: pathContent.widthAnchor)
		preferredWidth.priority = NSLayoutConstraint.Priority(999)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: pathContent.leadingAnchor),
			stack.topAnchor.constraint(equalTo: pathContent.topAnchor),
			stack.heightAnchor.constraint(equalToConstant: ViewerToolbarGroup.Geometry.controlSize),
			preferredWidth,
		])
		scroll.documentView = pathContent
		scroll.wantsLayer = true
		scroll.layer?.masksToBounds = true
		scroll.hasHorizontalScroller = false
		scroll.hasVerticalScroller = false
		scroll.drawsBackground = false
		scroll.horizontalScrollElasticity = .allowed
		AppKitLayout.pin(
			capsule,
			to: self,
			inset: 0
		)
		setAccessibilityLabel("File path")
		rebuild()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshSegmentColors()
	}

	private func refreshSegmentColors()
	{
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			let buttons = stack.arrangedSubviews.compactMap
			{
				$0 as? DesktopAttributedTitleButton
			}
			for (index, button) in buttons.enumerated()
			{
				let title = NSMutableAttributedString(attributedString: button.attributedTitle)
				title.addAttribute(
					.foregroundColor,
					value: index == buttons.count - 1 ? AppKitColorTokens
						.primaryText : AppKitColorTokens.secondaryText,
					range: NSRange(
						location: 0,
						length: title.length
					)
				)
				button.attributedTitle = title
			}
			if let root = stack.arrangedSubviews.first as? NSTextField
			{
				root.textColor = AppKitColorTokens.primaryText
			}
		}
	}

	override func layout()
	{
		super.layout()
		// Resolve the capsule and segments before measuring the retained scroll document.
		capsule.layoutSubtreeIfNeeded()
		stack.layoutSubtreeIfNeeded()
		let segmentWidth = stack.arrangedSubviews.reduce(
			stack.edgeInsets.left + stack.edgeInsets.right
		)
		{
			$0 + $1.fittingSize.width
		} + CGFloat(max(
			0,
			stack.arrangedSubviews.count - 1
		)) * stack.spacing
		pathContent.frame = NSRect(
			x: 0,
			y: 0,
			width: max(
				segmentWidth,
				stack.fittingSize.width,
				scroll.contentSize.width
			),
			height: scroll.contentSize.height
		)
		stack.layoutSubtreeIfNeeded()
		// AppKit may update a rebuilt stack's fitting width after its first sizing pass.
		for _ in 0 ..< 3 where stack.fittingSize.width > pathContent.frame.width
		{
			pathContent.frame.size.width = stack.fittingSize.width
			stack.layoutSubtreeIfNeeded()
		}
		let maximumX = max(
			0,
			pathContent.bounds.width - scroll.contentSize.width
		)
		let x = !revealLastSegment && viewportWidth == scroll.contentSize.width
			? min(
				maximumX,
				max(
					0,
					scroll.contentView.bounds.minX
				)
			) : maximumX
		viewportWidth = scroll.contentSize.width
		revealLastSegment = false
		scroll.contentView.scroll(to: NSPoint(
			x: x,
			y: 0
		))
		scroll.reflectScrolledClipView(scroll.contentView)
	}

	override var intrinsicContentSize: NSSize
	{
		NSSize(
			width: max(
				ViewerToolbarGroup.Geometry.actionHeight,
				stack.fittingSize.width + ViewerToolbarGroup.Geometry.actionInset * 2
			),
			height: ViewerToolbarGroup.Geometry.actionHeight
		)
	}

	required init?(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}

	func render(
		location: FileLocation?,
		state: FileViewerState
	)
	{
		let changed = self.location != location || self.state.activeRoot != state.activeRoot
		self.location = location
		self.state = state
		if changed
		{
			pendingMenu = nil
			rebuild()
		}
		if let pending = pendingMenu,
			pending.generation == state.generation,
			state.directoryEntries[pending.parent] != nil
		{
			pendingMenu = nil
			showSiblingMenu(
				for: pending.child,
				in: pending.parent
			)
		}
		else if let pending = pendingMenu,
				state.directoryFailures[pending.parent] != nil || pending.generation != state
				.generation
		{
			pendingMenu = nil
		}
	}

	private func rebuild()
	{
		stack.edgeInsets = location == nil ? NSEdgeInsetsZero : NSEdgeInsets(
			top: 0,
			left: 8,
			bottom: 0,
			right: 4
		)
		defer
		{
			revealLastSegment = true
			invalidateIntrinsicContentSize()
			needsLayout = true
		}
		for item in stack.arrangedSubviews
		{
			stack.removeArrangedSubview(item)
			item.removeFromSuperview()
		}
		guard let location
		else
		{
			let label = NSTextField(labelWithString: "/")
			label.alignment = .center
			label.setTypographyRole(TypographyTokens.Files.location)
			label.textColor = AppKitColorTokens.primaryText
			label.setAccessibilityLabel("Workspace root")
			stack.addArrangedSubview(label)
			return
		}
		let names = location.relativePath.split(separator: "/").map(String.init)
		let rootName = URL(fileURLWithPath: location.root).lastPathComponent
		var parts = [""]
		for name in names
		{
			let next = parts.last!.isEmpty ? name : parts.last! + "/" + name
			parts.append(next)
		}
		for (index, path) in parts.enumerated()
		{
			if index > 0
			{
				let siblings = NSButton(
					title: "",
					target: self,
					action: #selector(activateSiblingMenu(_:))
				)
				siblings.isBordered = false
				siblings.image = FileViewerIcons.image(.chevronRight)
				siblings.contentTintColor = AppKitColorTokens.mutedText
				siblings.tag = index - 1
				siblings.setAccessibilityLabel("Browse siblings of "
					+ (index == 1 ? rootName : names[index - 2]))
				stack.addArrangedSubview(siblings)
			}
			let button = DesktopAttributedTitleButton(
				title: index == 0 ? rootName : names[index - 1],
				target: self,
				action: #selector(activateSegment(_:))
			)
			button.isBordered = false
			button
				.setTypographyRole(TypographyTokens.Files.breadcrumb(current: index == names.count))
			button.attributedTitle = NSAttributedString(
				string: button.title,
				attributes: [
					.font: button.font ?? AppKitFontResolver
						.font(TypographyTokens.Files.breadcrumb(current: false)),
					.foregroundColor: index == names.count
						? AppKitColorTokens.primaryText : AppKitColorTokens.secondaryText,
				]
			)
			button.tag = index
			button.toolTip = FileLocation(
				root: location.root,
				relativePath: path
			).fileURL.path
			button.setAccessibilityLabel(button.toolTip ?? button.title)
			button.setContentCompressionResistancePriority(
				.defaultLow,
				for: .horizontal
			)
			stack.addArrangedSubview(button)

		}
	}

	@objc private func activateSegment(_ sender: NSButton)
	{
		guard let location
		else
		{
			return
		}
		let names = location.relativePath.split(separator: "/").map(String.init)
		let relativePath = names.prefix(sender.tag).joined(separator: "/")
		let selected = FileLocation(
			root: location.root,
			relativePath: relativePath
		)
		if sender.tag == names.count, !names.isEmpty
		{
			onOpenFile?(selected)
		}
		else
		{
			onNavigate?(selected)
		}
	}

	@objc private func activateSiblingMenu(_ sender: NSButton)
	{
		guard let location
		else
		{
			return
		}
		let names = location.relativePath.split(separator: "/").map(String.init)
		let path = names.prefix(sender.tag).joined(separator: "/")
		showOrRequestSiblings(for: FileLocation(
			root: location.root,
			relativePath: path
		))
	}

	private func showOrRequestSiblings(for child: FileLocation)
	{
		let parentPath = child.relativePath.split(separator: "/").dropLast().joined(separator: "/")
		let parent = FileLocation(
			root: child.root,
			relativePath: parentPath
		)
		if state.directoryEntries[parent] != nil
		{
			showSiblingMenu(
				for: child,
				in: parent
			)
		}
		else
		{
			pendingMenu = (parent, child, state.generation)
			if state.directoryRequests[parent] == nil
			{
				onRequestDirectory?(parent)
			}
		}
	}

	private func showSiblingMenu(
		for child: FileLocation,
		in parent: FileLocation
	)
	{
		guard let entries = state.directoryEntries[parent], window != nil
		else
		{
			return
		}
		let menu = NSMenu()
		menuGeneration = state.generation
		for entry in entries
		{
			let item = NSMenuItem(
				title: entry.name,
				action: #selector(navigateSibling(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.representedObject = entry
			item.state = entry.location == child ? .on : .off
			menu.addItem(item)
		}
		if menu.items.isEmpty
		{
			let item = NSMenuItem(
				title: "Empty folder",
				action: nil,
				keyEquivalent: ""
			)
			menu.addItem(item)
		}
		let anchor = stack.arrangedSubviews.compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.toolTip == child.fileURL.path
		} ?? stack.arrangedSubviews.last
		if let anchor
		{
			menu.popUp(
				positioning: nil,
				at: NSPoint(
					x: 0,
					y: anchor.bounds.minY
				),
				in: anchor
			)
		}
	}

	@objc private func navigateSibling(_ sender: NSMenuItem)
	{
		guard let entry = sender.representedObject as? FileViewerDirectoryEntry,
				entry.location.root == state.activeRoot,
				menuGeneration == state.generation
		else
		{
			return
		}
		if entry.isDirectory, !entry.isSymbolicLink
		{
			onNavigate?(entry.location)
		}
		else
		{
			onOpenFile?(entry.location)
		}
	}
}
