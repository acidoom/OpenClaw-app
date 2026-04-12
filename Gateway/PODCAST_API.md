# Podcast API — Backend Specification

API endpoints required by the OpenClaw iOS podcast client. All endpoints are served from the same host as the OpenClaw Gateway (alongside existing `/api/library`, `/api/stream`, `/v1/chat/completions`, etc.).

## Authentication

All requests include:

```
Authorization: Bearer <gatewayHookToken>
Content-Type: application/json
Accept: application/json
```

Same token used for `/v1/chat/completions` and `/api/library`. Validate identically.

## JSON Convention

All response fields use **snake_case**. The iOS client auto-converts to camelCase via `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`.

Date fields should be ISO 8601 strings (e.g., `"2026-03-22T10:00:00Z"`). The client also handles Unix timestamps and `yyyy-MM-dd HH:mm:ss` SQL format as fallbacks.

---

## Endpoints

### 1. GET /api/podcasts

List all subscribed podcasts.

**Response** `200 OK`

```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "itunes_id": 1234567,
    "title": "Huberman Lab",
    "author": "Scicomm Media",
    "description": "Discusses science and science-based tools...",
    "artwork_url": "https://is1-ssl.mzstatic.com/image/thumb/...",
    "feed_url": "https://feeds.megaphone.fm/hubermanlab",
    "episode_count": 245,
    "last_refreshed_at": "2026-03-22T10:00:00Z",
    "subscribed_at": "2026-03-20T08:00:00Z"
  }
]
```

**Notes:**
- `id` — Server-generated UUID string
- `itunes_id` — Apple Podcasts collection ID. Nullable (may not always come from iTunes search)
- `artwork_url` - Absolute HTTPS URL. Nullable
- `episode_count` — Total episodes parsed from the RSS feed
- `last_refreshed_at` — When the RSS feed was last parsed. Nullable (null if never refreshed after initial subscribe)
- Return empty array `[]` if no subscriptions exist

---

### 2. POST /api/podcasts/subscribe

Subscribe to a podcast feed. The backend should immediately parse the RSS feed and store episodes.

**Request body:**

```json
{
  "feed_url": "https://feeds.megaphone.fm/hubermanlab",
  "itunes_id": 1234567,
  "title": "Huberman Lab",
  "author": "Scicomm Media",
  "artwork_url": "https://is1-ssl.mzstatic.com/image/thumb/..."
}
```

**Notes on request fields:**
- `feed_url` — **Required**. The RSS/Atom feed URL
- `itunes_id` — Nullable. Apple Podcasts collection ID (from iTunes Search API)
- `title` — **Required**. Display name
- `author` — **Required**. Podcast author/creator
- `artwork_url` — Nullable. High-res artwork URL

**Response** `200 OK` — Returns the created `Podcast` object (same shape as GET /api/podcasts items).

**Backend should:**
1. Check if already subscribed (by `feed_url`). Return existing podcast if so
2. Validate and fetch the RSS feed URL
3. Parse the feed — extract podcast metadata and all episodes
4. Generate a UUID for the podcast
5. Store podcast + episodes in the database
6. Return the podcast object with `episode_count` populated

**Error Responses:**
- `400 Bad Request` — Invalid or unreachable feed URL: `{"detail": "Could not fetch RSS feed"}`
- `409 Conflict` — Already subscribed: `{"detail": "Already subscribed to this podcast"}`

---

### 3. DELETE /api/podcasts/{podcast_id}

Unsubscribe from a podcast. Cascading delete removes episodes, playback state, highlights, and transcripts.

**Response:** Any `2xx` status code. Body ignored by iOS client.

**Backend should:**
1. Delete the podcast row (cascading deletes handle related data)
2. Optionally clean up any transcript audio files cached on disk

---

### 4. POST /api/podcasts/{podcast_id}/refresh

Re-fetch the RSS feed and add any new episodes.

**Response** `200 OK` — Returns the updated `Podcast` object with new `episode_count` and `last_refreshed_at`.

**Backend should:**
1. Fetch the RSS feed again
2. Compare episodes by GUID — insert new ones, skip existing
3. Update `episode_count` and `last_refreshed_at`
4. Throttle: reject if last refresh was < 15 minutes ago

**Error Responses:**
- `429 Too Many Requests` — Feed was refreshed too recently: `{"detail": "Feed was refreshed less than 15 minutes ago"}`
- `404 Not Found` — Unknown podcast ID

---

### 5. POST /api/podcasts/refresh-all

Re-fetch RSS feeds for **all** subscribed podcasts and add any new episodes. This is called by the iOS client on pull-to-refresh and the toolbar Refresh button, so users don't have to refresh each podcast individually.

**Response** `200 OK` — Returns the full updated array of `Podcast` objects (same shape as `GET /api/podcasts`).

```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "itunes_id": 1234567,
    "title": "Huberman Lab",
    "author": "Scicomm Media",
    "description": "Discusses science and science-based tools...",
    "artwork_url": "https://is1-ssl.mzstatic.com/image/thumb/...",
    "feed_url": "https://feeds.megaphone.fm/hubermanlab",
    "episode_count": 248,
    "last_refreshed_at": "2026-03-29T10:00:00Z",
    "subscribed_at": "2026-03-20T08:00:00Z"
  }
]
```

**Backend should:**
1. Iterate all subscribed podcasts
2. For each, fetch the RSS feed and insert any new episodes (same logic as endpoint 4)
3. Skip feeds that were refreshed within the last 15 minutes (per-feed throttle)
4. Update `episode_count` and `last_refreshed_at` for each podcast that was refreshed
5. Return the full updated list of all subscriptions (including those that were throttled/skipped)

**Notes:**
- This can take several seconds with many subscriptions. Consider fetching feeds concurrently (e.g., `Promise.all` or async pool)
- Failures on individual feeds should not fail the entire request — log the error and continue with remaining feeds
- The response includes all subscriptions, not just those that were refreshed
- Return empty array `[]` if no subscriptions exist

---

### 6. GET /api/podcasts/{podcast_id}/episodes

Paginated episode list for a podcast.

**Query parameters:**
- `page` — Page number, 1-indexed. Default: `1`
- `limit` — Episodes per page. Default: `50`, max: `100`

**Response** `200 OK`

```json
[
  {
    "id": "aae5e35a-episode-guid-from-rss",
    "podcast_id": "550e8400-e29b-41d4-a716-446655440000",
    "title": "Episode 245: Sleep Optimization",
    "description": "<p>Dr. Huberman discusses evidence-based protocols...</p>",
    "published_at": "2026-03-15T06:00:00Z",
    "duration_seconds": 7234.0,
    "audio_url": "https://traffic.megaphone.fm/GLT1234567890.mp3",
    "artwork_url": "https://...",
    "episode_number": 245,
    "season_number": null,
    "is_explicit": false,
    "transcription_status": "none"
  }
]
```

**Notes:**
- Default sort: newest first by `published_at`
- `id` — Derived from RSS `<guid>` element. If no GUID in the feed, use a hash of `audio_url`
- `description` — Raw HTML from the RSS feed. The iOS client strips HTML tags for display
- `duration_seconds` — Parsed from RSS `<itunes:duration>` (supports `HH:MM:SS`, `MM:SS`, or raw seconds). Nullable
- `audio_url` — Direct link to the MP3/M4A file from the RSS `<enclosure>` tag. **The iOS client streams directly from this URL — no gateway proxy needed**
- `artwork_url` — Episode-specific artwork. Nullable (falls back to podcast artwork on client)
- `episode_number`, `season_number` — From `<itunes:episode>` / `<itunes:season>`. Nullable
- `is_explicit` — From `<itunes:explicit>`. Default `false`
- `transcription_status` — One of: `"none"`, `"queued"`, `"processing"`, `"completed"`, `"failed"`. Default `"none"`
- Return empty array `[]` if no episodes or invalid page

---

### 7. GET /api/podcasts/episodes/latest

Latest episodes across **all** subscribed podcasts, sorted by `published_at` descending. This powers the "Latest" tab in the iOS client, giving users a unified feed of recent episodes.

**Query parameters:**
- `limit` — Max episodes to return. Default: `50`, max: `100`

**Response** `200 OK`

```json
[
  {
    "id": "aae5e35a-episode-guid",
    "podcast_id": "550e8400-e29b-41d4-a716-446655440000",
    "title": "Episode 245: Sleep Optimization",
    "description": "<p>...</p>",
    "published_at": "2026-03-21T06:00:00Z",
    "duration_seconds": 7234.0,
    "audio_url": "https://traffic.megaphone.fm/GLT1234567890.mp3",
    "artwork_url": null,
    "episode_number": 245,
    "season_number": null,
    "is_explicit": false,
    "transcription_status": "none"
  }
]
```

**Backend should:**
1. Query `podcast_episodes` JOIN `podcasts` to get episodes from all subscribed podcasts
2. Sort by `published_at DESC`
3. Limit to `limit` rows
4. Return same `PodcastEpisode` shape as endpoint 6

**Notes:**
- Return empty array `[]` if no subscriptions or no episodes
- This is a read-only convenience endpoint — no new data is stored

---

### 8. GET /api/podcasts/episodes/{episode_id}/playback

Get saved playback position for an episode.

**Response** `200 OK`

```json
{
  "episode_id": "aae5e35a-episode-guid",
  "position_seconds": 1234.5,
  "playback_speed": 1.5,
  "completed": false,
  "updated_at": "2026-03-22T10:30:00Z"
}
```

**Notes:**
- If no saved position exists, return either:
  - `{"episode_id": "...", "position_seconds": 0.0, "playback_speed": 1.0, "completed": false, "updated_at": null}`
  - Or `404 Not Found` — the iOS client wraps this in `try?` and defaults to position 0, speed 1.0

---

### 9. PUT /api/podcasts/episodes/{episode_id}/playback

Save playback position. Called by the iOS client every ~30 seconds during playback and on pause/stop.

**Request body:**

```json
{
  "position_seconds": 1234.5,
  "playback_speed": 1.5,
  "completed": false
}
```

**Response:** Any `2xx` status code. Body ignored by iOS client.

**Storage:** SQLite row keyed by `episode_id`. Upsert (insert or update). Set `updated_at` to current timestamp.

---

### 10. POST /api/podcasts/episodes/{episode_id}/transcribe

Request Whisper transcription for an episode. This is an **on-demand** operation — the user explicitly requests it because podcast episodes are typically 30-120 minutes (too costly to auto-transcribe all).

**Request body:** None (empty body or `{}`).

**Response** `200 OK`

```json
{
  "status": "queued",
  "message": "Transcription queued for episode"
}
```

**Backend should:**
1. Set `transcription_status` to `"queued"` on the episode
2. Enqueue a background job that:
   a. Downloads the audio from the episode's `audio_url`
   b. Runs Whisper transcription (reuse the existing audiobook Whisper pipeline)
   c. Stores timestamped segments in `podcast_transcripts` table
   d. Updates `transcription_status` to `"completed"` (or `"failed"` on error)
3. Return immediately — don't wait for transcription to complete

**Status progression:** `none` → `queued` → `processing` → `completed` (or `failed`)

**Notes:**
- The client polls the episode list or episode detail to check status updates
- If already transcribed (`completed`), return `200` with `"status": "completed"` — no-op
- If already in progress (`queued`/`processing`), return `200` with current status — no-op

**Error Responses:**
- `404 Not Found` — Unknown episode ID

---

### 11. GET /api/podcasts/episodes/{episode_id}/transcript

Fetch a time-windowed segment of the transcript. Used by the AI highlight system to get context around a bookmarked position.

**Query parameters:**
- `start_seconds` — Start of time window (float). **Required**
- `end_seconds` — End of time window (float). **Required**

**Response** `200 OK`

```json
{
  "episode_id": "aae5e35a-episode-guid",
  "segments": [
    {
      "text": "So the key insight here is that morning sunlight exposure",
      "start_seconds": 100.0,
      "end_seconds": 105.5,
      "speaker": null
    },
    {
      "text": "within the first 30 to 60 minutes of waking triggers",
      "start_seconds": 105.5,
      "end_seconds": 110.2,
      "speaker": null
    }
  ],
  "full_text": "So the key insight here is that morning sunlight exposure within the first 30 to 60 minutes of waking triggers"
}
```

**Notes:**
- `segments` — All transcript segments that overlap the `[start_seconds, end_seconds]` window
- `full_text` — Concatenation of all segment texts with spaces. This is what the iOS client sends to the AI for summarization
- `speaker` — Speaker label from diarization. Nullable (set to `null` if no diarization)
- Return segments ordered by `start_seconds` ascending
- The iOS client typically requests a 5-minute window before the bookmark position (e.g., `start_seconds=900&end_seconds=1200` for a bookmark at 20:00)

**Error Responses:**
- `404 Not Found` — Episode not transcribed (or unknown ID)
- `400 Bad Request` — Missing required query parameters

---

### 12. GET /api/podcasts/episodes/{episode_id}/highlights

List all AI highlights for an episode.

**Response** `200 OK`

```json
[
  {
    "id": "highlight-uuid-123",
    "episode_id": "aae5e35a-episode-guid",
    "podcast_id": "550e8400-podcast-uuid",
    "position_seconds": 1234.5,
    "start_seconds": 934.5,
    "episode_title": "Episode 245: Sleep Optimization",
    "highlight_text": "Morning sunlight exposure within the first 30-60 minutes of waking is the single most effective tool for optimizing circadian rhythm and improving nighttime sleep quality.",
    "transcript_excerpt": "So the key insight here is that morning sunlight exposure within the first 30 to 60 minutes of waking triggers a cortisol pulse that sets your circadian clock...",
    "created_at": "2026-03-22T10:00:00Z",
    "synced_at": "2026-03-22T10:00:05Z",
    "status": "completed",
    "references": [
      {
        "type": "paper",
        "title": "Timing of light exposure affects mood and brain circuits",
        "authors": "Zhao et al.",
        "url": null,
        "description": "Referenced when discussing morning light protocols for circadian rhythm"
      },
      {
        "type": "tool",
        "title": "Lux meter app",
        "authors": null,
        "url": null,
        "description": "Recommended for measuring outdoor light intensity"
      }
    ]
  }
]
```

**Notes:**
- `status` — One of: `"pending"`, `"processing"`, `"completed"`, `"failed"`. Only `"completed"` highlights will have `highlight_text` and `transcript_excerpt` populated
- `position_seconds` — The exact playback position when the user bookmarked
- `start_seconds` — Start of the transcript window (typically `position_seconds - 300`)
- `synced_at` — When the highlight was synced to the server. Nullable
- `references` — Array of extracted references (papers, books, tools, people). Nullable. Populated by the backend after transcription is available (see **Reference Extraction** section below)
- Sort by `position_seconds` descending (most recent bookmark first)
- Return empty array `[]` if no highlights

---

### 13. POST /api/podcasts/highlights

Save or update a highlight. The iOS client creates highlights locally first, processes them with AI, then syncs to the server.

**Request body:**

```json
{
  "id": "highlight-uuid-123",
  "episode_id": "aae5e35a-episode-guid",
  "podcast_id": "550e8400-podcast-uuid",
  "position_seconds": 1234.5,
  "start_seconds": 934.5,
  "episode_title": "Episode 245: Sleep Optimization",
  "highlight_text": "AI-generated summary text...",
  "transcript_excerpt": "Raw transcript text from Whisper...",
  "created_at": "2026-03-22T10:00:00Z",
  "synced_at": "2026-03-22T10:00:05Z",
  "status": "completed"
}
```

**Response:** Any `2xx` status code. Body ignored.

**Storage:** Upsert by `id`. If a highlight with the same ID exists, update it.

---

### 14. DELETE /api/podcasts/highlights/{highlight_id}

Delete a highlight.

**Response:** Any `2xx` status code. Body ignored.

**Notes:**
- Return `200` even if highlight doesn't exist (idempotent delete)

---

## Data Models

### Podcast

```json
{
  "id": "uuid-string",
  "itunes_id": 1234567,
  "title": "Huberman Lab",
  "author": "Scicomm Media",
  "description": "Discusses science and science-based tools for everyday life",
  "artwork_url": "https://is1-ssl.mzstatic.com/image/thumb/...",
  "feed_url": "https://feeds.megaphone.fm/hubermanlab",
  "episode_count": 245,
  "last_refreshed_at": "2026-03-22T10:00:00Z",
  "subscribed_at": "2026-03-20T08:00:00Z"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | string | Yes | Server-generated UUID |
| `itunes_id` | integer | No | Apple Podcasts collection ID |
| `title` | string | Yes | Podcast title |
| `author` | string | Yes | Podcast author/creator |
| `description` | string | No | Podcast description (from RSS `<description>`) |
| `artwork_url` | string | No | Absolute HTTPS URL to artwork |
| `feed_url` | string | Yes | RSS feed URL (unique constraint) |
| `episode_count` | integer | No | Total episodes from feed parse |
| `last_refreshed_at` | string | No | ISO 8601 timestamp |
| `subscribed_at` | string | Yes | ISO 8601 timestamp |

### PodcastEpisode

```json
{
  "id": "guid-from-rss-or-hashed-url",
  "podcast_id": "uuid-string",
  "title": "Episode 245: Sleep Optimization",
  "description": "<p>HTML description from RSS</p>",
  "published_at": "2026-03-15T06:00:00Z",
  "duration_seconds": 7234.0,
  "audio_url": "https://traffic.megaphone.fm/GLT1234567890.mp3",
  "artwork_url": "https://...",
  "episode_number": 245,
  "season_number": 2,
  "is_explicit": false,
  "transcription_status": "none"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | string | Yes | From RSS `<guid>`, or SHA256 hash of `audio_url` if no GUID |
| `podcast_id` | string | Yes | Foreign key to podcasts table |
| `title` | string | Yes | Episode title |
| `description` | string | No | Raw HTML from RSS. Client strips tags |
| `published_at` | string | No | ISO 8601 from RSS `<pubDate>` |
| `duration_seconds` | float | No | From `<itunes:duration>` |
| `audio_url` | string | Yes | Direct URL to audio file (from `<enclosure>`) |
| `artwork_url` | string | No | Episode-specific artwork |
| `episode_number` | integer | No | From `<itunes:episode>` |
| `season_number` | integer | No | From `<itunes:season>` |
| `is_explicit` | boolean | No | From `<itunes:explicit>`, default false |
| `transcription_status` | string | Yes | `"none"` / `"queued"` / `"processing"` / `"completed"` / `"failed"` |

### EpisodePlaybackState

```json
{
  "episode_id": "guid-from-rss",
  "position_seconds": 1234.5,
  "playback_speed": 1.5,
  "completed": false,
  "updated_at": "2026-03-22T10:00:00Z"
}
```

### PodcastHighlight

```json
{
  "id": "uuid-string",
  "episode_id": "guid-from-rss",
  "podcast_id": "uuid-string",
  "position_seconds": 1234.5,
  "start_seconds": 934.5,
  "episode_title": "Episode 245: Sleep Optimization",
  "highlight_text": "AI-generated summary...",
  "transcript_excerpt": "Raw Whisper transcript...",
  "created_at": "2026-03-22T10:00:00Z",
  "synced_at": "2026-03-22T10:00:05Z",
  "status": "completed",
  "references": [
    {
      "type": "paper",
      "title": "Attention Is All You Need",
      "authors": "Vaswani et al.",
      "url": null,
      "description": "Introduced the Transformer architecture"
    }
  ]
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | string | Yes | Client-generated UUID |
| `episode_id` | string | Yes | Foreign key to episodes |
| `podcast_id` | string | Yes | Foreign key to podcasts |
| `position_seconds` | float | Yes | Bookmark position in audio |
| `start_seconds` | float | Yes | Start of transcript window (`position - 300`) |
| `episode_title` | string | No | Denormalized for display |
| `highlight_text` | string | No | AI-generated summary (null until processed) |
| `transcript_excerpt` | string | No | Raw transcript text (null until processed) |
| `created_at` | string | Yes | ISO 8601 |
| `synced_at` | string | No | ISO 8601, null until synced |
| `status` | string | Yes | `"pending"` / `"processing"` / `"completed"` / `"failed"` |
| `references` | array | No | Extracted references. Null until backend processes transcript. See **PodcastReference** |

### PodcastReference

```json
{
  "type": "paper",
  "title": "Attention Is All You Need",
  "authors": "Vaswani et al.",
  "url": null,
  "description": "Introduced the Transformer architecture"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `type` | string | Yes | One of: `"paper"`, `"book"`, `"tool"`, `"person"` |
| `title` | string | Yes | Name of the referenced item |
| `authors` | string | No | Author names (e.g., "Vaswani et al.") |
| `url` | string | No | URL if explicitly mentioned in the podcast |
| `description` | string | No | One-sentence context for why it was mentioned |

### TranscriptSegment (within transcript response)

```json
{
  "text": "segment text from Whisper",
  "start_seconds": 100.0,
  "end_seconds": 105.5,
  "speaker": null
}
```

---

## Database Schema

```sql
CREATE TABLE podcasts (
    id TEXT PRIMARY KEY,
    itunes_id INTEGER,
    title TEXT NOT NULL,
    author TEXT NOT NULL,
    description TEXT,
    artwork_url TEXT,
    feed_url TEXT NOT NULL UNIQUE,
    episode_count INTEGER DEFAULT 0,
    last_refreshed_at TEXT,
    subscribed_at TEXT NOT NULL
);

CREATE TABLE podcast_episodes (
    id TEXT PRIMARY KEY,
    podcast_id TEXT NOT NULL REFERENCES podcasts(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    published_at TEXT,
    duration_seconds REAL,
    audio_url TEXT NOT NULL,
    artwork_url TEXT,
    episode_number INTEGER,
    season_number INTEGER,
    is_explicit BOOLEAN DEFAULT FALSE,
    transcription_status TEXT DEFAULT 'none',
    guid TEXT
);

CREATE INDEX idx_podcast_episodes_podcast_id ON podcast_episodes(podcast_id);
CREATE INDEX idx_podcast_episodes_published_at ON podcast_episodes(published_at DESC);

CREATE TABLE podcast_playback (
    episode_id TEXT PRIMARY KEY REFERENCES podcast_episodes(id) ON DELETE CASCADE,
    position_seconds REAL DEFAULT 0,
    playback_speed REAL DEFAULT 1.0,
    completed BOOLEAN DEFAULT FALSE,
    updated_at TEXT
);

CREATE TABLE podcast_highlights (
    id TEXT PRIMARY KEY,
    episode_id TEXT NOT NULL REFERENCES podcast_episodes(id) ON DELETE CASCADE,
    podcast_id TEXT NOT NULL,
    position_seconds REAL NOT NULL,
    start_seconds REAL NOT NULL,
    episode_title TEXT,
    highlight_text TEXT,
    transcript_excerpt TEXT,
    created_at TEXT NOT NULL,
    synced_at TEXT,
    status TEXT NOT NULL DEFAULT 'pending'
);

CREATE INDEX idx_podcast_highlights_episode_id ON podcast_highlights(episode_id);

CREATE TABLE podcast_transcripts (
    episode_id TEXT NOT NULL REFERENCES podcast_episodes(id) ON DELETE CASCADE,
    segment_index INTEGER NOT NULL,
    text TEXT NOT NULL,
    start_seconds REAL NOT NULL,
    end_seconds REAL NOT NULL,
    speaker TEXT,
    PRIMARY KEY (episode_id, segment_index)
);
```

---

## RSS Feed Parsing
The subscribe and refresh endpoints require parsing RSS/Atom feeds. Key RSS elements to extract:

### Podcast-level (from `<channel>`):
- `<title>` → `title`
- `<itunes:author>` or `<author>` → `author`
- `<description>` → `description`
- `<itunes:image href="...">` or `<image><url>` → `artwork_url`

### Episode-level (from each `<item>`):
- `<guid>` → `id` (fallback: SHA256 of `<enclosure url>`)
- `<title>` → `title`
- `<description>` or `<content:encoded>` → `description`
- `<pubDate>` → `published_at` (parse RFC 2822 to ISO 8601)
- `<itunes:duration>` → `duration_seconds` (handle `HH:MM:SS`, `MM:SS`, or raw seconds)
- `<enclosure url="..." type="audio/mpeg">` → `audio_url`
- `<itunes:image href="...">` → `artwork_url`
- `<itunes:episode>` → `episode_number`
- `<itunes:season>` → `season_number`
- `<itunes:explicit>` → `is_explicit` (values: `"yes"`, `"true"`, `"explicit"` → true)

**Recommended library:** `rss-parser` (Node.js/TypeScript) — handles most feed format variations.

---

## Whisper Transcription Pipeline

Reuse the existing audiobook Whisper pipeline with these adaptations:

1. **Audio download**: Fetch the MP3/M4A from `audio_url` (public CDN, no auth needed)
2. **Whisper processing**: Run `whisper` or `faster-whisper` with word-level timestamps
3. **Storage**: Store segments in `podcast_transcripts` table with `segment_index` for ordering
4. **Status updates**: Set episode `transcription_status` at each stage:
   - `"queued"` — Job enqueued
   - `"processing"` — Whisper is running
   - `"completed"` — Segments stored
   - `"failed"` — Error occurred (log error, allow retry)

**Cost consideration**: Podcast episodes are typically 30-120 minutes. Transcription is on-demand only — the user explicitly requests it per episode. Do not auto-transcribe.

---

## AI Highlight Flow (for reference)

The AI summarization happens **on the iOS client**, not the backend. The backend's role is to provide the transcript and persist highlights. The full flow:

1. User taps bookmark (or presses AirPods) → iOS creates a `PodcastHighlight` with `status: "processing"`
2. iOS calls `GET /api/podcasts/episodes/{id}/transcript?start_seconds=X&end_seconds=Y` to fetch 5 minutes of transcript before the bookmark
3. iOS sends the transcript text to `POST /v1/chat/completions` (existing Gateway chat endpoint) with a summarization prompt
4. iOS saves the AI summary to the highlight locally
5. iOS calls `POST /api/podcasts/highlights` to sync the completed highlight to the server

If the episode is not yet transcribed when the user bookmarks, the highlight is saved as `"pending"` and processed later when the user requests transcription.

---

## Reference Extraction (Backend)

When a highlight is saved to the server (`POST /api/podcasts/highlights`) with a non-empty `transcript_excerpt`, the backend automatically extracts references. This runs asynchronously — the highlight is saved immediately, and the `references` array is populated a few seconds later.

### Extraction Process

1. iOS syncs a completed highlight to the server (with `transcript_excerpt` populated)
2. Backend enqueues a reference extraction job
3. Backend sends the `transcript_excerpt` to Claude with a structured extraction prompt
4. Extracted references are stored in `podcast_highlight_references` table
5. Next time the iOS client fetches highlights (`GET /api/podcasts/episodes/{id}/highlights`), the `references` array is included

### Claude Extraction Prompt

```
Extract any research papers, books, tools, software, or notable people mentioned in this podcast transcript excerpt. For each reference found, return:
- type: "paper", "book", "tool", or "person"
- title: the name of the paper/book/tool or the person's full name
- authors: author names if mentioned (null if not stated)
- url: URL if explicitly stated in the transcript (null otherwise, do NOT guess URLs)
- description: one sentence explaining the context of why it was mentioned

Return a JSON array. If no references are found, return an empty array [].

Transcript:
{transcript_excerpt}
```

### Storage

References are stored in a separate table linked to the highlight:

```sql
CREATE TABLE podcast_highlight_references (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    highlight_id TEXT NOT NULL REFERENCES podcast_highlights(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    authors TEXT,
    url TEXT,
    description TEXT
);

CREATE INDEX idx_highlight_refs_highlight_id ON podcast_highlight_references(highlight_id);
```

When returning highlights via `GET /api/podcasts/episodes/{id}/highlights`, JOIN the references and nest them as a `references` array on each highlight object. If no references exist, return `null` or `[]`.

### Reference Types

| Type | Description | Example |
|------|-------------|---------|
| `paper` | Academic paper, study, research article | "Attention Is All You Need" |
| `book` | Published book | "Thinking, Fast and Slow" |
| `tool` | Software, app, framework, device | "PyTorch", "Whoop band" |
| `person` | Notable person mentioned | "Geoffrey Hinton" |

---

## Priority Summary

| Priority | Method | Path | Notes |
|----------|--------|------|-------|
| **Must have** | `GET` | `/api/podcasts` | Subscription list — main view depends on this |
| **Must have** | `POST` | `/api/podcasts/subscribe` | Subscribe with RSS parsing |
| **Must have** | `DELETE` | `/api/podcasts/{id}` | Unsubscribe |
| **Must have** | `GET` | `/api/podcasts/{id}/episodes` | Episode list for podcast detail |
| **Must have** | `GET` | `/api/podcasts/episodes/latest` | Latest episodes feed across all subscriptions |
| **Should have** | `POST` | `/api/podcasts/{id}/refresh` | Re-parse RSS for new episodes |
| **Should have** | `GET` | `/api/podcasts/episodes/{id}/playback` | Resume position; 404 OK as fallback |
| **Should have** | `PUT` | `/api/podcasts/episodes/{id}/playback` | Persist position; can be no-op initially |
| **Should have** | `GET` | `/api/podcasts/episodes/{id}/highlights` | List highlights |
| **Should have** | `POST` | `/api/podcasts/highlights` | Sync highlights from client |
| **Should have** | `DELETE` | `/api/podcasts/highlights/{id}` | Delete highlight |
| Later | `POST` | `/api/podcasts/episodes/{id}/transcribe` | Whisper transcription (needed for AI highlights) |
| Later | `GET` | `/api/podcasts/episodes/{id}/transcript` | Transcript segments (needed for AI highlights) |

---

## Minimum Viable Backend

To get the iOS podcast player working end-to-end, you need:

1. **SQLite tables** for podcasts, episodes, playback state
2. **RSS feed parser** that extracts episodes on subscribe and refresh
3. **CRUD endpoints** for subscriptions (GET list, POST subscribe, DELETE unsubscribe)
4. **Episode list endpoint** with pagination
5. **Playback state** GET/PUT for resume position

Everything else (Whisper transcription, transcript endpoints, highlights) can be added later. Without transcription, bookmarks are saved locally as `"pending"` and will auto-process once transcription is available.

**No audio streaming endpoint needed** — podcast episodes stream directly from the podcast CDN URLs. The gateway never proxies audio.

