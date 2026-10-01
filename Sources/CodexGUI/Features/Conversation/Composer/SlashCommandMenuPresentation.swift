import AppKit

struct SlashCommandMenuPresentation
{
	let title: String
	let symbol: String
	let opensPicker: Bool

	init(_ id: SlashCommandID)
	{
		switch id
		{
		case .new: (title, symbol) = ("New chat", "bubble.left")
		case .resume: (title, symbol) = ("Resume", "clock.arrow.circlepath")
		case .fork: (title, symbol) = ("Fork chat", "arrow.triangle.branch")
		case .rename: (title, symbol) = ("Rename", "pencil")
		case .archive: (title, symbol) = ("Archive", "archivebox")
		case .delete: (title, symbol) = ("Delete", "trash")
		case .compact: (title, symbol) = ("Compact", "circle.dashed")
		case .review: (title, symbol) = ("Code review", "checklist")
		case .model: (title, symbol) = ("Model", "cube")
		case .reasoning: (title, symbol) = ("Reasoning", "brain")
		case .fast: (title, symbol) = ("Fast", "bolt")
		case .permissions: (title, symbol) = ("Permissions", "checkmark.shield")
		case .plan: (title, symbol) = ("Plan mode", "lightbulb")
		case .status: (title, symbol) = ("Status", "info.circle")
		case .skills: (title, symbol) = ("Skills", "shippingbox")
		case .mention: (title, symbol) = ("Mention", "paperclip")
		case .diff: (title, symbol) = ("Diff", "doc.text.magnifyingglass")
		case .copy: (title, symbol) = ("Copy", "doc.on.doc")
		}
		opensPicker = [.resume, .review, .model, .reasoning, .permissions, .skills, .mention]
			.contains(id)
	}
}
