import { defineConfig, devices } from '@playwright/test'
import { readFileSync } from 'node:fs'
import assert from 'node:assert/strict'

// Ensayo autorizado. Nunca hereda el proyecto de .env.local ni utiliza mocks.
const datos = JSON.parse(readFileSync('/f3-privado/e2e.json', 'utf8'))
assert.equal(datos.ref, 'bxkborlvpmuwttzjrjqn')
assert.equal(datos.url, 'https://bxkborlvpmuwttzjrjqn.supabase.co')

export default defineConfig({
  testDir: './e2e-integration', testMatch: 'formulario3-real.spec.ts',
  workers: 2, retries: 0, timeout: 90_000, reporter: 'list',
  expect: { timeout: 30_000 },
  outputDir: './test-results/formulario3-real',
  use: { baseURL: 'http://127.0.0.1:5298', trace: 'off', screenshot: 'off' },
  projects: [{ name: 'formulario3-auth-real', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'npm run dev -- --port 5298 --host 127.0.0.1',
    url: 'http://127.0.0.1:5298', reuseExistingServer: false,
    env: { VITE_ENABLE_DEMO: 'false', VITE_LEADS_PREVIEW: 'false', VITE_SUPABASE_URL: datos.url, VITE_SUPABASE_ANON_KEY: datos.anon },
  },
})
