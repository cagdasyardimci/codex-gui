import AppKit

enum GitDiffLayoutPreference: String, CaseIterable, Sendable
{
	case automatic, unified, split

	static let splitMinimumWidth: CGFloat = 800

	var next: Self
	{
		switch self
		{
		case .automatic: .unified
		case .unified: .split
		case .split: .automatic
		}
	}

	func resolvedMode(viewportWidth: CGFloat) -> GitAdaptiveDiffView.LayoutMode
	{
		switch self
		{
		case .automatic: viewportWidth >= Self.splitMinimumWidth ? .split : .unified
		case .unified: .unified
		case .split: .split
		}
	}
}

/// Selects a source layout from the actual code viewport, independently of window width.
@MainActor
final class GitAdaptiveDiffView: NSView
{
	enum LayoutMode: String, Sendable
	{
		case unified, split
	}

	/// Proposed breakpoint: two source columns of at least 400 points each.
	static let splitMinimumWidth = GitDiffLayoutPreference.splitMinimumWidth
	private(set) var layoutMode = LayoutMode.unified
	var layoutPreference = GitDiffLayoutPreference.automatic
	{
		didSet
		{
			guard oldValue != layoutPreference
			else
			{
				return
			}
			install(layoutPreference.resolvedMode(viewportWidth: bounds.width))
			needsLayout = true
		}
	}
	var wrapsCode = false
	{
		didSet
		{
			guard oldValue != wrapsCode
			else
			{
				return
			}
			unified.wrapsCode = wrapsCode
			splitOld?.wrapsCode = wrapsCode
			splitNew?.wrapsCode = wrapsCode
			if !wrapsCode
			{
				splitOld?.setAdditionalVisualLines([])
				splitNew?.setAdditionalVisualLines([])
			}
			updateContentHeight()
			needsLayout = true
		}
	}
	private let presentation: GitSplitDiffPresentation
	private let path: String
	private var activeContent: NSView?
	private var contentHeight: NSLayoutConstraint?
	private var splitOld: GitUnifiedCodeView?
	private var splitNew: GitUnifiedCodeView?
	private var aligningSplitRows = false
	private lazy var unified: GitUnifiedCodeView =
	{
		let code = GitUnifiedCodeView(
			rows: presentation.unifiedRows,
			path: path
		)
		code.manageHeightFromParent()
		code.wrapsCode = wrapsCode
		code.onContentHeightChange =
		{
			[weak self] in self?.updateContentHeight()
		}
		return code
	}()
	private lazy var split = makeSplitContent()

	init(
		rows: [GitDiffRow],
		path: String
	)
	{
		presentation = GitSplitDiffPresentation(rows: rows)
		self.path = path
		super.init(frame: .zero)
		wantsLayer = true
		layer?.masksToBounds = true
		setAccessibilityLabel("Adaptive source diff for \(path)")
		let height = heightAnchor.constraint(
			equalToConstant: GitUnifiedCodeView
				.contentHeight(rowCount: presentation.unifiedRows.count)
		)
		height.isActive = true
		contentHeight = height
		install(.unified)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func layout()
	{
		super.layout()
		install(layoutPreference.resolvedMode(viewportWidth: bounds.width))
		updateContentHeight()
	}

	private func install(_ mode: LayoutMode)
	{
		guard mode != layoutMode || activeContent == nil
		else
		{
			return
		}
		activeContent?.removeFromSuperview()
		layoutMode = mode
		let content: NSView = mode == .split ? split : unified
		activeContent = content
		AppKitLayout.pin(
			content,
			to: self,
			inset: 0
		)
		setAccessibilityValue(mode == .split
			? "Split old and new source columns" : "Unified source changes")
		updateContentHeight()
	}

	private func updateContentHeight()
	{
		if layoutMode == .split
		{
			synchronizeSplitRows()
		}
		let height: CGFloat
		if layoutMode == .split
		{
			height = max(
				splitOld?.naturalContentHeight ?? 0,
				splitNew?.naturalContentHeight ?? 0
			)
		}
		else
		{
			height = unified.naturalContentHeight
		}
		if let contentHeight, height > 0, contentHeight.constant != height
		{
			contentHeight.constant = height
			needsLayout = true
		}
	}

	private func synchronizeSplitRows()
	{
		guard !aligningSplitRows, let splitOld, let splitNew,
				splitOld.visualLineCounts.count == presentation.pairs.count,
				splitNew.visualLineCounts.count == presentation.pairs.count
		else
		{
			return
		}
		aligningSplitRows = true
		defer
		{
			aligningSplitRows = false
		}
		let oldExtra = zip(
			splitOld.visualLineCounts,
			splitNew.visualLineCounts
		).map
		{
			max(
				0,
				$1 - $0
			)
		}
		let newExtra = zip(
			splitOld.visualLineCounts,
			splitNew.visualLineCounts
		).map
		{
			max(
				0,
				$0 - $1
			)
		}
		splitOld.setAdditionalVisualLines(oldExtra)
		splitNew.setAdditionalVisualLines(newExtra)
	}

	private func makeSplitContent() -> NSView
	{
		let old = makeColumn(
			presentation.oldRows,
			gutterMode: .old
		)
		let new = makeColumn(
			presentation.newRows,
			gutterMode: .new
		)
		splitOld = old
		splitNew = new
		let divider = DesktopSurface(DesktopTheme.paneDivider)
		divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
		let columns = NSStackView(views: [old, divider, new])
		columns.orientation = .horizontal
		columns.alignment = .top
		columns.spacing = 0
		NSLayoutConstraint.activate([
			old.widthAnchor.constraint(equalTo: new.widthAnchor),
			old.heightAnchor.constraint(equalTo: columns.heightAnchor),
			new.heightAnchor.constraint(equalTo: columns.heightAnchor),
			divider.heightAnchor.constraint(equalTo: columns.heightAnchor),
		])
		return columns
	}

	private func makeColumn(
		_ alignedRows: [GitDiffRow?],
		gutterMode: GitUnifiedCodeView.GutterMode
	) -> GitUnifiedCodeView
	{
		var placeholderIndices: Set<Int> = []
		let rows = alignedRows.enumerated().map
		{
			index, row in
			if let row
			{
				return row
			}
			placeholderIndices.insert(index)
			return GitDiffRow(
				id: "split-placeholder:\(gutterMode.rawValue):\(index)",
				kind: .context,
				text: "",
				oldLine: nil,
				newLine: nil
			)
		}
		let code = GitUnifiedCodeView(
			rows: rows,
			path: path,
			gutterMode: gutterMode,
			placeholderIndices: placeholderIndices
		)
		code.manageHeightFromParent()
		code.wrapsCode = wrapsCode
		code.onContentHeightChange =
		{
			[weak self] in self?.updateContentHeight()
		}
		return code
	}
}
