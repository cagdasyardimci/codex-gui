import AppKit

/// Displays inline attachments without creating files or treating their data URLs as paths.
@MainActor
final class UserMessageInlineImagePreview
{
	private var presentationTask: Task<Void, Never>?
	private var panel: NSPanel?
	private var generation = 0

	deinit
	{
		presentationTask?.cancel()
	}

	func present(
		_ reference: UserMessageReference,
		in parent: NSWindow
	)
	{
		dismiss()
		let generation = generation
		presentationTask = Task
		{
			[weak self, weak parent] in
			let thumbnail = await SourceThumbnailLoader.image(
				path: reference.path,
				maximumPixelSize: 1_600
			)
			guard !Task.isCancelled, let self, self.generation == generation,
					let parent, let thumbnail
			else
			{
				return
			}
			self.presentationTask = nil
			self.show(
				thumbnail,
				name: reference.name,
				in: parent
			)
		}
	}

	func dismiss()
	{
		generation += 1
		presentationTask?.cancel()
		presentationTask = nil
		if let panel
		{
			panel.parent?.removeChildWindow(panel)
			panel.orderOut(nil)
		}
		panel = nil
	}

	func waitForPresentation() async
	{
		await presentationTask?.value
	}

	private func show(
		_ thumbnail: SourceThumbnailLoader.Thumbnail,
		name: String,
		in parent: NSWindow
	)
	{
		let image = NSImage(
			cgImage: thumbnail.image,
			size: NSSize(
				width: thumbnail.image.width,
				height: thumbnail.image.height
			)
		)
		let imageView = NSImageView(image: image)
		imageView.imageScaling = .scaleProportionallyDown
		imageView.setAccessibilityLabel("Attached image: \(name)")
		let container = NSView()
		AppKitLayout.pin(
			imageView,
			to: container,
			inset: 20
		)
		let screen = parent.screen?.visibleFrame ?? parent.frame
		let size = NSSize(
			width: min(
				820,
				max(
					240,
					min(
						image.size.width + 40,
						screen.width - 80
					)
				)
			),
			height: min(
				620,
				max(
					180,
					min(
						image.size.height + 40,
						screen.height - 80
					)
				)
			)
		)
		let panel = NSPanel(
			contentRect: NSRect(
				origin: .zero,
				size: size
			),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		panel.title = name
		panel.setAccessibilityIdentifier("inline-image-preview")
		panel.isReleasedWhenClosed = false
		panel.contentView = container
		panel.setContentSize(size)
		panel.setFrameOrigin(NSPoint(
			x: parent.frame.midX - panel.frame.width / 2,
			y: parent.frame.midY - panel.frame.height / 2
		))
		self.panel = panel
		parent.addChildWindow(
			panel,
			ordered: .above
		)
		panel.orderFront(nil)
	}
}
