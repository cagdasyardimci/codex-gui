/// Cubic Bézier easing shared by pane transitions.
enum TransitionEasing
{
	/// Evaluates (0.42, 0)–(0.58, 1) with 12 bisection steps.
	/// Fractions outside (0, 1) pass through unchanged.
	static func easeInEaseOut(_ fraction: Double) -> Double
	{
		guard fraction > 0, fraction < 1
		else
		{
			return fraction
		}
		var lower = 0.0
		var upper = 1.0
		for _ in 0 ..< 12
		{
			let parameter = (lower + upper) / 2
			let inverse = 1 - parameter
			let time = 3 * inverse * inverse * parameter * 0.42
				+ 3 * inverse * parameter * parameter * 0.58 + parameter * parameter * parameter
			if time < fraction
			{
				lower = parameter
			}
			else
			{
				upper = parameter
			}
		}
		let parameter = (lower + upper) / 2
		return 3 * (1 - parameter) * parameter * parameter + parameter * parameter * parameter
	}
}
