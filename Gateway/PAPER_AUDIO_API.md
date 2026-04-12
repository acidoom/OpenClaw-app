# Paper Audio Backend API Requirements

API endpoints for the Paper-to-Audiobook pipeline. Converts research papers from Zotero into spoken audio using Claude (script generation) and ElevenLabs (TTS synthesis).

All endpoints are served from the same host as the OpenClaw Gateway.

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

---

## Endpoints

### 1. POST /api/paper-audio/generate

Start a paper audio generation job. The backend runs the full pipeline asynchronously.

**Request body:**

```json
{
  "zotero_item_key": "ABC123XY",
  "paper_title": "Attention Is All You Need",
  "mode": "runner",
  "skip_equations": true,
  "skip_tables": true,
  "skip_references": true,
  "summarize_figures": true,
  "explain_jargon": true,
  "voice_id": "default"
}
```

**Fields:**
- `zotero_item_key` — Zotero item key. Backend uses this to fetch the paper from Zotero API
- `paper_title` — Display title (used for metadata, not for fetching)
- `mode` — One of: `"summary"`, `"runner"`, `"deep_dive"`
- `skip_equations` — If true, summarize equations in plain language instead of reading them
- `skip_tables` — If true, omit table narration
- `skip_references` — If true, remove citation markers and bibliography
- `summarize_figures` — If true, briefly describe key figures
- `explain_jargon` — If true, define technical terms once in simple language
- `voice_id` — ElevenLabs voice ID. `"default"` uses the server's configured default voice

**Response** `200 OK`

```json
{
  "id": "job-uuid-1234",
  "zotero_item_key": "ABC123XY",
  "paper_title": "Attention Is All You Need",
  "mode": "runner",
  "status": "queued",
  "progress": null,
  "total_duration_sec": null,
  "error_message": null,
  "created_at": "2026-03-15T10:00:00Z",
  "completed_at": null
}
```

---

### 2. GET /api/paper-audio/jobs

List all paper audio jobs, ordered by `created_at` descending.

**Response** `200 OK`

```json
[
  {
    "id": "job-uuid-1234",
    "zotero_item_key": "ABC123XY",
    "paper_title": "Attention Is All You Need",
    "mode": "runner",
    "status": "completed",
    "progress": 1.0,
    "total_duration_sec": 720.5,
    "error_message": null,
    "created_at": "2026-03-15T10:00:00Z",
    "completed_at": "2026-03-15T10:05:30Z"
  },
  {
    "id": "job-uuid-5678",
    "zotero_item_key": "DEF456ZW",
    "paper_title": "BERT: Pre-training of Deep Bidirectional Transformers",
    "mode": "summary",
    "status": "generating_script",
    "progress": 0.45,
    "total_duration_sec": null,
    "error_message": null,
    "created_at": "2026-03-15T10:10:00Z",
    "completed_at": null
  }
]
```

---

### 3. GET /api/paper-audio/jobs/{job_id}

Get a single job's status.

**Response** `200 OK` — Same shape as one element of the jobs array.

**Status values** (in order of pipeline progression):

```
queued → extracting_text → cleaning_text → generating_script → synthesizing_audio → assembling_manifest → completed
```

Or `failed` at any point.

---

### 4. GET /api/paper-audio/{job_id}/manifest

Get the playback manifest for a completed job. Returns section structure and chunk metadata.

**Response** `200 OK`

```json
{
  "job_id": "job-uuid-1234",
  "paper_title": "Attention Is All You Need",
  "mode": "runner",
  "total_duration_sec": 720.5,
  "sections": [
    {
      "id": "introduction",
      "name": "Introduction",
      "start_sec": 0.0,
      "duration_sec": 120.5,
      "chunks": [
        {
          "id": 0,
          "index": 0,
          "text": "This paper introduces the Transformer architecture...",
          "audio_url": "/api/paper-audio/job-uuid-1234/chunks/0",
          "duration_sec": 28.3
        },
        {
          "id": 1,
          "index": 1,
          "text": "Unlike previous sequence models that rely on recurrence...",
          "audio_url": "/api/paper-audio/job-uuid-1234/chunks/1",
          "duration_sec": 32.1
        }
      ]
    },
    {
      "id": "method",
      "name": "Method",
      "start_sec": 120.5,
      "duration_sec": 240.0,
      "chunks": [...]
    }
  ]
}
```

**Notes:**
- `sections[].id` — Unique section identifier (lowercase section name or slug)
- `sections[].start_sec` — Start time within the concatenated audio file
- `sections[].chunks[].text` — The spoken script text for this chunk (used for transcript display)
- `sections[].chunks[].audio_url` — Individual chunk audio URL (optional, for future use)
- Sections must be contiguous and ordered by `start_sec`

---

### 5. GET /api/paper-audio/{job_id}/stream

Stream the complete concatenated audio file. **This is the primary playback endpoint.**

**Request headers from AVPlayer:**

```
Authorization: Bearer <token>
Range: bytes=0-65535
```

**Response** `206 Partial Content` (or `200 OK` for full file)

**Required response headers:**

```
Content-Type: audio/mpeg
Accept-Ranges: bytes
Content-Range: bytes 0-65535/720000
Content-Length: 65536
```

**Implementation requirements:**
- **Must support HTTP Range requests** — AVPlayer uses them for seeking
- Return `206 Partial Content` for ranged requests, `200 OK` for full file requests
- Audio format: MP3 (concatenated from TTS chunks)
- Set `Accept-Ranges: bytes` header
- Set `Content-Length` for the response chunk
- Set `Content-Range: bytes start-end/total` for ranged responses

---

### 6. DELETE /api/paper-audio/jobs/{job_id}

Delete a job and its associated audio files.

**Response** `200 OK`

```json
{
  "status": "deleted",
  "message": "Job and audio files deleted"
}
```

---

### 7. POST /api/paper-audio/jobs/{job_id}/cancel

Cancel an in-progress job. No effect if job is already completed or failed.

**Response** `200 OK`

```json
{
  "status": "cancelled",
  "message": "Job cancelled"
}
```

---

## Backend Pipeline

When `POST /api/paper-audio/generate` is called, the backend should run this pipeline asynchronously:

### Step 1: Fetch Paper Content (`extracting_text`)
- Use the `zotero_item_key` to fetch the paper from Zotero API
- Extract: title, authors, abstract, full text
- If the Zotero item has an attached PDF, extract text from the PDF
- If no PDF, use the abstract and any available full text from the Zotero metadata
- Prefer preserving section structure over preserving exact layout

### Step 2: Clean Text (`cleaning_text`)
- Remove page headers/footers, page numbers
- Fix hyphenated line breaks
- Merge broken lines into paragraphs
- Strip conference/journal boilerplate
- Detect and remove bibliography
- Detect inline citations: `[12]`, `(Smith et al., 2024)`, superscripts
- Reduce figure/table caption noise

### Step 3: Generate Listening Script (`generating_script`)
Call Claude with mode-specific prompts. The script should be spoken-word text, not the raw paper.

**System prompt:**

```
You are rewriting a research paper into spoken audio for a listener who may be running.
Your job is to preserve meaning while improving listenability.

Rules:
- Do not invent claims, results, or limitations.
- Remove inline citations and reference markers.
- Do not read bibliography entries.
- Convert equations into brief conceptual explanations unless explicitly asked to retain them.
- Prefer short, natural spoken sentences.
- Preserve uncertainty and limitations from the original paper.
- When terms are highly technical, explain them once in simple language.
- Organize output with clear section labels.
- Produce narration text only.
```

**Summary mode prompt:**

```
Create a 2 to 5 minute spoken summary of this research paper.

Must include:
- the main problem
- the proposed idea
- the main result
- the main limitation
- why it matters

Avoid:
- references
- equation recitation
- long methodological detail

Paper text:
{{cleaned_text}}
```

**Runner mode prompt:**

```
Rewrite the following research paper sections into a spoken script for listening during a run.

Audience: Technically literate listener who wants clarity, flow, and the key ideas without citation noise.

Style:
- natural spoken language
- concise but not shallow
- no hype
- no bibliography
- equations summarized conceptually
- mention the most important experimental results
- end with practical takeaways and limitations

Paper text:
{{cleaned_text}}
```

**Deep dive mode prompt:**

```
Rewrite the following research paper into a section-by-section spoken narration.

Preserve more detail than a summary, but still clean for audio listening.

Rules:
- Follow the paper's section structure
- Clean for spoken delivery
- Remove citation markers
- Explain equations conceptually (unless skip_equations is false)
- Include experimental setup and results in detail
- End each section with a brief transition

Paper text:
{{cleaned_text}}
```

Apply the user's configuration flags:
- If `skip_equations`: add "Summarize all equations in plain language" to prompt
- If `skip_tables`: add "Do not read table contents"
- If `skip_references`: add "Remove all citation markers and reference sections"
- If `summarize_figures`: add "Briefly describe only the most important figures"
- If `explain_jargon`: add "When using technical terms, explain them once in simple language"

### Step 4: Chunk Script for TTS (`synthesizing_audio`)
- Split the generated script into chunks of 500–1500 characters
- Break on sentence boundaries
- Retain section markers
- Attach chunk order metadata

### Step 5: Synthesize Audio with ElevenLabs
For each chunk:
- Send text to ElevenLabs Text-to-Speech API
- Use the specified voice (or default)
- Store resulting MP3 audio
- Record duration metadata

**Caching:**
- Hash chunk text + voice settings
- If same hash already synthesized, reuse existing audio
- This avoids regenerating unchanged chunks on retry

### Step 6: Assemble (`assembling_manifest`)
- Concatenate all chunk MP3 files into a single streamable file
- Calculate section start times and durations from chunk durations
- Build the manifest JSON
- Store the concatenated audio file on disk
- Mark job as `completed`

---

## Error Handling

- If any step fails, set job status to `failed` with `error_message`
- Store partial progress so retries can resume from last successful step
- Common failure modes:
  - Zotero API error (paper not found, PDF not accessible)
  - Claude timeout or malformed output
  - ElevenLabs rate limit or synthesis failure
  - Disk space issues

---

## Suggested Data Model

```sql
CREATE TABLE paper_audio_jobs (
    id TEXT PRIMARY KEY,
    zotero_item_key TEXT NOT NULL,
    paper_title TEXT NOT NULL,
    mode TEXT NOT NULL,          -- summary | runner | deep_dive
    status TEXT NOT NULL,        -- queued | extracting_text | ... | completed | failed
    progress REAL,               -- 0.0 to 1.0, nullable
    total_duration_sec REAL,     -- nullable, set on completion
    error_message TEXT,          -- nullable, set on failure
    config_json TEXT,            -- full PaperAudioConfig as JSON
    script_text TEXT,            -- generated listening script
    manifest_json TEXT,          -- playback manifest as JSON
    audio_file_path TEXT,        -- path to concatenated audio file
    created_at TEXT NOT NULL,    -- ISO 8601
    completed_at TEXT            -- ISO 8601, nullable
);
```

---

## Zotero API Integration

The backend needs Zotero API access to fetch paper content. Use the same credentials as configured in the iOS app:
- API Key and User ID stored in the Zotero configuration
- Base URL: `https://api.zotero.org`
- API version: 3

To fetch an item: `GET /users/{userId}/items/{itemKey}?v=3` with `Zotero-API-Key` header.

To fetch attachments: `GET /users/{userId}/items/{itemKey}/children?v=3` — look for items with `itemType: "attachment"` and `contentType: "application/pdf"`.

---

## ElevenLabs TTS Integration

Use the existing ElevenLabs API key (same one used for the conversation agent).

**Text-to-Speech endpoint:** `POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}`

```json
{
  "text": "chunk text here",
  "model_id": "eleven_multilingual_v2",
  "voice_settings": {
    "stability": 0.5,
    "similarity_boost": 0.75
  }
}
```

**Headers:**
```
xi-api-key: <elevenlabs_api_key>
Content-Type: application/json
Accept: audio/mpeg
```

**Response:** Raw MP3 audio data.

**Recommended default voice:** Use `"21m00Tcm4TlvDq8ikWAM"` (Rachel) or let the server admin configure their preferred narration voice.

---

## Priority Summary

| Priority | Method | Path | Notes |
|----------|--------|------|-------|
| **Must have** | `POST` | `/api/paper-audio/generate` | Start generation pipeline |
| **Must have** | `GET` | `/api/paper-audio/jobs` | List all jobs |
| **Must have** | `GET` | `/api/paper-audio/jobs/{id}` | Poll job status |
| **Must have** | `GET` | `/api/paper-audio/{id}/manifest` | Playback manifest |
| **Must have** | `GET` | `/api/paper-audio/{id}/stream` | Audio streaming with Range support |
| Should have | `DELETE` | `/api/paper-audio/jobs/{id}` | Delete job + audio |
| Should have | `POST` | `/api/paper-audio/jobs/{id}/cancel` | Cancel in-progress job |

---

## Minimum Viable Backend

To get the iOS Paper Audio feature working, you need:

1. A job queue (SQLite table + background worker)
2. Zotero API client to fetch paper content
3. Claude API client for script generation (3 prompt variants)
4. ElevenLabs API client for TTS synthesis
5. MP3 concatenation (ffmpeg or similar)
6. A file server with Range header support and Bearer token auth (same pattern as `/api/stream/{audiobook_id}`)
7. Manifest builder

The iOS client polls `/api/paper-audio/jobs` every 5 seconds while jobs are active.
