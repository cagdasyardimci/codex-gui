import Foundation

@MainActor
final class LocalStorage
{
	private enum Key
	{
		static let recentProjects = "CodexGUI.recentProjects"
		static let drafts = "CodexGUI.drafts"
		static let selectedThreads = "CodexGUI.selectedThreads"
		static let modelPreference = "CodexGUI.modelPreference"
		static let runPreferences = "CodexGUI.runPreferences"
		static let pinnedProjects = "CodexGUI.pinnedProjects"
		static let projectDisplayNames = "CodexGUI.projectDisplayNames"
		static let draftContext = "CodexGUI.draftContext"
		static let sentReferences = "CodexGUI.sentReferences"
		static let pendingCommands = "CodexGUI.pendingCommands"
		static let legacyRecentProject = "recentProject"
		static let legacyDraft = "draft"
	}

	private static let maximumRecentProjects = 10
	private static let maximumSentReferences = 200
	private static let maximumSentImages = 24
	private static let maximumReferencesPerThread = 100

	private let defaults: UserDefaults
	private let imageStore: DraftImageStore
	private var contextByPendingRequestID: [UUID: [ComposerContextItem]] = [:]

	/// All workspace sessions sharing these draft keys must share their write queue.
	lazy var workspacePersistenceScheduler = WorkspacePersistenceScheduler(storage: self)

	private var preferenceObservers: [UUID: (PreferencesRestoration) -> Void] = [:]

	var preferenceRestoration: PreferencesRestoration
	{
		PreferencesRestoration(
			modelPreference: modelPreference.map
			{
				ProjectModelPreference(
					modelID: $0.modelID,
					effort: $0.effort
				)
			},
			runPreferences: runPreferences,
			recentProjects: recentProjects,
			pinnedProjectPaths: pinnedProjectPaths,
			projectDisplayNames: projectDisplayNames
		)
	}

	func observePreferences(_ observer: @escaping (PreferencesRestoration) -> Void) -> UUID
	{
		let id = UUID()
		preferenceObservers[id] = observer
		observer(preferenceRestoration)
		return id
	}

	func removePreferenceObserver(_ id: UUID)
	{
		preferenceObservers.removeValue(forKey: id)
	}

	private func publishPreferences()
	{
		let value = preferenceRestoration
		for observer in Array(preferenceObservers.values)
		{
			observer(value)
		}
	}

	func applyPreferenceWrite(_ write: PreferenceWrite)
	{
		switch write.value
		{
		case .model(let preference):
			saveModelPreference(
				modelID: preference.modelID,
				effort: preference.effort
			)
		case .run(let preference): saveRunPreferences(preference)
		case .pin(
			let path,
			let pinned
		):
			let url = URL(fileURLWithPath: path)
			if pinnedProjectPaths.contains(canonicalPath(for: url)) != pinned
			{
				toggleProjectPin(url)
			}
		case .name(
			let path,
			let name
		): renameProject(
				URL(fileURLWithPath: path),
				name: name
			)
		case .recent(let path): rememberProject(URL(fileURLWithPath: path))
		}
	}

	private struct SentReferenceRecord: Codable
	{
		let projectPath: String
		let threadID: String
		let item: ComposerContextItem
	}

	struct ModelPreference: Equatable
	{
		let modelID: String?
		let effort: String?
	}

	init(
		defaults: UserDefaults = .standard,
		imageStore: DraftImageStore = DraftImageStore()
	)
	{
		self.defaults = defaults
		self.imageStore = imageStore
		migrateLegacyValues()
	}

	var recentProjects: [URL]
	{
		let recentPaths = storedRecentProjectPaths()
		let retainedPins = pinnedProjectPaths.subtracting(recentPaths).sorted()
		return (recentPaths + retainedPins).map(URL.init(fileURLWithPath:))
	}

	var pinnedProjectPaths: Set<String>
	{
		Set(
			(defaults.stringArray(forKey: Key.pinnedProjects) ?? []).map
			{
				canonicalPath(for: URL(fileURLWithPath: $0))
			}
		)
	}

	var projectDisplayNames: [String: String]
	{
		defaults.dictionary(forKey: Key.projectDisplayNames) as? [String: String] ?? [:]
	}

	func toggleProjectPin(_ project: URL)
	{
		let path = canonicalPath(for: project)
		var pins = pinnedProjectPaths
		if !pins.insert(path).inserted
		{
			pins.remove(path)
		}
		defaults.set(
			pins.sorted(),
			forKey: Key.pinnedProjects
		)
		publishPreferences()
	}

	/// Renaming affects the local sidebar alias, never the repository folder or conversation
	/// titles.
	func renameProject(
		_ project: URL,
		name: String
	)
	{
		var names = projectDisplayNames
		let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
		names[canonicalPath(for: project)] = trimmedName.isEmpty ? nil : trimmedName
		defaults.set(
			names,
			forKey: Key.projectDisplayNames
		)
		publishPreferences()
	}

	var runPreferences: RunPreferences
	{
		guard let data = defaults.data(forKey: Key.runPreferences),
				let preferences = try? JSONDecoder().decode(
				RunPreferences.self,
				from: data
				)
		else
		{
			return .standard
		}
		return preferences
	}

	func saveRunPreferences(_ preferences: RunPreferences)
	{
		guard let data = try? JSONEncoder().encode(preferences)
		else
		{
			return
		}
		defaults.set(
			data,
			forKey: Key.runPreferences
		)
		publishPreferences()
	}

	func rememberProject(_ url: URL)
	{
		let projectPath = canonicalPath(for: url)
		var paths = storedRecentProjectPaths()
		paths.removeAll
		{
			$0 == projectPath
		}
		paths.insert(
			projectPath,
			at: 0
		)

		defaults.set(
			Array(paths.prefix(Self.maximumRecentProjects)),
			forKey: Key.recentProjects
		)
		publishPreferences()
	}

	func pendingCommands(for project: URL) -> [TaskCommandOwnership]
	{
		guard let records = defaults.dictionary(forKey: Key.pendingCommands),
				let data = records[canonicalPath(for: project)] as? Data
		else
		{
			return []
		}
		return (try? JSONDecoder().decode(
			[TaskCommandOwnership].self,
			from: data
		)) ?? []
	}

	func savePendingCommands(
		_ commands: Set<TaskCommandOwnership>,
		for project: URL
	)
	{
		var records = defaults.dictionary(forKey: Key.pendingCommands) ?? [:]
		records[canonicalPath(for: project)] = try? JSONEncoder().encode(Array(commands))
		defaults.set(
			records,
			forKey: Key.pendingCommands
		)
	}

	func draft(
		for project: URL,
		threadID: String?
	) -> String
	{
		let projectPath = canonicalPath(for: project)
		let draftKey = Self.draftKey(for: threadID)
		return storedDrafts()[projectPath]?[draftKey] ?? ""
	}

	func saveDraft(
		_ text: String,
		for project: URL,
		threadID: String?
	)
	{
		let projectPath = canonicalPath(for: project)
		let draftKey = Self.draftKey(for: threadID)
		var drafts = storedDrafts()
		drafts[projectPath, default: [:]][draftKey] = text
		defaults.set(
			drafts,
			forKey: Key.drafts
		)
	}

	func draftContext(
		for project: URL,
		threadID: String?
	) -> [ComposerContextItem]
	{
		let records = contextRecords(forKey: Key.draftContext)
		let projectPath = canonicalPath(for: project)
		let draftKey = Self.draftKey(for: threadID)
		return records[projectPath]?[draftKey] ?? []
	}

	func saveDraftContext(
		_ items: [ComposerContextItem],
		for project: URL,
		threadID: String?
	)
	{
		var records = contextRecords(forKey: Key.draftContext)
		let projectPath = canonicalPath(for: project)
		let draftKey = Self.draftKey(for: threadID)
		let previousItems = records[projectPath]?[draftKey] ?? []
		records[projectPath, default: [:]][draftKey] = items
		guard saveContextRecords(
			records,
			forKey: Key.draftContext
		)
		else
		{
			return
		}
		pruneOwnedImages(from: previousItems)
	}

	func sentReferences(
		for project: URL,
		threadID: String
	) -> [ComposerContextItem]
	{
		sentReferenceRecords().filter
		{
			$0.projectPath == canonicalPath(for: project) && $0.threadID == threadID
		}.map(\.item)
	}

	func rememberSentReferences(
		_ items: [ComposerContextItem],
		for project: URL,
		threadID: String
	)
	{
		guard !items.isEmpty
		else
		{
			return
		}
		let previousRecords = sentReferenceRecords()
		let projectPath = canonicalPath(for: project)
		let appendedRecords = items.map
		{
			SentReferenceRecord(
				projectPath: projectPath,
				threadID: threadID,
				item: $0
			)
		}
		let retainedRecords = retainRecentReferences(previousRecords + appendedRecords)
		guard saveSentReferenceRecords(retainedRecords)
		else
		{
			return
		}

		pruneOwnedImages(from: previousRecords.map(\.item) + items)
	}

	private func saveSentReferenceRecords(_ records: [SentReferenceRecord]) -> Bool
	{
		guard let data = try? JSONEncoder().encode(records)
		else
		{
			return false
		}
		defaults.set(
			data,
			forKey: Key.sentReferences
		)
		return true
	}

	/// Draft editing must not delete an image while Codex is reading a submitted request.
	func retainContextForRequest(_ items: [ComposerContextItem]) -> UUID
	{
		let requestID = UUID()
		contextByPendingRequestID[requestID] = items
		return requestID
	}

	func releaseContextForRequest(_ requestID: UUID)
	{
		guard let items = contextByPendingRequestID.removeValue(forKey: requestID)
		else
		{
			return
		}
		pruneOwnedImages(from: items)
	}

	func selectedThreadID(for project: URL) -> String?
	{
		let path = canonicalPath(for: project)
		return (defaults.dictionary(forKey: Key.selectedThreads) as? [String: String])?[path]
	}

	func saveSelectedThreadID(
		_ id: String?,
		for project: URL
	)
	{
		let path = canonicalPath(for: project)
		var selections = defaults
			.dictionary(forKey: Key.selectedThreads) as? [String: String] ?? [:]
		selections[path] = id
		defaults.set(
			selections,
			forKey: Key.selectedThreads
		)
	}

	var modelPreference: ModelPreference?
	{
		guard let value = defaults.dictionary(forKey: Key.modelPreference) as? [String: String],
				let model = value["model"]
		else
		{
			return nil
		}
		return ModelPreference(
			modelID: model.isEmpty ? nil : model,
			effort: value["effort"].flatMap
			{
				$0.isEmpty ? nil : $0
			}
		)
	}

	func saveModelPreference(
		modelID: String?,
		effort: String?
	)
	{
		defaults.set(
			["model": modelID ?? "", "effort": effort ?? ""],
			forKey: Key.modelPreference
		)
		publishPreferences()
	}

	private func migrateLegacyValues()
	{
		guard let legacyProjectPath = defaults.string(forKey: Key.legacyRecentProject)
		else
		{
			return
		}

		let projectURL = URL(fileURLWithPath: legacyProjectPath)
		let canonicalProjectPath = canonicalPath(for: projectURL)
		rememberProject(projectURL)

		migrateLegacyDraft(for: canonicalProjectPath)

		defaults.removeObject(forKey: Key.legacyRecentProject)
	}

	private func migrateLegacyDraft(for canonicalProjectPath: String)
	{
		if let legacyDraft = defaults.string(forKey: Key.legacyDraft)
		{
			let draftKey = Self.draftKey(for: nil)
			var drafts = storedDrafts()
			if drafts[canonicalProjectPath]?[draftKey] == nil
			{
				drafts[canonicalProjectPath, default: [:]][draftKey] = legacyDraft
				defaults.set(
					drafts,
					forKey: Key.drafts
				)
			}
			defaults.removeObject(forKey: Key.legacyDraft)
		}
	}

	private func storedRecentProjectPaths() -> [String]
	{
		let values = defaults.stringArray(forKey: Key.recentProjects) ?? []
		var seenPaths = Set<String>()

		return values.compactMap
		{
			path in
			let canonicalProjectPath = canonicalPath(for: URL(fileURLWithPath: path))
			guard seenPaths.insert(canonicalProjectPath).inserted
			else
			{
				return nil
			}
			return canonicalProjectPath
		}
	}

	private func storedDrafts() -> [String: [String: String]]
	{
		defaults.dictionary(forKey: Key.drafts) as? [String: [String: String]] ?? [:]
	}

	private func contextRecords(forKey key: String) -> [String: [String: [ComposerContextItem]]]
	{
		guard let data = defaults.data(forKey: key)
		else
		{
			return [:]
		}
		return (try? JSONDecoder().decode(
			[String: [String: [ComposerContextItem]]].self,
			from: data
		))
			?? [:]
	}

	private func sentReferenceRecords() -> [SentReferenceRecord]
	{
		guard let data = defaults.data(forKey: Key.sentReferences)
		else
		{
			return []
		}
		if let records = try? JSONDecoder().decode(
			[SentReferenceRecord].self,
			from: data
		)
		{
			return records
		}
		return legacySentReferenceRecords(from: data)
	}

	private func legacySentReferenceRecords(from data: Data) -> [SentReferenceRecord]
	{
		// Earlier builds stored sent references by project and thread. Preserve
		// those records when switching to globally ordered retention.
		guard
			let legacy = try? JSONDecoder().decode(
				[String: [String: [ComposerContextItem]]].self,
				from: data
			)
		else
		{
			return []
		}
		return legacy.keys.sorted().flatMap
		{
			projectPath in
			(legacy[projectPath] ?? [:]).keys.sorted().flatMap
			{
				key -> [SentReferenceRecord] in
				guard key.hasPrefix("thread:")
				else
				{
					return []
				}
				let threadID = String(key.dropFirst("thread:".count))
				return (legacy[projectPath]?[key] ?? []).map
				{
					SentReferenceRecord(
						projectPath: projectPath,
						threadID: threadID,
						item: $0
					)
				}
			}
		}
	}

	private func retainRecentReferences(_ records: [SentReferenceRecord]) -> [SentReferenceRecord]
	{
		var retainedRecords: [SentReferenceRecord] = []
		var countByThread: [String: Int] = [:]
		var imageCount = 0
		for record in records.reversed()
		{
			let threadKey = "\(record.projectPath)\u{0}\(record.threadID)"
			guard retainedRecords.count < Self.maximumSentReferences,
					countByThread[threadKey, default: 0] < Self.maximumReferencesPerThread
			else
			{
				continue
			}
			if record.item.kind == .image
			{
				guard imageCount < Self.maximumSentImages
				else
				{
					continue
				}
				imageCount += 1
			}
			countByThread[threadKey, default: 0] += 1
			retainedRecords.append(record)
		}
		return retainedRecords.reversed()
	}

	private func pruneOwnedImages(from candidates: [ComposerContextItem])
	{
		let ownedCandidates = ownedImagePaths(in: candidates)
		guard !ownedCandidates.isEmpty
		else
		{
			return
		}

		let referencedImagePaths = referencedOwnedImagePaths()

		for path in ownedCandidates.subtracting(referencedImagePaths)
		{
			imageStore.removeOwnedCopy(at: path)
		}
	}

	private func referencedOwnedImagePaths() -> Set<String>
	{
		let draftItems = contextRecords(forKey: Key.draftContext).values.flatMap
		{
			$0.values.flatMap
			{
				$0
			}
		}
		let sentItems = sentReferenceRecords().map(\.item)
		let pendingItems = contextByPendingRequestID.values.flatMap
		{
			$0
		}
		// Pending requests retain their attachments even if their draft has been edited.
		return ownedImagePaths(in: draftItems + sentItems + pendingItems)
	}

	private func ownedImagePaths(in items: [ComposerContextItem]) -> Set<String>
	{
		Set(
			items.compactMap
			{
				item in
				item.kind == .image ? item.path.flatMap(imageStore.ownedPath) : nil
			}
		)
	}

	@discardableResult
	private func saveContextRecords(
		_ records: [String: [String: [ComposerContextItem]]],
		forKey key: String
	) -> Bool
	{
		guard let data = try? JSONEncoder().encode(records)
		else
		{
			return false
		}
		defaults.set(
			data,
			forKey: key
		)
		return true
	}

	private func canonicalPath(for url: URL) -> String
	{
		url.standardizedFileURL.resolvingSymlinksInPath().path
	}

	private static func draftKey(for threadID: String?) -> String
	{
		guard let threadID
		else
		{
			return "new-chat"
		}
		return "thread:\(threadID)"
	}
}
