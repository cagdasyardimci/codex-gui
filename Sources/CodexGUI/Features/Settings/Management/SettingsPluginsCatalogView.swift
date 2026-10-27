import AppKit

struct SettingsPluginsCatalogEntry
{
	let id: String
	let plugin: [String: Any]
	let marketplace: [String: Any]
	let installed: Bool
	let searchText: String
}

/// Catalog metadata can be large; only one bounded page becomes native views.
@MainActor
final class SettingsPluginsCatalogView: NSView
{
	static let pageSize = 40
	private(set) var visiblePluginIDs: [String] = []
	private(set) var matchingCount = 0
	private let entries: [SettingsPluginsCatalogEntry]
	private let makeRow: (SettingsPluginsCatalogEntry) -> NSView?
	private let results = AppKitLayout.verticalStack(
		[],
		spacing: 0
	)
	private let previous = RemoteConnectionsButton(
		title: "Previous",
		presentation: .secondary
	)
	private let next = RemoteConnectionsButton(
		title: "Next",
		presentation: .secondary
	)
	private lazy var paging = NSStackView(views: [NSView(), previous, next])
	private var installedOnly = true
	private var query = ""
	private var page = 0
	var installedCount: Int
	{
		entries.filter(\.installed).count
	}

	init(
		marketplaces: [[String: Any]],
		makeRow: @escaping (SettingsPluginsCatalogEntry) -> NSView?
	)
	{
		entries = marketplaces.flatMap
		{
			marketplace in
			(marketplace["plugins"] as? [[String: Any]] ?? []).compactMap
			{
				plugin in
				guard let id = plugin["id"] as? String, let name = plugin["name"] as? String
				else
				{
					return nil
				}
				let interface = plugin["interface"] as? [String: Any]
				let terms = [name,
								interface?["displayName"] as? String ?? "",
								interface?["shortDescription"] as? String ?? "",
								marketplace["name"] as? String ?? ""]
				let systemMarketplace = ["openai-primary-runtime", "openai-bundled"]
					.contains(marketplace["name"] as? String ?? "")
				let implicit = plugin["installPolicySource"] as? String == "IMPLICIT_CANONICAL_APP"
				return SettingsPluginsCatalogEntry(
					id: id,
					plugin: plugin,
					marketplace: marketplace,
					installed: (plugin["installed"] as? Bool ?? false)
						&& !systemMarketplace && !implicit,
					searchText: terms.joined(separator: " ").lowercased()
				)
			}
		}.sorted
		{
			let left = $0.plugin["installedAt"] as? Int ?? 0
			let right = $1.plugin["installedAt"] as? Int ?? 0
			return left == right ? $0.id < $1.id : left > right
		}
		self.makeRow = makeRow
		super.init(frame: .zero)
		previous.target = self
		previous.action = #selector(previousPage)
		previous.setAccessibilityLabel("Previous plugin page")
		next.target = self
		next.action = #selector(nextPage)
		next.setAccessibilityLabel("Next plugin page")
		paging.spacing = 8
		let stack = AppKitLayout.verticalStack(
			[results, paging],
			spacing: 4
		)
		stack.alignment = .width
		results.alignment = .width
		AppKitLayout.pin(
			stack,
			to: self,
			inset: 1
		)
		for child in stack.arrangedSubviews
		{
			child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		renderResults()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func setFilter(installedOnly: Bool)
	{
		self.installedOnly = installedOnly
		page = 0
		renderResults()
	}

	func setSearch(_ query: String)
	{
		self.query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		page = 0
		renderResults()
	}

	func showPage(_ index: Int)
	{
		page = max(
			0,
			index
		)
		renderResults()
	}

	@objc private func previousPage()
	{
		showPage(page - 1)
	}
	@objc private func nextPage()
	{
		showPage(page + 1)
	}

	private func renderResults()
	{
		let matches = entries.filter
		{
			(!installedOnly || $0.installed) && (query.isEmpty || $0.searchText.contains(query))
		}
		matchingCount = matches.count
		let pageCount = max(
			1,
			(matchingCount + Self.pageSize - 1) / Self.pageSize
		)
		page = min(
			page,
			pageCount - 1
		)
		let start = page * Self.pageSize
		let visible = matches.dropFirst(start).prefix(Self.pageSize)
		visiblePluginIDs = visible.map(\.id)
		for row in results.arrangedSubviews
		{
			results.removeArrangedSubview(row)
			row.removeFromSuperview()
		}
		for entry in visible
		{
			guard let row = makeRow(entry)
			else
			{
				continue
			}
			results.addArrangedSubview(row)
			row.widthAnchor.constraint(equalTo: results.widthAnchor).isActive = true
		}
		for row in results.arrangedSubviews.dropLast()
		{
			SettingsPageLayout.addDivider(to: row)
		}
		paging.isHidden = pageCount == 1
		previous.isEnabled = page > 0
		next.isEnabled = page + 1 < pageCount
	}
}
