import AppKit

/// The filename and its containing directory remain separate when the row is narrow.
@MainActor
final class ViewerFileSearchResultView: NSView
{
	let filenameLabel: NSTextField
	let directoryLabel: NSTextField

	init(relativePath: String)
	{
		let path = relativePath as NSString
		filenameLabel = NSTextField(labelWithString: path.lastPathComponent)
		let directory = path.deletingLastPathComponent
		directoryLabel = NSTextField(labelWithString: directory == "." || directory.isEmpty
			? "Top level" : directory)
		super.init(frame: .zero)

		let icon = NSImageView(image: WorkspaceFileIcon.image(relativePath: relativePath))
		icon.imageScaling = .scaleProportionallyDown
		icon.setContentHuggingPriority(
			.required,
			for: .horizontal
		)
		icon.setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
		filenameLabel.font = .systemFont(
			ofSize: 12,
			weight: .medium
		)
		filenameLabel.lineBreakMode = .byTruncatingMiddle
		filenameLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		directoryLabel.font = .systemFont(ofSize: 11)
		directoryLabel.textColor = .secondaryLabelColor
		directoryLabel.lineBreakMode = .byTruncatingMiddle
		directoryLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let labels = NSStackView(views: [filenameLabel, directoryLabel])
		labels.orientation = .vertical
		labels.alignment = .leading
		labels.spacing = 1
		labels.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let row = NSStackView(views: [icon, labels])
		row.orientation = .horizontal
		row.alignment = .centerY
		row.spacing = 8
		row.translatesAutoresizingMaskIntoConstraints = false
		addSubview(row)
		NSLayoutConstraint.activate([
			icon.widthAnchor.constraint(equalToConstant: 16),
			icon.heightAnchor.constraint(equalToConstant: 16),
			row.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 8
			),
			row.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -8
			),
			row.centerYAnchor.constraint(equalTo: centerYAnchor),
			labels.widthAnchor.constraint(
				lessThanOrEqualTo: row.widthAnchor,
				constant: -24
			),
		])
		setAccessibilityLabel(relativePath)
		toolTip = relativePath
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	/// Allows a containing button to receive clicks across the complete row.
	override func hitTest(_ point: NSPoint) -> NSView?
	{
		nil
	}
}
