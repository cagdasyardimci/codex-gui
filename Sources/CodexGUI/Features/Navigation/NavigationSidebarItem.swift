import Foundation

enum NavigationSidebarItem
{
	case sectionHeader(String)
	case pinnedThread(ThreadSummary)
	case project(URL)
	case thread(ThreadSummary)
	case showMore
}
