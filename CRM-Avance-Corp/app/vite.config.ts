import path from 'node:path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// Deploy estático a Hostinger → base relativa './' (mismo patrón que el portal).
export default defineConfig({
  base: './',
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  build: {
    // Vite 8 usa Rolldown. Separar dependencias estables reduce el JS propio
    // que cambia en cada deploy y permite cachearlas de forma independiente.
    rolldownOptions: {
      output: {
        manualChunks(id) {
          const modulo = id.replaceAll('\\', '/')
          if (
            modulo.includes('/node_modules/react/')
            || modulo.includes('/node_modules/react-dom/')
            || modulo.includes('/node_modules/scheduler/')
          ) return 'react-vendor'
          if (
            modulo.includes('/node_modules/@supabase/')
            || modulo.includes('/node_modules/@tanstack/')
          ) return 'data-vendor'
          if (
            modulo.includes('/node_modules/lucide-react/')
            || modulo.includes('/node_modules/sonner/')
          ) return 'ui-vendor'
          return undefined
        },
      },
    },
  },
})
