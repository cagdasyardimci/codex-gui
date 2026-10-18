import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationContentTests
{
	@Test func literalOutputKeepsMarkdownMarkersAndWhitespace() async
	{
		let body = "  # command\n- literal\n```x```\n\nlast  "
		let cache = ConversationContentCache()
		let content = await cache.content(
			body: body,
			markdown: false
		)

		#expect(content.attributedString.string == body)
		#expect(content.codeBlocks.isEmpty)
		let font = content.attributedString.attribute(
			.font,
			at: 0,
			effectiveRange: nil
		) as? NSFont
		#expect(font?.fontName.lowercased().contains("mono") == true)
		let again = await cache.content(
			body: body,
			markdown: false
		)
		#expect(content === again)
	}

	@Test func markdownStylesHeadingsListsAndLinksAndPreservesCodeForCopy() async
	{
		let body = """
		# Heading
		- first

		2. second [site](https://example.com/path)

		```swift
		let value = "  exact  "
		```
		End
		"""
		let content = await ConversationContentCache().content(
			body: body,
			markdown: true
		)
		let text = content.attributedString.string

		#expect(text.contains("Heading\n•\tfirst\n2. second \u{FFFC}site"))
		#expect(!text.contains("```"))
		#expect(content.codeBlocks == ["let value = \"  exact  \"\n"])
		let heading = (text as NSString).range(of: "Heading")
		let headingFont =
			content.attributedString.attribute(
				.font,
				at: heading.location,
				effectiveRange: nil
			) as? NSFont
		#expect(headingFont?.pointSize == 24)
		let link = (text as NSString).range(of: "site")
		let icon = content.attributedString.attribute(
			.attachment,
			at: link.location - 1,
			effectiveRange: nil
		) as? WebLinkFaviconAttachment
		#expect(icon?.url.absoluteString == "https://example.com/path")
		let url =
			content.attributedString.attribute(
				.link,
				at: link.location,
				effectiveRange: nil
			) as? URL
		#expect(url?.absoluteString == "https://example.com/path")
	}

	@Test func measuredHeightUsesPreparedTextAtNarrowAndWideWidths() async throws
	{
		_ = NSApplication.shared
		let body = """
		\(String(repeating: "Long output with text that wraps at a narrow pane width. ", count: 12))

		> A quoted paragraph with **emphasis** and `inline code`.

		- first item
		  - nested item with text that wraps at a narrow width

		| Name | Result |
		| :--- | ---: |
		| long table content that needs to wrap in a narrow pane | 42 |

		```text
		first
		```
		```text
		second
		```
		"""
		let content = await ConversationContentCache().content(
			body: body,
			markdown: true
		)
		let narrow = ConversationCollectionItem.itemSize(
			content: content,
			width: 220,
			expandable: true
		)
		let wide = ConversationCollectionItem.itemSize(
			content: content,
			width: 420,
			expandable: true
		)
		let repeated = ConversationCollectionItem.itemSize(
			content: content,
			width: 220,
			expandable: true
		)

		#expect(content.codeBlocks.count == 2)
		#expect(narrow.height >= wide.height)
		#expect(narrow == repeated)
		for size in [narrow, wide]
		{
			let item = ConversationCollectionItem()
			item.configure(
				ConversationEntry(
					id: "measured",
					kind: .agent,
					title: "Codex",
					body: body,
					isExpandable: true
				),
				content: content,
				expanded: true,
				onToggle:
				{
				}
			)
			let window = NSWindow(
				contentRect: NSRect(
					origin: .zero,
					size: size
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.contentViewController = item
			defer
			{
				window.contentViewController = nil
				window.close()
			}
			window.setContentSize(size)
			item.view.layoutSubtreeIfNeeded()
			let textView = try #require(findTextView(in: item.view))
			#expect(textView.string == content.attributedString.string)
			#expect(textView.bounds.width > 0)

			// Lay out the realized text at its actual width without the item's height constraint.
			// This checks content fit independently of itemSize's cached height and padding math.
			let storage = NSTextStorage(attributedString: try #require(textView.textStorage))
			let layout = NSLayoutManager()
			let container = NSTextContainer(
				size: NSSize(
					width: textView.bounds.width,
					height: .greatestFiniteMagnitude
				)
			)
			container.lineFragmentPadding = try #require(textView.textContainer).lineFragmentPadding
			storage.addLayoutManager(layout)
			layout.addTextContainer(container)
			layout.ensureLayout(for: container)
			#expect(layout.usedRect(for: container).height <= textView.bounds.height)
			#expect(item.view.bounds.contains(textView.convert(
				textView.bounds,
				to: item.view
			)))
		}
	}

	@Test func reusedMessagesKeepUnusedControlsOutsideTheirMeasuredLayout() async throws
	{
		_ = NSApplication.shared
		let body = String(
			repeating: "Long message line that wraps.\n",
			count: 60
		) + "Final reading marker"
		let content = await ConversationContentCache().content(
			body: body,
			markdown: false
		)
		let item = ConversationCollectionItem()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 320,
				height: 2000
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = item
		defer
		{
			window.contentViewController = nil
			window.close()
		}
		for (kind, expandable) in [
			(ConversationEntryKind.command, true),
			(.agent, false),
			(.user, false),
			(.tool, true),
			(.notice, false),
			(.agent, true),
		]
		{
			let textView = try #require(findTextView(in: item.view))
			let stack = try #require(textView.superview as? NSStackView)
			let previousControls = stack.views
			item.configure(
				ConversationEntry(
					id: "reused",
					kind: kind,
					title: "Message title",
					body: body,
					isExpandable: expandable
				),
				content: content,
				expanded: true,
				onToggle:
				{
				}
			)
			// Re-exposing controls from a previous reuse must not add unmeasured title/button rows.
			for control in previousControls
			{
				control.isHidden = false
			}
			let size = ConversationCollectionItem.itemSize(
				content: content,
				width: 320,
				expandable: expandable,
				kind: kind
			)
			window.setContentSize(size)
			item.view.layoutSubtreeIfNeeded()
			let hasTitle = kind != .agent && kind != .user
			#expect(stack.views.compactMap
			{
				$0 as? NSTextField
			}.count == (hasTitle ? 1 : 0))
			#expect(allButtons(in: item.view).count == (expandable ? 1 : 0))
			#expect(item.view.bounds.contains(textView.convert(
				textView.bounds,
				to: item.view
			)))
			let layout = try #require(textView.layoutManager)
			let container = try #require(textView.textContainer)
			layout.ensureLayout(for: container)
			#expect(layout.usedRect(for: container).height <= textView.bounds.height)
		}
	}

	@Test func longerAndTildeFencesKeepShorterDelimitersInsideCode() async
	{
		let body = """
		````text
		first
		```
		second
		````
		~~~text
		third
		~~~
		"""
		let content = await ConversationContentCache().content(
			body: body,
			markdown: true
		)
		#expect(content.codeBlocks == ["first\n```\nsecond\n", "third\n"])
	}

	@Test func codeCopyControlsAlignWithTheirBlocks() async throws
	{
		_ = NSApplication.shared
		let body = """
		```text
		first
		```
		```text
		second
		```
		"""
		let content = await ConversationContentCache().content(
			body: body,
			markdown: true
		)
		let item = ConversationCollectionItem()
		item.configure(
			ConversationEntry(
				id: "agent",
				kind: .agent,
				title: "Codex",
				body: body
			),
			content: content,
			expanded: true,
			onToggle:
			{
			}
		)
		item.view.frame = NSRect(
			x: 0,
			y: 0,
			width: 320,
			height: 300
		)
		let window = NSWindow(
			contentRect: item.view.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = item
		defer
		{
			window.contentViewController = nil
			window.close()
		}
		window.setContentSize(NSSize(
			width: 320,
			height: 300
		))
		item.view.layoutSubtreeIfNeeded()

		// Hover controls can change stacking order; identify blocks by their stable labels.
		let buttons = allButtons(in: item.view).filter
		{
			($0.accessibilityLabel() ?? "").hasPrefix("Copy code block ")
		}.sorted
		{
			($0.accessibilityLabel() ?? "") < ($1.accessibilityLabel() ?? "")
		}
		let textView = try #require(findTextView(in: item.view))
		#expect(buttons.map
		{
			$0.accessibilityLabel()
		} == [
			"Copy code block 1",
			"Copy code block 2"
		])
		try #require(buttons.count == 2)
		#expect(buttons.allSatisfy
		{
			$0.superview !== textView && $0.title.isEmpty && $0.imagePosition == .imageOnly
		})
		#expect(buttons.allSatisfy
		{
			textView.convert(
				$0.bounds,
				from: $0
			).maxX <= textView.bounds.width
		})
		#expect(textView.convert(
			buttons[0].bounds,
			from: buttons[0]
		).minY
			< textView.convert(
				buttons[1].bounds,
				from: buttons[1]
			).minY)
		for (index, range) in content.codeBlockRanges.enumerated()
		{
			#expect(
				(content.attributedString.string as NSString).substring(with: range)
					== content.codeBlocks[index]
			)
		}
	}

	private func findTextView(in view: NSView) -> NSTextView?
	{
		if let textView = view as? NSTextView
		{
			return textView
		}
		return view.subviews.lazy.compactMap
		{
			findTextView(in: $0)
		}.first
	}

	private func allButtons(in view: NSView) -> [NSButton]
	{
		((view as? NSButton).map
		{
			[$0]
		} ?? [])
			+ view.subviews.flatMap
			{
				allButtons(in: $0)
			}
	}
}
