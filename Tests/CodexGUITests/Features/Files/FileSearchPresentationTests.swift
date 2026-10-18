import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct FileSearchPresentationTests
{
	@Test func contentRowHighlightsEveryLiteralMatchAndKeepsLocationAtTrailingEdge() throws
	{
		_ = NSApplication.shared
		let result = FileViewerSearchResult(
			location: FileLocation(
				root: "/tmp/project",
				relativePath: "Sources/Long/Nested/Directory/VeryLongFilename.swift"
			),
			lineNumber: 128,
			lineText: "écho ÉCHO ÉCHO [needle]"
		)
		let row = FileSearchContentResultView(
			result: result,
			query: "écho"
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 270,
				height: 28
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		defer
		{
			window.close()
		}
		let host = try #require(window.contentView)
		row.translatesAutoresizingMaskIntoConstraints = false
		host.addSubview(row)
		NSLayoutConstraint.activate([
			row.leadingAnchor.constraint(equalTo: host.leadingAnchor),
			row.trailingAnchor.constraint(equalTo: host.trailingAnchor),
			row.topAnchor.constraint(equalTo: host.topAnchor),
			row.bottomAnchor.constraint(equalTo: host.bottomAnchor),
		])
		host.layoutSubtreeIfNeeded()
		#expect(row.snippetLabel.stringValue == result.lineText)
		#expect(row.locationLabel.stringValue == "VeryLongFilename.swift:128")
		#expect(row.locationLabel.lineBreakMode == .byTruncatingMiddle)
		#expect(row.locationLabel.frame.maxX <= row.bounds.maxX)
		#expect(row.locationLabel.frame.maxX >= row.bounds.maxX - 16)
		#expect(row.snippetLabel.frame.maxX <= row.locationLabel.frame.minX)
		#expect(row.toolTip?.contains(result.location.relativePath) == true)
		let text = row.snippetLabel.attributedStringValue
		for offset in [0, 5]
		{
			#expect(text
				.attribute(
					.backgroundColor,
					at: offset,
					effectiveRange: nil
				) != nil)
		}
		#expect(text.attribute(
			.backgroundColor,
			at: 10,
			effectiveRange: nil
		) == nil)
		#expect(text.attribute(
			.backgroundColor,
			at: 16,
			effectiveRange: nil
		) == nil)
	}

	@Test func distantMatchIsVisibleWithoutAttributingAnEntireLongLine() throws
	{
		_ = NSApplication.shared
		let fullLine = String(
			repeating: "界",
			count: 600
		) + " eR eR after"
		let result = FileViewerSearchResult(
			location: FileLocation(
				root: "/tmp/project",
				relativePath: "large.swift"
			),
			lineNumber: 5,
			lineText: fullLine
		)
		let row = FileSearchContentResultView(
			result: result,
			query: "er"
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 270,
				height: 28
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		defer
		{
			window.close()
		}
		let host = try #require(window.contentView)
		row.translatesAutoresizingMaskIntoConstraints = false
		host.addSubview(row)
		NSLayoutConstraint.activate([
			row.leadingAnchor.constraint(equalTo: host.leadingAnchor),
			row.trailingAnchor.constraint(equalTo: host.trailingAnchor),
			row.topAnchor.constraint(equalTo: host.topAnchor),
			row.bottomAnchor.constraint(equalTo: host.bottomAnchor),
		])
		#expect(row.toolTip?.contains(fullLine) == true)
		#expect(row.accessibilityLabel()?.contains(fullLine) == true)
		for width: CGFloat in [270, 400, 270]
		{
			window.setContentSize(NSSize(
				width: width,
				height: 28
			))
			host.layoutSubtreeIfNeeded()
			row.layoutSubtreeIfNeeded()
			let visible = row.snippetLabel.stringValue
			#expect(visible.hasPrefix("…"))
			#expect(row.snippetLabel.bounds.width >= 80)
			#expect(visible.contains("eR eR"))
			#expect(visible.count < 260)
			let range = (visible as NSString).range(of: "eR")
			let throughMatch = (visible as NSString).substring(to: NSMaxRange(range))
			let font = NSFont.monospacedSystemFont(
				ofSize: 13,
				weight: .regular
			)
			let measured = (throughMatch as NSString).size(withAttributes: [.font: font]).width
			#expect(measured <= row.snippetLabel.bounds.width)
			#expect(row.locationLabel.frame.maxX <= row.bounds.maxX)
			#expect(row.locationLabel.frame.maxX <= row.bounds.maxX)
			#expect(row.locationLabel.frame.maxX >= row.bounds.maxX - 16)
			#expect(row.snippetLabel.attributedStringValue.attribute(
				.backgroundColor,
				at: range.location,
				effectiveRange: nil
			) != nil)
		}
	}

	@Test func contentAndFilenameShareFixedPanelShell() throws
	{
		_ = NSApplication.shared
		for mode: FileSearchPanel.Mode in [.content, .filename]
		{
			let panel = FileSearchPanel(mode: mode)
			let view = panel.view
			let query = try #require(findField(
				"Search file contents",
				in: view
			)
				?? findField(
					"Open file by name",
					in: view
				))
			let scroll = try #require(findView(
				NSScrollView.self,
				in: view
			))
			let status = try #require(findField(
				"Search status",
				in: view
			))
			let escape = try #require(findButton(
				"Close search",
				in: view
			))
			#expect(!query.isBordered)
			#expect(!escape.isHidden)
			for width: CGFloat in [400, 640]
			{
				view.frame = NSRect(
					x: 0,
					y: 0,
					width: width,
					height: 480
				)
				view.layoutSubtreeIfNeeded()
				let queryFrame = query.convert(
					query.bounds,
					to: view
				)
				let statusFrame = status.convert(
					status.bounds,
					to: view
				)
				let escapeFrame = escape.convert(
					escape.bounds,
					to: view
				)
				#expect(queryFrame.minX >= 20)
				#expect(queryFrame.width >= 75)
				#expect(scroll.frame.maxY <= queryFrame.minY)
				#expect(statusFrame.maxY <= scroll.frame.minY)
				if mode == .content
				{
					let mask = try #require(findField(
						"File mask",
						in: view
					))
					let maskFrame = mask.convert(
						mask.bounds,
						to: view
					)
					#expect(queryFrame.maxX <= maskFrame.minX)
					#expect(maskFrame.maxX <= escapeFrame.minX)
					#expect(!mask.isHidden)
				}
				else
				{
					#expect(queryFrame.maxX <= escapeFrame.minX)
					#expect(findField(
						"File mask",
						in: view
					)?.isHidden == true)
				}
			}
		}
	}

	@Test(.timeLimit(.minutes(1)))
	func typingAndAppearanceKeepQueryClearOfAccessoriesAndSelection() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			for mode: FileSearchPanel.Mode in [.content, .filename]
			{
				let parent = NSWindow(
					contentRect: NSRect(
						x: 0,
						y: 0,
						width: 480,
						height: 540
					),
					styleMask: [.titled],
					backing: .buffered,
					defer: false
				)
				parent.isReleasedWhenClosed = false
				let origin = NSTextView(frame: NSRect(
					x: 8,
					y: 8,
					width: 100,
					height: 24
				))
				parent.contentView?.addSubview(origin)
				#expect(parent.makeFirstResponder(origin))
				let panel = FileSearchPanel(mode: mode)
				var chosenCount = 0
				var canceledCount = 0
				panel.onChooseContent =
				{
					_ in chosenCount += 1
				}
				panel.onChooseFilename =
				{
					_ in chosenCount += 1
				}
				panel.onCancelSearch =
				{
					canceledCount += 1
				}
				defer
				{
					panel.dismiss()
					parent.close()
				}
				var state = FileViewerState()
				state.activeRoot = "/tmp/search-presentation"
				panel.render(state)
				panel.present(in: parent)
				let sheet = try #require(parent.attachedSheet)
				#expect(sheet.title == (mode == .content ? "Search Files" : "Quick Open"))
				let queryLabel = mode == .content
					? "Search file contents" : "Open file by name"
				let query = try #require(findField(
					queryLabel,
					in: panel.view
				))
				let editor = try #require(query.currentEditor() as? NSTextView)
				let longQuery = String(
					repeating: "needle",
					count: 24
				)
				editor.insertText(
					longQuery,
					replacementRange: editor.selectedRange()
				)
				query.validateEditing()
				panel.controlTextDidChange(Notification(
					name: NSControl.textDidChangeNotification,
					object: query
				))
				#expect(query.stringValue == longQuery)
				let escape = try #require(findButton(
					"Close search",
					in: panel.view
				))
				let queryFrame = query.convert(
					query.bounds,
					to: panel.view
				)
				let escapeFrame = escape.convert(
					escape.bounds,
					to: panel.view
				)
				#expect(queryFrame.width >= 75)
				#expect(queryFrame.maxX <= escapeFrame.minX)
				if mode == .content
				{
					let mask = try #require(findField(
						"File mask",
						in: panel.view
					))
					let maskFrame = mask.convert(
						mask.bounds,
						to: panel.view
					)
					#expect(queryFrame.maxX <= maskFrame.minX)
				}
				editor.selectAll(nil)
				editor.insertText(
					"needle",
					replacementRange: editor.selectedRange()
				)
				query.validateEditing()
				panel.controlTextDidChange(Notification(
					name: NSControl.textDidChangeNotification,
					object: query
				))
				state.searchRequest = UUID()
				panel.render(state)
				state.searchRequest = nil
				let location = FileLocation(
					root: state.activeRoot!,
					relativePath: "Sources/needle.swift"
				)
				if mode == .content
				{
					state.contentResults = FileViewerSearchPage(
						results: [FileViewerSearchResult(
							location: location,
							lineNumber: 7,
							lineText: "needle needle result"
						)],
						isTruncated: false
					)
				}
				else
				{
					state.filenameResults = FileViewerSearchPage(
						results: [location],
						isTruncated: false
					)
				}
				panel.render(state)
				let table = try #require(findView(
					FileSearchResultsTableView.self,
					in: panel.view
				))
				#expect(table.selectedRow == 0)
				if mode == .content
				{
					let status = try #require(findField(
						"Search status",
						in: panel.view
					))
					#expect(status.stringValue == "1 matching line")
				}
				else
				{
					let status = try #require(findField(
						"Search status",
						in: panel.view
					))
					#expect(status.stringValue == "1 file")
				}
				for appearance: NSAppearance.Name in [.aqua, .darkAqua]
				{
					parent.appearance = NSAppearance(named: appearance)
					panel.view.layoutSubtreeIfNeeded()
					#expect(sheet.appearance?.name == appearance)
					#expect(query.currentEditor() === editor)
					#expect(table.selectedRow == 0)
					let selection = try #require(table.rowView(
						atRow: 0,
						makeIfNecessary: true
					) as? FileSearchResultSelectionRow)
					#expect(selection.isSelected)
					if mode == .content
					{
						let cell = try #require(table.view(
							atColumn: 0,
							row: 0,
							makeIfNecessary: true
						))
						let result = try #require(findView(
							FileSearchContentResultView.self,
							in: cell
						))
						#expect(result.snippetLabel.stringValue == "needle needle result")
						#expect(result.snippetLabel.attributedStringValue.attribute(
							.backgroundColor,
							at: 0,
							effectiveRange: nil
						) != nil)
					}
					if let directory = ProcessInfo.processInfo.environment["FILE_SEARCH_RENDER_DIR"]
					{
						let destination = URL(fileURLWithPath: directory)
						try FileManager.default.createDirectory(
							at: destination,
							withIntermediateDirectories: true
						)
						try AppTestPNGWriter.write(
							panel.view,
							to: destination.appendingPathComponent(
								"\(mode)-\(appearance.rawValue).png"
							)
						)
					}
				}
				editor.selectAll(nil)
				editor.insertText(
					"another query",
					replacementRange: editor.selectedRange()
				)
				query.validateEditing()
				panel.controlTextDidChange(Notification(
					name: NSControl.textDidChangeNotification,
					object: query
				))
				#expect(table.numberOfRows == 0)
				#expect(panel.control(
					query,
					textView: editor,
					doCommandBy: #selector(NSResponder.insertNewline(_:))
				))
				#expect(chosenCount == 0)
				#expect(parent.attachedSheet === sheet)
				state.searchRequest = UUID()
				panel.render(state)
				state.searchRequest = nil
				state.filenameResults = FileViewerSearchPage(
					results: [],
					isTruncated: true
				)
				state.contentResults = FileViewerSearchPage(
					results: [],
					isTruncated: true
				)
				panel.render(state)
				let status = try #require(findField(
					"Search status",
					in: panel.view
				))
				#expect(status.stringValue.contains("incomplete"))
				#expect(sheet.makeFirstResponder(escape))
				sheet.cancelOperation(nil)
				#expect(parent.attachedSheet == nil)
				#expect(parent.firstResponder === origin)
				#expect(canceledCount == 1)
			}
		}
	}

	private func findField(
		_ label: String,
		in view: NSView
	) -> NSTextField?
	{
		if let field = view as? NSTextField, field.accessibilityLabel() == label
		{
			return field
		}
		return view.subviews.lazy.compactMap
		{
			findField(
				label,
				in: $0
			)
		}.first
	}

	private func findView<View: NSView>(
		_ type: View.Type,
		in view: NSView
	) -> View?
	{
		if let found = view as? View
		{
			return found
		}
		return view.subviews.lazy.compactMap
		{
			findView(
				type,
				in: $0
			)
		}.first
	}

	private func findButton(
		_ label: String,
		in view: NSView
	) -> NSButton?
	{
		if let button = view as? NSButton, button.accessibilityLabel() == label
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			findButton(
				label,
				in: $0
			)
		}.first
	}
}
