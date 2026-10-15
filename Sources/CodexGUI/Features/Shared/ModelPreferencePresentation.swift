import Foundation

enum ModelPreferencePresentation
{
	static func effortTitle(_ effort: String?) -> String
	{
		guard let effort
		else
		{
			return "Default effort"
		}
		switch effort.lowercased()
		{
		case "low": return "Light"
		case "medium": return "Medium"
		case "high": return "High"
		case "xhigh": return "Extra High"
		case "max": return "Max"
		case "ultra": return "Ultra"
		default: return effort.capitalized
		}
	}
}
