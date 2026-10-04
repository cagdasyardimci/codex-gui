import AppKit

/// Compact turn marks beside the transcript, with an interactive hover preview.
@MainActor
final class TurnNavigationRail: NSView
{
	private struct TurnLocation
	{
		let summaryIndex: Int
		var markIndex: Int
	}

	private static let markHeight: CGFloat = 14
	var onJump: ((ConversationTurnSummary) -> Void)?
	var onBookmark: ((ConversationTurnSummary) -> Void)?
	var isBookmarked: ((ConversationTurnSummary) -> Bool)?
	// Reports the rail's writes independently of AppKit's inherited dirty flags.
	var onMarkAppearanceUpdate: ((Int) -> Void)?
	private(set) var summaries: [ConversationTurnSummary] = []
	private(set) var activeTurnID: String?
	private let scrollView = NSScrollView()
	private let document = NSView()
	private var marks: [TurnNavigationMark] = []
	private var entryIndices: [String: Int] = [:]
	private var turnLocations: [String: TurnLocation] = [:]
	private var hoveredEntryID: String?
	private var highlightedIndex: Int?
	private(set) var previewPanel: NSPanel?
	private var previewTurnID: String?
	private var dismissal: DispatchWorkItem?

	override init(frame: NSRect)
	{
		super.init(frame: frame)
		scrollView.documentView = document
		scrollView.drawsBackground = false
		scrollView.hasVerticalScroller = false
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
		let identitiesChanged = summaries.map(\.entryID) != next.map(\.entryID)
		summaries = next
		indexSummaries()
		if identitiesChanged
		{
			hoveredEntryID = nil
			dismissPreview()
			marks.forEach
			{
				$0.removeFromSuperview()
			}
			marks = next.map
			{
				summary in
				let mark = TurnNavigationMark(
					title: "",
					target: self,
					action: #selector(jump(_:))
				)
				mark.entryID = summary.entryID
				mark.isBordered = false
				mark.setAccessibilityLabel("Jump to turn: \(summary.title)")
				mark.onEnter =
				{
					[weak self, weak mark] in
					guard let mark
					else
					{
						return
					}
					self?.hoveredEntryID = mark.entryID
					self?.updateMarkAppearance()
					self?.showPreview(for: mark)
				}
				mark.onExit =
				{
					[weak self, weak mark] in
					if self?.hoveredEntryID == mark?.entryID
					{
						self?.hoveredEntryID = nil
						self?.updateMarkAppearance()
					}
					self?.scheduleDismissal()
				}
				document.addSubview(mark)
				return mark
			}
		}
		else if let previewTurnID, let location = turnLocations[previewTurnID]
		{
			showPreview(for: marks[location.markIndex])
		}
		isHidden = next.isEmpty
		updateMarkAppearance(force: identitiesChanged)
		needsLayout = true
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
		let height = min(
			bounds.height,
			CGFloat(marks.count) * Self.markHeight
		)
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
			height: CGFloat(marks.count) * Self.markHeight
		)
		for (index, mark) in marks.enumerated()
		{
			mark.frame = NSRect(
				x: 0,
				y: document.bounds.height - CGFloat(index + 1) * Self.markHeight,
				width: bounds.width,
				height: Self.markHeight
			)
		}
	}

	func updateActiveTurn(_ turnID: String?)
	{
		activeTurnID = turnID
		updateMarkAppearance()
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
		let previousRange = previousHighlightedIndex.map(appearanceRange)
		let nextRange = nextHighlightedIndex.map(appearanceRange)
		if let previousRange
		{
			for index in previousRange
			{
				updateMarkAppearance(at: index)
			}
		}
		if let nextRange
		{
			for index in nextRange where previousRange?.contains(index) != true
			{
				updateMarkAppearance(at: index)
			}
		}
	}

	private func appearanceRange(_ index: Int) -> Range<Int>
	{
		// Four tapering marks on either side make a nine-mark triangle.
		max(
			0,
			index - 4
		) ..< min(
			marks.count,
			index + 5
		)
	}

	private func updateMarkAppearance(
		at index: Int,
		force: Bool = false
	)
	{
		let mark = marks[index]
		let isEmphasized = index == highlightedIndex
		let lineWidth = highlightedIndex.map
		{
			max(
				8,
				26 - CGFloat(abs(index - $0)) * 4.5
			)
		} ?? 8
		guard force || mark.isEmphasized != isEmphasized || mark.lineWidth != lineWidth
		else
		{
			return
		}
		mark.isEmphasized = isEmphasized
		mark.lineWidth = lineWidth
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
		dismissal?.cancel()
		dismissal = nil
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
			dismissPreview()
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
			[weak self] in self?.dismissal?.cancel()
		}
		preview.onExit =
		{
			[weak self] in self?.scheduleDismissal()
		}
		preview.onBookmark =
		{
			[weak self, weak preview] in
			self?.onBookmark?(summary)
			preview?.setBookmarked(self?.isBookmarked?(summary) == true)
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
		let rect = window.convertToScreen(mark.convert(
			mark.bounds,
			to: nil
		))
		let screen = window.screen?.visibleFrame ?? window.frame
		let size = NSSize(
			width: TurnSummaryPreview.cardWidth,
			height: preview.cardHeight
		)
		let x = min(
			rect.maxX + 4,
			screen.maxX - size.width
		)
		let y = max(
			screen.minY,
			min(
				rect.midY - size.height / 2,
				screen.maxY - size.height
			)
		)
		panel.setFrame(
			NSRect(
				x: x,
				y: y,
				width: size.width,
				height: size.height
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
final class TurnNavigationMark: NSButton
{
	var entryID = ""
	var isEmphasized = false
	var lineWidth: CGFloat = 8
	private static let highlightedColor = gray(
		light: 0x80,
		dark: 0xE6
	)
	private static let ordinaryColor = gray(
		light: 0xD5,
		dark: 0x41
	)
	var onEnter: (() -> Void)?
	var onExit: (() -> Void)?

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
				x: 3,
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
