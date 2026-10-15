import AppKit

/// A passive tab preview; it never changes selection or opens source content.
@MainActor
final class SourcesTabHoverPreview
{
	private var pendingShow: Task<Void, Never>?
	private var previewWindow: NSPanel?
	private weak var parentWindow: NSWindow?
	private var appearanceBinding: DesktopPanelAppearanceBinding?

	@discardableResult
	func show(
		sources: ConversationLocalSources,
		below anchor: NSView
	) -> Task<Void, Never>
	{
		dismiss()
		let operation = Task
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
		// Callers that need a settled presentation can await this exact operation,
		// including after dismissal cancels and retires the stored handle.
		pendingShow = operation
		return operation
	}

	func dismiss()
	{
		pendingShow?.cancel()
		pendingShow = nil
		appearanceBinding?.invalidate()
		appearanceBinding = nil
		if let previewWindow
		{
			parentWindow?.removeChildWindow(previewWindow)
			previewWindow.orderOut(nil)
		}
		previewWindow = nil
		parentWindow = nil
	}

	private enum Layout
	{
		static let minimumPreviewWidth: CGFloat = 180
		static let maximumPreviewWidth: CGFloat = 320
		static let screenWidthAllowance: CGFloat = 20
		static let screenMargin: CGFloat = 8
		static let anchorSpacing: CGFloat = 3
	}

	private func present(
		sources: ConversationLocalSources,
		below anchor: NSView,
		in window: NSWindow
	)
	{
		let content = makePreviewContent(sources)
		let frame = measurePreviewFrame(
			content: content,
			below: anchor,
			in: window
		)
		let panel = makePreviewPanel(
			content: content,
			frame: frame
		)

		parentWindow = window
		previewWindow = panel
		appearanceBinding = DesktopPanelAppearanceBinding(
			panel: panel,
			source: anchor
		)
		window.addChildWindow(
			panel,
			ordered: .above
		)
		panel.orderFront(nil)
	}

	private func makePreviewContent(_ sources: ConversationLocalSources) -> SourcesTabPreviewContent
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
			let row = makePreviewRow(record)
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
		return content
	}

	private func makePreviewRow(_ record: ConversationLocalSources.Record) -> NSStackView
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
		return row
	}

	private func measurePreviewFrame(
		content: NSView,
		below anchor: NSView,
		in window: NSWindow
	) -> NSRect
	{
		let screen = window.screen?.visibleFrame ?? window.frame
		let previewWidth = min(
			Layout.maximumPreviewWidth,
			max(
				Layout.minimumPreviewWidth,
				screen.width - Layout.screenWidthAllowance
			)
		)
		content.widthAnchor.constraint(equalToConstant: previewWidth).isActive = true
		content.layoutSubtreeIfNeeded()
		let previewHeight = ceil(content.fittingSize.height)
		let tabRect = window.convertToScreen(anchor.convert(
			anchor.bounds,
			to: nil
		))
		let previewOriginX = min(
			max(
				tabRect.minX,
				screen.minX + Layout.screenMargin
			),
			screen.maxX - previewWidth - Layout.screenMargin
		)
		let previewOriginY = max(
			screen.minY + Layout.screenMargin,
			tabRect.minY - previewHeight - Layout.anchorSpacing
		)
		return NSRect(
			x: previewOriginX,
			y: previewOriginY,
			width: previewWidth,
			height: previewHeight
		)
	}

	private func makePreviewPanel(
		content: NSView,
		frame: NSRect
	) -> NSPanel
	{
		let panel = NSPanel(
			contentRect: frame,
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
		panel.contentView = content
		panel.setFrame(
			frame,
			display: false
		)
		return panel
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
