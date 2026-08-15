import { deduplicateAndFuse } from "./aggregate.js";
import { buildFullText, DEFAULT_FULLTEXT_MAX_CHARS, fetchFullTextXml, MAX_FULLTEXT_MAX_CHARS, MIN_FULLTEXT_MAX_CHARS, } from "./fulltext.js";
import { HistoryStore } from "./history.js";
import { HttpClient, sanitizedError } from "./http.js";
import { providers as defaultProviders } from "./providers/index.js";
import { applyCommonFilters } from "./providers/common.js";
import { compact, DEFAULT_ABSTRACT_MAX_CHARS, MAX_ABSTRACT_MAX_CHARS, normalizeDoi, normalizePmcid, normalizePmid, truncate } from "./normalize.js";
import { SOURCE_ORDER } from "./types.js";
export class LiteratureSearchService {
    providers;
    http;
    history;
    now;
    constructor(options = {}) {
        const supplied = options.providers ?? defaultProviders;
        this.providers = [...supplied].sort((a, b) => SOURCE_ORDER.indexOf(a.id) - SOURCE_ORDER.indexOf(b.id));
        this.http = options.http ?? new HttpClient();
        this.history = options.history ?? new HistoryStore();
        this.now = options.now ?? Date.now;
    }
    async search(raw, signal) {
        const input = normalizeInput(raw);
        const wanted = new Set(input.sources ?? SOURCE_ORDER);
        const selected = this.providers.filter((provider) => wanted.has(provider.id));
        const outcomes = await Promise.all(selected.map(async (provider) => {
            const started = this.now();
            const warnings = [];
            try {
                const papers = applyCommonFilters(await provider.search(input, { http: this.http, signal, warnings }), input).slice(0, input.limit);
                const status = {
                    source: provider.id,
                    status: papers.length > 0 ? "ok" : "empty",
                    result_count: papers.length,
                    duration_ms: Math.max(0, this.now() - started),
                    warnings: warnings.length ? warnings : undefined,
                };
                return { source: provider.id, papers, status };
            }
            catch (error) {
                if (signal?.aborted)
                    throw error;
                const detail = sanitizedError(error);
                const status = {
                    source: provider.id,
                    status: detail.status === 429 ? "rate_limited" : detail.type === "timeout" ? "timeout" : "error",
                    result_count: 0,
                    duration_ms: Math.max(0, this.now() - started),
                    warnings: warnings.length ? warnings : undefined,
                    error: detail,
                };
                return { source: provider.id, papers: [], status };
            }
        }));
        const results = deduplicateAndFuse(outcomes.map((outcome) => ({ source: outcome.source, papers: outcome.papers })), input.limit).map((result) => ({
            ...result,
            abstract: truncate(result.abstract, input.abstract_max_chars),
        }));
        const response = {
            query: input.query,
            parameters: {
                limit: input.limit,
                sources: selected.map((provider) => provider.id),
                year_from: input.year_from,
                year_to: input.year_to,
                open_access: input.open_access,
                abstract_max_chars: input.abstract_max_chars,
            },
            results,
            source_statuses: outcomes.map((outcome) => outcome.status),
            total_candidates: outcomes.reduce((total, outcome) => total + outcome.papers.length, 0),
            returned: results.length,
            all_sources_failed: outcomes.length > 0 &&
                outcomes.every((outcome) => ["error", "rate_limited", "timeout"].includes(outcome.status.status)),
        };
        await this.history.append(response);
        return response;
    }
    async fetchFullText(raw, signal) {
        const input = normalizeFullTextInput(raw);
        const identifiers = () => compact({ pmcid: input.pmcid, pmid: input.pmid, doi: input.doi });
        try {
            const result = await fetchFullTextXml(this.http, input, signal);
            if (!result.ok) {
                return {
                    status: "not_found",
                    sections: [],
                    full_text: "",
                    identifiers: result.identifiers,
                    source: "europepmc",
                    url: result.url,
                    word_count: 0,
                    character_count: 0,
                    truncated: false,
                    max_chars: input.max_chars,
                };
            }
            const parsed = result.parsed;
            if (!parsed)
                throw new Error("full text parser returned no content");
            const { full_text, truncated } = buildFullText(parsed, input.max_chars);
            return {
                status: "ok",
                title: parsed.title,
                abstract: parsed.abstract,
                sections: parsed.sections,
                full_text,
                identifiers: result.identifiers,
                source: "europepmc",
                url: result.url,
                license: parsed.license,
                word_count: full_text.split(/\s+/).filter(Boolean).length,
                character_count: Array.from(full_text).length,
                truncated,
                max_chars: input.max_chars,
            };
        }
        catch (error) {
            if (signal?.aborted)
                throw error;
            const detail = sanitizedError(error);
            return {
                status: "error",
                sections: [],
                full_text: "",
                identifiers: identifiers(),
                source: "europepmc",
                word_count: 0,
                character_count: 0,
                truncated: false,
                max_chars: input.max_chars,
                error: detail,
            };
        }
    }
}
export function normalizeFullTextInput(raw) {
    const pmcid = normalizePmcid(raw.pmcid);
    const pmid = normalizePmid(raw.pmid);
    const doi = normalizeDoi(raw.doi);
    if (pmcid === undefined && pmid === undefined && doi === undefined) {
        throw new Error("Provide at least one of pmcid, pmid, doi");
    }
    const max_chars = raw.max_chars ?? DEFAULT_FULLTEXT_MAX_CHARS;
    if (!Number.isInteger(max_chars) || max_chars < MIN_FULLTEXT_MAX_CHARS || max_chars > MAX_FULLTEXT_MAX_CHARS) {
        throw new Error(`max_chars must be an integer between ${MIN_FULLTEXT_MAX_CHARS} and ${MAX_FULLTEXT_MAX_CHARS}`);
    }
    return { pmcid, pmid, doi, max_chars };
}
export function normalizeInput(raw) {
    const query = raw.query.trim();
    if (!query)
        throw new Error("query must not be empty");
    const limit = Math.min(50, Math.max(1, Math.trunc(raw.limit ?? 10)));
    const abstract_max_chars = raw.abstract_max_chars ?? DEFAULT_ABSTRACT_MAX_CHARS;
    if (!Number.isInteger(abstract_max_chars) || abstract_max_chars < 1 || abstract_max_chars > MAX_ABSTRACT_MAX_CHARS) {
        throw new Error(`abstract_max_chars must be an integer between 1 and ${MAX_ABSTRACT_MAX_CHARS}`);
    }
    if (raw.year_from !== undefined && raw.year_to !== undefined && raw.year_from > raw.year_to) {
        throw new Error("year_from must be less than or equal to year_to");
    }
    const requested = raw.sources ? new Set(raw.sources) : undefined;
    const sources = requested ? SOURCE_ORDER.filter((source) => requested.has(source)) : undefined;
    if (requested && (!sources || sources.length === 0))
        throw new Error("sources must include at least one supported source");
    return {
        query,
        limit,
        sources,
        year_from: raw.year_from,
        year_to: raw.year_to,
        open_access: raw.open_access,
        abstract_max_chars,
    };
}
//# sourceMappingURL=service.js.map