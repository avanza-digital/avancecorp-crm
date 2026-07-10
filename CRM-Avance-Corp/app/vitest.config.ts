import path from 'node:path'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.{ts,tsx}'],
    setupFiles: ['./src/test/setup.ts'],
    clearMocks: true,
    restoreMocks: true,
    coverage: {
      provider: 'v8',
      reporter: ['text-summary', 'html', 'lcov'],
      reportsDirectory: './coverage',
      // TODO src: medir solo 4 utilidades daba un "100%" engañoso (auditoría
      // 2026-07-10: la cobertura real era ~17% con auth y pantallas al 0%).
      // En Vitest 4 `coverage.all` ya no existe: `include` amplio lo reemplaza.
      include: ['src/**/*.{ts,tsx}'],
      exclude: [
        'src/**/*.test.{ts,tsx}',
        'src/test/**',
        'src/lib/database.types.ts', // solo tipos: sin runtime que medir
      ],
      // Umbrales HONESTOS sobre todo src (no sobre un subconjunto cómodo).
      // Piso real verificado el 2026-07-10 (líneas 31.8% · ramas 27.5% ·
      // funciones 24.6% · statements 30.8%) — el gate protege contra
      // REGRESIÓN. Subirlos con cada suite nueva es bienvenido; bajarlos, no.
      thresholds: {
        branches: 26,
        functions: 23,
        lines: 30,
        statements: 29,
      },
    },
  },
})
