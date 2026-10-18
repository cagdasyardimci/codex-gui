import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ViewerNavigatorSplitViewTests
{
	@Test(.timeLimit(.minutes(1)))
	func panInterruptingShowRestoresVisibleMinimum() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let navigator = NSView()
			let pan = NSPanGestureRecognizer()
			let split = ViewerNavigatorSplitView(
				document: IntrinsicWidthDocument(),
				navigator: navigator,
				panGesture: pan
			)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 420,
					height: 300
				),
				styleMask: [.titled, .resizable],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.contentView = split
			window.orderFront(nil)
			defer
			{
				window.close()
			}
			window.layoutIfNeeded()
			split.setNavigatorVisible(
				false,
				animated: false
			)
			split.setNavigatorVisible(
				true,
				animated: true
			)
			pan.setTranslation(
				NSPoint(
					x: 1_000,
					y: 0
				),
				in: split
			)
			let action = try #require(pan.action)
			#expect(NSApp.sendAction(
				action,
				to: pan.target,
				from: pan
			))
			split.layoutSubtreeIfNeeded()
			#expect(split.isNavigatorVisible)
			#expect(abs(split.desiredNavigatorWidth - 120) < 1)
			#expect(navigator.frame.width >= 119)
			window.setContentSize(NSSize(
				width: 300,
				height: 300
			))
			window.layoutIfNeeded()
			split.layoutSubtreeIfNeeded()
			#expect(navigator.frame.width >= 119)
			#expect(!navigator.isHidden)
		}
	}

	@Test func releasingHostReleasesTheObservedSplit()
	{
		weak var releasedHost: NSView?
		weak var releasedSplit: ViewerNavigatorSplitView?
		autoreleasepool
		{
			let host = NSView(frame: NSRect(
				x: 0,
				y: 0,
				width: 720,
				height: 300
			))
			let split = ViewerNavigatorSplitView(
				document: NSView(),
				navigator: NSView()
			)
			host.addSubview(split)
			releasedHost = host
			releasedSplit = split
		}
		#expect(releasedHost == nil)
		#expect(releasedSplit == nil)
	}

	@Test func ancestorShrinkClampsEvenWhileSplitRetainsOldFrame()
	{
		let host = NSView(frame: NSRect(
			x: 0,
			y: 0,
			width: 720,
			height: 300
		))
		let navigator = NSView()
		let split = ViewerNavigatorSplitView(
			document: NSView(),
			navigator: navigator
		)
		split.frame = host.bounds
		host.addSubview(split)
		split.desiredNavigatorWidth = 360
		split.layoutSubtreeIfNeeded()
		#expect(navigator.layer?.masksToBounds == true)
		#expect(abs(split.navigatorWidth - 360) < 1)

		host.frame.size.width = 320
		split.layoutSubtreeIfNeeded()
		#expect(abs(split.bounds.width - 720) < 1)
		#expect(abs(split.navigatorWidth - 155) < 1)
		#expect(abs(navigator.frame.width - 155) < 1)

		host.frame.size.width = 720
		split.layoutSubtreeIfNeeded()
		#expect(abs(split.navigatorWidth - 360) < 1)
	}

	@Test func dividerPanClampsWidthAndRestoresDesiredWidthAfterResize() throws
	{
		_ = NSApplication.shared
		let pan = NSPanGestureRecognizer()
		let document = NSView()
		let navigator = NSView()
		let split = ViewerNavigatorSplitView(
			document: document,
			navigator: navigator,
			panGesture: pan
		)
		split.frame = NSRect(
			x: 0,
			y: 0,
			width: 720,
			height: 300
		)
		split.layoutSubtreeIfNeeded()
		#expect(abs(navigator.frame.width - 241) < 1)
		#expect(abs(split.dividerView.frame.width - 5) < 1)
		#expect(split.dividerView.accessibilityLabel() == "Resize file navigator")

		let action = try #require(pan.action)
		let target = try #require(pan.target)
		pan.setTranslation(
			NSPoint(
				x: -500,
				y: 0
			),
			in: split
		)
		#expect(NSApp.sendAction(
			action,
			to: target,
			from: pan
		))
		split.layoutSubtreeIfNeeded()
		#expect(abs(split.desiredNavigatorWidth - 360) < 1)
		#expect(abs(navigator.frame.width - 360) < 1)

		split.frame.size.width = 320
		split.layoutSubtreeIfNeeded()
		#expect(abs(navigator.frame.width - 155) < 1)
		#expect(document.frame.width >= 159)
		split.frame.size.width = 720
		split.layoutSubtreeIfNeeded()
		#expect(abs(navigator.frame.width - 360) < 1)

		pan.setTranslation(
			NSPoint(
				x: 900,
				y: 0
			),
			in: split
		)
		#expect(NSApp.sendAction(
			action,
			to: target,
			from: pan
		))
		split.layoutSubtreeIfNeeded()
		#expect(abs(split.desiredNavigatorWidth - 120) < 1)
		#expect(abs(navigator.frame.width - 120) < 1)
	}

	@Test func panStartsFromRenderedWidthWhenDocumentResistsCompression() throws
	{
		_ = NSApplication.shared
		let host = NSView(frame: NSRect(
			x: 0,
			y: 0,
			width: 420,
			height: 300
		))
		let navigator = NSView()
		let pan = NSPanGestureRecognizer()
		let split = ViewerNavigatorSplitView(
			document: IntrinsicWidthDocument(),
			navigator: navigator,
			panGesture: pan
		)
		split.frame = host.bounds
		host.addSubview(split)
		split.layoutSubtreeIfNeeded()
		let renderedWidth = navigator.frame.width
		#expect(renderedWidth >= 119)
		#expect(renderedWidth < split.desiredNavigatorWidth)
		#expect(split.navigatorWidth == renderedWidth)

		pan.setTranslation(
			NSPoint(
				x: -20,
				y: 0
			),
			in: split
		)
		let action = try #require(pan.action)
		#expect(NSApp.sendAction(
			action,
			to: pan.target,
			from: pan
		))
		#expect(abs(split.desiredNavigatorWidth - (renderedWidth + 20)) < 1)
	}

	@Test func hideRemovesDividerAndReopenRestoresNavigatorWithoutGap()
	{
		let document = NSView()
		let navigator = IntrinsicWidthNavigator()
		let split = ViewerNavigatorSplitView(
			document: document,
			navigator: navigator
		)
		split.frame = NSRect(
			x: 0,
			y: 0,
			width: 720,
			height: 300
		)
		split.layoutSubtreeIfNeeded()
		split.desiredNavigatorWidth = 300
		split.layoutSubtreeIfNeeded()
		split.setNavigatorVisible(
			false,
			animated: false
		)
		split.layoutSubtreeIfNeeded()
		#expect(!split.isNavigatorVisible)
		#expect(navigator.isHidden)
		#expect(split.dividerView.isHidden)
		#expect(abs(navigator.frame.width) < 1)
		#expect(abs(document.frame.width - split.bounds.width) < 1)

		split.frame.size.width = 320
		split.layoutSubtreeIfNeeded()
		split.setNavigatorVisible(
			true,
			animated: false
		)
		split.layoutSubtreeIfNeeded()
		#expect(abs(navigator.frame.width - 155) < 1)
		#expect(abs(split.desiredNavigatorWidth - 300) < 1)
		#expect(!navigator.isHidden)
		#expect(!split.dividerView.isHidden)
		split.frame.size.width = 720
		split.layoutSubtreeIfNeeded()
		#expect(abs(navigator.frame.width - 300) < 1)
	}
}

@MainActor
private final class IntrinsicWidthNavigator: NSView
{
	override var intrinsicContentSize: NSSize
	{
		NSSize(
			width: 20,
			height: NSView.noIntrinsicMetric
		)
	}
}

@MainActor
private final class IntrinsicWidthDocument: NSView
{
	override var intrinsicContentSize: NSSize
	{
		NSSize(
			width: 200,
			height: NSView.noIntrinsicMetric
		)
	}
}
