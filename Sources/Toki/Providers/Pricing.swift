import Foundation

/// Anthropic list price for one model, in USD per million tokens.
///
/// Cache pricing is derived from the input rate by fixed multipliers:
/// a 5-minute cache write costs 1.25x input, a 1-hour write 2x, and a read 0.1x.
struct ModelPrice: Sendable {
    let inputPerMTok: Double
    let outputPerMTok: Double

    var cacheWrite5mPerMTok: Double { inputPerMTok * 1.25 }
    var cacheWrite1hPerMTok: Double { inputPerMTok * 2.0 }
    var cacheReadPerMTok: Double { inputPerMTok * 0.1 }
}

/// Model-id to list-price lookup.
///
/// These are standard first-party API list prices. Claude Code subscription usage
/// is not billed per token, so the cost this produces is a "what this would have
/// cost on the API" equivalent, not an invoice amount. Sonnet 5 also carries a
/// promotional $2/$10 rate through 2026-08-31; the standard rate is used here so
/// the equivalent stays stable once the promotion ends.
enum Pricing {
    private static let millionTokens = 1_000_000.0

    /// Longest matching prefix wins, so `claude-opus-5` beats `claude-opus-4`,
    /// and suffixed ids such as `claude-opus-5[1m]` still resolve.
    private static let table: [(prefix: String, price: ModelPrice)] = [
        ("claude-fable-5", ModelPrice(inputPerMTok: 10, outputPerMTok: 50)),
        ("claude-mythos", ModelPrice(inputPerMTok: 10, outputPerMTok: 50)),
        ("claude-opus-5", ModelPrice(inputPerMTok: 5, outputPerMTok: 25)),
        ("claude-opus-4", ModelPrice(inputPerMTok: 5, outputPerMTok: 25)),
        ("claude-opus-3", ModelPrice(inputPerMTok: 15, outputPerMTok: 75)),
        ("claude-sonnet-5", ModelPrice(inputPerMTok: 3, outputPerMTok: 15)),
        ("claude-sonnet-4", ModelPrice(inputPerMTok: 3, outputPerMTok: 15)),
        ("claude-haiku-4", ModelPrice(inputPerMTok: 1, outputPerMTok: 5)),
        ("claude-haiku-3", ModelPrice(inputPerMTok: 0.25, outputPerMTok: 1.25))
    ]

    /// Unrecognised models are priced at the Opus tier rather than dropped, so a
    /// newly released model under-reports nothing.
    static let unknownModelFallback = ModelPrice(inputPerMTok: 5, outputPerMTok: 25)

    static func price(forModel model: String) -> ModelPrice {
        let normalized = model.lowercased()
        let best = table
            .filter { normalized.hasPrefix($0.prefix) }
            .max { $0.prefix.count < $1.prefix.count }
        return best?.price ?? unknownModelFallback
    }

    static func costUSD(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheWrite5mTokens: Int,
        cacheWrite1hTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        let price = price(forModel: model)
        let weighted =
            Double(inputTokens) * price.inputPerMTok
            + Double(outputTokens) * price.outputPerMTok
            + Double(cacheWrite5mTokens) * price.cacheWrite5mPerMTok
            + Double(cacheWrite1hTokens) * price.cacheWrite1hPerMTok
            + Double(cacheReadTokens) * price.cacheReadPerMTok
        return weighted / millionTokens
    }
}
