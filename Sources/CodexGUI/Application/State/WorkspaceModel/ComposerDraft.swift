import Foundation

struct ComposerDraft: Equatable
{
	var text = ""
	var context: [ComposerContextItem] = []
	/// Supplied by draft actions, so acknowledging an earlier edit cannot clear a later edit.
	var revision = 0
	/// Distinguishes explicit New Chat interactions and later draft adoption.
	var lifetime = 0
}
