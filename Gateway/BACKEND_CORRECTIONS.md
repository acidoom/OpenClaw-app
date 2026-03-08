# Backend Corrections Required

Bugs and inconsistencies discovered during iOS client integration testing. These must be fixed server-side before the audiobook feature works end-to-end.

---

## Bug 1: Download endpoint rejects re-download when audio file is missing

**Endpoint:** `POST /api/libro/download/{book_id}`

**Symptom:** Returns `400 Bad Request` with `{"detail": "Book already in library"}` even though the audio file does not exist on disk.

**Root cause:** The endpoint checks only whether a database record exists for the book. It does not verify that the actual audio file is present on the filesystem.

**Evidence from logs:**

```
POST /api/libro/download/... → 400 {"detail":"Book already in library"}
GET /api/stream/...          → 404 {"detail":"No local file for this audiobook"}
GET /api/library             → "downloaded": false
```

The `downloaded` flag in `/api/library` is `false`, confirming the file doesn't exist. But the download endpoint refuses to re-download because the DB row exists.

**Required fix:** Before returning "Book already in library", verify the audio file exists on disk:

```python
@app.post("/api/libro/download/{book_id}")
async def download_book(book_id: str):
    book = db.get_audiobook_by_libro_id(book_id)
    
    if book:
        # Check BOTH database AND filesystem
        file_exists = book.local_path and Path(book.local_path).exists()
        if file_exists:
            raise HTTPException(400, detail="Book already in library")
        # File missing — delete stale DB record and re-download
        db.delete_audiobook(book.id)
    
    # Proceed with download
    job = start_download_job(book_id)
    return {"status": "started", "job_id": job.id, "message": "Download queued"}
```

**Alternative:** Add a separate "re-download" or "repair" endpoint that forces a fresh download regardless of DB state.

---

## Bug 2: Stream endpoint returns 404 for books without audio files

**Endpoint:** `GET /api/stream/{audiobook_id}`

**Symptom:** Returns `404` with `{"detail": "No local file for this audiobook"}`.

**Root cause:** This is a downstream consequence of Bug 1 — the book was added to the database during a Libro.fm sync or partial download, but the actual audio file was never saved to disk (or was lost).

**Required fix:** This is fixed implicitly by Bug 1. Once the download endpoint properly handles missing files, the stream endpoint will work because the file will actually exist.

**Additional hardening:** The `/api/library` endpoint should verify file existence when setting the `downloaded` flag:

```python
# In the library endpoint
audiobook.downloaded = audiobook.local_path is not None and Path(audiobook.local_path).exists()
```

This ensures the iOS client gets an accurate `downloaded` flag and can show the correct UI state.

---

## Bug 3: Chapters endpoint returns empty array

**Endpoint:** `GET /api/chapters/{audiobook_id}`

**Symptom:** Returns `[]` (empty array) for audiobooks that should have chapters.

**Expected behavior:** M4B files contain embedded chapter metadata. After downloading an audiobook, the backend should extract chapters using `ffprobe` or `mutagen` and store them in the database.

**Required fix:** After a successful Libro.fm download completes:

1. Extract chapters from the audio file:
   ```bash
   ffprobe -v quiet -print_format json -show_chapters "path/to/audiobook.m4b"
   ```

2. Parse the output and insert chapter records:
   ```python
   for i, chapter in enumerate(chapters):
       db.insert_chapter(
           audiobook_id=book.id,
           title=chapter.get("tags", {}).get("title", f"Chapter {i + 1}"),
           start_seconds=float(chapter["start_time"]),
           end_seconds=float(chapter["end_time"]),
           chapter_index=i
       )
   ```

3. For MP3 audiobooks without embedded chapters, either:
   - Create a single chapter spanning the full duration, or
   - Use silence detection to auto-split chapters

**Impact:** Without chapters, the iOS chapter navigation UI is empty and users cannot jump to specific sections.

---

## Bug 4: Playback endpoint returns 404 with wrong format

**Endpoint:** `GET /api/playback/{audiobook_id}`

**Symptom:** Returns `404` with `{"detail": "No saved position"}` instead of the expected format.

**Expected behavior per API spec:** When no saved position exists, return either:
- `200 OK` with `{"audiobook_id": "...", "position_seconds": 0.0, "playback_speed": 1.0, "updated_at": null}`
- Or `404 Not Found` (the iOS client handles this gracefully via `try?`)

**Current behavior:** The `404` response body uses `"detail"` key which doesn't match the documented response shape. While the iOS client does handle this case (defaults to position 0), the inconsistency should be noted.

**Required fix:** This is low priority. The iOS client already handles `404` correctly. However, for consistency, the error response should use the FastAPI/standard format. No action needed unless you want to return a default position object instead of 404.

---

## Bug 5: `in_library` flag inconsistency in Libro.fm books list

**Endpoint:** `GET /api/libro/books`

**Symptom:** The `in_library` field may report `true` for books whose audio files don't actually exist on disk (same root cause as Bug 1).

**Required fix:** Cross-reference should check both the database record AND filesystem:

```python
in_library = (
    local_book is not None 
    and local_book.local_path is not None 
    and Path(local_book.local_path).exists()
)
```

---

## Summary

| Bug | Endpoint | Severity | Fix |
|-----|----------|----------|-----|
| 1 | `POST /api/libro/download/{id}` | **Critical** | Check file existence, not just DB record |
| 2 | `GET /api/stream/{id}` | **Critical** | Implicit fix via Bug 1; harden `downloaded` flag |
| 3 | `GET /api/chapters/{id}` | **High** | Extract chapters from M4B after download |
| 4 | `GET /api/playback/{id}` | Low | Cosmetic — iOS handles 404 fine |
| 5 | `GET /api/libro/books` | Medium | Check file existence for `in_library` flag |

**The core issue is Bug 1.** The download pipeline created a database record without successfully saving the audio file to disk. All other bugs are downstream consequences of this state inconsistency between the database and filesystem.

### Recommended approach

Add a filesystem check everywhere the backend reports "this book exists locally":
- `/api/libro/download/{id}` — before rejecting as duplicate
- `/api/library` — when setting `downloaded` flag  
- `/api/libro/books` — when setting `in_library` flag
- `/api/stream/{id}` — already correctly checks (returns 404)

This single pattern — "trust the filesystem, not just the database" — resolves all five bugs.
---

# New Endpoints Required: AI Highlights

The iOS client now supports AI-powered audiobook highlights. Four new backend endpoints are needed.

---

## Endpoint 1: Get highlights for an audiobook

**Method:** `GET /api/highlights/{audiobook_id}`

**Description:** Returns all saved highlights for the given audiobook, ordered by `position_seconds` ascending.

**Response (200):**

```json
[
  {
    "id": "4634338F-8707-4506-86E3-E10AC4891B49",
    "audiobook_id": "9781663757166",
    "position_seconds": 54.0,
    "start_seconds": 0.0,
    "chapter_title": "Chapter 1",
    "highlight_text": "AI-generated 2-3 sentence summary of the passage.",
    "transcript_excerpt": "The raw transcript text that was summarized.",
    "created_at": "2026-02-28T12:34:56Z",
    "synced_at": "2026-02-28T12:35:00Z",
    "status": "completed"
  }
]
```

**Response when no highlights exist:** Return `200` with `[]` (empty array), **not** `404`.

The iOS client currently receives `404` which triggers error logging. An empty array is the correct response for "no highlights yet."

**Schema notes:**
- `id` is a client-generated UUID string
- `status` is one of: `pending`, `processing`, `completed`, `failed`
- `highlight_text`, `transcript_excerpt`, `chapter_title`, `synced_at` are nullable
- Dates are ISO 8601 format

---

## Endpoint 2: Save/upsert a highlight

**Method:** `POST /api/highlights`

**Description:** Creates or updates a highlight. The `id` is client-generated, so use upsert semantics (insert if new, update if ID exists).

**Request body:**

```json
{
  "id": "4634338F-8707-4506-86E3-E10AC4891B49",
  "audiobook_id": "9781663757166",
  "position_seconds": 54.0,
  "start_seconds": 0.0,
  "chapter_title": "Chapter 1",
  "highlight_text": "AI summary text.",
  "transcript_excerpt": "Raw transcript.",
  "created_at": "2026-02-28T12:34:56Z",
  "synced_at": null,
  "status": "completed"
}
```

**Response (200/201):**

```json
{
  "id": "4634338F-8707-4506-86E3-E10AC4891B49",
  "status": "saved"
}
```

**Notes:**
- The server should set `synced_at` to the current timestamp on save
- All fields from the request body should be stored as-is (the iOS client handles AI processing)

---

## Endpoint 3: Delete a highlight

**Method:** `DELETE /api/highlights/{highlight_id}`

**Description:** Deletes a single highlight by its ID.

**Response (204):** No content.

**Response (404):** If the highlight doesn't exist, return `404`. The iOS client handles this gracefully (the highlight was already deleted server-side).

---

## Endpoint 4: Get transcript for a time range

**Method:** `GET /api/transcript/{audiobook_id}?start_seconds=X&end_seconds=Y`

**Description:** Returns the transcript text for the specified time range of an audiobook. Used by the iOS client to fetch the last ~5 minutes of audio before a bookmark, which is then sent to the AI for summarization.

**Query parameters:**
- `start_seconds` (float, required) — start of the time range
- `end_seconds` (float, required) — end of the time range

**Response (200):**

```json
{
  "audiobook_id": "9781663757166",
  "segments": [
    {
      "text": "It was a bright cold day in April...",
      "start_seconds": 0.0,
      "end_seconds": 15.5,
      "speaker": null
    },
    {
      "text": "The clocks were striking thirteen.",
      "start_seconds": 15.5,
      "end_seconds": 22.3,
      "speaker": null
    }
  ],
  "full_text": "It was a bright cold day in April... The clocks were striking thirteen."
}
```

**Response (404):** If the audiobook has not been transcribed yet.

**Notes:**
- `segments` contains individual transcript segments that overlap with the requested time range
- `full_text` is the concatenation of all segment texts (convenience field for AI processing)
- `speaker` is nullable — only populated if speaker diarization was performed
- The iOS client requests a 300-second (5 minute) window: `start_seconds = current_position - 300`, `end_seconds = current_position`

---

## Database schema suggestion

```sql
CREATE TABLE highlights (
    id TEXT PRIMARY KEY,           -- Client-generated UUID
    audiobook_id TEXT NOT NULL,    -- FK to audiobooks table
    position_seconds REAL NOT NULL,
    start_seconds REAL NOT NULL DEFAULT 0,
    chapter_title TEXT,
    highlight_text TEXT,
    transcript_excerpt TEXT,
    created_at TEXT NOT NULL,      -- ISO 8601
    synced_at TEXT,                -- ISO 8601, set on server save
    status TEXT NOT NULL DEFAULT 'pending',
    FOREIGN KEY (audiobook_id) REFERENCES audiobooks(id)
);

CREATE INDEX idx_highlights_audiobook ON highlights(audiobook_id);
```

---

## Bug 6: Stream endpoint serves DRM-encrypted audio files without decryption

**Endpoint:** `GET /api/stream/{audiobook_id}`

**Symptom:** AVPlayer fails with "Cannot Open" for both local file and streaming playback. The detailed error is:

```
AVFoundationErrorDomain, code: -11829
Underlying: NSOSStatusErrorDomain, code: -12848 (media data unreadable/unsupported format)
```

**Affected audiobook:** `9780008711511` (104 MB M4B file)

**Root cause:** Some Libro.fm audiobooks are DRM-encrypted (Adobe Digital Editions DRM). The backend downloaded the encrypted `.m4b` file as-is and serves it without decryption. AVPlayer cannot play DRM-protected M4B files — it only supports Apple's FairPlay DRM, not Adobe DRM.

**Evidence:**
- Local file exists, correct size (104 MB), but `AVAsset.isPlayable` returns `false`
- Streaming the same file from the backend also fails with the same error
- Other audiobooks (e.g., `9781663757166`) play fine — those are likely DRM-free

**Required fix:** The backend download pipeline must strip DRM before saving the audio file. Options:

1. **Use Libro.fm's DRM-free download option** (preferred): Libro.fm offers DRM-free downloads for most titles. The download pipeline should request the DRM-free version. Check if the Libro.fm API or download page provides a DRM-free download link.

2. **DeDRM during download**: If DRM-free downloads aren't available for all titles, use a library like `ffmpeg` with the appropriate decryption key to strip Adobe DRM before saving.

3. **Flag unplayable files**: At minimum, after downloading, verify the file is playable:
   ```python
   import subprocess
   result = subprocess.run(
       ["ffprobe", "-v", "error", "-show_format", path],
       capture_output=True, text=True
   )
   if result.returncode != 0:
       # File is likely DRM-encrypted or corrupt
       audiobook.playable = False
       audiobook.drm_protected = True
   ```

4. **Add a `drm_protected` or `playable` field** to the `/api/library` response so the iOS client can show appropriate UI (e.g., "This title requires DRM removal on the server").

**Impact:** Users cannot play DRM-protected audiobooks at all — neither locally nor via streaming.

---

## Summary (updated)

| Bug/Feature | Endpoint | Severity | Status |
|-------------|----------|----------|--------|
| 1 | `POST /api/libro/download/{id}` | **Critical** | Bug — check file existence |
| 2 | `GET /api/stream/{id}` | **Critical** | Bug — implicit fix via Bug 1 |
| 3 | `GET /api/chapters/{id}` | **High** | Bug — extract chapters from M4B |
| 4 | `GET /api/playback/{id}` | Low | Bug — cosmetic 404 format |
| 5 | `GET /api/libro/books` | Medium | Bug — check file for `in_library` |
| 6 | `GET /api/stream/{id}` | **Critical** | Bug — DRM-encrypted files unplayable |
| 7 | `GET /api/highlights/{audiobook_id}` | **High** | New — return highlights array |
| 8 | `POST /api/highlights` | **High** | New — upsert highlight |
| 9 | `DELETE /api/highlights/{id}` | **High** | New — delete highlight |
| 10 | `GET /api/transcript/{audiobook_id}` | **High** | New — transcript for time range |

