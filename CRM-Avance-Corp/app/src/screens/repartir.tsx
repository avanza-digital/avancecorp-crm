// Repartir leads (C1) — la única pantalla del coordinador: mueve los leads
// recién nacidos de la cola global a la BANDEJA de un supervisor, que luego los
// baja a sus vendedores.
//
// Orden comercial (regla de Miguel: lo que genera ingreso, primero): capital en
// juego arriba, la cola FIFO como protagonista, y en cada fila el monto del
// lead — porque repartir un lead de US$ 30k no es lo mismo que uno de S/ 3k.
// PEN y USD JAMÁS se suman: se muestran como dos cifras separadas.
//
// Estado local con React (sin XState: eso vive solo en auth). La verdad la tiene
// el servidor — cada reparto pasa por la RPC atómica crm.repartir_lead.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Split, Users, Wallet, Inbox } from 'lucide-react'
import { toast } from 'sonner'
import {
  CrmApiError,
  leadsPorRepartir,
  repartirLead,
  supervisoresParaReparto,
} from '@/data/crm-api'
import { origenLabel, type ColaLead, type SupervisorReparto } from '@/lib/tipos'
import { moneyK } from '@/lib/format'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { SectionHead } from '@/components/common/section-head'
import { StatStrip } from '@/components/common/stat-strip'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'

/** Días transcurridos desde que el lead entró a la cola (para la urgencia). */
function diasEnCola(desde: string, ahora: number): number {
  const t = Date.parse(desde)
  if (!Number.isFinite(t)) return 0
  return Math.max(0, Math.floor((ahora - t) / 86_400_000))
}

function esperaTxt(dias: number): string {
  if (dias <= 0) return 'hoy'
  if (dias === 1) return 'hace 1 día'
  return `hace ${dias} días`
}

interface EstadoReparto {
  cola: ColaLead[]
  supervisores: SupervisorReparto[]
  cargando: boolean
  error: string | null
}

function useReparto() {
  const [estado, setEstado] = useState<EstadoReparto>({
    cola: [], supervisores: [], cargando: true, error: null,
  })
  const [enviandoId, setEnviandoId] = useState<string | null>(null)
  const abortRef = useRef<AbortController | null>(null)

  const cargar = useCallback(async () => {
    abortRef.current?.abort()
    const ctrl = new AbortController()
    abortRef.current = ctrl
    setEstado((e) => ({ ...e, cargando: true, error: null }))
    try {
      const [cola, supervisores] = await Promise.all([
        leadsPorRepartir(ctrl.signal),
        supervisoresParaReparto(ctrl.signal),
      ])
      if (ctrl.signal.aborted) return
      setEstado({ cola, supervisores, cargando: false, error: null })
    } catch (error) {
      if (ctrl.signal.aborted) return
      setEstado((e) => ({
        ...e,
        cargando: false,
        error: error instanceof Error ? error.message : 'No se pudo cargar la cola de leads.',
      }))
    }
  }, [])

  useEffect(() => {
    void cargar()
    return () => abortRef.current?.abort()
  }, [cargar])

  /** Reparte un lead. El servidor manda: si rechaza, la fila NO se mueve. */
  const repartir = useCallback(async (lead: ColaLead, supervisorId: string) => {
    const destino = supervisorId
    setEnviandoId(lead.id)
    try {
      await repartirLead(lead.id, destino)
      // Éxito: la fila sale de la cola y la bandeja destino sube en 1 (el
      // servidor ya lo sabe; esto evita un refetch completo por cada reparto).
      setEstado((e) => ({
        ...e,
        cola: e.cola.filter((l) => l.id !== lead.id),
        supervisores: e.supervisores.map((s) =>
          s.perfil_id === destino ? { ...s, bandeja_pendiente: s.bandeja_pendiente + 1 } : s,
        ),
      }))
      const nombre = estado.supervisores.find((s) => s.perfil_id === destino)?.nombre ?? 'la bandeja'
      toast.success(`${lead.nombre_completo} pasó a ${nombre}`)
    } catch (error) {
      const mensaje = error instanceof Error ? error.message : 'No se pudo repartir el lead.'
      toast.error(mensaje)
      // Fuera de cola, veto legal o carrera: la cola local quedó desfasada
      // respecto del servidor → se relee en vez de adivinar.
      if (error instanceof CrmApiError
        && ['FUERA_DE_COLA', 'NO_INSISTA', 'REINTENTAR'].includes(error.code)) {
        void cargar()
      }
    } finally {
      setEnviandoId(null)
    }
  }, [cargar, estado.supervisores])

  return { ...estado, enviandoId, recargar: cargar, repartir }
}

export function Repartir() {
  const { cola, supervisores, cargando, error, enviandoId, recargar, repartir } = useReparto()
  const [destino, setDestino] = useState<Record<string, string>>({})
  const ahora = Date.now()

  // Capital en juego, SIEMPRE separado por moneda (nunca una suma mixta).
  const capital = useMemo(() => {
    let pen = 0
    let usd = 0
    for (const l of cola) {
      if (l.moneda === 'USD') usd += l.monto_estimado
      else pen += l.monto_estimado
    }
    return { pen, usd }
  }, [cola])

  const masAntiguo = useMemo(() => {
    if (cola.length === 0) return 0
    return Math.max(...cola.map((l) => diasEnCola(l.creado_en, ahora)))
  }, [cola, ahora])

  const stats = useMemo(() => [
    { icon: Inbox, label: 'Por repartir', value: String(cola.length), tone: cola.length > 0 ? 'accent' : 'default' as const },
    { icon: Wallet, label: 'Capital en juego (PEN)', value: moneyK(capital.pen, 'PEN') },
    { icon: Wallet, label: 'Capital en juego (USD)', value: moneyK(capital.usd, 'USD') },
    {
      icon: Users,
      label: 'Espera más larga',
      value: cola.length === 0 ? '—' : esperaTxt(masAntiguo),
      tone: masAntiguo >= 1 ? 'warn' : 'default' as const,
    },
  ], [cola.length, capital.pen, capital.usd, masAntiguo])

  return (
    <div className="space-y-5">
      <StatStrip stats={stats} />

      <Card className="overflow-hidden">
        <SectionHead
          icon={Split}
          title="Cola de leads nuevos"
          right={
            <span className="text-[11px] font-semibold text-muted-foreground">
              {cola.length > 0 ? `${cola.length} en espera · más antiguos primero` : ''}
            </span>
          }
        />

        {cargando ? (
          <PanelCargando filas={4} />
        ) : error ? (
          <PanelError mensaje={error} onReintentar={() => void recargar()} reintentando={cargando} />
        ) : cola.length === 0 ? (
          <PanelVacio
            icono={Inbox}
            titulo="No hay leads por repartir"
            detalle="Cuando entren leads nuevos por la hoja o la landing aparecerán aquí para asignarlos a un supervisor."
          />
        ) : supervisores.length === 0 ? (
          <PanelVacio
            icono={Users}
            titulo="No hay supervisores activos"
            detalle="Sin una bandeja de destino no se puede repartir. Avisa a gerencia para activar al menos un supervisor."
          />
        ) : (
          <div className="space-y-2 px-5 pb-5">
            {cola.map((lead) => {
              const dias = diasEnCola(lead.creado_en, ahora)
              const elegido = destino[lead.id] ?? ''
              const enviando = enviandoId === lead.id
              return (
                <div
                  key={lead.id}
                  className="flex flex-col gap-2.5 rounded-xl border border-border p-3 sm:flex-row sm:items-center"
                >
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-semibold">{lead.nombre_completo}</p>
                    <p className="truncate text-[11px] text-muted-foreground">
                      {origenLabel(lead.origen)}
                      {' · '}
                      <span className="font-semibold text-foreground">
                        {moneyK(lead.monto_estimado, lead.moneda)}
                      </span>
                      {lead.distrito ? ` · ${lead.distrito}` : ''}
                      {' · entró '}
                      <span className={dias >= 1 ? 'font-bold text-warning' : undefined}>
                        {esperaTxt(dias)}
                      </span>
                    </p>
                  </div>
                  <div className="flex items-center gap-2 sm:w-[320px] sm:shrink-0">
                    <Select
                      value={elegido}
                      disabled={enviando}
                      onChange={(e) => setDestino((d) => ({ ...d, [lead.id]: e.target.value }))}
                      aria-label={`Asignar ${lead.nombre_completo} a un supervisor`}
                    >
                      <option value="">Asignar a…</option>
                      {supervisores.map((s) => (
                        <option key={s.perfil_id} value={s.perfil_id}>
                          {s.nombre} ({s.bandeja_pendiente} en bandeja)
                        </option>
                      ))}
                    </Select>
                    <Button
                      size="sm"
                      disabled={!elegido || enviando}
                      onClick={() => void repartir(lead, elegido)}
                    >
                      {enviando ? 'Enviando…' : 'Repartir'}
                    </Button>
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </Card>
    </div>
  )
}
