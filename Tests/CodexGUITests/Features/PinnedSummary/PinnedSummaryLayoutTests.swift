import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct PinnedSummaryLayoutTests
{
	@Test func populatedCardFitsNormalHeightAndKeepsConstrainedRowsAccessible() throws
	{
		_ = NSApplication.shared
		let inspector = InspectorViewController()
		let model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/fixture/workspace"
		))
		var sections = ContextSummarySections()
		sections.changes = .available(SummaryChangeTotals(
			additions: 7,
			deletions: 2
		))
		sections.agents = .available(SummaryAgentProjection(
			identities: [],
			completedCount: 2,
			runningCount: 1,
			aggregationDescription: "Associated with this chat"
		))
		sections.sources = .available((0 ..< 3).map
		{
			SummarySourceReference(
				id: "attachment-\($0)",
				label: "neutral-long-attachment-name-\($0).png",
				kind: .attachment
			)
		})
		sections.availableDestinations = [.changes, .sources, .subagents]
		let presentation = PinnedSummaryPresentation(
			WorkspaceSelectors.snapshot(
				model: model,
				now: .distantPast
			),
			sections: sections
		)
		inspector.renderSummary(
			presentation,
			visible: true
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 320,
				height: 500
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = inspector
		window.setContentSize(NSSize(
			width: 320,
			height: 500
		))
		defer
		{
			window.close()
		}
		window.layoutIfNeeded()
		inspector.view.layoutSubtreeIfNeeded()
		let scroll = try #require(inspector.summary.view as? NSScrollView)
		let box = try #require(inspector.view.subviews.first)
		#expect(inspector.summary.preferredContentHeight > 0)
		#expect(abs(scroll.convert(
			.zero,
			to: box
		).x - 20) < 1)
		#expect(abs(box.frame.height - min(
			440,
			inspector.summary.preferredContentHeight + 20
		)) < 1)
		let document = try #require(scroll.documentView)
		let all = try #require(descendants(document).compactMap
		{
			$0 as? NSButton
		}
		.first
		{
			$0.title == "View all"
		})
		#expect(scroll.contentView.bounds.contains(all.convert(
			all.bounds,
			to: document
		)))
		let names = descendants(document).compactMap
		{
			$0 as? NSTextField
		}
		.filter
		{
			$0.stringValue.hasPrefix("neutral-long-")
		}
		#expect(names.count == 3)
		#expect(names.allSatisfy
		{
			$0.textColor == .secondaryLabelColor
		})
		#expect(names.allSatisfy
		{
			$0.frame.width > 80
		})
		#expect(descendants(document).compactMap
		{
			$0 as? NSButton
		}
		.first
		{
			$0.title == "Changes"
		}?.isEnabled == true)

		window.setContentSize(NSSize(
			width: 260,
			height: 220
		))
		window.layoutIfNeeded()
		inspector.view.layoutSubtreeIfNeeded()
		#expect(document.frame.height > scroll.contentSize.height)
		all.scrollToVisible(all.bounds)
		#expect(scroll.contentView.bounds.intersects(all.convert(
			all.bounds,
			to: document
		)))
		#expect(names.allSatisfy
		{
			$0.frame.width > 50
		})
	}

	@Test func firstActivityPublicationWithoutMonitorKeepsViewAllInsideCard() throws
	{
		_ = NSApplication.shared
		let inspector = InspectorViewController()
		let model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/fixture/workspace"
		))
		let snapshot = WorkspaceSelectors.snapshot(
			model: model,
			now: .distantPast
		)
		inspector.renderSummary(
			PinnedSummaryPresentation(snapshot),
			visible: true
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 320,
				height: 500
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = inspector
		window.setContentSize(NSSize(
			width: 320,
			height: 500
		))
		defer
		{
			window.close()
		}
		window.layoutIfNeeded()
		inspector.view.layoutSubtreeIfNeeded()

		var sections = ContextSummarySections()
		sections.changes = .unavailable("Open Changes to load a repository comparison")
		sections.sources = .available([
			SummarySourceReference(
				id: "tool",
				label: "Call",
				kind: .tool
			),
			SummarySourceReference(
				id: "web",
				label: "Search",
				kind: .web
			),
		])
		sections.availableDestinations.insert(.sources)
		inspector.renderSummary(
			PinnedSummaryPresentation(
				snapshot,
				sections: sections
			),
			visible: true
		)
		window.layoutIfNeeded()
		inspector.view.layoutSubtreeIfNeeded()
		let scroll = try #require(inspector.summary.view as? NSScrollView)
		let document = try #require(scroll.documentView)
		let all = try #require(descendants(document).compactMap
		{
			$0 as? NSButton
		}
		.first
		{
			$0.title == "View all"
		})
		#expect(scroll.contentView.bounds.contains(all.convert(
			all.bounds,
			to: document
		)))
		#expect(descendants(document).compactMap
		{
			$0 as? NSButton
		}
		.filter
		{
			["ChatGPT App Tools", "Web search"].contains($0.title)
		}.count == 2)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}
