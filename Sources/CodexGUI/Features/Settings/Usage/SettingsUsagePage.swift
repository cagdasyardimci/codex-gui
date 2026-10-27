import AppKit

@MainActor
final class SettingsUsagePage: SettingsManagementPage
{
	private var rawLimits: [String: Any]?
	private var limits: AccountRateLimitsSnapshot?
	private var planType: String?
	private var usage: [String: Any]?
	private lazy var usageView = SettingsUsageView()

	init(backend: SettingsBackend)
	{
		super.init(
			title: "Usage & billing",
			backend: backend
		)
		usageView.onRefresh =
		{
			[weak self] in self?.load()
		}
		usageView.onUseReset =
		{
			[weak self] creditID in self?.requestReset(creditID)
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func render()
	{
		if usageView.superview == nil
		{
			AppKitLayout.pin(
				usageView,
				to: self,
				inset: 0
			)
		}
		usageView.update(
			limits: limits,
			planType: planType,
			usage: usage,
			busy: isOperating,
			canUseReset: rawLimits.map(SettingsManagementPolicy.canReset) ?? false
		)
	}

	override func load()
	{
		guard !isOperating
		else
		{
			return
		}
		run
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			let metadata = try await readMetadata()
			try Task.checkCancellation()
			publish(metadata)
		}
	}

	private struct Metadata
	{
		let rawLimits: [String: Any]
		let limits: AccountRateLimitsSnapshot
		let planType: String?
		let usage: [String: Any]?
	}

	private func readMetadata() async throws -> Metadata
	{
		let raw = try await backend.perform(
			"account/rateLimits/read",
			params: [:]
		)
		guard let snapshot = AccountRateLimitsSnapshot(json: raw)
		else
		{
			throw AppServerError.protocolError("Codex returned an invalid usage snapshot.")
		}
		try Task.checkCancellation()
		var plan = snapshot.rateLimits.planType
			?? snapshot.rateLimitsByLimitId?["codex"]?.planType
		if plan == nil
		{
			do
			{
				let account = try await backend.perform(
					"account/read",
					params: ["refreshToken": false]
				)
				plan = (account["account"] as? [String: Any])?["planType"] as? String
			}
			catch
			{
				try Task.checkCancellation()
			}
		}
		try Task.checkCancellation()
		var tokenUsage: [String: Any]?
		do
		{
			tokenUsage = try await backend.perform(
				"account/usage/read",
				params: [:]
			)
		}
		catch
		{
			try Task.checkCancellation()
		}
		try Task.checkCancellation()
		return Metadata(
			rawLimits: raw,
			limits: snapshot,
			planType: plan,
			usage: tokenUsage
		)
	}

	private func publish(_ metadata: Metadata)
	{
		rawLimits = metadata.rawLimits
		limits = metadata.limits
		planType = metadata.planType
		usage = metadata.usage
	}

	private func requestReset(_ creditID: String?)
	{
		guard !isOperating, let rawLimits,
				SettingsManagementPolicy.canReset(rawLimits)
		else
		{
			return
		}
		let requestedID = creditID
		let expectedAccountID = limits?.accountId
		let selected = limits?.rateLimitResetCredits?.credits?.first
		{
			$0.id == requestedID
		}
		let description = selected?.title.map
		{
			"Use “\($0)” to reset eligible usage limits?"
		}
		?? "Consume one existing usage reset for this account?"
		confirm(
			"Use reset",
			detail: description
		)
		{
			[weak self] in
			guard let self, !isOperating
			else
			{
				return
			}
			let attemptID = UUID().uuidString
			run
			{
				[weak self] in
				guard let self
				else
				{
					return
				}
				let fresh = try await backend.perform(
					"account/rateLimits/read",
					params: [:]
				)
				try Task.checkCancellation()
				guard let snapshot = AccountRateLimitsSnapshot(json: fresh),
						SettingsManagementPolicy.canReset(fresh)
				else
				{
					throw AppServerError
						.requestRejected("No eligible usage window or reset credit.")
				}
				if let expectedAccountID, snapshot.accountId != expectedAccountID
				{
					throw AppServerError
						.requestRejected("The account changed. Refresh usage and try again.")
				}
				if let requestedID
				{
					try validateCredit(
						requestedID,
						in: snapshot
					)
				}
				var params: [String: Any] = ["idempotencyKey": attemptID]
				if let requestedID
				{
					params["creditId"] = requestedID
				}
				let response = try await backend.perform(
					"account/rateLimitResetCredit/consume",
					params: params
				)
				try Task.checkCancellation()
				try Self.validateResetOutcome(response["outcome"] as? String)
				do
				{
					let metadata = try await readMetadata()
					try Task.checkCancellation()
					publish(metadata)
				}
				catch
				{
					try Task.checkCancellation()
					self.rawLimits = nil
				}
			}
		}
	}

	private func validateCredit(
		_ id: String,
		in snapshot: AccountRateLimitsSnapshot
	) throws
	{
		guard let credit = snapshot.rateLimitResetCredits?.credits?.first(where:
			{
				$0.id == id
			}),
			credit.status == "available", credit.resetType == "codexRateLimits",
			credit.expiresAt.map(
				{
					$0 > Date()
				}
			) ?? true
		else
		{
			throw AppServerError
				.requestRejected("This usage reset is no longer available. Refresh usage.")
		}
	}

	private static func validateResetOutcome(_ outcome: String?) throws
	{
		switch outcome
		{
		case "reset", "alreadyRedeemed", "nothingToReset", "noCredit": return
		default: throw AppServerError.protocolError("Codex returned an unknown usage reset result.")
		}
	}
}
