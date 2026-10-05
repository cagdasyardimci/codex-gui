import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct ConversationActivityCollectionItemTests
{
	@Test func commandDetailPreservesFullOutputAndClearsOnReuse() throws
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
		#expect(text?.string == "first\nlast\n")
		let command = try #require(descendants(item.view).compactMap
		{
			$0 as? NSTextField
		}.first
		{
			$0.stringValue == "$ printf 'first\\nlast\\n'"
		})
		#expect(command.isSelectable)
		#expect(!command.isEditable)
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
				#expect(size.height <= 254)
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

	@Test func longShellLinesScrollHorizontallyWithoutWrappingAndKeepReadingPosition() throws
	{
		let item = ConversationActivityCollectionItem()
		let longLine = String(
			repeating: "wide terminal output ",
			count: 80
		)
		var row = commandRow(
			expanded: true,
			output: String(
				repeating: longLine + "\n",
				count: 50
			)
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
		let text = try #require(descendants(item.view).compactMap
		{
			$0 as? NSTextView
		}.first)
		let scroll = try #require(descendants(item.view).compactMap
		{
			$0 as? NSScrollView
		}.first)
		let container = try #require(text.textContainer)
		let commandField = try #require(descendants(item.view).compactMap
		{
			$0 as? NSTextField
		}.first
		{
			$0.stringValue == "$ printf 'first\\nlast\\n'"
		})
		let commandFrame = commandField.convert(
			commandField.bounds,
			to: item.view
		)
		#expect(scroll.hasHorizontalScroller)
		#expect(scroll.hasVerticalScroller)
		#expect(text.isHorizontallyResizable)
		#expect(!container.widthTracksTextView)
		#expect(text.frame.width > scroll.contentSize.width)
		#expect(text.string.contains(longLine))
		item.restoreOutputReadingPosition(.init(
			origin: NSPoint(
				x: 180,
				y: 100
			),
			selection: NSRange(
				location: 40,
				length: 13
			)
		))
		layout(
			item,
			row: row
		)
		let before = try #require(item.outputReadingPosition())
		#expect(before.origin.x == 180)
		#expect(before.origin.y == 100)
		#expect(commandField.convert(
			commandField.bounds,
			to: item.view
		) == commandFrame)
		let command = try #require(row.command)
		row.command = ConversationCommand(
			command: command.command,
			cwd: command.cwd,
			output: command.output + "appended\n",
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
		#expect(text.string.hasSuffix("appended\n"))
		#expect(commandField.convert(
			commandField.bounds,
			to: item.view
		) == commandFrame)
	}

	@Test func multilineCommandPreviewPreservesPayloadAndLeavesOutputAndFooterVisible() throws
	{
		let commands = [
			"printf first\nprintf second",
			(0 ..< 9).map
			{
				"printf 'line \($0)'"
			}.joined(separator: "\n"),
			String(
				repeating: "printf 'wide command words'; ",
				count: 20
			)
		]
		for command in commands
		{
			for width: CGFloat in [220, 736, 1000]
			{
				let item = ConversationActivityCollectionItem()
				var row = commandRow(
					expanded: true,
					output: "done\n"
				)
				row.command = ConversationCommand(
					command: command,
					cwd: "/tmp",
					output: "done\n",
					status: "completed",
					exitCode: 0,
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
				let size = ConversationActivityCollectionItem.itemSize(
					row: row,
					width: width
				)
				item.view.frame = NSRect(
					origin: .zero,
					size: size
				)
				item.view.layoutSubtreeIfNeeded()
				item.viewDidLayout()
				item.view.layoutSubtreeIfNeeded()
				let views = descendants(item.view)
				let preview = try #require(views.compactMap
				{
					$0 as? NSTextField
				}.first
				{
					$0.accessibilityLabel() == "Shell command"
				})
				let output = try #require(views.compactMap
				{
					$0 as? NSTextView
				}.first)
				let scroll = try #require(views.compactMap
				{
					$0 as? NSScrollView
				}.first)
				let shell = try #require(scroll.superview?.superview)
				let footer = try #require(views.compactMap
				{
					$0 as? NSTextField
				}.first
				{
					$0.stringValue == "✓ Success"
				})
				#expect(preview.stringValue == "$ \(command)")
				#expect(preview.accessibilityValue() == "$ \(command)")
				#expect(preview.toolTip == command)
				#expect(preview.isSelectable && !preview.isEditable)
				#expect(preview.maximumNumberOfLines == 2)
				#expect(preview.lineBreakMode == .byWordWrapping)
				#expect(preview.cell?.truncatesLastVisibleLine == true)
				#expect(preview.clipsToBounds)
				let font = try #require(preview.font)
				#expect(font.pointSize == 13)
				#expect(output.font == font)
				let lineHeight = ceil(font.ascender - font.descender + font.leading)
				#expect(preview.frame.height <= 2 * lineHeight + 4)
				#expect(preview.frame.height >= lineHeight)
				#expect(scroll.contentSize.height >= 24)
				#expect(output.string == "done\n")
				#expect(abs(item.view.fittingSize.height - size.height) < 1)
				let previewBounds = preview.convert(
					preview.bounds,
					to: shell
				)
				let scrollBounds = scroll.convert(
					scroll.bounds,
					to: shell
				)
				let footerBounds = footer.convert(
					footer.bounds,
					to: shell
				)
				#expect(shell.bounds.contains(previewBounds))
				#expect(shell.bounds.contains(scrollBounds))
				#expect(shell.bounds.contains(footerBounds))
				#expect(!previewBounds.intersects(scrollBounds))
				#expect(!footerBounds.intersects(scrollBounds))
				for (label, anchor) in [
					("Copy command", try #require(preview.superview)),
					("Copy output", scroll)
				]
				{
					let button = try #require(views.compactMap
					{
						$0 as? NSButton
					}.first
					{
						$0.accessibilityLabel() == label
					})
					let buttonBounds = button.convert(
						button.bounds,
						to: shell
					)
					#expect(shell.bounds.contains(buttonBounds))
					#expect(anchor.convert(
						anchor.bounds,
						to: shell
					).contains(buttonBounds))
					#expect(button.target === item)
					#expect(button
						.action ==
						NSSelectorFromString(label == "Copy command" ? "copyCommand" :
							"copyOutput"))
				}
				let pasteboard = NSPasteboard.withUniqueName()
				defer
				{
					pasteboard.releaseGlobally()
				}
				item.writeCommand(to: pasteboard)
				#expect(pasteboard.string(forType: .string) == command)
			}
		}
	}

	@Test func commandPreviewReflowsAtNarrowWidthsAndCapsAdditionalLines() throws
	{
		let fixtures = [
			"printf first",
			"printf first\nprintf second",
			String(
				repeating: "printf next\n",
				count: 12
			),
			"printf 'a command with enough words to wrap at narrow terminal widths'"
		]
		var heights: [[CGFloat]] = []
		for command in fixtures
		{
			var fixtureHeights: [CGFloat] = []
			for width: CGFloat in [220, 1000]
			{
				let item = ConversationActivityCollectionItem()
				var row = commandRow(
					expanded: true,
					output: "done"
				)
				row.command = ConversationCommand(
					command: command,
					cwd: nil,
					output: "done",
					status: "completed",
					exitCode: 0,
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
				let preview = try #require(descendants(item.view).compactMap
				{
					$0 as? NSTextField
				}
				.first
				{
					$0.accessibilityLabel() == "Shell command"
				})
				fixtureHeights.append(preview.frame.height)
			}
			heights.append(fixtureHeights)
		}
		#expect(heights[1][0] > heights[0][0])
		#expect(heights[1][1] > heights[0][1])
		#expect(abs(heights[2][0] - heights[1][0]) < 1)
		#expect(abs(heights[2][1] - heights[1][1]) < 1)
		#expect(heights[3][0] > heights[3][1])
	}

	@Test func shellCopyActionsCopyCommandAndOutputSeparately() throws
	{
		let item = ConversationActivityCollectionItem()
		let row = commandRow(
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
		layout(
			item,
			row: row
		)
		let buttons = descendants(item.view).compactMap
		{
			$0 as? NSButton
		}
		let copyCommand = try #require(buttons.first
		{
			$0.accessibilityLabel() == "Copy command"
		})
		let copyOutput = try #require(buttons.first
		{
			$0.accessibilityLabel() == "Copy output"
		})
		let commandHover = try #require(copyCommand as? ConversationTerminalCopyButton)
		let outputHover = try #require(copyOutput as? ConversationTerminalCopyButton)
		#expect(!commandHover.isHovered)
		#expect(!outputHover.isHovered)
		#expect(!commandHover.isGlyphVisible)
		#expect(!outputHover.isGlyphVisible)
		#expect(commandHover.image == nil)
		#expect(outputHover.image == nil)
		commandHover.updateTrackingAreas()
		outputHover.updateTrackingAreas()
		for button in [commandHover, outputHover]
		{
			#expect(button.trackingAreas.contains
			{
				$0.options.contains(.inVisibleRect) && $0.options.contains(.activeAlways)
			})
		}
		commandHover.mouseEntered(with: try hoverEvent(type: .mouseEntered))
		#expect(commandHover.isHovered)
		#expect(commandHover.isGlyphVisible)
		#expect(commandHover.image != nil)
		#expect(outputHover.image == nil)
		#expect(!outputHover.isHovered)
		commandHover.mouseExited(with: try hoverEvent(type: .mouseExited))
		#expect(!commandHover.isHovered)
		#expect(commandHover.image == nil)
		outputHover.mouseEntered(with: try hoverEvent(type: .mouseEntered))
		#expect(outputHover.isHovered)
		#expect(outputHover.image != nil)
		#expect(copyCommand.toolTip == "Copy command")
		#expect(copyOutput.toolTip == "Copy output")
		#expect(copyCommand.acceptsFirstResponder)
		#expect(copyOutput.acceptsFirstResponder)
		#expect(copyCommand.target === item)
		#expect(copyOutput.target === item)
		#expect(copyCommand.action == NSSelectorFromString("copyCommand"))
		#expect(copyOutput.action == NSSelectorFromString("copyOutput"))
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		item.writeCommand(to: pasteboard)
		#expect(pasteboard.string(forType: .string) == row.command?.command)
		item.writeOutput(to: pasteboard)
		#expect(pasteboard.string(forType: .string) == row.command?.output)
		item.prepareForReuse()
		#expect(!commandHover.isHovered)
		#expect(!outputHover.isHovered)
		#expect(!commandHover.isTooltipVisible)
		#expect(!outputHover.isTooltipVisible)
		pasteboard.clearContents()
		item.writeCommand(to: pasteboard)
		item.writeOutput(to: pasteboard)
		#expect(pasteboard.string(forType: .string) == nil)
	}

	@Test func firstExpansionAndReexpansionLeaveCopyCellsWithoutImages() throws
	{
		let item = ConversationActivityCollectionItem()
		item.view.wantsLayer = true
		var row = commandRow(
			expanded: false,
			output: "output"
		)
		for expanded in [false, true, false, true]
		{
			row.expanded = expanded
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
			guard expanded
			else
			{
				continue
			}
			let buttons = descendants(item.view).compactMap
			{
				$0 as? ConversationTerminalCopyButton
			}
			#expect(buttons.count == 2)
			for button in buttons
			{
				#expect(!button.isGlyphVisible)
				#expect(button.image == nil)
				#expect(button.cell?.image == nil)
			}
			let button = try #require(buttons.first)
			button.mouseEntered(with: try hoverEvent(type: .mouseEntered))
			#expect(button.image != nil)
			#expect(button.cell?.image != nil)
		}
		item.prepareForReuse()
	}

	@Test func terminalCopyHoverShowsTooltipAndDismissesWithoutTakingFocus() async throws
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: NSEvent.mouseLocation.x - 92,
				y: NSEvent.mouseLocation.y - 52,
				width: 200,
				height: 100
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		let button = ConversationTerminalCopyButton()
		button.setCopyImage(DesktopIcons.image(.copy))
		#expect(button.clipsToBounds)
		button.frame = NSRect(
			x: 80,
			y: 40,
			width: 24,
			height: 24
		)
		button.toolTip = "Copy output"
		try #require(window.contentView).addSubview(button)
		defer
		{
			button.resetHover()
			window.orderOut(nil)
		}
		window.orderFront(nil)
		let originalResponder = window.firstResponder
		// The cursor is inside the parent, but initially outside the copy button.
		button.frame.origin = NSPoint(
			x: 10,
			y: 10
		)
		button.updateTrackingAreas()
		#expect(!button.isHovered)
		#expect(button.image == nil)
		button.mouseEntered(with: try hoverEvent(type: .mouseEntered))
		#expect(!button.isHovered)
		#expect(!button.isTooltipVisible)
		button.frame.origin = NSPoint(
			x: 80,
			y: 40
		)
		button.updateTrackingAreas()
		button.mouseEntered(with: try hoverEvent(type: .mouseEntered))
		#expect(button.isHovered)
		#expect(button.isGlyphVisible)
		#expect(!button.isTooltipVisible)
		try await Task.sleep(for: .milliseconds(500))
		#expect(button.isTooltipVisible)
		#expect(window.firstResponder === originalResponder)
		if ProcessInfo.processInfo.environment["CODEX_TERMINAL_CAPTURE"] == "1"
		{
			let tooltip = try #require(window.childWindows?.first?.contentView)
			tooltip.layoutSubtreeIfNeeded()
			let bitmap = try #require(tooltip.bitmapImageRepForCachingDisplay(in: tooltip.bounds))
			tooltip.cacheDisplay(
				in: tooltip.bounds,
				to: bitmap
			)
			let png = try #require(bitmap.representation(
				using: .png,
				properties: [:]
			))
			try png.write(to: URL(fileURLWithPath: "/tmp/codex-terminal-copy-tooltip.png"))
		}
		button.mouseExited(with: try hoverEvent(type: .mouseExited))
		#expect(!button.isHovered)
		#expect(!button.isGlyphVisible)
		#expect(!button.isTooltipVisible)
		button.mouseEntered(with: try hoverEvent(type: .mouseEntered))
		button.resetHover()
		try await Task.sleep(for: .milliseconds(500))
		#expect(!button.isHovered)
		#expect(!button.isTooltipVisible)
		window.makeFirstResponder(button)
		#expect(button.isGlyphVisible)
		#expect(!button.isHovered)
	}

	@Test func shellSuccessFooterDoesNotExposeRawMetadata() throws
	{
		let item = ConversationActivityCollectionItem()
		let row = commandRow(
			expanded: true,
			output: "complete\n"
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
		let labels = descendants(item.view).compactMap
		{
			$0 as? NSTextField
		}
		let footer = try #require(labels.first
		{
			$0.stringValue == "✓ Success"
		})
		#expect(!footer.isHidden)
		#expect(labels.contains
		{
			$0.stringValue == "Shell"
		})
		#expect(!labels.contains
		{
			$0.stringValue.contains("completed ·")
		})
		let footerBounds = footer.convert(
			footer.bounds,
			to: item.view
		)
		#expect(footer.alignment == .right)
		#expect(abs(footerBounds.maxX - (item.view.bounds.maxX - 10)) <= 2)
	}

	@Test func shellFooterDistinguishesRunningCompletionFailureAndInterruption()
	{
		let cases: [(String, Int?, String)] = [
			("inProgress", nil, "Running…"),
			("completed", nil, "Completed"),
			("completed", 1, "Exit code 1"),
			("completed", 3, "Exit code 3"),
			("failed", 1, "Exit code 1"),
			("failed", 127, "Exit code 127"),
			("failed", -9, "Exit code -9"),
			("failed", nil, "Failed"),
			("declined", nil, "Declined"),
			("interrupted", nil, "Interrupted"),
		]
		let item = ConversationActivityCollectionItem()
		for (status, exitCode, expected) in cases
		{
			var row = commandRow(
				expanded: true,
				output: "output"
			)
			row.command = ConversationCommand(
				command: "swift build",
				cwd: "/tmp",
				output: "output",
				status: status,
				exitCode: exitCode,
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
			let shellLabels = descendants(item.view).compactMap
			{
				$0 as? NSTextField
			}
			.filter
			{
				$0.superview?.superview is DesktopSurface
			}
			#expect(shellLabels.contains
			{
				$0.stringValue == expected && $0.alignment == .right &&
					$0.textColor == DesktopTheme.terminalMutedText
			})
			#expect(!shellLabels.contains
			{
				$0.stringValue == "✓ Success"
			})
		}
	}

	@Test func terminalCardRendersInLightAndDarkAppearanceWithScrollEdgeFades() throws
	{
		_ = NSApplication.shared
		let fixture = """
		warning: 'codex-gui': found 1 file(s) which are unhandled
		    /tmp/codex-gui/Sources/CodexGUI/Features/README.md
		[0/1] Planning build
		Building for debugging...
		[0/4] Write swift-version--1AB21518FC5DEDBE.txt
		[2/194] Compiling MermaidLayoutDagre Rank.swift
		[3/195] Compiling SwiftMath MTUnicode.swift
		[617/623] Compiling CodexGUI WorkspaceLifecycleGitRunner.swift
		[618/623] Compiling CodexGUI WorkspaceLifecycleOperations.swift
		[619/623] Compiling CodexGUI main.swift
		[620/623] Compiling CodexGUI resource_bundle_accessor.swift
		[620/622] Linking CodexGUI
		[621/622] Applying CodexGUI
		Build complete! (13.90s)
		"""
		for (name, filename) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")]
		{
			let appearance = try #require(NSAppearance(named: name))
			let item = ConversationActivityCollectionItem()
			let row = ConversationActivityRow(
				id: "build-preview",
				sourceEntryID: "build-preview",
				groupID: "group",
				kind: .command,
				title: "Ran commands",
				command: ConversationCommand(
					command: "swift build",
					cwd: "/tmp/codex-gui",
					output: fixture,
					status: "completed",
					exitCode: 0,
					durationMs: 13900,
					actions: []
				),
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
			item.view.appearance = appearance
			item.view.frame = NSRect(
				origin: .zero,
				size: ConversationActivityCollectionItem.itemSize(
					row: row,
					width: 736
				)
			)
			item.view.layoutSubtreeIfNeeded()
			item.viewDidLayout()
			item.view.layoutSubtreeIfNeeded()
			let scroll = try #require(descendants(item.view).compactMap
			{
				$0 as? NSScrollView
			}
			.first)
			let topFade = try #require(descendants(scroll)
				.first
				{
					$0.identifier?.rawValue == "terminal-top-fade"
				})
			let bottomFade = try #require(descendants(scroll)
				.first
				{
					$0.identifier?.rawValue == "terminal-bottom-fade"
				})
			#expect(topFade.isHidden)
			#expect(!bottomFade.isHidden)
			let document = try #require(scroll.documentView)
			let maximumY = document.frame.height - scroll.contentSize.height
			#expect(maximumY > 0)
			let margin: CGFloat = 64
			let host = TerminalRenderHost(frame: NSRect(
				x: 0,
				y: 0,
				width: item.view.bounds.width + 2 * margin,
				height: item.view.bounds.height
			))
			host.appearance = appearance
			item.view.frame.origin.x = margin
			host.addSubview(item.view)
			for offset in [maximumY / 2, maximumY]
			{
				scroll.contentView.scroll(to: NSPoint(
					x: 0,
					y: offset
				))
				scroll.reflectScrolledClipView(scroll.contentView)
				#expect(!topFade.isHidden)
				#expect(bottomFade.isHidden == (offset == maximumY))
				#expect(topFade.hitTest(NSPoint(
					x: 5,
					y: 5
				)) == nil)
				#expect(bottomFade.hitTest(NSPoint(
					x: 5,
					y: 5
				)) == nil)
				let hostBitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
				appearance.performAsCurrentDrawingAppearance
				{
					host.cacheDisplay(
						in: host.bounds,
						to: hostBitmap
					)
				}
				let scale = CGFloat(hostBitmap.pixelsWide) / host.bounds.width
				for x in [Int(margin * scale / 2), hostBitmap.pixelsWide - Int(margin * scale / 2)]
				{
					for y in 0 ..< hostBitmap.pixelsHigh
					{
						let color = try #require(hostBitmap.colorAt(
							x: x,
							y: y
						)?
							.usingColorSpace(.deviceRGB))
						#expect(color.redComponent > 0.99 && color.greenComponent > 0.99 &&
							color.blueComponent > 0.99 && color.alphaComponent > 0.99)
					}
				}
			}
			let bitmap = try #require(item.view
				.bitmapImageRepForCachingDisplay(in: item.view.bounds))
			appearance.performAsCurrentDrawingAppearance
			{
				item.view.cacheDisplay(
					in: item.view.bounds,
					to: bitmap
				)
			}
			#expect(bitmap.pixelsWide >= 736)
			#expect(bitmap.pixelsHigh >= Int(item.view.bounds.height))
			let background = try #require(bitmap.colorAt(
				x: bitmap.pixelsWide - 5,
				y: bitmap.pixelsHigh / 2
			)?.usingColorSpace(.deviceRGB))
			#expect(background.alphaComponent > 0.9)
			#expect(name == .aqua ? background.redComponent > 0.7 : background.redComponent < 0.3)
			let png = try #require(bitmap.representation(
				using: .png,
				properties: [:]
			))
			#expect(!png.isEmpty)
			if ProcessInfo.processInfo.environment["CODEX_TERMINAL_CAPTURE"] == "1"
			{
				try png.write(to: URL(fileURLWithPath: "/tmp/codex-terminal-\(filename).png"))
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
		let labels = descendants(item.view).compactMap
		{
			$0 as? NSTextField
		}
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
		#expect(!labels.contains
		{
			$0.stringValue == "Exit 3" || $0.textColor == .systemRed
		})
		#expect(output.textColor == DesktopTheme.terminalText)
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

	@Test func collapsedHeaderOmitsFailureBadgeWhileFooterRetainsExitCode()
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
		#expect(!descendants(item.view).compactMap
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

@MainActor
private final class TerminalRenderHost: NSView
{
	override func draw(_ dirtyRect: NSRect)
	{
		NSColor.white.setFill()
		bounds.fill()
	}
}
