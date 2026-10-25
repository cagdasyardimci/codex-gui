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
		window.prepareForTesting()
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
		// Other fixtures may create unrelated windows while this preview loads.
		// Verify this component remains in its original owned hierarchy instead.
		let originalContent = window.contentView
		let section = try #require(descendants(controller.view).compactMap
		{
			$0 as? GitDiffFileSectionView
		}.first)
		let originalDocument = section.superview
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
		try button(
			"Show diff for README.md",
			in: controller.view
		).performClick(nil)
		#expect(!descendants(controller.view).contains
		{
			$0 is GitRichPreviewView
		})
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

	private func waitForText(_ view: NSView) async throws -> MarkdownTextView
	{
		for _ in 0 ..< 100
		{
			if let text = descendants(view).compactMap(
				{
					$0 as? MarkdownTextView
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
