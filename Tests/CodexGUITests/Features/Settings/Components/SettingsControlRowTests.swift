import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SettingsControlRowTests
{
	@Test func mutableTextKeepsItsControlAndExpandsOnlyForAnIncludedDetail() throws
	{
		_ = NSApplication.shared
		let control = NSButton(
			title: "Action",
			target: nil,
			action: nil
		)
		control.heightAnchor.constraint(equalToConstant: 10).isActive = true
		let row = SettingsPageLayout.row(
			title: "Original",
			detail: nil,
			control: control
		)
		row.widthAnchor.constraint(equalToConstant: 500).isActive = true
		let originalHeight = row.fittingSize.height

		row.setTitle("Updated")
		row.setDetail("A supporting detail")
		row.setDetailHelp("Additional context")

		let labels = descendants(row).compactMap
		{
			$0 as? NSTextField
		}
		#expect(labels.contains
		{
			$0.stringValue == "Updated"
		})
		#expect(labels.contains
		{
			$0.stringValue == "A supporting detail" && $0.toolTip == "Additional context"
		})
		#expect(control.isDescendant(of: row))
		#expect(row.fittingSize.height > originalHeight + 10)
		row.setDetail(nil)
		#expect(abs(row.fittingSize.height - originalHeight) < 1)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}
}
