import AppKit

/// Opens the recorded call envelope without interpreting or executing its contents.
@MainActor
final class SourceRawOutputPresenter: NSObject
{
	private var panel: NSPanel?
	private var copiedOutput = ""
	private var inspection: Inspection?

	private struct Inspection
	{
		let recordID: String
		let invocation: ConversationLocalSources.Invocation
	}

	func update(records: [ConversationLocalSources.Record])
	{
		guard let inspection
		else
		{
			return
		}
		let current = records.first
		{
			$0.id == inspection.recordID
		}?.invocations.first
		{
			$0.id == inspection.invocation.id
		}
		if current != inspection.invocation
		{
			dismiss()
		}
	}

	func present(
		_ invocation: ConversationLocalSources.Invocation,
		recordID: String,
		in parent: NSWindow
	)
	{
		guard panel == nil, parent.attachedSheet == nil
		else
		{
			return
		}
		let data = invocation.detail.data(using: .utf8)
		let json = data.flatMap
		{
			try? JSONSerialization.jsonObject(with: $0)
		}
		let fields = json as? [String: Any]
		let server = fields?["server"] as? String ?? fields?["namespace"] as? String
		let tool = fields?["tool"] as? String ?? invocation.operation
		let call = server.map
		{
			$0 + "." + tool
		} ?? tool
		let title = "Raw \(call) tool call output"
		copiedOutput = invocation.detail
		let width = min(
			640,
			max(
				320,
				parent.contentLayoutRect.width - 80
			)
		)
		let maximumBodyHeight = max(
			140,
			min(
				580,
				parent.contentLayoutRect.height - 180
			)
		)
		let container = NSView()
		container.widthAnchor.constraint(equalToConstant: width).isActive = true
		let heading = NSTextField(labelWithString: title)
		heading.font = .systemFont(
			ofSize: 17,
			weight: .semibold
		)
		heading.lineBreakMode = .byTruncatingTail
		heading.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let closeButton = iconButton(
			.x,
			label: "Close raw tool call output",
			action: #selector(close)
		)
		closeButton.keyEquivalent = "\u{1b}"
		closeButton.keyEquivalentModifierMask = []
		let header = AppKitLayout.horizontalStack(
			[heading, NSView(), closeButton],
			spacing: 12
		)
		let copy = iconButton(
			.copy,
			label: "Copy raw tool call output",
			action: #selector(copyOutput)
		)
		let code = SourceResultCodeCard(
			text: invocation.detail.isEmpty ? "No recorded call details." : invocation.detail,
			language: json == nil ? "text" : "json",
			identifier: "source-raw-output:\(invocation.id)",
			maximumBodyHeight: maximumBodyHeight,
			headerAccessory: copy
		)
		let limit =
			NSTextField(labelWithString: "Recorded details are bounded; omitted content is marked.")
		limit.font = .systemFont(ofSize: 11)
		limit.textColor = .secondaryLabelColor
		let stack = AppKitLayout.verticalStack(
			[header, code, limit],
			spacing: 12
		)
		AppKitLayout.pin(
			stack,
			to: container,
			inset: 24
		)
		let rows: [NSView] = [header, code, limit]
		for row in rows
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		container.layoutSubtreeIfNeeded()
		let sheet = NSPanel(
			contentRect: NSRect(
				origin: .zero,
				size: container.fittingSize
			),
			styleMask: [.titled, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		sheet.title = title
		sheet.titleVisibility = .hidden
		sheet.titlebarAppearsTransparent = true
		sheet.isReleasedWhenClosed = false
		sheet.contentView = container
		sheet.setContentSize(container.fittingSize)
		for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
		{
			sheet.standardWindowButton(kind)?.isHidden = true
		}
		panel = sheet
		inspection = Inspection(
			recordID: recordID,
			invocation: invocation
		)
		parent.beginSheet(sheet)
		{
			[weak self] _ in
			guard self?.panel === sheet
			else
			{
				return
			}
			self?.panel = nil
			self?.inspection = nil
			self?.copiedOutput = ""
		}
		sheet.makeFirstResponder(closeButton)
	}

	func dismiss()
	{
		guard let panel
		else
		{
			return
		}
		panel.sheetParent?.endSheet(panel)
		panel.orderOut(nil)
		self.panel = nil
		inspection = nil
		copiedOutput = ""
	}

	private func iconButton(
		_ icon: DesktopIcon,
		label: String,
		action: Selector
	) -> NSButton
	{
		let button = NSButton(
			title: "",
			target: self,
			action: action
		)
		button.image = DesktopIcons.image(icon)
		button.imagePosition = .imageOnly
		button.isBordered = false
		button.toolTip = label
		button.setAccessibilityLabel(label)
		button.widthAnchor.constraint(equalToConstant: 24).isActive = true
		button.heightAnchor.constraint(equalToConstant: 24).isActive = true
		return button
	}

	@objc private func close()
	{
		dismiss()
	}

	@objc private func copyOutput()
	{
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(
			copiedOutput,
			forType: .string
		)
	}
}

/// Keeps the raw-output action below each individual result, as in the reference.
@MainActor
final class SourceRawOutputEntryView: NSView
{
	private let onOpen: () -> Void

	init(
		card: NSView,
		id: String,
		onOpen: @escaping () -> Void
	)
	{
		self.onOpen = onOpen
		super.init(frame: .zero)
		let button = SourceRawOutputButton(
			title: "",
			target: self,
			action: #selector(openRawOutput)
		)
		button.imagePosition = .imageOnly
		button.isBordered = false
		button.contentTintColor = .secondaryLabelColor
		button.toolTip = "Show raw tool call output"
		button.setAccessibilityLabel("Show raw tool call output")
		button.identifier = NSUserInterfaceItemIdentifier("source-show-raw:\(id)")
		button.widthAnchor.constraint(equalToConstant: 24).isActive = true
		button.heightAnchor.constraint(equalToConstant: 24).isActive = true
		let actions = AppKitLayout.horizontalStack(
			[button, NSView()],
			spacing: 0
		)
		let stack = AppKitLayout.verticalStack(
			[card, actions],
			spacing: 4
		)
		AppKitLayout.pin(
			stack,
			to: self,
			inset: 0
		)
		card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		actions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
	}

	required init?(coder: NSCoder)
	{
		return nil
	}

	@objc private func openRawOutput()
	{
		onOpen()
	}
}

@MainActor
private final class SourceRawOutputButton: NSButton
{
	private var hoverArea: NSTrackingArea?
	private var isHovered = false
	private var isKeyboardFocused = false

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let hoverArea
		{
			removeTrackingArea(hoverArea)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [
				.mouseEnteredAndExited,
				.activeInKeyWindow,
				.inVisibleRect
			],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		hoverArea = area
		if let window, window.isKeyWindow
		{
			let point = convert(
				window.mouseLocationOutsideOfEventStream,
				from: nil
			)
			isHovered = !isHidden && visibleRect.contains(point)
		}
		else
		{
			isHovered = false
		}
		updateVisibility()
	}

	override func mouseEntered(with event: NSEvent)
	{
		isHovered = true
		updateVisibility()
	}

	override func mouseExited(with event: NSEvent)
	{
		isHovered = false
		updateVisibility()
	}

	override func becomeFirstResponder() -> Bool
	{
		let accepted = super.becomeFirstResponder()
		if accepted
		{
			isKeyboardFocused = true
			updateVisibility()
		}
		return accepted
	}

	override func resignFirstResponder() -> Bool
	{
		let accepted = super.resignFirstResponder()
		if accepted
		{
			isKeyboardFocused = false
			updateVisibility()
		}
		return accepted
	}

	private func updateVisibility()
	{
		image = isHovered || isKeyboardFocused ? DesktopIcons.image(
			.code,
			size: 12
		) : nil
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if isHovered
		{
			NSColor.quaternaryLabelColor.setFill()
			NSBezierPath(ovalIn: bounds.insetBy(
				dx: 1,
				dy: 1
			)).fill()
		}
		super.draw(dirtyRect)
	}
}
