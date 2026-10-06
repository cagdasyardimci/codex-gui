import AppKit
import QuartzCore

/// Compact turn marks beside the transcript, with an interactive hover preview.
@MainActor
final class TurnNavigationRail: NSView, DesktopWheelInputReceiving
{
	private struct TurnLocation
	{
		let summaryIndex: Int
		var markIndex: Int
	}

	private static let markHeight: CGFloat = 10
	private static let maximumHeight: CGFloat = 62 * markHeight
	private static let edgeFadeHeight: CGFloat = 40
	var onLoadTurnPreview: ((String) -> Void)?
	private var hoverLoadTask: Task<Void, Never>?
	var onJump: ((ConversationTurnSummary) -> Void)?
	var onLoadEarlierReferences: (() -> Void)?
	var canLoadEarlierReferences = false
	{
		didSet
		{
			if oldValue != canLoadEarlierReferences
			{
				historyRequestPending = false
			}
			updateEdgeFade()
		}
	}
	private var historyRequestPending = false
	var onBookmark: ((ConversationTurnSummary) -> Void)?
	var isBookmarked: ((ConversationTurnSummary) -> Bool)?
	// Reports the rail's writes independently of AppKit's inherited dirty flags.
	var onMarkAppearanceUpdate: ((Int) -> Void)?
	private(set) var summaries: [ConversationTurnSummary] = []
	private(set) var activeTurnID: String?
	private let scrollView = TurnNavigationScrollView()
	private let document = NSView()
	private let edgeFade = CAGradientLayer()
	private var marks: [TurnNavigationMark] = []
	private var entryIndices: [String: Int] = [:]
	private var turnLocations: [String: TurnLocation] = [:]
	private weak var hoveredMark: TurnNavigationMark?
	private var hoveredEntryID: String?
	private var highlightedIndex: Int?
	private var needsActiveTurnReveal = false
	private(set) var previewPanel: NSPanel?
	private var previewAppearance: DesktopPanelAppearanceBinding?
	private var previewTurnID: String?
	private var dismissal: DispatchWorkItem?

	override init(frame: NSRect)
	{
		super.init(frame: frame)
		scrollView.documentView = document
		scrollView.drawsBackground = false
		scrollView.hasVerticalScroller = false
		scrollView.verticalScrollElasticity = .none
		scrollView.horizontalScrollElasticity = .none
		scrollView.wantsLayer = true
		scrollView.contentView.postsBoundsChangedNotifications = true
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(railViewportChanged),
			name: NSView.boundsDidChangeNotification,
			object: scrollView.contentView
		)
		addSubview(scrollView)
		setAccessibilityLabel("Conversation turns")
	}

	@available(
		*,
		unavailable
	)
	required init?(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}

	func render(_ next: [ConversationTurnSummary])
	{
		guard summaries != next
		else
		{
			return
		}
		let previousIDs = summaries.map(\.entryID)
		let nextIDs = next.map(\.entryID)
		let previousTurns = summaries.map(\.turnID)
		let nextTurns = next.map(\.turnID)
		// Loading or evicting content changes its entry target, not the ordered rail turns.
		// Equal entry targets also retain the legacy first-match behavior for duplicate IDs.
		let identitiesChanged = previousIDs != nextIDs && previousTurns != nextTurns
		let prependedHistory = !previousTurns.isEmpty && nextTurns.count > previousTurns.count
			&& Array(nextTurns.suffix(previousTurns.count)) == previousTurns
		summaries = next
		indexSummaries()
		if identitiesChanged
		{
			needsActiveTurnReveal = !prependedHistory
			hoveredMark = nil
			hoveredEntryID = nil
			dismissPreview()
			marks.forEach
			{
				$0.removeFromSuperview()
			}
			marks = next.map
			{
				_ in
				let mark = TurnNavigationMark(
					title: "",
					target: self,
					action: #selector(jump(_:))
				)
				mark.isBordered = false
				mark.onScrollWheel =
				{
					[weak self] event in self?.scrollWheel(with: event)
				}
				mark.onEnter =
				{
					[weak self, weak mark] in
					guard let mark
					else
					{
						return
					}
					self?.hoveredMark = mark
					self?.hoveredEntryID = mark.entryID
					self?.updateMarkAppearance()
					self?.showPreview(for: mark)
					if let self, let index = entryIndices[mark.entryID]
					{
						requestTurnPreview(summaries[index])
					}
				}
				mark.onExit =
				{
					[weak self, weak mark] in
					if self?.hoveredMark === mark
					{
						self?.hoveredMark = nil
						self?.hoveredEntryID = nil
						self?.updateMarkAppearance()
					}
					self?.hoverLoadTask?.cancel()
					self?.scheduleDismissal()
				}
				document.addSubview(mark)
				return mark
			}
			needsLayout = true
		}
		for (index, mark) in marks.enumerated()
		{
			let summary = next[index]
			mark.entryID = summary.entryID
			mark.setAccessibilityLabel("Jump to turn: \(summary.title)")
		}
		if let hoveredMark
		{
			hoveredEntryID = hoveredMark.entryID
		}
		if let previewTurnID, let location = turnLocations[previewTurnID]
		{
			showPreview(for: marks[location.markIndex])
		}
		isHidden = next.isEmpty
		updateMarkAppearance(force: identitiesChanged)
	}

	private func indexSummaries()
	{
		var entryIndices: [String: Int] = [:]
		entryIndices.reserveCapacity(summaries.count)
		for (index, summary) in summaries.enumerated() where entryIndices[summary.entryID] == nil
		{
			entryIndices[summary.entryID] = index
		}

		var turnLocations: [String: TurnLocation] = [:]
		turnLocations.reserveCapacity(summaries.count)
		for (index, summary) in summaries.enumerated()
		{
			let markIndex = entryIndices[summary.entryID] ?? index
			if let location = turnLocations[summary.turnID]
			{
				// A duplicate entry can put the first matching preview mark before this turn.
				if markIndex < location.markIndex
				{
					turnLocations[summary.turnID]?.markIndex = markIndex
				}
			}
			else
			{
				turnLocations[summary.turnID] = TurnLocation(
					summaryIndex: index,
					markIndex: markIndex
				)
			}
		}
		self.entryIndices = entryIndices
		self.turnLocations = turnLocations
	}

	override func layout()
	{
		super.layout()
		// Keep the same 62-turn range when the window is shorter than 620 points.
		let markHeight = min(
			Self.markHeight,
			max(
				0,
				bounds.height
			) / CGFloat(min(
				62,
				max(
					1,
					marks.count
				)
			))
		)
		let height = min(
			bounds.height,
			Self.maximumHeight,
			CGFloat(marks.count) * markHeight
		)
		let viewportHeightChanged = scrollView.frame.height != height
		scrollView.frame = NSRect(
			x: 0,
			y: (bounds.height - height) / 2,
			width: bounds.width,
			height: height
		)
		document.frame = NSRect(
			x: 0,
			y: 0,
			width: bounds.width,
			height: CGFloat(marks.count) * markHeight
		)
		for (index, mark) in marks.enumerated()
		{
			mark.frame = NSRect(
				x: 0,
				y: document.bounds.height - CGFloat(index + 1) * markHeight,
				width: bounds.width,
				height: markHeight
			)
		}
		if needsActiveTurnReveal || viewportHeightChanged
		{
			needsActiveTurnReveal = false
			revealActiveTurn()
		}
		updateEdgeFade()
	}

	func updateActiveTurn(_ turnID: String?)
	{
		if activeTurnID != turnID
		{
			needsActiveTurnReveal = true
			needsLayout = true
		}
		activeTurnID = turnID
		updateMarkAppearance()
	}

	private func revealActiveTurn()
	{
		guard let activeTurnID, let location = turnLocations[activeTurnID],
				marks.indices.contains(location.summaryIndex)
		else
		{
			return
		}
		let mark = marks[location.summaryIndex]
		document.scrollToVisible(mark.frame.insetBy(
			dx: 0,
			dy: -Self.edgeFadeHeight
		).intersection(document.bounds))
	}

	override func scrollWheel(with event: NSEvent)
	{
		scrollView.scrollWheel(with: event)
		let visible = scrollView.contentView.bounds
		if event.scrollingDeltaY > 0,
			visible.maxY >= document.bounds.maxY - Self.edgeFadeHeight,
			canLoadEarlierReferences, !historyRequestPending, let onLoadEarlierReferences
		{
			historyRequestPending = true
			onLoadEarlierReferences()
		}
	}

	@objc private func railViewportChanged()
	{
		hoveredMark = nil
		hoveredEntryID = nil
		dismissPreview()
		updateMarkAppearance()
		updateEdgeFade()
	}

	private func updateEdgeFade()
	{
		let visible = scrollView.contentView.bounds
		guard visible.height > 0,
				document.bounds.height > visible.height || canLoadEarlierReferences
		else
		{
			scrollView.layer?.mask = nil
			return
		}
		let fadeFraction = min(
			Self.edgeFadeHeight / visible.height,
			0.5
		)
		let opaque = NSColor.black.cgColor
		let transparent = NSColor.clear.cgColor
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		edgeFade.frame = scrollView.bounds
		edgeFade.startPoint = CGPoint(
			x: 0.5,
			y: scrollView.isFlipped ? 1 : 0
		)
		edgeFade.endPoint = CGPoint(
			x: 0.5,
			y: scrollView.isFlipped ? 0 : 1
		)
		edgeFade.colors = [
			visible.minY > document.bounds.minY ? transparent : opaque,
			opaque,
			opaque,
			visible.maxY < document.bounds.maxY || canLoadEarlierReferences ? transparent : opaque,
		]
		edgeFade.locations = [
			0,
			NSNumber(value: fadeFraction),
			NSNumber(value: 1 - fadeFraction),
			1,
		]
		scrollView.layer?.mask = edgeFade
		CATransaction.commit()
	}

	private func updateMarkAppearance(force: Bool = false)
	{
		let nextHighlightedIndex: Int?
		if let hoveredEntryID
		{
			nextHighlightedIndex = entryIndices[hoveredEntryID]
		}
		else
		{
			nextHighlightedIndex = activeTurnID.flatMap
			{
				turnLocations[$0]?.summaryIndex
			}
		}
		guard force || nextHighlightedIndex != highlightedIndex
		else
		{
			return
		}
		let previousHighlightedIndex = highlightedIndex
		highlightedIndex = nextHighlightedIndex
		if force
		{
			for index in marks.indices
			{
				updateMarkAppearance(
					at: index,
					force: true
				)
			}
			return
		}
		if let previousHighlightedIndex
		{
			updateMarkAppearance(at: previousHighlightedIndex)
		}
		if let nextHighlightedIndex,
			nextHighlightedIndex != previousHighlightedIndex
		{
			updateMarkAppearance(at: nextHighlightedIndex)
		}
	}

	private func updateMarkAppearance(
		at index: Int,
		force: Bool = false
	)
	{
		let mark = marks[index]
		let isEmphasized = index == highlightedIndex
		guard force || mark.isEmphasized != isEmphasized
		else
		{
			return
		}
		mark.isEmphasized = isEmphasized
		mark.needsDisplay = true
		onMarkAppearanceUpdate?(index)
	}

	func refreshBookmark()
	{
		guard let previewTurnID, let location = turnLocations[previewTurnID],
				let preview = previewPanel?.contentView as? TurnSummaryPreview
		else
		{
			return
		}
		preview.setBookmarked(isBookmarked?(summaries[location.summaryIndex]) == true)
	}

	func dismissPreview()
	{
		hoverLoadTask?.cancel()
		hoverLoadTask = nil
		dismissal?.cancel()
		dismissal = nil
		previewAppearance?.invalidate()
		previewAppearance = nil
		if let panel = previewPanel
		{
			panel.parent?.removeChildWindow(panel)
			panel.orderOut(nil)
		}
		previewPanel = nil
		previewTurnID = nil
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		if window == nil
		{
			hoveredMark = nil
			hoveredEntryID = nil
			dismissPreview()
			updateMarkAppearance()
		}
	}

	@objc private func jump(_ mark: TurnNavigationMark)
	{
		guard let index = entryIndices[mark.entryID]
		else
		{
			return
		}
		dismissPreview()
		onJump?(summaries[index])
	}

	func requestTurnPreview(_ summary: ConversationTurnSummary)
	{
		hoverLoadTask?.cancel()
		if summary.isContentLoaded || summary.isPreviewLoaded
		{
			onLoadTurnPreview?(summary.turnID)
			return
		}
		if !summary.isContentLoaded && !summary.isPreviewLoaded
		{
			hoverLoadTask = Task
			{
				[weak self] in
				do
				{
					try await Task
						.sleep(for: .milliseconds(ConversationCachePolicy.debounceMilliseconds))
				}
				catch
				{
					return
				}
				guard let self, !Task.isCancelled
				else
				{
					return
				}
				hoverLoadTask = nil
				onLoadTurnPreview?(summary.turnID)
			}
		}
	}

	private func showPreview(for mark: TurnNavigationMark)
	{
		guard window != nil,
				let index = entryIndices[mark.entryID]
		else
		{
			return
		}
		let summary = summaries[index]

		if previewTurnID == summary.turnID,
			let preview = previewPanel?.contentView as? TurnSummaryPreview
		{
			preview.render(summary)
			positionPreview(
				beside: mark,
				preview: preview
			)
			return
		}
		dismissPreview()
		previewTurnID = summary.turnID
		let preview = TurnSummaryPreview(
			summary: summary,
			bookmarked: isBookmarked?(summary) == true
		)
		preview.onEnter =
		{
			[weak self] in
			self?.dismissal?.cancel()
			if let self, let current = summaries.first(where:
				{
					$0.turnID == summary.turnID
				})
			{
				requestTurnPreview(current)
			}
		}
		preview.onExit =
		{
			[weak self] in self?.scheduleDismissal()
		}
		preview.onBookmark =
		{
			[weak self, weak preview] in
			guard let self, let location = turnLocations[summary.turnID]
			else
			{
				return
			}
			let current = summaries[location.summaryIndex]
			onBookmark?(current)
			preview?.setBookmarked(isBookmarked?(current) == true)
		}
		let panel = NSPanel(
			contentRect: preview.bounds,
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		panel.isReleasedWhenClosed = false
		panel.animationBehavior = .none
		panel.contentView = preview
		previewAppearance = DesktopPanelAppearanceBinding(
			panel: panel,
			source: self
		)
		previewPanel = panel
		positionPreview(
			beside: mark,
			preview: preview
		)
		window?.addChildWindow(
			panel,
			ordered: .above
		)
		panel.orderFront(nil)
	}

	private func positionPreview(
		beside mark: NSView,
		preview: TurnSummaryPreview
	)
	{
		guard let window, let panel = previewPanel
		else
		{
			return
		}
		let markScreenRect = window.convertToScreen(mark.convert(
			mark.bounds,
			to: nil
		))
		let visibleScreenFrame = window.screen?.visibleFrame ?? window.frame
		let previewSize = NSSize(
			width: TurnSummaryPreview.cardWidth,
			height: preview.cardHeight
		)
		let previewOriginX = min(
			markScreenRect.maxX + 4,
			visibleScreenFrame.maxX - previewSize.width
		)
		let previewOriginY = max(
			visibleScreenFrame.minY,
			min(
				markScreenRect.midY - previewSize.height / 2,
				visibleScreenFrame.maxY - previewSize.height
			)
		)
		panel.setFrame(
			NSRect(
				x: previewOriginX,
				y: previewOriginY,
				width: previewSize.width,
				height: previewSize.height
			),
			display: true
		)
	}

	private func scheduleDismissal()
	{
		dismissal?.cancel()
		let work = DispatchWorkItem
		{
			[weak self] in self?.dismissPreview()
		}
		dismissal = work
		DispatchQueue.main.asyncAfter(
			deadline: .now() + 0.2,
			execute: work
		)
	}
}

@MainActor
final class TurnNavigationScrollView: NSScrollView
{
	override func scrollWheel(with event: NSEvent)
	{
		guard let documentView, documentView.bounds.height > contentView.bounds.height
		else
		{
			return
		}
		let scale = event.hasPreciseScrollingDeltas ? 1 : verticalLineScroll
		let direction: CGFloat = documentView.isFlipped ? -1 : 1
		let origin = contentView.bounds.origin
		let maximumY = documentView.bounds.maxY - contentView.bounds.height
		let nextY = min(
			maximumY,
			max(
				documentView.bounds.minY,
				origin.y + direction * event.scrollingDeltaY * scale
			)
		)
		contentView.scroll(to: NSPoint(
			x: origin.x,
			y: nextY
		))
		reflectScrolledClipView(contentView)
	}
}

@MainActor
final class TurnNavigationMark: NSButton
{
	var entryID = ""
	var isEmphasized = false
	let lineWidth: CGFloat = 6
	private static let highlightedColor = gray(
		light: 0x80,
		dark: 0xA3
	)
	private static let ordinaryColor = gray(
		light: 0xD5,
		dark: 0x46
	)
	var onEnter: (() -> Void)?
	var onExit: (() -> Void)?
	var onScrollWheel: ((NSEvent) -> Void)?

	override func scrollWheel(with event: NSEvent)
	{
		onScrollWheel?(event)
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		trackingAreas.forEach(removeTrackingArea)
		addTrackingArea(NSTrackingArea(
			rect: .zero,
			options: [
				.mouseEnteredAndExited,
				.activeInKeyWindow,
				.inVisibleRect
			],
			owner: self,
			userInfo: nil
		))
	}

	override func mouseEntered(with event: NSEvent)
	{
		onEnter?()
	}
	override func mouseExited(with event: NSEvent)
	{
		onExit?()
	}

	private static func gray(
		light: CGFloat,
		dark: CGFloat
	) -> NSColor
	{
		NSColor(name: nil)
		{
			appearance in
			let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
			return NSColor(
				srgbRed: value / 255,
				green: value / 255,
				blue: value / 255,
				alpha: 1
			)
		}
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		(isEmphasized ? Self.highlightedColor : Self.ordinaryColor).setFill()
		NSBezierPath(
			roundedRect: NSRect(
				x: 4.5,
				y: bounds.midY - 1,
				width: lineWidth,
				height: 2
			),
			xRadius: 1,
			yRadius: 1
		).fill()
		if window?.firstResponder === self
		{
			NSColor.keyboardFocusIndicatorColor.setStroke()
			NSBezierPath(
				roundedRect: bounds.insetBy(
					dx: 1,
					dy: 1
				),
				xRadius: 3,
				yRadius: 3
			).stroke()
		}
	}
}
