import AppKit
import Testing
@testable import CodexGUI

@MainActor
struct ProjectPickerTests
{
	@Test func filteringSelectsMatchingProjectAndKeepsCreationAvailable() throws
	{
		let first = URL(fileURLWithPath: "/tmp/alpha")
		let second = URL(fileURLWithPath: "/tmp/semantic-checker")
		let picker = ProjectPickerViewController(projects: [
			.init(
				url: first,
				name: "Alpha"
			),
			.init(
				url: second,
				name: "Swift tools"
			),
		])
		picker.loadViewIfNeeded()
		var selected: URL?
		var creations = 0
		picker.onSelect =
		{
			selected = $0
		}
		picker.onCreate =
		{
			creations += 1
		}
		picker.search.stringValue = "SEMANTIC"
		picker.controlTextDidChange(Notification(
			name: NSControl.textDidChangeNotification,
			object: picker.search
		))
		#expect(picker.rows.count == 1)
		#expect(picker.handleKey(36))
		#expect(selected == second)
		picker.search.stringValue = "unmatched"
		picker.controlTextDidChange(Notification(
			name: NSControl.textDidChangeNotification,
			object: picker.search
		))
		#expect(picker.rows.isEmpty)
		#expect(picker.handleKey(36))
		#expect(creations == 1)
		#expect(selected == second)
	}

	@Test func longProjectListHasBoundedViewportWithCreationOutsideIt()
	{
		let picker = ProjectPickerViewController(projects: (0 ..< 30).map
		{
			.init(
				url: URL(fileURLWithPath: "/tmp/project-\($0)"),
				name: "Project \($0)"
			)
		})
		picker.loadViewIfNeeded()
		picker.view.frame.size = picker.preferredContentSize
		picker.view.layoutSubtreeIfNeeded()
		#expect(picker.rows.count == 30)
		#expect(picker.scroll.documentView!.fittingSize.height > picker.scroll.bounds.height)
		#expect(picker.scroll.documentView!.frame.height > picker.scroll.bounds.height)
		picker.scroll.contentView.scroll(to: NSPoint(
			x: 0,
			y: 100
		))
		#expect(picker.scroll.contentView.bounds.minY > 0)
		#expect(!picker.createRow.isDescendant(of: picker.scroll))
		#expect(picker.createRow.isEnabled)
	}

	@Test func creationRequiresFolderAndTrimmedName()
	{
		let form = ProjectCreationViewController()
		form.loadViewIfNeeded()
		#expect(!form.createButton.isEnabled)
		form.nameField.stringValue = "Custom name"
		form.nameField.onChange?("Custom name")
		#expect(!form.createButton.isEnabled)
		let folder = URL(fileURLWithPath: "/tmp/source")
		form.selectFolder(folder)
		#expect(form.createButton.isEnabled)
		#expect(form.projectName == "Custom name")
		#expect(form.folder == folder)
		form.nameField.stringValue = "  \n "
		form.nameField.onChange?("  \n ")
		#expect(!form.createButton.isEnabled)
	}
}
