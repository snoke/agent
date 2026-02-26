export type AgentReply = {
  reply: string
  state?: unknown
  booking_intent?: boolean
  transcript?: string
  raw?: unknown
}

export async function sendAgentMessage(options: {
  webhookUrl: string
  message: string
  sessionId: string
  context?: Record<string, unknown>
  state?: unknown
}): Promise<AgentReply> {
  const response = await fetch(options.webhookUrl, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      message: options.message,
      sessionId: options.sessionId,
      context: options.context ?? {},
      state: options.state ?? null,
    }),
  })

  const contentType = response.headers.get('content-type') ?? ''
  const payload = contentType.includes('application/json') ? await response.json() : await response.text()

  if (!response.ok) {
    const detail = typeof payload === 'string' ? payload : JSON.stringify(payload)
    throw new Error(`Webhook failed (${response.status}): ${detail}`)
  }

  if (typeof payload === 'string') {
    return { reply: payload, raw: payload }
  }

  if (payload && typeof payload === 'object' && 'reply' in payload && typeof (payload as any).reply === 'string') {
    return payload as AgentReply
  }

  return { reply: JSON.stringify(payload), raw: payload }
}

export async function sendAgentVoiceMessage(options: {
  webhookUrl: string
  audioBase64: string
  mimeType: string
  fileName: string
  sessionId: string
  context?: Record<string, unknown>
  state?: unknown
}): Promise<AgentReply> {
  const response = await fetch(options.webhookUrl, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      audio_base64: options.audioBase64,
      mimeType: options.mimeType,
      fileName: options.fileName,
      sessionId: options.sessionId,
      context: options.context ?? {},
      state: options.state ?? null,
    }),
  })

  const contentType = response.headers.get('content-type') ?? ''
  const payload = contentType.includes('application/json') ? await response.json() : await response.text()

  if (!response.ok) {
    const detail = typeof payload === 'string' ? payload : JSON.stringify(payload)
    throw new Error(`Webhook failed (${response.status}): ${detail}`)
  }

  if (typeof payload === 'string') {
    return { reply: payload, raw: payload }
  }

  if (payload && typeof payload === 'object' && 'reply' in payload && typeof (payload as any).reply === 'string') {
    return payload as AgentReply
  }

  return { reply: JSON.stringify(payload), raw: payload }
}
