import Foundation

enum FileViewerDocumentStatus: Equatable, Sendable
{
	case loading
	case ready
	case failed(FileViewerFailure)
	case conflict
}

struct FileViewerDocument: Identifiable, Sendable
{
	let id: UUID
	let location: FileLocation
	var isRetained: Bool
	var content: FileViewerContent?
	var diskRevision: FileDiskRevision?
	var isReadOnly = false
	var status: FileViewerDocumentStatus = .loading
	var editRevision = 0
	var savedEditRevision = 0
	var requestedLine: Int?
	var lineRequestGeneration = 0
	var loadGeneration = 0
	var saveGeneration = 0
	var isSaving = false

	var isDirty: Bool
	{
		editRevision != savedEditRevision
	}

	var currentText: String?
	{
		if case .text(let text) = content
		{
			return text
		}
		if content == .empty
		{
			return ""
		}
		return nil
	}

	var canEdit: Bool
	{
		guard !isReadOnly, currentText != nil
		else
		{
			return false
		}
		if status == .ready
		{
			return true
		}
		if case .failed = status
		{
			return true
		}
		return false
	}
}

struct FileViewerState: Sendable
{
	var activeRoot: String?
	var documents: [FileViewerDocument] = []
	var selectedDocumentID: UUID?
	var previewDocumentID: UUID?
	var directoryEntries: [FileLocation: [FileViewerDirectoryEntry]] = [:]
	var directoryFailures: [FileLocation: FileViewerFailure] = [:]
	var directoryRequests: [FileLocation: UUID] = [:]
	var filenameResults: FileViewerSearchPage<FileLocation>?
	var contentResults: FileViewerSearchPage<FileViewerSearchResult>?
	var searchFailure: FileViewerFailure?
	var searchRequest: UUID?
	var generation = 0

	var selectedDocument: FileViewerDocument?
	{
		documents.first
		{
			$0.id == selectedDocumentID
		}
	}
}
