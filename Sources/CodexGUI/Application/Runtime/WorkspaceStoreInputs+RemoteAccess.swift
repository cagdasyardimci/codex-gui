import Foundation

extension WorkspaceStoreInputs
{
	func remoteAccess(_ command: RemoteAccessCommand)
	{
		store.dispatch(.remoteAccess(.requested(
			store.operationContext(),
			command,
			store.now()
		)))
	}
}
