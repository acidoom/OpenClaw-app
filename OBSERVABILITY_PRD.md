# OpenClaw Voice Observability — PRD

Status: Draft
Owner: Platform
Target branch: `claude/plan-observability-28JIM`
Scope: iOS app (`OpenClaw`, `OpenClawWidgets`) + `Gateway/` TS plugin + optional self-hosted inference on DGX Spark.

---

## 1. Problem

OpenClaw is a voice-first iOS app built on the ElevenLabs Conversational AI SDK (LiveKit/WebRTC under the hood), with a TypeScript Gateway plugin for APNs and iOS hooks. Today, signals are limited to unstructured `print("[OpenClaw] ...")` statements and `console.log` in the Gateway. There is no session/turn model, no latency breakdown, no error aggregation, no correlation between client, Gateway, and model backends.

When a user says "it felt slow" or "it interrupted me," we cannot tell whether the regression was capture, VAD, ASR, LLM TTFT, TTS first audio, playout, or the network in between. We need a production-grade observability story focused on **turn waterfalls**, not just component health, because vLLM/ASR/TTS can each look green while the user experience is bad.

## 2. Goals & non‑goals

**Goals**
- Model every interaction as `session → turn → stage`, with correlation IDs traversing iOS → Gateway → model backends.
- Emit OpenTelemetry traces + Prometheus metrics + structured logs for the full voice pipeline.
- Ship six Grafana dashboards (executive, realtime ops, latency waterfall, audio/network quality, ASR/TTS quality, per-session drilldown).
- Alert on UX symptoms, not component noise.
- Integrate crash reporting and centralized error capture for the iOS client.
- Retention + sampling policy with PII redaction before long-term storage.

**Non‑goals**
- Replacing ElevenLabs-hosted ASR/LLM/TTS with self-hosted for observability reasons alone.
- Building a new transcript store (reuse ElevenLabs + optional ClickHouse warehouse).
- Instrumenting every non-voice service (Zotero, Libro, Podcasts) beyond error capture in this phase.

## 3. Success metrics (SLOs)

Canonical per-turn targets:

| Stage | Target (p95) |
|---|---|
| ASR partial | < 300 ms |
| LLM TTFT | < 500 ms |
| TTS first audio | < 400 ms |
| Full conversational turn (capture → playout) | < 2.0 s |
| Session error rate | < 3% |
| Packet loss sustained | < 5% |

Derived KPIs (composite scores, 0–1):
- `conversational_smoothness` — low dead air + low interrupt mismatch + low clarification rate + low ASR rewrite + stable playout.
- `turn_friction` — restatements + ASR commit lag + high TTFT + slow TTS first audio.
- `understanding_stability` — ASR partial→final drift + tool correction rate + "no, that's not what I said" patterns.

## 4. Event taxonomy

Every event carries: `session_id`, `turn_id`, `trace_id`, `span_id`, `device_id` (hashed), `app_version`, `agent_id`, `model_name`, `voice_id`, `network_type`.

Lifecycle events:

| Event | Emitter | Notes |
|---|---|---|
| `session.started` | iOS `ConversationManager` | at `.connecting → .active` |
| `session.ended` | iOS `ConversationManager` | reason, duration, turn count |
| `turn.started` | iOS (VAD open) | user speech begin |
| `turn.ended` | iOS (playout complete) | closes the waterfall |
| `vad.started` / `vad.ended` | iOS | from SDK mic energy/VAD |
| `asr.partial` | iOS | partial count, language, confidence |
| `asr.commit` | iOS | final transcript, commit lag |
| `llm.first_token` | Gateway (if proxied) or iOS | TTFT |
| `llm.completed` | Gateway or iOS | total tokens, duration |
| `tts.started` | iOS | chars, chunk count |
| `tts.first_audio` | iOS | first audio byte latency |
| `tts.completed` | iOS | synthesis duration |
| `playout.started` / `playout.completed` | iOS `AudioPlayerManager` / SDK | underruns, silence |
| `barge_in.detected` | iOS | user interrupt vs. agent speaking |
| `tool.started` / `tool.completed` | Gateway + iOS | tool name, duration, result |
| `handoff.triggered` | Gateway/agent | reason, target |
| `error` | all tiers | component, code, message, stack |

## 5. Metric catalog (Prometheus names)

Histograms (buckets in ms; `le` per OTEL conventions):
- `voice_turn_e2e_ms{agent_id,model,voice}`
- `voice_asr_partial_ms`, `voice_asr_commit_ms`, `voice_asr_commit_lag_ms`
- `voice_llm_ttft_ms{model}`, `voice_llm_total_ms{model}`
- `voice_tts_first_audio_ms{voice,model}`, `voice_tts_synth_ms`
- `voice_playout_first_frame_ms`, `voice_playout_underrun_ms`
- `voice_capture_ms`, `voice_vad_detect_ms`

Counters:
- `voice_session_total{outcome}`, `voice_turn_total{outcome}`
- `voice_error_total{component,code}`
- `voice_barge_in_total{kind}` (user_interrupt | false_positive)
- `voice_clarification_turns_total`
- `voice_dead_air_ms_bucket`
- `voice_tool_invocations_total{tool,outcome}`
- `voice_handoff_total{reason}`

Gauges:
- `voice_sessions_active`, `voice_turns_active`
- `voice_asr_sessions_active`, `voice_tts_sessions_active`
- `voice_webrtc_jitter_ms`, `voice_webrtc_loss_pct`, `voice_webrtc_rtt_ms`

If DGX Spark hosts vLLM:
- scrape vLLM's native `/metrics` endpoint — do not reinvent
- join via `{model_name, instance, request_id}` where `request_id = turn_id`

## 6. Trace (OTEL) span taxonomy

Root span per turn: `voice.turn`
Child spans (in causal order):
```
voice.turn
├── audio.capture
├── vad.detect
├── asr.stream
│   ├── asr.partial (event link)
│   └── asr.commit
├── orchestration.route
├── llm.generate
│   ├── llm.first_token (event)
│   └── llm.completed (event)
├── tool.invoke (0..N, parallel allowed)
├── tts.synthesize
│   ├── tts.first_audio (event)
│   └── tts.completed (event)
└── playout.render
```
Session span `voice.session` is the parent of all turn spans in the same conversation. `trace_id` is seeded on the iOS client at `startConversation` and propagated via W3C traceparent to the Gateway and any proxied LLM/tool calls.

## 7. Dashboards (Grafana pack)

1. **Executive voice health** — success rate, abandonment, p50/p95 e2e latency, handoff rate, cost per completed session.
2. **Realtime operations** — active sessions/turns, ASR/TTS sessions, vLLM running requests, GPU/UMA pressure, error rate by component.
3. **Latency waterfall** (most useful) — p50/p95/p99 per stage: capture → VAD → ASR → orchestration → LLM TTFT → LLM total → TTS first audio → playout.
4. **Audio/network quality** — jitter, loss, RTT, playout underruns, barge-ins, silence gaps, interruption timing.
5. **ASR/TTS quality** — ASR confidence by language, partial→final rewrite ratio, commit lag, TTS first audio by voice/model, long-text chunk perf.
6. **Per-session drilldown** — transcript + turn timeline + trace waterfall + logs + audio clip + tool calls + model timings (mirrors LiveKit session insights).

Dashboards live as JSON in `observability/grafana/` and are provisioned via the Grafana folder `openclaw-voice`.

## 8. Alerting strategy

**Critical** (page):
- `voice_turn_e2e_ms{quantile="0.95"} > 2500` for 10 min
- `voice_llm_ttft_ms{quantile="0.95"} > 800`
- `voice_tts_first_audio_ms{quantile="0.95"} > 700`
- session error rate > 3%
- abandonment rate > threshold
- packet loss sustained > 5%
- ASR commit lag > threshold

**Early warning** (ticket):
- rising `voice_clarification_turns_total`
- rising `voice_barge_in_total`
- rising dead-air buckets
- rising vLLM queue depth
- GPU memory pressure + preemption together

Alert routes: PagerDuty (critical), Slack `#openclaw-voice-alerts` (warning).

## 9. Logs vs traces vs metrics

- **Logs**: exceptions, policy decisions, prompt/template version, tool selection, routing choices, SDK errors, reconnects.
- **Traces**: stage timing, causality, waterfall debugging, per-turn root cause.
- **Metrics**: SLOs, alerts, capacity, regression detection.

Rule of thumb: page → metric; explain a bad turn → trace; raw context → log.

## 10. Retention & sampling

| Signal | Retention |
|---|---|
| Metrics | 30–90 days |
| Traces | 7–14 days hot, sampled after |
| Logs | 14–30 days |
| Transcripts | per product policy |
| Raw audio | shortest viable; QA-approved only |

Tail-based sampling:
- 100% traces for errors
- 100% traces for sessions with any stage above SLO
- 100% traces for handoffs/escalations
- 10–20% of healthy sessions
- 1–5% raw audio retention, QA-approved
- PII redaction pass (regex + ML NER) before long-term storage; EU sessions get stricter access controls.

## 11. Stack

- **LiveKit** — realtime/session spine (already in ElevenLabs SDK) + agent trace/metric hooks where available.
- **OTEL Collector** — single ingestion hub for traces + metrics + logs.
- **Tempo** (traces), **Prometheus** (metrics), **Loki** (logs), **Grafana** (dashboards).
- **Kafka** (optional) — normalized event fan-out.
- **ClickHouse** — session analytics warehouse (per-turn rows joined with transcripts).
- **Sentry** — iOS + TS crash/error aggregation (cheapest first-line win).

## 12. Implementation plan

### Phase 0 — Foundations (week 1)

Ship the correlation + transport plumbing before any dashboards.

1. Add an `Observability` module to the iOS target:
   - `observability/Telemetry.swift` — facade over OTEL Swift SDK + `os.Logger` + Sentry.
   - `observability/IDs.swift` — `SessionID`, `TurnID`, `TraceID` generation and propagation.
   - `observability/Events.swift` — typed event structs matching §4.
   - Feature flag `OBSERVABILITY_ENABLED` (default on debug, configurable in `SettingsViewModel`).
2. Add Sentry (iOS) + Sentry (Node) with DSNs from Keychain / env. Hook `AppDelegate` crash capture.
3. In `Gateway/`, add `@opentelemetry/sdk-node` + Pino logger; replace `console.log` with structured logger that forwards to OTEL collector; propagate `traceparent` header in `apns-notifier.ts` and `ios-hooks.ts`.
4. Stand up OTEL Collector + Tempo + Prometheus + Loki + Grafana via `observability/docker-compose.yml` for dev; provision IaC (Terraform module) for staging/prod.

### Phase 1 — Minimum-viable voice telemetry (week 2)

Target "best first version" from the brief: get 80% of value fast.

Per turn, emit from iOS `ConversationManager.swift`:
- start `voice.session` span at `state = .connecting` (line 59).
- start `voice.turn` span when `conversation.$agentState` transitions `listening → user-speaking`, close when `playout.completed` fires.
- record `asr.commit`, `llm.first_token` (via SDK callback), `tts.first_audio` (first audio frame), `playout.completed` (AVAudioEngine tap).
- emit `voice_turn_e2e_ms`, `voice_asr_commit_ms`, `voice_llm_ttft_ms`, `voice_tts_first_audio_ms`, `voice_webrtc_{jitter,loss,rtt}_ms`.
- emit `error` events for every `catch` in `ConversationManager.swift` (lines 68, 82–85, 107, 122–125, 153) via `Telemetry.captureError`.

Per session: transcript, timeline, audio playback reference, model versions, trace/log correlation — stored to ClickHouse via Gateway ingest endpoint.

### Phase 2 — Full pipeline instrumentation (weeks 3–4)

1. **iOS SDK event bridge**: subscribe to every ElevenLabs SDK publisher (`conversation.$state`, `$messages`, `$agentState`, `$isMuted`) in `setupConversationBindings` (line 187) and translate to §4 events. For VAD/ASR/TTS partials, use the SDK's WebSocket-mirrored event model (client/server events already include audio, transcription, agent-response frames).
2. **Gateway voice routes** (new): if any LLM/tool/handoff call is proxied, wrap it in `voice.llm.generate` / `voice.tool.invoke` spans in `Gateway/index.ts` and `Gateway/ios-hooks.ts`.
3. **vLLM (DGX Spark)**: scrape `/metrics` (`vllm_request_*`, `vllm_gpu_*`) via Prometheus; inject `request_id = turn_id` at the gateway so joins work.
4. **WebRTC stats**: every 2 s snapshot from LiveKit `Room` → `voice_webrtc_*` gauges + event log.
5. **Audio quality**: `AudioPlayerManager.swift` taps the AVAudioEngine output for underrun detection → `voice_playout_underrun_ms`.
6. **Barge-in**: correlate VAD-open events while `agentState == .speaking` → `voice_barge_in_total{kind="user_interrupt"}`; if agent recovers < 200 ms, reclassify as `false_positive`.

### Phase 3 — Dashboards + alerts (week 5)

Provision the six Grafana dashboards and alert rules from §7–§8 as JSON + YAML in `observability/`.

### Phase 4 — Derived KPIs + tail sampling (week 6)

1. Implement the three composite KPIs (§3) as Grafana recording rules.
2. Turn on tail-based sampling in the OTEL Collector (`tail_sampling` processor) with the policy in §10.
3. PII redaction processor (`attributes/redact`) before Tempo/Loki/ClickHouse export.

### Phase 5 — Rollout (week 7)

1. Enable on 10% of sessions via remote config (Keychain-backed flag, surfaced in `SettingsView`).
2. Validate dashboards against a baked set of 20 recorded bad-turn scenarios.
3. 100% rollout; announce in-app under Settings → Diagnostics.

## 13. Code touchpoints (iOS)

| File | Instrumentation |
|---|---|
| `OpenClaw/Services/ConversationManager.swift` | session + turn spans; all `catch` → `Telemetry.captureError`; SDK publisher bridge |
| `OpenClaw/Services/TokenService.swift` | `voice.auth.token` span; replace prints at 55–60 |
| `OpenClaw/Services/AudioPlayerManager.swift` | playout underrun metric; playout span close |
| `OpenClaw/Services/AudioSessionManager.swift` | AVAudioSession route change logs |
| `OpenClaw/Services/NetworkMonitor.swift` | network type attribute on all spans |
| `OpenClaw/Services/TodoService.swift`, `GatewayChatService.swift`, `LibroAIService.swift`, `PodcastService.swift`, `PaperAudioService.swift`, `ZoteroService.swift` | structured logger + `tool.invoke` spans |
| `OpenClaw/Services/HighlightManager.swift`, `PodcastHighlightManager.swift` | `tool.invoke` spans for AI highlights |
| `OpenClaw/App/AppDelegate.swift` | Sentry init, APNs delivery counters |
| `OpenClaw/Features/Conversation/ConversationViewModel.swift` | user-intent events (tap-to-talk, mute, interrupt) |
| `OpenClaw/Models/ConversationTypes.swift` | `AgentMode` transitions → span events |

## 14. Code touchpoints (Gateway TS)

| File | Instrumentation |
|---|---|
| `Gateway/index.ts` | OTEL SDK init, Pino logger, plugin lifecycle spans |
| `Gateway/apns-notifier.ts` | `apns.send` span with JWT/HTTP2 attributes; error capture |
| `Gateway/ios-hooks.ts` | accept + propagate `traceparent`; `ios.hook.{name}` spans |

## 15. Open questions

1. Does DGX Spark host vLLM in production, or is ElevenLabs fully hosted? (determines whether Phase 2.3 is in scope)
2. Retention policy for transcripts and audio — legal/EU review needed before storing beyond 24 h.
3. Sentry vs. rolling our own iOS crash capture (Sentry recommended for speed).
4. Do we proxy LLM calls through the Gateway, or does the ElevenLabs agent call them directly? (affects TTFT instrumentation point).
5. Cost model for ClickHouse session warehouse — buy (Grafana Cloud/Logz) vs. run (DGX Spark host).

## 16. Deliverables checklist

- [ ] `observability/` directory with docker-compose, Grafana dashboards, alert rules, OTEL collector config, Terraform module.
- [ ] iOS `Observability` module + SDK event bridge + Sentry.
- [ ] Gateway OTEL + Pino wiring.
- [ ] vLLM Prometheus scrape config (if applicable).
- [ ] Six Grafana dashboards committed as JSON.
- [ ] Alert rules in Prometheus + PagerDuty/Slack routing.
- [ ] Retention/sampling/PII redaction processors.
- [ ] Runbook: "How to debug a bad turn" using per-session drilldown.
- [ ] Rollout plan with remote-config flag and diagnostics screen.
