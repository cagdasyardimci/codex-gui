import AppKit

/// Compact turn marks beside the transcript, with an interactive hover preview.
@MainActor
final class TurnNavigationRail: NSView
{
	var onJump: ((ConversationTurnSummary) -> Void)?
	var onBookmark: ((ConversationTurnSummary) -> Void)?
	var isBookmarked: ((ConversationTurnSummary) -> Bool)?
	private(set) var summaries: [ConversationTurnSummary] = []
	private(set) var activeTurnID: String?
	private let scrollView = NSScrollView()
	private let document = NSView()
	private var marks: [TurnNavigationMark] = []
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
					self?.showPreview(for: mark)
				}
				mark.onExit =
				{
					[weak self] in self?.scheduleDismissal()
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
			CGFloat(marks.count) * 14
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
			height: CGFloat(marks.count) * 14
		)
		for (index, mark) in marks.enumerated()
		{
			mark.frame = NSRect(
				x: 0,
				y: document.bounds.height - CGFloat(index + 1) * 14,
				width: bounds.width,
				height: 14
			)
		}
	}

	func updateActiveTurn(_ turnID: String?)
	{
		activeTurnID = turnID
		for (index, mark) in marks.enumerated()
		{
			mark.isCurrent = summaries[index].turnID == turnID
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
	var isCurrent = false
	private var isHovered = false
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
		isHovered = true
		needsDisplay = true
		onEnter?()
	}
	override func mouseExited(with event: NSEvent)
	{
		isHovered = false
		needsDisplay = true
		onExit?()
	}

	override func draw(_ dirtyRect: NSRect)
	{
		(isCurrent || isHovered ? NSColor.labelColor : NSColor.tertiaryLabelColor).setFill()
		let width: CGFloat = isCurrent || isHovered ? 26 : 18
		NSBezierPath(
			roundedRect: NSRect(
				x: 3,
				y: bounds.midY - 1,
				width: width,
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
