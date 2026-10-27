import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct DesktopStatusViewTests
{
	@Test(.appKitIsolation)
	func recoveryActionKeepsFocusAndUsesCurrentCallbackDuringRefresh() throws
	{
		_ = NSApplication.shared
		let status = DesktopStatusView(
			message: "Load failed",
			presentation: .conversation
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 420,
				height: 80
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentView = status
		defer
		{
			window.close()
		}
		var callbacks: [String] = []
		status.setActions([DesktopStatusView.Action(
			title: "Retry",
			identifier: "retry"
		)
		{
			callbacks.append("original")
		}])
		let retry = try #require(buttons(in: status).first)
		#expect(window.makeFirstResponder(retry))
		status.setLoading(true)
		status.setMessage("Retrying conversation…")
		status.setActions([DesktopStatusView.Action(
			title: "Retry again",
			identifier: "retry"
		)
		{
			callbacks.append("current")
		}])
		#expect(buttons(in: status).first === retry)
		#expect(window.firstResponder === retry)
		#expect(retry.title == "Retry again")
		status.setActionsEnabled(false)
		#expect(!retry.dispatchConfiguredAction())
		status.setActionsEnabled(true)
		try #require(retry.dispatchConfiguredAction())
		#expect(callbacks == ["current"])
		status.setActions([DesktopStatusView.Action(
			title: "Retry again",
			identifier: "retry",
			isEnabled: false,
			onActivate:
			{
				callbacks.append("disabled")
			}
		)])
		status.setActionsEnabled(false)
		status.setActionsEnabled(true)
		#expect(!retry.dispatchConfiguredAction())
		#expect(callbacks == ["current"])
		status.setLoading(false)
	}

	@Test func inlineLoadingRemainsVisibleWithoutMessageOrRecoveryAction()
	{
		let status = DesktopStatusView(
			message: "",
			presentation: .inlineCompact
		)
		#expect(status.isHidden)
		status.setLoading(true)
		#expect(!status.isHidden)
		status.setMessage("Loading sources…")
		status.setLoading(false)
		#expect(!status.isHidden)
		status.setMessage("")
		#expect(status.isHidden)
	}

	@Test(.appKitIsolation)
	func narrowRecoveryStatusKeepsMessageAndActionSeparate() throws
	{
		_ = NSApplication.shared
		let status = DesktopStatusView(
			message: "The conversation could not be loaded. Check the connection and retry.",
			actions: [.init(
				title: "Retry",
				onActivate:
				{
				}
			)],
			presentation: .conversation
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: -2000,
				y: -2000,
				width: 180,
				height: 180
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentView = status
		defer
		{
			window.close()
		}
		status.layoutSubtreeIfNeeded()
		let retry = try #require(buttons(in: status).first)
		let messageBounds = status.messageLabel.convert(
			status.messageLabel.bounds,
			to: status
		)
		let buttonBounds = retry.convert(
			retry.bounds,
			to: status
		)
		#expect(messageBounds.width >= 160)
		#expect(!messageBounds.intersects(buttonBounds))
	}

	private func buttons(in view: NSView) -> [NSButton]
	{
		(view as? NSButton).map
		{
			[$0]
		} ?? view.subviews.flatMap
		{
			buttons(in: $0)
		}
	}
}
