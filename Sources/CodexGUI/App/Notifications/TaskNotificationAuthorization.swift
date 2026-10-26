/// Typed macOS authorization state shared by delivery and Settings.
enum TaskNotificationAuthorization: Equatable, Sendable
{
	case checking, notDetermined, denied, authorized, unavailable

	var allowsConfiguration: Bool
	{
		self == .authorized
	}
}
