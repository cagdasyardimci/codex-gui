import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct FilesViewControllerIntegrationTests
{
	@Test(.timeLimit(.minutes(1)))
	func BMPAndSVGSharePreviewCapabilitiesWhileSVGKeepsEditableSource() async throws
	{
		let fixture = try await BackgroundTestWork.perform
		{
			let fixture = try FileReadSafetyFixture()
			try FilePreviewTestData.bmp.write(to: fixture.root.appendingPathComponent("image.bmp"))
			try Data().write(to: fixture.root.appendingPathComponent("empty.png"))
			try Data().write(to: fixture.root.appendingPathComponent("empty.pdf"))
			try Data(FilePreviewTestData.svg.utf8).write(
				to: fixture.root.appendingPathComponent("image.svg")
			)
			return fixture
		}
		defer
		{
			try? FileManager.default.removeItem(at: fixture.root)
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let runtime = FileViewerRuntime(autosaveDelay: .seconds(60))
			let files = FilesViewController(runtime: runtime)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 700,
					height: 500
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			window.contentViewController = files
			do
			{
				files.view.layoutSubtreeIfNeeded()
				try assertEmptyState(files)
				runtime.switchRoot(fixture.root.path)
				for path in ["empty.png", "empty.pdf"]
				{
					files.open(
						FileLocation(
							root: fixture.root.path,
							relativePath: path
						),
						retained: true
					)
					let id = try #require(runtime.state.selectedDocumentID)
					await runtime.readTask(for: id)?.value
					let toggle = try #require(findButton(
						"View source",
						in: files.view
					))
					#expect(toggle.isHidden)
				}

				files.open(
					FileLocation(
						root: fixture.root.path,
						relativePath: "image.bmp"
					),
					retained: true
				)
				let bmpID = try #require(runtime.state.selectedDocumentID)
				await runtime.readTask(for: bmpID)?.value
				let bmpPreview = try #require(findPreview(in: files.document.view))
				await bmpPreview.waitForLoading()
				let renderedImages = descendants(in: bmpPreview).compactMap
				{
					($0 as? NSImageView)?.image
				}
				let image = try #require(renderedImages.first)
				#expect(image.size == NSSize(
					width: 1,
					height: 1
				))
				let bmpToggle = try #require(findButton(
					"View source",
					in: files.view
				))
				#expect(bmpToggle.isHidden)
				let changesPreview = GitRichPreviewView(kind: try #require(
					GitRichPreviewKind(path: "image.bmp")
				))
				{
					FilePreviewTestData.bmp
				}
				await changesPreview.waitForLoading()
				#expect(descendants(in: changesPreview).compactMap
				{
					($0 as? NSImageView)?.image
				}.first?.size == image.size)
				changesPreview.cancelLoading()

				files.open(
					FileLocation(
						root: fixture.root.path,
						relativePath: "image.svg"
					),
					retained: true
				)
				let svgID = try #require(runtime.state.selectedDocumentID)
				await runtime.readTask(for: svgID)?.value
				let svgPreview = try #require(findPreview(in: files.document.view))
				await svgPreview.waitForLoading()
				#expect(descendants(in: svgPreview).contains
				{
					$0 is NSImageView
				})
				#expect(!files.document.isShowingSource)
				let sourceToggle = try #require(findButton(
					"View source",
					in: files.view
				))
				#expect(!sourceToggle.isHidden)
				#expect(sourceToggle.dispatchConfiguredAction())
				let source =
					try #require(findTextView(in: files.document.view) as? FileSourceTextView)
				#expect(source.isEditable)
				#expect(source.string == FilePreviewTestData.svg)
				let wrap = try #require(findButtonTitle(
					"Wrap lines",
					in: files.document.view
				))
				#expect(!wrap.isHidden)
				source.setSelectedRange(NSRange(
					location: 0,
					length: 0
				))
				source.insertText(
					"<!-- edited -->",
					replacementRange: source.selectedRange()
				)
				let edited = "<!-- edited -->" + FilePreviewTestData.svg
				#expect(runtime.state.selectedDocument?.currentText == edited)
				let selection = NSRange(
					location: 4,
					length: 3
				)
				source.setSelectedRange(selection)
				let copy = try #require(files.document.makeActionsMenu()
					.item(withTitle: "Copy contents"))
				#expect(NSApp.sendAction(
					try #require(copy.action),
					to: copy.target,
					from: copy
				))
				#expect(NSPasteboard.general.string(forType: .string) == edited)
				#expect(sourceToggle.dispatchConfiguredAction())
				let editedPreview = try #require(findPreview(in: files.document.view))
				await editedPreview.waitForLoading()
				#expect(descendants(in: editedPreview).contains
				{
					$0 is NSImageView
				})
				#expect(sourceToggle.dispatchConfiguredAction())
				let restored =
					try #require(findTextView(in: files.document.view) as? FileSourceTextView)
				#expect(restored === source)
				#expect(restored.string == edited)
				#expect(restored.selectedRange() == selection)
			}
			catch
			{
				_ = await runtime.shutdown()
				window.close()
				throw error
			}
			_ = await runtime.shutdown()
			window.close()
		}
	}

	private func requireToolbarPainted(
		_ root: NSView,
		toolbar: NSView,
		controls: [NSView]
	) throws
	{
		let full = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
		root.cacheDisplay(
			in: root.bounds,
			to: full
		)
		let reference = try #require(toolbar.bitmapImageRepForCachingDisplay(in: toolbar.bounds))
		toolbar.cacheDisplay(
			in: toolbar.bounds,
			to: reference
		)
		let scaleX = CGFloat(full.pixelsWide) / root.bounds.width
		let scaleY = CGFloat(full.pixelsHigh) / root.bounds.height
		let dark = root.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		for control in controls
		{
			let rect = control.convert(
				control.bounds,
				to: toolbar
			).insetBy(
				dx: 6,
				dy: 6
			)
			var expectedInk = 0
			var visibleInk = 0
			for y in Int(rect.minY * scaleY) ..< Int(rect.maxY * scaleY)
			{
				for x in Int(rect.minX * scaleX) ..< Int(rect.maxX * scaleX)
				{
					let sampleY = toolbar.isFlipped ? y : reference.pixelsHigh - 1 - y
					guard let expected = reference.colorAt(
						x: x,
						y: sampleY
					)?.usingColorSpace(.sRGB)
					else
					{
						continue
					}
					let brightness = (expected.redComponent + expected.greenComponent
						+ expected.blueComponent) / 3
					let saturation = max(
						expected.redComponent,
						expected.greenComponent,
						expected.blueComponent
					)
						- min(
							expected.redComponent,
							expected.greenComponent,
							expected.blueComponent
						)
					// Grouped actions use secondary ink; include it without counting the
					// white capsule or its pale selected background as control artwork.
					guard saturation > 0.35 || (dark ? brightness > 0.45 : brightness < 0.8)
					else
					{
						continue
					}
					expectedInk += 1
					let point = root.convert(
						NSPoint(
							x: CGFloat(x) / scaleX,
							y: CGFloat(y) / scaleY
						),
						from: toolbar
					)
					let fullY = root.isFlipped ? Int(point.y * scaleY)
						: full.pixelsHigh - 1 - Int(point.y * scaleY)
					let actual = try #require(full.colorAt(
						x: Int(point.x * scaleX),
						y: fullY
					)?.usingColorSpace(.sRGB))
					let delta = abs(actual.redComponent - expected.redComponent)
						+ abs(actual.greenComponent - expected.greenComponent)
						+ abs(actual.blueComponent - expected.blueComponent)
					if delta < 0.45
					{
						visibleInk += 1
					}
				}
			}
			#expect(expectedInk > 5)
			#expect(Double(visibleInk) / Double(max(
				1,
				expectedInk
			)) > 0.8)
		}
	}

	@Test func markdownLoadsContainedRelativeImageAndKeepsOutsideImageAsSource() async throws
	{
		_ = NSApplication.shared
		let fixture = FileManager.default.temporaryDirectory
			.appendingPathComponent(
				UUID().uuidString,
				isDirectory: true
			)
		let root = fixture.appendingPathComponent(
			"workspace",
			isDirectory: true
		)
		let docs = root.appendingPathComponent(
			"docs",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: docs,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: fixture)
		}
		let image = try pngBytes()
		try image.write(to: docs.appendingPathComponent("picture.png"))
		try image.write(to: fixture.appendingPathComponent("outside.png"))
		let markdown = "![Picture](picture.png)\n\nA separate paragraph.\n\n"
			+ "![Outside](../../outside.png)"
		try markdown.write(
			to: docs.appendingPathComponent("readme.md"),
			atomically: true,
			encoding: .utf8
		)
		let runtime = FileViewerRuntime()
		do
		{
			let files = FilesViewController(runtime: runtime)
			files.view.frame = NSRect(
				x: 0,
				y: 0,
				width: 720,
				height: 480
			)
			let location = FileLocation(
				root: root.path,
				relativePath: "docs/readme.md"
			)
			let loadedImage = await files.document.markdownImageLoader?(
				location,
				docs.appendingPathComponent("picture.png").path,
				160
			)
			#expect(loadedImage != nil)
			runtime.switchRoot(root.path)
			runtime.open(
				location,
				retained: true
			)
			let id = try #require(runtime.state.selectedDocumentID)
			await runtime.readTask(for: id)?.value
			let preview = try #require(findPreview(in: files.document.view))
			await preview.waitForLoading()
			let text = try #require(findMarkdownTextView(in: preview))
			let storage = try #require(text.textStorage)
			let gallery = storage.attribute(
				.attachment,
				at: 0,
				effectiveRange: nil
			)
				as? MarkdownImageGalleryAttachment
			#expect(gallery?.paths == [docs.appendingPathComponent("picture.png").path])
			var fallbackSources: [String] = []
			storage.enumerateAttribute(
				.attachment,
				in: NSRange(
					location: 0,
					length: storage.length
				)
			)
			{
				value, _, _ in
				if let fallback = value as? MarkdownRichAttachment
				{
					fallbackSources.append(fallback.source)
				}
			}
			#expect(fallbackSources.contains("![Outside](../../outside.png)"))
			files.contentSearch.onChoose?(FileViewerSearchResult(
				location: FileLocation(
					root: root.path,
					relativePath: "docs/readme.md"
				),
				lineNumber: 3,
				lineText: "Outside"
			))
			#expect(files.document.isShowingSource)
			#expect(findButtonTitle(
				"Preview",
				in: files.view
			) != nil)
		}
		catch
		{
			_ = await runtime.shutdown()
			throw error
		}
		_ = await runtime.shutdown()
	}

	private func assertEmptyState(_ files: FilesViewController) throws
	{
		let labels = descendants(in: files.document.view).compactMap
		{
			$0 as? NSTextField
		}.map(\.stringValue)
		#expect(!labels.contains("Open file"))
		#expect(!labels.contains("Select a file from the workspace tree"))
		#expect(findButton(
			"Open file actions",
			in: files.view
		)?.isHidden == true)
		let rootLabel = try #require(descendants(in: files.breadcrumb).compactMap
		{
			$0 as? NSTextField
		}
		.first
		{
			$0.stringValue == "/"
		})
		#expect(rootLabel.alignment == .center)
		#expect(abs(files.breadcrumb.bounds.width - files.breadcrumb.bounds.height) < 0.5)
		#expect(files.breadcrumb.bounds.height == 34)
		let rootLabelFrame = rootLabel.convert(
			rootLabel.bounds,
			to: files.breadcrumb
		)
		#expect(abs(rootLabelFrame.midX - files.breadcrumb.bounds.midX) < 0.5)
		for label in ["Search in files", "Toggle file tree"]
		{
			let button = try #require(findButton(
				label,
				in: files.view
			))
			#expect(abs(button.bounds.width - button.bounds.height) < 0.5)
			#expect(button.toolTip == label)
		}
	}

	private func descendants(in view: NSView) -> [NSView]
	{
		view.subviews + view.subviews.flatMap
		{
			descendants(in: $0)
		}
	}

	private func pngBytes() throws -> Data
	{
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: 2,
			pixelsHigh: 2,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 8,
			bitsPerPixel: 32
		))
		return try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
	}

	private func findPreview(in view: NSView) -> RichFilePreviewView?
	{
		if let preview = view as? RichFilePreviewView
		{
			return preview
		}
		return view.subviews.lazy.compactMap
		{
			findPreview(in: $0)
		}.first
	}

	private func findMarkdownTextView(in view: NSView) -> MarkdownTextView?
	{
		if let text = view as? MarkdownTextView
		{
			return text
		}
		return view.subviews.lazy.compactMap
		{
			findMarkdownTextView(in: $0)
		}.first
	}

	private func findButtonTitle(
		_ title: String,
		in view: NSView
	) -> NSButton?
	{
		if let button = view as? NSButton, button.title == title
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			findButtonTitle(
				title,
				in: $0
			)
		}.first
	}

	private func findTextView(in view: NSView) -> NSTextView?
	{
		if let text = view as? NSTextView
		{
			return text
		}
		return view.subviews.lazy.compactMap
		{
			findTextView(in: $0)
		}.first
	}

	private func findButton(
		_ label: String,
		in view: NSView
	) -> NSButton?
	{
		if let button = view as? NSButton, button.accessibilityLabel() == label
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			findButton(
				label,
				in: $0
			)
		}.first
	}
}
