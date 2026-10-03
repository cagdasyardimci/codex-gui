import Foundation

enum GitSummaryEffect
{
	case cancelRead
	case read(GitComparisonRequest)
}
