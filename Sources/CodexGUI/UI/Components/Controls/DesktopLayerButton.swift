import AppKit

/// Retains semantic colors while AppKit keeps the button's existing layer and interaction state.
@MainActor
class DesktopLayerButton: DesktopAttributedTitleButton
{
	var layerBackgroundColor: NSColor?
	{
		didSet
		{
			refreshLayerColors()
		}
	}
	var layerBackgroundAlpha: CGFloat?
	{
		didSet
		{
			refreshLayerColors()
		}
	}
	var layerBorderColor: NSColor?
	{
		didSet
		{
			refreshLayerColors()
		}
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshLayerColors()
	}

	private func refreshLayerColors()
	{
		layer?.backgroundColor = layerBackgroundColor.map
		{
			AppKitColorResolution.resolvedCGColor(
				$0,
				for: self,
				alpha: layerBackgroundAlpha
			)
		}
		layer?.borderColor = layerBorderColor.map
		{
			AppKitColorResolution.resolvedCGColor(
				$0,
				for: self
			)
		}
	}
}
