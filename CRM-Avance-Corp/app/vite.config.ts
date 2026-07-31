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
    // Inventario de dependencias y avisos legales usados por el bundle.
    // Vite lo publica en dist/.vite/license.md junto al artefacto estático.
    license: true,
    // Vite 8 usa Rolldown. Separar dependencias estables reduce el JS propio
    // que cambia en cada deploy y permite cachearlas de forma independiente.
    //
    // POR QUÉ codeSplitting y no manualChunks: cuando un grupo captura un
    // módulo, Rolldown arrastra RECURSIVAMENTE sus dependencias al grupo
    // ignorando lo que manualChunks devuelva para ellas. Con recharts eso
    // aspiraba clsx y use-sync-external-store (compartidos con la UI base y
    // @xstate/react) dentro de charts-vendor, y el ENTRY pasaba a importar el
    // chunk de charts en el arranque (verificado por inspección del dist). En
    // codeSplitting la prioridad manda: ui-vendor (mayor) captura primero los
    // módulos compartidos y la recursión de charts-vendor ya los ve asignados.
    rolldownOptions: {
      output: {
        // La minificación conserva dentro del JS los avisos propietarios que
        // la licencia de GSAP exige no retirar.
        comments: { legal: true },
        codeSplitting: {
          groups: [
            {
              name: 'react-vendor',
              test: /[\\/]node_modules[\\/](react|react-dom|scheduler)[\\/]/,
              priority: 40,
            },
            {
              name: 'data-vendor',
              test: /[\\/]node_modules[\\/](@supabase|@tanstack)[\\/]/,
              priority: 30,
            },
            {
              // lucide/sonner + los COMPARTIDOS del arranque (clsx la usa la UI
              // base y use-sync-external-store lo usa @xstate/react): anclados
              // aquí para que charts-vendor no se los lleve por recursión.
              name: 'ui-vendor',
              test: /[\\/]node_modules[\\/](lucide-react|sonner|clsx|use-sync-external-store)[\\/]/,
              priority: 20,
            },
            {
              // recharts y sus dependencias exclusivas (gráficas de gerencia):
              // pesadas y estables → chunk propio cacheable que solo baja con
              // la vista Hoy, sin engordar el entry ni el chunk de la vista.
              name: 'charts-vendor',
              test: /[\\/]node_modules[\\/](recharts|victory-vendor|d3-[^\\/]+|internmap|@reduxjs|react-redux|reselect|immer|es-toolkit|eventemitter3|decimal\.js-light|tiny-invariant)[\\/]/,
              priority: 10,
            },
          ],
        },
      },
    },
  },
})
