import Foundation

/// A projection of explicit references and structured activity in loaded conversation entries.
struct ConversationLocalSources
{
	struct Invocation: Equatable, Identifiable
	{
		let id: String
		let summary: String
		let detail: String
		let status: String
		var operation: String = ""
		var resultText: String = ""
		var resultLanguage: String = ""
		var isError: Bool = false

		static func == (lhs: Self, rhs: Self) -> Bool
		{
			// Result and raw-detail snapshots must invalidate when their recorded bytes change.
			lhs.id == rhs.id && lhs.summary == rhs.summary
				&& lhs.detail.utf8.elementsEqual(rhs.detail.utf8) && lhs.status == rhs.status
				&& lhs.operation == rhs.operation
				&& lhs.resultText.utf8.elementsEqual(rhs.resultText.utf8)
				&& lhs.resultLanguage == rhs.resultLanguage && lhs.isError == rhs.isError
		}
	}

	enum Kind: String, Equatable
	{
		case image, file, folder, audio, pdf, page, tool, web
	}

	struct Record: Equatable, Identifiable
	{
		typealias Kind = ConversationLocalSources.Kind
		let id: String
		let name: String
		let path: String
		var kind: Kind = .image
		var association: String = "Attached to the conversation"
		var invocations: [Invocation] = []
		var isInlineImage: Bool
		{
			kind == .image && InlineImageData.isDataURL(path)
		}
		var displayPath: String
		{
			isInlineImage ? "Inline image" : path
		}
		var url: URL?
		{
			switch kind
			{
			case .tool, .web: return nil
			case .page:
				guard let url = URL(string: path), url.scheme == "https",
						url.host != nil
				else
				{
					return nil
				}
				return url
			default: return LocalAttachmentURL.resolve(path)
			}
		}
		var iconIdentifier: DesktopIcon
		{
			switch kind
			{
			case .image: .fileImage
			case .folder: .folder
			case .audio: .fileAudio
			case .pdf: .fileDocument
			case .file: .file
			case .page: .document
			case .web: .globe
			case .tool:
				switch name
				{
				case "Terminal": .terminal
				case "Space": .stack
				case "ChatGPT App Tools": .openaiLogoRegular
				default: .tools
				}
			}
		}
		var summary: SummarySourceReference
		{
			let summaryKind: SummarySourceReference.Kind
			switch kind
			{
			case .folder: summaryKind = .folder
			case .web: summaryKind = .web
			case .tool: summaryKind = .tool
			case .image, .audio, .pdf, .file, .page: summaryKind = .attachment
			}
			return SummarySourceReference(
				id: id,
				label: name,
				kind: summaryKind,
				thumbnailPath: kind == .image ? (isInlineImage ? path : url?.path) : nil,
				detailRecordID: id,
				categoryLabel: kind == .tool || kind == .web ? name : nil,
				icon: iconIdentifier
			)
		}
	}

	let records: [Record]

	init(entries: [ConversationEntry])
	{
		var seen = Set<Data>()
		var records: [Record] = []
		var activityIndices: [String: Int] = [:]
		var seenInvocations = Set<String>()
		var entryIndices: [String: Int] = [:]
		var uniqueEntries: [ConversationEntry] = []
		for entry in entries
		{
			if let index = entryIndices[entry.id]
			{
				uniqueEntries[index] = entry
			}
			else
			{
				entryIndices[entry.id] = uniqueEntries.count
				uniqueEntries.append(entry)
			}
		}
		for entry in uniqueEntries
		{
			if entry.kind == .user
			{
				for reference in entry.sourceReferences + entry.imageAttachments
				{
					let local = LocalAttachmentURL.resolve(reference.path)
					let key = LocalAttachmentURL.referenceIdentity(reference.path)
					guard seen.insert(key).inserted
					else
					{
						continue
					}
					let id = "attachment:\(entry.id.utf8.count):\(entry.id):\(reference.id)"
					records.append(Record(
						id: id,
						name: InlineImageData
							.isDataURL(reference.path) ? "Attached image" : reference.name,
						path: reference.path,
						kind: Self.kind(
							for: reference,
							url: local
						)
					))
				}
			}
			guard let activity = entry.sourceActivity, activity.kind != .terminal
			else
			{
				continue
			}
			// Turn scope prevents collisions; repeated events remain one invocation.
			let invocationID = entry.id
			guard seenInvocations.insert(invocationID).inserted
			else
			{
				continue
			}
			let key = "activity:\(activity.kind == .web ? "web" : "tool"):\(activity.provider)"
			let invocation = Invocation(
				id: invocationID,
				summary: activity.summary,
				detail: activity.detail,
				status: activity.status,
				operation: activity.operation,
				resultText: activity.displayPayload,
				resultLanguage: activity.displayLanguage,
				isError: activity.displayIsError
			)
			if let index = activityIndices[key]
			{
				records[index].invocations.append(invocation)
			}
			else
			{
				activityIndices[key] = records.count
				records.append(Record(
					id: key,
					name: activity.provider,
					path: activity.provider,
					kind: activity.kind == .web ? .web : .tool,
					association: "Used in the conversation",
					invocations: [invocation]
				))
			}
			if let page = activity.page, seen.insert(Data("page:\(page.id)".utf8)).inserted
			{
				records.append(Record(
					id: "page:\(page.id)",
					name: page.title,
					path: page.url,
					kind: .page,
					association: "Read during the chat"
				))
			}
		}
		for index in records.indices where !records[index].invocations.isEmpty
		{
			let invocations = records[index].invocations
			if records[index].kind == .web
			{
				let counts = [("Search", "Searches"), ("Open", "Opens"), ("Find", "Finds")]
					.compactMap
					{
						operation, plural -> String? in
						let count = invocations
							.filter
							{
								$0.summary == operation || $0.summary.hasPrefix(operation + ":")
							}
							.count
						return count == 0 ? nil : "\(count) \(count == 1 ? operation : plural)"
					}
				records[index].association = counts
					.isEmpty ? "\(invocations.count) operations" : counts.joined(separator: ", ")
			}
			else
			{
				let noun = invocations.count == 1 ? "invocation" : "invocations"
				records[index].association = "\(invocations.count) \(noun)"
			}
		}
		let resourceRecords = records.filter
		{
			$0.kind != .tool && $0.kind != .web
		}
		let providerOrder = ["Space", "ChatGPT App Tools", "Web search"]
		let activities = records.enumerated()
			.filter
			{
				$0.element.kind == .tool || $0.element.kind == .web
			}.sorted
			{
				left, right in
				let leftRank = providerOrder.firstIndex(of: left.element.name) ?? providerOrder
					.count
				let rightRank = providerOrder.firstIndex(of: right.element.name) ?? providerOrder
					.count
				return leftRank == rightRank ? left.offset < right.offset : leftRank < rightRank
			}.map(\.element)
		self.records = resourceRecords + activities
	}

	private static func kind(
		for reference: UserMessageReference,
		url: URL?
	) -> Kind
	{
		if reference.kind == .audio
		{
			return .audio
		}
		if reference.kind == .image
		{
			return .image
		}
		if reference.path
			.hasSuffix("/") || (try? url?.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ==
			true
		{
			return .folder
		}
		switch url?.pathExtension.lowercased() ?? URL(fileURLWithPath: reference.path).pathExtension
			.lowercased()
		{
		case "pdf": return .pdf
		case "mp3", "wav", "m4a", "aac", "flac", "ogg", "aiff", "opus": return .audio
		case "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff": return .image
		default: return .file
		}
	}

	func record(
		for request: ContextPanelRequest,
		owner: FeaturePresentationOwner
	) -> Record?
	{
		guard request.owner == owner, request.destination == .sources, let id = request.recordID
		else
		{
			return nil
		}
		return records.first
		{
			$0.id == id
		}
	}
}
