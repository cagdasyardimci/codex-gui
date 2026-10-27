import AppKit

@MainActor
final class SettingsMCPForm: NSView
{
	var onCancel: (() -> Void)?
	var onSave: ((String, [String: Any]) -> Void)?
	private let name = SettingsFormField(
		title: "Name",
		presentation: .nativeRounded
	)
	private let endpoint = SettingsFormField(
		title: "Command or URL",
		presentation: .nativeRounded
	)
	private let arguments = SettingsFormEntriesField(
		format: .lines,
		item: "argument",
		addTitle: "Add argument"
	)
	private let environment = SettingsFormEntriesField(
		format: .pairs,
		item: "environment variable",
		addTitle: "Add environment variable"
	)
	private let environmentPassthrough = SettingsFormEntriesField(
		format: .lines,
		item: "passthrough variable",
		addTitle: "Add variable"
	)
	private let workingDirectory = SettingsFormField(
		title: "Working directory",
		presentation: .nativeRounded
	)
	private let bearerTokenEnvironmentVariable = SettingsFormField(
		title: "Bearer token env var",
		presentation: .nativeRounded
	)
	private let headers = SettingsFormEntriesField(
		format: .pairs,
		item: "header",
		addTitle: "Add header"
	)
	private let environmentHeaders = SettingsFormEntriesField(
		format: .pairs,
		item: "environment header",
		addTitle: "Add variable"
	)
	private let save = DesktopStyledButton(
		title: "Save",
		presentation: .primary
	)
	private let fields = NSStackView()
	private var fieldWidths: [NSLayoutConstraint] = []
	private var transport = "STDIO"
	private var original: [String: Any]
	private var initialName: String?

	init(
		name: String?,
		configuration: [String: Any]
	)
	{
		initialName = name
		original = configuration
		super.init(frame: .zero)
		self.name.stringValue = name ?? ""
		self.name.isEditable = name == nil
		transport = configuration["url"] is String ? "HTTP" : "STDIO"
		endpoint.stringValue = configuration["url"] as? String
			?? configuration["command"] as? String ?? ""
		arguments.stringValue = (configuration["args"] as? [String] ?? []).joined(separator: "\n")
		environment.stringValue = Self.pairText(configuration["env"])
		environmentPassthrough.stringValue = (configuration["env_vars"] as? [String] ?? [])
			.joined(separator: "\n")
		workingDirectory.stringValue = configuration["cwd"] as? String ?? ""
		bearerTokenEnvironmentVariable.stringValue =
			configuration["bearer_token_env_var"] as? String ?? ""
		headers.stringValue = Self.pairText(configuration["http_headers"])
		environmentHeaders.stringValue = Self.pairText(configuration["env_http_headers"])
		for field in [self.name, endpoint, workingDirectory, bearerTokenEnvironmentVariable]
		{
			field.onChange =
			{
				[weak self] _ in self?.validate()
			}
		}

		for entries in [
			arguments,
			environment,
			environmentPassthrough,
			headers,
			environmentHeaders,
		]
		{
			entries.onChange =
			{
				[weak self] in self?.validate()
			}
		}
		fields.orientation = .vertical
		fields.alignment = .leading
		fields.spacing = 16
		AppKitLayout.pin(
			fields,
			to: self,
			inset: 12
		)
		save.target = self
		save.action = #selector(submit)
		save.keyEquivalent = "\r"
		buildFields()
	}
	required init?(coder: NSCoder)
	{
		nil
	}

	private static func pairText(_ value: Any?) -> String
	{
		let pairs = value as? [String: String] ?? [:]
		return pairs.keys.sorted().map
		{
			"\($0)=\(pairs[$0]!)"
		}.joined(separator: "\n")
	}

	private func buildFields()
	{
		NSLayoutConstraint.deactivate(fieldWidths)
		fieldWidths.removeAll()
		for view in fields
			.arrangedSubviews
		{
			fields.removeArrangedSubview(view); view.removeFromSuperview()
		}
		let back = DesktopStyledButton(
			title: "Back",
			presentation: .secondary
		)
		back.target = self
		back.action = #selector(cancel)
		fields.addArrangedSubview(back)
		let tabs = SettingsManagementTabs(
			titles: ["STDIO", "Streamable HTTP"],
			selected: transport == "HTTP" ? "Streamable HTTP" : "STDIO"
		)
		{
			[weak self] selected in
			guard let self
			else
			{
				return
			}
			let next = selected == "STDIO" ? "STDIO" : "HTTP"
			guard transport != next
			else
			{
				return
			}
			transport = next
			endpoint.stringValue = ""
			buildFields()
		}
		fields.addArrangedSubview(tabs)
		addField(
			"Name",
			field: name
		)
		addField(
			transport == "HTTP" ? "URL" : "Command to launch",
			field: endpoint
		)
		if transport == "HTTP"
		{
			addField(
				"Bearer token env var",
				field: bearerTokenEnvironmentVariable
			)
			addField(
				"Headers",
				field: headers
			)
			addField(
				"Headers from environment variables",
				field: environmentHeaders
			)
		}
		else
		{
			addField(
				"Arguments",
				field: arguments
			)
			addField(
				"Environment variables",
				field: environment
			)
			addField(
				"Environment variable passthrough",
				field: environmentPassthrough
			)
			addField(
				"Working directory",
				field: workingDirectory
			)
		}
		let cancel = DesktopStyledButton(
			title: "Cancel",
			presentation: .secondary
		)
		cancel.target = self
		cancel.action = #selector(self.cancel)
		cancel.keyEquivalent = "\u{1b}"
		let actions = NSStackView(views: [cancel, save])
		actions.orientation = .horizontal
		actions.spacing = 8
		fields.addArrangedSubview(actions)
		validate()
	}

	private func addField(
		_ title: String,
		field: NSView
	)
	{
		let component: SettingsFormField
		if let existing = field as? SettingsFormField
		{
			existing.title = title
			component = existing
		}
		else
		{
			component = SettingsFormField(
				title: title,
				content: field
			)
		}
		fields.addArrangedSubview(component)
		let width = component.widthAnchor.constraint(equalTo: fields.widthAnchor)
		width.isActive = true
		fieldWidths.append(width)
	}

	private var draft: SettingsMCPDraft
	{
		SettingsMCPDraft(
			name: name.stringValue,
			transport: transport,
			endpoint: endpoint.stringValue,
			arguments: arguments.stringValue,
			environment: environment.stringValue,
			headers: headers.stringValue,
			original: original,
			environmentPassthrough: environmentPassthrough.stringValue,
			workingDirectory: workingDirectory.stringValue,
			bearerTokenEnvironmentVariable: bearerTokenEnvironmentVariable.stringValue,
			environmentHeaders: environmentHeaders.stringValue
		)
	}

	private func validate()
	{
		do
		{
			_ = try draft.configuration(); save.isEnabled = true
		}
		catch
		{
			save.isEnabled = false
		}
	}
	@objc private func submit()
	{
		do
		{
			onSave?(name.stringValue, try draft.configuration())
		}
		catch
		{
		}
	}
	@objc private func cancel()
	{
		onCancel?()
	}
}
