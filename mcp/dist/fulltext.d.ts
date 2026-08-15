import { type HttpClient } from "./http.js";
import type { FullTextInput, FullTextSection, Identifiers } from "./types.js";
export declare const DEFAULT_FULLTEXT_MAX_CHARS = 100000;
export declare const MIN_FULLTEXT_MAX_CHARS = 1000;
export declare const MAX_FULLTEXT_MAX_CHARS = 1000000;
export interface ParsedFullText {
    title?: string;
    abstract?: string;
    sections: FullTextSection[];
    license?: string;
}
export interface FullTextFetchResult {
    ok: boolean;
    reason?: "no_full_text";
    identifiers: Identifiers;
    url?: string;
    parsed?: ParsedFullText;
}
export declare function parseJatsXml(xml: string): ParsedFullText;
export declare function buildFullText(parsed: ParsedFullText, maxChars: number): {
    full_text: string;
    truncated: boolean;
};
export declare function fetchFullTextXml(http: HttpClient, input: FullTextInput, signal?: AbortSignal): Promise<FullTextFetchResult>;
