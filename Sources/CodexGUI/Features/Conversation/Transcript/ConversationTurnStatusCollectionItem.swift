import AppKit

@MainActor
final class ConversationTurnStatusCollectionItem: NSCollectionViewItem
{
	private let label = NSTextField(labelWithString: "")
	private let divider = NSBox()
	private var timing: ConversationTurnTiming?

	override func loadView()
	{
		view = NSView()
		label.font = .systemFont(ofSize: 14)
		label.textColor = .secondaryLabelColor
		label.lineBreakMode = .byTruncatingTail
		label.translatesAutoresizingMaskIntoConstraints = false
		divider.boxType = .separator
		divider.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(label)
		view.addSubview(divider)
		NSLayoutConstraint.activate([
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
		now: Date
	)
	{
		_ = view
		self.timing = timing
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
	}

	static func itemSize(width: CGFloat) -> NSSize
	{
		NSSize(
			width: max(
				1,
				width
			),
			height: 32
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
		let working = timing.status == "inProgress"
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
		switch timing.status
		{
		case "inProgress": verb = "Working"
		case "failed": verb = "Failed"
		case "interrupted", "stopped", "cancelled": verb = "Interrupted"
		case "completed": verb = "Worked"
		case "statusUnknown": verb = "Status unavailable"
		default: verb = "Work ended"
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
