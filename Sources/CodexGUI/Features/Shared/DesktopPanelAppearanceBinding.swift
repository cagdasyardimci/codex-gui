import AppKit

/// A separate panel follows its anchor's appearance, including local view overrides.
@MainActor
final class DesktopPanelAppearanceBinding
{
	private var observation: NSKeyValueObservation?

	init(
		panel: NSPanel,
		source: NSView
	)
	{
		observation = source.observe(
			\.effectiveAppearance,
			options: [.initial, .new]
		)
		{
			[weak panel] view, _ in
			MainActor.assumeIsolated
			{
				panel?.appearance = view.effectiveAppearance
			}
		}
	}

	func invalidate()
	{
		observation?.invalidate()
		observation = nil
	}
}
