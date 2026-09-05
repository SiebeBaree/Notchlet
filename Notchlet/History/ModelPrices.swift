import Foundation

/// Dollars per million tokens at API list price: a value, never a bill.
nonisolated struct ModelPrice: Hashable, Sendable {
    var input: Double
    var output: Double
    var cacheRead: Double
    var cacheWrite5m: Double
    var cacheWrite1h: Double

    func cost(of tokens: TokenCount) -> Double {
        (Double(tokens.input) * input
            + Double(tokens.cacheRead) * cacheRead
            + Double(tokens.cacheWrite5m) * cacheWrite5m
            + Double(tokens.cacheWrite1h) * cacheWrite1h
            + Double(tokens.output) * output) / 1_000_000
    }

    /// Cache reads at 10% of input, 5-minute writes at 125%, 1-hour writes
    /// at 200%, the same for every model.
    static func anthropic(input: Double, output: Double) -> ModelPrice {
        ModelPrice(
            input: input,
            output: output,
            cacheRead: input / 10,
            cacheWrite5m: input * 1.25,
            cacheWrite1h: input * 2
        )
    }

    /// Cache writes are ordinary input.
    static func openAI(input: Double, output: Double, cacheRead: Double) -> ModelPrice {
        ModelPrice(input: input, output: output, cacheRead: cacheRead, cacheWrite5m: input, cacheWrite1h: input)
    }

    static func cursor(input: Double, output: Double, cacheRead: Double, cacheWrite: Double) -> ModelPrice {
        ModelPrice(
            input: input,
            output: output,
            cacheRead: cacheRead,
            cacheWrite5m: cacheWrite,
            cacheWrite1h: cacheWrite
        )
    }
}

/// Lookup is exact after normalizing, never fuzzy: a guess between
/// `gpt-5.7` and `gpt-5.7-mini` would be off by a factor of five, so an
/// unpriced model is named in the pane instead. Kept by hand because the
/// public catalogs lag new models by weeks. Sources: each vendor's pricing
/// page, cross-checked against LiteLLM and OpenUsage, September 2026.
nonisolated enum ModelPrices {
    static func price(for model: String) -> ModelPrice? {
        table[normalize(model)]
    }

    /// What the CLI reported, else the table.
    static func cost(of row: DailyUsage) -> Double? {
        if let reported = row.reportedCost {
            return reported
        }
        guard let model = row.model, let price = price(for: model) else { return nil }
        return price.cost(of: row.tokens)
    }

    /// `anthropic/claude-sonnet-4-5-20250929[1m]` becomes
    /// `claude-sonnet-4-5`.
    static func normalize(_ model: String) -> String {
        var name = model.lowercased().trimmingCharacters(in: .whitespaces)
        for prefix in ["anthropic/", "openai/", "anthropic."] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        name = name.replacingOccurrences(of: "[1m]", with: "")
        name = name.replacingOccurrences(of: #"[-@](\d{8}|\d{4}-\d{2}-\d{2})$"#, with: "", options: .regularExpression)
        return name
    }

    static let table: [String: ModelPrice] = [
        // Anthropic. Opus 4 and 4.1 were the last at the old rate.
        "claude-opus-4": .anthropic(input: 15, output: 75),
        "claude-opus-4-1": .anthropic(input: 15, output: 75),
        "claude-opus-4-5": .anthropic(input: 5, output: 25),
        "claude-opus-4-6": .anthropic(input: 5, output: 25),
        "claude-opus-4-7": .anthropic(input: 5, output: 25),
        "claude-opus-4-7-fast": .anthropic(input: 30, output: 150),
        "claude-opus-4-8": .anthropic(input: 5, output: 25),
        "claude-opus-4-8-fast": .anthropic(input: 10, output: 50),
        "claude-opus-5": .anthropic(input: 5, output: 25),
        "claude-opus-5-fast": .anthropic(input: 10, output: 50),
        "claude-sonnet-4": .anthropic(input: 3, output: 15),
        "claude-sonnet-4-5": .anthropic(input: 3, output: 15),
        "claude-sonnet-4-6": .anthropic(input: 3, output: 15),
        "claude-sonnet-5": .anthropic(input: 3, output: 15),
        "claude-haiku-4-5": .anthropic(input: 1, output: 5),
        "claude-3-5-haiku": .anthropic(input: 0.8, output: 4),
        "claude-3-5-sonnet": .anthropic(input: 3, output: 15),
        "claude-3-7-sonnet": .anthropic(input: 3, output: 15),
        "claude-fable-5": .anthropic(input: 10, output: 50),
        "claude-fable-5-1": .anthropic(input: 10, output: 50),

        // OpenAI. Codex logs the bare model id from its config.
        "gpt-4o": .openAI(input: 2.5, output: 10, cacheRead: 1.25),
        "gpt-4.1": .openAI(input: 2, output: 8, cacheRead: 0.5),
        "gpt-4.1-mini": .openAI(input: 0.4, output: 1.6, cacheRead: 0.1),
        "gpt-4.1-nano": .openAI(input: 0.1, output: 0.4, cacheRead: 0.025),
        "o3": .openAI(input: 2, output: 8, cacheRead: 0.5),
        "o4-mini": .openAI(input: 1.1, output: 4.4, cacheRead: 0.275),
        "codex-mini-latest": .openAI(input: 1.5, output: 6, cacheRead: 0.375),
        "gpt-5": .openAI(input: 1.25, output: 10, cacheRead: 0.125),
        "gpt-5-mini": .openAI(input: 0.25, output: 2, cacheRead: 0.025),
        "gpt-5-nano": .openAI(input: 0.05, output: 0.4, cacheRead: 0.005),
        "gpt-5-codex": .openAI(input: 1.25, output: 10, cacheRead: 0.125),
        "gpt-5-pro": .openAI(input: 15, output: 120, cacheRead: 1.5),
        "gpt-5.1": .openAI(input: 1.25, output: 10, cacheRead: 0.125),
        "gpt-5.1-codex": .openAI(input: 1.25, output: 10, cacheRead: 0.125),
        "gpt-5.1-codex-max": .openAI(input: 1.25, output: 10, cacheRead: 0.125),
        "gpt-5.1-codex-mini": .openAI(input: 0.25, output: 2, cacheRead: 0.025),
        "gpt-5.2": .openAI(input: 1.75, output: 14, cacheRead: 0.175),
        "gpt-5.2-codex": .openAI(input: 1.75, output: 14, cacheRead: 0.175),
        "gpt-5.2-pro": .openAI(input: 21, output: 168, cacheRead: 2.1),
        "gpt-5.3-codex": .openAI(input: 1.75, output: 14, cacheRead: 0.175),
        "gpt-5.4": .openAI(input: 2.5, output: 15, cacheRead: 0.25),
        "gpt-5.4-mini": .openAI(input: 0.75, output: 4.5, cacheRead: 0.075),
        "gpt-5.4-nano": .openAI(input: 0.2, output: 1.25, cacheRead: 0.02),
        "gpt-5.4-pro": .openAI(input: 30, output: 180, cacheRead: 3),
        "gpt-5.5": .openAI(input: 5, output: 30, cacheRead: 0.5),
        "gpt-5.5-pro": .openAI(input: 30, output: 180, cacheRead: 3),
        "gpt-5.6-sol": .openAI(input: 5, output: 30, cacheRead: 0.5),
        "gpt-5.6-terra": .openAI(input: 2, output: 12, cacheRead: 0.2),
        "gpt-5.6-luna": .openAI(input: 0.2, output: 1.2, cacheRead: 0.02),

        // Cursor's own models and its router, as the usage export names them.
        "auto": .cursor(input: 1.25, output: 6, cacheRead: 0.25, cacheWrite: 1.25),
        "composer-1": .cursor(input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 1.25),
        "composer-1.5": .cursor(input: 3.5, output: 17.5, cacheRead: 0.35, cacheWrite: 3.5),
        "composer-2": .cursor(input: 0.5, output: 2.5, cacheRead: 0.2, cacheWrite: 0.5),
        "composer-2-fast": .cursor(input: 1.5, output: 7.5, cacheRead: 0.35, cacheWrite: 1.5),
        "composer-2.5": .cursor(input: 0.5, output: 2.5, cacheRead: 0.2, cacheWrite: 0.5),
        "composer-2.5-fast": .cursor(input: 3, output: 15, cacheRead: 0.5, cacheWrite: 3),
    ]
}
