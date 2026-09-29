import Foundation

@MainActor
enum WorkspaceHydration
{
	static func restoreSourceStartup(_ store: WorkspaceStateStore)
	{
		store.dispatch(.workspaceLifecycle(.sourceStartupRequested(store.operationContext())))
	}

	static func initialize(_ store: WorkspaceStateStore)
	{
		guard store.model.identity.canonicalCheckoutPath != nil
		else
		{
			return
		}
		store.dispatch(.workspaceLifecycle(.initialHydrationRequested(store.operationContext())))
	}
}
