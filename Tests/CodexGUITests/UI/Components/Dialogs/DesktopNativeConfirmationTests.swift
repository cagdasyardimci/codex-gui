import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(.serialized)
struct DesktopNativeConfirmationTests
{
	@Test(
		.timeLimit(.minutes(1)),
		arguments: [false, true]
	)
	func nativeButtonOrderingMapsOnlyTheConfirmationToApproval(_ confirmFirst: Bool) async throws
	{
		try await AppKitTestIsolation.perform
		{
			for response in [NSApplication.ModalResponse.alertFirstButtonReturn,
								.alertSecondButtonReturn,
								.cancel]
			{
				let parent = makeWindow()
				defer
				{
					parent.close()
				}
				let confirmation = DesktopNativeConfirmation(
					title: "Remove item?",
					message: "Remove the selected item.",
					confirmTitle: "Remove",
					defaultAction: confirmFirst ? .confirm : .cancel,
					emphasis: .warning
				)
				confirmation.alert.window.prepareForTesting()
				#expect(confirmation.alert.buttons.map(\.title)
					== (confirmFirst ? ["Remove", "Cancel"] : ["Cancel", "Remove"]))
				#expect(confirmation.alert.alertStyle == .warning)
				let result = AsyncStream<Bool>.makeStream()
				confirmation.beginSheet(in: parent)
				{
					approved in
					result.continuation.yield(approved)
					result.continuation.finish()
				}
				let sheet = try #require(parent.attachedSheet)
				parent.endSheet(
					sheet,
					returnCode: response
				)
				var iterator = result.stream.makeAsyncIterator()
				let expected = response == (confirmFirst
					? .alertFirstButtonReturn : .alertSecondButtonReturn)
				#expect(await iterator.next() == expected)
				#expect(await iterator.next() == nil)
				var repeatedCallbacks = 0
				confirmation.beginSheet(in: parent)
				{
					_ in repeatedCallbacks += 1
				}
				#expect(parent.attachedSheet == nil)
				#expect(repeatedCallbacks == 0)
			}
		}
	}

	@Test(
		.timeLimit(.minutes(1)),
		arguments: [false, true]
	)
	func nativeTextPromptReturnsExactEditedValuesOnlyWhenApproved(_ approved: Bool) async throws
	{
		try await AppKitTestIsolation.perform
		{
			let parent = makeWindow()
			defer
			{
				parent.close()
			}
			let prompt = DesktopTextEntryPrompt(
				title: "Rename item",
				actionTitle: "Save",
				fields: [DesktopTextEntryPrompt.Field(
					value: "Original",
					placeholder: "Name",
					accessibilityLabel: "Name"
				)],
				layout: .single
			)
			let result = AsyncStream<[String]?>.makeStream()
			prompt.beginSheet(in: parent)
			{
				values in
				result.continuation.yield(values)
				result.continuation.finish()
			}
			let sheet = try #require(parent.attachedSheet)
			sheet.prepareForTesting()
			let edited = "  Edited name  "
			prompt.fields[0].stringValue = edited
			parent.endSheet(
				sheet,
				returnCode: approved ? .alertFirstButtonReturn : .alertSecondButtonReturn
			)
			var iterator = result.stream.makeAsyncIterator()
			let response = await iterator.next()
			let values = try #require(response)
			#expect(values == (approved ? [edited] : nil))
		}
	}

	private func makeWindow() -> NSWindow
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 800,
				height: 600
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		return window
	}
}
