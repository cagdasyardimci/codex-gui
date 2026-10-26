import AppKit
import UniformTypeIdentifiers

/// Application destinations share the settings selector's drawing and choice-menu behavior.
@MainActor
final class SettingsEditorPicker: SettingsChoicePicker
{
	var onChooseEditor: (() -> Void)?
	var onSelectApplication: ((URL?) -> Void)?
	var onUseSystemDefault: (() -> Void)?
	private var application: URL?
	private var configured = false
	private var applications: [String: URL] = [:]
	private static let defaultID = "system-default"
	private static let chooseID = "choose-editor"

	init()
	{
		super.init(choices: [])
		menuWidth = 220
		setAccessibilityLabel("Preferred editor")
		onMenuWillOpen =
		{
			[weak self] in self?.rebuildChoices()
		}
		onSelect =
		{
			[weak self] id in
			guard let self
			else
			{
				return
			}
			if id == Self.chooseID
			{
				self.onChooseEditor?()
			}
			else
			{
				let url = self.applications[id]
				if let onSelectApplication = self.onSelectApplication
				{
					onSelectApplication(url)
				}
				else if id == Self.defaultID
				{
					self.onUseSystemDefault?()
				}
			}
		}
		setApplication(nil)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func setApplication(_ url: URL?)
	{
		guard !configured || application != url
		else
		{
			return
		}
		configured = true
		application = url
		rebuildChoices()
		toolTip = url?.path ?? "Use the system default application to open files"
	}

	private func rebuildChoices()
	{
		applications = [:]
		let installed = FileOpeningDestinations.installed()
		var choices = installed.filter
		{
			["VS Code", "Zed"].contains($0.title)
		}
		.map(applicationChoice)
		choices.append(Choice(
			id: Self.defaultID,
			title: "Default app",
			icon: NSWorkspace.shared.icon(for: .applicationBundle)
		))
		if let finder = NSWorkspace.shared
			.urlForApplication(withBundleIdentifier: "com.apple.finder")
		{
			choices.append(applicationChoice(FileOpeningDestination(
				title: "Finder",
				application: finder,
				opensFolder: true,
				icon: FileOpeningDestinations.menuIcon(for: finder)
			)))
		}
		choices += installed.filter
		{
			!["VS Code", "Zed"].contains($0.title)
		}
		.map(applicationChoice)
		if let application, applications[application.standardizedFileURL.absoluteString] == nil
		{
			choices.append(applicationChoice(FileOpeningDestination(
				title: application.deletingPathExtension().lastPathComponent,
				application: application,
				opensFolder: false,
				icon: FileOpeningDestinations.menuIcon(for: application)
			)))
		}
		choices.append(Choice(
			id: Self.chooseID,
			title: "Choose Editor…",
			icon: DesktopIcons.image(.folder)
		))
		setChoices(
			choices,
			selectedID: application?.standardizedFileURL.absoluteString ?? Self.defaultID
		)
	}

	private func applicationChoice(_ destination: FileOpeningDestination) -> Choice
	{
		let id = destination.application.standardizedFileURL.absoluteString
		applications[id] = destination.application
		return Choice(
			id: id,
			title: destination.title,
			icon: destination.icon
		)
	}
}
