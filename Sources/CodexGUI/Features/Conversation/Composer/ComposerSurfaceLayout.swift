import AppKit

/// Both rows stay inside the stack even when the footer has a larger inset than the editor.
@MainActor
enum ComposerSurfaceLayout
{
	static func install(
		in surface: NSView,
		attachments: NSView,
		editor: NSView,
		footer: NSView,
		metrics: LayoutTokens.Composer = LayoutTokens.composer
	)
	{
		precondition(
			metrics.isValid,
			"Invalid composer surface metrics"
		)
		let stack = AppKitLayout.verticalStack(
			[attachments, editor, footer],
			spacing: LayoutTokens.Composer.editorFooterSpacing
		)
		stack.alignment = .centerX
		stack.translatesAutoresizingMaskIntoConstraints = false
		surface.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(
				equalTo: surface.leadingAnchor,
				constant: metrics.stackHorizontalInset
			),
			stack.trailingAnchor.constraint(
				equalTo: surface.trailingAnchor,
				constant: -metrics.stackHorizontalInset
			),
			stack.topAnchor.constraint(
				equalTo: surface.topAnchor,
				constant: LayoutTokens.Composer.topInset
			),
			stack.bottomAnchor.constraint(
				equalTo: surface.bottomAnchor,
				constant: -LayoutTokens.Composer.bottomInset
			),
			footer.widthAnchor.constraint(
				equalTo: stack.widthAnchor,
				constant: metrics.nestedFooterWidthAdjustment
			),
		])
		for row in [attachments, editor]
		{
			row.widthAnchor.constraint(
				equalTo: stack.widthAnchor,
				constant: metrics.nestedEditorWidthAdjustment
			)
			.isActive = true
		}
	}
}
