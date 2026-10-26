import AppKit

@MainActor
final class ConversationTurnStatusCollectionItem: NSCollectionViewItem
{
	private let label = NSTextField(labelWithString: "")
	private let divider = NSBox()
	private let disclosure = DesktopDisclosureButton()
	private var expanded = false
	private var onToggle: (() -> Void)?
	private var timing: ConversationTurnTiming?

	override func loadView()
	{
		view = NSView()
		label.font = AppKitFontResolver.interfaceFont(ofSize: 14)
		label.textColor = .secondaryLabelColor
		label.lineBreakMode = .byTruncatingTail
		label.translatesAutoresizingMaskIntoConstraints = false
		divider.boxType = .separator
		divider.translatesAutoresizingMaskIntoConstraints = false

		disclosure.translatesAutoresizingMaskIntoConstraints = false
		disclosure.target = self
		disclosure.action = #selector(toggleWork)
		view.addSubview(disclosure)
		view.addSubview(label)
		view.addSubview(divider)
		NSLayoutConstraint.activate([
			disclosure.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			disclosure.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
			disclosure.topAnchor.constraint(equalTo: view.topAnchor),
			label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			label.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			label.topAnchor.constraint(equalTo: view.topAnchor),
			divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			divider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			divider.heightAnchor.constraint(equalToConstant: 1),
		])
	}

	func configure(
		_ timing: ConversationTurnTiming,
		now: Date,
		expanded: Bool = false,
		onToggle: (() -> Void)? = nil
	)
	{
		_ = view
		self.timing = timing
		self.expanded = expanded
		self.onToggle = onToggle
		label.isHidden = onToggle != nil
		disclosure.isHidden = onToggle == nil
		refresh(now: now)
	}

	func refresh(now: Date)
	{
		guard let timing
		else
		{
			return
		}
		label.stringValue = Self.statusText(
			timing: timing,
			now: now
		)
		label.setAccessibilityLabel(label.stringValue)
		disclosure.setLabel(label.stringValue)
		disclosure.setExpanded(expanded)
	}

	@objc private func toggleWork()
	{
		onToggle?()
	}

	override func prepareForReuse()
	{
		super.prepareForReuse()
		timing = nil
		onToggle = nil
	}

	static func itemSize(width: CGFloat) -> NSSize
	{
		NSSize(
			width: max(
				1,
				width
			),
			height: 25
		)
	}

	static func statusText(
		timing: ConversationTurnTiming,
		now: Date
	) -> String
	{
		guard timing.status != "statusUnknown"
		else
		{
			return "Status unavailable"
		}
		let lifecycle = ConversationTurnStatus.lifecycle(timing.status)
		let working = lifecycle == .running
		let seconds: Double?
		if working, let started = timing.startedAt
		{
			seconds = max(
				0,
				now.timeIntervalSince(started)
			)
		}
		else if let milliseconds = timing.durationMs, milliseconds.isFinite
		{
			seconds = max(
				0,
				milliseconds / 1000
			)
		}
		else if let started = timing.startedAt, let completed = timing.completedAt
		{
			seconds = max(
				0,
				completed.timeIntervalSince(started)
			)
		}
		else
		{
			seconds = nil
		}
		let verb: String
		switch lifecycle
		{
		case .running: verb = "Working"
		case .failed: verb = "Failed"
		case .interrupted: verb = "Interrupted"
		case .completed: verb = "Worked"
		case .unknown: verb = "Work ended"
		}
		guard let seconds
		else
		{
			return verb
		}
		let wholeSeconds = Int(min(
			seconds,
			Double(Int.max / 2)
		))
		let duration: String
		if wholeSeconds < 60
		{
			duration = "\(wholeSeconds)s"
		}
		else if wholeSeconds < 3600
		{
			duration = "\(wholeSeconds / 60)m \(wholeSeconds % 60)s"
		}
		else
		{
			duration = "\(wholeSeconds / 3600)h \((wholeSeconds % 3600) / 60)m"
		}
		let joining = verb == "Failed" || verb == "Interrupted" ? "after" : "for"
		return "\(verb) \(joining) \(duration)"
	}
}
