import AppKit

/// Diagram zoom controls own their appearance and expose only zoom actions and rendered state.
@MainActor
final class ExpandedImageZoomGroup: DesktopSurface
{
	var onZoomOut: (() -> Void)?
	var onZoomIn: (() -> Void)?
	let zoomOutButton = ExpandedImageDownloadButton(
		title: "−",
		target: nil,
		action: nil
	)
	let zoomInButton = ExpandedImageDownloadButton(
		title: "+",
		target: nil,
		action: nil
	)
	private let percentageLabel = NSTextField(labelWithString: "100%")

	init()
	{
		super.init(
			.white,
			cornerRadius: 22
		)
		appearance = NSAppearance(named: .aqua)
		zoomOutButton.target = self
		zoomOutButton.action = #selector(zoomOut)
		zoomOutButton.setAccessibilityLabel("Zoom out")
		zoomInButton.target = self
		zoomInButton.action = #selector(zoomIn)
		zoomInButton.setAccessibilityLabel("Zoom in")
		percentageLabel.font = AppKitFontResolver.font(TypographyTokens.Button.compact)
		percentageLabel.textColor = .darkGray
		percentageLabel.alignment = .center
		percentageLabel.setAccessibilityLabel("Diagram zoom percentage")
		percentageLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true
		let controls = AppKitLayout.horizontalStack(
			[zoomOutButton, percentageLabel, zoomInButton],
			spacing: 4
		)
		AppKitLayout.pin(
			controls,
			to: self,
			inset: 4
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func render(
		percentage: Int,
		canZoomOut: Bool,
		canZoomIn: Bool
	)
	{
		percentageLabel.stringValue = "\(percentage)%"
		zoomOutButton.isEnabled = canZoomOut
		zoomInButton.isEnabled = canZoomIn
	}

	@objc private func zoomOut()
	{
		onZoomOut?()
	}

	@objc private func zoomIn()
	{
		onZoomIn?()
	}
}
