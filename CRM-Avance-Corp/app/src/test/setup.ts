import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach } from 'vitest'

// Los contadores (AnimatedValue) y las intros GSAP respetan
// prefers-reduced-motion, pero jsdom NO trae matchMedia: los componentes
// animaban de verdad y, con los workers en paralelo, un assert podía pillar un
// fotograma de tránsito. Las unitarias generales corren en un mundo con la
// preferencia activa, igual que la suite e2e (emulateMedia en _helpers).
// La ruta animada y su reloj se prueban expresamente en animated-value.test
// y en Cartera E2E con movimiento habilitado; reducirlo no sustituye esa prueba.
// `writable`: los tests
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

// Node ≥ 25 define `globalThis.localStorage` (experimental) y vale `undefined` sin
// `--localstorage-file`; como la propiedad ya existe en el global, jsdom NO la
// pisa y `localStorage.clear()` rompe con «Cannot read properties of undefined».
// Se instala un almacenamiento en memoria con la misma superficie (Storage). Los
// tests que stubean localStorage por su cuenta (vi.stubGlobal) lo siguen pudiendo pisar.
if (typeof window !== 'undefined' && globalThis.localStorage == null) {
  const datos = new Map<string, string>()
  const memoria = {
    get length() {
      return datos.size
    },
    key: (i: number) => [...datos.keys()][i] ?? null,
    getItem: (k: string) => datos.get(String(k)) ?? null,
    setItem: (k: string, v: string) => {
      datos.set(String(k), String(v))
    },
    removeItem: (k: string) => {
      datos.delete(String(k))
    },
    clear: () => {
      datos.clear()
    },
  }
  Object.defineProperty(globalThis, 'localStorage', { value: memoria, writable: true, configurable: true })
}

afterEach(() => {
  cleanup()
})
