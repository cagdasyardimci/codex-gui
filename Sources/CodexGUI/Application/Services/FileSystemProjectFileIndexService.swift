import Foundation

protocol ProjectFileIndexService: Sendable
{
	func load(projectPath: String) async -> ProjectFileIndex?
}

struct FileSystemProjectFileIndexService: ProjectFileIndexService
{
	func load(projectPath: String) async -> ProjectFileIndex?
	{
		let indexingTask = Task.detached(priority: .userInitiated)
		{
			Self.enumerate(projectPath: projectPath)
		}
		return await withTaskCancellationHandler
		{
			await indexingTask.value
		} onCancel:
		{
			indexingTask.cancel()
		}
	}

	private static func enumerate(projectPath: String) -> ProjectFileIndex?
	{
		let projectRoot = URL(fileURLWithPath: projectPath)
		guard let enumerator = FileManager.default.enumerator(atPath: projectRoot.path)
		else
		{
			return ProjectFileIndex(files: [])
		}
		let maximumIndexedFiles = 50_000
		var files: [String] = []
		var isReusableWithProjectObservation = true
		while let relativePath = enumerator.nextObject() as? String,
				files.count < maximumIndexedFiles
		{
			if Task.isCancelled
			{
				return nil
			}
			let name = URL(fileURLWithPath: relativePath).lastPathComponent
			// Inspect the link itself before checking whether its destination currently exists.
			let fileType = enumerator.fileAttributes?[.type] as? FileAttributeType
			let isSymbolicLink = fileType == .typeSymbolicLink
			var isDirectory: ObjCBool = false
			let exists = FileManager.default.fileExists(
				atPath: projectRoot.appendingPathComponent(relativePath).path,
				isDirectory: &isDirectory
			)
			if isSymbolicLink, !name.hasPrefix(".")
			{
				let targetIsIgnoredDirectory = exists && isDirectory.boolValue
					&& ProjectFileIndexPathPolicy.ignoresDirectory(named: name)
				if !targetIsIgnoredDirectory
				{
					// External link targets can change without an event inside the checkout.
					isReusableWithProjectObservation = false
				}
			}
			guard exists
			else
			{
				continue
			}
			if isDirectory.boolValue
			{
				if ProjectFileIndexPathPolicy.ignoresDirectory(named: name)
				{
					enumerator.skipDescendants()
				}
				continue
			}
			guard !name.hasPrefix(".")
			else
			{
				continue
			}
			files.append(relativePath)
		}
		guard !Task.isCancelled
		else
		{
			return nil
		}
		return ProjectFileIndex(
			files: files.sorted(),
			isReusableWithProjectObservation: isReusableWithProjectObservation
		)
	}
}
