import AppKit

/// Hosts the sidebar material without replacing its content when appearance preferences change.
@MainActor
final class SidebarBackgroundView: NSView
{
	private let materialView = NSVisualEffectView()
	private let configuration: () -> ColorThemeConfiguration
	private var colorObservation: ThemeColorObservation?
	private var translucent = false
	private var tintView: DesktopSurface?

	init(
		configuration: @escaping ()
			-> ColorThemeConfiguration =
			{
				ColorPreferences().configuration
			},
		center: NotificationCenter = .default
	)
	{
		self.configuration = configuration
		super.init(frame: .zero)
		materialView.material = .sidebar
		materialView.blendingMode = .behindWindow
		materialView.state = .followsWindowActiveState
		materialView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(materialView)
		let tint = DesktopSurface(
			AppKitColorTokens.sidebarOpaque,
			colorProvider:
			{
				[weak self] in
				self?.translucent == true ? AppKitColorTokens
					.sidebarTranslucentTint : AppKitColorTokens.sidebarOpaque
			}
		)
		tintView = tint
		tint.translatesAutoresizingMaskIntoConstraints = false
		addSubview(tint)
		NSLayoutConstraint.activate([
			materialView.leadingAnchor.constraint(equalTo: leadingAnchor),
			materialView.trailingAnchor.constraint(equalTo: trailingAnchor),
			materialView.topAnchor.constraint(equalTo: topAnchor),
			materialView.bottomAnchor.constraint(equalTo: bottomAnchor),
			tint.leadingAnchor.constraint(equalTo: leadingAnchor),
			tint.trailingAnchor.constraint(equalTo: trailingAnchor),
			tint.topAnchor.constraint(equalTo: topAnchor),
			tint.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
		colorObservation = ThemeColorObservation(center: center)
		{
			[weak self] in self?.refresh()
		}
		refresh()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refresh()
	}

	private func refresh()
	{
		let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
		translucent = !configuration().profile(for: dark ? .dark : .light).opaqueWindows
		materialView.isHidden = !translucent
		tintView?.needsDisplay = true
	}
}
