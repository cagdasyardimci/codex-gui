import Foundation

/// Providers project their canonical records; unavailable is distinct from a known empty value.
enum SummarySection<Value: Equatable>: Equatable
{
	case unavailable(String)
	case loading(previous: Value?)
	case available(Value)
	case failed(
		String,
		previous: Value?
	)

	var value: Value?
	{
		switch self
		{
		case .available(let value): value
		case .loading(let previous), .failed(
			_,
			let previous
		): previous
		case .unavailable: nil
		}
	}

	var message: String?
	{
		switch self
		{
		case .unavailable(let reason), .failed(
			let reason,
			_
		): reason
		case .loading: "Loading…"
		case .available: nil
		}
	}
}
