import AppKit

/// A passive tab preview; it never changes selection or opens source content.
@MainActor
final class SourcesTabHoverPreview
{
	private let presentation = DesktopDelayedPresentation()
	private let preview = DesktopHoverPreview()

	@discardableResult
	func show(
		sources: ConversationLocalSources,
		below anchor: NSView
	) -> Task<Void, Never>
	{
		dismiss()
		return presentation.schedule(after: .milliseconds(250))
		{
			[weak self, weak anchor] in
			guard let self, let anchor,
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
		presentation.dismiss()
		preview.dismiss()
	}

	private func present(
		sources: ConversationLocalSources,
		below anchor: NSView,
		in window: NSWindow
	)
	{
		preview.present(
			content: makePreviewContent(sources),
			relativeTo: anchor,
			placement: .below
		)
	}

	private func makePreviewContent(_ sources: ConversationLocalSources) -> NSView
	{
		let resources = sources.records.filter
		{
			$0.kind != .tool && $0.kind != .web
		}
		let records = resources.isEmpty
			? Array(sources.records.prefix(5)) : Array(resources.suffix(5).reversed())
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
		return stack
	}

	private func makePreviewRow(_ record: ConversationLocalSources.Record) -> NSView
	{
		let badge: String
		switch record.kind
		{
		case .page: badge = "Read"
		case .tool, .web: badge = "Used"
		default: badge = "Attached"
		}
		return DesktopResourceRow(
			title: record.name,
			icon: DesktopIcons.image(
				record.summary.icon ?? .file,
				size: 14
			),
			presentation: .compact,
			badge: badge
		)
	}
}
