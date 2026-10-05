import AppKit

/// A reusable right-panel container. Feature controllers retain their own state and callbacks.
@MainActor
final class ContextPanelShell: NSViewController
{
	private var controllers: [ContextPanelDestination: NSViewController] = [:]
	private var featureHeaders: Set<ContextPanelDestination> = []
	private var requestHandlers: [ContextPanelDestination: (ContextPanelRequest) -> Void] = [:]
	private(set) var destination: ContextPanelDestination?
	var onClose: (() -> Void)?
	var closeControlTitle = "Back to summary"
	{
		didSet
		{
			closeButton.title = closeControlTitle
		}
	}
	var closeControlVisible = true
	{
		didSet
		{
			closeButton.isHidden = featureHeaders
				.contains(destination ?? .reportedChanges) || destination == .sources ||
				!closeControlVisible
			sourcesCloseButton.isHidden = !closeControlVisible
		}
	}
	private let content = NSView()
	private let titleLabel = NSTextField(labelWithString: "")
	private let sourcesHeader = NSStackView()
	private let sourcesCloseButton = NSButton(
		title: "",
		target: nil,
		action: nil
	)
	private let closeButton = NSButton(
		title: "Close panel",
		target: nil,
		action: nil
	)

	override func loadView()
	{
		view = NSView()
		closeButton.target = self
		closeButton.action = #selector(closePanel)
		titleLabel.font = .systemFont(
			ofSize: 15,
			weight: .semibold
		)
		titleLabel.setAccessibilityRole(.staticText)
		titleLabel.setAccessibilityRoleDescription("heading")
		configureSourcesHeader()
		let stack = AppKitLayout.verticalStack(
			[sourcesHeader, titleLabel, closeButton, content],
			spacing: 12
		)
		AppKitLayout.pin(
			stack,
			to: view,
			inset: 0
		)
		sourcesHeader.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		content.bottomAnchor.constraint(equalTo: stack.bottomAnchor).isActive = true
		content.setContentHuggingPriority(
			.defaultLow,
			for: .vertical
		)
		content.wantsLayer = true
		content.layer?.masksToBounds = true
	}

	private func configureSourcesHeader()
	{
		let icon = NSImageView(image: DesktopIcons.image(.addSources))
		icon.imageScaling = .scaleProportionallyDown
		icon.setAccessibilityElement(false)
		let label = NSTextField(labelWithString: "Sources")
		label.font = .systemFont(
			ofSize: 15,
			weight: .medium
		)
		label.setAccessibilityRole(.staticText)
		label.setAccessibilityRoleDescription("heading")
		sourcesCloseButton.target = self
		sourcesCloseButton.action = #selector(closePanel)
		sourcesCloseButton.image = DesktopIcons.image(
			.x,
			accessibilityDescription: "Close Sources"
		)
		sourcesCloseButton.isBordered = false
		sourcesCloseButton.contentTintColor = .secondaryLabelColor
		sourcesCloseButton.toolTip = "Close Sources"
		sourcesCloseButton.setAccessibilityLabel("Close Sources")
		sourcesCloseButton.setAccessibilityIdentifier("sources-panel-close")
		sourcesCloseButton.isHidden = !closeControlVisible
		sourcesHeader.orientation = .horizontal
		sourcesHeader.alignment = .centerY
		sourcesHeader.spacing = 8
		sourcesHeader.edgeInsets = NSEdgeInsets(
			top: 8,
			left: 12,
			bottom: 8,
			right: 12
		)
		[icon, label, NSView(), sourcesCloseButton].forEach(sourcesHeader.addArrangedSubview)
		sourcesHeader.wantsLayer = true
		sourcesHeader.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
		sourcesHeader.layer?.cornerRadius = 10
		sourcesHeader.isHidden = true
		NSLayoutConstraint.activate([
			icon.widthAnchor.constraint(equalToConstant: 18),
			icon.heightAnchor.constraint(equalToConstant: 18),
			sourcesCloseButton.widthAnchor.constraint(equalToConstant: 24),
			sourcesCloseButton.heightAnchor.constraint(equalToConstant: 24),
		])
	}

	func register(
		_ controller: NSViewController,
		for destination: ContextPanelDestination,
		providesHeader: Bool = false,
		onRequest: ((ContextPanelRequest) -> Void)? = nil
	)
	{
		if providesHeader
		{
			featureHeaders.insert(destination)
		}
		else
		{
			featureHeaders.remove(destination)
		}
		controllers[destination] = controller
		requestHandlers[destination] = onRequest
	}

	var availableDestinations: Set<ContextPanelDestination>
	{
		Set(controllers.keys)
	}

	func supportsRecordNavigation(_ destination: ContextPanelDestination) -> Bool
	{
		requestHandlers[destination] != nil
	}

	@discardableResult
	func open(_ request: ContextPanelRequest) -> Bool
	{
		if request.recordID != nil, requestHandlers[request.destination] == nil
		{
			return false
		}
		guard open(request.destination)
		else
		{
			return false
		}
		requestHandlers[request.destination]?(request)
		return true
	}

	@discardableResult
	func open(_ destination: ContextPanelDestination) -> Bool
	{
		guard let controller = controllers[destination]
		else
		{
			return false
		}
		_ = view
		children.forEach
		{
			$0.removeFromParent()
		}
		content.subviews.forEach
		{
			$0.removeFromSuperview()
		}
		addChild(controller)
		AppKitLayout.pin(
			controller.view,
			to: content,
			inset: 0
		)
		let providesHeader = featureHeaders.contains(destination)
		sourcesHeader.isHidden = destination != .sources || providesHeader
		titleLabel.isHidden = providesHeader || destination == .sources
		closeButton.isHidden = providesHeader || destination == .sources || !closeControlVisible
		self.destination = destination
		titleLabel.stringValue = destination.rawValue.capitalized
		return true
	}

	@objc private func closePanel()
	{
		onClose?()
	}
}
