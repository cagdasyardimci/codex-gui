import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct ViewerFileActionsTests
{
	@Test func sharedMenuRecipePreservesContentAndOpenOrder() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let actions = ViewerFileActions(
				location: FileLocation(
					root: "/tmp",
					relativePath: "sample.md"
				),
				content: .init(
					text:
					{
						"first\r\nsecond"
					},
					bytes:
					{
						Data("first\r\nsecond".utf8)
					},
					immediateText: "first\r\nsecond"
				),
				onError:
				{
					_ in
				}
			)
			let menu = NSMenu(title: "File actions")
			actions.addContentActions(
				to: menu,
				copyContentsTitle: "Copy Markdown",
				exportTitle: "Save As…",
				in: nil
			)
			actions.addExternalOpenActions(
				to: menu,
				preferredTitle: "Open in preferred editor",
				openWithTitle: "Open with…",
				revealTitle: "Reveal in Finder",
				in: nil
			)
			#expect(menu.items.map(\.title) == [
				"Copy path",
				"Copy Markdown",
				"Save As…",
				"",
				"Open in preferred editor",
				"Open with…",
				"Reveal in Finder",
			])
			let copy = try #require(menu.item(withTitle: "Copy Markdown"))
			#expect(NSApp.sendAction(
				try #require(copy.action),
				to: copy.target,
				from: copy
			))
			#expect(NSPasteboard.general.string(forType: .string) == "first\r\nsecond")
		}
	}

	@Test func menuKeepsCapturedPathAndExactTextWhenAnotherMenuIsMade() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let original = "first\r\nsecond\n"
			let first = ViewerFileActions(
				location: FileLocation(
					root: "/tmp",
					relativePath: "first.md"
				),
				content: .init(
					text:
					{
						original
					},
					bytes:
					{
						Data(original.utf8)
					},
					immediateText: original
				),
				onError:
				{
					_ in
				}
			)
			let firstMenu = NSMenu(title: "Actions")
			first.addCopyPath(
				"Copy path",
				to: firstMenu
			)
			first.addCopyContents(
				"Copy contents",
				to: firstMenu
			)
			let second = ViewerFileActions(
				location: FileLocation(
					root: "/tmp",
					relativePath: "second.md"
				),
				onError:
				{
					_ in
				}
			)
			let secondMenu = NSMenu(title: "Actions")
			second.addCopyPath(
				"Copy path",
				to: secondMenu
			)
			let path = try #require(firstMenu.item(withTitle: "Copy path"))
			#expect(NSApp.sendAction(
				try #require(path.action),
				to: path.target,
				from: path
			))
			#expect(NSPasteboard.general.string(forType: .string) == "/tmp/first.md")
			let content = try #require(firstMenu.item(withTitle: "Copy contents"))
			#expect(NSApp.sendAction(
				try #require(content.action),
				to: content.target,
				from: content
			))
			#expect(NSPasteboard.general.string(forType: .string) == original)
			#expect(try await first.loadExportBytes() == Data(original.utf8))
		}
	}

	@Test func unavailableContentCannotRunDisabledAction() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let actions = ViewerFileActions(
				location: FileLocation(
					root: "/tmp",
					relativePath: "missing.txt"
				),
				onError:
				{
					_ in
				}
			)
			let menu = NSMenu(title: "Actions")
			actions.addCopyContents(
				"Copy contents",
				to: menu
			)
			actions.addExport(
				"Export",
				to: menu,
				in: nil
			)
			let copy = try #require(menu.item(withTitle: "Copy contents"))
			let export = try #require(menu.item(withTitle: "Export"))
			menu.update()
			#expect(!copy.isEnabled)
			#expect(!export.isEnabled)
			NSPasteboard.general.clearContents()
			_ = NSApp.sendAction(
				try #require(copy.action),
				to: copy.target,
				from: copy
			)
			_ = NSApp.sendAction(
				try #require(export.action),
				to: export.target,
				from: export
			)
			#expect(NSPasteboard.general.string(forType: .string) == nil)
			#expect(try await actions.loadExportBytes() == nil)
		}
	}
}
