import AppKit

/// Selected-task edit totals; previous-turn counts can bridge missing active-turn reports.
struct ConversationTurnChangeSummary: Equatable, Sendable
{
	let fileCount: Int
	let additions: Int
	let deletions: Int
	let failure: GitComparisonFailure?
	let usesReportedEditFallback: Bool
	var usesPreviousTurn: Bool = false
	let isLoading: Bool
	static let loading = ConversationTurnChangeSummary()

	private init()
	{
		fileCount = 0
		additions = 0
		deletions = 0
		failure = nil
		usesReportedEditFallback = false
		isLoading = true
	}

	init?(comparison: GitComparisonSnapshot)
	{
		guard !comparison.files.isEmpty
		else
		{
			return nil
		}
		fileCount = comparison.files.count
		additions = comparison.additions
		deletions = comparison.deletions
		failure = nil
		usesReportedEditFallback = comparison.usesReportedEditFallback
		isLoading = false
	}

	init(
		unavailable failure: GitComparisonFailure,
		request: GitComparisonRequest? = nil
	)
	{
		let changes = ReportedRepositoryFileChanges.filter(
			request?.reportedChanges ?? [],
			repositoryRoot: request?.repositoryRoot
		)
		fileCount = Set(changes.map
		{
			Data(($0.movePath ?? $0.path).utf8)
		}).count
		let counts = changes.map
		{
			GitDiffParser.hunks(in: ConversationNetFileChanges.normalizedDiff($0)
				.components(separatedBy: "\n"))
		}
		additions = counts.reduce(0)
		{
			$0 + $1.additions
		}
		deletions = counts.reduce(0)
		{
			$0 + $1.deletions
		}
		self.failure = failure
		usesReportedEditFallback = !changes.isEmpty
		isLoading = false
	}

	init?(
		result: GitComparisonResult,
		usesPreviousTurn: Bool = false,
		request: GitComparisonRequest? = nil
	)
	{
		switch result
		{
		case .snapshot(let comparison): self.init(comparison: comparison)
		case .unavailable(let failure): self.init(
				unavailable: failure,
				request: request
			)
		}
		self.usesPreviousTurn = usesPreviousTurn
	}

	init?(_ snapshot: ConversationSnapshot)
	{
		guard let request = snapshot
			.runningGitReviewRequest(owner: FeaturePresentationOwner(snapshot))
		else
		{
			return nil
		}
		self.init(
			result: GitReportedTurnComparison.compare(request),
			usesPreviousTurn: request.lastTurnID != snapshot.activeTurnID,
			request: request
		)
	}
}

@MainActor
final class TurnChangeSummaryButton: NSButton
{
	private var summary: ConversationTurnChangeSummary?

	init()
	{
		super.init(frame: .zero)
		bezelStyle = .inline
		isBordered = false
		wantsLayer = true
		layer?.cornerRadius = 17
		layer?.borderWidth = 1
		updateColors()
		setAccessibilityLabel("Turn file changes")
	}

	required init?(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}

	override var intrinsicContentSize: NSSize
	{
		let measured = super.intrinsicContentSize
		return NSSize(
			width: measured.width + 24,
			height: 34
		)
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		updateColors()
	}

	func render(_ summary: ConversationTurnChangeSummary?)
	{
		self.summary = summary
		guard let summary
		else
		{
			isHidden = true
			return
		}
		let fileText = "\(summary.fileCount) \(summary.fileCount == 1 ? "file" : "files") changed"
		updateColors()
		let description: String
		if summary.isLoading
		{
			description = "Loading turn changes"
		}
		else
		{
			description = "\(fileText), \(summary.additions) additions, "
				+ "\(summary.deletions) deletions."
		}
		let previousNote = summary.usesPreviousTurn
			? "Previous editing turn; this active turn has no available edit reports yet. " : ""
		let fallbackNote = previousNote + (summary.usesReportedEditFallback
			? GitReportedTurnComparison.fallbackMessage + " " : "")
		setAccessibilityLabel(description + " " + fallbackNote + "View changes")
		toolTip = fallbackNote + GitReportedTurnComparison.coverageMessage
		invalidateIntrinsicContentSize()
		isHidden = false
	}

	private func updateColors()
	{
		layer?.backgroundColor = DesktopTheme.resolvedCGColor(
			DesktopTheme.canvas,
			for: self
		)
		layer?.borderColor = DesktopTheme.resolvedCGColor(
			DesktopTheme.border,
			for: self
		)
		guard let summary
		else
		{
			return
		}
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			let fileText: String
			if summary.isLoading
			{
				fileText = "Loading turn changes"
			}
			else
			{
				fileText = "\(summary.fileCount) "
					+ "\(summary.fileCount == 1 ? "file" : "files") changed"
			}
			let title = NSMutableAttributedString(
				string: fileText,
				attributes: [
					.font: NSFont.systemFont(ofSize: 13),
					.foregroundColor: NSColor.secondaryLabelColor.usingColorSpace(.deviceRGB)
						?? NSColor.secondaryLabelColor,
				]
			)
			let counts = !summary.isLoading
				? [(" +\(summary.additions)", NSColor.systemGreen),
					(" -\(summary.deletions)", NSColor.systemRed)] : []
			for (text, color) in counts
			{
				title.append(NSAttributedString(
					string: text,
					attributes: [
						.font: NSFont.systemFont(ofSize: 13),
						.foregroundColor: color.usingColorSpace(.deviceRGB) ?? color,
					]
				))
			}
			attributedTitle = title
		}
		needsDisplay = true
	}
}
