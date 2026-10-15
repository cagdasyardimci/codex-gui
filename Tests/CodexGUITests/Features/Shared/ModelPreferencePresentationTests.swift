import Testing

@testable import CodexGUI

struct ModelPreferencePresentationTests
{
	@Test func effortTitlesPreserveDefaultKnownAndUnknownPresentation()
	{
		#expect(ModelPreferencePresentation.effortTitle(nil) == "Default effort")
		#expect(ModelPreferencePresentation.effortTitle("low") == "Light")
		#expect(ModelPreferencePresentation.effortTitle("MEDIUM") == "Medium")
		#expect(ModelPreferencePresentation.effortTitle("High") == "High")
		#expect(ModelPreferencePresentation.effortTitle("xhigh") == "Extra High")
		#expect(ModelPreferencePresentation.effortTitle("max") == "Max")
		#expect(ModelPreferencePresentation.effortTitle("ULTRA") == "Ultra")
		#expect(ModelPreferencePresentation.effortTitle("minimal") == "Minimal")
		#expect(ModelPreferencePresentation.effortTitle("CUSTOM EFFORT") == "Custom Effort")
		#expect(ModelPreferencePresentation.effortTitle("") == "")
	}
}
