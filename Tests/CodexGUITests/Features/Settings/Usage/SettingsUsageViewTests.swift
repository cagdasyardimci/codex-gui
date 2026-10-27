import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SettingsUsageViewTests
{
	@Test func tabsRouteActionsWithoutUnavailableBillingControls() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let page = SettingsUsageView()
			let window = makeWindow(page)
			defer
			{
				window.close()
			}
			var refreshes = 0
			var resets: [String?] = []
			page.onRefresh =
			{
				refreshes += 1
			}
			page.onUseReset =
			{
				resets.append($0)
			}
			page.update(
				limits: try snapshot(
					used: 95,
					creditCount: 1
				),
				planType: "pro",
				usage: ["summary": ["lifetimeTokens": 1_250_000,
									"peakDailyTokens": 24_000,
									"currentStreakDays": 3,
									"longestStreakDays": 12,
									"longestRunningTurnSec": 90],
						"dailyUsageBuckets": [["startDate": "2026-10-25", "tokens": 1200]]],
				busy: false,
				canUseReset: true
			)
			window.layoutIfNeeded()
			try capture(
				page,
				suffix: "overview-top"
			)
			#expect(labels(page).contains
			{
				$0.localizedCaseInsensitiveContains("Plan limits")
			})
			let refresh = try button(
				"Refresh",
				in: page
			)
			#expect(refresh.dispatchConfiguredAction())
			#expect(refreshes == 1)
			let reset = try button(
				"Use reset",
				in: page
			)
			#expect(reset.dispatchConfiguredAction())
			#expect(resets == ["credit-a"])
			#expect(labels(page).contains("ChatGPT Pro"))
			#expect(labels(page).contains("Current balance"))
			for title in [
				"View plans",
				"Add more",
				"Automatic reload",
				"Allow your assistant to use resets"
			]
			{
				#expect(!labels(page).contains(title))
				#expect(!buttons(page).contains
				{
					$0.title == title || $0.accessibilityLabel() == title
				})
			}
			try assertResetSectionLayout(page)
			reset.scrollToVisible(reset.bounds)
			let scroll = try #require(descendants(page).compactMap
			{
				$0 as? NSScrollView
			}.first)
			#expect(scroll.contentView.bounds.minY > 0)
			try capture(
				page,
				suffix: "overview-resets"
			)
			let history = try button(
				"History",
				in: page
			)
			#expect(history.dispatchConfiguredAction())
			let historyTab = try #require(button(
				"History",
				in: page
			) as? DesktopStyledButton)
			#expect(historyTab.presentation == .tab(selected: true))
			#expect(buttons(page).filter
			{
				$0.title == "Use reset"
			}.isEmpty)
			let analytics = try button(
				"Analytics",
				in: page
			)
			#expect(analytics.dispatchConfiguredAction())
			window.layoutIfNeeded()
			page.layoutSubtreeIfNeeded()
			#expect(abs(scroll.contentView.bounds.minY) < 0.5)
			#expect(labels(page)
				.contains
				{
					$0.localizedCaseInsensitiveContains("Lifetime tokens")
				})
			for value in [1_250_000.formatted(), 24_000.formatted(), "3 days", "12 days", "1m 30s"]
			{
				#expect(labels(page).contains(value))
			}
			#expect(labels(page).contains("2026-10-25"))
			#expect(labels(page).contains(1200.formatted() + " tokens"))
			let chart = try #require(descendants(page).compactMap
			{
				$0 as? SettingsUsageDailyChart
			}.first)
			#expect(chart.days == [
				SettingsUsagePresentation.DailyBucket(
					date: "2026-10-25",
					tokens: 1200
				)
			])
			#expect(chart.fractions == [1])
			#expect(abs(chart.bounds.height - 144) < 0.5)
			#expect(chart.accessibilityLabel() == "Daily token usage chart")
			#expect(chart.accessibilityValue() as? String == "1 day")
			try capture(
				page,
				suffix: "analytics"
			)
			#expect(try button(
				"Overview",
				in: page
			).dispatchConfiguredAction())
			#expect(labels(page).contains
			{
				$0.localizedCaseInsensitiveContains("Plan limits")
			})
		}
	}

	@Test func allowanceRowsKeepUnknownAndZeroRemainingDistinct() throws
	{
		_ = NSApplication.shared
		for remaining: Double? in [nil, 0]
		{
			let row = SettingsUsageLimitRow(limit: .init(
				title: "Weekly limit",
				accessibilityLabel: "Weekly allowance remaining",
				remaining: remaining,
				reset: "Resets tomorrow"
			))
			let views = descendants(row)
			let labels = views.compactMap
			{
				$0 as? NSTextField
			}.map(\.stringValue)
			let progress = views.filter
			{
				$0.accessibilityRole() == .progressIndicator
			}
			#expect(labels.contains("Weekly limit"))
			#expect(labels.contains("Resets tomorrow"))
			if remaining == nil
			{
				#expect(!labels.contains("Unavailable"))
				#expect(progress.isEmpty)
			}
			else
			{
				#expect(labels.contains("0% left"))
				#expect(progress.count == 1)
				#expect(progress.first?.accessibilityLabel() == "Weekly allowance remaining")
				#expect(progress.first?.accessibilityValue() as? String == "0% left")
			}
		}
	}

	@Test func missingAndZeroDataRemainDistinctAndBusyActionsDoNotDispatch() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let page = SettingsUsageView()
			let window = makeWindow(page)
			defer
			{
				window.close()
			}
			var actions = 0
			page.onRefresh =
			{
				actions += 1
			}
			page.onUseReset =
			{
				_ in actions += 1
			}
			page.update(
				limits: nil,
				planType: nil,
				usage: nil,
				busy: false,
				canUseReset: false
			)
			#expect(!labels(page).contains("Usage could not be loaded."))
			#expect(progressValues(page).isEmpty)
			#expect(try button(
				"Analytics",
				in: page
			).dispatchConfiguredAction())
			let missingLabels = labels(page)
			#expect(descendants(page).compactMap
			{
				$0 as? SettingsUsageDailyChart
			}.isEmpty)
			#expect(!missingLabels.contains
			{
				$0.localizedCaseInsensitiveContains("unavailable")
			})
			page.update(
				limits: try snapshot(
					used: 0,
					creditCount: 0
				),
				planType: "free",
				usage: ["summary": ["lifetimeTokens": 0,
									"peakDailyTokens": 0,
									"currentStreakDays": 0,
									"longestStreakDays": 0,
									"longestRunningTurnSec": 0]],
				busy: true,
				canUseReset: false
			)
			#expect(labels(page) != missingLabels)
			#expect(labels(page).contains("0"))
			#expect(!buttonEnabled(
				"Refresh",
				in: page
			))
			#expect(try button(
				"Overview",
				in: page
			).dispatchConfiguredAction())
			#expect(progressValues(page).contains("100% left"))
			#expect(buttons(page).filter
			{
				$0.title == "Use reset"
			}.allSatisfy
			{
				!$0.isEnabled
			})
			page.update(
				limits: try snapshot(
					used: 95,
					creditCount: 1
				),
				planType: "pro",
				usage: nil,
				busy: true,
				canUseReset: true
			)
			let busyReset = try button(
				"Use reset",
				in: page
			)
			#expect(!busyReset.isEnabled)
			#expect(!busyReset.dispatchConfiguredAction())
			#expect(actions == 0)
		}
	}

	@Test func chartKeepsLatestValidBucketsAndScalesZeroSeparately() throws
	{
		let data: [[String: Any]] = (1 ... 35).reversed().map
		{
			index in
			let date = index <= 31
				? String(
					format: "2026-01-%02d",
					index
				) :
				String(
					format: "2026-02-%02d",
					index - 31
				)
			return ["startDate": date, "tokens": index == 5 ? 0 : index]
		}
		let invalid: [[String: Any]] = [
			["startDate": "", "tokens": 50],
			["startDate": "2026-02-05", "tokens": -1],
			["startDate": "2026-02-06", "tokens": "50"]
		]
		let days = SettingsUsagePresentation.dailyBuckets(["dailyUsageBuckets": data + invalid])
		try #require(days.count == 31)
		#expect(days.first?.date == "2026-01-05")
		#expect(days.first?.tokens == 0)
		#expect(days.last?.date == "2026-02-04")
		let fractions = SettingsUsagePresentation.dailyChartFractions(days)
		#expect(fractions.first == 0)
		#expect(fractions.last == 1)
		#expect(fractions[1] > 0 && fractions[1] < 1)
		#expect(SettingsUsagePresentation.dailyChartFractions([
			SettingsUsagePresentation.DailyBucket(
				date: "2026-02-05",
				tokens: 0
			)
		]) == [0])
	}

	@Test func independentBucketsUseWindowDurationsAndClampDecimalPercentages() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let page = SettingsUsageView()
			let window = makeWindow(page)
			defer
			{
				window.close()
			}
			let limits = try #require(AccountRateLimitsSnapshot(json: [
				"rateLimits": ["primary": ["usedPercent": 99, "windowDurationMins": 300]],
				"rateLimitsByLimitId": [
					"codex": ["limitId": "codex",
								"limitName": "Codex",
								"primary": ["usedPercent": 12.5, "windowDurationMins": 10080],
								"secondary": ["usedPercent": 92.5, "windowDurationMins": 300]],
					"review": ["limitId": "review",
								"limitName": "Review",
								"primary": ["usedPercent": -12.5, "windowDurationMins": 300],
								"secondary": ["usedPercent": 130.5, "windowDurationMins": 10080]],
				],
			]))
			page.update(
				limits: limits,
				planType: "pro",
				usage: nil,
				busy: false,
				canUseReset: false
			)
			let bars = descendants(page).filter
			{
				$0.accessibilityRole() == .progressIndicator
			}
			#expect(bars.count == 4)
			let weeklyRemaining = 87.5.formatted(.number) + "% left"
			let shortRemaining = 7.5.formatted(.number) + "% left"
			#expect(Set(progressValues(page)) == [
				weeklyRemaining,
				shortRemaining,
				"100% left",
				"0% left"
			])
			let weekly = try #require(bars.first
			{
				($0.accessibilityLabel() ?? "").contains("Codex")
					&& ($0.accessibilityLabel() ?? "").contains("Weekly")
			})
			#expect(weekly.accessibilityValue() as? String == weeklyRemaining)
			let short = try #require(bars.first
			{
				($0.accessibilityLabel() ?? "").contains("Codex")
					&& ($0.accessibilityLabel() ?? "").contains("5-hour")
			})
			#expect(short.accessibilityValue() as? String == shortRemaining)
		}
	}

	private func snapshot(
		used: Double,
		creditCount: Int
	) throws -> AccountRateLimitsSnapshot
	{
		try #require(AccountRateLimitsSnapshot(json: [
			"rateLimits": ["limitName": "Codex",
							"planType": "pro",
							"primary": ["usedPercent": used, "windowDurationMins": 300],
							"secondary": ["usedPercent": 50, "windowDurationMins": 10080],
							"credits": [
							"hasCredits": true,
							"unlimited": false,
							"balance": "10.50",
							]],
			"rateLimitResetCredits": ["availableCount": creditCount,
										"credits": creditCount == 0 ? [] : [[
										"id": "credit-a",
										"resetType": "codexRateLimits",
										"status": "available",
										"grantedAt": 1_700_000_000,
										"expiresAt": 4_102_444_800,
										"title": "Plan usage reset"
										]]],
		]))
	}

	private func makeWindow(_ page: NSView) -> NSWindow
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 1100,
				height: 760
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.appearance = NSAppearance(named: .aqua)
		let surface = SettingsSurfaceView(color: AppKitColorTokens.canvas)
		window.contentView = surface
		AppKitLayout.pin(
			page,
			to: surface,
			inset: 0
		)
		window.orderFront(nil)
		window.layoutIfNeeded()
		return window
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}

	private func labels(_ view: NSView) -> [String]
	{
		descendants(view).filter
		{
			!$0.isHiddenOrHasHiddenAncestor
		}.compactMap
		{
			($0 as? NSTextField)?.stringValue
		}
	}

	private func buttons(_ view: NSView) -> [NSButton]
	{
		descendants(view).filter
		{
			!$0.isHiddenOrHasHiddenAncestor
		}.compactMap
		{
			$0 as? NSButton
		}
	}

	private func button(
		_ title: String,
		in view: NSView
	) throws -> NSButton
	{
		try #require(buttons(view).first
		{
			$0.title == title || $0.accessibilityLabel() == title
		})
	}

	private func buttonEnabled(
		_ title: String,
		in view: NSView
	) -> Bool
	{
		let control = buttons(view).first
		{
			$0.title == title || $0.accessibilityLabel() == title
		}
		return control?.isEnabled == true
	}

	private func progressValues(_ view: NSView) -> [String]
	{
		descendants(view).filter
		{
			$0.accessibilityRole() == .progressIndicator
		}
		.compactMap
		{
			$0.accessibilityValue() as? String
		}
	}

	private func assertResetSectionLayout(_ page: NSView) throws
	{
		page.window?.layoutIfNeeded()
		page.layoutSubtreeIfNeeded()
		let heading = try #require(descendants(page).compactMap
		{
			$0 as? NSTextField
		}.first
		{
			$0.stringValue == "Usage limit resets"
		})
		let section = try #require(heading.superview as? NSStackView)
		let body = try #require(section.superview as? NSStackView)
		let index = try #require(body.arrangedSubviews.firstIndex
		{
			$0 === section
		})
		try #require(index > 0)
		let preceding = body.arrangedSubviews[index - 1]
		let scroll = try #require(descendants(page).compactMap
		{
			$0 as? NSScrollView
		}.first)
		let document = try #require(scroll.documentView)
		let before = document.convert(
			preceding.bounds,
			from: preceding
		)
		let after = document.convert(
			section.bounds,
			from: section
		)
		#expect(before.height > 0)
		#expect(after.height > 0)
		#expect(!before.intersects(after))
		let gap = after.minY - before.maxY
		#expect(abs(gap - LayoutTokens.Connections.sectionGap) < 1)
	}

	private func capture(
		_ page: NSView,
		suffix: String
	) throws
	{
		guard let directory = ProcessInfo.processInfo.environment["CODEX_GUI_USAGE_PREVIEW"]
		else
		{
			return
		}
		let output = URL(
			fileURLWithPath: directory,
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: output,
			withIntermediateDirectories: true
		)
		let canvas = page.window?.contentView ?? page
		page.window?.layoutIfNeeded()
		canvas.layoutSubtreeIfNeeded()
		for child in descendants(canvas)
		{
			child.needsDisplay = true
		}
		canvas.display()
		try AppTestPNGWriter.write(
			canvas,
			to: output.appendingPathComponent(suffix + ".png")
		)
	}
}
