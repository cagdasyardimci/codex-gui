import AppKit

/// Compatibility name for the complete Settings search presentations.
@MainActor
final class SettingsSearchField: DesktopSearchField
{
	var usesOutline: Bool
	{
		get
		{
			presentation == .settingsOutlined || presentation == .settingsCatalog
		}
		set
		{
			presentation = newValue ? .settingsOutlined : .settingsFilled
		}
	}
	var usesCatalogStyle: Bool
	{
		get
		{
			presentation == .settingsCatalog
		}
		set
		{
			presentation = newValue ? .settingsCatalog : .settingsOutlined
		}
	}

	convenience init()
	{
		self.init(frame: .zero)
	}

	override init(frame frameRect: NSRect)
	{
		super.init(
			frame: frameRect,
			presentation: .settingsFilled
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
