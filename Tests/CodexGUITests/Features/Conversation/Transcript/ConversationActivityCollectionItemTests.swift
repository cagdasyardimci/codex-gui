import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationActivityCollectionItemTests
{
	@Test func commandDetailPreservesFullOutputAndClearsOnReuse()
	{
		let item = ConversationActivityCollectionItem()
		var row = commandRow(
			expanded: true,
			output: "first\nlast\n"
		)
		item.configure(
			row,
			onToggle:
			{
			},
			onOpenFile:
			{
				_ in
			}
		)
		let text = descendants(item.view).compactMap
		{
			$0 as? NSTextView
		}.first
		#expect(text?.isSelectable == true)
		#expect(text?.isEditable == false)
		#expect(text?.string == "$ printf 'first\\nlast\\n'\nfirst\nlast\n")
		row.expanded = false
		item.configure(
			row,
			onToggle:
			{
			},
			onOpenFile:
			{
				_ in
			}
		)
		#expect(text?.string == "")
		#expect(!descendants(item.view).contains
		{
			$0 is NSScrollView
		})
	}

	@Test func readLinkAndDisclosureHaveIndependentCallbacks() throws
	{
		let item = ConversationActivityCollectionItem()
		var row = commandRow(expanded: false)
		row = ConversationActivityRow(
			id: row.id,
			sourceEntryID: row.sourceEntryID,
			groupID: row.groupID,
			kind: .read,
			title: "Read example.swift",
			filePath: "/tmp/example.swift",
			linkTitle: "example.swift",
			command: row.command
		)
		var opened: String?
		var toggles = 0
		item.configure(
			row,
			onToggle:
			{
				toggles += 1
			},
			onOpenFile:
			{
				opened = $0
			}
		)
		let buttons = descendants(item.view).compactMap
		{
			$0 as? NSButton
		}
		try #require(buttons.first
		{
			$0.attributedTitle.string == "example.swift"
		})
		.performClick(nil)
		#expect(opened == "/tmp/example.swift")
		#expect(toggles == 0)
		try #require(buttons.first
		{
			$0.attributedTitle.string != "example.swift"
		})
		.performClick(nil)
		#expect(toggles == 1)
	}

	@Test func disclosureFollowsActivityTextAtWideWidths() throws
	{
		let command = commandRow(expanded: false)
		let read = ConversationActivityRow(
			id: "read",
			sourceEntryID: "read",
			groupID: "group",
			kind: .read,
			title: "Read example.swift",
			filePath: "/tmp/example.swift",
			linkTitle: "example.swift",
			command: command.command
		)
		for row in [command, read]
		{
			let item = ConversationActivityCollectionItem()
			item.configure(
				row,
				onToggle:
				{
				},
				onOpenFile:
				{
					_ in
				}
			)
			item.view.frame = NSRect(
				origin: .zero,
				size: ConversationActivityCollectionItem.itemSize(
					row: row,
					width: 1000
				)
			)
			item.view.layoutSubtreeIfNeeded()
			let header = try #require(descendants(item.view).first
			{
				!$0.trackingAreas.isEmpty
			})
			let disclosure = try #require(header.subviews.compactMap
			{
				$0 as? NSButton
			}.first
			{
				$0.accessibilityLabel()?.hasPrefix("Expand ") == true
			})
			let precedingView: NSView
			if row.kind == .read
			{
				precedingView = try #require(header.subviews.compactMap
				{
					$0 as? NSButton
				}.first
				{
					$0.attributedTitle.string == "example.swift"
				})
			}
			else
			{
				precedingView = try #require(header.subviews.compactMap
				{
					$0 as? NSTextField
				}.first
				{
					$0.stringValue == row.title
				})
			}
			#expect(disclosure.frame.minX - precedingView.frame.maxX < 20)
			#expect(disclosure.frame.maxX < header.frame.width / 2)
		}
	}

	@Test func shellHeightIsBoundedAndMatchesLayoutAtDifferentWidths()
	{
		for width: CGFloat in [220, 1000]
		{
			for output in ["", String(
				repeating: "long output line\n",
				count: 3000
			)]
			{
				let row = commandRow(
					expanded: true,
					output: output
				)
				let size = ConversationActivityCollectionItem.itemSize(
					row: row,
					width: width
				)
				#expect(size.height >= 136)
				#expect(size.height <= 314)
				let item = ConversationActivityCollectionItem()
				item.configure(
					row,
					onToggle:
					{
					},
					onOpenFile:
					{
						_ in
					}
				)
				item.view.frame = NSRect(
					origin: .zero,
					size: size
				)
				item.view.layoutSubtreeIfNeeded()
				item.viewDidLayout()
				item.view.layoutSubtreeIfNeeded()
				#expect(abs(item.view.fittingSize.height - size.height) < 1)
			}
		}
	}

	@Test func outputAppendPreservesInnerScrollAndSelection() throws
	{
		let item = ConversationActivityCollectionItem()
		let original = String(
			repeating: "A line of shell output\n",
			count: 150
		)
		var row = commandRow(
			expanded: true,
			output: original
		)
		item.configure(
			row,
			onToggle:
			{
			},
			onOpenFile:
			{
				_ in
			}
		)
		layout(
			item,
			row: row
		)
		let textView = try #require(descendants(item.view).compactMap
		{
			$0 as? NSTextView
		}.first)
		let scrollView = try #require(descendants(item.view).compactMap
		{
			$0 as? NSScrollView
		}
		.first)
		textView.setSelectedRange(NSRange(
			location: 40,
			length: 13
		))
		scrollView.contentView.scroll(to: NSPoint(
			x: 0,
			y: 120
		))
		scrollView.reflectScrolledClipView(scrollView.contentView)
		let before = try #require(item.outputReadingPosition())
		#expect(before.origin.y > 0)
		#expect(before.selection == NSRange(
			location: 40,
			length: 13
		))
		row.command = ConversationCommand(
			command: row.command!.command,
			cwd: "/tmp",
			output: original + "appended line\n",
			status: "inProgress",
			exitCode: nil,
			durationMs: nil,
			actions: []
		)
		item.configure(
			row,
			onToggle:
			{
			},
			onOpenFile:
			{
				_ in
			}
		)
		layout(
			item,
			row: row
		)
		let after = try #require(item.outputReadingPosition())
		#expect(after.origin == before.origin)
		#expect(after.selection == before.selection)
		#expect(textView.string.hasSuffix("appended line\n"))
	}

	@Test func readingPositionRestoreClampsAndDifferentRowResets() throws
	{
		let item = ConversationActivityCollectionItem()
		let first = commandRow(
			expanded: true,
			output: String(
				repeating: "output\n",
				count: 150
			)
		)
		item.configure(
			first,
			onToggle:
			{
			},
			onOpenFile:
			{
				_ in
			}
		)
		layout(
			item,
			row: first
		)
		item.restoreOutputReadingPosition(ConversationActivityCollectionItem.OutputReadingPosition(
			origin: NSPoint(
				x: 0,
				y: 80
			),
			selection: NSRange(
				location: 30,
				length: 10
			)
		))
		layout(
			item,
			row: first
		)
		#expect(try #require(item.outputReadingPosition()).origin.y == 80)
		let second = ConversationActivityRow(
			id: "another",
			sourceEntryID: "another",
			groupID: "group",
			kind: .command,
			title: "Ran printf",
			command: first.command,
			expanded: true
		)
		item.configure(
			second,
			onToggle:
			{
			},
			onOpenFile:
			{
				_ in
			}
		)
		layout(
			item,
			row: second
		)
		let reset = try #require(item.outputReadingPosition())
		#expect(reset.origin == .zero)
		#expect(reset.selection == NSRange(
			location: 0,
			length: 0
		))
		item.restoreOutputReadingPosition(ConversationActivityCollectionItem.OutputReadingPosition(
			origin: NSPoint(
				x: 99999,
				y: 99999
			),
			selection: NSRange(
				location: 99999,
				length: 99999
			)
		))
		layout(
			item,
			row: second
		)
		let clamped = try #require(item.outputReadingPosition())
		let textView = try #require(descendants(item.view).compactMap
		{
			$0 as? NSTextView
		}.first)
		#expect(clamped.origin.y > 0 && clamped.origin.y < 99999)
		#expect(clamped.origin.x == 0)
		#expect(clamped.selection == NSRange(
			location: (textView.string as NSString).length,
			length: 0
		))
		item.prepareForReuse()
		#expect(item.activityID == nil)
		#expect(item.outputReadingPosition() == nil)
	}

	private func layout(
		_ item: ConversationActivityCollectionItem,
		row: ConversationActivityRow
	)
	{
		item.view.frame = NSRect(
			origin: .zero,
			size: ConversationActivityCollectionItem.itemSize(
				row: row,
				width: 400
			)
		)
		item.view.layoutSubtreeIfNeeded()
		item.viewDidLayout()
		item.view.layoutSubtreeIfNeeded()
	}

	@Test func disclosureGlyphAppearsOnlyOverHeaderWithoutLosingInteraction() throws
	{
		for kind: ConversationActivityRow.Kind in [
			.group,
			.command,
			.read,
			.search,
			.listFiles,
			.image
		]
		{
			let item = ConversationActivityCollectionItem()
			let row = ConversationActivityRow(
				id: "hover",
				sourceEntryID: "hover",
				groupID: "group",
				kind: kind,
				title: "Activity",
				command: kind == .group || kind == .image ? nil :
					commandRow(expanded: false).command
			)
			var toggles = 0
			item.configure(
				row,
				onToggle:
				{
					toggles += 1
				},
				onOpenFile:
				{
					_ in
				}
			)
			layout(
				item,
				row: row
			)
			let button = try #require(descendants(item.view).compactMap
			{
				$0 as? NSButton
			}
			.first
			{
				$0.accessibilityLabel() == "Expand Activity"
			})
			let header = try #require(descendants(item.view).first
			{
				!$0.trackingAreas.isEmpty
			})
			#expect(header.frame.height == 30)
			#expect(header.trackingAreas.count == 1)
			#expect(header.trackingAreas[0].options.contains(.inVisibleRect))
			let title = try #require(header.subviews.compactMap
			{
				$0 as? NSTextField
			}
			.first
			{
				$0.stringValue == "Activity"
			})
			let restingFrame = button.frame
			#expect(title.textColor == .secondaryLabelColor)
			#expect(button.image == nil)
			#expect(!button.isHidden && button.alphaValue == 1)
			#expect(button.acceptsFirstResponder)
			#expect(button.isAccessibilityElement())
			#expect(button.frame.size == NSSize(
				width: 24,
				height: 24
			))
			#expect(button.hitTest(NSPoint(
				x: button.frame.midX,
				y: button.frame.midY
			)) === button)
			button.performClick(nil)
			#expect(toggles == 1)
			let entered = try hoverEvent(type: .mouseEntered)
			item.mouseEntered(with: entered)
			let hoveredImage = try #require(button.image)
			#expect(title.textColor == .labelColor)
			item.mouseEntered(with: entered)
			#expect(button.image === hoveredImage)
			#expect(button.frame == restingFrame)
			item.mouseExited(with: try hoverEvent(type: .mouseExited))
			#expect(title.textColor == .secondaryLabelColor)
			#expect(button.image == nil)
			#expect(button.frame == restingFrame)
			item.mouseEntered(with: entered)
			item.prepareForReuse()
			#expect(title.textColor == .secondaryLabelColor)
			#expect(button.image == nil)
			item.configure(
				row,
				onToggle:
				{
					toggles += 1
				},
				onOpenFile:
				{
					_ in
				}
			)
			#expect(button.image == nil)
			button.performClick(nil)
			#expect(toggles == 2)
		}
	}

	private func hoverEvent(type: NSEvent.EventType) throws -> NSEvent
	{
		try #require(NSEvent.enterExitEvent(
			with: type,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			eventNumber: 0,
			trackingNumber: 0,
			userData: nil
		))
	}

	@Test func activityHeaderAndShellFillTheRowAtEveryTranscriptWidth() throws
	{
		let item = ConversationActivityCollectionItem()
		for width: CGFloat in [220, 736, 1000]
		{
			for expanded in [false, true]
			{
				let row = commandRow(
					expanded: expanded,
					output: "short output"
				)
				item.configure(
					row,
					onToggle:
					{
					},
					onOpenFile:
					{
						_ in
					}
				)
				item.view.frame = NSRect(
					origin: .zero,
					size: ConversationActivityCollectionItem.itemSize(
						row: row,
						width: width
					)
				)
				item.view.layoutSubtreeIfNeeded()
				item.viewDidLayout()
				item.view.layoutSubtreeIfNeeded()
				let header = try #require(descendants(item.view)
					.first
					{
						!$0.trackingAreas.isEmpty
					})
				let headerBounds = header.convert(
					header.bounds,
					to: item.view
				)
				#expect(abs(headerBounds.minX - item.view.bounds.minX) < 0.5)
				#expect(abs(headerBounds.width - item.view.bounds.width) < 0.5)
				let icon = try #require(header.subviews.compactMap
				{
					$0 as? NSImageView
				}.first)
				let iconBounds = icon.convert(
					icon.bounds,
					to: item.view
				)
				#expect(abs(iconBounds.minX - item.view.bounds.minX) < 0.5)
				if expanded
				{
					let scroll = try #require(descendants(item.view)
						.compactMap
						{
							$0 as? NSScrollView
						}.first)
					let shell = try #require(scroll.superview?.superview)
					#expect(shell is DesktopSurface)
					let shellBounds = shell.convert(
						shell.bounds,
						to: item.view
					)
					#expect(abs(shellBounds.minX - item.view.bounds.minX) < 0.5)
					#expect(abs(shellBounds.width - item.view.bounds.width) < 0.5)
				}
			}
		}
	}

	@Test func shownWindowHoverUsesSettledHeaderGeometryAfterRepositioning() async throws
	{
		_ = NSApplication.shared
		let cursor = NSEvent.mouseLocation
		let window = NSWindow(
			contentRect: NSRect(
				x: cursor.x - 250,
				y: cursor.y - 250,
				width: 500,
				height: 500
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		defer
		{
			window.orderOut(nil)
		}
		let content = NSView(frame: NSRect(
			x: 0,
			y: 0,
			width: 500,
			height: 500
		))
		window.contentView = content
		let item = ConversationActivityCollectionItem()
		let row = commandRow(expanded: false)
		item.configure(
			row,
			onToggle:
			{
			},
			onOpenFile:
			{
				_ in
			}
		)
		content.addSubview(item.view)
		let button = try #require(descendants(item.view).compactMap
		{
			$0 as? NSButton
		}
		.first
		{
			$0.accessibilityLabel()?.hasPrefix("Expand") == true
		})
		window.orderFront(nil)
		for overHeader in [false, true, false]
		{
			let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
			item.view.frame = NSRect(
				x: point.x - 150,
				y: point.y - (overHeader ? 15 : 100),
				width: 400,
				height: 30
			)
			item.view.layoutSubtreeIfNeeded()
			item.viewDidLayout()
			item.view.layoutSubtreeIfNeeded()
			for _ in 0 ..< 10
			{
				await Task.yield()
			}
			let header = try #require(descendants(item.view).first
			{
				!$0.trackingAreas.isEmpty
			})
			let headerBounds = header.convert(
				header.bounds,
				to: nil
			)
			let settledPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
			#expect(headerBounds.contains(settledPoint) == overHeader)
			#expect((button.image != nil) == overHeader)
			let title = try #require(header.subviews.compactMap
			{
				$0 as? NSTextField
			}.first)
			#expect(title.textColor == (overHeader ? NSColor.labelColor : .secondaryLabelColor))
			#expect(button.isAccessibilityElement())
			#expect(button.acceptsFirstResponder)
			#expect(!button.isHidden && button.alphaValue == 1)
		}
	}

	@Test func hoverHighlightsReadTextPreservingUnderlineFailureAndShell() throws
	{
		let item = ConversationActivityCollectionItem()
		let row = ConversationActivityRow(
			id: "read",
			sourceEntryID: "read",
			groupID: "group",
			kind: .read,
			title: "Read example.swift",
			filePath: "/tmp/example.swift",
			linkTitle: "example.swift",
			command: ConversationCommand(
				command: "cat example.swift",
				cwd: "/tmp",
				output: "denied",
				status: "failed",
				exitCode: 3,
				durationMs: nil,
				actions: []
			),
			expanded: true
		)
		var openedPath: String?
		item.configure(
			row,
			onToggle:
			{
			},
			onOpenFile:
			{
				openedPath = $0
			}
		)
		layout(
			item,
			row: row
		)
		let link = try #require(descendants(item.view).compactMap
		{
			$0 as? NSButton
		}
		.first
		{
			$0.attributedTitle.string == "example.swift"
		})
		let title = try #require(descendants(item.view).compactMap
		{
			$0 as? NSTextField
		}
		.first
		{
			$0.stringValue == "Read"
		})
		let failure = try #require(descendants(item.view).compactMap
		{
			$0 as? NSTextField
		}
		.first
		{
			$0.stringValue == "Exit 3"
		})
		let output = try #require(descendants(item.view).compactMap
		{
			$0 as? NSTextView
		}.first)
		let originalText = output.string
		let originalFrame = link.frame
		#expect(link.attributedTitle.attribute(
			.foregroundColor,
			at: 0,
			effectiveRange: nil
		)
			as? NSColor == .secondaryLabelColor)
		item.mouseEntered(with: try hoverEvent(type: .mouseEntered))
		#expect(title.textColor == .labelColor)
		#expect(link.attributedTitle.attribute(
			.foregroundColor,
			at: 0,
			effectiveRange: nil
		)
			as? NSColor == .labelColor)
		#expect(link.attributedTitle.attribute(
			.underlineStyle,
			at: 0,
			effectiveRange: nil
		)
			as? Int == 1)
		#expect(link.frame == originalFrame)
		#expect(failure.textColor == .systemRed)
		#expect(output.textColor == .secondaryLabelColor)
		#expect(output.string == originalText)
		link.performClick(nil)
		#expect(openedPath == "/tmp/example.swift")
		item.configure(
			row,
			onToggle:
			{
			},
			onOpenFile:
			{
				openedPath = $0
			}
		)
		#expect(link.attributedTitle.attribute(
			.foregroundColor,
			at: 0,
			effectiveRange: nil
		)
			as? NSColor == .labelColor)
		item.mouseExited(with: try hoverEvent(type: .mouseExited))
		#expect(title.textColor == .secondaryLabelColor)
		#expect(link.attributedTitle.attribute(
			.foregroundColor,
			at: 0,
			effectiveRange: nil
		)
			as? NSColor == .secondaryLabelColor)
		item.mouseEntered(with: try hoverEvent(type: .mouseEntered))
		item.prepareForReuse()
		#expect(title.textColor == .secondaryLabelColor)
		#expect(link.attributedTitle.attribute(
			.foregroundColor,
			at: 0,
			effectiveRange: nil
		)
			as? NSColor == .secondaryLabelColor)
	}

	@Test func failedExitRemainsVisibleWhenCollapsed()
	{
		let item = ConversationActivityCollectionItem()
		var row = commandRow(expanded: false)
		row.command = ConversationCommand(
			command: "false",
			cwd: nil,
			output: "",
			status: "completed",
			exitCode: 3,
			durationMs: nil,
			actions: []
		)
		item.configure(
			row,
			onToggle:
			{
			},
			onOpenFile:
			{
				_ in
			}
		)
		#expect(descendants(item.view).compactMap
		{
			$0 as? NSTextField
		}
		.contains
		{
			$0.stringValue == "Exit 3"
		})
	}

	@Test func missingImagePathHasVisibleUnavailableState()
	{
		let item = ConversationActivityCollectionItem()
		let row = ConversationActivityRow(
			id: "image",
			sourceEntryID: "image",
			groupID: "image",
			kind: .image,
			title: "Viewed an image",
			expanded: true
		)
		item.configure(
			row,
			onToggle:
			{
			},
			onOpenFile:
			{
				_ in
			}
		)
		#expect(descendants(item.view).compactMap
		{
			$0 as? NSTextField
		}
		.contains
		{
			$0.stringValue == "Image unavailable"
		})
	}

	private func commandRow(
		expanded: Bool,
		output: String = ""
	) -> ConversationActivityRow
	{
		ConversationActivityRow(
			id: "command",
			sourceEntryID: "command",
			groupID: "group",
			kind: .command,
			title: "Ran printf",
			command: ConversationCommand(
				command: "printf 'first\\nlast\\n'",
				cwd: "/tmp",
				output: output,
				status: "completed",
				exitCode: 0,
				durationMs: 100,
				actions: []
			),
			expanded: expanded
		)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}
}
