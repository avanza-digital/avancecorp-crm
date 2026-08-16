import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach } from 'vitest'

// Los contadores (AnimatedValue) y las intros GSAP respetan
// prefers-reduced-motion, pero jsdom NO trae matchMedia: los componentes
// animaban de verdad y, con los workers en paralelo, un assert podía pillar un
// fotograma de tránsito («US$ -42k» camino de «US$ 30k» — pasó una vez entre
// miles). Las unitarias corren en un mundo con la preferencia activa, igual
// que la suite e2e (emulateMedia en _helpers). `writable`: los cuatro tests
// que stubean matchMedia por su cuenta lo siguen pudiendo pisar.
// (guardado: los tests MSW corren en @vitest-environment node, sin window)
if (typeof window !== 'undefined') {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    configurable: true,
    value: (query: string) => ({
      matches: query.includes('prefers-reduced-motion'),
      media: query,
      onchange: null,
      addEventListener: () => {},
      removeEventListener: () => {},
      addListener: () => {},
      removeListener: () => {},
      dispatchEvent: () => false,
    }),
  })
}

afterEach(() => {
  cleanup()
})
