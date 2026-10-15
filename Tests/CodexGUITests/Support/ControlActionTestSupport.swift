import AppKit

@MainActor
extension NSButton
{
	/// Routing checks use the configured target and action without native press tracking.
	/// Disabled controls must not dispatch, just as they would not accept a user click.
	@discardableResult
	func dispatchConfiguredAction() -> Bool
	{
		guard isEnabled, let action
		else
		{
			return false
		}
		return sendAction(
			action,
			to: target
		)
	}
}
