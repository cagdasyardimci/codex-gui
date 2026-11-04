import AppKit

/// Owner-retained subscription for views that retain resolved theme colors.
@MainActor
final class ThemeColorObservation: NSObject
{
	private let update: @MainActor () -> Void
	private var appearanceObservation: NSKeyValueObservation?

	init(
		center: NotificationCenter = .default,
		view: NSView? = nil,
		update: @escaping @MainActor () -> Void
	)
	{
		self.update = update
		super.init()
		if let view
		{
			appearanceObservation = view.observe(
				\.effectiveAppearance,
				options: [.new]
			)
			{
				[weak self] _, _ in
				Task
				{
					@MainActor [weak self] in
					self?.update()
				}
			}
		}
		center.addObserver(
			self,
			selector: #selector(changed),
			name: ColorPreferences.didChange,
			object: nil
		)
	}

	@objc private func changed()
	{
		update()
	}
}
