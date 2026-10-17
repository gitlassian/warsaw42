import react from '@vitejs/plugin-react'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  // Hostnames besides localhost that may reach the dev and preview servers (e.g. a tunnel).
  server: { allowedHosts: ['test.t.froti.dev'] },
  preview: { allowedHosts: ['test.t.froti.dev'] },
})
