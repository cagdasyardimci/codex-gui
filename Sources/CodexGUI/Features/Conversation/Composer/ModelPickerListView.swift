import AppKit

struct ModelPickerChoice
{
	let id: String?
	let title: String
	var subtitle: String?
	{
		id == nil ? "Recommended set of models" : nil
	}
}

@MainActor
final class ModelPickerListView: NSView
{
	var onSelect: ((String?) -> Void)?
	private let scrollView = NSScrollView()
	private let document = ModelPickerDocumentView()
	private let stack = NSStackView()
	private(set) var rows: [ModelPickerRow] = []
	private typealias Layout = LayoutTokens.ModelList

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		setAccessibilityElement(true)
		setAccessibilityRole(.menu)
		setAccessibilityLabel("Select model")
		scrollView.drawsBackground = false
		scrollView.hasVerticalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.scrollerStyle = .overlay
		scrollView.documentView = document
		AppKitLayout.pin(
			scrollView,
			to: self,
			inset: Layout.outerInset
		)
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 0
		AppKitLayout.pin(
			stack,
			to: document,
			inset: 0
		)
		document.translatesAutoresizingMaskIntoConstraints = false
		document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	var preferredHeight: CGFloat
	{
		(2 * Layout.outerInset + Layout.headerHeight
			+ rows.reduce(0)
			{
				$0 + $1.preferredHeight
			}).rounded()
	}

	func render(
		choices: [ModelPickerChoice],
		selectedID: String?
	)
	{
		let focusedID = (window?.firstResponder as? ModelPickerRow)?.choice.id
		let hadFocus = rows.contains
		{
			$0 === window?.firstResponder
		}
		for child in stack.arrangedSubviews
		{
			stack.removeArrangedSubview(child)
			child.removeFromSuperview()
		}
		let header = ModelPickerHeading()
		stack.addArrangedSubview(header)
		header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		header.heightAnchor.constraint(equalToConstant: Layout.headerHeight).isActive = true
		rows = choices.map
		{
			choice in
			let row = ModelPickerRow(
				choice: choice,
				selected: choice.id == selectedID
			)
			row.target = self
			row.action = #selector(selectRow(_:))
			row.onNavigate =
			{
				[weak self, weak row] offset in
				guard let row
				else
				{
					return
				}
				self?.moveFocus(
					from: row,
					offset: offset
				)
			}
			row.onHover =
			{
				[weak self, weak row] in
				guard let self
				else
				{
					return
				}
				for other in self.rows where other !== row
				{
					other.clearHover()
				}
			}
			stack.addArrangedSubview(row)
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
			row.heightAnchor.constraint(equalToConstant: row.preferredHeight).isActive = true
			return row
		}
		for index in rows.indices
		{
			rows[index].nextKeyView = rows[(index + 1) % rows.count]
		}
		if hadFocus
		{
			focus(rows.first
			{
				$0.choice.id == focusedID
			} ?? rows.first
			{
				$0.state == .on
			})
		}
	}

	func focusSelectedRow()
	{
		focus(rows.first
		{
			$0.state == .on
		} ?? rows.first)
	}

	private func focus(_ row: ModelPickerRow?)
	{
		guard let row
		else
		{
			return
		}
		window?.makeFirstResponder(row)
		row.scrollToVisible(row.bounds)
	}

	private func moveFocus(
		from row: ModelPickerRow,
		offset: Int
	)
	{
		guard let index = rows.firstIndex(where:
			{
				$0 === row
			})
		else
		{
			return
		}
		let destination: Int
		switch offset
		{
		case .min: destination = 0
		case .max: destination = rows.count - 1
		default: destination = (index + offset + rows.count) % rows.count
		}
		focus(rows[destination])
	}

	@objc private func selectRow(_ row: ModelPickerRow)
	{
		guard row.superview === stack
		else
		{
			return
		}
		onSelect?(row.choice.id)
	}
}

@MainActor
private final class ModelPickerDocumentView: NSView
{
	override var isFlipped: Bool
	{
		true
	}
}

@MainActor
private final class ModelPickerHeading: NSView
{
	override func draw(_ dirtyRect: NSRect)
	{
		DesktopTextRendering.withFontSmoothingDisabled
		{
			("Select model" as NSString).draw(
				at: NSPoint(
					x: LayoutTokens.ModelList.horizontalInset,
					y: LayoutTokens.ModelList.headerVerticalInset
				),
				withAttributes: [
					.font: AppKitFontResolver.font(TypographyTokens.ModelPopover.menu),
					.foregroundColor: AppKitColorTokens.secondaryText,
				]
			)
		}
	}
}

@MainActor
final class ModelPickerRow: NSButton
{
	let choice: ModelPickerChoice
	var onNavigate: ((Int) -> Void)?
	var onHover: (() -> Void)?
	private var hovered = false
	private var tracking: NSTrackingArea?
	private typealias Layout = LayoutTokens.ModelList

	init(
		choice: ModelPickerChoice,
		selected: Bool
	)
	{
		self.choice = choice
		super.init(frame: .zero)
		title = choice.title
		isBordered = false
		bezelStyle = .inline
		focusRingType = .none
		state = selected ? .on : .off
		setAccessibilityRole(.menuItem)
		setAccessibilityLabel(choice.title)
		setAccessibilityHelp(choice.subtitle)
		setAccessibilityValue(selected ? "Selected" : "Not selected")
	}

	required init?(coder: NSCoder)
	{
		nil
	}
	override var acceptsFirstResponder: Bool
	{
		true
	}
	override var isFlipped: Bool
	{
		true
	}
	var preferredHeight: CGFloat
	{
		Layout.rowHeight + (choice.subtitle == nil ? 0 : Layout.secondaryHeight)
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let tracking
		{
			removeTrackingArea(tracking)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		tracking = area
	}

	override func mouseEntered(with event: NSEvent)
	{
		onHover?()
		hovered = true
		needsDisplay = true
	}
	override func mouseExited(with event: NSEvent)
	{
		clearHover()
	}
	func clearHover()
	{
		guard hovered
		else
		{
			return
		}
		hovered = false
		needsDisplay = true
	}
	override func becomeFirstResponder() -> Bool
	{
		let accepted = super.becomeFirstResponder()
		needsDisplay = true
		return accepted
	}
	override func resignFirstResponder() -> Bool
	{
		let accepted = super.resignFirstResponder()
		needsDisplay = true
		return accepted
	}
	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if hovered || window?.firstResponder === self || cell?.isHighlighted == true
		{
			AppKitColorTokens.rowHighlight.setFill()
			NSBezierPath(
				roundedRect: bounds,
				xRadius: ShapeTokens.ModelList.rowRadius,
				yRadius: ShapeTokens.ModelList.rowRadius
			).fill()
		}
		let textWidth = max(
			0,
			bounds.width - 2 * Layout.horizontalInset - Layout.checkSize - Layout.checkTextSpacing
		)
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		DesktopTextRendering.withFontSmoothingDisabled
		{
			(choice.title as NSString).draw(
				in: NSRect(
					x: Layout.horizontalInset,
					y: Layout.verticalInset,
					width: textWidth,
					height: Layout.titleHeight
				),
				withAttributes: [
					.font: AppKitFontResolver.font(TypographyTokens.ModelPopover.menu),
					.foregroundColor: AppKitColorTokens.primaryText,
					.paragraphStyle: paragraph,
				]
			)
			if let subtitle = choice.subtitle
			{
				(subtitle as NSString).draw(
					in: NSRect(
						x: Layout.horizontalInset,
						y: Layout.verticalInset + Layout.titleHeight,
						width: textWidth,
						height: Layout.secondaryHeight
					),
					withAttributes: [
						.font: AppKitFontResolver
							.font(TypographyTokens.ModelPopover.modelExplanation),
						.foregroundColor: AppKitColorTokens.secondaryText,
						.paragraphStyle: paragraph,
					]
				)
			}
		}
		if state == .on
		{
			DesktopIcons.draw(
				ApprovalPolicyIcons.selectedCheck,
				in: NSRect(
					x: bounds.maxX - Layout.horizontalInset - Layout.checkSize,
					y: bounds.midY - Layout.checkSize / 2,
					width: Layout.checkSize,
					height: Layout.checkSize
				),
				tint: AppKitColorTokens.primaryText
			)
		}
	}

	override func keyDown(with event: NSEvent)
	{
		switch event.keyCode
		{
		case 125: onNavigate?(1)
		case 126: onNavigate?(-1)
		case 115: onNavigate?(.min)
		case 119: onNavigate?(.max)
		case 36, 76, 49: performClick(nil)
		default: super.keyDown(with: event)
		}
	}
}
