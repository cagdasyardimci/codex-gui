import Foundation

extension TurnInput
{
	static func protocolValues(
		for inputs: [TurnInput],
		skills: [SkillReference]
	) -> [[String: Any]]
	{
		let skillInvocations = skills.map
		{
			"$\($0.name)"
		}
		let invocation = skillInvocations.joined(separator: " ")

		var turnInputs = inputs
		if !invocation.isEmpty
		{
			if !turnInputs.isEmpty, case .text(let text) = turnInputs[0]
			{
				turnInputs[0] = .text("\(invocation) \(text)")
			}
			else
			{
				turnInputs.insert(
					.text(invocation),
					at: 0
				)
			}
		}

		var protocolInputs = turnInputs.map(\.protocolValue)
		protocolInputs += skills.map
		{
			["type": "skill", "name": $0.name, "path": $0.path]
		}
		return protocolInputs
	}

	var protocolValue: [String: Any]
	{
		switch self
		{
		case .text(let text):
			["type": "text", "text": text, "text_elements": []]
		case .mention(
			let name,
			let path
		):
			["type": "mention", "name": name, "path": path]
		case .localImage(let path):
			["type": "localImage", "path": path]
		}
	}
}
