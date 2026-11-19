import AppKit

/// Keeps the account column visible independently of the collapsible workspace panes.
@MainActor
final class WindowChromeViewController: NSViewController
{
	private typealias Layout = LayoutTokens.Chrome

	private var accountColumn: NSView!
	private var panel: RoundedContentPanel!
	private var panelShadow: RoundedContentShadow!
	private var accountWidth: NSLayoutConstraint!
	private var trailingInset: NSLayoutConstraint!
	private var bottomInset: NSLayoutConstraint!
	private var topInset: NSLayoutConstraint!
	private var splitInset: NSLayoutConstraint!
	private weak var workspaceView: NSView?
	private var settings: SettingsViewController?
	private var workspaceWasAccessibilityHidden = false
	private var workspaceWasHidden = false
	private let fullscreenToolbarHost = NSView()
	private let toolsHeaderHost = NSView()
	private weak var toolsHeader: ToolsTabHeader?

	func alignWorkspaceBelowTitleBar(in window: NSWindow)
	{
		guard let guide = window.contentLayoutGuide as? NSLayoutGuide
		else
		{
			return
		}
		topInset.isActive = false
		topInset = panel.topAnchor.constraint(
			equalTo: guide.topAnchor,
			constant: Layout.panelTopInset
		)
		topInset.isActive = true
	}

	func setToolsTabHeader(
		_ tabs: ToolsTabViewController?,
		alignedTo viewport: NSView,
		after toolbarEdge: CGFloat,
		fullscreenControls: ToolsToolbarCoordinator.FullscreenControls?,
		navigationEdge: CGFloat
	)
	{
		guard let tabs, let window = view.window, viewport.window === window,
				settings == nil, !panel.isGitReviewFocused
		else
		{
			hideToolsTabHeader()
			return
		}
		let viewportBounds = view.convert(
			viewport.bounds,
			from: viewport
		)
		let isFullScreen = window.styleMask.contains(.fullScreen)
		let nativeLeading = view.convert(
			NSPoint(
				x: toolbarEdge,
				y: 0
			),
			from: nil
		).x
		let fullscreenLeading = view.safeAreaRect.minX + fullscreenControlWidth(fullscreenControls)
		let leading = max(
			viewportBounds.minX,
			isFullScreen ? fullscreenLeading : nativeLeading
		)
		let width = max(
			0,
			min(
				isFullScreen ? view.safeAreaRect.maxX : view.bounds.maxX,
				viewportBounds.maxX
			) - leading
		)
		let contentTop = view.convert(
			window.contentLayoutRect,
			from: nil
		).maxY
		let nativeHeight = max(
			0,
			view.bounds.maxY - contentTop
		)
		let headerHeight = LayoutTokens.Tabs.headerHeight
		// The fullscreen system chrome can cover the area above the safe content.
		let bandTop = isFullScreen ? min(
			contentTop,
			view.safeAreaRect.maxY
		) : view.bounds.maxY
		let bandHeight = !isFullScreen && nativeHeight >= LayoutTokens.Tabs.tabHeight + 2
			? nativeHeight : headerHeight
		let bandBottom = bandTop - bandHeight
		let inset = Layout.panelTopInset + max(
			0,
			contentTop - bandBottom
		)
		if topInset.constant != inset
		{
			topInset.constant = inset
		}
		layoutFullscreenControls(
			fullscreenControls,
			in: NSRect(
				x: view.safeAreaRect.minX,
				y: bandBottom,
				width: max(
					0,
					leading - view.safeAreaRect.minX
				),
				height: bandHeight
			),
			navigationEdge: view.convert(
				NSPoint(
					x: navigationEdge,
					y: 0
				),
				from: nil
			).x
		)
		let header = tabs.tabBarView
		if toolsHeader !== header
		{
			toolsHeader?.removeFromSuperview()
			toolsHeader = header
			toolsHeaderHost.addSubview(header)
		}
		let hostFrame = NSRect(
			x: leading,
			y: bandBottom,
			width: width,
			height: bandHeight
		)
		if toolsHeaderHost.frame != hostFrame
		{
			toolsHeaderHost.frame = hostFrame
		}
		let headerFrame = NSRect(
			x: 0,
			y: (bandHeight - headerHeight) / 2,
			width: max(
				width,
				tabs.minimumTabBarWidth
			),
			height: headerHeight
		)
		if header.frame != headerFrame
		{
			header.frame = headerFrame
		}
		toolsHeaderHost.isHidden = width == 0
	}

	private func hideToolsTabHeader()
	{
		fullscreenToolbarHost.subviews.forEach
		{
			$0.removeFromSuperview()
		}
		fullscreenToolbarHost.isHidden = true
		toolsHeader?.removeFromSuperview()
		toolsHeader = nil
		toolsHeaderHost.isHidden = true
		let inset = panel.isGitReviewFocused ? 0 : Layout.panelTopInset
		if topInset.constant != inset
		{
			topInset.constant = inset
		}
	}

	private func fullscreenControlWidth(
		_ controls: ToolsToolbarCoordinator.FullscreenControls?
	) -> CGFloat
	{
		guard let controls
		else
		{
			return 0
		}
		let navigation = controls.navigation?.fittingSize.width ?? 0
		let actions = controls.actions?.fittingSize.width ?? 0
		return navigation + actions + 3 * LayoutTokens.Toolbar.controlSpacing
	}

	private func layoutFullscreenControls(
		_ controls: ToolsToolbarCoordinator.FullscreenControls?,
		in frame: NSRect,
		navigationEdge: CGFloat
	)
	{
		guard let controls
		else
		{
			fullscreenToolbarHost.subviews.forEach
			{
				$0.removeFromSuperview()
			}
			fullscreenToolbarHost.isHidden = true
			return
		}
		fullscreenToolbarHost.isHidden = false
		if fullscreenToolbarHost.frame != frame
		{
			fullscreenToolbarHost.frame = frame
		}
		let spacing = LayoutTokens.Toolbar.controlSpacing
		let navigationWidth = controls.navigation?.fittingSize.width ?? 0
		let actionsWidth = controls.actions?.fittingSize.width ?? 0
		let actionsStart = max(
			spacing,
			frame.width - spacing - actionsWidth
		)
		let titleStart = max(
			navigationWidth + 2 * spacing,
			navigationEdge - frame.minX + spacing
		)
		let titleWidth = min(
			controls.title?.fittingSize.width ?? 0,
			actionsStart - spacing - titleStart
		)
		placeFullscreenControl(
			controls.navigation,
			x: spacing,
			width: navigationWidth,
			rowHeight: frame.height
		)
		placeFullscreenControl(
			controls.title,
			x: titleStart,
			width: titleWidth,
			rowHeight: frame.height
		)
		placeFullscreenControl(
			controls.actions,
			x: actionsStart,
			width: actionsWidth,
			rowHeight: frame.height
		)
	}

	private func placeFullscreenControl(
		_ control: NSView?,
		x: CGFloat,
		width: CGFloat,
		rowHeight: CGFloat
	)
	{
		guard let control
		else
		{
			return
		}
		guard width >= LayoutTokens.Toolbar.controlSize
		else
		{
			if control.superview === fullscreenToolbarHost
			{
				control.removeFromSuperview()
			}
			return
		}
		if control.superview !== fullscreenToolbarHost
		{
			control.translatesAutoresizingMaskIntoConstraints = true
			control.autoresizingMask = []
			fullscreenToolbarHost.addSubview(control)
		}
		let height = LayoutTokens.Toolbar.rowHeight
		let frame = NSRect(
			x: x,
			y: (rowHeight - height) / 2,
			width: width,
			height: height
		)
		if control.frame != frame
		{
			control.frame = frame
		}
	}

	func showSettings(_ settings: SettingsViewController)
	{
		guard self.settings == nil, let workspaceView
		else
		{
			return
		}
		self.settings = settings
		hideToolsTabHeader()
		workspaceWasHidden = workspaceView.isHidden
		workspaceWasAccessibilityHidden = workspaceView.isAccessibilityHidden()
		workspaceView.isHidden = true
		workspaceView.setAccessibilityHidden(true)
		addChild(settings)
		AppKitLayout.pin(
			settings.view,
			to: panel,
			inset: 0
		)
	}

	func hideSettings()
	{
		guard let settings
		else
		{
			return
		}
		settings.endPresentation()
		settings.view.removeFromSuperview()
		settings.removeFromParent()
		self.settings = nil
		workspaceView?.isHidden = workspaceWasHidden
		workspaceView?.setAccessibilityHidden(workspaceWasAccessibilityHidden)
	}

	func setGitReviewFocused(_ focused: Bool)
	{
		accountColumn.isHidden = focused
		accountWidth.constant = focused ? 0 : Layout.accountColumnWidth
		trailingInset.constant = focused ? 0 : -Layout.panelOuterInset
		bottomInset.constant = focused ? 0 : -Layout.panelOuterInset
		topInset.constant = focused ? 0 : Layout.panelTopInset
		splitInset.constant = focused ? 0 : Layout.splitLeadingInset
		panel.isGitReviewFocused = focused
		panelShadow.isHidden = focused
		if focused
		{
			hideToolsTabHeader()
		}
		view.needsLayout = true
	}

	init(
		split: NSSplitViewController,
		accountButton: NSButton
	)
	{
		super.init(
			nibName: nil,
			bundle: nil
		)
		view = DesktopSurface(AppKitColorTokens.chrome)
		addChild(split)
		workspaceView = split.view

		let column = DesktopSurface(AppKitColorTokens.chrome)
		let avatar = DesktopSurface(
			AppKitColorTokens.accountAvatar,
			cornerRadius: Layout.avatarSize / 2
		)
		let panel = RoundedContentPanel()
		let shadow = RoundedContentShadow()
		self.accountColumn = column
		self.panel = panel
		self.panelShadow = shadow
		accountWidth = column.widthAnchor.constraint(equalToConstant: Layout.accountColumnWidth)
		trailingInset = panel.trailingAnchor.constraint(
			equalTo: view.trailingAnchor,
			constant: -Layout.panelOuterInset
		)
		bottomInset = panel.bottomAnchor.constraint(
			equalTo: view.bottomAnchor,
			constant: -Layout.panelOuterInset
		)
		topInset = panel.topAnchor.constraint(
			equalTo: view.topAnchor,
			constant: Layout.panelTopInset
		)
		splitInset = split.view.leadingAnchor.constraint(
			equalTo: panel.leadingAnchor,
			constant: Layout.splitLeadingInset
		)
		for child in [column, shadow, panel]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			view.addSubview(child)
		}
		fullscreenToolbarHost.clipsToBounds = true
		fullscreenToolbarHost.isHidden = true
		view.addSubview(fullscreenToolbarHost)
		toolsHeaderHost.clipsToBounds = true
		toolsHeaderHost.isHidden = true
		view.addSubview(toolsHeaderHost)
		split.view.translatesAutoresizingMaskIntoConstraints = false
		panel.addSubview(split.view)
		avatar.translatesAutoresizingMaskIntoConstraints = false
		accountButton.translatesAutoresizingMaskIntoConstraints = false
		column.addSubview(avatar)
		column.addSubview(accountButton)

		NSLayoutConstraint.activate([
			column.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			column.topAnchor.constraint(equalTo: view.topAnchor),
			column.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			accountWidth,
			avatar.centerXAnchor.constraint(equalTo: column.centerXAnchor),
			accountButton.bottomAnchor.constraint(
				equalTo: column.bottomAnchor,
				constant: -Layout.accountBottomInset
			),
			avatar.widthAnchor.constraint(equalToConstant: Layout.avatarSize),
			avatar.heightAnchor.constraint(equalToConstant: Layout.avatarSize),
			accountButton.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
			accountButton.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
			panel.leadingAnchor.constraint(equalTo: column.trailingAnchor),
			trailingInset,
			topInset,
			bottomInset,
			shadow.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
			shadow.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
			shadow.topAnchor.constraint(equalTo: panel.topAnchor),
			shadow.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
			splitInset,
			split.view.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
			split.view.topAnchor.constraint(equalTo: panel.topAnchor),
			split.view.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}

@MainActor
private final class RoundedContentShadow: NSView
{
	private let cornerRadius = ShapeTokens.NativeChrome.panelRadius

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.cornerCurve = .circular
		layer?.shadowColor = ShadowTokens.windowChrome.color.cgColor
		layer?.shadowOffset = .zero
		layer?.shadowRadius = 8
		updateAppearance()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func layout()
	{
		super.layout()
		let radius = min(
			cornerRadius,
			bounds.height / 2,
			bounds.width
		)
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		layer?.cornerRadius = radius
		layer?.shadowPath = CGPath(
			roundedRect: bounds,
			cornerWidth: radius,
			cornerHeight: radius,
			transform: nil
		)
		CATransaction.commit()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		updateAppearance()
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		updateAppearance()
	}

	private func updateAppearance()
	{
		let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		layer?.backgroundColor = AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.chrome,
			for: self
		)
		layer?.shadowOpacity = isDark ? 0 : 0.08
	}
}

/// Clips workspace content and draws its rounded border inside the window chrome.
@MainActor
private final class RoundedContentPanel: NSView
{
	// Match the reference content panel independently of the native window corner.
	private let cornerRadius = ShapeTokens.NativeChrome.panelRadius
	var isGitReviewFocused = false
	{
		didSet
		{
			needsLayout = true
		}
	}

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.cornerRadius = cornerRadius
		layer?.cornerCurve = .circular
		layer?.borderWidth = 0.5
		layer?.masksToBounds = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func layout()
	{
		super.layout()
		let radius = min(
			cornerRadius,
			bounds.height / 2,
			bounds.width
		)
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		layer?.cornerRadius = isGitReviewFocused ? 0 : radius
		layer?.borderWidth = isGitReviewFocused ? 0 : 0.5
		layer?.borderColor = AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.border,
			for: self
		)
		CATransaction.commit()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsLayout = true
	}
}
