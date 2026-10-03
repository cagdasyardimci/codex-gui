import Testing

@testable import CodexGUI

@Suite
struct TransitionEasingTests
{
	@Test func fractionsOutsideCurvePassThrough()
	{
		for fraction in [-0.25, 0, 1, 1.25]
		{
			#expect(TransitionEasing.easeInEaseOut(fraction) == fraction)
		}
		#expect(TransitionEasing.easeInEaseOut(.nan).isNaN)
	}

	@Test func interiorSamplesPreserveTwelveStepCurve()
	{
		#expect(abs(TransitionEasing.easeInEaseOut(0.25) - 0.12906820777061512) < 1e-12)
		#expect(abs(TransitionEasing.easeInEaseOut(0.5) - 0.499816894534888) < 1e-12)
		#expect(abs(TransitionEasing.easeInEaseOut(0.75) - 0.8709317922293849) < 1e-12)
	}
}
