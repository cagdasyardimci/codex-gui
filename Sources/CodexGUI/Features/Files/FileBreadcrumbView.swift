import AppKit

@MainActor
final class FileBreadcrumbView: DesktopSurface
{
	private enum Geometry
	{
		static let height: CGFloat = 34
	}

	var onNavigate: ((FileLocation) -> Void)?
	var onOpenFile: ((FileLocation) -> Void)?
	var onRequestDirectory: ((FileLocation) -> Void)?

	private let scroll = NSScrollView()
	private let pathContent = NSView()
	private let stack = NSStackView()
	private var state = FileViewerState()
	private var location: FileLocation?
	private var pendingMenu: (parent: FileLocation, child: FileLocation, generation: Int)?
	private var menuGeneration = -1
	private var viewportWidth: CGFloat = 0
	private var revealLastSegment = true

	init(frame frameRect: NSRect = .zero)
	{
		super.init(
			AppKitColorTokens.canvas,
			cornerRadius: Geometry.height / 2,
			bordered: true,
			borderColor: AppKitColorTokens.subtleEdge,
			shadows: [ShadowTokens.fileViewerControl]
		)
		frame = frameRect
		stack.orientation = .horizontal
		stack.alignment = .centerY
		stack.distribution = .fill
		stack.spacing = 6
		// The manually sized stack must fit its edge insets before its first layout.
		stack.frame = NSRect(
			x: 0,
			y: 0,
			width: 20,
			height: Geometry.height
		)
		stack.edgeInsets = NSEdgeInsets(
			top: 0,
			left: 10,
			bottom: 0,
			right: 10
		)
		pathContent.addSubview(stack)
		scroll.documentView = pathContent
		scroll.wantsLayer = true
		scroll.layer?.masksToBounds = true
		scroll.hasHorizontalScroller = false
		scroll.hasVerticalScroller = false
		scroll.drawsBackground = false
		scroll.horizontalScrollElasticity = .allowed
		scroll.translatesAutoresizingMaskIntoConstraints = false
		addSubview(scroll)
		NSLayoutConstraint.activate([
			scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
			scroll.topAnchor.constraint(equalTo: topAnchor),
			scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
		setAccessibilityLabel("File path")
		rebuild()
	}

	override func layout()
	{
		super.layout()
		pathContent.frame = NSRect(
			x: 0,
			y: 0,
			width: max(
				stack.fittingSize.width,
				scroll.contentSize.width
			),
			height: scroll.contentSize.height
		)
		stack.frame = pathContent.bounds
		stack.layoutSubtreeIfNeeded()
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
				Geometry.height,
				stack.fittingSize.width
			),
			height: Geometry.height
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
			label.font = .systemFont(ofSize: 15)
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
				siblings.contentTintColor = .tertiaryLabelColor
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
			button.font = .systemFont(
				ofSize: 13,
				weight: index == names.count ? .medium : .regular
			)
			button.attributedTitle = NSAttributedString(
				string: button.title,
				attributes: [
					.font: button.font ?? NSFont.systemFont(ofSize: 13),
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
