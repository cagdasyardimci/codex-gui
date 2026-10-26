import Foundation

struct AccountStatus: Equatable
{
	let type: String?
	let email: String?
	let requiresOpenAIAuth: Bool
	var planType: String? = nil

	var description: String
	{
		switch type
		{
		case "chatgpt":
			if let email
			{
				return "Signed in as \(email)"
			}
			return "Signed in with ChatGPT"
		case "apiKey": return "Signed in with API key"
		case "amazonBedrock": return "Signed in with Amazon Bedrock"
		case nil: return requiresOpenAIAuth ? "Sign in required" : "Authentication is not required"
		default: return "Signed in: \(type ?? "unknown")"
		}
	}
}
