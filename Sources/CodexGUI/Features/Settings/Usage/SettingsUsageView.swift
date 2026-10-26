import AppKit

/// The billing overview presents account usage and available reset actions.
@MainActor
final class SettingsUsageView: NSView
{
	var onRefresh: (() -> Void)?
	var onUseReset: ((String?) -> Void)?
	private let body = AppKitLayout.verticalStack(
		[],
		spacing: 40
	)
	private let status = SettingsPageLayout.status("")
	private let refresh = SettingsUsageButton(
		title: "Refresh",
		presentation: .icon
	)
	private var tabs: SettingsManagementTabs!
	private var selectedTab = "Overview"
	private var resetTab = "Available"
	private var limits: AccountRateLimitsSnapshot?
	private var planType: String?
	private var usage: [String: Any]?
	private var busy = false
	private var canUseReset = false
	private var now = Date()

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		tabs = SettingsManagementTabs(
			titles: ["Overview", "Analytics"],
			selected: selectedTab
		)
		{
			[weak self] selected in self?.selectTab(selected)
		}
		let tabRow = NSStackView(views: [tabs, NSView()])
		refresh.image = NSImage(
			systemSymbolName: "arrow.clockwise",
			accessibilityDescription: "Refresh usage"
		)
		refresh.setAccessibilityLabel("Refresh usage")
		refresh.onAction =
		{
			[weak self] in self?.onRefresh?()
		}
		AppKitLayout.pin(
			SettingsPageLayout.document(
				title: "Usage & billing",
				sections: [tabRow, status, body],
				headerAccessory: refresh
			),
			to: self,
			inset: 0
		)
		renderBody()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func update(
		limits: AccountRateLimitsSnapshot?,
		planType: String?,
		usage: [String: Any]?,
		message: String,
		busy: Bool,
		canUseReset: Bool
	)
	{
		self.limits = limits
		self.planType = planType
		self.usage = usage
		self.busy = busy
		self.canUseReset = canUseReset
		now = Date()
		status.stringValue = message
		refresh.isEnabled = !busy
		renderBody()
	}

	private func selectTab(_ selected: String)
	{
		guard selected != selectedTab
		else
		{
			return
		}
		selectedTab = selected
		tabs.select(title: selected)
		renderBody()
		if let scroll = subviews.first?.subviews.first as? NSScrollView
		{
			scroll.contentView.scroll(to: .zero)
			scroll.reflectScrolledClipView(scroll.contentView)
		}
	}

	private func renderBody()
	{
		for child in body.arrangedSubviews
		{
			body.removeArrangedSubview(child)
			child.removeFromSuperview()
		}
		let sections = selectedTab == "Overview" ? overview() : analytics()
		for section in sections
		{
			body.addArrangedSubview(section)
			section.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
		}
	}

	private func overview() -> [NSView]
	{
		let windows = SettingsUsagePresentation.limits(
			limits,
			now: now
		)
		let plan = section(
			"Your plan",
			detail: "",
			content: SettingsPageLayout.card(rows: [SettingsContentRow(
				title: SettingsUsagePresentation.planTitle(planType ?? limits?.rateLimits.planType),
				detail: "Current subscription"
			)])
		)
		let planLimits = section(
			"Plan limits",
			detail: "Your remaining allowance for the usage windows on this account.",
			content: SettingsPageLayout.card(rows: windows.isEmpty
				? [emptyRow("Plan limits unavailable")] : windows
				.map(limitRow))
		)
		let recent = section(
			"Recent plan usage",
			detail: "How your activity draws down your allowance",
			content: balanceHistory(windows.first?.remaining)
		)
		let credits = section(
			"Credits",
			detail: "Use credits to continue using Codex when you reach usage limits.",
			content: SettingsPageLayout.card(rows: [SettingsContentRow(
				title: SettingsUsagePresentation.credits(limits),
				detail: "Current balance"
			)])
		)
		return [plan, planLimits, recent, credits, resetSection()]
	}

	private func limitRow(_ limit: SettingsUsagePresentation.Limit) -> NSView
	{
		SettingsUsageLimitRow(limit: limit)
	}

	private func balanceHistory(_ remaining: Double?) -> NSView
	{
		let card = DesktopFormCard()
		let value = label(
			remaining.map(SettingsUsagePresentation.percent) ?? "—",
			role: TypographyTokens.Connections.title
		)
		value.setAccessibilityLabel("Plan allowance remaining")
		let caption = secondary("Balance history isn’t available yet")
		for child in [value, caption]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			card.addSubview(child)
		}
		NSLayoutConstraint.activate([
			card.heightAnchor.constraint(equalToConstant: 210),
			value.leadingAnchor.constraint(
				equalTo: card.leadingAnchor,
				constant: 16
			),
			value.topAnchor.constraint(
				equalTo: card.topAnchor,
				constant: 14
			),
			caption.centerXAnchor.constraint(equalTo: card.centerXAnchor),
			caption.centerYAnchor.constraint(
				equalTo: card.centerYAnchor,
				constant: 28
			),
			caption.leadingAnchor.constraint(
				greaterThanOrEqualTo: card.leadingAnchor,
				constant: 16
			),
			caption.trailingAnchor.constraint(
				lessThanOrEqualTo: card.trailingAnchor,
				constant: -16
			)
		])
		return card
	}

	private func resetSection() -> NSView
	{
		let count = limits?.rateLimitResetCredits?.availableCount
		let availableTitle = count.map
		{
			"Available \($0.formatted())"
		} ?? "Available"
		let tabs = SettingsManagementTabs(
			titles: [availableTitle, "History"],
			selected: resetTab == "Available" ? availableTitle :
				"History"
		)
		{
			[weak self] selected in
			self?.resetTab = selected == "History" ? "History" : "Available"
			self?.renderBody()
		}
		let tabRow = NSStackView(views: [tabs, NSView()])
		var rows: [NSView] = [paddedStack(
			[tabRow],
			spacing: 0
		)]
		if resetTab == "History"
		{
			rows.append(emptyRow("Reset history unavailable."))
		}
		else if let count
		{
			let available = limits?.rateLimitResetCredits?.credits?.filter
			{
				$0.status == "available" && ($0.expiresAt.map
				{
					$0 > now
				} ?? true)
			} ?? []
			for credit in available.prefix(40)
			{
				let button = resetButton(
					id: credit.id,
					enabled: credit.resetType == "codexRateLimits"
				)
				let expires = credit.expiresAt.map
				{
					"Expires " + $0.formatted(
						date: .abbreviated,
						time: .shortened
					)
				}
				?? "No expiration"
				rows.append(SettingsPageLayout.row(
					title: credit.title ?? "Full reset",
					detail: expires,
					control: button
				))
			}
			if available.count < count || available.count > 40
			{
				rows.append(SettingsPageLayout.row(
					title: "Usage resets",
					detail: "\(count.formatted()) available. Uses the next available reset.",
					control: resetButton(
						id: nil,
						enabled: true
					)
				))
			}
			else if available.isEmpty
			{
				rows.append(emptyRow("No usage resets available."))
			}
		}
		else
		{
			rows.append(emptyRow("Usage resets unavailable."))
		}
		return section(
			"Usage limit resets",
			detail: "Use a reset to restore your 5-hour limit, weekly limit, or both.",
			content: SettingsPageLayout.card(rows: rows)
		)
	}

	private func resetButton(
		id: String?,
		enabled: Bool
	) -> NSView
	{
		let button = SettingsUsageButton(title: "Use reset")
		button.isEnabled = enabled && canUseReset && !busy
		button.toolTip = "Available when a usage limit has 10% or less remaining."
		button.onAction =
		{
			[weak self] in self?.onUseReset?(id)
		}
		return button
	}

	private func analytics() -> [NSView]
	{
		let rows = SettingsUsagePresentation.activity(usage).map
		{
			title, value in
			SettingsPageLayout.row(
				title: title,
				detail: nil,
				control: secondary(value)
			)
		}
		let activity = section(
			"Token activity",
			detail: "Your account’s Codex activity.",
			content: SettingsPageLayout.card(rows: rows)
		)
		let buckets = SettingsUsagePresentation.dailyBuckets(usage)
		let days = buckets.reversed().map
		{
			SettingsPageLayout.row(
				title: $0.date,
				detail: nil,
				control: secondary($0.tokens.formatted() + " tokens")
			)
		}
		let dailyContent: [NSView] = buckets.isEmpty
			? [emptyRow("Daily usage history isn’t available yet.")] :
			[paddedStack(
				[SettingsUsageDailyChart(days: buckets)],
				spacing: 0
			)] + days
		return [activity, section(
			"Daily token usage",
			detail: "Recent daily token totals",
			content: SettingsPageLayout.card(rows: dailyContent)
		)]
	}

	private func section(
		_ title: String,
		detail: String,
		content: NSView
	) -> NSView
	{
		SettingsDescriptiveSection(
			title: title,
			detail: detail,
			content: content
		)
	}

	private func paddedStack(
		_ views: [NSView],
		spacing: CGFloat
	) -> NSView
	{
		let stack = AppKitLayout.verticalStack(
			views,
			spacing: spacing
		)
		for view in views
		{
			view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		return SettingsContentRow(content: stack)
	}

	private func emptyRow(_ text: String) -> NSView
	{
		SettingsContentRow(content: SettingsPageLayout.status(text))
	}

	private func label(
		_ text: String,
		role: TypographyTokens.Role
	) -> DesktopLineBoxLabel
	{
		DesktopLineBoxLabel(
			text,
			role: role
		)
	}

	private func secondary(_ text: String) -> DesktopLineBoxLabel
	{
		let caption = label(
			text,
			role: TypographyTokens.Connections.caption
		)
		caption.textColor = AppKitColorTokens.settingsSecondaryText
		return caption
	}

}

@MainActor
final class SettingsUsageDailyChart: NSView
{
	let days: [SettingsUsagePresentation.DailyBucket]
	let fractions: [Double]

	init(days: [SettingsUsagePresentation.DailyBucket])
	{
		self.days = days
		fractions = SettingsUsagePresentation.dailyChartFractions(days)
		super.init(frame: .zero)
		heightAnchor.constraint(equalToConstant: 144).isActive = true
		setAccessibilityElement(true)
		setAccessibilityRole(.image)
		setAccessibilityLabel("Daily token usage chart")
		setAccessibilityValue("\(days.count) \(days.count == 1 ? "day" : "days")")
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		guard !days.isEmpty, bounds.width > 32, bounds.height > 40
		else
		{
			return
		}
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		let plot = NSRect(
			x: 12,
			y: 24,
			width: bounds.width - 24,
			height: bounds.height - 40
		)
		AppKitColorTokens.settingsSecondaryText.withAlphaComponent(0.18).setStroke()
		for fraction in [0.0, 0.5, 1.0]
		{
			let y = plot.minY + plot.height * fraction
			let line = NSBezierPath()
			line.lineWidth = 0.5
			line.move(to: NSPoint(
				x: plot.minX,
				y: y
			))
			line.line(to: NSPoint(
				x: plot.maxX,
				y: y
			))
			line.stroke()
		}
		let slot = plot.width / CGFloat(days.count)
		let barWidth = min(
			16,
			max(
				4,
				slot * 0.65
			)
		)
		AppKitColorTokens.settingsPrimaryText.withAlphaComponent(0.82).setFill()
		for (index, fraction) in fractions.enumerated()
		{
			guard fraction > 0
			else
			{
				continue
			}
			let height = max(
				2,
				plot.height * CGFloat(fraction)
			)
			let bar = NSRect(
				x: plot.minX + slot * (CGFloat(index) + 0.5) - barWidth / 2,
				y: plot.minY,
				width: barWidth,
				height: height
			)
			NSBezierPath(
				roundedRect: bar,
				xRadius: min(
					3,
					barWidth / 2
				),
				yRadius: min(
					3,
					height / 2
				)
			).fill()
		}
	}
}

@MainActor
private final class SettingsUsageButton: DesktopActionButton
{
	override func draw(_ dirtyRect: NSRect)
	{
		guard !isEnabled, let context = NSGraphicsContext.current?.cgContext
		else
		{
			super.draw(dirtyRect)
			return
		}
		context.saveGState()
		context.setAlpha(0.4)
		context.beginTransparencyLayer(auxiliaryInfo: nil)
		super.draw(dirtyRect)
		context.endTransparencyLayer()
		context.restoreGState()
	}
	override func invokeAction()
	{
		if isEnabled
		{
			super.invokeAction()
		}
	}
}
