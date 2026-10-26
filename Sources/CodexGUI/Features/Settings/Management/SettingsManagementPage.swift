import AppKit

/// Settings management requests stay scoped to the visible page and never replay mutations.
@MainActor
class SettingsManagementPage: NSView
{
	let backend: SettingsBackend
	let pageTitle: String
	var rows: [NSView] = []
	var message = ""
	private var reloadPending = false
	private var loaded = false
	private var switchActions: [SettingsManagementSwitchAction] = []
	private(set) var operation: Task<Void, Never>?
	private var generation = UUID()
	var displayTitle: String
	{
		pageTitle
	}
	var showsRefresh: Bool
	{
		true
	}
	var pageSubtitle: String?
	{
		nil
	}
	var headerAccessory: NSView?
	{
		nil
	}
	var subtitleView: NSView?
	{
		nil
	}
	var headerSpacing: SettingsPageDocument.HeaderSpacing
	{
		.standard
	}
	var isOperating: Bool
	{
		operation != nil
	}

	init(
		title: String,
		backend: SettingsBackend
	)
	{
		self.backend = backend
		pageTitle = title
		super.init(frame: .zero)
		render()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if newWindow == nil
		{
			invalidateLoad()
		}
		super.viewWillMove(toWindow: newWindow)
	}

	func invalidateLoad()
	{
		generation = UUID()
		operation?.cancel()
		operation = nil
		loaded = false
		reloadPending = false
	}

	func refresh()
	{
		guard !loaded, !backend.isBusy, backend.isConnected
		else
		{
			return
		}
		loaded = true
		load()
	}

	func load()
	{
	}

	func run(_ work: @escaping @MainActor () async throws -> Void)
	{
		guard operation == nil
		else
		{
			return
		}
		let identity = generation
		message = "Loading…"
		operation = Task
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			do
			{
				try await work()
				guard identity == generation, !Task.isCancelled
				else
				{
					return
				}
				message = ""
			}
			catch
			{
				guard identity == generation, !Task.isCancelled
				else
				{
					return
				}
				message = error.localizedDescription
			}
			operation = nil
			render()
			if reloadPending
			{
				reloadPending = false
				load()
			}
		}
		render()
	}

	func reloadAfterOperation()
	{
		reloadPending = true
	}

	func render()
	{
		for child in subviews
		{
			child.removeFromSuperview()
		}
		switchActions.removeAll
		{
			!$0.isAlive
		}
		AppKitLayout.pin(
			SettingsPageLayout.document(
				title: displayTitle,
				sections: sectionsForDisplay(),
				headerAccessory: headerAccessory,
				subtitle: pageSubtitle,
				subtitleView: subtitleView,
				headerSpacing: headerSpacing
			),
			to: self,
			inset: 0
		)
	}

	func sectionsForDisplay() -> [NSView]
	{
		let reload = button("Refresh")
		{
			[weak self] in self?.load()
		}
		reload.isEnabled = operation == nil
		var sections: [NSView] = showsRefresh ? [SettingsPageLayout.row(
			title: pageTitle,
			detail: nil,
			control: reload
		)] : []
		if !backend.status.isEmpty
		{
			sections.append(SettingsPageLayout.status(backend.status))
		}
		if !message.isEmpty
		{
			sections.append(SettingsPageLayout.status(message))
		}
		if !rows.isEmpty
		{
			sections.append(SettingsPageLayout.section(
				title: "",
				rows: rows
			))
		}
		return sections
	}

	func button(
		_ title: String,
		presentation: DesktopStyledButton.Presentation? = nil,
		action: @escaping () -> Void
	) -> NSButton
	{
		let button = DesktopActionButton(
			title: title,
			presentation: presentation
				?? (["Delete", "Uninstall", "Remove"].contains(title) ? .destructive : .secondary),
			action: action
		)
		return button
	}

	func toggle(
		_ label: String,
		enabled: Bool,
		action: @escaping (Bool) -> Void
	) -> NSView
	{
		switchActions.removeAll
		{
			!$0.isAlive
		}
		let control = DesktopSwitch()
		let handler = SettingsManagementSwitchAction(
			control: control,
			action: action
		)
		switchActions.append(handler)
		control.target = handler
		control.action = #selector(SettingsManagementSwitchAction.invoke)
		control.state = enabled ? .on : .off
		control.setAccessibilityLabel(label)
		return control
	}

	func confirm(
		_ title: String,
		detail: String,
		action: @escaping () -> Void
	)
	{
		guard let window
		else
		{
			return
		}
		let confirmation = DesktopNativeConfirmation(
			title: title,
			message: detail,
			confirmTitle: title
		)
		confirmation.beginSheet(in: window)
		{
			confirmed in
			if confirmed, self.window === window
			{
				action()
			}
		}
	}

	func prompt(
		_ title: String,
		fields: [(String, String)],
		action: @escaping ([String]) -> Void
	)
	{
		guard let window
		else
		{
			return
		}
		let prompt = DesktopTextEntryPrompt(
			title: title,
			actionTitle: "Save",
			fields: fields.map
			{
				name, value in
				DesktopTextEntryPrompt.Field(
					value: value,
					placeholder: name,
					accessibilityLabel: name
				)
			},
			layout: .multiple
		)
		prompt.beginSheet(in: window)
		{
			values in
			if let values, self.window === window
			{
				action(values)
			}
		}
	}

	func controls(_ views: [NSView]) -> NSView
	{
		let stack = NSStackView(views: views)
		stack.orientation = .horizontal
		stack.spacing = 8
		return stack
	}
}

@MainActor
private final class SettingsManagementSwitchAction: NSObject
{
	private weak var control: DesktopSwitch?
	var isAlive: Bool
	{
		control != nil
	}
	private let callback: (Bool) -> Void
	init(
		control: DesktopSwitch,
		action: @escaping (Bool) -> Void
	)
	{
		self.control = control
		callback = action
	}
	@objc func invoke()
	{
		guard let control
		else
		{
			return
		}
		let value = control.state == .on
		control.state = value ? .off : .on
		callback(value)
	}
}
