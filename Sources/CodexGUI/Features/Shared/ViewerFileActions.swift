import AppKit
import UniformTypeIdentifiers

/// Captures the file and its content source when a menu is made.
@MainActor
final class ViewerFileActions: NSObject
{
	struct Content
	{
		let text: (@MainActor @Sendable () async throws -> String)?
		let bytes: (@MainActor @Sendable () async throws -> Data)?
		let immediateText: String?

		init(
			text: (@MainActor @Sendable () async throws -> String)?,
			bytes: (@MainActor @Sendable () async throws -> Data)?,
			immediateText: String? = nil
		)
		{
			self.text = text
			self.bytes = bytes
			self.immediateText = immediateText
		}
	}

	let location: FileLocation
	let content: Content
	var onError: (String) -> Void
	var onOpenDestination: ((FileOpeningDestination) async throws -> Void)?
	var onOpenDefault: (() throws -> Void)?
	var onOpenPreferred: (() async throws -> String?)?
	var onReveal: (() -> Void)?
	var onOpenGitHub: (() async throws -> Void)?
	private let editor = EditorOpeningService()

	init(
		location: FileLocation,
		content: Content = Content(
			text: nil,
			bytes: nil
		),
		onError: @escaping (String) -> Void
	)
	{
		self.location = location
		self.content = content
		self.onError = onError
	}

	private final class Action: NSObject
	{
		let owner: ViewerFileActions
		let run: () -> Void

		init(
			owner: ViewerFileActions,
			run: @escaping () -> Void
		)
		{
			self.owner = owner
			self.run = run
		}
	}

	@discardableResult
	func add(
		_ title: String,
		to menu: NSMenu,
		enabled: Bool = true,
		image: NSImage? = nil,
		run: @escaping () -> Void
	) -> NSMenuItem
	{
		// Content availability is captured by the owner, not responder-chain validation.
		menu.autoenablesItems = false
		let item = NSMenuItem(
			title: title,
			action: #selector(runMenuAction(_:)),
			keyEquivalent: ""
		)
		item.target = self
		item.representedObject = Action(
			owner: self,
			run: run
		)
		item.isEnabled = enabled
		item.image = image
		menu.addItem(item)
		return item
	}

	@objc private func runMenuAction(_ sender: NSMenuItem)
	{
		guard sender.isEnabled,
				let action = sender.representedObject as? Action,
				action.owner === self
		else
		{
			return
		}
		action.run()
	}

	func addCopyPath(
		_ title: String,
		to menu: NSMenu
	)
	{
		let path = location.fileURL.path
		add(
			title,
			to: menu
		)
		{
			Self.copyText(path)
		}
	}

	func addContentActions(
		to menu: NSMenu,
		copyContentsTitle: String?,
		exportTitle: String?,
		in window: NSWindow?
	)
	{
		addCopyPath(
			"Copy path",
			to: menu
		)
		if let copyContentsTitle
		{
			addCopyContents(
				copyContentsTitle,
				to: menu
			)
		}
		if let exportTitle
		{
			addExport(
				exportTitle,
				to: menu,
				in: window
			)
		}
	}

	func addExternalOpenActions(
		to menu: NSMenu,
		preferredTitle: String,
		openWithTitle: String,
		revealTitle: String,
		in window: NSWindow?,
		beforeReveal: ((NSMenu) -> Void)? = nil
	)
	{
		menu.addItem(.separator())
		addPreferred(
			preferredTitle,
			to: menu
		)
		addOpenWith(
			openWithTitle,
			to: menu,
			in: window
		)
		beforeReveal?(menu)
		addReveal(
			revealTitle,
			to: menu
		)
	}

	func addCopyContents(
		_ title: String,
		to menu: NSMenu
	)
	{
		add(
			title,
			to: menu,
			enabled: content.text != nil
		)
		{
			if let text = self.content.immediateText
			{
				Self.copyText(text)
				return
			}
			Task
			{
				await self.copyContents()
			}
		}
	}

	func addExport(
		_ title: String,
		to menu: NSMenu,
		in window: NSWindow?
	)
	{
		add(
			title,
			to: menu,
			enabled: content.bytes != nil
		)
		{
			Task
			{
				await self.export(in: window)
			}
		}
	}

	func addDefault(
		_ title: String,
		to menu: NSMenu
	)
	{
		let item = add(
			title,
			to: menu
		)
		{
			do
			{
				if let onOpenDefault = self.onOpenDefault
				{
					try onOpenDefault()
				}
				else
				{
					try self.editor.openWithDefault(
						path: self.location.relativePath,
						project: URL(fileURLWithPath: self.location.root)
					)
				}
			}
			catch
			{
				self.onError(error.localizedDescription)
			}
		}
		if let application = NSWorkspace.shared.urlForApplication(toOpen: location.fileURL)
		{
			item.image = FileOpeningDestinations.menuIcon(for: application)
		}
	}

	func addDestination(
		_ destination: FileOpeningDestination,
		to menu: NSMenu
	)
	{
		add(
			destination.title,
			to: menu,
			image: destination.icon
		)
		{
			Task
			{
				do
				{
					if let onOpenDestination = self.onOpenDestination
					{
						try await onOpenDestination(destination)
					}
					else if destination.opensFolder
					{
						try await self.editor.openFolder(
							path: self.location.relativePath,
							project: URL(fileURLWithPath: self.location.root),
							withApplicationAt: destination.application
						)
					}
					else
					{
						try await self.editor.open(
							path: self.location.relativePath,
							project: URL(fileURLWithPath: self.location.root),
							withApplicationAt: destination.application
						)
					}
				}
				catch
				{
					self.onError(error.localizedDescription)
				}
			}
		}
	}

	func addPreferred(
		_ title: String,
		to menu: NSMenu
	)
	{
		add(
			title,
			to: menu
		)
		{
			self.openPreferred()
		}
	}

	func openPreferred()
	{
		Task
		{
			do
			{
				let message: String?
				if let onOpenPreferred = self.onOpenPreferred
				{
					message = try await onOpenPreferred()
				}
				else
				{
					message = try await self.editor.open(
						path: self.location.relativePath,
						project: URL(fileURLWithPath: self.location.root),
						line: 1
					)
				}
				if let message
				{
					self.onError(message)
				}
			}
			catch
			{
				self.onError(error.localizedDescription)
			}
		}
	}

	func addOpenWith(
		_ title: String,
		to menu: NSMenu,
		in window: NSWindow?
	)
	{
		add(
			title,
			to: menu
		)
		{
			let panel = NSOpenPanel()
			panel.allowedContentTypes = [.application]
			panel.canChooseDirectories = false
			panel.canChooseFiles = true
			let finish: (NSApplication.ModalResponse) -> Void =
			{
				response in
				guard response == .OK, let application = panel.url
				else
				{
					return
				}
				Task
				{
					do
					{
						try await self.editor.open(
							path: self.location.relativePath,
							project: URL(fileURLWithPath: self.location.root),
							withApplicationAt: application
						)
					}
					catch
					{
						self.onError(error.localizedDescription)
					}
				}
			}
			if let window
			{
				panel.beginSheetModal(
					for: window,
					completionHandler: finish
				)
			}
			else
			{
				panel.begin(completionHandler: finish)
			}
		}
	}

	func addReveal(
		_ title: String,
		to menu: NSMenu
	)
	{
		add(
			title,
			to: menu
		)
		{
			if let onReveal = self.onReveal
			{
				onReveal()
			}
			else
			{
				NSWorkspace.shared.activateFileViewerSelecting([self.location.fileURL])
			}
		}
	}

	func addGitHub(
		_ title: String,
		to menu: NSMenu
	)
	{
		add(
			title,
			to: menu,
			enabled: onOpenGitHub != nil
		)
		{
			Task
			{
				do
				{
					try await self.onOpenGitHub?()
				}
				catch
				{
					self.onError(error.localizedDescription)
				}
			}
		}
	}

	func loadExportBytes() async throws -> Data?
	{
		try await content.bytes?()
	}

	private func copyContents() async
	{
		do
		{
			guard let text = try await content.text?()
			else
			{
				return
			}
			Self.copyText(text)
		}
		catch
		{
			onError(error.localizedDescription)
		}
	}

	private func export(in window: NSWindow?) async
	{
		let data: Data
		do
		{
			guard let loaded = try await loadExportBytes()
			else
			{
				return
			}
			data = loaded
		}
		catch
		{
			onError(error.localizedDescription)
			return
		}
		let panel = NSSavePanel()
		panel.nameFieldStringValue = location.fileURL.lastPathComponent
		let finish: (NSApplication.ModalResponse) -> Void =
		{
			response in
			guard response == .OK, let destination = panel.url
			else
			{
				return
			}
			Task
			{
				let result = await Task.detached(priority: .userInitiated)
				{
					Result
					{
						try data.write(
							to: destination,
							options: .atomic
						)
					}
				}.value
				if case .failure(let error) = result
				{
					self.onError(error.localizedDescription)
				}
			}
		}
		if let window
		{
			panel.beginSheetModal(
				for: window,
				completionHandler: finish
			)
		}
		else
		{
			panel.begin(completionHandler: finish)
		}
	}

	static func hasWorkspaceFile(_ location: FileLocation) -> Bool
	{
		let root = URL(fileURLWithPath: location.root).resolvingSymlinksInPath()
		let file = location.fileURL.standardizedFileURL.resolvingSymlinksInPath()
		let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
		var isDirectory: ObjCBool = false
		return file.path.hasPrefix(prefix)
			&& FileManager.default.fileExists(
				atPath: file.path,
				isDirectory: &isDirectory
			)
			&& !isDirectory.boolValue
	}

	static func copyText(_ value: String)
	{
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(
			value,
			forType: .string
		)
	}

	static func presentError(
		_ message: String,
		in window: NSWindow?
	)
	{
		let alert = NSAlert()
		alert.messageText = "File action failed"
		alert.informativeText = message
		if let window
		{
			alert.beginSheetModal(for: window)
		}
		else
		{
			alert.runModal()
		}
	}
}
