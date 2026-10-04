import CoreServices
import Darwin
import Foundation

protocol ProjectFileIndexObservation: Sendable
{
	var isCurrent: Bool
	{
		get
	}

	func cancel()
}

@MainActor
protocol ProjectFileIndexMonitoring
{
	func watch(
		projectPath: String,
		onChange: @escaping @MainActor () -> Void
	) -> (any ProjectFileIndexObservation)?
}

/// FSEvents observes descendants too, including changes below already existing directories.
struct FileSystemProjectFileIndexMonitor: ProjectFileIndexMonitoring
{
	func watch(
		projectPath: String,
		onChange: @escaping @MainActor () -> Void
	) -> (any ProjectFileIndexObservation)?
	{
		let maximumBindingAttempts = 2
		for _ in 0 ..< maximumBindingAttempts
		{
			guard let scope = ProjectFileIndexWatchScope.capture(projectPath: projectPath),
					let observation = FSEventsProjectFileIndexObservation(
					scope: scope,
					onChange: onChange
					)
			else
			{
				return nil
			}
			if observation.isCurrent
			{
				return observation
			}
			// A path changed during subscription setup; retire it before trying the new root.
			observation.cancel()
		}
		return nil
	}
}

private final class ProjectFileIndexEventHandler: Sendable
{
	let root: String
	let onChange: @MainActor () -> Void

	init(
		root: String,
		onChange: @escaping @MainActor () -> Void
	)
	{
		self.root = root
		self.onChange = onChange
	}

	func receive(
		paths: [String],
		flags: UnsafePointer<FSEventStreamEventFlags>
	)
	{
		let rescanFlags = FSEventStreamEventFlags(
			kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
				| kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount
		)
		let filenameFlags = FSEventStreamEventFlags(
			kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved
				| kFSEventStreamEventFlagItemRenamed
		)
		let prefix = root.hasSuffix("/") ? root : root + "/"
		for (index, path) in paths.enumerated()
		{
			let eventFlags = flags[index]
			let needsRescan = eventFlags & rescanFlags != 0
			guard needsRescan || eventFlags & filenameFlags != 0
			else
			{
				continue
			}
			if !needsRescan
			{
				guard path.hasPrefix(prefix),
						ProjectFileIndexPathPolicy.includes(
						relativePath: String(path.dropFirst(prefix.count)),
						isDirectory: eventFlags & FSEventStreamEventFlags(
							kFSEventStreamEventFlagItemIsDir
						) != 0
						)
				else
				{
					continue
				}
			}
			Task
			{
				@MainActor in onChange()
			}
			return
		}
	}
}

/// Cancellation may run from a runtime's deinitializer, so stream teardown is synchronized.
private final class FSEventsProjectFileIndexObservation: ProjectFileIndexObservation,
	@unchecked Sendable
{
	private let lock = NSLock()
	private let scope: ProjectFileIndexWatchScope
	private var stream: FSEventStreamRef?
	private var rootParentObservers: [DispatchSourceFileSystemObject]

	var isCurrent: Bool
	{
		let isActive = lock.withLock
		{
			!rootParentObservers.isEmpty
		}
		return isActive && scope.isCurrent
	}

	init?(
		scope: ProjectFileIndexWatchScope,
		onChange: @escaping @MainActor () -> Void
	)
	{
		guard let parentObservers = Self.observeRootParents(
			scope: scope,
			onChange: onChange
		)
		else
		{
			return nil
		}
		self.scope = scope
		rootParentObservers = parentObservers
		if let root = scope.root
		{
			guard let stream = Self.makeEventStream(
				root: root.path,
				onChange: onChange
			)
			else
			{
				for observer in parentObservers
				{
					observer.cancel()
				}
				return nil
			}
			self.stream = stream
		}
	}

	private static func observeRootParents(
		scope: ProjectFileIndexWatchScope,
		onChange: @escaping @MainActor () -> Void
	) -> [DispatchSourceFileSystemObject]?
	{
		var observers: [DispatchSourceFileSystemObject] = []
		for parent in scope.parentDirectories
		{
			let descriptor = open(
				parent.path,
				O_EVTONLY | O_CLOEXEC
			)
			guard descriptor >= 0
			else
			{
				for observer in observers
				{
					observer.cancel()
				}
				return nil
			}
			let observer = DispatchSource.makeFileSystemObjectSource(
				fileDescriptor: descriptor,
				eventMask: [.write, .delete, .rename, .revoke],
				queue: .main
			)
			observer.setEventHandler
			{
				// Parent writes also report unrelated sibling changes; only path changes reload.
				guard !scope.isCurrent
				else
				{
					return
				}
				Task
				{
					@MainActor in onChange()
				}
			}
			observer.setCancelHandler
			{
				close(descriptor)
			}
			observer.activate()
			observers.append(observer)
		}
		return observers
	}

	private static func makeEventStream(
		root: String,
		onChange: @escaping @MainActor () -> Void
	) -> FSEventStreamRef?
	{
		let handler = ProjectFileIndexEventHandler(
			root: root,
			onChange: onChange
		)
		// Keep the managed reference alive until the stream retains its callback context.
		defer
		{
			withExtendedLifetime(handler)
			{
			}
		}
		var context = FSEventStreamContext(
			version: 0,
			info: Unmanaged.passUnretained(handler).toOpaque(),
			retain:
			{
				info in
				guard let info
				else
				{
					return nil
				}
				return UnsafeRawPointer(Unmanaged<ProjectFileIndexEventHandler>
					.fromOpaque(info).retain().toOpaque())
			},
			release:
			{
				info in
				guard let info
				else
				{
					return
				}
				Unmanaged<ProjectFileIndexEventHandler>.fromOpaque(info).release()
			},
			copyDescription: nil
		)
		guard let stream = FSEventStreamCreate(
			kCFAllocatorDefault,
			{
				_, info, _, eventPaths, eventFlags, _ in
				guard let info,
						let paths = Unmanaged<CFArray>.fromOpaque(eventPaths)
						.takeUnretainedValue() as? [String]
				else
				{
					return
				}
				Unmanaged<ProjectFileIndexEventHandler>.fromOpaque(info)
					.takeUnretainedValue().receive(
						paths: paths,
						flags: eventFlags
					)
			},
			&context,
			[root] as CFArray,
			FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
			0.1,
			FSEventStreamCreateFlags(
				kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
					| kFSEventStreamCreateFlagWatchRoot
			)
		)
		else
		{
			return nil
		}
		FSEventStreamSetDispatchQueue(
			stream,
			.main
		)
		guard FSEventStreamStart(stream)
		else
		{
			FSEventStreamInvalidate(stream)
			FSEventStreamRelease(stream)
			return nil
		}
		return stream
	}

	deinit
	{
		cancel()
	}

	func cancel()
	{
		lock.lock()
		let stream = stream
		let parentObservers = rootParentObservers
		self.stream = nil
		rootParentObservers = []
		lock.unlock()
		for observer in parentObservers
		{
			observer.cancel()
		}
		guard let stream
		else
		{
			return
		}
		FSEventStreamStop(stream)
		FSEventStreamInvalidate(stream)
		FSEventStreamRelease(stream)
	}
}
