#!/usr/bin/env node
import { pathToFileURL } from "node:url";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import * as z from "zod/v4";
import { DEFAULT_FULLTEXT_MAX_CHARS, MAX_FULLTEXT_MAX_CHARS, MIN_FULLTEXT_MAX_CHARS, } from "./fulltext.js";
import { sourceCatalog } from "./providers/index.js";
import { LiteratureSearchService } from "./service.js";
import { MAX_ABSTRACT_MAX_CHARS } from "./normalize.js";
import { SOURCE_ORDER } from "./types.js";
const sourceSchema = z.enum(SOURCE_ORDER);
export function createLiteratureServer(options = {}) {
    const service = options.service ?? new LiteratureSearchService({ providers: options.providers });
    const server = new McpServer({ name: "literature-search-mcp", version: "1.2.1" });
    server.registerTool("literature_search", {
        title: "Search scholarly literature",
        description: "Search PubMed, Europe PMC, bioRxiv/medRxiv, Crossref, OpenAlex, Semantic Scholar, and arXiv. Sources fan out in parallel by default; results are normalized, deduplicated, and fused deterministically. Returns provider-supplied metadata abstracts or summaries capped at 3,000 characters by default, never full text or citation graphs.",
        inputSchema: {
            query: z.string().min(1).describe("Literature query"),
            limit: z.number().int().min(1).max(50).default(10).describe("Maximum fused results to return"),
            sources: z.array(sourceSchema).min(1).optional().describe("Optional source subset; default is all sources"),
            year_from: z.number().int().min(1000).max(3000).optional(),
            year_to: z.number().int().min(1000).max(3000).optional(),
            open_access: z.boolean().optional().describe("When true, retain results with positive open-access or PDF evidence"),
            abstract_max_chars: z
                .number()
                .int()
                .min(1)
                .max(MAX_ABSTRACT_MAX_CHARS)
                .default(MAX_ABSTRACT_MAX_CHARS)
                .describe("Maximum characters returned for each abstract or summary"),
        },
        annotations: {
            readOnlyHint: false,
            destructiveHint: false,
            idempotentHint: false,
            openWorldHint: true,
        },
    }, async (input, extra) => {
        if (input.year_from !== undefined && input.year_to !== undefined && input.year_from > input.year_to) {
            throw new Error("year_from must be less than or equal to year_to");
        }
        const response = await service.search(input, extra.signal);
        return {
            content: [{ type: "text", text: JSON.stringify(response, null, 2) }],
            structuredContent: { ...response },
        };
    });
    server.registerTool("literature_sources", {
        title: "List literature sources",
        description: "List the seven supported literature sources, optional credential environment variables, and provider limitations.",
        annotations: { readOnlyHint: true, openWorldHint: false },
    }, async () => {
        const sources = sourceCatalog(options.providers).map((source) => ({
            ...source,
            credentials: source.credentials.map((name) => ({ name, configured: Boolean(process.env[name]?.trim()) })),
        }));
        const response = { sources, default_source_order: SOURCE_ORDER, count: sources.length };
        return {
            content: [{ type: "text", text: JSON.stringify(response, null, 2) }],
            structuredContent: response,
        };
    });
    server.registerTool("literature_get_fulltext", {
        title: "Fetch open-access full text",
        description: "Fetch open-access full text from Europe PMC (PMC Open Access subset) for a paper identified by at least one of pmcid, pmid, or doi. Returns title, abstract, structured sections, a joined plain-text full_text, and metadata (identifiers, source, url, license, word/character counts, truncated flag). Papers without open-access full text return a structured status of \"not_found\".",
        inputSchema: {
            pmcid: z.string().optional().describe("PubMed Central identifier, e.g. PMC1234567"),
            pmid: z.string().optional().describe("PubMed identifier"),
            doi: z.string().optional().describe("Digital Object Identifier"),
            max_chars: z
                .number()
                .int()
                .min(MIN_FULLTEXT_MAX_CHARS)
                .max(MAX_FULLTEXT_MAX_CHARS)
                .default(DEFAULT_FULLTEXT_MAX_CHARS)
                .describe("Maximum characters in the joined full_text string; sections and abstract are returned in full"),
        },
        annotations: {
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: true,
        },
    }, async (input, extra) => {
        if (!input.pmcid && !input.pmid && !input.doi) {
            throw new Error("Provide at least one of pmcid, pmid, doi");
        }
        const response = await service.fetchFullText(input, extra.signal);
        return {
            content: [{ type: "text", text: JSON.stringify(response, null, 2) }],
            structuredContent: { ...response },
        };
    });
    return server;
}
export async function main() {
    const server = createLiteratureServer();
    await server.connect(new StdioServerTransport());
    console.error("literature-search-mcp running on stdio");
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
    main().catch((error) => {
        console.error(`literature-search-mcp failed: ${error instanceof Error ? error.message : "unknown error"}`);
        process.exitCode = 1;
    });
}
//# sourceMappingURL=server.js.map