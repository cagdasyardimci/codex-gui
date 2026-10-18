import AppKit

struct FileOpeningDestination
{
	let title: String
	let application: URL
	let opensFolder: Bool
	let icon: NSImage
}

@MainActor
enum FileOpeningDestinations
{
	static func installed() -> [FileOpeningDestination]
	{
		let known: [(String, String, Bool)] = [
			("VS Code", "com.microsoft.VSCode", false),
			("Zed", "dev.zed.Zed", false),
			("Terminal", "com.apple.Terminal", true),
			("Kitty", "net.kovidgoyal.kitty", true),
			("Xcode", "com.apple.dt.Xcode", false),
		]
		return known.compactMap
		{
			title, bundleID, opensFolder in
			guard let application = NSWorkspace.shared.urlForApplication(
				withBundleIdentifier: bundleID
			), FileManager.default.fileExists(atPath: application.path)
			else
			{
				return nil
			}
			return FileOpeningDestination(
				title: title,
				application: application,
				opensFolder: opensFolder,
				icon: menuIcon(for: application)
			)
		}
	}

	static func menuIcon(for application: URL) -> NSImage
	{
		let image = NSWorkspace.shared.icon(forFile: application.path)
		image.size = NSSize(
			width: 16,
			height: 16
		)
		return image
	}
}
