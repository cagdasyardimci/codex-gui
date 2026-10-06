import Foundation
import Testing

@testable import CodexGUI

@Suite("Project productivity")
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

	@Test("Coordinator resolves a selected skill only from the current enabled catalog")
	@MainActor
	func selectedSkillResolution() throws
	{
		var context = ProjectContext()
		context.selectedSkill = ProjectSkillSelection(
			name: "review",
			description: "Review code",
			path: "/old/review/SKILL.md"
		)
		let available = try #require(
			AvailableSkill(json: [
				"name": "review",
				"description": "Review code",
				"path": "/new/review/SKILL.md",
				"scope": "repo",
				"enabled": true,
			])
		)
		let catalog = SkillCatalog(
			skills: [available],
			errors: []
		)

		#expect(ProjectProductivity.resolvedSkill(
			context: context,
			in: catalog
		)?
			.path == "/new/review/SKILL.md")
		#expect(ProjectProductivity.skillWarning(
			context: context,
			in: catalog
		) == nil)
		#expect(ProjectProductivity.resolvedSkill(
			context: context,
			in: nil
		) == nil)
		#expect(ProjectProductivity.skillWarning(
			context: context,
			in: nil
		) != nil)
	}
}
