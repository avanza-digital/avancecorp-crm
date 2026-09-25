// Verificación adicional de la tabla adaptable y el teclado en WebKit, local.
import { defineConfig, devices } from '@playwright/test'
import base from './playwright.config'

export default defineConfig({
  ...base,
  testMatch: ['gestion-diaria-pulso.spec.ts', 'gestion-diaria-cola.spec.ts'],
  projects: [{ name: 'webkit', use: { ...devices['Desktop Safari'] } }],
})
