<script setup lang="ts">
const n8nBaseUrl = import.meta.env.VITE_N8N_BASE_URL ?? 'http://localhost:5678'
import AgentChat from './components/AgentChat.vue'
</script>

<template>
  <main class="layout">
    <AgentChat />
  </main>
</template>

<style scoped>
.layout {
  display: grid;
  gap: 16px;
}

</style>
