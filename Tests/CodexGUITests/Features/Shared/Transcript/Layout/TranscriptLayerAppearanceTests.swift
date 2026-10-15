import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TranscriptLayerAppearanceTests
{
	@Test func loadingSkeletonRefreshesInheritedAppearanceWithoutRestartingLoading() throws
	{
		_ = NSApplication.shared
		let preview = TurnSummaryPreview(
			summary: ConversationTurnSummary(
				turnID: "loading",
				entryID: "loading:reference",
				title: "Earlier turn",
				reply: "Select to view this turn.",
				isContentLoaded: false
			),
			bookmarked: true
		)
		let window = makeWindow(preview)
		defer
		{
			detach(window)
		}
		let skeleton = try #require(preview.layer?.sublayers?.first)
		let bars = try #require(skeleton.sublayers)
		try #require(bars.count == 4)
		let frames = bars.map(\.frame)
		let animationKeys = skeleton.animationKeys()
		let bookmark = try #require(descendants(preview).compactMap
		{
			$0 as? NSButton
		}.first)
		for name in [NSAppearance.Name.aqua, .darkAqua, .aqua, .darkAqua]
		{
			window.appearance = try #require(NSAppearance(named: name))
			window.displayIfNeeded()
			let expected = resolved(
				.secondaryLabelColor,
				for: preview,
				alpha: 0.2
			)
			for bar in bars
			{
				try expectColor(
					bar.backgroundColor,
					expected
				)
			}
			#expect(preview.appearance == nil)
			#expect(preview.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
			#expect(preview.isLoading && !skeleton.isHidden)
			#expect(preview.cardHeight == 100)
			#expect(preview.accessibilityLabel() == "Loading turn preview")
			#expect(bookmark.isHidden)
			#expect(bookmark.accessibilityLabel() == "Remove turn bookmark")
			#expect(bars.map(\.frame) == frames)
			#expect(skeleton.animationKeys() == animationKeys)
			#expect(zip(
				bars,
				skeleton.sublayers ?? []
			).allSatisfy
			{
				pair in pair.0 === pair.1
			})
		}
	}

	@Test func reviewBorderRefreshesInheritedAppearanceAndPreservesFocusAndAction() throws
	{
		_ = NSApplication.shared
		let item = ConversationFileChangeCollectionItem()
		let change = try #require(FileChange(json: [
			"path": "/tmp/a.swift",
			"kind": "update",
			"diff": "@@ -1 +1 @@\n-old\n+new",
		]))
		var actions = 0
		item.configure(
			[change],
			status: "completed",
			onViewChanges:
			{
				actions += 1
			}
		)
		item.view.setFrameSize(NSSize(
			width: 480,
			height: 111
		))
		let window = makeWindow(item.view)
		defer
		{
			detach(window)
		}
		item.view.layoutSubtreeIfNeeded()
		let button = try #require(descendants(item.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == "View changes"
		})
		#expect(window.makeFirstResponder(button))
		button.state = .on
		let frame = button.frame
		for name in [NSAppearance.Name.aqua, .darkAqua, .aqua, .darkAqua]
		{
			window.appearance = try #require(NSAppearance(named: name))
			window.displayIfNeeded()
			try expectColor(
				button.layer?.borderColor,
				resolved(
					AppKitColorTokens.border,
					for: button
				)
			)
			#expect(button.appearance == nil)
			#expect(button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
			#expect(button.state == .on && button.isEnabled)
			#expect(window.firstResponder === button)
			#expect(button.frame == frame)
			#expect(button.title == "View changes")
			#expect(item.view.accessibilityLabel() == "Edited a.swift")
			#expect(button.layer?.cornerRadius == 10 && button.layer?.borderWidth == 1)
		}
		button.dispatchConfiguredAction()
		#expect(actions == 1)
	}

	// Native event polling and transient panels share the application event/window state.
	@Test func openCodeTooltipTracksOwnerAppearanceAndKeepsHoverFocusAndGeometry(
	) async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let native = TestTiming.begin("native.body")
			defer
			{
				native.end()
			}
			native.mark("application.shared.begin")
			_ = NSApplication.shared
			native.mark("application.shared.end")
			let body = "```text\nlet value = 1\n```"
			native.mark("item.init.begin")
			let item = ConversationCollectionItem()
			native.mark("item.init.end")
			native.mark("item.configure.begin")
			item.configure(
				ConversationEntry(
					id: "turn:reply",
					kind: .agent,
					title: "Codex",
					body: body
				),
				content: PreparedConversationContent(MarkdownContentParser.parse(
					body,
					markdown: true
				)),
				expanded: true,
				onToggle:
				{
				}
			)
			native.mark("item.configure.end")
			item.view.setFrameSize(NSSize(
				width: 480,
				height: 240
			))
			native.mark("window.init.begin")
			let window = makeWindow(item.view)
			native.mark("window.init.end")
			defer
			{
				native.mark("cleanup.window.begin")
				detach(window)
				native.mark("cleanup.window.end")
			}
			native.mark("layout.begin")
			window.appearance = try #require(NSAppearance(named: .aqua))
			item.view.layoutSubtreeIfNeeded()
			native.mark("layout.end")
			let button = try #require(descendants(item.view).compactMap
			{
				$0 as? NSButton
			}.first
			{
				$0.accessibilityLabel() == "Copy code block 1"
			})
			#expect(window.makeFirstResponder(button))
			native.mark("hover.begin")
			button.mouseEntered(with: try hoverEvent(.mouseEntered))
			native.mark("hover.end")
			defer
			{
				native.mark("cleanup.hover.begin")
				if let event = try? hoverEvent(.mouseExited)
				{
					button.mouseExited(with: event)
				}
				native.mark("cleanup.hover.end")
			}
			// Await the owned tooltip operation;
			// concurrent main-actor work can exceed a fixed margin.
			let copyButton = try #require(button as? CodeCopyButton)
			native.mark("tooltip.await.begin")
			await (try #require(copyButton.tooltipTask)).value
			native.mark("tooltip.await.end")
			let panel = try #require(window.childWindows?.first)
			let surface = try #require(panel.contentView)
			let label = try #require(descendants(surface).compactMap
			{
				$0 as? NSTextField
			}.first)
			let frame = panel.frame
			let buttonFrame = button.frame
			native.mark("appearance.assertions.begin")
			for name in [NSAppearance.Name.darkAqua, .aqua, .darkAqua]
			{
				window.appearance = try #require(NSAppearance(named: name))
				window.displayIfNeeded()
				panel.displayIfNeeded()
				#expect(button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
				#expect(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
				#expect(surface.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
				#expect(window.childWindows?.first === panel)
				#expect(panel.contentView === surface)
				#expect(panel.frame == frame && button.frame == buttonFrame)
				#expect(window.firstResponder === button)
				#expect(button.contentTintColor == NSColor.labelColor)
				#expect(label.stringValue == "Copy code")
				#expect(button.accessibilityLabel() == "Copy code block 1")
				try expectTooltipFill(
					surface,
					owner: button
				)
			}
			button.appearance = try #require(NSAppearance(named: .aqua))
			panel.displayIfNeeded()
			#expect(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
			try expectTooltipFill(
				surface,
				owner: button
			)
			button.appearance = nil
			panel.displayIfNeeded()
			#expect(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
			#expect(window.childWindows?.first === panel)
			#expect(window.firstResponder === button)
			native.mark("appearance.assertions.end")
			native.mark("dismiss.begin")
			button.mouseExited(with: try hoverEvent(.mouseExited))
			native.mark("dismiss.end")
			#expect(window.childWindows?.isEmpty != false)
			#expect(button.contentTintColor == NSColor.secondaryLabelColor)
		}
	}

	private func makeWindow(_ view: NSView) -> NSWindow
	{
		let window = NSWindow(
			contentRect: view.bounds,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentView = view
		return window
	}

	private func detach(_ window: NSWindow)
	{
		for child in window.childWindows ?? []
		{
			window.removeChildWindow(child)
			child.orderOut(nil)
		}
		window.contentView = nil
		window.orderOut(nil)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews + view.subviews.flatMap
		{
			descendants($0)
		}
	}

	private func resolved(
		_ color: NSColor,
		for view: NSView,
		alpha: CGFloat? = nil
	) -> NSColor
	{
		var result = NSColor.clear
		view.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			result = (alpha.map
			{
				color.withAlphaComponent($0)
			} ?? color)
				.usingColorSpace(.deviceRGB) ?? .clear
		}
		return result
	}

	private func expectColor(
		_ actual: CGColor?,
		_ expected: NSColor
	) throws
	{
		let color = try #require(actual.flatMap
		{
			NSColor(cgColor: $0)
		}?
		.usingColorSpace(.deviceRGB))
		#expect(abs(color.redComponent - expected.redComponent) < 0.001)
		#expect(abs(color.greenComponent - expected.greenComponent) < 0.001)
		#expect(abs(color.blueComponent - expected.blueComponent) < 0.001)
		#expect(abs(color.alphaComponent - expected.alphaComponent) < 0.001)
	}

	private func expectTooltipFill(
		_ surface: NSView,
		owner: NSView
	) throws
	{
		let bitmap = try #require(surface.bitmapImageRepForCachingDisplay(in: surface.bounds))
		surface.cacheDisplay(
			in: surface.bounds,
			to: bitmap
		)
		let scale = CGFloat(bitmap.pixelsHigh) / surface.bounds.height
		let sample = NSPoint(
			x: surface.bounds.midX,
			y: surface.bounds.maxY - 3
		)
		#expect(surface.subviews.allSatisfy
		{
			!$0.frame.contains(sample)
		})
		let pixel = try #require(bitmap.colorAt(
			x: bitmap.pixelsWide / 2,
			y: Int(3 * scale)
		))
		// colorAt labels cached-display bytes Generic RGB; retain the bitmap's actual profile.
		var components = [
			pixel.redComponent,
			pixel.greenComponent,
			pixel.blueComponent,
			pixel.alphaComponent,
		]
		let color = try #require(NSColor(
			colorSpace: bitmap.colorSpace,
			components: &components,
			count: components.count
		).usingColorSpace(.deviceRGB))
		let expected = resolved(
			AppKitColorTokens.inspector,
			for: owner
		)
		#expect(abs(color.redComponent - expected.redComponent) < 2 / 255)
		#expect(abs(color.greenComponent - expected.greenComponent) < 2 / 255)
		#expect(abs(color.blueComponent - expected.blueComponent) < 2 / 255)
	}

	private func hoverEvent(_ type: NSEvent.EventType) throws -> NSEvent
	{
		try #require(NSEvent.enterExitEvent(
			with: type,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			eventNumber: 0,
			trackingNumber: 0,
			userData: nil
		))
	}
}
