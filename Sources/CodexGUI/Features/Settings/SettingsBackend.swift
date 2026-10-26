import Foundation

/// A presentation-scoped connection for user settings, separate from workspace turn ownership.
@MainActor
final class SettingsBackend
{
	let server: AppServer
	private(set) var config: [String: Any] = [:]
	private(set) var requirements: [String: Any] = [:]
	private(set) var status = "Open settings to load your configuration."
	private(set) var isConnected = false
	private(set) var featureStatus = ""
	private var featureStates: [String: Bool] = [:]
	var isBusy: Bool
	{
		operationActive
	}
	var onChange: (() -> Void)?
	var onDidSave: (([String: Any]) -> Void)?

	private var presented = false
	private var generation = UUID()
	private var userVersion: String?
	private var configurationLoaded = false
	private var operationActive = false
	private var waiters: [CheckedContinuation<Void, Never>] = []

	init(server: AppServer = AppServer())
	{
		self.server = server
		server.onDisconnect =
		{
			[weak self] message in
			guard let self, self.presented
			else
			{
				return
			}
			self.generation = UUID()
			self.isConnected = false
			self.featureStates = [:]
			self.featureStatus = ""
			self.status = message
			self.onChange?()
		}
	}

	func start() async
	{
		guard !presented
		else
		{
			return
		}
		presented = true
		generation = UUID()
		featureStates = [:]
		featureStatus = ""
		let scope = generation
		await acquire()
		defer
		{
			release()
		}
		guard isCurrent(scope)
		else
		{
			return
		}
		status = "Loading settings…"
		onChange?()
		do
		{
			try await server.connect()
			guard isCurrent(scope)
			else
			{
				return
			}
			isConnected = true
			try await readConfiguration(scope: scope)
			guard isCurrent(scope)
			else
			{
				return
			}
			status = ""
		}
		catch
		{
			guard isCurrent(scope)
			else
			{
				return
			}
			status = error.localizedDescription
		}
	}

	func stop()
	{
		presented = false
		generation = UUID()
		isConnected = false
		config = [:]
		requirements = [:]
		featureStates = [:]
		featureStatus = ""
		userVersion = nil
		configurationLoaded = false
		server.disconnect()
		status = "Settings are closed."
		onChange?()
	}

	func reload() async
	{
		if !isConnected
		{
			await start()
			return
		}
		let scope = generation
		await acquire()
		defer
		{
			release()
		}
		guard isCurrent(scope), isConnected
		else
		{
			return
		}
		do
		{
			try await readConfiguration(scope: scope)
			guard isCurrent(scope)
			else
			{
				return
			}
			status = ""
		}
		catch
		{
			guard isCurrent(scope)
			else
			{
				return
			}
			status = error.localizedDescription
		}
	}

	func value(_ key: String) -> Any?
	{
		var value: Any = config
		for component in key.split(separator: ".").map(String.init)
		{
			guard let next = (value as? [String: Any])?[component]
			else
			{
				return nil
			}
			value = next
		}
		return value is NSNull ? nil : value
	}

	/// The catalog resolves runtime defaults; a missing config override does not mean disabled.
	func featureEnabled(_ name: String) -> Bool?
	{
		featureStates[name] ?? value("features.\(name)") as? Bool
	}

	@discardableResult
	func write(_ values: [String: Any]) async -> Bool
	{
		let scope = generation
		await acquire()
		defer
		{
			release()
		}
		guard isCurrent(scope), isConnected, !Task.isCancelled
		else
		{
			return false
		}
		guard !values.isEmpty
		else
		{
			return false
		}
		if !configurationLoaded
		{
			do
			{
				try await readConfiguration(scope: scope)
			}
			catch
			{
				guard isCurrent(scope)
				else
				{
					return false
				}
				status = error.localizedDescription
				return false
			}
		}
		guard isCurrent(scope), !Task.isCancelled
		else
		{
			return false
		}
		status = "Saving…"
		onChange?()
		var parameters: [String: Any] = [
			"edits": values.keys.sorted().map
			{
				["keyPath": $0, "value": values[$0]!, "mergeStrategy": "replace"]
			},
			"reloadUserConfig": true,
		]
		if let userVersion
		{
			parameters["expectedVersion"] = userVersion
		}
		do
		{
			let result = try await server.settingsRequest(
				"config/batchWrite",
				params: parameters
			)
			guard isCurrent(scope)
			else
			{
				return false
			}
			guard let outcome = result["status"] as? String,
					["ok", "okOverridden"].contains(outcome), result["version"] is String
			else
			{
				throw AppServerError
					.protocolError("Codex returned an invalid settings write result.")
			}
			let overridden = outcome == "okOverridden"
			do
			{
				try await readConfiguration(scope: scope)
				guard isCurrent(scope)
				else
				{
					return false
				}
				status = overridden
					? "Saved, but a higher-priority configuration overrides this setting."
					: "Saved. Existing chats may retain their current model and speed settings."
				onDidSave?(values)
				return true
			}
			catch
			{
				guard isCurrent(scope)
				else
				{
					return false
				}
				status = "The write completed, but settings could not be refreshed: "
					+ error.localizedDescription
				userVersion = nil
				configurationLoaded = false
			}
		}
		catch
		{
			guard isCurrent(scope)
			else
			{
				return false
			}
			status = error.localizedDescription
			// A rejected version or uncertain response must be resolved by a read, never a replay.
			let failure = status
			try? await readConfiguration(scope: scope)
			guard isCurrent(scope)
			else
			{
				return false
			}
			status = failure
		}
		return false
	}

	func perform(
		_ method: String,
		params: [String: Any]
	) async throws -> [String: Any]
	{
		let scope = generation
		await acquire()
		defer
		{
			release()
		}
		guard isCurrent(scope), isConnected
		else
		{
			throw AppServerError.disconnected
		}
		try Task.checkCancellation()
		let response = try await server.settingsRequest(
			method,
			params: params
		)
		guard isCurrent(scope)
		else
		{
			throw AppServerError.disconnected
		}
		return response
	}

	private func readConfiguration(scope: UUID) async throws
	{
		configurationLoaded = false
		featureStates = [:]
		featureStatus = ""
		let response = try await server.settingsRequest(
			"config/read",
			params: ["includeLayers": true]
		)
		guard isCurrent(scope)
		else
		{
			throw AppServerError.disconnected
		}
		guard let effective = response["config"] as? [String: Any]
		else
		{
			throw AppServerError.protocolError("Codex returned invalid settings.")
		}
		config = effective
		let layers = response["layers"] as? [[String: Any]] ?? []
		userVersion = layers.first
		{
			guard let name = $0["name"] as? [String: Any]
			else
			{
				return false
			}
			return name["type"] as? String == "user"
				&& (name["profile"] == nil || name["profile"] is NSNull)
		}?["version"] as? String
		let responseRequirements = try await server.settingsRequest(
			"configRequirements/read",
			params: [:]
		)
		guard isCurrent(scope)
		else
		{
			throw AppServerError.disconnected
		}
		requirements = responseRequirements["requirements"] as? [String: Any] ?? [:]
		configurationLoaded = true
		await readFeatureStates(scope: scope)
		guard isCurrent(scope)
		else
		{
			throw AppServerError.disconnected
		}
	}

	private func readFeatureStates(scope: UUID) async
	{
		do
		{
			var states: [String: Bool] = [:]
			var cursor: String?
			var tracker = PaginationCursorTracker(
				repeatedCursorMessage: "Codex repeated the feature catalog cursor."
			)
			repeat
			{
				var parameters: [String: Any] = ["limit": 100]
				if let cursor
				{
					parameters["cursor"] = cursor
				}
				let response = try await server.settingsRequest(
					"experimentalFeature/list",
					params: parameters
				)
				guard isCurrent(scope)
				else
				{
					return
				}
				guard let rows = response["data"] as? [[String: Any]]
				else
				{
					throw AppServerError.protocolError("Codex returned an invalid feature catalog.")
				}
				for row in rows
				{
					guard let name = row["name"] as? String,
							let enabled = row["enabled"] as? Bool
					else
					{
						throw AppServerError.protocolError("Codex returned invalid feature state.")
					}
					states[name] = enabled
				}
				cursor = try tracker.advance(to: response["nextCursor"] as? String)
			}
			while cursor != nil
			featureStates = states
			featureStatus = ""
		}
		catch
		{
			guard isCurrent(scope)
			else
			{
				return
			}
			featureStates = [:]
			featureStatus = "Feature availability could not be loaded: " + error
				.localizedDescription
		}
	}

	private func isCurrent(_ scope: UUID) -> Bool
	{
		presented && generation == scope
	}

	private func acquire() async
	{
		if operationActive
		{
			await withCheckedContinuation
			{
				waiters.append($0)
			}
		}
		else
		{
			operationActive = true
			onChange?()
		}
	}

	private func release()
	{
		if waiters.isEmpty
		{
			operationActive = false
		}
		else
		{
			waiters.removeFirst().resume()
		}
		onChange?()
	}
}
