import AppKit
import PDFKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitInlineRichPreviewTests
{
	@Test func eyeButtonExpandsCollapsedFileAndLoadsPreviewInChangesViewer() async throws
	{
		_ = NSApplication.shared
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
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
		for _ in 0 ..< 100
		{
			if controller.runtime.state.snapshot?.request.scope == .unstaged
			{
				break
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		_ = try #require(controller.runtime.state.snapshot)
		settle(window)
		try button(
			"Collapse diff for README.md",
			in: controller.view
		).performClick(nil)
		_ = try button(
			"Expand diff for README.md",
			in: controller.view
		)
		let windows = NSApplication.shared.windows.map(\.windowNumber)
		try button(
			"Rich preview of README.md",
			in: controller.view
		).performClick(nil)
		let preview = try #require(descendants(controller.view).compactMap
		{
			$0 as? GitRichPreviewView
		}.first)
		let text = try await waitForText(preview)
		settle(window)
		#expect(text.string.hasPrefix("Inline preview"))
		#expect(preview.window === window)
		#expect(NSApplication.shared.windows.map(\.windowNumber) == windows)
		_ = try button(
			"Collapse diff for README.md",
			in: controller.view
		)
		try button(
			"Show diff for README.md",
			in: controller.view
		).performClick(nil)
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
		let windows = NSApplication.shared.windows.map(\.windowNumber)
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
		#expect(NSApplication.shared.windows.map(\.windowNumber) == windows)
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
		let image = NSImage(size: NSSize(
			width: 100,
			height: 60
		))
		image.lockFocus()
		NSColor.systemBlue.setFill()
		NSRect(
			x: 0,
			y: 0,
			width: 100,
			height: 60
		).fill()
		image.unlockFocus()
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
			for _ in 0 ..< 100
			{
				if preview.subviews
					.contains(where:
						{
							$0 is NSImageView || $0 is PDFView
						})
				{
					break
				}
				try await Task.sleep(for: .milliseconds(10))
			}
			#expect(preview.subviews.contains
			{
				$0 is NSImageView || $0 is PDFView
			})
		}
	}

	private func waitForText(_ view: NSView) async throws -> ConversationMarkdownTextView
	{
		for _ in 0 ..< 100
		{
			if let text = descendants(view).compactMap(
				{
					$0 as? ConversationMarkdownTextView
				}
			)
			.first
			{
				return text
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		Issue.record("Inline Markdown did not finish loading")
		throw GitComparisonFailure.repositoryUnavailable
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
