# Literature providers

The server uses public metadata/search APIs and returns metadata plus cleaned provider-supplied abstracts or summaries, capped at 3,000 characters by default (or the requested `abstract_max_chars`). `literature_search` never downloads article full text, traverses citation graphs, or fetches cited/reference records.

Query syntax: rich expressions (fielded, wildcard, Boolean) are passed through verbatim to providers that support them natively — PubMed (`[Title]`, `[tiab]`, …), Europe PMC (`TITLE_ABS:`, `ABSTRACT:`, …), and arXiv (`ti:`, `abs:`, `all:`, …). Crossref, OpenAlex, Semantic Scholar, and bioRxiv receive a sanitized keyword form (`keywordQuery` strips field prefixes, `[Field]` qualifiers, `*` wildcards, and standalone `AND`/`OR`/`NOT`) so that e.g. `acoustic*` no longer breaks OpenAlex with an HTTP 400.

Open-access full text is available through the separate `literature_get_fulltext` tool, which uses Europe PMC only. The Europe PMC REST `fullTextXML` method is PMCID-keyed: the bare `{base}/{pmcid}/fullTextXML` form works, while `{base}/{source}/{id}` (source `MED`/`PMC`/`DOI`) returns 404 for every article. A supplied `pmid` or `doi` is first resolved to a PMCID via the search API (`EXT_ID:{pmid} AND SRC:MED` / `DOI:"{doi}"`). Articles without open-access full text, or identifiers that resolve to no PMCID, return a structured `not_found` status.

| Source ID | API | Search and filtering notes | Optional configuration |
|---|---|---|---|
| `pubmed` | NCBI E-utilities (`ESearch` + `EFetch`) | Relevance search, publication-year query clauses, and `free full text[sb]` for `open_access`. Requests include the `tool` parameter. Keyless pacing is 3 requests/second; keyed pacing is 10 requests/second. | `NCBI_TOOL`, `NCBI_EMAIL`, `NCBI_API_KEY` |
| `europepmc` | Europe PMC REST search | `resultType=core` supplies abstracts. Supports first-publication-date and `OPEN_ACCESS:Y` filters. | None |
| `biorxiv` | bioRxiv API (`api.biorxiv.org/details`) | The public API has no full-text search. DOI-shaped queries use exact DOI lookup. Other queries cursor-page through a bounded recent window (maximum 200 records per backend) from bioRxiv and medRxiv and rank term overlap locally. A recoverable failure of one backend/page is reported in source warnings. Preprints are treated as openly accessible. | None |
| `crossref` | Crossref REST works search | Supports publication-date filters. Open-access filtering is applied after normalization; a recognized open license or a direct PDF is positive access evidence. Crossref metadata often lacks abstracts and direct PDFs. | `CROSSREF_MAILTO` |
| `openalex` | OpenAlex Works API | Supports publication dates and the current `is_oa:true` filter. Reconstructs abstracts from the inverted index and uses best open-access locations when present. | `OPENALEX_MAILTO`, `OPENALEX_API_KEY` |
| `semantic-scholar` | Semantic Scholar Academic Graph | Supports year ranges. Open-access filtering is enforced after parsing from `openAccessPdf`; no citation or reference fields are requested. Keyless requests are paced conservatively. | `SEMANTIC_SCHOLAR_API_KEY` |
| `arxiv` | arXiv Atom API | Supports native fielded queries and submitted-date ranges. Every record is openly accessible. Requests use a 3-second minimum start interval and maximum concurrency of 1. | None |

## Open-access interpretation

`open_access: true` is conservative: a record is retained only when the provider supplies positive open-access evidence or a usable PDF URL. Provider definitions differ, so this is an access-oriented filter rather than a legal conclusion about reuse rights.

## Provider failures

Each source runs independently. Statuses distinguish `ok`, `empty`, `rate_limited`, `timeout`, and `error`; recoverable sub-backend failures appear as warnings. Successful sources still contribute results. If every selected source fails, `literature_search` returns a normal structured response with `all_sources_failed: true` and an empty `results` array.
