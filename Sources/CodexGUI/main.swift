import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
let iconURL = Bundle.main.url(
	forResource: "AppIcon",
	withExtension: "icns"
)
	?? Bundle.module.url(
		forResource: "AppIcon",
		withExtension: "icns"
	)
if let iconURL,
	let icon = NSImage(contentsOf: iconURL)
{
	application.applicationIconImage = icon
}
application.run()
