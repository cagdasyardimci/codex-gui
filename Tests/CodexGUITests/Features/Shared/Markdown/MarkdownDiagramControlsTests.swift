import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct MarkdownDiagramControlsTests
{
	@Test func diagramsKeepSourceActionsAndResizeWithoutStaleControls() throws
	{
		let textView = MarkdownTextView(frame: NSRect(
			x: 0,
			y: 0,
			width: 600,
			height: 800
		))
		textView.textContainer?.widthTracksTextView = true
		let image = NSImage(size: NSSize(
			width: 200,
			height: 300
		))
		let source = "```mermaid\nclassDiagram\nDocument *-- Block\n```"
		let attachment = MarkdownRichAttachment(
			source: source,
			lightImage: image,
			darkImage: image,
			isDiagram: true
		)
		textView.installContent(NSAttributedString(attachment: attachment))
		textView.updateDiagramControls()
		let controls = try #require(textView.subviews.compactMap
		{
			$0 as? MarkdownDiagramControls
		}
		.first)
		textView.updateDiagramControlVisibility(at: nil)
		#expect(controls.alphaValue == 0)
		textView.updateDiagramControlVisibility(at: controls.frame.origin)
		#expect(controls.alphaValue == 1)
		textView.updateDiagramControlVisibility(at: nil)
		#expect(controls.alphaValue == 0)
		#expect(controls.makeMenu().items.map(\.title) == ["Copy as code", "Download image"])
		#expect(controls.expandButton.accessibilityLabel() == "Expand diagram")
		var expandedImage: NSImage?
		controls.onExpand =
		{
			expandedImage = $0
		}
		#expect(controls.expandButton.sendAction(
			controls.expandButton.action,
			to: controls
		))
		#expect(expandedImage === image)
		textView.setFrameSize(NSSize(
			width: 320,
			height: 800
		))
		textView.updateDiagramControls()
		#expect(controls.frame.maxX <= textView.bounds.width)
		#expect(controls.frame.minX >= 0)
		textView.installContent(NSAttributedString(string: "Replacement"))
		textView.updateDiagramControls()
		#expect(controls.superview == nil)
		#expect(attachment.source == source)
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		controls.copyCode(to: pasteboard)
		#expect(pasteboard.string(forType: .string) == source)
	}

	@Test func expandedDiagramUsesNaturalSizeAndRoutesZoomAndClose() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 1000,
					height: 800
				),
				styleMask: [.titled, .resizable],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.appearance = NSAppearance(named: .aqua)
			let preview = ExpandedImagePreview()
			defer
			{
				preview.dismiss(); window.close()
			}
			let svg = Data(
				("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"220\" height=\"500\">"
					+ "<rect width=\"220\" height=\"500\" fill=\"#5796ff\"/></svg>").utf8
			)
			let image = try #require(MarkdownSVGImage(
				data: svg,
				size: NSSize(
					width: 220,
					height: 500
				)
			))
			preview.present(
				path: "",
				name: "Diagram",
				in: window,
				preparedDiagram: image
			)
			let controller = try #require(preview.controller)
			let overlayWindow = try #require(controller.view.window)
			#expect(overlayWindow !== window)
			#expect(overlayWindow.parent === window)
			#expect(overlayWindow.frame == window.frame)
			#expect(overlayWindow.canBecomeKey)
			#expect(controller.view.bounds.size == window.frame.size)
			#expect(controller.view.bounds.height > (window.contentView?.bounds.height ?? 0))
			#expect(controller.backdropView.isHidden)
			#expect(controller.originalPixelSize == image.size)
			#expect(controller.displayedZoomPercentage == 100)
			let buttons = descendants(controller.view).compactMap
			{
				$0 as? NSButton
			}
			let plus = try #require(buttons.first
			{
				$0.accessibilityLabel() == "Zoom in"
			})
			#expect(plus.sendAction(
				plus.action,
				to: plus.target
			))
			#expect(controller.displayedZoomPercentage == 110)
			let minus = try #require(buttons.first
			{
				$0.accessibilityLabel() == "Zoom out"
			})
			#expect(minus.sendAction(
				minus.action,
				to: minus.target
			))
			#expect(controller.displayedZoomPercentage == 100)
			controller.setZoom(1.97)
			#expect(controller.displayedZoomPercentage == 197)
			#expect(controller.scrollView.allowsMagnification)
			let download = try #require(buttons.first
			{
				$0.accessibilityLabel() == "Download image"
			})
			#expect(download.frame.width == download.frame.height)
			controller.view.layoutSubtreeIfNeeded()
			let bounds = controller.view.bounds
			let close = controller.closeButton.frame
			#expect(close.size == NSSize(
				width: 42,
				height: 40
			))
			#expect(abs(bounds.maxX - close.maxX - 12) < 0.01)
			#expect(abs(bounds.maxY - close.maxY - 12) < 0.01)
			#expect(download.frame.size == NSSize(
				width: 40,
				height: 40
			))
			#expect(abs(bounds.maxX - download.frame.maxX - 62) < 0.01)
			#expect(abs(bounds.maxY - download.frame.maxY - 12) < 0.01)
			#expect(plus.frame.size == NSSize(
				width: 36,
				height: 36
			))
			#expect(minus.frame.size == NSSize(
				width: 36,
				height: 36
			))
			let zoomPill = try #require(plus.superview)
			#expect(zoomPill.frame.size == NSSize(
				width: 152,
				height: 44
			))
			let canvasView = try #require(controller.scrollView.superview)
			let canvas = canvasView.frame
			#expect(abs(canvas.minX - bounds.minX - 32) < 0.01)
			#expect(abs(bounds.maxX - canvas.maxX - 32) < 0.01)
			#expect(abs(bounds.maxY - canvas.maxY - 48) < 0.01)
			#expect(abs(canvas.minY - bounds.minY - 96) < 0.01)
			#expect(canvasView.layer?.cornerRadius == 20)
			#expect(controller.scrollView.frame == canvasView.bounds.insetBy(
				dx: 16,
				dy: 16
			))
			#expect(controller.scrollView.layer?.masksToBounds == true)
			#expect(controller.imageView.image === image)
			#expect(image.representations.allSatisfy
			{
				!($0 is NSBitmapImageRep)
			})
			let exported = try #require(MarkdownDiagramExport.file(image))
			#expect(exported.data == svg)
			#expect(exported.contentType.identifier == "public.svg-image")
			#expect(exported.name == "diagram.svg")
			var resizedFrame = window.frame
			resizedFrame.size.width += 100
			resizedFrame.size.height += 80
			window.setFrame(
				resizedFrame,
				display: false
			)
			NotificationCenter.default.post(
				name: NSWindow.didResizeNotification,
				object: window
			)
			#expect(overlayWindow.frame == window.frame)
			#expect(controller.view.bounds.size == window.frame.size)
			#expect(controller.closeButton.sendAction(
				controller.closeButton.action,
				to: controller.closeButton.target
			))
			#expect(preview.controller == nil)
			#expect(overlayWindow.parent == nil)
			#expect(overlayWindow.isVisible == false)
			#expect(controller.view.window == nil)
		}
	}

	@Test func oversizedDiagramFitsWithinThePaddedCanvas() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 1000,
					height: 800
				),
				styleMask: [.titled, .resizable],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			let preview = ExpandedImagePreview()
			defer
			{
				preview.dismiss(); window.close()
			}
			let svg = Data(
				("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1512\" height=\"220\">"
					+ "<rect width=\"1512\" height=\"220\" fill=\"#5796ff\"/></svg>").utf8
			)
			let image = try #require(MarkdownSVGImage(
				data: svg,
				size: NSSize(
					width: 1512,
					height: 220
				)
			))
			preview.present(
				path: "",
				name: "Gantt",
				in: window,
				preparedDiagram: image
			)
			let controller = try #require(preview.controller)
			controller.view.layoutSubtreeIfNeeded()
			let canvas = try #require(controller.scrollView.superview)
			#expect(controller.scrollView.frame == canvas.bounds.insetBy(
				dx: 16,
				dy: 16
			))
			#expect(abs(controller.scrollView.contentSize.width - 904) < 0.01)
			#expect(abs(controller.scrollView.magnification - CGFloat(904) / 1512) < 0.001)
			#expect(controller.displayedZoomPercentage == 60)
			controller.setZoom(2)
			#expect(controller.scrollView.frame == canvas.bounds.insetBy(
				dx: 16,
				dy: 16
			))
			#expect(controller.scrollView.contentView.documentVisibleRect.width < image.size.width)
			#expect(controller.imageView.image === image)
		}
	}

	@Test func diagramZoomUsesReferenceStopsAndClampsItsRange() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 1000,
					height: 800
				),
				styleMask: [.titled, .resizable],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			let preview = ExpandedImagePreview()
			defer
			{
				preview.dismiss(); window.close()
			}
			preview.present(
				path: "",
				name: "Diagram",
				in: window,
				preparedDiagram: NSImage(size: NSSize(
					width: 220,
					height: 500
				))
			)
			let controller = try #require(preview.controller)
			let buttons = descendants(controller.view).compactMap
			{
				$0 as? NSButton
			}
			let plus = try #require(buttons.first
			{
				$0.accessibilityLabel() == "Zoom in"
			})
			let minus = try #require(buttons.first
			{
				$0.accessibilityLabel() == "Zoom out"
			})
			let stops = [
				25,
				33,
				50,
				67,
				75,
				80,
				90,
				100,
				110,
				125,
				150,
				175,
				200,
				250,
				300,
				400,
				500
			]
			#expect(controller.scrollView.minMagnification == 0.25)
			#expect(controller.scrollView.maxMagnification == 5)
			controller.setZoom(0.01)
			#expect(controller.displayedZoomPercentage == 25)
			#expect(!minus.isEnabled)
			for stop in stops.dropFirst()
			{
				#expect(plus.isEnabled)
				#expect(plus.sendAction(
					plus.action,
					to: plus.target
				))
				#expect(controller.displayedZoomPercentage == stop)
			}
			#expect(!plus.isEnabled)
			for stop in stops.dropLast().reversed()
			{
				#expect(minus.isEnabled)
				#expect(minus.sendAction(
					minus.action,
					to: minus.target
				))
				#expect(controller.displayedZoomPercentage == stop)
			}
			#expect(!minus.isEnabled)
			controller.setZoom(10)
			#expect(controller.displayedZoomPercentage == 500)
			#expect(!plus.isEnabled)
			controller.setZoom(1.97)
			#expect(plus.sendAction(
				plus.action,
				to: plus.target
			))
			#expect(controller.displayedZoomPercentage == 200)
			controller.setZoom(1.97)
			#expect(minus.sendAction(
				minus.action,
				to: minus.target
			))
			#expect(controller.displayedZoomPercentage == 175)
		}
	}

	@Test(arguments: [false, true])
	func referenceDiagramsRenderWithoutCodeCardsAndExpand(isSequence: Bool) async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let sequence = "```mermaid\nsequenceDiagram\nUser->>Renderer: Markdown source\n"
				+ "Renderer-->>User: Rendered output\n```"
			let source = isSequence ? sequence : """
			```mermaid
			classDiagram
			    class Document {
			        +String title
			        +render()
			    }
			    class Block {
			        +String content
			        +parse()
			    }
			    class CodeBlock {
			        +String language
			        +highlight()
			    }
			    Document "1" *-- "0..*" Block : contains
			    Block <|-- CodeBlock
			```
			"""
			let parsed = MarkdownContentParser.parse(
				source,
				markdown: true
			)
			#expect(parsed.runs.allSatisfy
			{
				!$0.style.codeHeader && !$0.style.codeBlock
			})
			let images = await MarkdownMermaidRenderer.prepare(parsed: parsed)
			if isSequence
			{
				let pair = try #require(images.values.first)
				let cgImage = try #require(pair.light.cgImage(
					forProposedRect: nil,
					context: nil,
					hints: nil
				))
				let bitmap = NSBitmapImageRep(cgImage: cgImage)
				// Midway between actor boxes, lifelines must be gray rather than node-border blue.
				let row = bitmap.pixelsHigh / 2
				let bluePixels = (0 ..< bitmap.pixelsWide).filter
				{
					x in
					guard let color = bitmap.colorAt(
						x: x,
						y: row
					)?.usingColorSpace(.deviceRGB)
					else
					{
						return false
					}
					return color.alphaComponent > 0.8
						&& color.blueComponent - color.redComponent > 0.15
						&& color.blueComponent - color.greenComponent > 0.10
				}
				#expect(bluePixels.isEmpty)
			}
			let rendered = MarkdownAttributedStringRenderer.render(
				parsed.runs,
				preparedDiagramImages: images
			)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 1200,
					height: 900
				),
				styleMask: [.titled, .resizable],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.appearance = NSAppearance(named: .aqua)
			let text = MarkdownTextView(frame: NSRect(
				x: 0,
				y: 0,
				width: 1200,
				height: 900
			))
			text.isEditable = false
			window.contentView = text
			defer
			{
				text.dismissExpandedImage(); window.close()
			}
			text.installContent(rendered)
			text.layoutSubtreeIfNeeded()
			let controls = try #require(text.subviews.compactMap
			{
				$0 as? MarkdownDiagramControls
			}.first)
			#expect(controls.attachment.isDiagram)
			#expect(controls.attachment.rendersNativeImage)
			try capture(
				text,
				name: isSequence ? "sequence-inline" : "inline"
			)
			#expect(controls.expandButton.sendAction(
				controls.expandButton.action,
				to: controls
			))
			let overlayWindow = try #require(window.childWindows?.first)
			#expect(overlayWindow.parent === window)
			let overlayHost = try #require(overlayWindow.contentView)
			overlayHost.layoutSubtreeIfNeeded()
			let expanded = try #require(descendants(overlayHost).first
			{
				$0.accessibilityIdentifier() == "expanded-image-preview"
			})
			#expect(expanded.superview === overlayHost)
			try capture(
				expanded,
				name: isSequence ? "sequence-expanded" : "expanded"
			)
			let plus = try #require(descendants(expanded).compactMap
			{
				$0 as? NSButton
			}.first
			{
				$0.accessibilityLabel() == "Zoom in"
			})
			for _ in 0 ..< 3
			{
				#expect(plus.sendAction(
					plus.action,
					to: plus.target
				))
			}
			try capture(
				expanded,
				name: isSequence ? "sequence-zoomed" : "zoomed"
			)
			text.installContent(NSAttributedString(string: "Replacement"))
			#expect(overlayWindow.parent == nil)
			#expect(!descendants(overlayHost).contains
			{
				$0.accessibilityIdentifier() == "expanded-image-preview"
			})
		}
	}

	@Test func diagramSourceRangesAndRegularCodeHeadersRemainIndependent() throws
	{
		let source = "```mermaid\nsequenceDiagram\nA->>B: Hello\n```\n\n```swift\nlet x = 1\n```"
		let parsed = MarkdownContentParser.parse(
			source,
			markdown: true
		)
		#expect(parsed.codeBlocks == ["sequenceDiagram\nA->>B: Hello\n", "let x = 1\n"])
		#expect(parsed.runs.filter
		{
			$0.style.codeHeader
		}.count == 1)
		let rendered = MarkdownAttributedStringRenderer.render(parsed.runs)
		let diagramRange = try #require(parsed.codeBlockRanges.first)
		#expect(rendered.attribute(
			.markdownCodeBlockID,
			at: diagramRange.location,
			effectiveRange: nil
		) == nil)
		let diagram = try #require(rendered.attribute(
			.attachment,
			at: diagramRange.location,
			effectiveRange: nil
		) as? MarkdownRichAttachment)
		#expect(diagram.source == "```mermaid\nsequenceDiagram\nA->>B: Hello\n```")
		let codeRange = try #require(parsed.codeBlockRanges.last)
		#expect((rendered.string as NSString).substring(with: codeRange) == "let x = 1\n")
		#expect(rendered.attribute(
			.markdownCodeBlockID,
			at: codeRange.location,
			effectiveRange: nil
		) != nil)
	}

	private func capture(
		_ view: NSView,
		name: String
	) throws
	{
		guard let directory = ProcessInfo.processInfo.environment["CODEX_GUI_DIAGRAM_CAPTURE_DIR"]
		else
		{
			return
		}
		view.layoutSubtreeIfNeeded()
		let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
		view.cacheDisplay(
			in: view.bounds,
			to: bitmap
		)
		let data = try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
		try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}
}
