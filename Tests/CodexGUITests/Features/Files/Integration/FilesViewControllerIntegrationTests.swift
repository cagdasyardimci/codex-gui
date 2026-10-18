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
			runtime.switchRoot(fixture.root.path)
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
			window.isReleasedWhenClosed = false
			window.contentViewController = files
			do
			{
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

	@Test(.timeLimit(.minutes(1)))
	func fileSelectionPreservesNavigatorAndReadableDocumentWidth() async throws
	{
		let fixture = FileManager.default.temporaryDirectory
			.appendingPathComponent(
				UUID().uuidString,
				isDirectory: true
			)
		let root = fixture.appendingPathComponent(
			"codex-gui",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: fixture)
		}
		try "# Document\n\none\ntwo\n".write(
			to: root.appendingPathComponent("README.md"),
			atomically: true,
			encoding: .utf8
		)
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let runtime = FileViewerRuntime()
			let files = FilesViewController(runtime: runtime)
			runtime.switchRoot(root.path)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 720,
					height: 560
				),
				styleMask: [.titled, .resizable],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.contentViewController = files
			do
			{
				window.contentView?.layoutSubtreeIfNeeded()
				let rootLocation = FileLocation(
					root: root.path,
					relativePath: ""
				)
				if runtime.state.directoryEntries[rootLocation] == nil
				{
					await withCheckedContinuation
					{
						continuation in
						files.onStateChange =
						{
							state in
							if state.directoryEntries[rootLocation] != nil
							{
								files.onStateChange = nil
								continuation.resume()
							}
						}
					}
				}
				for width in [CGFloat(320), 892]
				{
					window.setContentSize(NSSize(
						width: width,
						height: 560
					))
					for appearance in [NSAppearance.Name.aqua, .darkAqua, .aqua]
					{
						window.appearance = NSAppearance(named: appearance)
						window.contentView?.layoutSubtreeIfNeeded()
						files.view.layoutSubtreeIfNeeded()
						try assertEmptyState(files)
						if let directory = ProcessInfo.processInfo.environment["CODEX_FILES_QA_DIR"]
						{
							try AppTestPNGWriter.write(
								files.view,
								to: URL(fileURLWithPath: directory)
									.appendingPathComponent(
										"empty-\(Int(width))-\(appearance.rawValue).png"
									)
							)
						}
					}
				}
				files.open(
					FileLocation(
						root: root.path,
						relativePath: "README.md"
					),
					retained: true
				)
				let id = try #require(runtime.state.selectedDocumentID)
				await runtime.readTask(for: id)?.value
				await findPreview(in: files.document.view)?.waitForLoading()
				#expect(files.navigator.parent === files)
				#expect(files.document.parent === files)
				let toggle = try #require(findButton(
					"Toggle file navigator",
					in: files.view
				))
				let search = try #require(findButton(
					"Search files",
					in: files.view
				))
				let actions = try #require(findButton(
					"Open file actions",
					in: files.view
				))
				for width in [CGFloat(320), 568, 892, 320]
				{
					window.setContentSize(NSSize(
						width: width,
						height: 560
					))
					window.contentView?.layoutSubtreeIfNeeded()
					files.view.layoutSubtreeIfNeeded()
					files.view.layoutSubtreeIfNeeded()
					#expect(abs(files.view.bounds.width - width) < 1)
					let document = files.document.view.convert(
						files.document.view.bounds,
						to: files.view
					)
					let navigator = files.navigator.view.convert(
						files.navigator.view.bounds,
						to: files.view
					)
					#expect(abs(navigator.maxX - files.view.bounds.maxX) < 1)
					#expect(abs(document.minX - files.view.bounds.minX) < 1)
					#expect(abs(navigator.minX - document.maxX - 5) < 1)
					#expect(document.width >= 159)
					#expect(navigator.width >= 119)
					let toolbar = try #require(search.superview?.superview)
					let searchFrame = search.convert(
						search.bounds,
						to: toolbar
					)
					let actionsFrame = actions.convert(
						actions.bounds,
						to: toolbar
					)
					let toggleFrame = toggle.convert(
						toggle.bounds,
						to: toolbar
					)
					#expect(!actions.isHidden)
					#expect(abs(search.bounds.width - search.bounds.height) < 0.5)
					#expect(abs(toggle.bounds.width - toggle.bounds.height) < 0.5)
					#expect(searchFrame.maxX <= toggleFrame.minX + 1)
					#expect(toggleFrame.maxX <= actionsFrame.minX + 1)
					let navigatorTop = files.navigator.view.convert(
						files.navigator.view.bounds,
						to: toolbar
					)
					#expect(navigatorTop.maxY <= toolbar.bounds.minY)
					#expect(files.breadcrumb.frame.maxX <= searchFrame.minX + 1)
					let mode = try #require(findButton(
						"View source",
						in: files.view
					))
					#expect(!mode.isHidden)
					#expect(searchFrame.maxX <= actionsFrame.minX + 1)
					for appearance in [NSAppearance.Name.aqua, .darkAqua, .aqua]
					{
						window.appearance = NSAppearance(named: appearance)
						files.view.layoutSubtreeIfNeeded()
						#expect(toggle.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
							== appearance)
						#expect(toggle.state == .on)
						try requireToolbarPainted(
							files.view,
							toolbar: toolbar,
							controls: [search, mode, toggle, actions]
						)
						if let directory = ProcessInfo.processInfo.environment["CODEX_FILES_QA_DIR"]
						{
							try AppTestPNGWriter.write(
								files.view,
								to: URL(fileURLWithPath: directory)
									.appendingPathComponent(
										"files-\(Int(width))-\(appearance.rawValue).png"
									)
							)
						}
					}

				}
				let mode = try #require(findButton(
					"View source",
					in: files.view
				))
				#expect(mode.dispatchConfiguredAction())
				#expect(files.document.isShowingSource)
				try requireToolbarPainted(
					files.view,
					toolbar: try #require(search.superview?.superview),
					controls: [search, mode, toggle, actions]
				)
				let menu = files.makeFileActionsMenu()
				let titles = menu.items.filter
				{
					!$0.isSeparatorItem
				}.map(\.title)
				#expect(titles.contains("Default app"))
				#expect(Array(titles.suffix(3)) == ["Open in folder", "Open in GitHub", "Save as…"])
				let extraControls: Set<String> = [
					"View source",
					"Preview",
					"Don't wrap lines",
					"Wrap lines",
					"Copy path",
					"Copy Markdown",
					"Open in preferred editor",
					"Open with…",
					"Reveal in Finder",
					"Add to chat",
					"Search files",
					"Search file contents",
				]
				#expect(Set(titles).isDisjoint(with: extraControls))
				let searchMenu = try #require(search.menu)
				#expect(searchMenu.items.map(\.title) == [
					"Search file contents",
					"Open file by name",
				])
				#expect(toggle.dispatchConfiguredAction())
				window.setContentSize(NSSize(
					width: 892,
					height: 560
				))
				window.contentView?.layoutSubtreeIfNeeded()
				files.view.layoutSubtreeIfNeeded()
				let collapsed = files.document.view.convert(
					files.document.view.bounds,
					to: files.view
				)
				#expect(abs(collapsed.maxX - files.view.bounds.maxX) < 1)
				#expect(toggle.dispatchConfiguredAction())
				files.view.layoutSubtreeIfNeeded()
				let restored = files.navigator.view.convert(
					files.navigator.view.bounds,
					to: files.view
				)
				#expect(abs(restored.maxX - files.view.bounds.maxX) < 1)
				#expect(await runtime.close(
					id,
					choice: .discard
				) == .closed)
				files.view.layoutSubtreeIfNeeded()
				try assertEmptyState(files)
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

	@Test(.timeLimit(.minutes(1)))
	func toolbarSearchOpensContentAndContextMenuPreservesFilenameQuickOpen() async throws
	{
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent(
				UUID().uuidString,
				isDirectory: true
			)
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: root)
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let runtime = FileViewerRuntime()
			let files = FilesViewController(runtime: runtime)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 720,
					height: 560
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			defer
			{
				files.contentSearch.dismiss()
				files.quickOpen.dismiss()
				window.close()
			}
			window.contentViewController = files
			runtime.switchRoot(root.path)
			do
			{
				window.contentView?.layoutSubtreeIfNeeded()
				let search = try #require(findButton(
					"Search files",
					in: files.view
				))
				let searchMenu = try #require(search.menu)
				do
				{
					defer
					{
						files.contentSearch.dismiss()
					}
					#expect(search.dispatchConfiguredAction())
					let sheet = try #require(window.attachedSheet)
					#expect(sheet.title == "Search Files")
					let contentView = try #require(sheet.contentView)
					let fields = descendants(in: contentView).compactMap
					{
						$0 as? NSTextField
					}
					let query = try #require(fields.first
					{
						$0.accessibilityLabel() == "Search file contents"
					})
					let mask = try #require(fields.first
					{
						$0.accessibilityLabel() == "File mask"
					})
					#expect(!mask.isHiddenOrHasHiddenAncestor)
					let editor = try #require(query.currentEditor())
					#expect(sheet.firstResponder === editor)
				}
				#expect(window.attachedSheet == nil)
				do
				{
					defer
					{
						files.quickOpen.dismiss()
					}
					let openByName = try #require(searchMenu.items.first
					{
						$0.title == "Open file by name"
					})
					let action = try #require(openByName.action)
					#expect(openByName.isEnabled)
					#expect(NSApplication.shared.sendAction(
						action,
						to: openByName.target,
						from: openByName
					))
					let sheet = try #require(window.attachedSheet)
					#expect(sheet.title == "Quick Open")
					let contentView = try #require(sheet.contentView)
					let query = try #require(descendants(in: contentView)
						.compactMap
						{
							$0 as? NSTextField
						}.first
						{
							$0.accessibilityLabel() == "Open file by name"
						})
					let editor = try #require(query.currentEditor())
					#expect(sheet.firstResponder === editor)
				}
				#expect(window.attachedSheet == nil)
			}
			catch
			{
				_ = await runtime.shutdown()
				throw error
			}
			_ = await runtime.shutdown()
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
					guard saturation > 0.35 || (dark ? brightness > 0.7 : brightness < 0.4)
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

	@Test func backgroundStateAndTabReturnPreserveSourceSelection() async throws
	{
		_ = NSApplication.shared
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent(
				UUID().uuidString,
				isDirectory: true
			)
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: root)
		}
		let text = (0 ..< 80).map
		{
			"line \($0)"
		}.joined(separator: "\n")
		try text.write(
			to: root.appendingPathComponent("one.txt"),
			atomically: true,
			encoding: .utf8
		)
		try "second".write(
			to: root.appendingPathComponent("two.txt"),
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
				width: 680,
				height: 400
			)
			runtime.switchRoot(root.path)
			runtime.open(
				FileLocation(
					root: root.path,
					relativePath: "one.txt"
				),
				retained: true
			)
			let first = try #require(runtime.state.selectedDocumentID)
			await runtime.readTask(for: first)?.value
			files.view.layoutSubtreeIfNeeded()
			let source = try #require(findTextView(in: files.document.view))
			source.setSelectedRange(NSRange(
				location: 24,
				length: 4
			))
			let before = source.selectedRange()
			runtime.listDirectory(FileLocation(
				root: root.path,
				relativePath: ""
			))
			#expect(source.selectedRange() == before)
			runtime.open(
				FileLocation(
					root: root.path,
					relativePath: "two.txt"
				),
				retained: true
			)
			let second = try #require(runtime.state.selectedDocumentID)
			await runtime.readTask(for: second)?.value
			runtime.select(first)
			await runtime.readTask(for: first)?.value
			let restored = try #require(findTextView(in: files.document.view))
			#expect(restored.selectedRange() == before)
		}
		catch
		{
			_ = await runtime.shutdown()
			throw error
		}
		_ = await runtime.shutdown()
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
		let empty = try #require(descendants(in: files.document.view).compactMap
		{
			$0 as? FileViewerEmptyStateView
		}.first)
		let group = try #require(empty.subviews.compactMap
		{
			$0 as? NSStackView
		}.first)
		#expect(abs(group.frame.midX - empty.bounds.midX) < 0.5)
		#expect(abs(group.frame.midY - empty.bounds.midY) < 0.5)
		#expect(empty.bounds.contains(group.frame))
		let labels = descendants(in: empty).compactMap
		{
			$0 as? NSTextField
		}.map(\.stringValue)
		#expect(labels.contains("Open file"))
		#expect(labels.contains("Select a file from the workspace tree"))
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
		for label in ["Search files", "Toggle file navigator"]
		{
			let button = try #require(findButton(
				label,
				in: files.view
			))
			#expect(abs(button.bounds.width - button.bounds.height) < 0.5)
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
