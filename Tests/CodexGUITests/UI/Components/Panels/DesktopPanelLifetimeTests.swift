import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct DesktopPanelLifetimeTests
{
	@Test func invalidationRetiresObserversBeforeTheNextPresentation()
	{
		let lifetime = DesktopPanelLifetime()
		let name = Notification.Name("panel-lifetime-\(UUID().uuidString)")
		let source = NSObject()
		let otherSource = NSObject()
		let recorder = PanelNotificationRecorder()
		defer
		{
			lifetime.invalidate()
		}

		func observePresentation()
		{
			lifetime.addObserver(
				recorder,
				selector: #selector(PanelNotificationRecorder.record),
				name: name,
				object: source
			)
			lifetime.addObserver(
				forName: name,
				object: source,
				queue: .main
			)
			{
				_ in MainActor.assumeIsolated
				{
					recorder.blockCount += 1
				}
			}
		}

		observePresentation()
		NotificationCenter.default.post(
			name: name,
			object: otherSource
		)
		#expect(recorder.selectorCount == 0)
		#expect(recorder.blockCount == 0)
		NotificationCenter.default.post(
			name: name,
			object: source
		)
		#expect(recorder.selectorCount == 1)
		#expect(recorder.blockCount == 1)

		lifetime.invalidate()
		lifetime.invalidate()
		NotificationCenter.default.post(
			name: name,
			object: source
		)
		#expect(recorder.selectorCount == 1)
		#expect(recorder.blockCount == 1)

		observePresentation()
		NotificationCenter.default.post(
			name: name,
			object: source
		)
		#expect(recorder.selectorCount == 2)
		#expect(recorder.blockCount == 2)
	}
}

@MainActor
private final class PanelNotificationRecorder: NSObject
{
	var selectorCount = 0
	var blockCount = 0

	@objc func record(_ notification: Notification)
	{
		selectorCount += 1
	}
}
