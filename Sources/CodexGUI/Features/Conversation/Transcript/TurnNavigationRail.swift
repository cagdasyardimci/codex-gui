import AppKit

/// Compact turn marks beside the transcript, with an interactive hover preview.
@MainActor
final class TurnNavigationRail: NSView
{
	private static let markHeight: CGFloat = 14
	var onJump: ((ConversationTurnSummary) -> Void)?
	var onBookmark: ((ConversationTurnSummary) -> Void)?
	var isBookmarked: ((ConversationTurnSummary) -> Bool)?
	private(set) var summaries: [ConversationTurnSummary] = []
	private(set) var activeTurnID: String?
	private let scrollView = NSScrollView()
	private let document = NSView()
	private var marks: [TurnNavigationMark] = []
	private var hoveredEntryID: String?
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
		else if let previewTurnID, let mark = marks.first(where:
			{
				mark in next.contains
				{
					$0.turnID == previewTurnID && $0.entryID == mark.entryID
				}
			})
		{
			showPreview(for: mark)
		}
		isHidden = next.isEmpty
		updateActiveTurn(activeTurnID)
		needsLayout = true
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

	private func updateMarkAppearance()
	{
		let highlightedIndex = summaries.firstIndex
		{
			if let hoveredEntryID
			{
				return $0.entryID == hoveredEntryID
			}
			return $0.turnID == activeTurnID
		}
		for (index, mark) in marks.enumerated()
		{
			mark.isEmphasized = index == highlightedIndex
			let distance = highlightedIndex.map
			{
				abs(index - $0)
			}
			mark.lineWidth = distance.map
			{
				// Four tapering marks on either side make a nine-mark triangle.
				max(
					8,
					26 - CGFloat($0) * 4.5
				)
			} ?? 8
			mark.needsDisplay = true
		}
	}

	func refreshBookmark()
	{
		guard let summary = summaries.first(where:
			{
				$0.turnID == previewTurnID
			}),
			let preview = previewPanel?.contentView as? TurnSummaryPreview
		else
		{
			return
		}
		preview.setBookmarked(isBookmarked?(summary) == true)
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
		guard let summary = summaries.first(where:
			{
				$0.entryID == mark.entryID
			})
		else
		{
			return
		}
		dismissPreview()
		onJump?(summary)
	}

	private func showPreview(for mark: TurnNavigationMark)
	{
		guard window != nil,
				let summary = summaries.first(where:
				{
					$0.entryID == mark.entryID
				})
		else
		{
			return
		}

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
private final class TurnNavigationMark: NSButton
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
