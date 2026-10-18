import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct ViewerSearchFieldTests
{
	@Test func searchTextAndNativeEditorFitBetweenSearchAndClearIcons() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let field = ViewerSearchField()
			field.stringValue = "file name"
			field.setAccessibilityLabel("Filter files")
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 360,
					height: 60
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			let host = NSView()
			window.contentView = host
			host.addSubview(field)
			defer
			{
				window.close()
			}
			for appearance in [NSAppearance.Name.aqua, .darkAqua, .aqua]
			{
				window.appearance = NSAppearance(named: appearance)
				for width in [CGFloat(150), 340]
				{
					field.frame = NSRect(
						x: 10,
						y: 10,
						width: width,
						height: 28
					)
					let cell = try #require(field.cell as? NSSearchFieldCell)
					let text = cell.searchTextRect(forBounds: field.bounds)
					let icon = cell.searchButtonRect(forBounds: field.bounds)
					let clear = cell.cancelButtonRect(forBounds: field.bounds)
					#expect(text.width > 0)
					#expect(text.minX >= icon.maxX)
					#expect(text.maxX <= clear.minX)
					#expect(abs(text.midY - icon.midY) <= 0.5)
					#expect(window.makeFirstResponder(field))
					let editor = try #require(field.currentEditor())
					#expect(editor.string == "file name")
					#expect(field.accessibilityLabel() == "Filter files")
					#expect(window.makeFirstResponder(nil))
				}
				if let directory = ProcessInfo.processInfo.environment["CODEX_FILES_QA_DIR"]
				{
					try AppTestPNGWriter.write(
						host,
						to: URL(fileURLWithPath: directory)
							.appendingPathComponent("search-field-\(appearance.rawValue).png")
					)
				}
			}
		}
	}
}
