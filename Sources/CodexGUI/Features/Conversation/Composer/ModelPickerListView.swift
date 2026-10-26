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
	private let document = DesktopFlippedView()
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
				self?.rows.filter
				{
					$0 !== row
				}.forEach
				{
					$0.clearHover()
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
		onSelect?(row.choice.id)
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
					.foregroundColor: AppKitColorTokens.composerSecondaryText,
				]
			)
		}
	}
}

@MainActor
final class ModelPickerRow: DesktopMenuRow
{
	let choice: ModelPickerChoice
	var onNavigate: ((Int) -> Void)?

	init(
		choice: ModelPickerChoice,
		selected: Bool
	)
	{
		self.choice = choice
		super.init(content: Content(
			title: choice.title,
			subtitle: choice.subtitle,
			indicator: .checkmark,
			checked: selected
		))
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	var preferredHeight: CGFloat
	{
		rowHeight
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
