import path from 'node:path'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

// El negocio opera en Perú (UTC-5, sin horario de verano) y hay lógica de fechas
// que SOLO falla en offsets negativos: leer '2026-07-15' como UTC muestra el día
// anterior en Lima. Sin fijar la zona, esos tests pasan en verde en una máquina
// en UTC aunque el bug vuelva (comprobado reintroduciéndolo). Se fija aquí, en el
// proceso padre, porque los workers heredan el entorno; `test.env` NO sirve (no
// llega a process.env a tiempo).
process.env.TZ = 'America/Lima'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.{ts,tsx}'],
    setupFiles: ['./src/test/setup.ts'],
    // La zona horaria se fija en setupFiles (no aquí con `env`: no llega a
    // process.env a tiempo — comprobado con el bug reintroducido a propósito).
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
