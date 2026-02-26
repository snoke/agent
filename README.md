# Challenge: Vue + n8n

This repo runs a Vue 3 frontend (Vite) and an n8n instance as the backend.

## Quickstart

1. `docker compose up --build`
2. Open:
   - Frontend: `http://localhost:8080`
   - n8n: `http://localhost:5678`

## Agent Chat (n8n Webhook)

The frontend chat calls an n8n webhook (default: `http://localhost:5678/webhook/agent-chat-confirm`) and expects JSON:

```json
{ "reply": "..." }
```

Important (n8n “test” vs “production” webhooks):
- `/webhook-test/...` works only after you click **Execute workflow** in the n8n editor (usually for a single call).
- For a stable endpoint use `/webhook/agent-chat-confirm` and **activate** the workflow.

Workflow in this repo:
- `Voice-Lead-Agent.confirm.json`: decider + datetime parser + response writer with confirmation step on `/webhook/agent-chat-confirm` + voice input on `/webhook/agent-chat-confirm-voice`

Voice input:
- The frontend has a **Voice** button that records from the microphone and sends audio to `/webhook/agent-chat-confirm-voice`.
- The workflow transcribes via OpenAI speech-to-text and then continues through the normal text agent flow.
- Requires an OpenAI credential in n8n (Credentials → OpenAI) referenced by the workflow nodes.

Agent context:
- Put extra system context in `context.txt`.
- The container mounts it to `AGENT_CONTEXT_FILE` (default: `/opt/agent/context.txt`) and injects it into the decider LLM system prompt.
- Requires `NODE_FUNCTION_ALLOW_BUILTIN=fs` (see `.env.example`) so n8n Function nodes can read the file.

### Workflow requirements

- Create an OpenAI credential in n8n (Credentials → OpenAI) and ensure the workflow nodes reference it.
- Connect Google Calendar credentials in n8n for the Google Calendar nodes.

## Configuration (optional)

Copy `.env.example` to `.env` and adjust values if needed.

Note: `docker-compose.yml` passes `.env` into the n8n container via `env_file`, so changes require recreating the container:
- `docker compose up -d --force-recreate n8n`

Booking policy defaults:
- Timezone: `AGENT_TZ` / `TZ` (default `Europe/Berlin`)
- Workdays: `AGENT_WORKDAYS` (default `1,2,3,4,5` = Mon–Fri)
- Working hours: `AGENT_WORK_START`–`AGENT_WORK_END` (default `09:00`–`17:00`)
- Horizon: `AGENT_HORIZON_DAYS` (default `30`)
- Google Meet link on bookings: `CREATE_GOOGLE_MEET` (default `true`)
- Required fields before booking: `REQUIRE_INPUT` (comma-separated, e.g. `email,name`)
- Optional fields to ask before booking: `OPTIONAL_INPUT` (comma-separated, e.g. `note,name`)

Note: This setup enables `$env` access in n8n via `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` for local development.
