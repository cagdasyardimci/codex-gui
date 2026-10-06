import AppKit
import Foundation
import Testing

@testable import CodexGUI

@Suite
@MainActor
struct ComposerContextViewTests
{
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
		view.render(items: [item])
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
