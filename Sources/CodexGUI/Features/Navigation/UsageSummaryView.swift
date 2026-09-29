import AppKit

@MainActor
final class UsageSummaryView: NSView
{
	private let button = NSButton(
		title: "Usage unavailable",
		target: nil,
		action: nil
	)
	private var details = "Backend usage data is unavailable."
	private var popover: NSPopover?

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)

		DesktopTheme.styleButton(
			button,
			symbol: "chart.bar"
		)
		button.alignment = .left
		button.cell?.lineBreakMode = .byTruncatingTail
		button.target = self
		button.action = #selector(showDetails)
		button.setAccessibilityLabel("Backend usage limits and reset times")

		addSubview(button)
		button.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			button.leadingAnchor.constraint(equalTo: leadingAnchor),
			button.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
			button.topAnchor.constraint(equalTo: topAnchor),
			button.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	private var renderedPresentation: UsagePresentation?

	func render(
		limits: AccountRateLimitsSnapshot?,
		refreshedAt: Date?,
		isStale: Bool,
		unavailableReason: String?
	)
	{
		render(UsagePresentation(
			limits: limits,
			refreshedAt: refreshedAt,
			isStale: isStale,
			unavailableReason: unavailableReason
		))
	}

	func render(_ presentation: UsagePresentation)
	{
		guard renderedPresentation != presentation
		else
		{
			return
		}
		renderedPresentation = presentation
		let limits = presentation.limits
		let refreshedAt = presentation.refreshedAt
		let isStale = presentation.isStale
		let unavailableReason = presentation.unavailableReason
		let title: String
		let detailText: String
		if let limits
		{
			title = Self.usageTitle(
				for: limits.rateLimits,
				isStale: isStale
			)
			detailText = Self.usageDetailText(
				for: limits,
				refreshedAt: refreshedAt,
				isStale: isStale,
				unavailableReason: unavailableReason
			)
		}
		else
		{
			title = "Usage unavailable"
			detailText = unavailableReason ?? "Backend usage data is unavailable."
		}

		button.title = title
		details = detailText
		button.toolTip = detailText
	}

	private static func usageTitle(
		for limits: RateLimitSnapshot,
		isStale: Bool
	) -> String
	{
		let staleSuffix = isStale ? " · stale" : ""
		if let primary = limits.primary
		{
			return "Usage \(Int(primary.usedPercent.rounded()))%\(staleSuffix)"
		}
		if limits.secondary == nil
		{
			return "Usage windows unavailable\(staleSuffix)"
		}
		return "Usage details\(staleSuffix)"
	}

	private static func usageDetailText(
		for snapshot: AccountRateLimitsSnapshot,
		refreshedAt: Date?,
		isStale: Bool,
		unavailableReason: String?
	) -> String
	{
		var lines = accountLimitDetails(snapshot.rateLimits)
		let limitsByIdentifier = (snapshot.rateLimitsByLimitId ?? [:]).sorted
		{
			$0.key < $1.key
		}
		for (identifier, limits) in limitsByIdentifier
		{
			lines.append("\(limits.limitName ?? identifier):")
			lines.append(contentsOf: windowDetails(limits))
		}

		lines.append(contentsOf: creditDetails(snapshot))

		if let refreshedAt
		{
			lines.append("Fetched: \(dateFormatter.string(from: refreshedAt))")
		}
		if isStale
		{
			lines.append("Stale: backend has not confirmed a recent value")
		}
		if let unavailableReason
		{
			lines.append(unavailableReason)
		}

		return lines.isEmpty ? "Backend reported no usage windows." : lines.joined(separator: "\n")
	}

	private static func accountLimitDetails(_ limits: RateLimitSnapshot) -> [String]
	{
		var lines: [String] = []
		if let name = limits.limitName
		{
			lines.append(name)
		}
		if let plan = limits.planType
		{
			lines.append("Plan: \(plan)")
		}
		lines.append(contentsOf: windowDetails(limits))
		return lines
	}

	private static func windowDetails(_ limits: RateLimitSnapshot) -> [String]
	{
		let primary = limits.primary.map
		{
			describe(
				$0,
				name: "Primary"
			)
		} ?? "Primary: unavailable"
		let secondary = limits.secondary.map
		{
			describe(
				$0,
				name: "Secondary"
			)
		} ?? "Secondary: unavailable"
		return [primary, secondary]
	}

	private static func creditDetails(_ snapshot: AccountRateLimitsSnapshot) -> [String]
	{
		var lines: [String] = []
		if let credits = snapshot.rateLimits.credits
		{
			let balance = credits.balance ?? (credits.unlimited ? "Unlimited" : "Unavailable")
			lines.append("Credits: \(balance)")
		}
		if let resets = snapshot.rateLimitResetCredits
		{
			lines.append("Reset credits available: \(resets.availableCount)")
		}
		return lines
	}

	private static func describe(
		_ window: RateLimitWindow,
		name: String
	) -> String
	{
		var text = "\(name): \(Int(window.usedPercent.rounded()))% used"
		if let duration = window.windowDurationMins
		{
			text += " over \(duration) min"
		}
		if let reset = window.resetsAt
		{
			text += " · resets \(dateFormatter.string(from: reset))"
		}
		return text
	}

	private static let dateFormatter: DateFormatter =
	{
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .short
		return formatter
	}()

	@objc private func showDetails()
	{
		let label = NSTextField(wrappingLabelWithString: details)
		label.font = .systemFont(ofSize: 12)
		label.setAccessibilityLabel("Backend reported usage details")

		let controller = NSViewController()
		let container = DesktopSurface(DesktopTheme.elevated)
		AppKitLayout.pin(
			label,
			to: container
		)
		controller.view = container

		let popover = NSPopover()
		popover.contentViewController = controller
		popover.contentSize = NSSize(
			width: 300,
			height: max(
				100,
				CGFloat(details.count / 42 + 1) * 22
			)
		)
		popover.behavior = .transient
		self.popover = popover

		popover.show(
			relativeTo: button.bounds,
			of: button,
			preferredEdge: .maxY
		)
	}
}
