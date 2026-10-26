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
		let button = DesktopStyledButton(
			icon: icon,
			label: label
		)
		button.target = self
		button.action = action
		button.toolTip = label
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
		let button = DesktopStyledButton(
			icon: .code,
			label: "Show raw tool call output",
			presentation: .revealingIcon
		)
		button.target = self
		button.action = #selector(openRawOutput)
		button.toolTip = "Show raw tool call output"
		button.identifier = NSUserInterfaceItemIdentifier("source-show-raw:\(id)")
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
