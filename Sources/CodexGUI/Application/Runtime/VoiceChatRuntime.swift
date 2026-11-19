import AppKit

/// A live call owns its originating store and thread independently of the window's selection.
@MainActor
final class VoiceChatRuntime
{
	typealias PeerFactory = @MainActor (
		NSView,
		@escaping () -> Void,
		@escaping () -> Void,
		@escaping (Double) -> Void
	) -> any VoiceChatPeer

	private enum Transport
	{
		case webRTC
		case retiringWebRTC
		case webSocket
	}

	@MainActor
	private final class Call
	{
		let id = UUID()
		let store: WorkspaceStateStore
		let server: AppServer
		let generation: UUID
		let allowsWebSocketFallback: Bool
		var summary: ThreadSummary?
		var voice: String?
		var transcriptStartTurnID: String?
		var voiceTurnIDs: Set<String> = []
		var threadID: String?
		{
			summary?.id
		}
		var storeObserver: UUID?
		var startupTask: Task<Void, Never>?
		var startRequest: Task<Void, Never>?
		var startSubmitted = false
		var transport: Transport
		var onStarted: (() -> Void)?
		var peer: (any VoiceChatPeer)?
		var peerReady = false
		var serverStarted = false
		var started = false
		var ending = false
		var reconnectAfterClose = false
		var microphoneMuted = false
		var speakersMuted = false
		var segments: [VoiceChatSegment] = []
		var pendingLegacySegments: [Bool: Int] = [:]
		var input: AsyncStream<Data>.Continuation?

		init(
			store: WorkspaceStateStore,
			server: AppServer,
			transport: Transport,
			allowsWebSocketFallback: Bool
		)
		{
			self.store = store
			self.server = server
			self.transport = transport
			self.allowsWebSocketFallback = allowsWebSocketFallback
			generation = server.connectionGeneration
		}

		var isConnected: Bool
		{
			!store.isRetired && server.connectionGeneration == generation
				&& store.model.connection.isConnected
		}
	}

	@MainActor
	private final class ReconnectTarget
	{
		weak var store: WorkspaceStateStore?
		let threadID: String
		let checkoutPath: String?
		let voice: String
		let microphoneMuted: Bool
		let speakersMuted: Bool

		init(
			call: Call,
			threadID: String,
			voice: String
		)
		{
			store = call.store
			self.threadID = threadID
			checkoutPath = call.store.model.identity.canonicalCheckoutPath
			self.voice = voice
			microphoneMuted = call.microphoneMuted
			speakersMuted = call.speakersMuted
		}
	}

	private struct AvailabilityScope: Equatable
	{
		let store: ObjectIdentifier
		let generation: UUID
		let path: String
		let accountType: String?
	}

	weak var webRTCHost: NSView?
	private var availabilityScope: AvailabilityScope?
	private var webRTCAvailable = false
	private var webSocketAvailable = false
	private var availabilityRefreshAfter = ContinuousClock.now
	private var availabilityTask: Task<Void, Never>?

	private let microphone = VoiceChatMicrophone()
	private let requestMicrophonePermission: @MainActor () async -> Bool
	private let makePeer: PeerFactory
	private let player = ReadAloudPCMPlayer()
	private var call: Call?
	private var reconnectTarget: ReconnectTarget?
	private var startupTimeout: Task<Void, Never>?
	private var audioTask: Task<Void, Never>?
	private var textTask: Task<Void, Never>?
	private var historyTask: Task<Void, Never>?
	private var transcriptPublication: Task<Void, Never>?
	private weak var historyStore: WorkspaceStateStore?
	private var historyThreadID: String?
	private var historyGeneration: UUID?
	private var history = VoiceChatHistory()
	private var historyWindow = AppServer.VoiceTimelineWindow()
	private var historyFailedCoverage: AppServer.VoiceTimelineWindow.Coverage?
	var onChange: (() -> Void)?
	var onPlaybackLevel: ((Double) -> Void)?
	var onThreadStarted: ((WorkspaceStateStore, String) -> Void)?

	init(
		requestMicrophonePermission: @escaping @MainActor () async -> Bool = VoiceChatMicrophone
			.requestPermission,
		makePeer: @escaping PeerFactory = VoiceChatWebRTC.init
	)
	{
		self.requestMicrophonePermission = requestMicrophonePermission
		self.makePeer = makePeer
	}

	var hasCall: Bool
	{
		call != nil
	}
	var threadID: String?
	{
		call?.threadID
	}
	func activeThread(in store: WorkspaceStateStore) -> ThreadSummary?
	{
		call?.store === store && call?.started == true ? call?.summary : nil
	}

	var microphoneMuted: Bool
	{
		call?.microphoneMuted == true
	}
	var speakersMuted: Bool
	{
		call?.speakersMuted == true
	}
	var acceptsText: Bool
	{
		call?.started == true && call?.ending == false && textTask == nil
	}

	func isShowingCall(
		store: WorkspaceStateStore,
		threadID: String?
	) -> Bool
	{
		guard let call, call.store === store, let threadID
		else
		{
			return false
		}
		return call.threadID == threadID
	}

	func refreshAvailability(store: WorkspaceStateStore)
	{
		let model = store.model
		guard model.connection.isConnected,
				let server = store.factoryDependencies.service as? AppServer,
				let path = model.identity.canonicalCheckoutPath
		else
		{
			availabilityTask?.cancel()
			availabilityTask = nil
			availabilityScope = nil
			webRTCAvailable = false
			webSocketAvailable = false
			return
		}
		let scope = AvailabilityScope(
			store: ObjectIdentifier(store),
			generation: server.connectionGeneration,
			path: path,
			accountType: model.preferences.accountStatus?.type
		)
		if scope != availabilityScope
		{
			availabilityTask?.cancel()
			availabilityTask = nil
			availabilityScope = scope
			webRTCAvailable = false
			webSocketAvailable = false
			availabilityRefreshAfter = .now
		}
		guard call == nil, availabilityTask == nil, .now >= availabilityRefreshAfter
		else
		{
			return
		}
		availabilityTask = Task
		{
			[weak self] in
			let directory = URL(fileURLWithPath: path)
			async let webRTC = Self.probeAvailability
			{
				guard scope.accountType == "chatgpt"
				else
				{
					return false
				}
				return try await server.chatGPTVoiceAvailable(in: directory)
			}
			async let webSocket = Self.probeAvailability
			{
				try await server.realtimeWebSocketAvailable(in: directory)
			}
			let options = await (webRTC, webSocket)
			guard let self, !Task.isCancelled, self.availabilityScope == scope,
					server.connectionGeneration == scope.generation
			else
			{
				return
			}
			self.availabilityTask = nil
			self.availabilityRefreshAfter = .now + .seconds(15)
			if self.webRTCAvailable != options.0 || self.webSocketAvailable != options.1
			{
				self.webRTCAvailable = options.0
				self.webSocketAvailable = options.1
				self.onChange?()
			}
		}
	}

	private static func probeAvailability(
		_ check: @MainActor @Sendable () async throws -> Bool
	) async -> Bool
	{
		do
		{
			return try await check()
		}
		catch
		{
			do
			{
				try await Task.sleep(for: .seconds(2))
				return try await check()
			}
			catch
			{
				return false
			}
		}
	}

	private func hasCurrentAvailability(for store: WorkspaceStateStore) -> Bool
	{
		guard let scope = availabilityScope,
				let server = store.factoryDependencies.service as? AppServer
		else
		{
			return false
		}
		return scope.store == ObjectIdentifier(store)
			&& scope.generation == server.connectionGeneration
			&& scope.path == store.model.identity.canonicalCheckoutPath
			&& scope.accountType == store.model.preferences.accountStatus?.type
	}

	private func canUseWebRTC(store: WorkspaceStateStore) -> Bool
	{
		webRTCAvailable && webRTCHost != nil && hasCurrentAvailability(for: store)
	}

	private func canUseWebSocket(store: WorkspaceStateStore) -> Bool
	{
		webSocketAvailable && hasCurrentAvailability(for: store)
	}

	func canStart(store: WorkspaceStateStore) -> Bool
	{
		let model = store.model
		let threadID = model.conversations.selectedConversation.threadID
		if let workspace = store.managedWorkspace, workspace.threadID == nil
			|| workspace.threadID != threadID
		{
			return false
		}
		return call == nil && !store.isRetired && model.connection.isConnected
			&& (canUseWebRTC(store: store) || canUseWebSocket(store: store))
			&& !model.conversations.showingArchived && model.lifecycle.quitReservation == nil
			&& model.lifecycle.cleanupReservation == nil
			&& threadID.map
			{
				!model.conversations.lockedThreadIDs.contains($0)
			} != false
			&& model.identity.canonicalCheckoutPath != nil
			&& store.factoryDependencies.service is AppServer
	}

	func canReconnect(store: WorkspaceStateStore) -> Bool
	{
		reconnectTarget(for: store) != nil && canStart(store: store)
	}

	private func reconnectTarget(for store: WorkspaceStateStore) -> ReconnectTarget?
	{
		guard let target = reconnectTarget, target.store === store,
				target.checkoutPath == store.model.identity.canonicalCheckoutPath,
				store.model.conversations.selectedConversation == .thread(target.threadID)
		else
		{
			return nil
		}
		return target
	}

	func start(store: WorkspaceStateStore)
	{
		guard canStart(store: store), let path = store.model.identity.canonicalCheckoutPath,
				let server = store.factoryDependencies.service as? AppServer
		else
		{
			return
		}
		let usesWebRTC = canUseWebRTC(store: store)
		let selection = store.model.conversations.selectedConversation
		let workspace = store.managedWorkspace
		let draftLifetime = store.model.composer.drafts[selection]?.lifetime
		store.inputs.stopReadAloud()
		let selectedModel = store.model.composerSelection
		let preferences = store.model.runPreferencesForSubmission
		let reconnect = reconnectTarget(for: store)
		reconnectTarget = reconnect
		let call = Call(
			store: store,
			server: server,
			transport: usesWebRTC ? .webRTC : .webSocket,
			allowsWebSocketFallback: canUseWebSocket(store: store)
		)
		call.microphoneMuted = reconnect?.microphoneMuted ?? false
		call.speakersMuted = reconnect?.speakersMuted ?? false
		self.call = call
		call.storeObserver = store.observe
		{
			[weak self, weak call] model in
			guard let self, let call, self.call === call
			else
			{
				return
			}
			let lostChatGPTSignIn = call.transport == .webRTC
				&& model.preferences.accountStatus?.type != "chatgpt"
			if model.identity.canonicalCheckoutPath != path
				|| model.lifecycle.quitReservation != nil || model.lifecycle
				.cleanupReservation != nil
				|| lostChatGPTSignIn
			{
				self.stop()
			}
			else if !call.isConnected
			{
				if call.server.connectionGeneration != call.generation
				{
					if !call.ending || call.reconnectAfterClose
					{
						self.rememberDroppedCall(call)
					}
					self.retire(call)
				}
				else
				{
					self.stop(call)
				}
			}
			else if call.started, let id = call.threadID,
					let turn = model.execution(for: .thread(id)).activeTurnID,
					turn != call.transcriptStartTurnID
			{
				call.voiceTurnIDs.insert(turn)
			}
		}
		onChange?()
		call.startupTask = Task
		{
			[weak self, weak call] in
			guard let self, let call
			else
			{
				return
			}
			guard await self.requestMicrophonePermission(), self.call === call,
					!call.ending, call.isConnected
			else
			{
				self.retire(call)
				return
			}
			do
			{
				self.watchForStartup(call)
				try await store.verifyWorkspace(workspace)
				try Task.checkCancellation()
				if let reconnect
				{
					call.voice = reconnect.voice
				}
				else
				{
					call.voice = try await server
						.realtimeVoiceForSession(in: URL(fileURLWithPath: path))
				}
				try Task.checkCancellation()
				let offer = try await self.prepareOffer(for: call)
				guard self.call === call, !call.ending, call.isConnected
				else
				{
					return
				}
				let summary = try await server.prepareVoiceChat(
					threadID: selection.threadID,
					projectPath: path,
					model: selectedModel.modelID,
					effort: selectedModel.effort,
					preferences: preferences
				)
				guard self.call === call, !call.ending, call.isConnected
				else
				{
					return
				}
				call.summary = summary
				call.transcriptStartTurnID = self.precedingTurnID(for: call)
				let id = summary.id
				if selection == .newChat
				{
					call.onStarted =
					{
						[weak self] in
						if store.model.conversations.selectedConversation == selection,
							store.model.composer.drafts[selection]?.lifetime == draftLifetime
						{
							self?.onThreadStarted?(store, id)
						}
						store.inputs.refreshThreads()
					}
				}
				server.voiceChatObservers[id] =
				{
					[weak self, weak call] event in
					if let call
					{
						self?.receive(
							event,
							for: call
						)
					}
				}
				self.startTransport(
					call,
					offer: call.transport == .webRTC ? offer : nil
				)
			}
			catch
			{
				self.stop(call)
			}
		}
	}

	func stop()
	{
		reconnectTarget = nil
		if let call
		{
			call.reconnectAfterClose = false
			stop(call)
		}
	}

	private func rememberDroppedCall(_ call: Call)
	{
		guard call.started, let threadID = call.threadID, let voice = call.voice
		else
		{
			return
		}
		reconnectTarget = ReconnectTarget(
			call: call,
			threadID: threadID,
			voice: voice
		)
	}

	private func stop(_ call: Call)
	{
		guard self.call === call, !call.ending
		else
		{
			return
		}
		call.ending = true
		stopAudio(for: call)
		textTask?.cancel()
		guard call.isConnected
		else
		{
			retire(call)
			return
		}
		if call.transport == .retiringWebRTC
		{
			onChange?()
			return
		}
		startupTimeout?.cancel()
		guard let id = call.threadID, call.startSubmitted
		else
		{
			retire(call)
			return
		}
		onChange?()
		Task
		{
			[weak self, weak call] in
			guard let self, let call, self.call === call
			else
			{
				return
			}
			do
			{
				await call.startRequest?.value
				guard self.call === call
				else
				{
					return
				}
				guard call.isConnected
				else
				{
					self.retire(call)
					return
				}
				try await call.server.stopVoiceChat(threadID: id)
				try await Task.sleep(for: .seconds(3))
			}
			catch
			{
			}
			self.retire(call)
		}
	}

	private func retire(_ call: Call)
	{
		guard self.call === call
		else
		{
			return
		}
		self.call = nil
		call.startupTask?.cancel()
		call.startRequest?.cancel()
		transcriptPublication?.cancel()
		transcriptPublication = nil
		if let id = call.threadID
		{
			call.server.voiceChatObservers.removeValue(forKey: id)
			if call.started, call.isConnected
			{
				call.store.inputs.refreshThreads()
			}
			if call.started, call.summary?.historyMode == "paginated", historyStore === call.store,
				historyThreadID == id
			{
				history.segments = mergingSegments(call.segments)
				history.voiceTurnIDs.formUnion(call.voiceTurnIDs)
				loadHistory(
					store: call.store,
					threadID: id,
					force: true
				)
			}
			else if call.started, call.isConnected, !call.segments.isEmpty,
					call.summary?.historyMode != "paginated",
					call.store.model.conversations.selectedConversation == .thread(id)
			{
				call.store.inputs.selectThread(id)
			}
		}
		if let observer = call.storeObserver
		{
			call.store.removeObserver(observer)
		}
		startupTimeout?.cancel()
		textTask?.cancel()
		textTask = nil
		stopAudio(for: call)
		onChange?()
	}

	func toggleMicrophone()
	{
		guard let call, call.started, !call.ending
		else
		{
			return
		}
		call.microphoneMuted.toggle()
		if let peer = call.peer
		{
			peer.setMuted(
				microphone: call.microphoneMuted,
				speakers: call.speakersMuted
			)
		}
		else if call.microphoneMuted
		{
			stopMicrophone(for: call)
		}
		else
		{
			let needsDuplexEngine = microphone.engine == nil
			startMicrophone(for: call)
			if needsDuplexEngine, !call.ending
			{
				player.useDuplexEngine(microphone.engine)
			}
		}
		onChange?()
	}

	func toggleSpeakers()
	{
		guard let call, !call.ending
		else
		{
			return
		}
		call.speakersMuted.toggle()
		if call.speakersMuted
		{
			onPlaybackLevel?(0)
		}
		if let peer = call.peer
		{
			if call.started
			{
				peer.setMuted(
					microphone: call.microphoneMuted,
					speakers: call.speakersMuted
				)
			}
		}
		else if call.speakersMuted
		{
			player.discardQueuedAudio()
		}
		onChange?()
	}

	func submit(
		_ text: String,
		clearingDraft: @escaping () -> Void
	)
	{
		guard acceptsText, let call, let id = call.threadID, call.isConnected,
				!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		else
		{
			return
		}
		textTask = Task
		{
			[weak self, weak call] in
			guard let self, let call, self.call === call, !call.ending, call.isConnected
			else
			{
				return
			}
			defer
			{
				if self.call === call
				{
					self.textTask = nil
					self.onChange?()
				}
			}
			do
			{
				try await call.server.appendVoiceText(
					threadID: id,
					text: text
				)
				if self.call === call, !call.ending
				{
					clearingDraft()
				}
			}
			catch
			{
			}
		}
		onChange?()
	}

	private func prepareOffer(for call: Call) async throws -> String?
	{
		guard call.transport == .webRTC
		else
		{
			return nil
		}
		do
		{
			return try await makeOffer(for: call)
		}
		catch
		{
			guard self.call === call, !call.ending, call.isConnected,
					call.allowsWebSocketFallback
			else
			{
				throw error
			}
			if call.transport == .webRTC
			{
				transportFailed(call)
			}
			return nil
		}
	}

	private func makeOffer(for call: Call) async throws -> String
	{
		guard let host = webRTCHost
		else
		{
			throw ReadAloudError.unavailable
		}
		let peer = makePeer(
			host,
			{
				[weak self, weak call] in
				guard let call, call.transport == .webRTC
				else
				{
					return
				}
				call.peerReady = true
				self?.completeStartup(call)
			},
			{
				[weak self, weak call] in
				if let call, call.transport == .webRTC
				{
					self?.transportFailed(call)
				}
			},
			{
				[weak self, weak call] level in
				self?.publishPlaybackLevel(
					level,
					for: call
				)
			}
		)
		call.peer = peer
		return try await peer.makeOffer()
	}

	private func applyAnswer(
		_ sdp: String,
		to call: Call
	)
	{
		guard let peer = call.peer, call.transport == .webRTC, !call.ending
		else
		{
			return
		}
		Task
		{
			[weak self, weak call] in
			do
			{
				try await peer.applyAnswer(sdp)
			}
			catch
			{
				if let call, call.peer === peer, call.transport == .webRTC
				{
					self?.transportFailed(call)
				}
			}
		}
	}

	private func startTransport(
		_ call: Call,
		offer: String?
	)
	{
		guard let id = call.threadID, let voice = call.voice
		else
		{
			return
		}
		let transport = call.transport
		call.startRequest = Task
		{
			[weak self, weak call] in
			guard let self, let call, self.call === call, !call.ending, call.isConnected,
					call.transport == transport
			else
			{
				return
			}
			do
			{
				call.startSubmitted = true
				try await call.server.startVoiceChat(
					threadID: id,
					sessionID: call.id,
					offer: offer,
					voice: voice
				)
			}
			catch
			{
				if call.transport == transport
				{
					self.transportFailed(call)
				}
			}
		}
	}

	private func transportFailed(_ call: Call)
	{
		guard self.call === call, !call.ending
		else
		{
			return
		}
		if call.started
		{
			call.reconnectAfterClose = true
			stop(call)
			return
		}
		guard call.transport == .webRTC, call.allowsWebSocketFallback,
				call.isConnected
		else
		{
			stop(call)
			return
		}
		call.peer?.close()
		call.peer = nil
		call.peerReady = false
		call.serverStarted = false
		guard call.startSubmitted, let startRequest = call.startRequest, let id = call.threadID
		else
		{
			call.transport = .webSocket
			watchForStartup(call)
			if call.threadID != nil
			{
				startTransport(
					call,
					offer: nil
				)
			}
			return
		}
		call.transport = .retiringWebRTC
		startupTimeout?.cancel()
		Task
		{
			[weak self, weak call] in
			// The start RPC may still be queued. Issue stop after it, then wait for its close
			// event before reusing the thread. The stop RPC response alone only queues the stop.
			await startRequest.value
			guard let self, let call, self.call === call, call.transport == .retiringWebRTC
			else
			{
				return
			}
			guard call.isConnected
			else
			{
				self.retire(call)
				return
			}
			do
			{
				try await call.server.stopVoiceChat(threadID: id)
				if self.call === call, call.transport == .retiringWebRTC
				{
					self.watchForStartup(call)
				}
			}
			catch
			{
				if call.transport == .retiringWebRTC
				{
					self.retire(call)
				}
			}
		}
	}

	private func completeStartup(_ call: Call)
	{
		guard self.call === call, !call.ending, !call.started, call.serverStarted,
				call.peer == nil || call.peerReady
		else
		{
			return
		}
		startupTimeout?.cancel()
		call.started = true
		reconnectTarget = nil
		if let peer = call.peer
		{
			peer.setMuted(
				microphone: call.microphoneMuted,
				speakers: call.speakersMuted
			)
		}
		else
		{
			if !call.microphoneMuted
			{
				startMicrophone(for: call)
			}
			if !call.ending
			{
				player.useDuplexEngine(microphone.engine)
				player.onPlaybackLevel =
				{
					[weak self, weak call] level in
					self?.publishPlaybackLevel(
						level,
						for: call
					)
				}
			}
		}
		if !call.ending
		{
			call.onStarted?()
		}
		call.onStarted = nil
		onChange?()
	}

	private func watchForStartup(_ call: Call)
	{
		startupTimeout?.cancel()
		startupTimeout = Task
		{
			[weak self, weak call] in
			do
			{
				try await Task.sleep(for: .seconds(15))
			}
			catch
			{
				return
			}
			guard let self, let call, self.call === call
			else
			{
				return
			}
			if call.transport == .retiringWebRTC
			{
				self.retire(call)
			}
			else
			{
				self.transportFailed(call)
			}
		}
	}

	private func receive(
		_ event: VoiceChatEvent,
		for call: Call
	)
	{
		guard self.call === call
		else
		{
			return
		}
		if call.transport == .retiringWebRTC
		{
			if case .requestedStop = event
			{
				if call.ending || !call.isConnected
				{
					retire(call)
				}
				else
				{
					call.transport = .webSocket
					call.startSubmitted = false
					watchForStartup(call)
					startTransport(
						call,
						offer: nil
					)
				}
			}
			return
		}
		switch event
		{
		case .started:
			call.serverStarted = true
			completeStartup(call)
		case .sdp(let sdp):
			applyAnswer(
				sdp,
				to: call
			)
		case .segment(var segment):
			let existingIndex = call.segments.firstIndex
			{
				$0.id == segment.id
			}
			if let existingIndex
			{
				segment.precedingTurnID = call.segments[existingIndex].precedingTurnID
				call.segments[existingIndex] = segment
			}
			else
			{
				segment.precedingTurnID = precedingTurnID(for: call)
				call.segments.append(segment)
			}
			publishTranscript()
			return
		case .transcriptDelta(
			let id,
			let text
		):
			if let index = call.segments.firstIndex(where:
				{
					$0.id == id
				})
			{
				call.segments[index].text += text
				publishTranscript()
			}
			return
		case .legacyTranscript(
			let isUser,
			let text,
			let isFinal
		):
			guard call.summary?.historyMode != "paginated"
			else
			{
				return
			}
			if let index = call.pendingLegacySegments[isUser]
			{
				if isFinal
				{
					if !text.isEmpty
					{
						call.segments[index].text = text
					}
					call.pendingLegacySegments.removeValue(forKey: isUser)
				}
				else
				{
					call.segments[index].text += text
				}
			}
			else if !text.isEmpty
			{
				if !isFinal
				{
					call.pendingLegacySegments[isUser] = call.segments.count
				}
				call.segments.append(VoiceChatSegment(
					id: UUID().uuidString,
					isUser: isUser,
					text: text,
					precedingTurnID: precedingTurnID(for: call)
				))
			}
			publishTranscript()
			return
		case .audio(let audio):
			if call.started, call.peer == nil, !call.speakersMuted, !call.ending
			{
				do
				{
					try player.enqueue(audio)
				}
				catch
				{
					player.stop()
					onPlaybackLevel?(0)
				}
			}
			return
		case .interrupted:
			player.discardQueuedAudio()
			onPlaybackLevel?(0)
			return
		case .failed:
			transportFailed(call)
			return
		case .closed:
			if call.ending, call.reconnectAfterClose,
				call.server.connectionGeneration == call.generation
			{
				// The explicit stop may still be queued for this same thread.
				return
			}
			if call.transport == .webRTC, !call.started, !call.ending
			{
				transportFailed(call)
			}
			else
			{
				if !call.ending || call.reconnectAfterClose
				{
					rememberDroppedCall(call)
				}
				retire(call)
			}
			return
		case .requestedStop:
			if call.reconnectAfterClose
			{
				rememberDroppedCall(call)
			}
			retire(call)
			return
		}
	}

	private func publishPlaybackLevel(
		_ level: Double,
		for call: Call?
	)
	{
		guard let call, self.call === call, call.started, !call.ending, !call.speakersMuted
		else
		{
			return
		}
		onPlaybackLevel?(level)
	}

	private func precedingTurnID(for call: Call) -> String?
	{
		guard let id = call.threadID
		else
		{
			return nil
		}
		let key = ConversationKey.thread(id)
		let model = call.store.model
		return model.execution(for: key).activeTurnID
			?? model.conversations.content[key]?.loadedTurns.last?.id
	}

	private func publishTranscript()
	{
		guard transcriptPublication == nil
		else
		{
			return
		}
		transcriptPublication = Task
		{
			[weak self] in
			do
			{
				try await Task.sleep(for: .milliseconds(50))
			}
			catch
			{
				return
			}
			self?.transcriptPublication = nil
			self?.onChange?()
		}
	}

	private func startMicrophone(for call: Call)
	{
		guard let id = call.threadID
		else
		{
			return
		}
		let (frames, input) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(8))
		call.input = input
		do
		{
			try microphone.start(output: input)
		}
		catch
		{
			stop(call)
			return
		}
		audioTask = Task
		{
			[weak self, weak call] in
			for await frame in frames
			{
				guard let self, let call, self.call === call, call.isConnected,
						!call.ending, !call.microphoneMuted, !Task.isCancelled
				else
				{
					return
				}
				do
				{
					try await call.server.appendVoiceAudio(
						threadID: id,
						pcm: frame
					)
				}
				catch
				{
					if !Task.isCancelled
					{
						self.transportFailed(call)
					}
					return
				}
			}
		}
	}

	private func stopMicrophone(for call: Call)
	{
		microphone.stopCapture()
		call.input?.finish()
		call.input = nil
		audioTask?.cancel()
		audioTask = nil
	}

	private func stopAudio(for call: Call)
	{
		call.peer?.close()
		stopMicrophone(for: call)
		player.onPlaybackLevel = nil
		player.useDuplexEngine(nil)
		microphone.stop()
		onPlaybackLevel?(0)
	}

	func loadHistory(
		store: WorkspaceStateStore,
		threadID: String?,
		force: Bool = false
	)
	{
		let server = store.factoryDependencies.service as? AppServer
		let generation = server?.connectionGeneration
		let hasPaginatedHistory = force || (isShowingCall(
			store: store,
			threadID: threadID
		)
			&& call?.summary?.historyMode == "paginated") || store.model.conversations.threads
			.contains
			{
				$0.id == threadID && $0.historyMode == "paginated"
			}
		let shouldRead = hasPaginatedHistory && store.model.connection.isConnected
		let historyID = shouldRead ? threadID : nil
		let scopeChanged = historyStore !== store || historyThreadID != historyID
			|| historyGeneration != generation
		if scopeChanged || force
		{
			historyTask?.cancel()
			historyTask = nil
			historyWindow = AppServer.VoiceTimelineWindow()
			historyFailedCoverage = nil
			if scopeChanged
			{
				history = VoiceChatHistory()
			}
			historyStore = store
			historyThreadID = historyID
			historyGeneration = generation
		}
		guard let threadID = historyID, let server, historyTask == nil
		else
		{
			return
		}

		let content = store.model.conversations.content[.thread(threadID)]
		guard force || content?.hasLoadedHistory == true
		else
		{
			return
		}
		let coverage: AppServer.VoiceTimelineWindow.Coverage
		if content?.hasLoadedHistory != true
		{
			coverage = .latest
		}
		else if content?.nextTurnsCursor == nil
		{
			coverage = .entireThread
		}
		else
		{
			coverage = content?.loadedTurns.first.map
			{
				.throughTurn($0.id)
			} ?? .latest
		}
		guard !historyWindow.covers(coverage), historyFailedCoverage != coverage
		else
		{
			return
		}
		let window = historyWindow
		historyTask = Task
		{
			[weak self, weak store] in
			let loaded = try? await server.loadVoiceTimeline(
				threadID: threadID,
				covering: coverage,
				extending: window
			)
			guard let self, let store, self.historyStore === store,
					self.historyThreadID == threadID, !Task.isCancelled,
					server.connectionGeneration == generation
			else
			{
				return
			}
			self.historyTask = nil
			self.historyFailedCoverage = loaded == nil ? coverage : nil
			if let loaded
			{
				self.historyWindow = loaded
				self.history = loaded.history
				self.onChange?()
			}
			// Normal turn history may have expanded while this request was in flight.
			self.loadHistory(
				store: store,
				threadID: threadID
			)
		}
	}

	func transcript(
		_ entries: [ConversationEntry],
		store: WorkspaceStateStore,
		threadID: String?
	) -> [ConversationEntry]
	{
		let hasHistory = historyStore === store && historyThreadID == threadID
		let saved = hasHistory ? history : VoiceChatHistory()
		guard isShowingCall(
			store: store,
			threadID: threadID
		), let call, let threadID
		else
		{
			return VoiceChatTranscript.present(
				entries,
				segments: saved.segments,
				hasCanonicalSpeech: !saved.segments.isEmpty,
				historyTurnIDs: saved.voiceTurnIDs,
				historicalTurnOrder: saved.orderedTurnIDs
			)
		}
		let turnIDs = entries.map
		{
			ConversationEntryIdentity.turnIDWithFallback($0.id)
		}
		var liveTurnIDs = call.voiceTurnIDs
		if let start = call.transcriptStartTurnID,
			let index = turnIDs.lastIndex(of: start)
		{
			liveTurnIDs.formUnion(turnIDs.dropFirst(index + 1))
		}
		if let activeTurn = store.model.execution(for: .thread(threadID)).activeTurnID,
			activeTurn != call.transcriptStartTurnID
		{
			liveTurnIDs.insert(activeTurn)
		}

		let paginated = call.summary?.historyMode == "paginated"
		let segments = hasHistory && paginated ? mergingSegments(call.segments) : call.segments
		return VoiceChatTranscript.present(
			entries,
			segments: segments,
			hasCanonicalSpeech: paginated && !segments.isEmpty,
			historyTurnIDs: saved.voiceTurnIDs,
			historicalTurnOrder: saved.orderedTurnIDs,
			liveTurnIDs: liveTurnIDs
		)
	}

	private func mergingSegments(_ live: [VoiceChatSegment]) -> [VoiceChatSegment]
	{
		var liveByID = Dictionary(uniqueKeysWithValues: live.map
		{
			($0.id, $0)
		})
		let saved = history.segments.map
		{
			var segment = $0
			if let update = liveByID.removeValue(forKey: segment.id)
			{
				segment.text = update.text
			}
			return segment
		}
		return saved + live.filter
		{
			liveByID[$0.id] != nil
		}
	}
}
