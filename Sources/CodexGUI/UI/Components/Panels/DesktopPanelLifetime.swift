import AppKit

/// Owns resources installed for one transient-panel presentation.
/// The panel owner keeps its keyboard, focus, placement and parent-window policies.
@MainActor
final class DesktopPanelLifetime
{
	private var eventMonitors: [Any] = []
	private var notificationObservers: [NSObjectProtocol] = []
	private var selectorRemovals: [() -> Void] = []
	private var appearance: DesktopPanelAppearanceBinding?

	func bindAppearance(
		panel: NSPanel,
		source: NSView
	)
	{
		appearance?.invalidate()
		appearance = DesktopPanelAppearanceBinding(
			panel: panel,
			source: source
		)
	}

	func addObserver(
		forName name: Notification.Name,
		object: Any?,
		queue: OperationQueue?,
		using block: @escaping @Sendable (Notification) -> Void
	)
	{
		notificationObservers.append(NotificationCenter.default.addObserver(
			forName: name,
			object: object,
			queue: queue,
			using: block
		))
	}

	func addObserver(
		_ observer: AnyObject,
		selector: Selector,
		name: Notification.Name,
		object: AnyObject?
	)
	{
		NotificationCenter.default.addObserver(
			observer,
			selector: selector,
			name: name,
			object: object
		)
		selectorRemovals.append
		{
			[weak observer, weak object] in
			if let observer
			{
				NotificationCenter.default.removeObserver(
					observer,
					name: name,
					object: object
				)
			}
		}
	}

	func monitorLocalEvents(
		matching mask: NSEvent.EventTypeMask,
		handler: @escaping (NSEvent) -> NSEvent?
	)
	{
		if let monitor = NSEvent.addLocalMonitorForEvents(
			matching: mask,
			handler: handler
		)
		{
			eventMonitors.append(monitor)
		}
	}

	func monitorGlobalEvents(
		matching mask: NSEvent.EventTypeMask,
		handler: @escaping (NSEvent) -> Void
	)
	{
		if let monitor = NSEvent.addGlobalMonitorForEvents(
			matching: mask,
			handler: handler
		)
		{
			eventMonitors.append(monitor)
		}
	}

	func invalidate()
	{
		eventMonitors.forEach(NSEvent.removeMonitor)
		eventMonitors.removeAll()
		notificationObservers.forEach(NotificationCenter.default.removeObserver)
		notificationObservers.removeAll()
		selectorRemovals.forEach
		{
			$0()
		}
		selectorRemovals.removeAll()
		appearance?.invalidate()
		appearance = nil
	}
}
