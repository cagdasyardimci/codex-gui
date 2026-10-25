import Foundation
import Testing

@testable import CodexGUI

@Suite(
	"Project productivity"
)
struct ProjectProductivityTests
{
	@Test("Explicitly included items alone appear in request context")
	func contextSelection()
	{
		var context = ProjectContext()
		context.items = [
			ProjectContextItem(
				kind: .note,
				title: "Selected",
				body: "Send this",
				isIncluded: true
			),
			ProjectContextItem(
				kind: .decision,
				title: "Private",
				body: "Do not send"
			),
			ProjectContextItem(
				kind: .referenceFile,
				title: "Reference",
				referencePath: "docs/a.md",
				isIncluded: true
			),
		]
		#expect(context.includedContextText.contains("Send this"))
		#expect(context.includedContextText.contains("docs/a.md"))
		#expect(!context.includedContextText.contains("Do not send"))
	}

	@Test(arguments: ["/old/review/SKILL.md", "/new/review/SKILL.md"])
	@MainActor
	func disabledSkillCannotResolveByExactPathOrRelocatedName(path: String) throws
	{
		var context = ProjectContext()
		context.selectedSkill = ProjectSkillSelection(
			name: "review",
			description: "Review code",
			path: "/old/review/SKILL.md"
		)
		let disabled = try #require(AvailableSkill(json: [
			"name": "review",
			"description": "Review code",
			"path": path,
			"scope": "repo",
			"enabled": false,
		]))
		let catalog = SkillCatalog(
			skills: [disabled],
			errors: []
		)

		#expect(ProjectProductivity.resolvedSkill(
			context: context,
			in: catalog
		) == nil)
		#expect(ProjectProductivity.skillWarning(
			context: context,
			in: catalog
		) == "Selected skill review is unavailable or disabled for this project.")
	}
}
