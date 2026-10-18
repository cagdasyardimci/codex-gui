import AppKit
import PDFKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitInlineRichPreviewTests
{
	@Test func eyeButtonExpandsCollapsedFileAndLoadsPreviewInChangesViewer() async throws
	{
		// Repository preparation is independent of the native viewer and can block on Git.
		let fixture = try await BackgroundTestWork.perform
		{
			let fixture = try GitTurnBaselineFixture()
			do
			{
				try fixture.write(
					"README.md",
					"# Before\n"
				)
				try fixture.git(["add", "README.md"])
				try fixture.commit()
				try fixture.write(
					"README.md",
					"# Inline preview\n\n**Formatted** content.\n"
				)
				return fixture
			}
			catch
			{
				fixture.remove()
				throw error
			}
		}
		defer
		{
			fixture.remove()
		}
		_ = NSApplication.shared
		let controller = GitChangesViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 900,
				height: 500
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		defer
		{
			controller.close(); window.close()
		}
		controller.activate(owner: fixture.comparisonRequest(
			baseline: nil,
			turnID: nil
		).owner)
		controller.runtime.selectScope(.unstaged)
		await controller.runtime.readTask?.value
		#expect(try #require(controller.runtime.state.snapshot).request.scope == .unstaged)
		settle(window)
		#expect(try button(
			"Collapse diff for README.md",
			in: controller.view
		).dispatchConfiguredAction())
		_ = try button(
			"Expand diff for README.md",
			in: controller.view
		)
		// Other fixtures may create unrelated windows while this preview loads.
		// Verify this component remains in its original owned hierarchy instead.
		let originalContent = window.contentView
		let section = try #require(descendants(controller.view).compactMap
		{
			$0 as? GitDiffFileSectionView
		}.first)
		let originalDocument = section.superview
		#expect(try button(
			"Rich preview of README.md",
			in: controller.view
		).dispatchConfiguredAction())
		let preview = try #require(descendants(controller.view).compactMap
		{
			$0 as? GitRichPreviewView
		}.first)
		let text = try await waitForText(preview)
		settle(window)
		#expect(text.string.hasPrefix("Inline preview"))
		#expect(preview.window === window)
		#expect(window.contentView === originalContent)
		// Expanding a collapsed file legitimately replaces its old section.
		let expandedSection = try #require(preview.superview as? GitDiffFileSectionView)
		#expect(expandedSection.superview === originalDocument)
		#expect(descendants(expandedSection).contains
		{
			$0 === preview
		})
		#expect(text.window === window)
		#expect(window.childWindows?.isEmpty != false)
		_ = try button(
			"Collapse diff for README.md",
			in: controller.view
		)
		#expect(try button(
			"Show diff for README.md",
			in: controller.view
		).dispatchConfiguredAction())
		#expect(!descendants(controller.view).contains
		{
			$0 is GitRichPreviewView
		})
	}

	@Test func markdownTogglesInsideSectionAndRestoresRetainedDiff() async throws
	{
		_ = NSApplication.shared
		let section = makeSection()
		let outer = AppKitLayout.scrollableContent(
			section,
			inset: 0
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 680,
				height: 320
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentView = outer
		defer
		{
			window.close()
		}
		settle(window)
		let source = try #require(descendants(section).compactMap
		{
			$0 as? GitDiffTextView
		}.first)
		source.setSelectedRange(NSRange(
			location: 2,
			length: 5
		))
		let originalBody = try #require(section.arrangedSubviews.last)
		let inner = try #require(source.enclosingScrollView)
		inner.contentView.scroll(to: NSPoint(
			x: 60,
			y: 0
		))
		let horizontal = inner.contentView.bounds.origin.x
		// Scope the no-new-preview-window invariant to this fixture's ownership.
		let originalDocument = outer.documentView
		let originalSectionParent = section.superview
		let markdown = "# Preview\n\n" + String(
			repeating: "Formatted **content** wraps. ",
			count: 60
		)
		section.toggleRichPreview
		{
			GitRichPreviewView(kind: .markdown)
			{
				Data(markdown.utf8)
			}
		}
		let preview = try #require(section.arrangedSubviews.last as? GitRichPreviewView)
		#expect(originalBody.isHidden)
		let text = try await waitForText(preview)
		settle(window)
		#expect(text.string.hasPrefix("Preview"))
		#expect(!text.string.contains("**content**"))
		#expect(text.enclosingScrollView === outer)
		#expect(outer.documentView === originalDocument)
		#expect(section.superview === originalSectionParent)
		#expect(preview.superview === section)
		#expect(preview.window === window)
		#expect(text.window === window)
		#expect(window.childWindows?.isEmpty != false)
		let wideHeight = preview.frame.height
		window.setContentSize(NSSize(
			width: 300,
			height: 320
		))
		settle(window)
		#expect(preview.frame.height > wideHeight)
		text.setSelectedRange(NSRange(
			location: 0,
			length: 7
		))
		for name in [NSAppearance.Name.aqua, .darkAqua, .aqua]
		{
			window.appearance = NSAppearance(named: name)
			settle(window)
			#expect(text.selectedRange() == NSRange(
				location: 0,
				length: 7
			))
		}
		window.setContentSize(NSSize(
			width: 680,
			height: 320
		))
		section.toggleRichPreview
		{
			Issue.record("Toggling off must not create a new preview");
			return GitRichPreviewView(kind: .markdown)
			{
				Data()
			}
		}
		settle(window)
		#expect(!originalBody.isHidden)
		#expect(source.selectedRange() == NSRange(
			location: 2,
			length: 5
		))
		#expect(inner.contentView.bounds.origin.x == horizontal)
		#expect(!section.arrangedSubviews.contains
		{
			$0 is GitRichPreviewView
		})
	}

	@Test func imagesAndPDFsRenderInInlineViews() async throws
	{
		_ = NSApplication.shared
		let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
		let context = try #require(CGContext(
			data: nil,
			width: 100,
			height: 60,
			bitsPerComponent: 8,
			bytesPerRow: 400,
			space: colorSpace,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		))
		let fixtureColor = try #require(CGColor(
			colorSpace: colorSpace,
			components: [0.125, 0.25, 0.75, 1]
		))
		context.setFillColor(fixtureColor)
		context.fill(CGRect(
			x: 0,
			y: 0,
			width: 100,
			height: 60
		))
		let image = NSImage(
			cgImage: try #require(context.makeImage()),
			size: NSSize(
				width: 100,
				height: 60
			)
		)
		let imageData = try #require(image.tiffRepresentation)
		let document = PDFDocument()
		document.insert(
			try #require(PDFPage(image: image)),
			at: 0
		)
		let pdfData = try #require(document.dataRepresentation())
		for (kind, bytes) in [(GitRichPreviewKind.image, imageData), (.pdf, pdfData)]
		{
			let preview = GitRichPreviewView(kind: kind)
			{
				bytes
			}
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 400,
					height: 600
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			defer
			{
				preview.cancelLoading()
				window.close()
			}
			let host = try #require(window.contentView)
			host.addSubview(preview)
			preview.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				preview.leadingAnchor.constraint(equalTo: host.leadingAnchor),
				preview.trailingAnchor.constraint(equalTo: host.trailingAnchor),
				preview.topAnchor.constraint(equalTo: host.topAnchor)
			])
			await preview.waitForLoading()
			settle(window)
			let content: NSView
			switch kind
			{
			case .image:
				let view = try #require(preview.subviews.compactMap
				{
					$0 as? NSImageView
				}.first)
				let loaded = try #require(view.image)
				#expect(loaded.size == NSSize(
					width: 100,
					height: 60
				))
				try expectFixturePixels(in: loaded)
				content = view
			case .pdf:
				let view = try #require(preview.subviews.compactMap
				{
					$0 as? PDFView
				}.first)
				let loaded = try #require(view.document)
				#expect(loaded.pageCount == 1)
				let page = try #require(loaded.page(at: 0))
				#expect(page.bounds(for: .mediaBox) == NSRect(
					x: 0,
					y: 0,
					width: 100,
					height: 60
				))
				try expectFixturePixels(in: page.thumbnail(
					of: NSSize(
						width: 100,
						height: 60
					),
					for: .mediaBox
				))
				content = view
			case .markdown:
				Issue.record("This fixture exercises image and PDF previews")
				continue
			}
			#expect(content.window === window)
			#expect(content.frame.width > 0 && content.frame.height > 0)
			#expect(preview.bounds.contains(content.frame))
		}
	}

	@Test func SVGSnapshotBytesRenderInGitPreview() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let snapshot = Data("""
			<svg xmlns="http://www.w3.org/2000/svg" width="17" height="11">
			<rect width="17" height="11" fill="red"/>
			</svg>
			""".utf8)
			let preview = GitRichPreviewView(kind: .image)
			{
				snapshot
			}
			defer
			{
				preview.cancelLoading()
			}
			await preview.waitForLoading()
			let image = try #require((preview.subviews.first as? NSImageView)?.image)
			#expect(image.size == NSSize(
				width: 17,
				height: 11
			))
			#expect(image.cgImage(
				forProposedRect: nil,
				context: nil,
				hints: nil
			) != nil)
		}
	}

	@Test(
		.timeLimit(.minutes(1)),
		arguments: ["throwing", "invalidUTF8", "image", "pdf"]
	)
	func failedPreviewsExplainTheProblemAndRestoreRetainedDiff(_ failure: String) async throws
	{
		_ = NSApplication.shared
		let section = makeSection()
		let outer = AppKitLayout.scrollableContent(
			section,
			inset: 0
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 680,
				height: 320
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentView = outer
		defer
		{
			window.close()
		}
		settle(window)
		let source = try #require(descendants(section).compactMap
		{
			$0 as? GitDiffTextView
		}.first)
		let originalText = source.string
		let selection = NSRange(
			location: 2,
			length: 5
		)
		source.setSelectedRange(selection)
		let originalBody = try #require(section.arrangedSubviews.last)
		let kind: GitRichPreviewKind = switch failure
		{
		case "image": .image
		case "pdf": .pdf
		default: .markdown
		}
		let expectedMessage = switch failure
		{
		case "image": "This image cannot be rendered as a rich preview."
		case "pdf": "This PDF cannot be rendered as a rich preview."
		default: "Rich preview unavailable. Refresh the comparison and retry."
		}
		section.toggleRichPreview
		{
			GitRichPreviewView(kind: kind)
			{
				if failure == "throwing"
				{
					throw GitComparisonFailure.repositoryChanged
				}
				return Data([0xFF, 0xFE, 0xFF])
			}
		}
		let preview = try #require(section.arrangedSubviews.last as? GitRichPreviewView)
		defer
		{
			preview.cancelLoading()
		}
		#expect(originalBody.isHidden)
		await preview.waitForLoading()
		settle(window)
		let messages = descendants(preview).compactMap
		{
			$0 as? NSTextField
		}
		#expect(messages.map(\.stringValue) == [expectedMessage])
		#expect(messages.first?.isHiddenOrHasHiddenAncestor == false)
		#expect(messages.first?.window === window)
		#expect((messages.first?.frame.height ?? 0) > 0)
		#expect(!descendants(preview).contains
		{
			$0 is NSImageView || $0 is PDFView || $0 is NSTextView
		})
		section.toggleRichPreview
		{
			Issue.record("Returning to the diff must not start another preview")
			return GitRichPreviewView(kind: .markdown)
			{
				Data()
			}
		}
		settle(window)
		#expect(!originalBody.isHidden)
		#expect(section.arrangedSubviews.last === originalBody)
		#expect(preview.superview == nil)
		#expect(descendants(section).contains
		{
			$0 === source
		})
		#expect(source.string == originalText)
		#expect(source.selectedRange() == selection)
	}

	private func expectFixturePixels(in image: NSImage) throws
	{
		let pixels = try #require(image.cgImage(
			forProposedRect: nil,
			context: nil,
			hints: nil
		))
		// Normalize pixel storage explicitly; colorAt can tag its result as calibrated RGB.
		let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
		let normalized = try #require(CGContext(
			data: nil,
			width: pixels.width,
			height: pixels.height,
			bitsPerComponent: 8,
			bytesPerRow: pixels.width * 4,
			space: colorSpace,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		))
		normalized.draw(
			pixels,
			in: CGRect(
				x: 0,
				y: 0,
				width: pixels.width,
				height: pixels.height
			)
		)
		let storage = try #require(normalized.data)
		let bytes = storage.assumingMemoryBound(to: UInt8.self)
		let offset = (pixels.height / 2 * pixels.width + pixels.width / 2) * 4
		#expect(abs(Double(bytes[offset]) / 255 - 0.125) < 0.05)
		#expect(abs(Double(bytes[offset + 1]) / 255 - 0.25) < 0.05)
		#expect(abs(Double(bytes[offset + 2]) / 255 - 0.75) < 0.05)
		#expect(Double(bytes[offset + 3]) / 255 > 0.99)
	}

	private func waitForText(_ view: GitRichPreviewView) async throws -> MarkdownTextView
	{
		await view.waitForLoading()
		return try #require(descendants(view).compactMap
		{
			$0 as? MarkdownTextView
		}.first)
	}

	private func button(
		_ label: String,
		in view: NSView
	) throws -> NSButton
	{
		try #require(descendants(view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.accessibilityLabel() == label
		})
	}

	private func makeSection() -> GitDiffFileSectionView
	{
		let patch = "index " + String(
			repeating: "a",
			count: 40
		) + ".."
			+ String(
				repeating: "b",
				count: 40
			) + " 100644\n"
		let row = GitDiffRow(
			id: "line",
			kind: .addition,
			text: String(
				repeating: "source ",
				count: 100
			),
			oldLine: nil,
			newLine: 1
		)
		return GitDiffFileSectionView(
			file: GitComparisonFile(
				oldPath: "README.md",
				newPath: "README.md",
				kind: .modified,
				additions: 1,
				deletions: 1,
				isBinary: false,
				patch: patch,
				hunks: [GitComparisonHunk(
					header: "@@ -1 +1 @@",
					text: "+source",
					oldStart: 1,
					newStart: 1
				)]
			),
			rows: [row],
			isCollapsed: false,
			layoutPreference: .unified,
			wrapsCode: false,
			onToggleFileDiff:
			{
				_ in
			},
			onExpandGap:
			{
				_ in
			},
			onRichPreview:
			{
				_ in
			}
		)
	}

	private func settle(_ window: NSWindow)
	{
		for _ in 0 ..< 5
		{
			window.contentView?.layoutSubtreeIfNeeded()
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}
