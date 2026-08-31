import { extractLinks, normalizeUrl } from '../src/parsers/htmlParser';
import { SourceConfig } from '../src/sources/sourceConfig';

const config: SourceConfig = {
  sourceId: 'test_source',
  name: 'Test Source',
  baseUrl: 'https://example.gov.pk/',
  listUrl: 'https://example.gov.pk/notifications/',
  department: 'DCTE',
  linkSelector: 'a[href]',
  verificationStatus: 'NEEDS_LIVE_VERIFICATION',
};

describe('normalizeUrl', () => {
  it('resolves relative URLs against the base', () => {
    expect(normalizeUrl('/wp-content/file.pdf', config.baseUrl)).toBe(
      'https://example.gov.pk/wp-content/file.pdf',
    );
  });

  it('leaves absolute URLs untouched', () => {
    expect(normalizeUrl('https://other.gov.pk/x.pdf', config.baseUrl)).toBe('https://other.gov.pk/x.pdf');
  });
});

describe('extractLinks', () => {
  it('finds and de-duplicates PDF links', () => {
    const html = `
      <html><body>
        <article>
          <a href="/uploads/notice.pdf">Notice</a>
          <a href="/uploads/notice.pdf">Notice (duplicate)</a>
          <a href="/page/about">About</a>
        </article>
      </body></html>`;
    const links = extractLinks(html, config);
    expect(links).toHaveLength(2);
    expect(links.find((l) => l.url.endsWith('notice.pdf'))?.isPdf).toBe(true);
  });

  it('returns an empty array (never throws) when the selector matches nothing', () => {
    const links = extractLinks('<html><body>no links here</body></html>', {
      ...config,
      linkSelector: '.does-not-exist a',
    });
    expect(links).toEqual([]);
  });
});
