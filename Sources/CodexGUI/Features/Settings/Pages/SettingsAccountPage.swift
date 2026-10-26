import AppKit

/// Account details available through the app-server's account/read response.
@MainActor
final class SettingsAccountPage: NSView
{
	private let emailRow = SettingsReadOnlyValueRow(
		title: "Email",
		value: "Checking…"
	)
	private let statusRow = SettingsReadOnlyValueRow(
		title: "Account Status",
		value: "Checking…"
	)

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		emailRow.isHidden = true
		AppKitLayout.pin(
			SettingsPageDocument(
				accountSectionTitle: "General",
				rows: [emailRow, statusRow]
			),
			to: self,
			inset: 0
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func render(_ presentation: WorkspaceStatusPresentation)
	{
		let account = presentation.accountStatus
		let accountEmail = account?.email?.trimmingCharacters(in: .whitespacesAndNewlines)
		emailRow.setValue(
			accountEmail ?? "",
			help: accountEmail
		)
		emailRow.isHidden = accountEmail?.isEmpty != false
		let plan = account?.planType ?? presentation.usage.limits?.rateLimits.planType
		statusRow.setValue(
			plan?.capitalized ?? presentation.accountDescription,
			help: presentation.accountDescription
		)
	}

}
