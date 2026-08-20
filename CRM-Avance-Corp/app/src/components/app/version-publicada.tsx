import { useEffect, useState } from 'react'
import { RefreshCw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  consultarVersionPublicada,
  hayVersionNueva,
  INTERVALO_VERSION_PUBLICADA_MS,
  urlParaActualizar,
} from '@/lib/version-publicada'

const BUILD_DESARROLLO = 'desarrollo'
const BUILD_ACTUAL = typeof __CRM_BUILD_ID__ === 'string'
  ? __CRM_BUILD_ID__
  : BUILD_DESARROLLO

interface VersionPublicadaAvisoProps {
  activo?: boolean
  buildActual?: string
  intervaloMs?: number
  fetchVersion?: typeof globalThis.fetch
  onActualizar?: (buildId: string) => void
}

/**
 * Detecta despliegues posteriores sin recargar la sesión por sorpresa.
 *
 * La recarga automática podría borrar un formulario o un reparto aún no
 * guardado. Por eso el aviso permanece visible y la persona actualiza solo
 * después de guardar. También intercepta el error de chunks antiguos de Vite:
 * en lugar de tumbar la pantalla, ofrece la misma salida segura.
 */
export function VersionPublicadaAviso({
  activo = import.meta.env.PROD && BUILD_ACTUAL !== BUILD_DESARROLLO,
  buildActual = BUILD_ACTUAL,
  intervaloMs = INTERVALO_VERSION_PUBLICADA_MS,
  fetchVersion = globalThis.fetch,
  onActualizar,
}: VersionPublicadaAvisoProps = {}) {
  const [buildPublicado, setBuildPublicado] = useState<string | null>(null)
  const [archivoObsoleto, setArchivoObsoleto] = useState(false)

  useEffect(() => {
    if (!activo) return

    let desmontado = false
    let detectada = false
    let comprobando = false
    const controlador = new AbortController()

    const comprobar = async () => {
      if (detectada || comprobando || document.visibilityState === 'hidden') return
      comprobando = true
      const publicada = await consultarVersionPublicada({
        baseUrl: document.baseURI,
        fetchVersion,
        signal: controlador.signal,
      })
      comprobando = false
      if (desmontado || !hayVersionNueva(buildActual, publicada)) return
      detectada = true
      setBuildPublicado(publicada?.buildId ?? null)
    }

    const alVolver = () => {
      if (document.visibilityState === 'visible') void comprobar()
    }
    const alErrorDePrecarga = (evento: WindowEventMap['vite:preloadError']) => {
      // Vite volvería a lanzar el error y desmontaría la vista. Conservamos el
      // estado abierto mientras la persona decide cuándo actualizar.
      evento.preventDefault()
      setArchivoObsoleto(true)
    }

    void comprobar()
    const reloj = window.setInterval(() => void comprobar(), intervaloMs)
    document.addEventListener('visibilitychange', alVolver)
    window.addEventListener('focus', comprobar)
    window.addEventListener('online', comprobar)
    window.addEventListener('vite:preloadError', alErrorDePrecarga)

    return () => {
      desmontado = true
      controlador.abort()
      comprobando = false
      window.clearInterval(reloj)
      document.removeEventListener('visibilitychange', alVolver)
      window.removeEventListener('focus', comprobar)
      window.removeEventListener('online', comprobar)
      window.removeEventListener('vite:preloadError', alErrorDePrecarga)
    }
  }, [activo, buildActual, fetchVersion, intervaloMs])

  if (!buildPublicado && !archivoObsoleto) return null

  const actualizar = () => {
    const destino = buildPublicado ?? `disponible-${Date.now()}`
    if (onActualizar) {
      onActualizar(destino)
      return
    }
    window.location.replace(urlParaActualizar(window.location.href, destino))
  }

  return (
    <aside
      className="fixed inset-x-3 bottom-3 z-[100] mx-auto flex max-w-2xl flex-col gap-3 rounded-2xl border border-primary/20 bg-card p-4 shadow-[0_18px_50px_rgba(15,30,61,0.24)] sm:flex-row sm:items-center"
      role="status"
      aria-live="polite"
      aria-label="Nueva versión del CRM disponible"
    >
      <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary">
        <RefreshCw className="size-5" aria-hidden />
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-sm font-extrabold text-primary">Nueva versión disponible</p>
        <p className="mt-0.5 text-xs leading-relaxed text-muted-foreground">
          Guarda lo que estés editando y actualiza para ver los últimos cambios. Esta pantalla no se recargará sola.
        </p>
      </div>
      <Button type="button" className="shrink-0" onClick={actualizar}>
        Ya guardé, actualizar
      </Button>
    </aside>
  )
}
