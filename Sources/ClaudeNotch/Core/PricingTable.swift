import Foundation

/// USD per 1M tokens at API list price. Estimates for display only: on a subscription this is
/// what the usage would have cost, not a bill. Cache write is 1.25× input, cache read 10% of
/// input (Fable 5.1 reads at a flat $0.25). Most specific name first: the first match wins.
enum PricingTable {
    struct Rate { let input, output, cacheWrite, cacheRead: Double }

    static let rates: [(match: String, rate: Rate)] = [
        ("fable-5-1", Rate(input: 10,   output: 50, cacheWrite: 12.5,  cacheRead: 0.25)),
        ("fable",     Rate(input: 10,   output: 50, cacheWrite: 12.5,  cacheRead: 1.0)),
        ("opus-4-1",  Rate(input: 15,   output: 75, cacheWrite: 18.75, cacheRead: 1.5)),
        ("opus-3",    Rate(input: 15,   output: 75, cacheWrite: 18.75, cacheRead: 1.5)),
        ("opus",      Rate(input: 5,    output: 25, cacheWrite: 6.25,  cacheRead: 0.5)),
        ("sonnet-5",  Rate(input: 2,    output: 10, cacheWrite: 2.5,   cacheRead: 0.2)),
        ("sonnet",    Rate(input: 3,    output: 15, cacheWrite: 3.75,  cacheRead: 0.30)),
        ("haiku-4-5", Rate(input: 1,    output: 5,  cacheWrite: 1.25,  cacheRead: 0.1)),
        ("haiku",     Rate(input: 0.80, output: 4,  cacheWrite: 1.0,   cacheRead: 0.08)),
    ]
    static let fallback = Rate(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.30)

    static func rate(for model: String) -> Rate {
        let m = model.lowercased()
        return rates.first { m.contains($0.match) }?.rate ?? fallback
    }

    static func cost(for e: UsageEvent) -> Double {
        let r = rate(for: e.model)
        return (Double(e.inputTokens) * r.input
              + Double(e.outputTokens) * r.output
              + Double(e.cacheCreationTokens) * r.cacheWrite
              + Double(e.cacheReadTokens) * r.cacheRead) / 1_000_000
    }
}
