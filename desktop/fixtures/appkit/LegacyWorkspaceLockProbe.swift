import Darwin
import Foundation

@main
struct LegacyWorkspaceLockProbe
{
	static func main()
	{
		let arguments = CommandLine.arguments
		let records = URL(fileURLWithPath: arguments[1])
		let action = arguments[2]
		let store = TaskWorkspaceStore(directory: records)
		do
		{
			if action == "running"
			{
				waitForRelease()
				return
			}
			try store.withExclusiveLock
			{
				if action == "holding"
				{
					waitForRelease()
				}
				else
				{
					let records = try store.loadAll()
					guard records.count == 1
					else
					{
						throw TaskWorkspaceError.storageFailure("fixture expected one record")
					}
					try store.save(records[0])
				}
			}
		}
		catch TaskWorkspaceError.storageFailure(let failure)
		{
			FileHandle.standardError.write(Data(failure.utf8))
			exit(23)
		}
		catch
		{
			FileHandle.standardError.write(Data(error.localizedDescription.utf8))
			exit(1)
		}
	}

	private static func waitForRelease()
	{
		FileHandle.standardOutput.write(Data("ready\n".utf8))
		_ = readLine()
	}
}
