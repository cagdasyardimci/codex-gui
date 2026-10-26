import AppKit

/// Retains the exact delayed operation and passive child panel until its owner dismisses them.
@MainActor
final class DesktopDelayedPresentation
{
	private(set) var task: Task<Void, Never>?
	private(set) var panel: NSPanel?
	private let lifetime = DesktopPanelLifetime()

	@discardableResult
	func schedule(
		after delay: Duration,
		show: @escaping @MainActor () -> Void
	) -> Task<Void, Never>
	{
		task?.cancel()
		let operation = Task
		{
			do
			{
				try await Task.sleep(for: delay)
			}
			catch
			{
				return
			}
			guard !Task.isCancelled
			else
			{
				return
			}
			show()
		}
		task = operation
		return operation
	}

	func attach(
		_ panel: NSPanel,
		to parent: NSWindow,
		appearanceSource: NSView? = nil,
		orderFront: Bool = true
	)
	{
		dismissPanel()
		self.panel = panel
		if let appearanceSource
		{
			lifetime.bindAppearance(
				panel: panel,
				source: appearanceSource
			)
		}
		parent.addChildWindow(
			panel,
			ordered: .above
		)
		if orderFront
		{
			panel.orderFront(nil)
		}
	}

	func dismiss()
	{
		task?.cancel()
		task = nil
		dismissPanel()
	}

	private func dismissPanel()
	{
		lifetime.invalidate()
		if let panel
		{
			panel.parent?.removeChildWindow(panel)
		}
		panel?.orderOut(nil)
		panel = nil
	}
}
