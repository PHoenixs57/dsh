import { cleanText, normalizeIdentifiers, truncate } from "../normalize.js";
export function makePaper(input) {
    const title = truncate(input.title, 500);
    return {
        source: input.source,
        source_id: input.source_id,
        title: title ?? `${input.source} record ${input.source_id || "without identifier"}`,
        title_missing: !title,
        abstract: cleanText(input.abstract),
        identifiers: normalizeIdentifiers(input.identifiers ?? {}),
        url: cleanText(input.url),
        pdf_url: cleanText(input.pdf_url),
        year: input.year,
        authors: input.authors?.map(cleanText).filter((value) => Boolean(value)),
        venue: cleanText(input.venue),
        open_access: input.open_access,
    };
}
export function applyCommonFilters(papers, input) {
    return papers.filter((paper) => {
        if (input.year_from !== undefined && (paper.year === undefined || paper.year < input.year_from))
            return false;
        if (input.year_to !== undefined && (paper.year === undefined || paper.year > input.year_to))
            return false;
        if (input.open_access === true && paper.open_access !== true && !paper.pdf_url)
            return false;
        return true;
    });
}
export function yearRange(input) {
    if (input.year_from === undefined && input.year_to === undefined)
        return undefined;
    return `${input.year_from ?? 1000}-${input.year_to ?? 3000}`;
}
export function catalog(id, name, description, homepage, credentials, notes) {
    return { id, name, description, homepage, credentials, notes };
}
// Sanitizes rich query expressions for providers that accept only free-text
// keywords. Native fielded providers (PubMed, Europe PMC, arXiv) keep the raw
// query; this is applied to Crossref/OpenAlex/Semantic Scholar and to bioRxiv's
// local term-overlap scoring, so wildcard/fielded/Boolean syntax never breaks
// those endpoints (e.g. a wildcard `acoustic*` would otherwise 400 OpenAlex).
const FIELD_PREFIX = /^(?!https?:)[A-Z][A-Z0-9_]*:/i;
const BOOLEAN_OPERATOR = /^(?:AND|OR|NOT)$/i;
export function keywordQuery(query) {
    const noQualifiers = query.replace(/\[[^\]]*\]/g, " ").replace(/\*/g, " ");
    const tokens = noQualifiers.match(/"[^"]*"|\S+/g) ?? [];
    const kept = tokens
        .map((token) => token.replace(FIELD_PREFIX, ""))
        .filter((token) => {
        const trimmed = token.trim();
        return trimmed.length > 0 && !BOOLEAN_OPERATOR.test(trimmed);
    });
    return kept.join(" ");
}
//# sourceMappingURL=common.js.map