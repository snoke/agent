<script setup lang="ts">
import { computed, ref } from 'vue'
import { sendAgentMessage, sendAgentVoiceMessage } from '../api/agent'

type ChatMessage = {
  id: string
  role: 'user' | 'agent' | 'system'
  text: string
}

function randomId() {
  return Math.random().toString(16).slice(2) + Date.now().toString(16)
}

const defaultWebhookUrl =
  import.meta.env.VITE_AGENT_WEBHOOK_URL ?? 'http://localhost:5678/webhook/agent-chat'

function deriveVoiceWebhookUrl(textWebhookUrl: string) {
  const trimmed = textWebhookUrl.trim()
  if (!trimmed) return ''
  if (trimmed.endsWith('/agent-chat-confirm')) return trimmed + '-voice'
  if (trimmed.includes('/webhook/')) return trimmed + '-voice'
  return trimmed
}

const defaultVoiceWebhookUrl =
  import.meta.env.VITE_AGENT_VOICE_WEBHOOK_URL ?? deriveVoiceWebhookUrl(defaultWebhookUrl)

const sessionId = ref(`session_${randomId()}`)
const webhookUrl = ref(defaultWebhookUrl)
const voiceWebhookUrl = ref(defaultVoiceWebhookUrl)
const input = ref('')
const isSending = ref(false)
const isRecording = ref(false)
const error = ref<string | null>(null)
const agentState = ref<unknown>(null)
const messages = ref<ChatMessage[]>([
  {
    id: randomId(),
    role: 'agent',
    text: 'Hi, ich bin Agent! KI-Assistent von Stefan. Ich kann dir dabei helfen, ein kurzes Meeting zu arrangieren.',
  },
])

const canSend = computed(() => !isSending.value && input.value.trim().length > 0 && webhookUrl.value.trim().length > 0)
const canRecord = computed(() => !isSending.value && !isRecording.value && voiceWebhookUrl.value.trim().length > 0)

let recorder: MediaRecorder | null = null
let recorderStream: MediaStream | null = null
let recorderChunks: BlobPart[] = []

function stopStream() {
  try {
    recorderStream?.getTracks().forEach((t) => t.stop())
  } catch {
    // ignore
  } finally {
    recorderStream = null
  }
}

async function blobToBase64(blob: Blob) {
  const dataUrl = await new Promise<string>((resolve, reject) => {
    const r = new FileReader()
    r.onerror = () => reject(r.error ?? new Error('Failed to read audio'))
    r.onload = () => resolve(String(r.result ?? ''))
    r.readAsDataURL(blob)
  })
  const idx = dataUrl.indexOf(',')
  return idx >= 0 ? dataUrl.slice(idx + 1) : dataUrl
}

async function send() {
  if (!canSend.value) return
  error.value = null

  const text = input.value.trim()
  input.value = ''

  messages.value.push({ id: randomId(), role: 'user', text })

  isSending.value = true
  try {
    const { reply, state } = await sendAgentMessage({
      webhookUrl: webhookUrl.value.trim(),
      message: text,
      sessionId: sessionId.value,
      state: agentState.value,
    })
    agentState.value = state ?? agentState.value
    messages.value.push({ id: randomId(), role: 'agent', text: reply })
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e)
    error.value = message
    messages.value.push({
      id: randomId(),
      role: 'system',
      text: `Error: ${message}`,
    })
  } finally {
    isSending.value = false
  }
}

async function startVoice() {
  if (!canRecord.value) return
  error.value = null

  try {
    recorderStream = await navigator.mediaDevices.getUserMedia({ audio: true })
    recorderChunks = []

    const mimeTypeCandidates = ['audio/webm;codecs=opus', 'audio/webm', 'audio/ogg;codecs=opus', 'audio/ogg']
    const mimeType = mimeTypeCandidates.find((t) => MediaRecorder.isTypeSupported(t)) ?? ''

    recorder = new MediaRecorder(recorderStream, mimeType ? { mimeType } : undefined)
    recorder.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) recorderChunks.push(e.data)
    }
    recorder.onerror = () => {
      error.value = 'Recording failed.'
      isRecording.value = false
      stopStream()
    }
    recorder.onstop = async () => {
      isRecording.value = false
      stopStream()

      const blob = new Blob(recorderChunks, { type: recorder?.mimeType || 'audio/webm' })
      recorderChunks = []
      recorder = null

      isSending.value = true
      try {
        const audioBase64 = await blobToBase64(blob)
        const mimeTypeFinal = blob.type || 'audio/webm'
        const fileName = mimeTypeFinal.includes('ogg') ? 'voice.ogg' : 'voice.webm'

        const { reply, state, transcript } = await sendAgentVoiceMessage({
          webhookUrl: voiceWebhookUrl.value.trim(),
          audioBase64,
          mimeType: mimeTypeFinal,
          fileName,
          sessionId: sessionId.value,
          state: agentState.value,
        })

        if (typeof transcript === 'string' && transcript.trim()) {
          messages.value.push({ id: randomId(), role: 'user', text: transcript })
        } else {
          messages.value.push({ id: randomId(), role: 'user', text: '(voice message)' })
        }

        agentState.value = state ?? agentState.value
        messages.value.push({ id: randomId(), role: 'agent', text: reply })
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e)
        error.value = message
        messages.value.push({ id: randomId(), role: 'system', text: `Error: ${message}` })
      } finally {
        isSending.value = false
      }
    }

    isRecording.value = true
    recorder.start()
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e)
    error.value = `Microphone error: ${message}`
    isRecording.value = false
    stopStream()
  }
}

function stopVoice() {
  if (!isRecording.value) return
  try {
    recorder?.stop()
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e)
    error.value = `Stop recording failed: ${message}`
    isRecording.value = false
    stopStream()
  }
}
</script>

<template>
  <section class="wrap">

    <div class="chat" aria-live="polite">
      <div v-for="m in messages" :key="m.id" class="msg" :class="`role-${m.role}`">
        <div class="bubble">
          <div class="role">{{ m.role }}</div>
          <div class="text">{{ m.text }}</div>
        </div>
      </div>
    </div>

    <footer class="composer">
      <form class="row" @submit.prevent="send">
        <input v-model="input" placeholder="Schreib was…" :disabled="isSending" />
        <button type="submit" :disabled="!canSend">{{ isSending ? '…' : 'Senden' }}</button>
        <button v-if="!isRecording" type="button" class="voice" :disabled="!canRecord" @click="startVoice">
          Voice
        </button>
        <button v-else type="button" class="voice-stop" @click="stopVoice">Stop</button>
      </form>
      <p v-if="error" class="error">{{ error }}</p>
      <details class="state">
        <summary>State</summary>
        <pre>{{ JSON.stringify(agentState, null, 2) }}</pre>
      </details>
    </footer>
  </section>
</template>

<style scoped>
.wrap {
  display: grid;
  grid-template-rows: auto 1fr auto;
  gap: 12px;
  min-height: 70vh;
}

.header {
  display: flex;
  gap: 16px;
  align-items: flex-start;
  justify-content: space-between;
  flex-wrap: wrap;
}

.meta {
  display: grid;
  grid-template-columns: 1fr 1fr 220px;
  gap: 8px;
  width: min(720px, 100%);
}

.field span {
  display: block;
  font-size: 12px;
  opacity: 0.75;
  margin-bottom: 4px;
}

input {
  width: 100%;
  padding: 10px 12px;
  border-radius: 10px;
  border: 1px solid color-mix(in srgb, currentColor 18%, transparent);
  background: color-mix(in srgb, canvas 96%, transparent);
  color: inherit;
  outline: none;
}

.chat {
  border: 1px solid color-mix(in srgb, currentColor 18%, transparent);
  border-radius: 12px;
  padding: 12px;
  overflow: auto;
  background: color-mix(in srgb, canvas 96%, transparent);
}

.msg {
  display: flex;
  margin: 10px 0;
}

.msg.role-user {
  justify-content: flex-end;
}

.bubble {
  max-width: min(680px, 95%);
  padding: 10px 12px;
  border-radius: 12px;
  border: 1px solid color-mix(in srgb, currentColor 14%, transparent);
}

.msg.role-user .bubble {
  background: color-mix(in srgb, #4f46e5 22%, transparent);
}

.msg.role-agent .bubble {
  background: color-mix(in srgb, #16a34a 18%, transparent);
}

.msg.role-system .bubble {
  background: color-mix(in srgb, currentColor 6%, transparent);
  opacity: 0.9;
}

.role {
  font-size: 11px;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  opacity: 0.7;
  margin-bottom: 6px;
}

.text {
  white-space: pre-wrap;
  word-break: break-word;
}

.composer .row {
  display: grid;
  grid-template-columns: 1fr auto auto;
  gap: 8px;
}

button {
  padding: 10px 14px;
  border-radius: 10px;
  border: 1px solid color-mix(in srgb, currentColor 18%, transparent);
  background: color-mix(in srgb, currentColor 10%, transparent);
  color: inherit;
  cursor: pointer;
}

button:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.voice {
  background: color-mix(in srgb, #0ea5e9 18%, transparent);
}

.voice-stop {
  background: color-mix(in srgb, #ef4444 18%, transparent);
}

.error {
  margin: 8px 0 0;
  color: #ef4444;
}

.state {
  margin-top: 10px;
  opacity: 0.85;
}

pre {
  margin: 8px 0 0;
  padding: 10px 12px;
  border-radius: 10px;
  border: 1px solid color-mix(in srgb, currentColor 14%, transparent);
  overflow: auto;
}
</style>
