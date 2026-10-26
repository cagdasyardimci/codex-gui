import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct DesktopDelayedPresentationTests
{
	@Test func replacingPendingPresentationCannotRunThePreviousCallback() async
	{
		let presentation = DesktopDelayedPresentation()
		var shown: [String] = []
		let previous = presentation.schedule(after: .zero)
		{
			shown.append("previous")
		}
		let replacement = presentation.schedule(after: .zero)
		{
			shown.append("replacement")
		}
		await previous.value
		await replacement.value
		#expect(shown == ["replacement"])
		presentation.dismiss()
	}

	@Test func dismissingPendingPresentationPreventsItsCallback() async
	{
		let presentation = DesktopDelayedPresentation()
		var didShow = false
		let operation = presentation.schedule(after: .zero)
		{
			didShow = true
		}
		presentation.dismiss()
		await operation.value
		#expect(!didShow)
		#expect(presentation.task == nil)
	}
}
