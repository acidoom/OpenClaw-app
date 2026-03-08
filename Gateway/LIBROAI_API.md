# LibroAI Backend API Requirements

API endpoints required by the OpenClaw iOS audiobook client. All endpoints are served from the same host as the OpenClaw Gateway.

## Authentication

All requests include:

```
Authorization: Bearer <gatewayHookToken>
Content-Type: application/json
Accept: application/json
```

Same token used for `/v1/chat/completions`. Validate identically.

## JSON Convention

All response fields use **snake_case**. The iOS client auto-converts to camelCase via `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`.

---

## Endpoints

### 1. GET /api/library

List all audiobooks.

**Response** `200 OK`

```json
[
  {
    "id": "abc123",
    "title": "Project Hail Mary",
    "author": "Andy Weir",
    "narrator": "Ray Porter",
    "duration_seconds": 58320.0,
    "cover_url": "/api/covers/abc123.jpg",
    "local_path": "/data/audiobooks/abc123.m4b",
    "format": "m4b",
    "downloaded": true,
    "transcribed": false,
    "indexed": false,
    "summarized": false,
    "diarized": false
  }
]
```

**Notes:**
- `id` — Unique string identifier (Libro.fm audiobook ID or UUID)
- `cover_url` — Relative path (appended to base URL) or absolute `http(s)://` URL. Can be `null`
- `format` — Either `"m4b"` or `"mp3"`
- `narrator`, `local_path` — Nullable
- Boolean flags (`downloaded`, `transcribed`, `indexed`, `summarized`, `diarized`) — Processing pipeline status

---

### 2. GET /api/library/{id}

Single audiobook detail.

**Response** `200 OK` — Same shape as one element of the `/api/library` array.

**Priority:** Nice to have. The iOS client currently uses the library list.

---

### 3. POST /api/library/sync

Trigger a Libro.fm library sync (fetch new purchases, download audio files).

**Response** `200 OK`

```json
{
  "status": "success",
  "message": "Library is up to date",
  "books_added": 0
}
```

**Notes:**
- `status` — `"success"` or `"error"`
- `message` — Human-readable status string. Nullable
- `books_added` — Number of new audiobooks added. Nullable

**Priority:** Nice to have. Only used when user explicitly taps "Sync from Libro.fm".

---

### 4. GET /api/chapters/{audiobook_id}

Chapter list for an audiobook, sorted by `chapter_index`.

**Response** `200 OK`

```json
[
  {
    "id": 1,
    "audiobook_id": "abc123",
    "title": "Chapter 1: The Problem",
    "start_seconds": 0.0,
    "end_seconds": 1845.5,
    "chapter_index": 0,
    "summary": null
  },
  {
    "id": 2,
    "audiobook_id": "abc123",
    "title": "Chapter 2: Rocky",
    "start_seconds": 1845.5,
    "end_seconds": 3720.0,
    "chapter_index": 1,
    "summary": null
  }
]
```

**Notes:**
- `id` — Unique integer ID per chapter
- `chapter_index` — Zero-based, used for ordering and next/previous navigation
- `start_seconds`, `end_seconds` — Timestamp boundaries within the audio file
- `summary` — AI-generated chapter summary. Nullable (populated later by AI pipeline)
- Chapters must be contiguous (no gaps) and sorted by `chapter_index`

**Source:** Parse from M4B chapter atoms (`mutagen` / `ffprobe -show_chapters`) or MP3 file boundaries.

---

### 5. GET /api/stream/{audiobook_id}

Stream the audio file. This is the most critical endpoint.

**Request headers from AVPlayer:**

```
Authorization: Bearer <token>
Range: bytes=0-65535
```

**Response** `206 Partial Content` (or `200 OK` for full file)

**Required response headers:**

```
Content-Type: audio/mp4          (for M4B)
Content-Type: audio/mpeg         (for MP3)
Accept-Ranges: bytes
Content-Range: bytes 0-65535/58320000
Content-Length: 65536
```

**Implementation requirements:**
- **Must support HTTP Range requests** — AVPlayer uses them for seeking. Without Range support, seeking will not work
- Return `206 Partial Content` for ranged requests, `200 OK` for full file requests
- Set correct `Content-Type` based on format
- Set `Accept-Ranges: bytes` header
- Set `Content-Length` for the response chunk (not the full file)
- Set `Content-Range: bytes start-end/total` for ranged responses

**FastAPI example:**

```python
from fastapi import Request
from fastapi.responses import StreamingResponse
from pathlib import Path

@app.get("/api/stream/{audiobook_id}")
async def stream_audio(audiobook_id: str, request: Request):
    # Look up audiobook, get file path
    book = get_audiobook(audiobook_id)
    file_path = Path(book.local_path)
    file_size = file_path.stat().st_size
    content_type = "audio/mp4" if book.format == "m4b" else "audio/mpeg"

    range_header = request.headers.get("range")

    if range_header:
        # Parse "bytes=start-end"
        range_spec = range_header.replace("bytes=", "")
        parts = range_spec.split("-")
        start = int(parts[0])
        end = int(parts[1]) if parts[1] else file_size - 1
        end = min(end, file_size - 1)
        length = end - start + 1

        def iter_file():
            with open(file_path, "rb") as f:
                f.seek(start)
                remaining = length
                while remaining > 0:
                    chunk = f.read(min(8192, remaining))
                    if not chunk:
                        break
                    remaining -= len(chunk)
                    yield chunk

        return StreamingResponse(
            iter_file(),
            status_code=206,
            headers={
                "Content-Type": content_type,
                "Content-Range": f"bytes {start}-{end}/{file_size}",
                "Content-Length": str(length),
                "Accept-Ranges": "bytes",
            },
        )
    else:
        # Full file
        def iter_full():
            with open(file_path, "rb") as f:
                while chunk := f.read(8192):
                    yield chunk

        return StreamingResponse(
            iter_full(),
            headers={
                "Content-Type": content_type,
                "Content-Length": str(file_size),
                "Accept-Ranges": "bytes",
            },
        )
```

---

### 6. GET /api/playback/{audiobook_id}

Get saved playback position.

**Response** `200 OK`

```json
{
  "audiobook_id": "abc123",
  "position_seconds": 3456.7,
  "playback_speed": 1.5,
  "updated_at": "2026-02-28T10:30:00Z"
}
```

**Notes:**
- If no saved position exists, return either:
  - `{"audiobook_id": "abc123", "position_seconds": 0.0, "playback_speed": 1.0, "updated_at": null}`
  - Or `404 Not Found` — the iOS client wraps this in `try?` and defaults to position 0, speed 1.0

---

### 7. PUT /api/playback/{audiobook_id}

Save playback position. Called by the iOS client every ~30 seconds during playback and on pause.

**Request body:**

```json
{
  "position_seconds": 3456.7,
  "playback_speed": 1.5
}
```

**Response:** Any `2xx` status code. The iOS client ignores the response body.

**Storage:** SQLite row keyed by `audiobook_id`. Upsert (insert or update).

---

## Priority Summary

| Priority | Method | Path | Notes |
|----------|--------|------|-------|
| **Must have** | `GET` | `/api/library` | Without this, nothing shows |
| **Must have** | `GET` | `/api/stream/{id}` | Audio playback; needs Range support |
| **Must have** | `GET` | `/api/chapters/{id}` | Chapter navigation; empty array `[]` is OK as fallback |
| **Should have** | `GET` | `/api/playback/{id}` | Resume from last position; 404 OK as fallback |
| **Should have** | `PUT` | `/api/playback/{id}` | Persist position; can be no-op initially |
| Nice to have | `GET` | `/api/library/{id}` | Single book detail |
| Nice to have | `POST` | `/api/library/sync` | Libro.fm sync trigger |

---

## Libro.fm Integration Endpoints

The following endpoints enable Libro.fm account management from the iOS app. The backend manages the Libro.fm session server-side; the iOS client only sends credentials once for login.

### 8. GET /api/libro/status

Check Libro.fm connection status.

**Response** `200 OK`

```json
{
  "connected": true,
  "email": "user@example.com"
}
```

**Notes:**
- `connected` — Whether a valid Libro.fm session exists on the server
- `email` — The account email. Nullable (null when not connected)

---

### 9. POST /api/libro/auth

Login to Libro.fm.

**Request body:**

```json
{
  "email": "user@example.com",
  "password": "their_password"
}
```

**Response** `200 OK`

```json
{
  "status": "success",
  "message": "Logged in successfully",
  "email": "user@example.com"
}
```

**Error Response** `401 Unauthorized`

```json
{
  "status": "error",
  "message": "Invalid email or password",
  "email": null
}
```

**Notes:**
- Backend should authenticate with Libro.fm and store the session/cookie server-side
- Do NOT return the Libro.fm session token to the iOS client — keep it server-side
- `status` — `"success"` or `"error"`

---

### 10. DELETE /api/libro/auth

Logout / disconnect Libro.fm account.

**Response** `200 OK`

```json
{
  "status": "success",
  "message": "Disconnected from Libro.fm"
}
```

**Notes:**
- Clear the stored Libro.fm session on the server
- Response body is ignored by the iOS client (any 2xx is fine)

---

### 11. GET /api/libro/books

List purchased Libro.fm audiobooks available for download.

**Response** `200 OK`

```json
[
  {
    "id": "libro-abc123",
    "title": "Project Hail Mary",
    "author": "Andy Weir",
    "cover_url": "https://libro.fm/covers/abc123.jpg",
    "in_library": false
  },
  {
    "id": "libro-def456",
    "title": "The Martian",
    "author": "Andy Weir",
    "cover_url": "https://libro.fm/covers/def456.jpg",
    "in_library": true
  }
]
```

**Notes:**
- `id` — Libro.fm's book identifier
- `cover_url` — Absolute URL to cover image on Libro.fm's CDN. Nullable
- `in_library` — Whether this book has already been downloaded to the server's local library
- The backend should scrape/API-call the user's Libro.fm library to get this list
- Cross-reference with local audiobooks table to set `in_library` flag

---

### 12. POST /api/libro/download/{book_id}

Start downloading a Libro.fm book to the server.

**Response** `200 OK`

```json
{
  "status": "started",
  "job_id": "job-uuid-1234",
  "message": "Download queued"
}
```

**Error Response** `400 Bad Request`

```json
{
  "status": "error",
  "job_id": "",
  "message": "Book already in library"
}
```

**Notes:**
- Downloads run asynchronously on the server (background task)
- `job_id` — Unique ID to track this download job's progress
- The server should download the DRM-free audio file from Libro.fm, extract chapters, and add to the library

---

### 13. GET /api/libro/downloads

List all download jobs and their statuses.

**Response** `200 OK`

```json
[
  {
    "id": "job-uuid-1234",
    "book_id": "libro-abc123",
    "title": "Project Hail Mary",
    "status": "downloading",
    "progress": 0.45,
    "error_message": null
  },
  {
    "id": "job-uuid-5678",
    "book_id": "libro-def456",
    "title": "The Martian",
    "status": "completed",
    "progress": 1.0,
    "error_message": null
  }
]
```

**Notes:**
- `status` — One of: `"queued"`, `"downloading"`, `"completed"`, `"failed"`
- `progress` — 0.0 to 1.0. Nullable (null for queued jobs)
- `error_message` — Nullable. Set when `status` is `"failed"`
- The iOS client polls this endpoint every 5 seconds while downloads are active
- Clear completed/failed jobs after 24 hours or provide a separate cleanup endpoint

---

## Priority Summary

| Priority | Method | Path | Notes |
|----------|--------|------|-------|
| **Must have** | `GET` | `/api/library` | Without this, nothing shows |
| **Must have** | `GET` | `/api/stream/{id}` | Audio playback; needs Range support |
| **Must have** | `GET` | `/api/chapters/{id}` | Chapter navigation; empty array `[]` is OK as fallback |
| **Should have** | `GET` | `/api/playback/{id}` | Resume from last position; 404 OK as fallback |
| **Should have** | `PUT` | `/api/playback/{id}` | Persist position; can be no-op initially |
| **Should have** | `GET` | `/api/libro/status` | Libro.fm connection check |
| **Should have** | `POST` | `/api/libro/auth` | Libro.fm login |
| **Should have** | `DELETE` | `/api/libro/auth` | Libro.fm logout |
| **Should have** | `GET` | `/api/libro/books` | Browse Libro.fm purchases |
| **Should have** | `POST` | `/api/libro/download/{id}` | Start downloading a book |
| **Should have** | `GET` | `/api/libro/downloads` | Track download progress |
| Nice to have | `GET` | `/api/library/{id}` | Single book detail |
| Nice to have | `POST` | `/api/library/sync` | Libro.fm sync trigger |

## Local Download (to Device)

The iOS client can download audiobook files to the device for offline playback. This reuses the existing `GET /api/stream/{audiobook_id}` endpoint — when no `Range` header is sent, the server returns the full audio file (`200 OK` instead of `206 Partial Content`).

**No new backend endpoint is required.** The existing stream endpoint already supports both:
- **Streaming (with `Range` header)** → `206 Partial Content` with chunked response
- **Full download (no `Range` header)** → `200 OK` with full file

The iOS client downloads the file using `URLSession.bytes(for:)` and saves it to the app's Documents/Audiobooks directory. When a local file exists, AVPlayer uses it directly instead of streaming.

**Required response headers for full download:**

```
Content-Type: audio/mp4 (or audio/mpeg)
Content-Length: <total file size>
Accept-Ranges: bytes
```

---

## Minimum Viable Backend

To get the iOS player working, you need:

1. A SQLite table of audiobooks with metadata
2. Audio files on disk (M4B or MP3)
3. Chapter data extracted from audio files (`ffprobe -show_chapters`)
4. A file server with Range header support and Bearer token auth

Everything else (sync, playback state, AI pipeline, Libro.fm integration) can be stubbed or added later.
