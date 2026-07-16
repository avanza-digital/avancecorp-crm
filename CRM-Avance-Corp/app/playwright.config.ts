// E2E del CRM en MODO DEMO (sin backend): Playwright levanta el dev server con
// la demo habilitada y recorre la app como cada rol. Correr: npm run test:e2e
// (la primera vez: npx playwright install chromium).
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL: 'http://127.0.0.1:5199',
    trace: 'on-first-retry',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  // Server PROPIO en un puerto dedicado, SIN reusar el de desarrollo. El 5173
  // lo comparten el dev server del CRM (a veces con VITE_LEADS_PREVIEW=true,
  // que cambia la vista por defecto de las cuentas reales y tumba los tests de
  // Clientes) y otros proyectos de la máquina. Reusar el server ambiente mordió
  // 3 veces el 2026-07-16: la suite corre SIEMPRE contra un entorno conocido.
  webServer: {
    command: 'npm run dev -- --port 5199 --host 127.0.0.1',
    url: 'http://127.0.0.1:5199',
    reuseExistingServer: false,
    env: { VITE_ENABLE_DEMO: 'true' },
  },
})
