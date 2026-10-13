import AppKit

/// Keeps the add menu and model controls on one row when the pane has room.
@MainActor
final class ComposerToolbarView: NSView
{
	private var wideConstraints: [NSLayoutConstraint] = []
	private var compactConstraints: [NSLayoutConstraint] = []
	private var isCompact = true
	private let composerLayout: ComposerLayout

	init(
		leadingControls: NSView,
		preferenceControl: NSView,
		actionControls: NSView,
		metrics: LayoutTokens.Composer = LayoutTokens.composer
	)
	{
		precondition(
			metrics.isValid,
			"Invalid composer metrics"
		)
		let composerLayout = ComposerLayout(metrics: metrics)
		let supportedHeight = composerLayout.footerHeight(
			compact: false,
			leadingHeight: leadingControls.fittingSize.height,
			preferenceHeight: preferenceControl.fittingSize.height,
			actionHeight: actionControls.fittingSize.height
		)
		precondition(
			supportedHeight != nil,
			"Composer controls must fit the action row"
		)
		self.composerLayout = composerLayout
		super.init(frame: .zero)

		for controls in [leadingControls, preferenceControl, actionControls]
		{
			controls.translatesAutoresizingMaskIntoConstraints = false
			addSubview(controls)
		}

		wideConstraints = [
			leadingControls.leadingAnchor.constraint(equalTo: leadingAnchor),
			leadingControls.centerYAnchor.constraint(equalTo: centerYAnchor),
			leadingControls.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
			leadingControls.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
			preferenceControl.leadingAnchor.constraint(
				greaterThanOrEqualTo: leadingControls.trailingAnchor,
				constant: LayoutTokens.Composer.leadingPreferenceSpacing
			),
			preferenceControl.trailingAnchor.constraint(
				equalTo: actionControls.leadingAnchor,
				constant: -metrics.preferenceToActionSpacing
			),
			preferenceControl.centerYAnchor.constraint(equalTo: centerYAnchor),
			preferenceControl.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
			preferenceControl.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
			actionControls.trailingAnchor.constraint(equalTo: trailingAnchor),
			actionControls.topAnchor.constraint(equalTo: topAnchor),
			actionControls.bottomAnchor.constraint(equalTo: bottomAnchor),
		]

		compactConstraints = [
			leadingControls.leadingAnchor.constraint(equalTo: leadingAnchor),
			leadingControls.topAnchor.constraint(equalTo: topAnchor),
			preferenceControl.leadingAnchor.constraint(equalTo: leadingAnchor),
			preferenceControl.trailingAnchor.constraint(
				lessThanOrEqualTo: actionControls.leadingAnchor,
				constant: -metrics.preferenceToActionSpacing
			),
			preferenceControl.centerYAnchor.constraint(equalTo: actionControls.centerYAnchor),
			preferenceControl.topAnchor.constraint(
				greaterThanOrEqualTo: leadingControls.bottomAnchor,
				constant: metrics.compactRowSpacing
			),
			preferenceControl.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
			actionControls.topAnchor.constraint(
				equalTo: leadingControls.bottomAnchor,
				constant: metrics.compactRowSpacing
			),
			actionControls.trailingAnchor.constraint(equalTo: trailingAnchor),
			actionControls.bottomAnchor.constraint(equalTo: bottomAnchor),
		]

		// Before a pane supplies its width, reserve both rows in its initial fitting height.
		NSLayoutConstraint.activate(compactConstraints)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func layout()
	{
		let shouldUseCompactLayout = composerLayout.usesCompactFooter(innerWidth: bounds.width)
		if shouldUseCompactLayout != isCompact
		{
			NSLayoutConstraint.deactivate(isCompact ? compactConstraints : wideConstraints)
			isCompact = shouldUseCompactLayout
			NSLayoutConstraint.activate(isCompact ? compactConstraints : wideConstraints)
		}
		super.layout()
	}
}
