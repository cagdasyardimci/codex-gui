import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitNavigatorTransitionTests
{
	@Test func widthFollowsBothTargetsAndReversalDropsSupersededCompletion() async throws
	{
		let root = NSView(frame: NSRect(
			x: 0,
			y: 0,
			width: 500,
			height: 200
		))
		let host = NSView()
		root.addSubview(host)
		host.translatesAutoresizingMaskIntoConstraints = false
		let width = host.widthAnchor.constraint(equalToConstant: 280)
		NSLayoutConstraint.activate([
			width,
			host.leadingAnchor.constraint(equalTo: root.leadingAnchor),
			host.topAnchor.constraint(equalTo: root.topAnchor),
			host.heightAnchor.constraint(equalToConstant: 100),
		])
		let transition = GitNavigatorTransition(
			widthConstraint: width,
			layoutView: root
		)
		transition.setVisible(
			false,
			animated: false
		)
		#expect(width.constant == 0)
		transition.setVisible(
			true,
			animated: false
		)
		#expect(width.constant == 280)
		transition.setVisible(
			false,
			animated: false
		)
		#expect(width.constant == 0)

		guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		else
		{
			return
		}
		var supersededCompletions = 0
		var finalCompletions = 0
		transition.setVisible(
			true,
			completion:
			{
				supersededCompletions += 1
			}
		)
		try await Task.sleep(nanoseconds: 80_000_000)
		#expect(transition.currentWidth > 0 && transition.currentWidth < 280)
		transition.setVisible(
			false,
			completion:
			{
				finalCompletions += 1
			}
		)
		try await Task.sleep(nanoseconds: 350_000_000)
		#expect(abs(transition.currentWidth) < 0.5)
		#expect(supersededCompletions == 0)
		#expect(finalCompletions == 1)
		#expect(!transition.isAnimating)
	}
}
