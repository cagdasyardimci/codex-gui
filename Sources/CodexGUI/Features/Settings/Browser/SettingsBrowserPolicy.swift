import Foundation

/// Site keys contain dots, so callers replace the origins table rather than building dotted paths.
enum SettingsBrowserPolicy
{
	static let fields: [(key: String, title: String)] = [
		("access", "Browse"),
		("downloads", "Downloads"),
		("uploads", "Uploads"),
		("full_cdp_access", "Site tools"),
	]

	static func normalizedOrigin(_ input: String) -> String?
	{
		let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let components = URLComponents(string: value),
				let scheme = components.scheme?.lowercased(),
				["https", "http"].contains(scheme),
				let host = components.host, !host.isEmpty,
				components.user == nil, components.password == nil,
				components.query == nil, components.fragment == nil,
				components.path.isEmpty || components.path == "/",
				!host.contains(where: \.isWhitespace)
		else
		{
			return nil
		}
		var origin = URLComponents()
		origin.scheme = scheme
		origin.host = host.lowercased()
		origin.port = components.port
		return origin.string
	}

	static func hasChanges(
		_ policy: [String: String],
		defaults: [String: Any]
	) -> Bool
	{
		policy.contains
		{
			key, value in defaults[key] as? String != value
		}
	}
}
