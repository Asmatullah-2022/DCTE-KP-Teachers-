import * as cheerio from 'cheerio';
import { SourceConfig } from '../sources/sourceConfig';

export interface DiscoveredLink {
  url: string;
  title: string;
  isPdf: boolean;
  publishedDateGuess?: string;
}

/** Normalize a possibly-relative URL against a source's base URL. */
export function normalizeUrl(href: string, baseUrl: string): string {
  try {
    return new URL(href, baseUrl).toString();
  } catch {
    return href;
  }
}

/**
 * Extract candidate notification/document links from a source's HTML using
 * its configured selectors (see sources/sourceConfig.ts). Returns an empty
 * array (never throws) if the selector matches nothing — the caller logs
 * this as a sync warning so the selectors can be corrected.
 */
export function extractLinks(html: string, config: SourceConfig): DiscoveredLink[] {
  const $ = cheerio.load(html);
  const seen = new Set<string>();
  const links: DiscoveredLink[] = [];

  $(config.linkSelector).each((_, el) => {
    const href = $(el).attr('href');
    if (!href) return;
    const url = normalizeUrl(href, config.baseUrl);
    if (seen.has(url)) return;
    seen.add(url);

    const title =
      (config.titleSelector ? $(el).closest('article, .post, li, div').find(config.titleSelector).first().text() : '') ||
      $(el).text() ||
      url;

    const dateText = config.dateSelector
      ? $(el).closest('article, .post, li, div').find(config.dateSelector).first().text().trim()
      : undefined;

    links.push({
      url,
      title: title.trim().replace(/\s+/g, ' '),
      isPdf: url.toLowerCase().endsWith('.pdf'),
      publishedDateGuess: dateText || undefined,
    });
  });

  return links;
}
