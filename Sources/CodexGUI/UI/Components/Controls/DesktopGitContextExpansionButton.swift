import AppKit

/// Snapshot-context expansion retains native icon sizing and owns its symbol and accessible action.
@MainActor
final class DesktopGitContextExpansionButton: NSButton
{
	enum Edge
	{
		case above, below
	}

	init(
		hiddenLineCount: Int,
		edge: Edge,
		target: AnyObject?,
		action: Selector?
	)
	{
		super.init(frame: .zero)
		let direction = edge == .above ? "above" : "below"
		let label = "Expand all \(hiddenLineCount) unmodified lines from snapshot \(direction)"
		let symbolImage = NSImage(
			systemSymbolName: edge == .above ? "chevron.down" : "chevron.up",
			accessibilityDescription: label
		) ?? NSImage()
		image = symbolImage.withSymbolConfiguration(NSImage.SymbolConfiguration(
			pointSize: 11,
			weight: .medium
		)) ?? NSImage()
		imagePosition = .imageOnly
		self.target = target
		self.action = action
		isBordered = false
		focusRingType = .none
		contentTintColor = .secondaryLabelColor
		toolTip = label
		setAccessibilityLabel(label)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
