import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SettingsFormComponentsTests
{
	@Test func validationKeepsTheActiveEditorAndLiteralDraft() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let component = SettingsFormField(title: "Working directory")
			let window = makeWindow(content: component)
			defer
			{
				window.close()
			}
			let input = try #require(component.input)
			var changes: [String] = []
			component.onChange =
			{
				changes.append($0)
			}
			window.makeKeyAndOrderFront(nil)
			#expect(window.makeFirstResponder(input))
			input.selectText(nil)
			let editor = try #require(input.currentEditor() as? NSTextView)
			editor.insertText(
				"folder with spaces=a",
				replacementRange: editor.selectedRange()
			)
			let selection = editor.selectedRange()

			component.error = "Choose an existing directory."
			#expect(input.currentEditor() === editor)
			#expect(editor.string == "folder with spaces=a")
			#expect(editor.selectedRange() == selection)
			#expect(input.hasValidationError)
			#expect(!changes.isEmpty)
			component.error = ""
			#expect(input.currentEditor() === editor)
			#expect(!input.hasValidationError)
			#expect(window.makeFirstResponder(nil))
			#expect(component.stringValue == "folder with spaces=a")
		}
	}

	@Test func repeatedPairsKeepLiteralValuesAndReindexAfterRemoval() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let component = SettingsFormEntriesField(
				format: .pairs,
				item: "header",
				addTitle: "Add header"
			)
			component.stringValue = "TOKEN=a=b\nPATH=folder with spaces"
			#expect(try #require(field(
				"header 1",
				in: component
			)).stringValue == "TOKEN")
			#expect(try #require(field(
				"header value 1",
				in: component
			)).stringValue == "a=b")
			var changes = 0
			component.onChange =
			{
				changes += 1
			}
			let add = try #require(button(
				"Add header",
				in: component
			))
			#expect(add.dispatchConfiguredAction())
			let key = try #require(field(
				"header 3",
				in: component
			))
			let value = try #require(field(
				"header value 3",
				in: component
			))
			key.stringValue = "NEW"
			value.stringValue = "x=y z"
			let remove = try #require(button(
				"Remove header 1",
				in: component
			))
			#expect(remove.image != nil)
			#expect(remove.dispatchConfiguredAction())
			#expect(component.stringValue == "PATH=folder with spaces\nNEW=x=y z")
			#expect(field(
				"header 3",
				in: component
			) == nil)
			#expect(field(
				"header value 2",
				in: component
			)?.stringValue == "x=y z")
			#expect(changes == 2)
		}
	}

	private func makeWindow(content: NSView) -> NSWindow
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 400,
				height: 160
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		if let container = window.contentView
		{
			content.translatesAutoresizingMaskIntoConstraints = false
			container.addSubview(content)
			NSLayoutConstraint.activate([
				content.leadingAnchor.constraint(
					equalTo: container.leadingAnchor,
					constant: 20
				),
				content.trailingAnchor.constraint(
					equalTo: container.trailingAnchor,
					constant: -20
				),
				content.topAnchor.constraint(
					equalTo: container.topAnchor,
					constant: 20
				),
			])
		}
		return window
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}

	private func field(
		_ label: String,
		in view: NSView
	) -> NSTextField?
	{
		descendants(view).compactMap
		{
			$0 as? NSTextField
		}.first
		{
			$0.accessibilityLabel() == label
		}
	}

	private func button(
		_ label: String,
		in view: NSView
	) -> NSButton?
	{
		descendants(view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == label || $0.accessibilityLabel() == label
		}
	}
}
