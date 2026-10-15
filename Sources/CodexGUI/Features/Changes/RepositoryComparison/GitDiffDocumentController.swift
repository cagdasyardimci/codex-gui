import AppKit

/// Owns the retained comparison document and its presentation-only state.
@MainActor
final class GitDiffDocumentController: NSViewController
{
	var onExpandGap: ((String) -> Void)?
	var onNeedsRender: (() -> Void)?
	private(set) var projectionCache = GitDiffProjectionCache()
	private(set) var layoutPreference = GitDiffLayoutPreference.automatic
	private(set) var wrapsCode = false
	private(set) var collapseAllMode = false
	private var currentState: GitReviewState?
	private var renderedSnapshotID: String?
	private var renderedOwner: FeaturePresentationOwner?
	private var renderedOptions: GitDiffPresentationOptions?
	private var renderedSelectedFileID: String?
	private var layoutOwner: FeaturePresentationOwner?
	private var renderedScope: GitComparisonScope?
	private var collapsedFileIDs: Set<String> = []
	private var collapseSnapshotID: String?
	private var collapseOwner: FeaturePresentationOwner?
	private var fileSections: [Data: GitDiffFileSectionView] = [:]
	private var fileSectionKeys: [Data: GitDiffFileSectionKey] = [:]
	private var diffViews: [GitAdaptiveDiffView] = []
	private let sections = GitChangesSectionsView()
	private(set) var contentScroll = NSScrollView()

	override func loadView()
	{
		sections.orientation = .vertical
		sections.alignment = .leading
		sections.spacing = 0
		sections.translatesAutoresizingMaskIntoConstraints = false
		contentScroll = AppKitLayout.scrollableContent(
			sections,
			inset: 0
		)
		contentScroll.hasVerticalScroller = true
		contentScroll.hasHorizontalScroller = false
		contentScroll.autohidesScrollers = true
		contentScroll.drawsBackground = false
		sections.widthAnchor.constraint(equalTo: contentScroll.contentView.widthAnchor)
			.isActive = true
		view = contentScroll
	}

	func updateLayout(for state: GitReviewState)
	{
		if layoutOwner != state.owner || !state.isOpen
		{
			layoutOwner = state.owner
			layoutPreference = .automatic
			applyLayoutPreference()
		}
		if state.scope == .lastTurn, renderedScope != .lastTurn
		{
			layoutPreference = .unified
			applyLayoutPreference()
		}
		renderedScope = state.isOpen ? state.scope : nil
	}

	func switchLayout()
	{
		layoutPreference = layoutPreference.next
		applyLayoutPreference()
	}

	private func applyLayoutPreference()
	{
		for diff in diffViews
		{
			diff.layoutPreference = layoutPreference
		}
		view.needsLayout = true
	}

	func toggleWordWrap()
	{
		wrapsCode.toggle()
		for diff in diffViews
		{
			diff.wrapsCode = wrapsCode
		}
	}

	func toggleAllDiffs()
	{
		guard let snapshot = currentState?.snapshot
		else
		{
			return
		}
		collapseAllMode.toggle()
		collapsedFileIDs = collapseAllMode ? Set(snapshot.files.map(\.id)) : []
		invalidateSections()
	}

	func render(
		state: GitReviewState,
		presentation: GitDiffPresentation?,
		selectedFileID: String?,
		usesSingleFile: Bool
	)
	{
		_ = view
		currentState = state
		guard let presentation
		else
		{
			projectionCache.clear()
			collapsedFileIDs.removeAll()
			collapseAllMode = false
			collapseSnapshotID = nil
			collapseOwner = nil
			removeSections()
			return
		}
		let snapshot = presentation.snapshot
		if collapseSnapshotID != snapshot.id || collapseOwner != state.owner
		{
			collapsedFileIDs.removeAll()
			collapseAllMode = false
			collapseSnapshotID = snapshot.id
			collapseOwner = state.owner
		}
		projectionCache.prepare(for: presentation)
		updateDiffSections(
			presentation: presentation,
			selectedFileID: selectedFileID,
			usesSingleFile: usesSingleFile
		)
	}

	private func invalidateSections()
	{
		renderedOptions = nil
		onNeedsRender?()
	}

	func scrollToFile(_ id: String)
	{
		guard let section = fileSections[Data(id.utf8)],
				let document = contentScroll.documentView
		else
		{
			return
		}
		contentScroll.layoutSubtreeIfNeeded()
		document.layoutSubtreeIfNeeded()
		let sectionRect = section.convert(
			section.bounds,
			to: document
		)
		let clip = contentScroll.contentView
		let maximumY = max(
			0,
			document.bounds.height - clip.bounds.height
		)
		clip.scroll(to: NSPoint(
			x: clip.bounds.minX,
			y: min(
				maximumY,
				max(
					0,
					sectionRect.minY
				)
			)
		))
		contentScroll.reflectScrolledClipView(clip)
		section.setAccessibilityLabel("Selected changed file: \(id)")
	}
	private func updateDiffSections(
		presentation: GitDiffPresentation,
		selectedFileID displayedFileID: String?,
		usesSingleFile: Bool
	)
	{
		let snapshot = presentation.snapshot
		let needsSectionUpdate = renderedSnapshotID != snapshot.id
			|| renderedOptions != presentation.options
			|| renderedSelectedFileID != displayedFileID || renderedOwner != snapshot.request.owner
		guard needsSectionUpdate
		else
		{
			return
		}
		let origin = contentScroll.contentView.bounds.origin
		let changesDisplayedFile = renderedSnapshotID != snapshot.id
			|| renderedOwner != snapshot.request.owner
			|| renderedSelectedFileID != displayedFileID
		let files = usesSingleFile
			? snapshot.files.filter
			{
				$0.id == displayedFileID
			} : snapshot.files
		reconcileFileSections(
			files,
			presentation: presentation
		)

		renderedSnapshotID = snapshot.id
		renderedOwner = snapshot.request.owner
		renderedOptions = presentation.options
		renderedSelectedFileID = displayedFileID
		sections.layoutSubtreeIfNeeded()
		contentScroll.contentView
			.scroll(to: usesSingleFile && changesDisplayedFile ? .zero : origin)
		contentScroll.reflectScrolledClipView(contentScroll.contentView)
	}

	private func reconcileFileSections(
		_ files: [GitComparisonFile],
		presentation: GitDiffPresentation
	)
	{
		var nextKeys: [Data: GitDiffFileSectionKey] = [:]
		for file in files
		{
			nextKeys[Data(file.id.utf8)] = GitDiffFileSectionKey(
				file: file,
				presentation: presentation,
				isCollapsed: collapsedFileIDs.contains(file.id)
			)
		}
		for (id, section) in fileSections where fileSectionKeys[id] != nextKeys[id]
		{
			sections.removeArrangedSubview(section)
			section.removeFromSuperview()
			fileSections.removeValue(forKey: id)
		}

		for (index, file) in files.enumerated()
		{
			let fileIdentity = Data(file.id.utf8)
			if let section = fileSections[fileIdentity]
			{
				if !sections.arrangedSubviews.indices.contains(index)
					|| sections.arrangedSubviews[index] !== section
				{
					sections.removeArrangedSubview(section)
					sections.insertArrangedSubview(
						section,
						at: index
					)
				}
				continue
			}
			let section = makeFileSection(
				file,
				presentation: presentation
			)
			sections.insertArrangedSubview(
				section,
				at: index
			)
			section.widthAnchor.constraint(equalTo: sections.widthAnchor).isActive = true
			fileSections[fileIdentity] = section
		}
		fileSectionKeys = nextKeys
		diffViews = files.flatMap
		{
			fileSections[Data($0.id.utf8)]?.diffViews ?? []
		}
	}

	private func makeFileSection(
		_ file: GitComparisonFile,
		presentation: GitDiffPresentation
	) -> GitDiffFileSectionView
	{
		let isCollapsed = collapsedFileIDs.contains(file.id)
		let rows = isCollapsed ? nil : projectionCache.file(
			file,
			presentation: presentation
		).rows
		return GitDiffFileSectionView(
			file: file,
			rows: rows,
			isCollapsed: isCollapsed,
			layoutPreference: layoutPreference,
			wrapsCode: wrapsCode,
			onToggleFileDiff:
			{
				[weak self] button in self?.toggleFileDiff(button)
			},
			onExpandGap:
			{
				[weak self] button in self?.expandGap(button)
			},
			onRichPreview:
			{
				[weak self] button in
				self?.showRichPreview(
					file: file,
					snapshot: presentation.snapshot,
					button: button
				)
			}
		)
	}

	private func showRichPreview(
		file: GitComparisonFile,
		snapshot: GitComparisonSnapshot,
		button: NSButton
	)
	{
		guard currentState?.isOpen == true, currentState?.snapshot?.id == snapshot.id,
				currentState?.owner == snapshot.request.owner,
				let kind = GitRichPreviewKind(path: file.path),
				GitRichPreviewContent.blobID(for: file) != nil
		else
		{
			return
		}
		if collapsedFileIDs.contains(file.id)
		{
			toggleFileDiff(button)
		}
		fileSections[Data(file.id.utf8)]?.toggleRichPreview
		{
			GitRichPreviewView(kind: kind)
			{
				try await GitRichPreviewContent.read(
					file: file,
					snapshot: snapshot
				)
			}
		}
	}

	private func removeSections()
	{
		diffViews.removeAll()
		for section in sections.arrangedSubviews
		{
			sections.removeArrangedSubview(section)
			section.removeFromSuperview()
		}
		fileSections = [:]
		fileSectionKeys = [:]
		renderedSnapshotID = nil
		renderedOwner = nil
		renderedOptions = nil
		renderedSelectedFileID = nil
	}

	private func expandGap(_ sender: NSButton)
	{
		if let id = sender.identifier?.rawValue
		{
			onExpandGap?(id)
		}
	}

	private func toggleFileDiff(_ sender: NSButton)
	{
		guard let id = sender.identifier?.rawValue,
				currentState?.snapshot?.files.contains(where:
				{
					$0.id == id
				}) == true
		else
		{
			return
		}
		if !collapsedFileIDs.insert(id).inserted
		{
			collapsedFileIDs.remove(id)
		}
		invalidateSections()
	}
}

@MainActor
private final class GitChangesSectionsView: NSStackView
{
	override var isFlipped: Bool
	{
		true
	}
}
