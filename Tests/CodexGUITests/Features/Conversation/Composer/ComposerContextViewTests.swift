import AppKit
import Foundation
import Testing

@testable import CodexGUI

@Suite(
	.serialized
)
@MainActor
struct ComposerContextViewTests
{
	@Test func imageImportCreatesPreviewAndRemovalControl() async throws
	{
		_ = NSApplication.shared
		let directory = try await temporaryProject()
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
		#expect(findButton(
			in: view,
			title: "Inspect"
		) == nil)
		#expect(remove.alphaValue == 0)
		let tile = try #require(remove.superview as? ComposerImageAttachmentView)
		let event = try #require(NSEvent.otherEvent(
			with: .applicationDefined,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			subtype: 0,
			data1: 0,
			data2: 0
		))
		tile.mouseEntered(with: event)
		#expect(remove.alphaValue == 1)
		tile.mouseExited(with: event)
		#expect(remove.alphaValue == 0)

		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 500,
				height: 240
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentView = view
		defer
		{
			window.close()
		}
		view.layoutSubtreeIfNeeded()
		#expect(abs(tile.frame.width - 120) < 0.5)
		#expect(abs(tile.frame.height - 120) < 0.5)
		let closeFrame = tile.convert(
			remove.bounds,
			from: remove
		)
		#expect(abs(tile.bounds.maxX - closeFrame.maxX - 4) < 0.5)
		#expect(abs(tile.bounds.maxY - closeFrame.maxY - 4) < 0.5)
		#expect(!containsTextField(in: view))
		let expand = try #require(findButton(
			in: tile,
			title: ""
		))
		try #require(expand.dispatchConfiguredAction())
		await view.waitForExpandedPreview()
		let expanded = try #require(findExpandedPreview(in: view))
		#expect(findImageView(in: expanded)?.image != nil)
		#expect(window.attachedSheet == nil)
		view.render(items: [])
		#expect(expanded.superview == nil)
		try #require(remove.dispatchConfiguredAction())
		#expect(removedID == nil)
		view.render(items: [item])
		let currentRemove = try #require(findButton(
			in: view,
			title: "Remove"
		))
		try #require(currentRemove.dispatchConfiguredAction())
		#expect(removedID == item.id)
		let currentExpand = try #require(findButton(
			in: view,
			title: ""
		))
		try #require(currentExpand.dispatchConfiguredAction())
		await view.waitForExpandedPreview()
		let reopened = try #require(findExpandedPreview(in: view))
		window.contentView = NSView()
		#expect(reopened.superview == nil)
	}

	@Test func multipleImagesShareVisibleRowsAndWrapAfterResizing() throws
	{
		_ = NSApplication.shared
		let view = ComposerContextView()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 260,
				height: 400
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentView = view
		defer
		{
			window.close()
		}
		let items = (1 ... 3).map
		{
			ComposerContextItem(
				kind: .image,
				title: "Image \($0)"
			)
		}
		var removed: [String] = []
		view.onRemove =
		{
			removed.append($0)
		}
		view.render(items: items)
		view.layoutSubtreeIfNeeded()
		let tiles = imageTiles(in: view)
		try #require(tiles.count == 3)
		let frames = tiles.map
		{
			view.convert(
				$0.bounds,
				from: $0
			)
		}
		#expect(abs(frames[0].minY - frames[1].minY) < 0.5)
		#expect(frames[0].maxX <= frames[1].minX)
		#expect(abs(frames[0].minY - frames[2].minY) >= 120)
		#expect(frames.allSatisfy
		{
			view.bounds.contains($0)
		})
		let secondRemove = try #require(findButton(
			in: tiles[1],
			title: "Remove"
		))
		try #require(secondRemove.dispatchConfiguredAction())
		#expect(removed == [items[1].id])
		window.setContentSize(NSSize(
			width: 140,
			height: 400
		))
		view.layoutSubtreeIfNeeded()
		let narrowFrames = imageTiles(in: view).map
		{
			view.convert(
				$0.bounds,
				from: $0
			)
		}
		#expect(view.bounds.width == 140)
		#expect(narrowFrames.count == 3)
		#expect(Set(narrowFrames.map(\.minY)).count == 3)
		#expect(narrowFrames.allSatisfy
		{
			view.bounds.contains($0)
		})
	}

	@Test(arguments: [400, 600, 900])
	func imageTilesFillTheSquareAndCenterTheCrop(width: Int) throws
	{
		_ = NSApplication.shared
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: width,
			pixelsHigh: 400,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		try #require(!bitmap.isPlanar && bitmap.samplesPerPixel == 4
			&& bitmap.bitsPerSample == 8 && bitmap.bitsPerPixel == 32
			&& bitmap.bitmapFormat.rawValue == 0)
		let rowBytes = width * 4
		try #require(bitmap.bytesPerRow >= rowBytes)
		let pixels = try #require(bitmap.bitmapData)
		var row = [UInt8](
			repeating: 0,
			count: rowBytes
		)
		for x in 0 ..< width
		{
			let offset = x * 4
			row[offset] = x < width / 4 ? 255 : 0
			row[offset + 1] = x >= width / 4 && x < width * 3 / 4 ? 255 : 0
			row[offset + 2] = x >= width * 3 / 4 ? 255 : 0
			row[offset + 3] = 255
		}
		// Each row has identical stripes; respect the native stride while copying pixel bytes.
		try row.withUnsafeBytes
		{
			bytes in
			let source = try #require(bytes.baseAddress)
			for y in 0 ..< bitmap.pixelsHigh
			{
				UnsafeMutableRawPointer(pixels).advanced(by: y * bitmap.bytesPerRow)
					.copyMemory(
						from: source,
						byteCount: rowBytes
					)
			}
		}
		let image = NSImage(size: NSSize(
			width: width,
			height: 400
		))
		image.addRepresentation(bitmap)
		let tile = ComposerImageAttachmentView(
			image: image,
			previewButton: NSButton(),
			removeButton: NSButton()
		)
		tile.frame.size = NSSize(
			width: 120,
			height: 120
		)
		tile.layoutSubtreeIfNeeded()
		let imageView = try #require(findImageView(in: tile))
		let rendered = try #require(imageView.bitmapImageRepForCachingDisplay(in: imageView.bounds))
		imageView.cacheDisplay(
			in: imageView.bounds,
			to: rendered
		)
		for y in [10, rendered.pixelsHigh / 2, rendered.pixelsHigh - 10]
		{
			let center = try #require(rendered.colorAt(
				x: rendered.pixelsWide / 2,
				y: y
			))
			#expect(center.greenComponent > 0.9 && center.alphaComponent > 0.9)
			let left = try #require(rendered.colorAt(
				x: 10,
				y: y
			))
			let right = try #require(rendered.colorAt(
				x: rendered.pixelsWide - 10,
				y: y
			))
			if width == 900
			{
				#expect(left.greenComponent > 0.9 && right.greenComponent > 0.9)
			}
			else
			{
				#expect(left.redComponent > 0.9 && right.blueComponent > 0.9)
			}
		}
	}

	@Test func contextThumbnailsAreBoundedAndRetiredLoadsCannotReplaceNewRows() async throws
	{
		_ = NSApplication.shared
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("context-thumbnail-\(UUID()).png")
		defer
		{
			try? FileManager.default.removeItem(at: url)
		}
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: 1_200,
			pixelsHigh: 600,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		try #require(bitmap.bitmapData).initialize(
			repeating: 0,
			count: bitmap.bytesPerRow * bitmap.pixelsHigh
		)
		let bytes = try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
		try await BackgroundTestWork.perform
		{
			try bytes.write(to: url)
		}
		let item = ComposerContextItem(
			id: "image",
			kind: .image,
			title: "Large image",
			path: url.path
		)
		let view = ComposerContextView()
		view.render(items: [item])
		let retired = try #require(imageTiles(in: view).first)
		let retiredImage = findImageView(in: retired)?.image
		let pending = Array(view.imageTasks.values)
		view.render(items: [ComposerContextItem(
			id: "replacement",
			kind: .image,
			title: "Missing"
		)])
		for task in pending
		{
			await task.value
		}
		await view.waitForImages()
		#expect(findImageView(in: retired)?.image === retiredImage)
		#expect(imageTiles(in: view).first !== retired)
		view.render(items: [item])
		await view.waitForImages()
		#expect(view.imageTasks.isEmpty)
		let tile = try #require(imageTiles(in: view).first)
		let image = try #require(findImageView(in: tile)?.image)
		let pixels = try #require(image.cgImage(
			forProposedRect: nil,
			context: nil,
			hints: nil
		))
		#expect(pixels.width == 240 && pixels.height == 120)
		for width: CGFloat in [260, 140, 500]
		{
			view.frame.size = NSSize(
				width: width,
				height: 400
			)
			view.layoutSubtreeIfNeeded()
			#expect(imageTiles(in: view).first === tile)
			#expect(findImageView(in: tile)?.image === image)
		}
	}

	private func findExpandedPreview(in view: NSView) -> NSView?
	{
		if view.accessibilityIdentifier() == "expanded-image-preview"
		{
			return view
		}
		return view.subviews.lazy.compactMap
		{
			findExpandedPreview(in: $0)
		}.first
	}

	private func imageTiles(in view: NSView) -> [ComposerImageAttachmentView]
	{
		if let tile = view as? ComposerImageAttachmentView
		{
			return [tile]
		}
		return view.subviews.flatMap
		{
			imageTiles(in: $0)
		}
	}

	private func containsTextField(in view: NSView) -> Bool
	{
		view is NSTextField || view.subviews.contains
		{
			containsTextField(in: $0)
		}
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

	nonisolated private func temporaryProject() async throws -> URL
	{
		try await BackgroundTestWork.perform
		{
			let url = FileManager.default.temporaryDirectory
				.appendingPathComponent(UUID().uuidString)
			try FileManager.default.createDirectory(
				at: url,
				withIntermediateDirectories: true
			)
			return url
		}
	}
}
