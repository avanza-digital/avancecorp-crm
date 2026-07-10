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

export function instalarSentry(): void {
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
          // Las migas de navegación/console pueden arrastrar texto libre.
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
