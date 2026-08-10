// Integración OPCIONAL con Sentry (hallazgo Media: la observabilidad moría en
// la consola del navegador). Diseño:
//  - Sin VITE_SENTRY_DSN configurada NO se hace nada y el chunk de Sentry ni
//    se descarga (import dinámico) — cero peso para el usuario.
//  - PII: manejamos DNI/teléfonos/nombres de clientes. El scrub NUESTRO
//    (observabilidad.limpiarDato/limpiarTexto) se aplica en beforeSend y en
//    breadcrumbs — no se confía solo en el scrubbing por defecto de Sentry.
//  - Los registrarError/registrarAviso llegan vía el sumidero de
//    observabilidad.ts YA limpios.
import {
  conectarSumidero,
  idCorrelacion,
  limpiarDato,
  limpiarTexto,
  registrarAviso,
} from './observabilidad'

/** Deja la ruta (QUÉ se llamó) y descarta la query (CON QUÉ datos se llamó). */
function sinQuery(url: string): string {
  const corte = url.search(/[?#]/)
  return corte === -1 ? url : `${url.slice(0, corte)}?[QUERY REDACTADA]`
}

export function instalarSentry(): void {
  // SILENCIO TOTAL fuera de producción (decisión de Miguel, 2026-08-10).
  //
  // `app/.env` es el único fichero con DSN y Vite lo carga en TODOS los modos, así
  // que cada `npm run dev` —y cada corrida de Playwright, que levanta ese mismo
  // servidor de dev— reportaba al proyecto de PRODUCCIÓN. El 2026-08-09 eso enterró
  // la señal bajo 742 eventos de laboratorio: mocks de E2E y fetches cancelados que
  // parecían caídas del backend. El gate va aquí y no en el `.env` porque el `.env`
  // se repone sin querer y no protege de un build local; esto es incondicional.
  // Se compara MODE contra 'production' y NO se usa `PROD`: Vite deriva `PROD` de
  // NODE_ENV, así que `vite build --mode staging` da PROD=true (staging reportaría
  // al DSN de producción) y `NODE_ENV=production vite` also. MODE es el modo real
  // del build, que es lo que queremos discriminar. Hallazgo de la revisión de Codex.
  // (`NODE_ENV=production vite` —un servidor de desarrollo— también daba PROD=true.)
  if (import.meta.env.MODE !== 'production') return

  const dsn = import.meta.env.VITE_SENTRY_DSN
  if (typeof dsn !== 'string' || dsn.trim() === '') return

  void import('@sentry/react')
    .then((Sentry) => {
      Sentry.init({
        dsn: dsn.trim(),
        environment: import.meta.env.MODE,
        // Solo errores (sin tracing/replay): mínimo peso y mínima superficie
        // de datos. Ampliar será una decisión explícita, no un default.
        tracesSampleRate: 0,
        sendDefaultPii: false,
        initialScope: { tags: { correlationId: idCorrelacion() } },
        beforeSend(evento) {
          // Escombrar PII con NUESTRAS reglas encima de las de Sentry.
          if (evento.message) evento.message = limpiarTexto(evento.message)
          for (const excepcion of evento.exception?.values ?? []) {
            if (excepcion.value) excepcion.value = limpiarTexto(excepcion.value)
          }
          if (evento.request) delete evento.request
          if (evento.user) delete evento.user
          if (evento.extra) evento.extra = limpiarDato(evento.extra) as Record<string, unknown>
          if (evento.contexts) evento.contexts = limpiarDato(evento.contexts) as typeof evento.contexts
          return evento
        },
        beforeBreadcrumb(miga) {
          // ── Fuga de PII cerrada (hallazgo BLOQUEANTE de la revisión de Codex) ──
          // Sentry trae activas por defecto las migas de UI, y su serializador copia
          // LITERALMENTE el árbol DOM del elemento pulsado, `aria-label` incluido.
          // El CRM pone nombres de clientes justo ahí: «Llamar a JUAN PÉREZ»
          // (contacto.tsx), «Repartir a …» (repartir.tsx). Y nuestro `limpiarTexto`
          // NO conoce nombres propios — solo credenciales, correos y números.
          // `sendDefaultPii: false` tampoco desactiva esta integración.
          // Se descartan ENTERAS: la miga de reproducción no vale una fuga de PII.
          if (miga.category?.startsWith('ui.')) return null
          // En fetch/xhr la QUERY lleva los filtros de PostgREST, y ahí viaja el
          // texto que el usuario escribió en el buscador
          // (`nombre_completo=ilike.%…%`). Se conserva la ruta —dice QUÉ se llamó—
          // y se tira la query, que dice CON QUÉ datos.
          if (miga.data && typeof miga.data.url === 'string') {
            miga.data = { ...miga.data, url: sinQuery(miga.data.url) }
          }
          if (miga.message) miga.message = limpiarTexto(miga.message)
          if (miga.data) miga.data = limpiarDato(miga.data) as Record<string, unknown>
          return miga
        },
      })

      // Errores y avisos estructurados del CRM (ya limpios de PII).
      conectarSumidero((entrada) => {
        Sentry.captureMessage(`[${entrada.evento}]`, {
          level: entrada.nivel === 'error' ? 'error' : 'warning',
          extra: { datos: entrada.datos, correlationId: entrada.correlationId },
        })
      })
    })
    .catch((causa: unknown) => {
      registrarAviso('sentry.no_instalado', causa)
    })
}
