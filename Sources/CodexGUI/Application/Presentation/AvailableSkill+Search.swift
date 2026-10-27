import Foundation

extension AvailableSkill
{
	var searchText: SearchText
	{
		SearchText(terms: [name, displayName, description, shortDescription].compactMap
		{
			$0
		})
	}
}
