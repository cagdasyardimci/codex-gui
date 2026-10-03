import Foundation

enum TurnInput: Equatable
{
	case text(String)
	case mention(
		name: String,
		path: String
	)
	case localImage(path: String)
}
