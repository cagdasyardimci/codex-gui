import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct FileSearchPresentationTests
{

	private func referenceResults(root: String) -> [FileViewerSearchResult]
	{
		let rows: [(String, Int, String)] = [
			(
				"GitTurnBaselineSnapshotModels.swift",
				3,
				"struct GitTurnBaselineRecord: Codable, Sendable"
			),
			(
				"GitTurnBaselineSnapshotModels.swift",
				5,
				"var reference: GitTurnBaselineReference"
			),
			(
				"GitTurnBaselineSnapshotModels.swift",
				44,
				"enum GitTurnBaselineReadError: Error"
			),
			(
				"GitPatchSyntax.swift",
				3,
				"fields and the path markers shared by patch consumers."
			),
			(
				"GitPatchSyntax.swift",
				6,
				"typealias HeaderCandidate = (old: String, new: String)"
			),
			(
				"GitPatchSyntax.swift",
				22,
				"path from optional marker metadata."
			),
			(
				"GitPatchSyntax.swift",
				30,
				"static func markerPath("
			),
			(
				"GitPatchSyntax.swift",
				45,
				"Git path tokens; consumers decide how to treat ambiguous synthetic headers."
			),
			(
				"GitPatchSyntax.swift",
				46,
				"static func headerFields(_ header: String) -> (old: String, new: String)?"
			),
			(
				"GitPatchSyntax.swift",
				48,
				"guard header.hasPrefix(\"diff --git \")"
			),
			(
				"GitPatchSyntax.swift",
				53,
				"let fields = String(header.dropFirst(\"diff --git \".count))"
			),
			(
				"GitPatchSyntax.swift",
				70,
				"ible splits lazily; callers apply their own acceptance policy."
			),
			(
				"GitPatchSyntax.swift",
				71,
				"static func unquotedHeaderCandidates(_ header: String) "
					+ "-> AnySequence<HeaderCandidate>"
			),
			(
				"GitPatchSyntax.swift",
				73,
				"guard header.hasPrefix(\"diff --git a/\")"
			),
		]
		return (0 ..< 100).map
		{
			let row = rows[$0 % rows.count]
			return FileViewerSearchResult(
				location: FileLocation(
					root: root,
					relativePath: "Sources/\(row.0)"
				),
				lineNumber: row.1,
				lineText: row.2
			)
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
				parent.prepareForTesting()
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
				#expect(findField(
					"Search status",
					in: panel.view
				) == nil)
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
				#expect(findField(
					"Search status",
					in: panel.view
				) == nil)
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
				#expect(findField(
					"Search status",
					in: panel.view
				) == nil)
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
