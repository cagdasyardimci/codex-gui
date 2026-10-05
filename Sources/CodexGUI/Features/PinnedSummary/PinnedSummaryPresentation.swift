import Foundation

struct PinnedSummaryPresentation: Equatable
{
	/// Activity categories are presentation rows, distinct from canonical source records.
	struct SourcePreview: Equatable, Identifiable
	{
		let id: String
		let label: String
		let kind: SummarySourceReference.Kind
		let thumbnailPath: String?
		let detailRecordID: String?
		var icon: DesktopIcon? = nil
	}

	let owner: FeaturePresentationOwner
	let contextName: String
	let sections: ContextSummarySections
	let sourcePreviewLimit: Int

	init(
		_ snapshot: ConversationSnapshot,
		ownerIdentity: String? = nil,
		sections: ContextSummarySections = ContextSummarySections(),
		sourcePreviewLimit: Int = 3
	)
	{
		owner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: ownerIdentity
		)
		contextName = snapshot.projectPath.map
		{
			snapshot.projectDisplayNames[$0] ?? URL(fileURLWithPath: $0).lastPathComponent
		} ?? "Workspace unavailable"
		var scopedSections = sections
		if snapshot.projectPath == nil
		{
			scopedSections = ContextSummarySections()
			scopedSections.availableDestinations = []
		}
		self.sections = scopedSections
		self.sourcePreviewLimit = max(
			0,
			sourcePreviewLimit
		)
	}

	var sourcePreviews: [SourcePreview]
	{
		var seenRecords = Set<String>()
		var seenCategories = Set<String>()
		var previews: [SourcePreview] = []
		for source in sections.sources.value ?? []
		{
			guard seenRecords.insert(source.id).inserted
			else
			{
				continue
			}
			let category: String?
			switch source.kind
			{
			case .tool: category = source.categoryLabel ?? "ChatGPT App Tools"
			case .web: category = source.categoryLabel ?? "Web search"
			case .attachment, .folder: category = nil
			}
			if let category
			{
				guard seenCategories.insert(category).inserted
				else
				{
					continue
				}
				previews.append(SourcePreview(
					id: "category:\(category)",
					label: category,
					kind: source.kind,
					thumbnailPath: nil,
					detailRecordID: source.detailRecordID,
					icon: source.icon
				))
			}
			else
			{
				previews.append(SourcePreview(
					id: source.id,
					label: source.label,
					kind: source.kind,
					thumbnailPath: source.thumbnailPath,
					detailRecordID: source.detailRecordID,
					icon: source.icon
				))
			}
		}
		// Apply the configurable limit after grouping, retaining first-occurrence ordering.
		return Array(previews.prefix(sourcePreviewLimit))
	}

	func sourceRequest(for preview: SourcePreview) -> ContextPanelRequest?
	{
		guard sourcePreviews.contains(preview)
		else
		{
			return nil
		}
		switch preview.kind
		{
		case .tool, .web:
			return request(
				.sources,
				recordID: preview.detailRecordID
			)
		case .attachment, .folder:
			guard let recordID = preview.detailRecordID
			else
			{
				return nil
			}
			return request(
				.sources,
				recordID: recordID
			)
		}
	}

	func request(
		_ destination: ContextPanelDestination,
		recordID: String? = nil
	)
		-> ContextPanelRequest?
	{
		guard sections.availableDestinations.contains(destination)
		else
		{
			return nil
		}
		return ContextPanelRequest(
			owner: owner,
			destination: destination,
			recordID: recordID
		)
	}
}

/// Session-local presentation state, separate from chat-management pinning and domain records.
struct PinnedSummaryVisibility
{
	private struct Key: Hashable
	{
		let store: String?
		let project: String?
		let thread: String?
	}
	private var hidden = Set<Key>()

	func isVisible(for owner: FeaturePresentationOwner) -> Bool
	{
		!hidden.contains(key(owner))
	}

	mutating func toggle(for owner: FeaturePresentationOwner)
	{
		let key = key(owner)
		if !hidden.insert(key).inserted
		{
			hidden.remove(key)
		}
	}

	private func key(_ owner: FeaturePresentationOwner) -> Key
	{
		Key(
			store: owner.storeIdentity,
			project: owner.projectPath,
			thread: owner.selectedThreadID
		)
	}
}
