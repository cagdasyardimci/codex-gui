import Testing

@testable import CodexGUI

@Suite
struct MarkdownImagePreparationTests
{
	@Test func preloadPlanKeepsFirstUniquePathsWithinPixelBudget()
	{
		let paths = ["first.png", "second.png", "first.png"]
			+ (0 ..< 10_000).map
			{
				"image-\($0).png"
			}
		let run = MarkdownTextRun(
			text: "\u{FFFC}",
			style: MarkdownTextStyle(richBlock: MarkdownRichBlock(
				kind: .imageGallery,
				source: "source",
				payload: "",
				imagePaths: paths
			))
		)
		let plan = MarkdownImagePreparation.preloadPlan(in: [run])
		#expect(plan.paths.count == 32)
		#expect(Array(plan.paths.prefix(3)) == ["first.png", "second.png", "image-0.png"])
		#expect(Set(plan.paths).count == plan.paths.count)
		#expect(plan.paths.last == "image-29.png")
		#expect(plan.maximumPixelSize > 0)
		#expect(plan.paths.count * plan.maximumPixelSize * plan.maximumPixelSize
			<= 1_900_000)
		for count in [0, 1, 2, 3, 31, 32, 33, 100, 10_000]
		{
			let selected = Array(paths.prefix(count))
			let candidate = MarkdownTextRun(
				text: "\u{FFFC}",
				style: MarkdownTextStyle(richBlock: MarkdownRichBlock(
					kind: .imageGallery,
					source: "source",
					payload: "",
					imagePaths: selected
				))
			)
			let admitted = MarkdownImagePreparation.preloadPlan(in: [candidate])
			#expect(admitted.paths.count <= 32)
			#expect(admitted.paths.count * admitted.maximumPixelSize
				* admitted.maximumPixelSize <= 1_900_000)
		}
	}
}
