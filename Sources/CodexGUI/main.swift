import AppKit

@MainActor
final class ScaffoldDelegate: NSObject, NSApplicationDelegate
{
	private var window: NSWindow?

	func applicationDidFinishLaunching(_ notification: Notification)
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 1200,
				height: 760
			),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.title = "Codex GUI"
		window.center()
		window.makeKeyAndOrderFront(nil)
		self.window = window
		NSApp.activate(ignoringOtherApps: true)
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool
	{
		true
	}
}

let application = NSApplication.shared
let delegate = ScaffoldDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
