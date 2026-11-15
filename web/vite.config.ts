import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// /v1 and /v2 requests go to the FastAPI service (api/main.py) during dev.
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    proxy: {
      '/v1': 'http://localhost:8000',
      '/v2': 'http://localhost:8000',
      '/healthz': 'http://localhost:8000',
    },
  },
})
