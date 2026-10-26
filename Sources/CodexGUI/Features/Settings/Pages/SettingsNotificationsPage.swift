import AppKit

@MainActor
final class SettingsNotificationsPage: NSView
{
	var onRequestAuthorization: (() -> Void)?
	{
		didSet
		{
			controls.onRequestAuthorization = onRequestAuthorization
		}
	}
	var onRefreshAuthorization: (() -> Void)?
	{
		didSet
		{
			controls.onRefreshAuthorization = onRefreshAuthorization
		}
	}
	private let controls = SettingsNotificationControls()

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		AppKitLayout.pin(
			SettingsPageLayout.document(
				title: "Notifications",
				sections: [controls],
				columnWidth: .fitsViewport
			),
			to: self,
			inset: 0
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func setNotificationAuthorization(_ state: TaskNotificationAuthorization)
	{
		controls.setAuthorization(state)
	}

	func setNotificationStatus(_ message: String)
	{
		controls.setNotificationStatus(message)
	}

	func refreshPreferences()
	{
		controls.refreshPreferences()
	}
}
