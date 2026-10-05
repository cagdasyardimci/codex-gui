import AppKit

/// A passive tab preview; it never changes selection or opens source content.
@MainActor
final class SourcesTabHoverPreview
{
	private var pendingShow: Task<Void, Never>?
	private var previewWindow: NSPanel?
	private weak var parentWindow: NSWindow?

	func show(
		sources: ConversationLocalSources,
		below anchor: NSView
	)
	{
		dismiss()
		pendingShow = Task
		{
			[weak self, weak anchor] in
			try? await Task.sleep(for: .milliseconds(250))
			guard !Task.isCancelled, let self, let anchor,
					let window = anchor.window, window.isKeyWindow, !anchor.isHidden
			else
			{
				return
			}
			self.present(
				sources: sources,
				below: anchor,
				in: window
			)
		}
	}

	func dismiss()
	{
		pendingShow?.cancel()
		pendingShow = nil
		if let previewWindow
		{
			parentWindow?.removeChildWindow(previewWindow)
			previewWindow.orderOut(nil)
		}
		previewWindow = nil
		parentWindow = nil
	}

	private func present(
		sources: ConversationLocalSources,
		below anchor: NSView,
		in window: NSWindow
	)
	{
		let resources = sources.records.filter
		{
			$0.kind != .tool && $0.kind != .web
		}
		let records = resources.isEmpty
			? Array(sources.records.prefix(5)) : Array(resources.suffix(5).reversed())
		let content = SourcesTabPreviewContent()
		let title = NSTextField(labelWithString: "Sources")
		title.font = .systemFont(
			ofSize: 13,
			weight: .medium
		)
		let count = NSTextField(labelWithString:
			"\(sources.records.count) \(sources.records.count == 1 ? "source" : "sources")")
		count.font = .systemFont(ofSize: 12)
		count.textColor = .secondaryLabelColor
		let stack = AppKitLayout.verticalStack(
			[title, count],
			spacing: 6
		)
		stack.setCustomSpacing(
			16,
			after: count
		)
		for record in records
		{
			let icon = NSImageView(image: DesktopIcons.image(
				record.summary.icon ?? .file,
				size: 14
			))
			icon.contentTintColor = .secondaryLabelColor
			icon.setAccessibilityElement(false)
			let name = NSTextField(labelWithString: record.name)
			name.font = .systemFont(ofSize: 13)
			name.lineBreakMode = .byTruncatingTail
			name.setContentCompressionResistancePriority(
				.defaultLow,
				for: .horizontal
			)
			let badgeText: String
			switch record.kind
			{
			case .page: badgeText = "Read"
			case .tool, .web: badgeText = "Used"
			default: badgeText = "Attached"
			}
			let badge = NSTextField(labelWithString: badgeText)
			badge.font = .systemFont(ofSize: 12)
			badge.textColor = .secondaryLabelColor
			badge.setContentCompressionResistancePriority(
				.required,
				for: .horizontal
			)
			let row = AppKitLayout.horizontalStack(
				[icon, name, badge],
				spacing: 10
			)
			row.heightAnchor.constraint(equalToConstant: 26).isActive = true
			icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
			icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
			stack.addArrangedSubview(row)
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		if records.isEmpty
		{
			let empty = NSTextField(labelWithString: "No sources in loaded conversation history")
			empty.font = .systemFont(ofSize: 12)
			empty.textColor = .secondaryLabelColor
			stack.addArrangedSubview(empty)
		}
		AppKitLayout.pin(
			stack,
			to: content,
			inset: 10
		)
		let screen = window.screen?.visibleFrame ?? window.frame
		let width = min(
			320,
			max(
				180,
				screen.width - 20
			)
		)
		content.widthAnchor.constraint(equalToConstant: width).isActive = true
		content.layoutSubtreeIfNeeded()
		let height = ceil(content.fittingSize.height)
		let tabRect = window.convertToScreen(anchor.convert(
			anchor.bounds,
			to: nil
		))
		let x = min(
			max(
				tabRect.minX,
				screen.minX + 8
			),
			screen.maxX - width - 8
		)
		let y = max(
			screen.minY + 8,
			tabRect.minY - height - 3
		)
		let panel = NSPanel(
			contentRect: NSRect(
				x: x,
				y: y,
				width: width,
				height: height
			),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		panel.hidesOnDeactivate = true
		panel.ignoresMouseEvents = true
		panel.isReleasedWhenClosed = false
		panel.appearance = window.effectiveAppearance
		panel.contentView = content
		panel.setFrame(
			NSRect(
				x: x,
				y: y,
				width: width,
				height: height
			),
			display: false
		)
		parentWindow = window
		previewWindow = panel
		window.addChildWindow(
			panel,
			ordered: .above
		)
		panel.orderFront(nil)
	}
}

@MainActor
private final class SourcesTabPreviewContent: NSView
{
	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.cornerRadius = 12
		updateColors()
	}

	required init?(coder: NSCoder)
	{
		return nil
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		updateColors()
	}

	private func updateColors()
	{
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
		}
	}
}
