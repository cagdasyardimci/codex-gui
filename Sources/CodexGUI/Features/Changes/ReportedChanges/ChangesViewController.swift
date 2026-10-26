import AppKit

@MainActor
final class ChangesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate
{
	var onSelectReviewTurn: ((String) -> Void)?
	var onSetReviewed: ((Bool, ReviewReference) -> Void)?
	var onPrepareChangeRequest: ((ReviewRequestKind, ReviewReference) -> Void)?

	private let turnButton = DesktopPopupButton()
	private let originLabel = NSTextField(wrappingLabelWithString: "")
	let filesTable = NSTableView()
	private let filesScrollView = NSScrollView()
	private let emptySpace = NSView()
	private var reviewRow: NSStackView?
	let sectionButton = DesktopPopupButton()
	private let reviewedButton = NSButton(
		checkboxWithTitle: "Reviewed",
		target: nil,
		action: nil
	)
	private let actionsButton = DesktopPopupButton()
	let diffTextView = NSTextView()
	private let diffScrollView = NSScrollView()
	let openButton = DesktopStyledButton(
		title: "Open",
		target: nil,
		action: nil
	)
	let editorStatus = NSTextField(wrappingLabelWithString: "")
	typealias EditorOperation = @MainActor (
		String,
		URL,
		String
	) async throws -> String?
	private let openFile: EditorOperation
	var editorSelection: EditorSelection?
	var editorSelectionGeneration = 0
	var pendingEditorRequest: UUID?
	private(set) var editorHandoffTask: Task<Void, Never>?

	struct EditorSelection: Equatable
	{
		let projectPath: String?
		let owner: FeaturePresentationOwner?
		let threadID: String?
		let turnID: String?
		let filePath: String?
		let hunkID: String?
		let contentIdentity: String
	}

	init(openFile: EditorOperation? = nil)
	{
		let handoff = EditorHandoff()
		self.openFile =
			openFile ??
			{
				path, project, diff in
				try await handoff.open(
					path: path,
					project: project,
					diff: diff
				)
			}
		super.init(
			nibName: nil,
			bundle: nil
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	var presentationOwner: FeaturePresentationOwner?
	var projectPath: String?
	var reviewTurns: [ReviewTurn] = []
	var selectedReview: ReviewTurn?
	private var reviewedReferences: Set<ReviewReference> = []
	var selectedFilePath: String?
	var selectedHunkID: String?
	private var legacyFiles: [ChangeFile] = []
	var legacyDiff = ""
	var renderedKey: ReviewPresentation.Key?
	private var updatingFileSelection = false

	override func loadView()
	{
		configureTurnSelection()
		configureFilesTable()
		configureSectionSelection()
		configureReviewActions()
		configureDiff()
		configureEditor()
		for control in [turnButton, sectionButton, actionsButton]
		{
			AppKitLayout.compressHorizontally(control)
		}
		originLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)

		configureFileListScrolling()
		configureDiffHeight()

		view = makeReviewLayout()
	}

	private func configureFileListScrolling()
	{
		filesScrollView.documentView = filesTable
		filesScrollView.hasVerticalScroller = true
		filesScrollView.autohidesScrollers = true
		filesScrollView.drawsBackground = false
		let preferredFilesHeight = filesScrollView.heightAnchor.constraint(equalToConstant: 88)
		preferredFilesHeight.priority = .defaultHigh
		preferredFilesHeight.isActive = true
		filesScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
	}

	private func configureDiffHeight()
	{
		diffScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
		let preferredContentHeight = diffScrollView.heightAnchor.constraint(equalToConstant: 110)
		preferredContentHeight.priority = .defaultLow
		preferredContentHeight.isActive = true
		diffScrollView.setContentHuggingPriority(
			.defaultLow,
			for: .vertical
		)
	}

	private func makeReviewLayout() -> NSView
	{
		let reviewRow = makeReviewActionsRow()
		let summary = group([turnButton, originLabel, filesScrollView])
		let details = group([
			sectionButton,
			reviewRow,
			diffScrollView,
			openButton,
			editorStatus,
		])
		emptySpace.setContentHuggingPriority(
			NSLayoutConstraint.Priority(1),
			for: .vertical
		)
		emptySpace.heightAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
		let stack = AppKitLayout.verticalStack(
			[summary, details, emptySpace],
			spacing: 10
		)
		summary.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		details.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		let scrollView = AppKitLayout.scrollableContent(
			stack,
			inset: 0
		)
		scrollView.drawsBackground = false
		return scrollView
	}

	private func makeReviewActionsRow() -> NSStackView
	{
		let reviewRow = AppKitLayout.horizontalStack(
			[reviewedButton, actionsButton],
			spacing: 4
		)
		self.reviewRow = reviewRow
		reviewedButton.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		reviewedButton.controlSize = .small
		reviewedButton.font = .systemFont(ofSize: 11)
		return reviewRow
	}

	private func group(_ controls: [NSView]) -> NSView
	{
		let surface = NSView()
		let stack = AppKitLayout.verticalStack(
			controls,
			spacing: 8
		)
		AppKitLayout.pin(
			stack,
			to: surface,
			inset: 0
		)
		for control in controls
		{
			control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		return surface
	}

	func render(_ snapshot: ConversationSnapshot)
	{
		render(ReviewPresentation(snapshot))
	}

	func render(_ snapshot: ReviewPresentation)
	{
		_ = view
		let review = snapshot.selectedReview
		let key = snapshot.key
		guard renderedKey != key
		else
		{
			return
		}

		let previousTurnID = selectedReview?.turnID
		let previousThreadID = selectedReview?.threadID
		let previousProjectPath = projectPath
		let previousOwner = presentationOwner
		let previousFilePath = selectedFilePath
		let previousHunkID = selectedHunkID
		projectPath = snapshot.projectPath
		presentationOwner = snapshot.key.owner
		reviewTurns = snapshot.reviewTurns
		selectedReview = review
		reviewedReferences = snapshot.reviewedReferences
		legacyFiles = snapshot.changedFiles
		legacyDiff = snapshot.diff
		renderedKey = key

		renderTurns(selectedID: snapshot.selectedReviewTurnID)
		renderOrigin(selectedThreadID: snapshot.selectedThreadID)
		updatingFileSelection = true
		filesTable.reloadData()
		let hasFiles = numberOfRows(in: filesTable) > 0
		filesScrollView.isHidden = !hasFiles
		sectionButton.isHidden = !hasFiles
		reviewRow?.isHidden = !hasFiles
		openButton.isHidden = !hasFiles
		emptySpace.isHidden = hasFiles || !(review?.validations.isEmpty ?? true)
		let sameTurn =
			previousProjectPath == snapshot.projectPath
				&& previousOwner == snapshot.key.owner
				&& previousTurnID == review?.turnID && previousThreadID == review?.threadID
		let filePath = sameTurn ? previousFilePath : nil
		let selectedIndex =
			filePath.flatMap
				{
					path in
					(0 ..< numberOfRows(in: filesTable))
						.first(where:
							{
								displayedPath(at: $0) == path
							})
				} ?? (numberOfRows(in: filesTable) > 0 ? 0 : nil)
		if let selectedIndex
		{
			filesTable.selectRowIndexes(
				IndexSet(integer: selectedIndex),
				byExtendingSelection: false
			)
		}
		else
		{
			filesTable.deselectAll(nil)
		}
		if sameTurn && previousFilePath == selectedFilePath
		{
			selectedHunkID = previousHunkID
		}
		updatingFileSelection = false
		updateSelectedFile(preserveHunk: sameTurn)
	}

	func numberOfRows(in tableView: NSTableView) -> Int
	{
		if let selectedReview
		{
			return selectedReview.files.count
		}
		return reviewTurns.isEmpty ? legacyFiles.count : 0
	}

	func tableView(
		_ tableView: NSTableView,
		viewFor tableColumn: NSTableColumn?,
		row: Int
	) -> NSView?
	{
		guard row >= 0, row < numberOfRows(in: tableView)
		else
		{
			return nil
		}
		let identifier = NSUserInterfaceItemIdentifier("changedFile")
		let cell =
			tableView.makeView(
				withIdentifier: identifier,
				owner: self
			) as? NSTableCellView
			?? NSTableCellView()
		cell.identifier = identifier
		if cell.textField == nil
		{
			let label = NSTextField(labelWithString: "")
			label.font = .systemFont(ofSize: 12)
			label.lineBreakMode = .byTruncatingMiddle
			cell.addSubview(label)
			label.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				label.leadingAnchor.constraint(
					equalTo: cell.leadingAnchor,
					constant: 8
				),
				label.trailingAnchor.constraint(
					equalTo: cell.trailingAnchor,
					constant: -8
				),
				label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			])
			cell.textField = label
		}

		if let review = selectedReview, review.files.indices.contains(row)
		{
			let file = review.files[row]
			let reference = ReviewReference(
				threadID: review.threadID,
				turnID: review.turnID,
				file: file
			)
			let marker = reviewedReferences.contains(reference) ? "✓  " : ""
			cell.textField?.stringValue = "\(marker)\(file.kind.title)  \(file.displayName)"
			cell.textField?.toolTip = file.displayName
			cell.setAccessibilityLabel(
				"\(reviewedReferences.contains(reference) ? "Reviewed, " : "")"
					+ "\(file.kind.title) file \(file.displayName)"
			)
		}
		else if reviewTurns.isEmpty
		{
			let file = legacyFiles[row]
			cell.textField?.stringValue = "\(file.status)  \(file.path)"
			cell.textField?.toolTip = file.path
			cell.setAccessibilityLabel("\(file.status) file \(file.path)")
		}
		else
		{
			return nil
		}
		return cell
	}

	func tableViewSelectionDidChange(_ notification: Notification)
	{
		guard !updatingFileSelection
		else
		{
			return
		}
		updateSelectedFile(preserveHunk: false)
	}

	private func configureTurnSelection()
	{
		turnButton.target = self
		turnButton.action = #selector(selectTurn)
		turnButton.setAccessibilityLabel("Review turn")

		originLabel.textColor = .secondaryLabelColor
		originLabel.font = .systemFont(ofSize: 11)
		originLabel.setAccessibilityLabel("Source thread and turn of reported changes")
	}

	private func configureFilesTable()
	{
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("changedFiles"))
		column.title = "Changed files"
		filesTable.addTableColumn(column)
		filesTable.headerView = nil
		filesTable.rowHeight = 28
		filesTable.backgroundColor = .clear
		filesTable.selectionHighlightStyle = .regular
		filesTable.style = .plain
		filesTable.delegate = self
		filesTable.dataSource = self
		filesTable.setAccessibilityLabel("Files changed in the reviewed turn")
	}

	private func configureSectionSelection()
	{
		sectionButton.target = self
		sectionButton.action = #selector(selectSection)
		sectionButton.setAccessibilityLabel("Change section in selected file")

	}

	private func configureReviewActions()
	{
		reviewedButton.target = self
		reviewedButton.action = #selector(toggleReviewed)
		reviewedButton.setAccessibilityLabel("Mark selected file or section reviewed")
		actionsButton.pullsDown = true
		actionsButton.addItem(withTitle: "Actions…")
		actionsButton.addItem(withTitle: "Ask about this change")
		actionsButton.addItem(withTitle: "Request revision")
		actionsButton.target = self
		actionsButton.action = #selector(prepareChangeRequest)
		actionsButton.setAccessibilityLabel("Ask about or request revision of selected change")
		actionsButton.isEnabled = false

	}

	private func configureDiff()
	{
		diffTextView.isEditable = false
		diffTextView.isSelectable = true
		diffTextView.isVerticallyResizable = true
		diffTextView.isHorizontallyResizable = false
		diffTextView.autoresizingMask = [.width]
		diffTextView.minSize = .zero
		diffTextView.maxSize = NSSize(
			width: CGFloat.greatestFiniteMagnitude,
			height: CGFloat.greatestFiniteMagnitude
		)
		diffTextView.textContainer?.containerSize = NSSize(
			width: 200,
			height: CGFloat.greatestFiniteMagnitude
		)
		diffTextView.textContainer?.widthTracksTextView = true
		diffTextView.font = .monospacedSystemFont(
			ofSize: 11,
			weight: .regular
		)
		diffTextView.textContainerInset = NSSize(
			width: 8,
			height: 8
		)
		diffTextView.drawsBackground = false
		diffTextView.setAccessibilityLabel("Reported diff for selected file or section")
		diffScrollView.documentView = diffTextView
		diffScrollView.hasVerticalScroller = true
		diffScrollView.hasHorizontalScroller = false
		diffScrollView.autohidesScrollers = true
		diffScrollView.drawsBackground = false
	}

	private func configureEditor()
	{
		openButton.target = self
		openButton.action = #selector(openSelectedFile)
		openButton.isEnabled = false
		openButton.setAccessibilityLabel("Open selected changed file in editor")
		openButton.toolTip = "Open selected file in preferred editor"
		openButton.symbol = .externalLink
		editorStatus.textColor = .secondaryLabelColor
		editorStatus.font = .systemFont(ofSize: 11)
		editorStatus.setAccessibilityLabel("Editor handoff status")
		editorStatus.isHidden = true
	}

	private func renderTurns(selectedID: String?)
	{
		turnButton.removeAllItems()
		if reviewTurns.isEmpty
		{
			turnButton.addItem(withTitle: "Current turn")
			turnButton.isEnabled = false
			return
		}
		turnButton.isEnabled = true
		for (index, turn) in reviewTurns.enumerated()
		{
			let count = turn.files.count
			turnButton
				.addItem(withTitle: "Turn \(index + 1) · \(count) file\(count == 1 ? "" : "s")")
			turnButton.lastItem?.representedObject = turn.turnID
			turnButton.lastItem?.toolTip = "Thread \(turn.threadID), turn \(turn.turnID)"
		}
		let index =
			reviewTurns.firstIndex(where:
				{
					$0.turnID == selectedID
				})
			?? reviewTurns.count - 1
		turnButton.selectItem(at: index)
	}

	private func renderOrigin(selectedThreadID: String?)
	{
		if let review = selectedReview
		{
			originLabel.stringValue =
				review.hasUnknownEarlierHistory
					? "Reported turn \(review.turnID) · earlier history not loaded"
					: "Reported turn \(review.turnID) · current file may differ"
			originLabel.toolTip =
				"Codex-reported changes from thread \(review.threadID), turn \(review.turnID). "
					+ "This historical diff may not match the current file."
					+ (review.hasUnknownEarlierHistory ? " Earlier turns are not loaded." : "")
		}
		else if reviewTurns.isEmpty
		{
			originLabel.stringValue =
				selectedThreadID == nil
					? "Select a conversation to review changes"
					: "Codex-reported changes for the current turn"
			originLabel.toolTip = nil
		}
		else
		{
			originLabel.stringValue = "Select a reported turn to review changes"
			originLabel.toolTip = nil
		}
	}

	var selectedFile: ReviewFile?
	{
		guard let review = selectedReview, review.files.indices.contains(filesTable.selectedRow)
		else
		{
			return nil
		}
		return review.files[filesTable.selectedRow]
	}

	var selectedHunk: ReviewHunk?
	{
		selectedFile?.hunks.first(where:
			{
				$0.id == selectedHunkID
			})
	}

	private var selectedReference: ReviewReference?
	{
		guard let review = selectedReview, let file = selectedFile
		else
		{
			return nil
		}
		return ReviewReference(
			threadID: review.threadID,
			turnID: review.turnID,
			file: file,
			hunk: selectedHunk
		)
	}

	func displayedPath(at row: Int) -> String?
	{
		if let review = selectedReview, review.files.indices.contains(row)
		{
			return review.files[row].path
		}
		return reviewTurns.isEmpty && legacyFiles.indices.contains(row) ? legacyFiles[row]
			.path : nil
	}

	var canOpenSelectedFile: Bool
	{
		guard projectPath != nil, selectedFilePath != nil
		else
		{
			return false
		}
		return selectedFile?.kind != .deleted
	}

	func updateReviewActions()
	{
		let reference = selectedReference
		reviewedButton.isEnabled = reference != nil
		reviewedButton.state = reference
			.map
			{
				reviewedReferences.contains($0)
			} == true ? .on : .off
		reviewedButton.title = selectedHunk == nil ? "Reviewed file" : "Reviewed section"
		actionsButton.isEnabled = reference != nil
	}

	@objc private func selectTurn()
	{
		guard let id = turnButton.selectedItem?.representedObject as? String
		else
		{
			return
		}
		onSelectReviewTurn?(id)
	}

	@objc private func selectSection()
	{
		let value = sectionButton.selectedItem?.representedObject as? String
		selectedHunkID = value?.isEmpty == true ? nil : value
		updateDiff()
		updateReviewActions()
	}

	@objc private func toggleReviewed()
	{
		guard let reference = selectedReference
		else
		{
			return
		}
		onSetReviewed?(reviewedButton.state == .on, reference)
	}

	@objc private func prepareChangeRequest()
	{
		guard let reference = selectedReference
		else
		{
			return
		}
		let kind: ReviewRequestKind
		switch actionsButton.indexOfSelectedItem
		{
		case 1: kind = .ask
		case 2: kind = .revision
		default: return
		}
		actionsButton.selectItem(at: 0)
		onPrepareChangeRequest?(kind, reference)
	}

	@objc private func openSelectedFile()
	{
		guard let projectPath, let path = selectedFilePath, canOpenSelectedFile,
				pendingEditorRequest == nil
		else
		{
			return
		}
		let selectedDiff =
			selectedHunk?.text ?? selectedFile?.diff
				?? GitDiffParser.selectedDiff(
					for: path,
					in: legacyDiff
				)
		let generation = editorSelectionGeneration
		let request = UUID()
		pendingEditorRequest = request
		openButton.isEnabled = false
		editorHandoffTask = Task
		{
			[weak self, openFile] in
			let message: String
			do
			{
				let note = try await openFile(
					path,
					URL(fileURLWithPath: projectPath),
					selectedDiff
				)
				message = note ?? "Opened in editor."
			}
			catch
			{
				message = error.localizedDescription
			}
			guard let self, self.editorSelectionGeneration == generation,
					self.pendingEditorRequest == request
			else
			{
				return
			}
			self.pendingEditorRequest = nil
			self.editorStatus.stringValue = message
			self.editorStatus.isHidden = false
			self.openButton.isEnabled = self.canOpenSelectedFile
		}
	}

}

extension ReviewFileKind
{
	fileprivate var title: String
	{
		switch self
		{
		case .added: "Added"
		case .modified: "Modified"
		case .deleted: "Deleted"
		case .renamed: "Renamed"
		case .binary: "Binary"
		case .unsupported: "Unsupported"
		}
	}
}
