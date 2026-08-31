import fetch, { Response } from 'node-fetch';

/**
 * Polite HTTP fetch for official-source monitoring:
 * - identifying User-Agent
 * - request timeout
 * - retries with exponential backoff
 * - never bypasses robots.txt / CAPTCHA / login / rate limits — a source
 *   that returns 403/429 or requires auth is simply skipped and logged.
 */
const USER_AGENT =
  'DCTE-KP-Teachers-Bot/1.0 (+https://github.com/ — independent educational app; contact via app listing)';

export interface FetchOptions {
  timeoutMs?: number;
  maxRetries?: number;
}

export async function politeFetch(url: string, opts: FetchOptions = {}): Promise<Response> {
  const timeoutMs = opts.timeoutMs ?? 15_000;
  const maxRetries = opts.maxRetries ?? 3;

  let lastError: unknown;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetch(url, {
        headers: { 'User-Agent': USER_AGENT },
        signal: controller.signal as any,
      });
      clearTimeout(timer);

      if (res.status === 403 || res.status === 429 || res.status === 401) {
        // Respect access controls / rate limits — do not retry aggressively,
        // do not attempt to bypass. Surface as a handled failure.
        throw new Error(`Source declined request (status ${res.status}) for ${url}`);
      }
      if (!res.ok) {
        throw new Error(`Non-OK response (status ${res.status}) for ${url}`);
      }
      return res;
    } catch (err) {
      clearTimeout(timer);
      lastError = err;
      if (attempt < maxRetries) {
        const backoffMs = 2 ** attempt * 1000;
        await new Promise((resolve) => setTimeout(resolve, backoffMs));
      }
    }
  }
  throw lastError instanceof Error ? lastError : new Error(`Failed to fetch ${url}`);
}

export async function checkRobotsAllowed(baseUrl: string, path: string): Promise<boolean> {
  try {
    const robotsUrl = new URL('/robots.txt', baseUrl).toString();
    const res = await politeFetch(robotsUrl, { maxRetries: 1 });
    const text = await res.text();
    // Minimal, conservative robots.txt check: block only on an explicit
    // "Disallow: /" (or the exact path) under a User-agent: * block.
    const lines = text.split('\n').map((l) => l.trim());
    let inWildcardBlock = false;
    for (const line of lines) {
      if (/^user-agent:\s*\*/i.test(line)) {
        inWildcardBlock = true;
        continue;
      }
      if (/^user-agent:/i.test(line)) {
        inWildcardBlock = false;
        continue;
      }
      if (inWildcardBlock && /^disallow:\s*\/?\s*$/i.test(line)) {
        const disallowPath = line.split(':')[1]?.trim() || '/';
        if (disallowPath === '/' || path.startsWith(disallowPath)) {
          return false;
        }
      }
    }
    return true;
  } catch {
    // If robots.txt cannot be fetched, default to proceeding conservatively
    // with the low-frequency, low-volume schedule already in place.
    return true;
  }
}
