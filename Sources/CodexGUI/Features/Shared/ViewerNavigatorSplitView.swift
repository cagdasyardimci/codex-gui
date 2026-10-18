import AppKit

/// Places a document beside a resizable navigator in either file viewer.
@MainActor
final class ViewerNavigatorSplitView: NSView
{
	private static let minimumNavigatorWidth: CGFloat = 120
	private static let maximumNavigatorWidth: CGFloat = 360
	private static let minimumDocumentWidth: CGFloat = 160
	private static let dividerHitWidth: CGFloat = 5
	private static let navigatorContentPriority = NSLayoutConstraint.Priority(249)

	let dividerView: NavigatorDividerView
	private let navigator: NSView
	private let widthConstraint: NSLayoutConstraint
	private let minimumWidthConstraint: NSLayoutConstraint
	private let collapsedWidthConstraint: NSLayoutConstraint
	private let dividerWidthConstraint: NSLayoutConstraint
	private let panGesture: NSPanGestureRecognizer
	private var transition: ViewerNavigatorTransition?
	private var requestedWidth: CGFloat = 241
	private var observedAncestors: [WeakNavigatorAncestor] = []

	var onNavigatorVisibilityChanged: ((Bool) -> Void)?
	private(set) var isNavigatorVisible = true

	var navigatorWidth: CGFloat
	{
		navigator.frame.width
	}

	var desiredNavigatorWidth: CGFloat
	{
		get
		{
			requestedWidth
		}
		set
		{
			requestedWidth = min(
				Self.maximumNavigatorWidth,
				max(
					Self.minimumNavigatorWidth,
					newValue
				)
			)
			if isNavigatorVisible, transition?.isAnimating != true
			{
				widthConstraint.constant = resolvedWidth
			}
		}
	}

	init(
		document: NSView,
		navigator: NSView,
		panGesture: NSPanGestureRecognizer = NSPanGestureRecognizer()
	)
	{
		self.navigator = navigator
		self.panGesture = panGesture
		let dividerView = NavigatorDividerView()
		self.dividerView = dividerView
		let width = navigator.widthAnchor.constraint(equalToConstant: 0)
		// Stay below AppKit's window-size priority (500) while outranking
		// compressible document labels (250).
		width.priority = NSLayoutConstraint.Priority(499)
		widthConstraint = width
		minimumWidthConstraint = navigator.widthAnchor.constraint(
			greaterThanOrEqualToConstant: Self.minimumNavigatorWidth
		)
		collapsedWidthConstraint = navigator.widthAnchor.constraint(equalToConstant: 0)
		dividerWidthConstraint = dividerView.widthAnchor.constraint(
			equalToConstant: Self.dividerHitWidth
		)
		super.init(frame: .zero)
		// The desired width yields when a hosting window shrinks. Keep the
		// navigator's intrinsic size just below it so room restores that width.
		navigator.setContentHuggingPriority(
			Self.navigatorContentPriority,
			for: .horizontal
		)
		navigator.setContentCompressionResistancePriority(
			Self.navigatorContentPriority,
			for: .horizontal
		)
		navigator.wantsLayer = true
		navigator.layer?.masksToBounds = true

		for child in [document, dividerView, navigator]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			addSubview(child)
		}
		NSLayoutConstraint.activate([
			document.leadingAnchor.constraint(equalTo: leadingAnchor),
			document.topAnchor.constraint(equalTo: topAnchor),
			document.bottomAnchor.constraint(equalTo: bottomAnchor),
			document.trailingAnchor.constraint(equalTo: dividerView.leadingAnchor),
			document.widthAnchor.constraint(
				greaterThanOrEqualToConstant: Self.minimumDocumentWidth
			),
			dividerWidthConstraint,
			dividerView.topAnchor.constraint(equalTo: topAnchor),
			dividerView.bottomAnchor.constraint(equalTo: bottomAnchor),
			dividerView.trailingAnchor.constraint(equalTo: navigator.leadingAnchor),
			navigator.topAnchor.constraint(equalTo: topAnchor),
			navigator.bottomAnchor.constraint(equalTo: bottomAnchor),
			navigator.trailingAnchor.constraint(equalTo: trailingAnchor),
			width,
			minimumWidthConstraint,
		])
		panGesture.target = self
		panGesture.action = #selector(dragDivider(_:))
		dividerView.addGestureRecognizer(panGesture)
		transition = ViewerNavigatorTransition(
			widthConstraint: width,
			layoutView: self,
			expandedWidth: requestedWidth
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	deinit
	{
		NotificationCenter.default.removeObserver(self)
	}

	override func viewDidMoveToSuperview()
	{
		super.viewDidMoveToSuperview()
		observeAncestorGeometry()
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		observeAncestorGeometry()
	}

	private func observeAncestorGeometry()
	{
		let center = NotificationCenter.default
		for reference in observedAncestors
		{
			guard let ancestor = reference.view
			else
			{
				continue
			}
			center.removeObserver(
				self,
				name: NSView.frameDidChangeNotification,
				object: ancestor
			)
			center.removeObserver(
				self,
				name: NSView.boundsDidChangeNotification,
				object: ancestor
			)
		}
		observedAncestors.removeAll()
		var ancestor = superview
		while let view = ancestor
		{
			observedAncestors.append(WeakNavigatorAncestor(view))
			ancestor = view.superview
		}
		for reference in observedAncestors
		{
			guard let ancestor = reference.view
			else
			{
				continue
			}
			ancestor.postsFrameChangedNotifications = true
			ancestor.postsBoundsChangedNotifications = true
			center.addObserver(
				self,
				selector: #selector(ancestorGeometryDidChange),
				name: NSView.frameDidChangeNotification,
				object: ancestor
			)
			center.addObserver(
				self,
				selector: #selector(ancestorGeometryDidChange),
				name: NSView.boundsDidChangeNotification,
				object: ancestor
			)
		}
		updateWidthForBounds()
	}

	@objc private func ancestorGeometryDidChange(_ notification: Notification)
	{
		updateWidthForBounds()
	}

	override func setFrameSize(_ newSize: NSSize)
	{
		super.setFrameSize(newSize)
		updateWidthForBounds()
	}

	override func layout()
	{
		updateWidthForBounds()
		super.layout()
	}

	private func updateWidthForBounds()
	{
		guard isNavigatorVisible, transition?.isAnimating != true
		else
		{
			return
		}
		let width = resolvedWidth
		minimumWidthConstraint.constant = min(
			Self.minimumNavigatorWidth,
			availableNavigatorRoom
		)
		minimumWidthConstraint.isActive = true
		if widthConstraint.constant != width
		{
			widthConstraint.constant = width
		}
	}

	func setNavigatorVisible(
		_ visible: Bool,
		animated: Bool = true
	)
	{
		guard isNavigatorVisible != visible
		else
		{
			return
		}
		isNavigatorVisible = visible
		if visible
		{
			collapsedWidthConstraint.isActive = false
			widthConstraint.isActive = true
			navigator.isHidden = false
			dividerView.isHidden = false
			dividerWidthConstraint.constant = Self.dividerHitWidth
		}
		else
		{
			minimumWidthConstraint.isActive = false
		}
		transition?.setVisible(
			visible,
			expandedWidth: resolvedWidth,
			animated: animated && window?.isVisible == true
		)
		{
			[weak self] in
			guard let self, self.isNavigatorVisible == visible
			else
			{
				return
			}
			if !visible
			{
				self.widthConstraint.isActive = false
				self.collapsedWidthConstraint.isActive = true
				self.navigator.isHidden = true
				self.dividerView.isHidden = true
				self.dividerWidthConstraint.constant = 0
				self.layoutSubtreeIfNeeded()
			}
			else
			{
				self.minimumWidthConstraint.constant = min(
					Self.minimumNavigatorWidth,
					self.availableNavigatorRoom
				)
				self.minimumWidthConstraint.isActive = true
				self.updateWidthForBounds()
			}
		}
		onNavigatorVisibilityChanged?(visible)
	}

	private var resolvedWidth: CGFloat
	{
		min(
			requestedWidth,
			availableNavigatorRoom
		)
	}

	private var availableNavigatorRoom: CGFloat
	{
		var availableWidth = bounds.width
		var ancestor = superview
		while let view = ancestor
		{
			if view.bounds.width > 0
			{
				availableWidth = min(
					availableWidth,
					view.bounds.width
				)
			}
			ancestor = view.superview
		}
		return max(
			0,
			availableWidth - Self.minimumDocumentWidth
				- Self.dividerHitWidth
		)
	}

	@objc private func dragDivider(_ gesture: NSPanGestureRecognizer)
	{
		guard isNavigatorVisible
		else
		{
			return
		}
		let translation = gesture.translation(in: self)
		let requested = navigator.frame.width - translation.x
		requestedWidth = min(
			Self.maximumNavigatorWidth,
			max(
				Self.minimumNavigatorWidth,
				requested
			)
		)
		transition?.cancel()
		updateWidthForBounds()
		gesture.setTranslation(
			.zero,
			in: self
		)
	}
}

@MainActor
private final class WeakNavigatorAncestor
{
	weak var view: NSView?

	init(_ view: NSView)
	{
		self.view = view
	}
}

@MainActor
final class NavigatorDividerView: NSView
{
	private let line = DesktopSurface(AppKitColorTokens.border)

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		setAccessibilityLabel("Resize file navigator")
		line.translatesAutoresizingMaskIntoConstraints = false
		addSubview(line)
		NSLayoutConstraint.activate([
			line.centerXAnchor.constraint(equalTo: centerXAnchor),
			line.topAnchor.constraint(equalTo: topAnchor),
			line.bottomAnchor.constraint(equalTo: bottomAnchor),
			line.widthAnchor.constraint(equalToConstant: 1),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func resetCursorRects()
	{
		super.resetCursorRects()
		addCursorRect(
			bounds,
			cursor: .resizeLeftRight
		)
	}
}
