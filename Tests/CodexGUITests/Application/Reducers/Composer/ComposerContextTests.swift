import AppKit
import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ComposerContextTests
{
	@Test func nontextImageClipboardEnablesNativePasteAndPreservesEditableText() throws
	{
		_ = NSApplication.shared
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		let bitmap = try #require(
			NSBitmapImageRep(
				bitmapDataPlanes: nil,
				pixelsWide: 2,
				pixelsHigh: 2,
				bitsPerSample: 8,
				samplesPerPixel: 4,
				hasAlpha: true,
				isPlanar: false,
				colorSpaceName: .deviceRGB,
				bytesPerRow: 0,
				bitsPerPixel: 0
			)
		)
		bitmap.setColor(
			.systemBlue,
			atX: 0,
			y: 0
		)
		let png = try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
		#expect(pasteboard.setData(
			png,
			forType: .png
		))
		#expect(pasteboard.string(forType: .string) == nil)
		let composer = ContextComposerTextView()
		composer.isEditable = true
		composer.isRichText = false
		composer.string = "Existing draft"
		composer.imagePasteboard = pasteboard
		var attachment: (NSImage, String)?
		composer.onImage =
		{
			image, title in attachment = (image, title)
		}
		let paste = NSMenuItem(
			title: "Paste",
			action: #selector(NSText.paste(_:)),
			keyEquivalent: "v"
		)

		#expect(composer.validateMenuItem(paste))
		#expect(composer.validateUserInterfaceItem(paste))
		composer.paste(nil)
		#expect(attachment?.0.size == NSSize(
			width: 2,
			height: 2
		))
		#expect(attachment?.1 == "Pasted image")
		#expect(composer.string == "Existing draft")
		composer.isEditable = false
		#expect(!composer.validateMenuItem(paste))
		#expect(!composer.validateUserInterfaceItem(paste))
	}

	@Test func contextInputsKeepTypesAndLineNumbers() throws
	{
		let project = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let source = project.appendingPathComponent("Sources/Example.swift")
		try FileManager.default.createDirectory(
			at: source.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try "one\ntwo\nthree\n".write(
			to: source,
			atomically: true,
			encoding: .utf8
		)
		let image = project.appendingPathComponent("screenshot.png")
		try Data([0x89, 0x50, 0x4e, 0x47]).write(to: image)
		let items = [
			ComposerContextItem(
				kind: .fileReference,
				title: "Example.swift",
				path: "Sources/Example.swift"
			),
			ComposerContextItem(
				kind: .textExcerpt,
				title: "Example.swift",
				path: "Sources/Example.swift",
				firstLine: 2,
				lastLine: 3,
				excerpt: "two\nthree"
			),
			ComposerContextItem(
				kind: .image,
				title: "Screenshot",
				path: image.path
			),
		]

		let inputs = try ComposerContextBuilder.inputs(
			text: "Please inspect",
			items: items,
			project: project
		)
		#expect(inputs.count == 3)
		guard case .text(let text) = inputs[0]
		else
		{
			Issue.record("Expected text input")
			return
		}
		#expect(text.contains("Selected code from Sources/Example.swift, lines 2–3"))
		#expect(text.contains("2: two\n3: three"))
		#expect(inputs[1] == .mention(
			name: "Example.swift",
			path: source.path
		))
		#expect(inputs[2] == .localImage(path: image.path))
		#expect(inputs[2].protocolValue["type"] as? String == "localImage")

		let history = try #require(
			CodexItem(json: [
				"id": "user",
				"type": "userMessage",
				"content": inputs.map(\.protocolValue),
			])
		)
		let optimisticBody = UserMessagePresenter.body(for: inputs)
		#expect(UserMessagePresenter.body(for: history) == optimisticBody)
		#expect(optimisticBody.contains("2: two\n3: three"))
		#expect(optimisticBody.components(separatedBy: "File reference:").count == 2)
		#expect(optimisticBody.components(separatedBy: "Attached image:").count == 2)
		#expect(!optimisticBody.contains("[Image:"))
		#expect(!optimisticBody.contains("[File reference:"))
	}

	@Test func missingOrEscapingReferencesAreRejectedBeforeSend() throws
	{
		let project = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		#expect(throws: ComposerContextError.self)
		{
			try ComposerContextBuilder.inputs(
				text: "",
				items: [.init(
					kind: .fileReference,
					title: "Missing",
					path: "missing.swift"
				)],
				project: project
			)
		}
		#expect(throws: ComposerContextError.self)
		{
			try ComposerContextBuilder.inputs(
				text: "",
				items: [.init(
					kind: .fileReference,
					title: "Outside",
					path: "../outside"
				)],
				project: project
			)
		}
	}

	@Test func codeSelectionRecordsInclusiveSourceLines()
	{
		let contents = "first\nsecond\nthird\n"
		let range = (contents as NSString).range(of: "cond\nthi")
		let selected = CodeRangeSelection.item(
			path: "Example.swift",
			contents: contents,
			selectedRange: range
		)
		#expect(selected?.firstLine == 2)
		#expect(selected?.lastLine == 3)
		#expect(selected?.excerpt == "second\nthird")
		#expect(
			CodeRangeSelection.item(
				path: "Example.swift",
				contents: contents,
				selectedRange: NSRange(
					location: 0,
					length: 0
				)
			) == nil
		)
	}

	@Test func codePreviewHasUsableDocumentSizeAndTracksResize()
	{
		_ = NSApplication.shared
		let contents = (1 ... 120).map
		{
			"line \($0): let value = \($0)"
		}.joined(separator: "\n")
		let preview = ScrollableTextPreview.make(
			text: contents,
			size: NSSize(
				width: 540,
				height: 300
			),
			font: .monospacedSystemFont(
				ofSize: 12,
				weight: .regular
			),
			accessibilityLabel: "Select code lines"
		)
		preview.scrollView.layoutSubtreeIfNeeded()
		#expect(preview.textView.frame.width > 400)
		#expect(preview.textView.frame.height > preview.scrollView.contentSize.height)
		#expect(preview.textView.textContainer?.widthTracksTextView == true)
		let selection = (contents as NSString).range(of: "line 75: let value = 75")
		preview.textView.setSelectedRange(selection)
		#expect(
			CodeRangeSelection.item(
				path: "Example.swift",
				contents: contents,
				selectedRange: preview.textView.selectedRange()
			)?.firstLine == 75
		)

		preview.scrollView.setFrameSize(NSSize(
			width: 320,
			height: 200
		))
		preview.scrollView.layoutSubtreeIfNeeded()
		#expect(abs(preview.textView.frame.width - preview.scrollView.contentSize.width) < 2)
	}

	@Test func draftAttachmentsAndEarlierReferencesSurviveRelaunch() throws
	{
		let project = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let suite = "ComposerContextTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(defaults: defaults)
		let item = ComposerContextItem(
			kind: .textExcerpt,
			title: "Example.swift",
			path: "Example.swift",
			firstLine: 4,
			lastLine: 5,
			excerpt: "let answer = 42"
		)
		storage.saveDraftContext(
			[item],
			for: project,
			threadID: "thread-1"
		)
		storage.rememberSentReferences(
			[item],
			for: project,
			threadID: "thread-1"
		)
		let reopened = LocalStorage(defaults: defaults)
		#expect(reopened.draftContext(
			for: project,
			threadID: "thread-1"
		) == [item])
		#expect(reopened.draftContext(
			for: project,
			threadID: nil
		).isEmpty)
		#expect(reopened.sentReferences(
			for: project,
			threadID: "thread-1"
		) == [item])
		#expect(reopened.sentReferences(
			for: project,
			threadID: "thread-2"
		).isEmpty)
	}

	@Test func imageCleanupWaitsForOtherDraftsAndSentReferences() throws
	{
		let project = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let imageDirectory = project.appendingPathComponent("DraftImages")
		try FileManager.default.createDirectory(
			at: imageDirectory,
			withIntermediateDirectories: true
		)
		let suite = "ComposerContextCleanupTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(
			defaults: defaults,
			imageStore: DraftImageStore(directory: imageDirectory)
		)
		let firstImage = try ownedImage(in: imageDirectory)
		let firstItem = ComposerContextItem(
			kind: .image,
			title: "First",
			path: firstImage.path
		)
		storage.saveDraftContext(
			[firstItem],
			for: project,
			threadID: "first"
		)
		storage.saveDraftContext(
			[firstItem.reused()],
			for: project,
			threadID: "second"
		)
		storage.rememberSentReferences(
			[firstItem],
			for: project,
			threadID: "first"
		)

		storage.saveDraftContext(
			[],
			for: project,
			threadID: "first"
		)
		#expect(FileManager.default.fileExists(atPath: firstImage.path))
		let newer = try (0 ..< 24).map
		{
			number -> ComposerContextItem in
			let file = try ownedImage(in: imageDirectory)
			return ComposerContextItem(
				kind: .image,
				title: "New \(number)",
				path: file.path
			)
		}
		storage.rememberSentReferences(
			newer,
			for: project,
			threadID: "first"
		)
		#expect(storage.sentReferences(
			for: project,
			threadID: "first"
		).count == 24)
		#expect(FileManager.default.fileExists(atPath: firstImage.path))
		storage.saveDraftContext(
			[],
			for: project,
			threadID: "second"
		)
		#expect(!FileManager.default.fileExists(atPath: firstImage.path))
		#expect(newer.allSatisfy
		{
			FileManager.default.fileExists(atPath: $0.path ?? "")
		})
	}

	@Test func cleanupNeverDeletesAnImageOutsideTheOwnedStore() throws
	{
		let project = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let imageDirectory = project.appendingPathComponent("DraftImages")
		try FileManager.default.createDirectory(
			at: imageDirectory,
			withIntermediateDirectories: true
		)
		let source = try ownedImage(in: project)
		let ownedCopy = try ownedImage(in: imageDirectory)
		let suite = "ComposerContextExternalTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(
			defaults: defaults,
			imageStore: DraftImageStore(directory: imageDirectory)
		)
		let item = ComposerContextItem(
			kind: .image,
			title: "User file",
			path: source.path
		)
		let ownedItem = ComposerContextItem(
			kind: .image,
			title: "Owned copy",
			path: ownedCopy.path
		)
		storage.saveDraftContext(
			[item, ownedItem],
			for: project,
			threadID: nil
		)
		#expect(FileManager.default.fileExists(atPath: source.path))
		#expect(FileManager.default.fileExists(atPath: ownedCopy.path))
		storage.saveDraftContext(
			[],
			for: project,
			threadID: nil
		)
		#expect(FileManager.default.fileExists(atPath: source.path))
		#expect(!FileManager.default.fileExists(atPath: ownedCopy.path))
	}

	@Test func imageRemovedFromDraftSurvivesAllPendingRequests() throws
	{
		let project = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let imageDirectory = project.appendingPathComponent("DraftImages")
		try FileManager.default.createDirectory(
			at: imageDirectory,
			withIntermediateDirectories: true
		)
		let suite = "ComposerContextPendingTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(
			defaults: defaults,
			imageStore: DraftImageStore(directory: imageDirectory)
		)
		let file = try ownedImage(in: imageDirectory)
		let item = ComposerContextItem(
			kind: .image,
			title: "Screenshot",
			path: file.path
		)
		storage.saveDraftContext(
			[item],
			for: project,
			threadID: "thread"
		)
		let firstRequest = storage.retainContextForRequest([item])
		let secondRequest = storage.retainContextForRequest([item.reused()])

		storage.saveDraftContext(
			[],
			for: project,
			threadID: "thread"
		)
		#expect(FileManager.default.fileExists(atPath: file.path))
		storage.releaseContextForRequest(firstRequest)
		#expect(FileManager.default.fileExists(atPath: file.path))
		storage.releaseContextForRequest(secondRequest)
		#expect(!FileManager.default.fileExists(atPath: file.path))
	}

	@Test func acknowledgedImageRemainsReusableAfterRequestReleasesItsContext() throws
	{
		let project = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let imageDirectory = project.appendingPathComponent("DraftImages")
		try FileManager.default.createDirectory(
			at: imageDirectory,
			withIntermediateDirectories: true
		)
		let suite = "ComposerContextAcknowledgedTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(
			defaults: defaults,
			imageStore: DraftImageStore(directory: imageDirectory)
		)
		let file = try ownedImage(in: imageDirectory)
		let item = ComposerContextItem(
			kind: .image,
			title: "Screenshot",
			path: file.path
		)
		storage.saveDraftContext(
			[item],
			for: project,
			threadID: "thread"
		)
		let request = storage.retainContextForRequest([item])
		storage.saveDraftContext(
			[],
			for: project,
			threadID: "thread"
		)

		storage.rememberSentReferences(
			[item],
			for: project,
			threadID: "thread"
		)
		storage.releaseContextForRequest(request)
		#expect(FileManager.default.fileExists(atPath: file.path))
		#expect(storage.sentReferences(
			for: project,
			threadID: "thread"
		) == [item])
	}

	@Test func sentReferenceRetentionIsGloballyBoundedAcrossProjects() throws
	{
		let firstProject = try temporaryProject()
		let secondProject = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: firstProject)
			try? FileManager.default.removeItem(at: secondProject)
		}
		let suite = "ComposerContextRetentionTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(defaults: defaults)
		func references(_ count: Int) -> [ComposerContextItem]
		{
			(0 ..< count).map
			{
				number in
				ComposerContextItem(
					kind: .textExcerpt,
					title: "Item \(number)",
					path: "File.swift",
					firstLine: number + 1,
					lastLine: number + 1,
					excerpt: "line"
				)
			}
		}
		storage.rememberSentReferences(
			references(80),
			for: firstProject,
			threadID: "one"
		)
		storage.rememberSentReferences(
			references(80),
			for: firstProject,
			threadID: "two"
		)
		storage.rememberSentReferences(
			references(60),
			for: secondProject,
			threadID: "three"
		)
		#expect(storage.sentReferences(
			for: firstProject,
			threadID: "one"
		).count == 60)
		#expect(storage.sentReferences(
			for: firstProject,
			threadID: "two"
		).count == 80)
		#expect(storage.sentReferences(
			for: secondProject,
			threadID: "three"
		).count == 60)
	}

	@Test func earlierSentReferenceFormatIsReadAndMigratedOnWrite() throws
	{
		let project = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let suite = "ComposerContextMigrationTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let original = ComposerContextItem(
			kind: .fileReference,
			title: "Old",
			path: "Old.swift"
		)
		let legacy = [project.path: ["thread:one": [original]]]
		defaults.set(
			try JSONEncoder().encode(legacy),
			forKey: "CodexGUI.sentReferences"
		)
		let storage = LocalStorage(defaults: defaults)
		#expect(storage.sentReferences(
			for: project,
			threadID: "one"
		) == [original])
		let next = ComposerContextItem(
			kind: .fileReference,
			title: "New",
			path: "New.swift"
		)
		storage.rememberSentReferences(
			[next],
			for: project,
			threadID: "one"
		)
		#expect(storage.sentReferences(
			for: project,
			threadID: "one"
		) == [original, next])
	}

	@Test func fileSearchIncludesSourceAndSkipsBuildDirectories() throws
	{
		let project = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let source = project.appendingPathComponent("Sources/Example.swift")
		let ignored = project.appendingPathComponent("node_modules/Example.swift")
		try FileManager.default.createDirectory(
			at: source.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try FileManager.default.createDirectory(
			at: ignored.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try "source".write(
			to: source,
			atomically: true,
			encoding: .utf8
		)
		try "ignored".write(
			to: ignored,
			atomically: true,
			encoding: .utf8
		)
		let index = ProjectFileIndex.load(projectPath: project.path)
		#expect(index.search("Exam") == ["Sources/Example.swift"])
	}

	@Test func imageImportCreatesPreviewAndRemovalControl() throws
	{
		_ = NSApplication.shared
		let directory = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let bitmap = try #require(
			NSBitmapImageRep(
				bitmapDataPlanes: nil,
				pixelsWide: 2,
				pixelsHigh: 2,
				bitsPerSample: 8,
				samplesPerPixel: 4,
				hasAlpha: true,
				isPlanar: false,
				colorSpaceName: .deviceRGB,
				bytesPerRow: 0,
				bitsPerPixel: 0
			)
		)
		bitmap.setColor(
			.systemRed,
			atX: 0,
			y: 0
		)
		let image = NSImage(size: NSSize(
			width: 2,
			height: 2
		))
		image.addRepresentation(bitmap)
		let item = try DraftImageStore(directory: directory).importImage(
			image,
			title: "Test screenshot"
		)
		#expect(item.kind == .image)
		#expect(item.path.map
		{
			FileManager.default.fileExists(atPath: $0)
		} == true)
		let view = ComposerContextView()
		var removedID: String?
		view.onRemove =
		{
			removedID = $0
		}
		view.render(
			items: [item],
			reusable: []
		)
		#expect(findImageView(in: view) != nil)
		let remove = try #require(findButton(
			in: view,
			title: "Remove"
		))
		remove.performClick(nil)
		#expect(removedID == item.id)
	}

	private func findImageView(in view: NSView) -> NSImageView?
	{
		if let imageView = view as? NSImageView
		{
			return imageView
		}
		return view.subviews.lazy.compactMap
		{
			findImageView(in: $0)
		}.first
	}

	private func findButton(
		in view: NSView,
		title: String
	) -> NSButton?
	{
		if let button = view as? NSButton, button.title == title
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			findButton(
				in: $0,
				title: title
			)
		}.first
	}

	private func ownedImage(in directory: URL) throws -> URL
	{
		let file = directory.appendingPathComponent("\(UUID().uuidString).png")
		try Data([1, 2, 3]).write(to: file)
		return file
	}

	private func temporaryProject() throws -> URL
	{
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: url,
			withIntermediateDirectories: true
		)
		return url
	}
}
