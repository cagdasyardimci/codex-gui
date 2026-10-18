import Foundation

struct ContextNavigationModel
{
	var projectContext = ProjectContext()
	var contextError: String?
	var contextRevision = 0
	var pendingContextLoad: ContextLoadOperation?
	var pendingContextSave: ContextSaveOperation?
	var skillCatalog: SkillCatalog?
	var skillError: String?
	var pendingSkillRefresh: SkillsRefreshOperation?
	var skillRefreshPending = false
	var messageSearch: MessageSearchResults?
	var messageSearchContext: OperationContext?
	var pendingMessageSearch: MessageSearchOperation?
	var searchIndexSource: MessageSearchIndexSource?
	var searchableThreads: [SearchableThread] = []
	var searchIndexRevision = 0
	var navigationTargets: [ConversationJumpTarget] = []
	var pendingSearch: NavigationSearchOperation?
	var searchError: String?
	var pendingJump: ConversationJumpOperation?
	var jumpError: String?
}
