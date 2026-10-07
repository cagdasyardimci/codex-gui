import Foundation

/// Review markers are keyed by their origin and accepted only for the same content fingerprint.
final class ReviewMarkerStore
{
	private let defaults: UserDefaults
	private let storageKey = "reviewedChangeFingerprints.v1"

	init(defaults: UserDefaults = ApplicationPreferences.defaultStore)
	{
		self.defaults = defaults
	}

	func isReviewed(
		projectPath: String,
		reference: ReviewReference,
		fingerprint: String
	) -> Bool
	{
		let markerKey = key(
			projectPath: projectPath,
			reference: reference
		)
		return markers()[markerKey] == fingerprint
	}

	func setReviewed(
		_ reviewed: Bool,
		projectPath: String,
		reference: ReviewReference,
		fingerprint: String
	)
	{
		var storedMarkers = markers()
		let markerKey = key(
			projectPath: projectPath,
			reference: reference
		)
		if reviewed
		{
			storedMarkers[markerKey] = fingerprint
		}
		else
		{
			storedMarkers.removeValue(forKey: markerKey)
		}
		defaults.set(
			storedMarkers,
			forKey: storageKey
		)
	}

	/// One fresh snapshot belongs to each read operation, including file and hunk identities.
	func reviewedIdentities(
		projectPath: String,
		identities: [ReviewMarkerIdentity]
	) -> [ReviewMarkerIdentity]
	{
		let storedMarkers = markers()
		return identities.filter
		{
			identity in
			storedMarkers[key(
				projectPath: projectPath,
				reference: identity.reference
			)] == identity.fingerprint
		}
	}

	private func markers() -> [String: String]
	{
		defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
	}

	private func key(
		projectPath: String,
		reference: ReviewReference
	) -> String
	{
		[projectPath, reference.threadID, reference.turnID, reference.path, reference.hunkID ?? ""]
			.joined(separator: "\u{0}")
	}
}
