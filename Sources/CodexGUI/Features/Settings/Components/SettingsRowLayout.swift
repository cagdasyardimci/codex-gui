import AppKit

@MainActor
enum SettingsRowLayout
{
	/// Settings rows reserve a right-aligned control column, including for switches.
	static func accessory(_ control: NSView) -> NSView
	{
		let container = NSView()
		control.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(control)
		NSLayoutConstraint.activate([
			control.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
			control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			control.topAnchor.constraint(equalTo: container.topAnchor),
			control.bottomAnchor.constraint(equalTo: container.bottomAnchor),
		])
		let preferredWidth = container.widthAnchor.constraint(equalToConstant: 160)
		preferredWidth.priority = NSLayoutConstraint.Priority(rawValue: 749)
		preferredWidth.isActive = true
		return container
	}

	static func install(
		labels: [NSView],
		control: NSView,
		in row: NSView
	)
	{
		let text = AppKitLayout.verticalStack(
			labels,
			spacing: 2
		)
		for label in labels
		{
			label.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
		}
		let accessory = Self.accessory(control)
		for view in [text, accessory]
		{
			view.translatesAutoresizingMaskIntoConstraints = false
			row.addSubview(view)
		}
		NSLayoutConstraint.activate([
			text.leadingAnchor.constraint(
				equalTo: row.leadingAnchor,
				constant: 16
			),
			text.topAnchor.constraint(
				equalTo: row.topAnchor,
				constant: 12
			),
			text.bottomAnchor.constraint(
				equalTo: row.bottomAnchor,
				constant: -12
			),
			accessory.leadingAnchor.constraint(
				equalTo: text.trailingAnchor,
				constant: 24
			),
			accessory.trailingAnchor.constraint(
				equalTo: row.trailingAnchor,
				constant: -16
			),
			accessory.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			row.heightAnchor.constraint(
				greaterThanOrEqualTo: accessory.heightAnchor,
				constant: 24
			),
		])
	}

}
