import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(.serialized)
struct DesktopCompletePresentationTests
{
	@Test func codeAndTerminalCopyUseTheSameTooltipStyleAndKeepFocus() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let window = TranscriptPointerTestWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 240,
					height: 120
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			window.pointerLocation = .zero
			let code = CodeCopyButton(frame: NSRect(
				x: 20,
				y: 40,
				width: 24,
				height: 24
			))
			let terminal = ConversationTerminalCopyButton(
				frame: NSRect(
					x: 80,
					y: 40,
					width: 24,
					height: 24
				)
			)
			terminal.setCopyImage(DesktopIcons.image(.copy))
			terminal.toolTip = "Copy code"
			let content = try #require(window.contentView)
			content.addSubview(code)
			content.addSubview(terminal)
			defer
			{
				code.resetInteraction()
				terminal.resetHover()
				window.close()
			}
			window.orderFront(nil)
			let originalResponder = window.firstResponder
			let enter = try hoverEvent(.mouseEntered)
			code.mouseEntered(with: enter)
			await (try #require(code.tooltipTask)).value
			let codePanel = try #require(window.childWindows?.first)
			window.pointerLocation = NSPoint(
				x: 92,
				y: 52
			)
			terminal.mouseEntered(with: enter)
			await (try #require(terminal.tooltipTask)).value
			let terminalPanel = try #require(window.childWindows?.first
			{
				$0 !== codePanel
			})
			let codeTooltip = try #require(codePanel.contentView as? DesktopTooltipView)
			let terminalTooltip = try #require(terminalPanel.contentView as? DesktopTooltipView)
			#expect(codeTooltip.label.stringValue == terminalTooltip.label.stringValue)
			#expect(codeTooltip.label.font == terminalTooltip.label.font)
			#expect(codeTooltip.label.textColor == terminalTooltip.label.textColor)
			#expect(codeTooltip.bounds.size == terminalTooltip.bounds.size)
			#expect(codeTooltip.label.frame == terminalTooltip.label.frame)
			#expect(window.firstResponder === originalResponder)
			for name: NSAppearance.Name in [.darkAqua, .aqua]
			{
				window.appearance = NSAppearance(named: name)
				#expect(codeTooltip.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
				#expect(terminalTooltip.effectiveAppearance
					.bestMatch(from: [.aqua, .darkAqua]) == name)
			}
			code.resetInteraction()
			terminal.resetHover()
			#expect(codePanel.parent == nil && terminalPanel.parent == nil)
			#expect(!codePanel.isVisible && !terminalPanel.isVisible)
			code.mouseEntered(with: enter)
			let canceled = try #require(code.tooltipTask)
			code.resetInteraction()
			await canceled.value
			#expect(window.childWindows?.isEmpty != false)
		}
	}

	@Test func longTooltipWrapsInsideItsBoundedSurface()
	{
		let tooltip = DesktopTooltipView(text: String(
			repeating: "Readable tooltip content. ",
			count: 8
		))
		let size = tooltip.measuredSize(maximumWidth: 180)
		#expect(size.width <= 180)
		#expect(size.height > 28)
		#expect(tooltip.bounds.contains(tooltip.label.frame))
		#expect(tooltip.label.cell?.wraps == true)
	}

	@Test func taskAndSourcesPreviewsUseTheSameContentShell() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let window = PreviewWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 400,
					height: 240
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			let anchor = NSButton(frame: NSRect(
				x: 20,
				y: 60,
				width: 100,
				height: 24
			))
			try #require(window.contentView).addSubview(anchor)
			let task = TaskHoverCard(
				title: "Task",
				projectName: "Project",
				updatedAt: nil
			)
			let sources = SourcesTabHoverPreview()
			defer
			{
				task.dismiss()
				sources.dismiss()
				window.close()
			}
			task.show(beside: anchor)
			let taskPanel = try #require(task.panel)
			await sources.show(
				sources: ConversationLocalSources(entries: []),
				below: anchor
			).value
			let sourcePanel = try #require(window.childWindows?.first
			{
				$0 !== taskPanel
			})
			let taskSurface = try #require(taskPanel.contentView as? DesktopHoverPreviewSurface)
			let sourceSurface = try #require(sourcePanel.contentView as? DesktopHoverPreviewSurface)
			#expect(taskPanel.frame.width == sourcePanel.frame.width)
			#expect(taskPanel.ignoresMouseEvents && sourcePanel.ignoresMouseEvents)
			for surface in [taskSurface, sourceSurface]
			{
				surface.layoutSubtreeIfNeeded()
				let slot = try #require(surface.subviews.first)
				#expect(abs(slot.frame.minX - DesktopHoverPreviewSurface.contentInset) < 0.5)
				#expect(abs(surface.bounds.maxX - slot.frame.maxX
						- DesktopHoverPreviewSurface.contentInset) < 0.5)
			}
		}
	}

	@Test func disclosureOwnsExpansionAccessibilityFocusRevealAndActionRouting() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let window = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 240,
					height: 120
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			defer
			{
				window.close()
			}
			let target = DisclosureTarget()
			let button = DesktopDisclosureButton(
				title: "Details",
				presentation: .hoverReveal,
				target: target,
				action: #selector(DisclosureTarget.invoke(_:))
			)
			button.frame = NSRect(
				x: 20,
				y: 20,
				width: 160,
				height: 21
			)
			try #require(window.contentView).addSubview(button)
			button.setContextHovered(false)
			let resting = button.image?.tiffRepresentation
			#expect(window.makeFirstResponder(button))
			#expect(button.image?.tiffRepresentation != resting)
			#expect(window.makeFirstResponder(nil))
			#expect(button.image?.tiffRepresentation == resting)
			button.setExpanded(true)
			#expect(button.accessibilityValue() as? String == "Expanded")
			#expect(button.accessibilityLabel() == "Collapse Details")
			#expect(button.dispatchConfiguredAction())
			#expect(target.invocations == 1)
			#expect(target.expanded)
		}
	}

	@Test func outputDisclosureOwnsItsShowHideLabelAndExpansionAction()
	{
		_ = NSApplication.shared
		let target = DisclosureTarget()
		let button = DesktopDisclosureButton(
			presentation: .output,
			target: target,
			action: #selector(DisclosureTarget.invoke(_:))
		)
		#expect(button.title == "Show output")
		#expect(button.accessibilityLabel() == "Show output")
		#expect(button.toolTip == "Show output")
		#expect(button.imagePosition == .imageLeading)
		button.setExpanded(true)
		#expect(button.title == "Hide output")
		#expect(button.accessibilityLabel() == "Hide output")
		#expect(button.toolTip == "Hide output")
		#expect(button.dispatchConfiguredAction())
		#expect(target.invocations == 1 && target.expanded)
	}

	@MainActor
	private final class DisclosureTarget: NSObject
	{
		var invocations = 0
		var expanded = false

		@objc func invoke(_ button: DesktopDisclosureButton)
		{
			invocations += 1
			expanded = button.state == .on
		}
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

	@MainActor
	private final class PreviewWindow: NSWindow
	{
		override var isKeyWindow: Bool
		{
			true
		}
	}
}
