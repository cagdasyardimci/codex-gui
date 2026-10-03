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
				.contains(destination ?? .reportedChanges) || !closeControlVisible
		}
	}
	private let content = NSView()
	private let titleLabel = NSTextField(labelWithString: "")
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
		let stack = AppKitLayout.verticalStack(
			[titleLabel, closeButton, content],
			spacing: 12
		)
		AppKitLayout.pin(
			stack,
			to: view,
			inset: 0
		)
		content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		content.bottomAnchor.constraint(equalTo: stack.bottomAnchor).isActive = true
		content.setContentHuggingPriority(
			.defaultLow,
			for: .vertical
		)
		content.wantsLayer = true
		content.layer?.masksToBounds = true
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
		titleLabel.isHidden = featureHeaders.contains(destination)
		closeButton.isHidden = featureHeaders.contains(destination) || !closeControlVisible
		self.destination = destination
		titleLabel.stringValue = destination.rawValue.capitalized
		return true
	}

	@objc private func closePanel()
	{
		onClose?()
	}
}
