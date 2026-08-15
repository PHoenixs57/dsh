# literature-search-mcp

A standalone Node.js 22 TypeScript MCP server that searches seven scholarly metadata providers over stdio, normalizes records, deduplicates them, and applies deterministic reciprocal-rank fusion.

For ZIP packaging, recipient installation, Claude Code registration, permissions, updates, troubleshooting, and uninstallation, see the Chinese guide: [INSTALL_ZH.md](INSTALL_ZH.md).

## MCP tools

The server registers exactly three tools:

- `literature_search` — search selected providers or all providers by default.
- `literature_sources` — list supported providers, limitations, and whether optional environment variables are configured.
- `literature_get_fulltext` — fetch open-access full text from Europe PMC (PMC Open Access subset) for a paper identified by `pmcid`, `pmid`, or `doi`, returning title, abstract, structured sections, a joined plain-text `full_text`, and metadata.

`literature_search` accepts:

| Input | Type | Default | Notes |
|---|---|---:|---|
| `query` | string | required | Search expression. Rich syntax (fielded, wildcard, Boolean) is passed through to providers that support it natively (PubMed `[Field]`, Europe PMC `FIELD:`, arXiv `field:`); Crossref, OpenAlex, Semantic Scholar, and bioRxiv receive a sanitized keyword form so wildcards/fields never break them. |
| `limit` | integer 1–50 | `10` | Maximum fused results returned. |
| `sources` | source ID array | all seven | `pubmed`, `europepmc`, `biorxiv`, `crossref`, `openalex`, `semantic-scholar`, `arxiv` |
| `year_from` | integer | unset | Inclusive lower publication year. |
| `year_to` | integer | unset | Inclusive upper publication year. |
| `open_access` | boolean | unset | Require positive open-access or PDF evidence. |
| `abstract_max_chars` | integer 1–3000 | `3000` | Maximum characters returned for each provider-supplied abstract or summary. |

Results include title, cleaned provider-supplied abstracts or summaries capped at `abstract_max_chars`, normalized identifiers, canonical/PDF URLs, year, authors and venue when available, reciprocal-rank score, source evidence, and per-source statuses. `literature_search` never downloads full text, fetches citation graphs, or retrieves references/citations. Open-access full text is available through the separate `literature_get_fulltext` tool (Europe PMC OA subset only; input `pmcid`/`pmid`/`doi`; output title, abstract, structured sections, and a joined plain-text `full_text` capped by `max_chars`).

`literature_get_fulltext` accepts:

| Input | Type | Default | Notes |
|---|---|---:|---|
| `pmcid` | string | unset | PubMed Central identifier (e.g. `PMC1234567`); at least one of `pmcid`/`pmid`/`doi` is required. |
| `pmid` | string | unset | PubMed identifier; resolved to a PMCID via Europe PMC search. |
| `doi` | string | unset | DOI; resolved to a PMCID via Europe PMC search. |
| `max_chars` | integer 1000–1000000 | `100000` | Maximum characters in the joined `full_text` string; `sections` and `abstract` are returned in full. |

Papers without open-access full text in Europe PMC return a structured `status: "not_found"` with empty content; transport or server failures return `status: "error"` with a sanitized `error` detail. Full text is never persisted to search history.

## Requirements and commands

Node.js 22 or newer is required. Dependencies are pinned in `package-lock.json`.

```sh
npm run typecheck
npm test
npm run build
npm start
```

The build emits `dist/server.js` and `dist/cli.js`. `npm start` runs the stdio server; stdout is reserved for MCP protocol messages and operational logging goes to stderr.

An MCP client can launch the built server with a command equivalent to:

```json
{
  "command": "node",
  "args": ["/absolute/path/to/literature-search-mcp/dist/server.js"]
}
```

This project does not modify or register MCP client configuration itself.

## Optional provider configuration

The server starts and searches without credentials. Optional environment variables improve provider etiquette or rate limits:

```text
OPENALEX_MAILTO
OPENALEX_API_KEY
SEMANTIC_SCHOLAR_API_KEY
CROSSREF_MAILTO
NCBI_TOOL
NCBI_EMAIL
NCBI_API_KEY
```

No Synthetic Sciences contact address is used as a fallback. PubMed always sends a tool name (`literature-search-mcp` unless `NCBI_TOOL` is set); email parameters are sent only when explicitly configured.

See [PROVIDERS.md](PROVIDERS.md) for API-specific behavior and limitations.

## Ranking and deduplication

Providers are always processed in this fixed order:

1. PubMed
2. Europe PMC
3. bioRxiv/medRxiv
4. Crossref
5. OpenAlex
6. Semantic Scholar
7. arXiv

Deduplication checks normalized DOI, PMID, versionless arXiv ID, then normalized title. Records with conflicting values for the same strong identifier type are never merged. Ranking uses reciprocal-rank fusion with a fixed constant (`k = 60`), followed by stable source/rank/title tie-breakers; provider-native scores do not affect ordering.

## HTTP behavior

All provider traffic uses Node's native `fetch` with:

- 30-second per-attempt timeout;
- three retries after the initial attempt for HTTP 408, 429, 5xx, network failures, and internal timeouts;
- numeric and HTTP-date `Retry-After` support;
- exponential backoff;
- caller cancellation propagation;
- per-host request pacing and concurrency controls;
- a maximum five-minute, 256-entry in-memory GET cache;
- typed, sanitized errors that omit query strings and response bodies.

## Search history

Each completed search appends one JSON object to:

```text
${XDG_STATE_HOME:-~/.local/state}/literature-search-mcp/history.jsonl
```

History records query parameters, source statuses, result identifiers, ranks, evidence, and URLs. It does not store abstracts, authors, provider credentials, or secrets.

Clear history with the compiled CLI:

```sh
node dist/cli.js clear-history
# or
npm run history:clear
```

## Tests

`npm test` is offline and uses `node:test`, fixtures, fake fetch implementations, and an in-memory MCP transport. It covers HTTP behavior, every provider parser, aggregation/deduplication, history, the search service, and exact MCP tool registration.

The live smoke test is opt-in:

```sh
npm run test:live
```

It performs a small Crossref query and is not part of the offline suite.

## License and attribution

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). This project adapts concepts from OpenScience literature connectors but does not import the OpenScience runtime.
