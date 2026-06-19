# Libro.fm Catalog Search — Backend Specification

Backend specification for the `GET /api/libro/search` endpoint required by the OpenClaw
iOS client's **podcast book-reference** feature.

## Background

When a user bookmarks a moment in a podcast episode, the iOS app fetches a ~5-minute
transcript window and runs it through the AI. In addition to summarizing the passage,
the app now asks the AI to extract any **books** explicitly mentioned or recommended in
that passage. For each extracted book, the app calls this endpoint to find the matching
title in the **Libro.fm catalog** so it can attach a cover image, price, and a link to
the book's Libro.fm product page. The matched book then appears in the episode's
"References" section.

This endpoint searches the **public Libro.fm catalog**, not the user's purchased
library. (The user's purchases are served by the existing `GET /api/libro/books`.)

---

## Endpoint

```
GET /api/libro/search
```

### Authentication

Identical to every other LibroAI/Gateway endpoint:

```
Authorization: Bearer <gatewayHookToken>
Accept: application/json
```

Validate the bearer token the same way as `/v1/chat/completions` and `/api/library`.
Return `401 Unauthorized` for a missing/invalid token.

### Query Parameters

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `q` | string | Yes | Free-text search string, URL-encoded. Typically `"<title> <author>"`, e.g. `Project Hail Mary Andy Weir`. |
| `limit` | int | No | Max number of results to return. Default `10`, clamp to `1…25`. |

If `q` is missing or blank after trimming, return `400 Bad Request` (or an empty array
`[]` — the client treats both as "no results").

### Request Example

```
GET /api/libro/search?q=Project%20Hail%20Mary%20Andy%20Weir&limit=10
Authorization: Bearer <token>
Accept: application/json
```

---

## Response

`200 OK` — a JSON **array** of catalog results, ordered by relevance (best match first).

```json
[
  {
    "id": "9781250294852",
    "title": "Project Hail Mary",
    "author": "Andy Weir",
    "cover_url": "https://cdn.libro.fm/covers/9781250294852.jpg",
    "url": "https://libro.fm/audiobooks/9781250294852-project-hail-mary",
    "price": "$14.99",
    "isbn": "9781250294852"
  },
  {
    "id": "9780553418026",
    "title": "The Martian",
    "author": "Andy Weir",
    "cover_url": "https://cdn.libro.fm/covers/9780553418026.jpg",
    "url": "https://libro.fm/audiobooks/9780553418026-the-martian",
    "price": "$19.99",
    "isbn": "9780553418026"
  }
]
```

### JSON Convention

All field names are **snake_case**. The iOS client converts to camelCase automatically
(`JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`).

### Field Semantics

| Field | Type | Nullable | Notes |
|-------|------|----------|-------|
| `id` | string | No | Stable Libro.fm identifier for the book. ISBN-13 is a good choice. Used by the client as the row identity and may later be passed to `POST /api/libro/download/{book_id}`. |
| `title` | string | No | Book title as listed on Libro.fm. |
| `author` | string | Yes | Author name(s). `null` if unavailable. |
| `cover_url` | string | Yes | **Absolute** `https://` URL to the cover image on Libro.fm's CDN. Must be directly loadable by the client without auth (the app loads it with a plain `AsyncImage`). `null` if none. |
| `url` | string | Yes | **Absolute** `https://` URL to the book's Libro.fm product page. Opened in the browser when the user taps the reference. `null` if none. |
| `price` | string | Yes | Pre-formatted display price **including currency symbol**, e.g. `"$14.99"`. The client renders it verbatim (`"Libro.fm · $14.99"`). `null` if unavailable. |
| `isbn` | string | Yes | ISBN-13 if known. `null` otherwise. |

### Ordering & Matching

- Results **must** be ordered most-relevant-first. The iOS client applies this logic to
  the array you return:
  1. First result whose `title` matches the searched title case-insensitively (exact).
  2. Else first result whose `title` is a case-insensitive substring of the query (or
     vice-versa).
  3. Else the **first** element of the array.
- Because the client falls back to element `[0]`, a well-ranked first result matters most.

### Empty Results

Return `200 OK` with an empty array `[]` when nothing matches. The client then falls back
to a `https://libro.fm/search?q=<query>` deep link, so the reference still renders (just
without cover/price). **Do not** return `404` for "no matches".

---

## Error Handling

| Condition | Status | Body |
|-----------|--------|------|
| Missing/invalid bearer token | `401` | `{ "detail": "Unauthorized" }` |
| Missing/blank `q` | `400` | `{ "detail": "Query parameter 'q' is required" }` (empty `[]` also acceptable) |
| Upstream Libro.fm failure / timeout | `502` | `{ "detail": "Libro.fm search unavailable" }` |
| Anything else | `500` | `{ "detail": "<message>" }` |

The client surfaces the `detail` field from JSON error bodies. All non-2xx responses are
caught and treated as "no enrichment" — a failed search never blocks highlight creation.

---

## Implementation Guidance

> **Verified June 2026** by fetching the live site. Libro.fm has **no public/official
> search API** (confirmed across all community tools — they're login-only library
> downloaders). The only catalog-search path is **scraping the server-rendered
> `https://libro.fm/search` HTML page**. The details below were confirmed against the
> live page and are sufficient to implement the parser.

### Scraping `https://libro.fm/search`

**Request**

```
GET https://libro.fm/search?q=<url-encoded query>
User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36
Accept: text/html,application/xhtml+xml
```

- ⚠️ **A browser `User-Agent` is mandatory.** With no/default UA the page returns
  **`403 Forbidden`**. With a normal browser UA it returns `200` and a fully
  **server-rendered** ~200 KB HTML page (no JS execution required).
- **No login needed for search.** The session cookie from `POST /api/libro/auth` is
  *not* required to read public search results (it's only needed for library/download).
  Send it if convenient, but UA is the thing that matters.

**Result markup** — each result is an `<a class="book">`. A search page yields ~25 of
them. Verified structure:

```html
<a class="book" href="/audiobooks/9781035084111-the-traveler">
  <div class="book-cover-wrap">
    <img class="book-cover"
         alt="View audiobook of The Traveler by Joseph Eckert"
         src="//covers.libro.fm/9781035084111_400.jpg" />
  </div>
  <div class="book-info ">
    <div role="heading" aria-level="2" class="title">The Traveler</div>
    <div class="author">Joseph Eckert</div>
  </div>
</a>
```

**Field extraction** (preserve page order — it is the relevance ranking):

| Spec field | How to extract | Notes |
|------------|----------------|-------|
| `id` / `isbn` | Leading digits of the last path segment of `href` — `/audiobooks/**9781035084111**-the-traveler` | ISBN-13. Use as `id`. |
| `title` | Text of `a.book .book-info .title` | Falls back to parsing the `img.book-cover` `alt`: `"View audiobook of {TITLE} by {AUTHOR}"`. |
| `author` | Text of `a.book .book-info .author` | Same `alt` fallback. |
| `cover_url` | `img.book-cover` `src`, prefix scheme → `https://covers.libro.fm/{isbn}_400.jpg` | The src is protocol-relative (`//covers.libro.fm/…`). Deterministic from ISBN; `_200.jpg` and `_400.jpg` sizes exist. Use `_400`. |
| `url` | Prefix host onto `href` → `https://libro.fm{href}` | e.g. `https://libro.fm/audiobooks/9781035084111-the-traveler`. |
| `price` | **Not available on the search page** → return `null` | Libro.fm is membership/credit-priced; search results carry no flat price. See below. |

**Parsing cautions:**
- Select only `a.book` anchors. The grid also contains promo/membership cards
  (`book-grid-item__promo`, "Become a member…") with **no** `a.book` — skip them.
- Search is **fuzzy** — e.g. `q=Project Hail Mary` returns related sci-fi titles, not
  only an exact match. That's expected; the iOS client does its own best-match selection
  (exact title → substring → first). Just return results in the page's order.
- A per-result modal (`#book-{isbn}`) holds extras (narrator, "By:"/"Narrated by:"); not
  needed for this endpoint but available if you later want narrator.

### Price (optional enhancement)

`price` is `null` from search alone. If you want to populate it, fetch the product page
`https://libro.fm/audiobooks/{isbn}-{slug}` per result and parse the price/àla-carte cost
there. This is an extra request per result — only do it for the top 1–2 results, behind
the cache, or skip it (the client renders fine without price).

### Recommended server behavior

- **Caching** — cache results per normalized query string for ~24h. Transcript book
  mentions repeat across episodes, and Libro.fm's catalog is stable. An in-memory or
  SQLite cache keyed on `lower(trim(q))` is sufficient.
- **Timeouts** — cap the upstream request at ~8s and return `502` on timeout rather than
  hanging; the client has a 60s ceiling but should not wait that long for an optional
  enrichment.
- **Rate limiting** — debounce/coalesce identical concurrent queries. A single bookmark
  can yield several book lookups; avoid hammering Libro.fm.
- **Normalization** — trim whitespace, collapse internal whitespace, and lowercase for
  cache keys (but preserve original casing in the response `title`/`author`).
- **No auth leakage** — never include the Libro.fm session cookie/token in the response.

### FastAPI Reference Implementation

Verified against the live page (June 2026). Requires `httpx` and `selectolax`
(`pip install httpx selectolax`); swap in BeautifulSoup if preferred.

```python
import re
import time
import httpx
from selectolax.parser import HTMLParser
from fastapi import APIRouter, Depends, HTTPException, Query

router = APIRouter()

BROWSER_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)
_ISBN_RE = re.compile(r"/audiobooks/(\d+)")

# Tiny in-process TTL cache: {query_lower: (expires_at, payload)}
_cache: dict[str, tuple[float, list[dict]]] = {}
_CACHE_TTL = 86_400  # 24h


def _parse_search_html(html: str) -> list[dict]:
    tree = HTMLParser(html)
    results: list[dict] = []
    for a in tree.css("a.book"):                      # skip promo cards (no a.book)
        href = a.attributes.get("href") or ""
        m = _ISBN_RE.search(href)
        if not m:
            continue
        isbn = m.group(1)

        title_node = a.css_first(".book-info .title")
        author_node = a.css_first(".book-info .author")
        title = title_node.text(strip=True) if title_node else None
        author = author_node.text(strip=True) if author_node else None

        # Fallback: alt="View audiobook of {TITLE} by {AUTHOR}"
        if not title:
            img = a.css_first("img.book-cover")
            alt = (img.attributes.get("alt") if img else "") or ""
            mm = re.match(r"View audiobook of (.+?) by (.+)$", alt)
            if mm:
                title = title or mm.group(1).strip()
                author = author or mm.group(2).strip()

        if not title:
            continue

        results.append({
            "id": isbn,
            "title": title,
            "author": author,
            "cover_url": f"https://covers.libro.fm/{isbn}_400.jpg",
            "url": f"https://libro.fm{href}",
            "price": None,   # not exposed on the search page (membership pricing)
            "isbn": isbn,
        })
    return results


@router.get("/api/libro/search")
async def libro_search(
    q: str = Query(..., min_length=1),
    limit: int = Query(10, ge=1, le=25),
    _auth=Depends(verify_bearer_token),   # your existing bearer-token dependency
):
    query = " ".join(q.split())
    if not query:
        raise HTTPException(status_code=400, detail="Query parameter 'q' is required")

    key = query.lower()
    hit = _cache.get(key)
    if hit and hit[0] > time.time():
        return hit[1][:limit]

    try:
        async with httpx.AsyncClient(timeout=8.0, follow_redirects=True) as client:
            resp = await client.get(
                "https://libro.fm/search",
                params={"q": query},
                headers={"User-Agent": BROWSER_UA,
                         "Accept": "text/html,application/xhtml+xml"},
            )
    except (httpx.TimeoutException, httpx.TransportError):
        raise HTTPException(status_code=502, detail="Libro.fm search unavailable")

    if resp.status_code != 200:
        # 403 here almost always means the User-Agent was stripped/blocked.
        raise HTTPException(status_code=502, detail="Libro.fm search unavailable")

    payload = _parse_search_html(resp.text)
    _cache[key] = (time.time() + _CACHE_TTL, payload)
    return payload[:limit]
```

**Quick verification** (no auth needed for the scrape itself):

```bash
curl -s -A "$BROWSER_UA" "https://libro.fm/search?q=Project+Hail+Mary" \
  | grep -oE 'href="/audiobooks/[^"]+"' | head
# → href="/audiobooks/9781035084111-the-traveler"  (etc.)
```

---

## How the iOS Client Uses This

For reference, the client-side flow (already implemented):

1. `PodcastHighlightManager.processHighlightAI` fetches the transcript window and
   generates the highlight summary.
2. A second AI call extracts mentioned books as JSON
   `[{ "title", "authors", "context" }]`.
3. For each book, the client calls
   `LibroAIService.searchLibroFm(query: "<title> <authors>")` → `GET /api/libro/search`.
4. The client picks the best match (see *Ordering & Matching*) and builds a
   `PodcastReference(type: .book, title, authors, url, description: context, coverUrl,
   price)`.
5. The reference is stored on the highlight and rendered in the episode's
   "References" section with cover + price + a tappable Libro.fm link. If the array is
   empty, it falls back to a `libro.fm/search?q=…` link.

---

## Priority

**Should have.** Without this endpoint the feature degrades gracefully: extracted books
still appear with a Libro.fm search deep link, just without cover art or price. With it,
references show real catalog covers, prices, and product links.
