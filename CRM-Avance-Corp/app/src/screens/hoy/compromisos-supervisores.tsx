// F4.4 «Hoy del supervisor, sin ruido»: la trazabilidad para GERENCIA de los
// reconocimientos de alertas — reconocer es un compromiso con trazabilidad,
// no un botón de silencio (decisión de Miguel, F4.1). La tarjeta lista qué
// alertas están reconocidas o pospuestas, por quién y hasta cuándo rigen
// COMO MÁXIMO.
//
// Es una tarjeta de LECTURA: sin acciones (gerencia no reconoce por otros —
// el compromiso es personal, sellado en servidor) y sin rojos (la urgencia
// vive en las campanas; esto es un registro). El estado vacío SE MUESTRA:
// «ningún compromiso» significa que ninguna campana está atenuada, y esa
// ausencia es exactamente lo que gerencia audita. Límite honesto (Codex
// F4.4 B4): la tarjeta NO puede saber si un compromiso ya cedió porque su
// alerta empeoró — eso vive en la campana del supervisor; la nota al pie lo
// dice en llano en vez de prometer «vigente».
import { useMemo, type JSX } from 'react'
import { ClipboardCheck, RefreshCw } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { SectionHead } from '@/components/common/section-head'
import { useReconocimientosAlertas } from '@/data/crm-queries'
import { useAhora } from '@/lib/ahora'
import { horaLima } from '@/lib/agenda-derivada'
import { haceCortoTexto } from '@/lib/inteligencia'
import { textoVencimiento } from '@/lib/reconocimientos-alertas'
import {
  TOPE_LISTADO_RECONOCIMIENTOS,
  asientosDemoTrazabilidad,
  derivarCompromisos,
  resumenCompromisos,
} from '@/lib/trazabilidad-reconocimientos'

/** «el 30 de agosto a las 15:00» — con la hora SIEMPRE (Codex F4.4): dentro
 *  de una ventana de 7 días, el día solo no le dice a gerencia si una
 *  posposición de hoy ya venció o vence esta tarde. */
function textoVenceCon(venceEn: number): string {
  return `el ${textoVencimiento(venceEn)} a las ${horaLima(venceEn)}`
}

export function CompromisosSupervisoresPanel({
  demo,
  nombrePorId,
}: {
  demo: boolean
  /** perfil_id → nombre, del roster completo de gerencia. */
  nombrePorId: ReadonlyMap<string, string>
}): JSX.Element {
  const ahora = useAhora()
  // En real, la vista de VIGENTES del servidor (RLS: gerencia lee todo; el
  // reloj de Postgres corta la vigencia y sirve UN asiento por alerta). En
  // demo, el espejo local — misma forma del contrato, sobre los supervisores
  // del roster demo.
  const consulta = useReconocimientosAlertas(!demo)
  const asientos = useMemo(
    () => (demo ? asientosDemoTrazabilidad(ahora) : (consulta.data ?? [])),
    [ahora, consulta.data, demo],
  )
  const compromisos = useMemo(() => derivarCompromisos(asientos, ahora), [ahora, asientos])
  const resumen = resumenCompromisos(compromisos)
  const error = !demo && consulta.error != null
  // Caché fría: decir «ningún compromiso» mientras la red responde sería
  // inventar un vacío (Codex F4.4 B3).
  const consultando = !demo && !error && consulta.isPending
  // El tope del listado alcanzado = puede faltar trazabilidad; se DICE.
  const recortado = !demo && asientos.length >= TOPE_LISTADO_RECONOCIMIENTOS

  return (
    <Card>
      <SectionHead
        icon={ClipboardCheck}
        title="Compromisos de supervisores"
        right={resumen != null && !consultando && !error
          ? <span className="text-xs font-semibold text-muted-foreground-strong">{resumen}</span>
          : undefined}
      />
      {error ? (
        <CardContent className="flex flex-wrap items-center justify-between gap-3 pb-5 pt-0">
          {/* El mensaje es lo ÚNICO vivo (a11y F4.4 #2): con el botón dentro
              del status, el anuncio arrastraba el rótulo de Reintentar. */}
          <p role="status" className="text-xs font-semibold text-warning-text">
            No se pudieron cargar los compromisos. No se muestra nada para no inventar.
          </p>
          <Button type="button" variant="outline" size="sm" onClick={() => void consulta.refetch()}>
            <RefreshCw aria-hidden /> Reintentar
          </Button>
        </CardContent>
      ) : consultando ? (
        <CardContent aria-busy="true" role="status" className="pb-5 pt-0">
          <p className="text-xs font-medium text-muted-foreground">Consultando los compromisos…</p>
        </CardContent>
      ) : compromisos.length === 0 ? (
        <CardContent className="pb-5 pt-0">
          <p className="text-xs font-medium text-muted-foreground">
            Ningún compromiso en curso: ningún supervisor tiene alertas reconocidas ni pospuestas hoy.
          </p>
        </CardContent>
      ) : (
        <CardContent className="space-y-3 pb-5 pt-0">
          {recortado && (
            <p role="status" className="text-xs font-semibold text-warning-text">
              La lista llegó al tope de {TOPE_LISTADO_RECONOCIMIENTOS} registros: puede faltar trazabilidad.
            </p>
          )}
          {/* role="list" EXPLÍCITO (a11y F4.4 #1): el preflight de Tailwind
              pone list-style:none y Safari+VoiceOver borra entonces la
              semántica del ul nativo — sin esto gerencia no oye «lista, N».
              NO es redundante: es la restauración documentada (.oxlintrc). */}
          {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
          <ul role="list" className="space-y-3">
            {compromisos.map((c) => {
              // Un supervisor recién retirado del equipo ya no está en el
              // roster operativo; su compromiso sigue siendo trazable y se
              // dice de quién NO se sabe (jamás se oculta la fila).
              const supervisor = nombrePorId.get(c.supervisorId) ?? 'Un supervisor ya fuera del equipo'
              return (
                <li key={c.id} className="space-y-0.5 leading-tight">
                  <p className="text-xs font-bold text-foreground">
                    {supervisor}{' '}
                    <span className="font-semibold text-muted-foreground-strong">
                      {c.accion === 'posponer' ? 'pospuso' : 'reconoció'}
                    </span>{' '}
                    «{c.etiqueta}» ({c.cuanto})
                  </p>
                  {/* La traza completa en texto: severidad con la que se
                      comprometió, cuándo y hasta cuándo rige como máximo —
                      nada vive solo en un color. */}
                  <p className="text-[11px] font-medium text-muted-foreground">
                    severidad {c.severidad === 'critica' ? 'crítica' : 'de atención'}
                    {' · '}{haceCortoTexto((ahora - c.creadoEn) / 86_400_000)}
                    {' · '}
                    {c.accion === 'posponer'
                      ? `se reactiva ${textoVenceCon(c.venceEn)}`
                      : `rige como máximo hasta ${textoVenceCon(c.venceEn)}`}
                  </p>
                </li>
              )
            })}
          </ul>
          <p className="border-t border-border/60 pt-2 text-[11px] font-medium text-muted-foreground">
            Si una de estas alertas suma un caso nuevo o sube de gravedad, vuelve a sonar en la
            campana del supervisor antes de su fecha — eso no se refleja aquí.
          </p>
        </CardContent>
      )}
    </Card>
  )
}
