import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ComposerImageSourceTests
{
	@Test func screenshotPasteCapturesEncodedBytesAndRetainsExistingText() throws
	{
		_ = NSApplication.shared
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		let png = try DraftImageImportTestFixture.png()
		#expect(pasteboard.setData(
			png,
			forType: .png
		))
		let composer = ContextComposerTextView()
		composer.isEditable = true
		composer.isRichText = false
		composer.string = "Existing 🐈\u{2028} draft"
		composer.imagePasteboard = pasteboard
		var received: (DraftImageSource, String)?
		composer.onImageSource =
		{
			received = ($0, $1)
		}
		composer.onImage =
		{
			_, _ in Issue.record("The paste decoded an AppKit image before capture.")
		}
		let paste = NSMenuItem(
			title: "Paste",
			action: #selector(NSText.paste(_:)),
			keyEquivalent: "v"
		)
		#expect(composer.validateMenuItem(paste))
		#expect(composer.validateUserInterfaceItem(paste))
		composer.paste(nil)
		let (source, title) = try #require(received)
		guard case let .data(snapshot) = source
		else
		{
			Issue.record("The source callback did not receive encoded image bytes.")
			return
		}
		#expect(snapshot == png)
		#expect(title == "Pasted image")
		#expect(composer.string == "Existing 🐈\u{2028} draft")
		pasteboard.clearContents()
		#expect(snapshot == png)
		composer.isEditable = false
		#expect(!composer.validateMenuItem(paste))
	}

	@Test func fileURLAndTextPasteRetainImagePrecedenceWithoutLoadingFile() async throws
	{
		_ = NSApplication.shared
		let directory = try await BackgroundTestWork.perform
		{
			try DraftImageImportTestFixture.temporaryDirectory()
		}
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let file = directory.appendingPathComponent("Screenshot 🐈.png")
		let png = try DraftImageImportTestFixture.png()
		try await BackgroundTestWork.perform
		{
			try png.write(to: file)
		}
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		#expect(pasteboard.writeObjects([file as NSURL]))
		#expect(pasteboard.setString(
			"Screenshot 🐈.png",
			forType: .string
		))
		let composer = ContextComposerTextView()
		composer.isEditable = true
		composer.string = "Existing draft"
		composer.imagePasteboard = pasteboard
		var receivedURL: URL?
		composer.onImageSource =
		{
			source, _ in
			if case let .file(url) = source
			{
				receivedURL = url
			}
		}
		// Capture remains a URL after removal; the worker is responsible for reading it.
		try FileManager.default.removeItem(at: file)
		composer.paste(nil)
		#expect(receivedURL == file)
		#expect(composer.string == "Existing draft")
	}
	@Test func multiImagePasteCapturesEachItemOnceInClipboardOrder() throws
	{
		_ = NSApplication.shared
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		let firstPNG = try DraftImageImportTestFixture.png()
		let secondTIFF = try #require(NSImage(data: firstPNG)?.tiffRepresentation)
		let first = NSPasteboardItem()
		#expect(first.setData(
			firstPNG,
			forType: .png
		))
		let tiff = secondTIFF
		#expect(first.setData(
			tiff,
			forType: .tiff
		))
		let second = NSPasteboardItem()
		#expect(second.setData(
			secondTIFF,
			forType: .tiff
		))
		#expect(pasteboard.writeObjects([first, second]))
		let composer = ContextComposerTextView()
		composer.isEditable = true
		composer.string = "Existing draft"
		composer.imagePasteboard = pasteboard
		var snapshots: [Data] = []
		composer.onImageSource =
		{
			source, title in
			#expect(title == "Pasted image")
			if case let .data(data) = source
			{
				snapshots.append(data)
			}
			else
			{
				Issue.record("Expected encoded bytes for each clipboard image.")
			}
		}
		composer.paste(nil)
		#expect(snapshots == [firstPNG, secondTIFF])
		#expect(composer.string == "Existing draft")
		pasteboard.clearContents()
		#expect(snapshots == [firstPNG, secondTIFF])
	}

	@Test func multiFilePasteSkipsNonimagesAndKeepsLaterImageFiles() throws
	{
		_ = NSApplication.shared
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		let files = ["Notes.txt", "First 🐈.png", "Second.jpg"].map
		{
			URL(fileURLWithPath: "/nonexistent/" + $0)
		}
		#expect(pasteboard.writeObjects(files.map
			{
				$0 as NSURL
			}))
		let composer = ContextComposerTextView()
		composer.isEditable = true
		composer.string = "Existing draft"
		composer.imagePasteboard = pasteboard
		var received: [URL] = []
		composer.onImageSource =
		{
			source, _ in
			if case let .file(url) = source
			{
				received.append(url)
			}
		}
		let paste = NSMenuItem(
			title: "Paste",
			action: #selector(NSText.paste(_:)),
			keyEquivalent: "v"
		)
		#expect(composer.validateMenuItem(paste))
		composer.paste(nil)
		#expect(received == Array(files.dropFirst()))
		#expect(composer.string == "Existing draft")
	}

}
