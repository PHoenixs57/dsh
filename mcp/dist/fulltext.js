import { XMLParser } from "fast-xml-parser";
import { HttpRequestError } from "./http.js";
import { chooseUrl, cleanText, compact, normalizePmcid, normalizeTitle, toArray } from "./normalize.js";
export const DEFAULT_FULLTEXT_MAX_CHARS = 100_000;
export const MIN_FULLTEXT_MAX_CHARS = 1_000;
export const MAX_FULLTEXT_MAX_CHARS = 1_000_000;
// Europe PMC REST API base. The fullTextXML method is PMCID-keyed only: the
// bare `{base}/{pmcid}/fullTextXML` form works, while `{base}/{source}/{id}`
// (source = MED/PMC/DOI) returns 404 for every article.
const FULLTEXT_BASE = "https://www.ebi.ac.uk/europepmc/webservices/rest";
const XML_CACHE_TTL_MS = 5 * 60_000;
const parser = new XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: "@",
    removeNSPrefix: true,
    trimValues: true,
});
function extractText(value, opts = {}) {
    if (value === undefined || value === null)
        return undefined;
    if (typeof value === "string" || typeof value === "number")
        return String(value).trim() || undefined;
    if (Array.isArray(value))
        return value.map((item) => extractText(item, opts)).filter(Boolean).join(" ") || undefined;
    if (typeof value === "object") {
        const node = value;
        const parts = [];
        for (const [key, child] of Object.entries(node)) {
            if (key.startsWith("@"))
                continue;
            if (opts.skipKeys?.has(key))
                continue;
            const text = extractText(child, opts);
            if (text)
                parts.push(text);
        }
        return cleanText(parts.join(" "));
    }
    return undefined;
}
const REFERENCE_HEADING = /^(references|bibliography|literature cited|works cited|sources|reference)$/i;
function isReferenceHeading(heading) {
    return REFERENCE_HEADING.test(normalizeTitle(heading));
}
function extractSections(body) {
    const result = [];
    const visit = (sec, heading) => {
        const text = extractText(sec, { skipKeys: new Set(["title", "sec"]) });
        if (text && !(heading && isReferenceHeading(heading))) {
            result.push({ heading: heading ?? "", text });
        }
        for (const child of toArray(sec.sec)) {
            const node = child;
            visit(node, extractText(node.title));
        }
    };
    for (const sec of toArray(body?.sec)) {
        visit(sec, extractText(sec.title));
    }
    return result;
}
export function parseJatsXml(xml) {
    const root = parser.parse(xml);
    const article = toArray(root.article)[0];
    const front = toArray(article?.front)[0];
    const meta = toArray(front?.["article-meta"])[0];
    const titleGroup = toArray(meta?.["title-group"])[0];
    const title = extractText(titleGroup?.["article-title"]);
    // Skip the literal "Abstract" heading but keep any nested abstract sections.
    const abstract = extractText(meta?.abstract, { skipKeys: new Set(["title"]) });
    const permissions = toArray(meta?.permissions)[0];
    const license = extractText(permissions?.license);
    const body = toArray(article?.body)[0];
    const sections = extractSections(body);
    return { title, abstract, sections, license };
}
export function buildFullText(parsed, maxChars) {
    const blocks = [];
    if (parsed.abstract)
        blocks.push(parsed.abstract);
    for (const section of parsed.sections) {
        blocks.push(section.heading ? `${section.heading}\n\n${section.text}` : section.text);
    }
    const joined = blocks.join("\n\n");
    const characters = Array.from(joined);
    if (characters.length <= maxChars)
        return { full_text: joined, truncated: false };
    const prefix = characters.slice(0, maxChars - 1).join("");
    const shortened = prefix.replace(/\s+\S*$/, "").trimEnd();
    return { full_text: `${shortened || prefix}…`, truncated: true };
}
async function resolvePmcid(http, ids, signal) {
    const query = ids.pmid
        ? `EXT_ID:${ids.pmid} AND SRC:MED`
        : ids.doi
            ? `DOI:"${ids.doi}"`
            : undefined;
    if (!query)
        return undefined;
    const url = `${FULLTEXT_BASE}/search?query=${encodeURIComponent(query)}&format=json&resultType=lite`;
    const data = await http.getJson(url, { signal, cacheTtlMs: XML_CACHE_TTL_MS });
    const record = (data.resultList?.result ?? []).find((item) => item.pmcid);
    return record?.pmcid ? normalizePmcid(record.pmcid) : undefined;
}
export async function fetchFullTextXml(http, input, signal) {
    const ids = compact({
        pmcid: input.pmcid,
        pmid: input.pmid,
        doi: input.doi,
    });
    const pmcid = ids.pmcid ?? (await resolvePmcid(http, ids, signal));
    if (!pmcid) {
        return { ok: false, reason: "no_full_text", identifiers: ids, url: chooseUrl(ids) };
    }
    const url = `${FULLTEXT_BASE}/${encodeURIComponent(pmcid)}/fullTextXML`;
    let xml;
    try {
        xml = await http.requestText(url, {
            signal,
            cacheTtlMs: XML_CACHE_TTL_MS,
            looksValid: (body) => /<article[\s>]/i.test(body),
        });
    }
    catch (error) {
        if (error instanceof HttpRequestError && error.status === 404) {
            return { ok: false, reason: "no_full_text", identifiers: ids, url };
        }
        throw error;
    }
    return {
        ok: true,
        identifiers: { ...ids, pmcid },
        url: `https://europepmc.org/articles/${pmcid}`,
        parsed: parseJatsXml(xml),
    };
}
//# sourceMappingURL=fulltext.js.map