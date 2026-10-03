import AppKit
import Testing

@testable import CodexGUI

/// Offline design renders run only when the preview script provides an output directory.
@Suite @MainActor
struct GitReviewDesignPreviewTests
{
	@Test func optionalComparisonRenders() async throws
	{
		guard ProcessInfo.processInfo.environment["CODEX_DESIGN_PREVIEW_DIR"] != nil
		else
		{
			return
		}
		try await GitReviewDesignPreviewSupport(capture: savePreview).renderComparison()
	}

	@Test func optionalPinnedSummaryActivityAndAttachmentRenders() throws
	{
		guard ProcessInfo.processInfo.environment["CODEX_DESIGN_PREVIEW_DIR"] != nil
		else
		{
			return
		}
		try GitReviewDesignPreviewSupport(capture: savePreview)
			.renderPinnedSummaryActivityAndAttachments()
	}

	private func savePreview(
		_ view: NSView,
		named filename: String
	) throws
	{
		guard let directory = ProcessInfo.processInfo.environment["CODEX_DESIGN_PREVIEW_DIR"]
		else
		{
			return
		}
		let output = URL(
			fileURLWithPath: directory,
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: output,
			withIntermediateDirectories: true
		)
		view.layoutSubtreeIfNeeded()
		let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
		view.cacheDisplay(
			in: view.bounds,
			to: bitmap
		)
		let bytes = try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
		try bytes.write(
			to: output.appendingPathComponent(filename),
			options: .atomic
		)
	}
}
