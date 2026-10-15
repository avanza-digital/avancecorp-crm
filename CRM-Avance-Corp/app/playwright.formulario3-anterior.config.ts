import { defineConfig, devices } from '@playwright/test'

// Sirve los bytes del ZIP publicado anterior, montado en solo lectura.
export default defineConfig({
  testDir: './e2e-integration', testMatch: 'formulario3-anterior.spec.ts',
  workers: 1, retries: 0, timeout: 120_000, reporter: 'list',
  expect: { timeout: 30_000 }, outputDir: './test-results/formulario3-anterior',
  use: { baseURL: 'http://127.0.0.1:5298', trace: 'off', screenshot: 'off', serviceWorkers: 'block' },
  projects: [{ name: 'frontend-vivo-base-nueva', use: { ...devices['Desktop Chrome'] } }],
  webServer: { command: 'npx vite preview --host 127.0.0.1 --port 5298 --outDir /f4-anterior', url: 'http://127.0.0.1:5298', reuseExistingServer: false },
})
