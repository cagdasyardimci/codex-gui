/// Keeps thumbnail requests within the rich Markdown image pixel budget.
enum MarkdownImagePreparation
{
	struct PreloadPlan
	{
		let paths: [String]
		let maximumPixelSize: Int
	}

	private static let maximumUniquePaths = 32
	private static let maximumPixels = 1_900_000

	static func preloadPlan(in runs: [MarkdownTextRun]) -> PreloadPlan
	{
		var paths: [String] = []
		var seen: Set<String> = []
		for run in runs where run.text == "\u{FFFC}"
		{
			for path in run.style.richBlock?.imagePaths ?? []
			{
				guard seen.insert(path).inserted
				else
				{
					continue
				}
				paths.append(path)
				if paths.count == maximumUniquePaths
				{
					return plan(for: paths)
				}
			}
		}
		return plan(for: paths)
	}

	private static func plan(for paths: [String]) -> PreloadPlan
	{
		let maximumPixelSize = min(
			800,
			max(
				160,
				Int((Double(maximumPixels) / Double(max(
					1,
					paths.count
				))).squareRoot())
			)
		)
		return PreloadPlan(
			paths: paths,
			maximumPixelSize: maximumPixelSize
		)
	}
}
