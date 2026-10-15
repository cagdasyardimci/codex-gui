import Foundation

enum ApprovalMode: String, CaseIterable, Codable, Equatable
{
	case askForApproval
	case approveForMe
	case fullAccess
}
