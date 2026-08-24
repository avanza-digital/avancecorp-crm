// screens/derivaciones.tsx — módulo operativo de reparto para Supervisión.
//
// Tiene un solo trabajo: ayudar a decidir el reparto de hoy con la carga
// histórica de cada asesor visible. Gestión de equipo conserva su radiografía
// operativa; esta pantalla concentra filtros, borrador, guardado y devolución.
import { useEffect, useMemo, useState, type JSX, type ReactNode } from 'react'
import { Activity, Inbox, SendHorizontal, Users } from 'lucide-react'
import { toast } from 'sonner'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Progress } from '@/components/ui/progress'
import { Select } from '@/components/ui/select'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { DesgloseMonedas } from '@/components/common/desglose-monedas'
import { Paginacion } from '@/components/common/paginacion'
import { SectionHead } from '@/components/common/section-head'
import { StatStrip, type StatChipData } from '@/components/common/stat-strip'
import {
  useDerivarLeadsEquipo,
  useReporteDerivacionesEquipo,
  useRevertirDerivacionEquipo,
} from '@/data/crm-queries'
import { mensajeDeError } from '@/data/crm-api'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import { totalEnSoles } from '@/lib/capital-unificado'
import { moneyK } from '@/lib/format'
import { DIA_MS, diasDesdeReferencia, esAbierto, haceCortoTexto } from '@/lib/inteligencia'
import { paginar } from '@/lib/paginacion'
import type {
  AsesorDerivaciones,
  MovimientoDerivacionHoy,
} from '@/lib/reporte-derivaciones-equipo'
import { SEMAFORO } from '@/lib/semaforo'
import { useTipoCambio, type TipoCambio } from '@/lib/tipo-cambio'
import { origenLabel, type Lead, type Miembro } from '@/lib/tipos'

type ModoPeriodo = 'ayer' | 'semana' | 'rango'

const DERIVAR_POR_PAGINA = 5
const GUARDADAS_POR_PAGINA = 5

function fechaDesplazada(fecha: string, dias: number): string {
  return fechaLima(Date.parse(`${fecha}T12:00:00-05:00`) + dias * DIA_MS)
}

function MiniDato({
  label,
  valor,
  color,
  title,
  children,
}: {
  label: string
  valor: string
  color?: string
  title?: string
  children?: ReactNode
}): JSX.Element {
  return (
    <div className="min-w-0">
      <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
        {label}
      </p>
      <p
        className="truncate text-sm font-extrabold tabular-nums"
        style={color ? { color } : undefined}
        title={title}
      >
        {valor}
      </p>
      {children}
    </div>
  )
}

function TarjetaAsesor({
  asesor,
  tc,
  borradorHoy,
  delay,
}: {
  asesor: AsesorDerivaciones
  tc: TipoCambio | null | undefined
  borradorHoy: number
  delay: number
}): JSX.Element {
  const repartidoHoy = asesor.repartido_hoy + borradorHoy
  const contactabilidad = Math.round(asesor.contactabilidad_pct)
  const capital = totalEnSoles(asesor.capital_pen, asesor.capital_usd, tc?.promedio)
  const capitalUnificado = capital.estado === 'convertido' && capital.total != null

  return (
    <Card className="ac-lift ac-pop h-full p-3" style={{ animationDelay: `${delay}ms` }}>
      <div className="flex items-center gap-2.5">
        <Avatar
          nombre={asesor.asesor_nombre}
          color={SEMAFORO.ok}
          className="size-7 text-[10px]"
        />
        <div className="min-w-0 flex-1">
          <p className="truncate text-[13px] font-semibold">{asesor.asesor_nombre}</p>
          <p className="text-[11px] text-muted-foreground">
            {asesor.derivados} {asesor.derivados === 1 ? 'lead derivado' : 'leads derivados'}
          </p>
        </div>
        <Badge
          color={borradorHoy > 0 ? SEMAFORO.atencion : SEMAFORO.ok}
          variant="outline"
          dot
        >
          Hoy {repartidoHoy}{borradorHoy > 0 ? ' · borrador' : ''}
        </Badge>
      </div>

      <div className="mt-2 grid grid-cols-3 gap-1.5">
        <MiniDato label="Derivados" valor={String(asesor.derivados)} />
        <MiniDato
          label={capitalUnificado ? 'Capital (S/)' : 'Capital (PEN)'}
          valor={capital.total != null ? moneyK(capital.total) : '—'}
        >
          <DesgloseMonedas
            pen={asesor.capital_pen}
            usd={asesor.capital_usd}
            tc={capital.tc}
            compacto
          />
        </MiniDato>
        <MiniDato
          label="Sin contacto"
          valor={String(asesor.sin_primer_contacto)}
          {...(asesor.sin_primer_contacto > 0 ? { color: SEMAFORO.atencion } : {})}
          title="Derivados en el período sin una primera gestión del asesor"
        />
      </div>

      <div className="mt-2 flex items-center gap-2 text-[11px]">
        <span className="font-semibold text-muted-foreground">Contactabilidad</span>
        <Progress value={contactabilidad} color={SEMAFORO.navy} className="h-1 flex-1" />
        <span className="font-bold tabular-nums">{contactabilidad}%</span>
      </div>
    </Card>
  )
}

function ControlesPeriodo({
  modo,
  desde,
  hasta,
  hoy,
  rangoInvalido,
  onModo,
  onDesde,
  onHasta,
}: {
  modo: ModoPeriodo
  desde: string
  hasta: string
  hoy: string
  rangoInvalido: boolean
  onModo: (modo: ModoPeriodo) => void
  onDesde: (fecha: string) => void
  onHasta: (fecha: string) => void
}): JSX.Element {
  return (
    <div className="border-y border-border/70 bg-muted/20 px-5 py-3">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-2.5">
        <div className="mr-auto min-w-[190px]">
          <p className="text-xs font-semibold">Período para comparar la carga</p>
          <p className="text-[11px] text-muted-foreground">
            Todas las tarjetas responden al mismo filtro.
          </p>
        </div>
        <div
          className="flex items-center gap-1"
          role="group"
          aria-label="Período del reporte de derivaciones"
        >
          <Button
            type="button"
            size="xs"
            variant={modo === 'ayer' ? 'accent' : 'outline'}
            onClick={() => onModo('ayer')}
          >
            Ayer
          </Button>
          <Button
            type="button"
            size="xs"
            variant={modo === 'semana' ? 'accent' : 'outline'}
            onClick={() => onModo('semana')}
          >
            Últimos 7 días
          </Button>
          <Button
            type="button"
            size="xs"
            variant={modo === 'rango' ? 'accent' : 'outline'}
            onClick={() => onModo('rango')}
          >
            Rango
          </Button>
        </div>
        {modo === 'rango' && (
          <div className="flex flex-wrap items-end gap-2">
            <label className="grid gap-1 text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
              Desde
              <input
                type="date"
                value={desde}
                max={hoy}
                aria-label="Fecha inicial del reporte de derivaciones"
                onChange={(event) => onDesde(event.target.value)}
                className="h-8 rounded-lg border border-input bg-background px-2 text-xs font-medium text-foreground shadow-sm outline-none transition focus-visible:ring-[3px] focus-visible:ring-ring/30"
              />
            </label>
            <label className="grid gap-1 text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
              Hasta
              <input
                type="date"
                value={hasta}
                max={hoy}
                aria-label="Fecha final del reporte de derivaciones"
                onChange={(event) => onHasta(event.target.value)}
                className="h-8 rounded-lg border border-input bg-background px-2 text-xs font-medium text-foreground shadow-sm outline-none transition focus-visible:ring-[3px] focus-visible:ring-ring/30"
              />
            </label>
          </div>
        )}
      </div>
      {rangoInvalido && (
        <p role="status" className="mt-2 text-xs font-medium text-destructive">
          Elige un rango válido, de hasta 366 días, que termine hoy o antes.
        </p>
      )}
    </div>
  )
}

function BandejaDerivacion({
  leads,
  asesores,
  ahora,
  borrador,
  guardando,
  bloqueado,
  onCambiar,
  onDescartar,
  onGuardar,
}: {
  leads: Lead[]
  asesores: Miembro[]
  ahora: number
  borrador: Record<string, string>
  guardando: boolean
  bloqueado: boolean
  onCambiar: (leadId: string, asesorId: string | null) => void
  onDescartar: () => void
  onGuardar: () => void
}): JSX.Element {
  const [pagina, setPagina] = useState(0)
  const paginaDerivar = paginar(leads, pagina, DERIVAR_POR_PAGINA)
  const resumen = useMemo(() => {
    let pen = 0
    let usd = 0
    let cantidad = 0
    for (const lead of leads) {
      if (!borrador[lead.id]) continue
      cantidad += 1
      if (lead.moneda === 'USD') usd += lead.monto_estimado ?? 0
      else pen += lead.monto_estimado ?? 0
    }
    return { cantidad, pen, usd }
  }, [borrador, leads])

  useEffect(() => {
    if (pagina !== paginaDerivar.paginaActual) {
      setPagina(paginaDerivar.paginaActual)
    }
  }, [pagina, paginaDerivar.paginaActual])

  if (leads.length === 0) {
    return (
      <p className="px-5 pb-4 text-sm text-muted-foreground">
        No hay leads por repartir — bandeja limpia.
      </p>
    )
  }

  return (
    <div className="space-y-2 px-5 pb-4">
      <p className="text-[11px] text-muted-foreground">
        Elige el asesor de cada lead. Puedes cambiarlo o quitarlo antes de guardar el lote.
      </p>
      {bloqueado && (
        <p role="status" className="rounded-lg border border-border bg-muted/35 px-3 py-2 text-xs text-muted-foreground">
          Para derivar, primero carga un reporte válido del equipo.
        </p>
      )}
      <div role="list" aria-label="Leads por derivar hoy" className="space-y-2">
        {paginaDerivar.visibles.map((lead) => {
          const dias = diasDesdeReferencia(lead.creado_en, ahora)
          const asesorId = borrador[lead.id] ?? ''
          const elegido = asesorId !== ''
          return (
            <div
              key={lead.id}
              role="listitem"
              className={`flex flex-col gap-2.5 rounded-xl border p-3 transition-colors sm:flex-row sm:items-center ${
                elegido ? 'border-accent/35 bg-accent/[0.04]' : 'border-border'
              }`}
            >
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-semibold">{lead.nombre_completo}</p>
                <p className="truncate text-[11px] text-muted-foreground">
                  {origenLabel(lead.origen)}
                  {' · '}
                  {lead.monto_estimado != null
                    ? moneyK(lead.monto_estimado, lead.moneda)
                    : 'Sin monto'}
                  {' · entró '}
                  <span
                    style={dias >= 1
                      ? { color: SEMAFORO.critico, fontWeight: 700 }
                      : undefined}
                  >
                    {haceCortoTexto(dias)}
                  </span>
                </p>
              </div>
              <div className="flex items-center gap-2 sm:w-[300px] sm:shrink-0">
                <Select
                  value={asesorId}
                  disabled={guardando || bloqueado}
                  onChange={(event) => onCambiar(lead.id, event.target.value || null)}
                  aria-label={`Derivar ${lead.nombre_completo} a un asesor`}
                >
                  <option value="">Derivar a…</option>
                  {asesores.map((asesor) => (
                    <option key={asesor.perfil_id} value={asesor.perfil_id}>
                      {asesor.nombre_completo}
                    </option>
                  ))}
                </Select>
                {elegido && (
                  <Button
                    type="button"
                    size="sm"
                    variant="ghost"
                    disabled={guardando}
                    onClick={() => onCambiar(lead.id, null)}
                  >
                    Quitar
                  </Button>
                )}
              </div>
            </div>
          )
        })}
      </div>

      {paginaDerivar.paginas > 1 && (
        <div className="border-t border-border pt-3">
          <Paginacion
            paginaActual={paginaDerivar.paginaActual}
            paginas={paginaDerivar.paginas}
            total={leads.length}
            onCambio={setPagina}
            ariaLabel="Paginación de leads por derivar hoy"
          />
        </div>
      )}

      <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-accent/20 bg-accent/[0.04] px-3 py-2.5">
        <div>
          <p className="text-xs font-bold">
            {resumen.cantidad === 0
              ? 'Aún no hay leads en el borrador'
              : `${resumen.cantidad} ${resumen.cantidad === 1 ? 'lead listo' : 'leads listos'} para derivar`}
          </p>
          {resumen.cantidad > 0 && (
            <p className="text-[11px] text-muted-foreground">
              {moneyK(resumen.pen)}
              {resumen.usd > 0 ? ` + ${moneyK(resumen.usd, 'USD')}` : ''}
              {' · las tarjetas de arriba ya consideran el borrador.'}
            </p>
          )}
        </div>
        <div className="flex items-center gap-2">
          <Button
            type="button"
            size="sm"
            variant="ghost"
            disabled={guardando || resumen.cantidad === 0}
            onClick={onDescartar}
          >
            Descartar borrador
          </Button>
          <Button
            type="button"
            size="sm"
            disabled={guardando || bloqueado || resumen.cantidad === 0}
            onClick={onGuardar}
          >
            {guardando
              ? 'Guardando…'
              : resumen.cantidad > 0
                ? `Guardar ${resumen.cantidad} derivación${resumen.cantidad === 1 ? '' : 'es'}`
                : 'Guardar derivaciones'}
          </Button>
        </div>
      </div>
    </div>
  )
}

function GuardadasHoy({
  movimientos,
  devolviendoId,
  onDevolver,
}: {
  movimientos: MovimientoDerivacionHoy[]
  devolviendoId: string | null
  onDevolver: (movimiento: MovimientoDerivacionHoy) => void
}): JSX.Element {
  const [pagina, setPagina] = useState(0)
  const paginaGuardadas = paginar(movimientos, pagina, GUARDADAS_POR_PAGINA)

  if (movimientos.length === 0) {
    return (
      <p className="px-5 pb-4 text-sm text-muted-foreground">
        Aún no hay derivaciones guardadas hoy.
      </p>
    )
  }

  return (
    <div className="px-5 pb-4">
      <p className="text-[11px] text-muted-foreground">
        Puedes devolver un lead mientras el asesor no haya registrado gestión.
      </p>
      <ul
        aria-label="Derivaciones guardadas hoy"
        className="mt-3 space-y-2"
      >
        {paginaGuardadas.visibles.map((movimiento) => (
          <li
            key={`${movimiento.lead_id}-${movimiento.derivado_en}`}
            className="flex flex-col gap-2 rounded-xl border border-border p-3 sm:flex-row sm:items-center"
          >
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold">{movimiento.nombre_completo}</p>
              <p className="truncate text-[11px] text-muted-foreground">
                {movimiento.monto_estimado != null
                  ? moneyK(movimiento.monto_estimado, movimiento.moneda)
                  : 'Sin monto'}
                {' · '}
                {movimiento.asesor_nombre}
              </p>
            </div>
            <Button
              type="button"
              size="sm"
              variant="outline"
              disabled={!movimiento.reversible || devolviendoId != null}
              title={movimiento.reversible
                ? 'Devolver a mi bandeja'
                : 'El asesor ya registró gestión'}
              onClick={() => onDevolver(movimiento)}
            >
              {devolviendoId === movimiento.lead_id
                ? 'Devolviendo…'
                : movimiento.reversible ? 'Devolver' : 'Ya gestionado'}
            </Button>
          </li>
        ))}
      </ul>
      {paginaGuardadas.paginas > 1 && (
        <div className="mt-3 border-t border-border pt-3">
          <Paginacion
            paginaActual={paginaGuardadas.paginaActual}
            paginas={paginaGuardadas.paginas}
            total={movimientos.length}
            onCambio={setPagina}
            ariaLabel="Paginación de derivaciones guardadas hoy"
          />
        </div>
      )}
    </div>
  )
}

export function Derivaciones(): JSX.Element {
  const { ambito, recargar } = useCRMData()
  const { yo } = useAuth()
  const ahora = useAhora()
  const { tc } = useTipoCambio()

  const leadsPorRepartir = useMemo(
    () => ambito.leads.filter((lead) => esAbierto(lead) && lead.vendedor_id == null),
    [ambito.leads],
  )
  const hoy = fechaLima(ahora)
  const ayer = fechaDesplazada(hoy, -1)
  const [modo, setModo] = useState<ModoPeriodo>('ayer')
  const [desdeRango, setDesdeRango] = useState(() => fechaLima(Date.now() - 7 * DIA_MS))
  const [hastaRango, setHastaRango] = useState(() => fechaLima(Date.now() - DIA_MS))
  const periodo = useMemo(() => {
    if (modo === 'ayer') return { desde: ayer, hasta: ayer }
    if (modo === 'semana') return { desde: fechaDesplazada(hoy, -7), hasta: ayer }
    return { desde: desdeRango, hasta: hastaRango }
  }, [ayer, desdeRango, hastaRango, hoy, modo])
  const diferenciaDias = periodo.desde && periodo.hasta
    ? Math.round(
        (Date.parse(`${periodo.hasta}T12:00:00-05:00`)
          - Date.parse(`${periodo.desde}T12:00:00-05:00`)) / DIA_MS,
      )
    : Number.POSITIVE_INFINITY
  const rangoValido = Boolean(
    periodo.desde
    && periodo.hasta
    && periodo.desde <= periodo.hasta
    && periodo.hasta <= hoy
    && diferenciaDias <= 365,
  )
  const reporte = useReporteDerivacionesEquipo(
    !yo?.demo && rangoValido,
    periodo.desde,
    periodo.hasta,
  )

  const [borrador, setBorrador] = useState<Record<string, string>>({})
  const derivar = useDerivarLeadsEquipo()
  const revertir = useRevertirDerivacionEquipo()
  const [devolviendoId, setDevolviendoId] = useState<string | null>(null)

  useEffect(() => {
    const disponibles = new Set(leadsPorRepartir.map((lead) => lead.id))
    const asesores = new Set(ambito.vendedores.map((asesor) => asesor.perfil_id))
    setBorrador((actual) => {
      const siguiente = Object.fromEntries(
        Object.entries(actual).filter(
          ([leadId, asesorId]) => disponibles.has(leadId) && asesores.has(asesorId),
        ),
      )
      return Object.keys(siguiente).length === Object.keys(actual).length
        ? actual
        : siguiente
    })
  }, [ambito.vendedores, leadsPorRepartir])

  const borradorPorAsesor = useMemo(() => {
    const conteos = new Map<string, number>()
    for (const asesorId of Object.values(borrador)) {
      conteos.set(asesorId, (conteos.get(asesorId) ?? 0) + 1)
    }
    return conteos
  }, [borrador])
  const totalBorrador = Object.keys(borrador).length

  const cambiarBorrador = (leadId: string, asesorId: string | null) => {
    setBorrador((actual) => {
      if (asesorId == null) {
        const siguiente = { ...actual }
        delete siguiente[leadId]
        return siguiente
      }
      return { ...actual, [leadId]: asesorId }
    })
  }

  const guardarBorrador = async () => {
    const derivaciones = Object.entries(borrador).map(([leadId, asesorId]) => ({
      leadId,
      asesorId,
    }))
    if (derivaciones.length === 0) return
    try {
      const resultado = await derivar.mutateAsync(derivaciones)
      setBorrador({})
      await recargar()
      toast.success(
        `${resultado.derivados} ${resultado.derivados === 1 ? 'lead derivado' : 'leads derivados'} a tu equipo`,
      )
    } catch (error) {
      toast.error(mensajeDeError(error, 'No se pudieron guardar las derivaciones.'))
    }
  }

  const devolverDerivacion = async (movimiento: MovimientoDerivacionHoy) => {
    setDevolviendoId(movimiento.lead_id)
    try {
      await revertir.mutateAsync(movimiento.lead_id)
      await recargar()
      toast.success(`${movimiento.nombre_completo} volvió a tu bandeja`)
    } catch (error) {
      toast.error(mensajeDeError(error, 'No se pudo devolver el lead a tu bandeja.'))
    } finally {
      setDevolviendoId(null)
    }
  }

  const totalDerivados = reporte.data?.asesores.reduce(
    (total, asesor) => total + asesor.derivados,
    0,
  )
  const stats: StatChipData[] = [
    {
      icon: Users,
      label: 'Asesores activos',
      value: reporte.data ? String(reporte.data.asesores.length) : '—',
      tone: 'accent',
    },
    {
      icon: SendHorizontal,
      label: 'Derivados en el período',
      value: totalDerivados != null ? String(totalDerivados) : '—',
      tone: 'primary',
    },
    {
      icon: Inbox,
      label: 'Por repartir',
      value: String(leadsPorRepartir.length),
      tone: leadsPorRepartir.length > 0 ? 'warn' : 'default',
      sub: totalBorrador > 0 ? `${totalBorrador} en borrador` : 'Bandeja del supervisor',
    },
    {
      icon: Activity,
      label: 'Guardadas hoy',
      value: reporte.data ? String(reporte.data.movimientos_hoy.length) : '—',
      sub: 'Se pueden devolver antes de la gestión',
    },
  ]

  return (
    <div className="mx-auto max-w-[1280px] space-y-5 ac-rise">
      <StatStrip stats={stats} />

      <AvisoDegradacion
        activo={!yo?.demo && Boolean(reporte.error)}
        queReintenta="del reporte de derivaciones"
        onReintentar={() => { void reporte.refetch() }}
      >
        No se pudo cargar la carga histórica del equipo. El reparto permanece detenido para no decidir con cifras incompletas.
      </AvisoDegradacion>

      <Card>
        <SectionHead
          icon={Users}
          title="Carga por asesor"
          right={(
            <span className="text-xs tabular-nums text-muted-foreground">
              {periodo.desde} a {periodo.hasta}
            </span>
          )}
        />
        <ControlesPeriodo
          modo={modo}
          desde={desdeRango}
          hasta={hastaRango}
          hoy={hoy}
          rangoInvalido={!rangoValido}
          onModo={setModo}
          onDesde={(fecha) => {
            setModo('rango')
            setDesdeRango(fecha)
          }}
          onHasta={(fecha) => {
            setModo('rango')
            setHastaRango(fecha)
          }}
        />
        <CardContent className="pt-4">
          {yo?.demo ? (
            <p className="text-sm text-muted-foreground">
              El reporte de derivaciones usa datos reales y no está disponible en el modo demostración.
            </p>
          ) : !rangoValido ? (
            <p className="text-sm text-muted-foreground">
              Corrige el rango para comparar la carga del equipo.
            </p>
          ) : reporte.isPending && !reporte.data ? (
            <p className="text-sm text-muted-foreground">Cargando las derivaciones del período…</p>
          ) : reporte.data == null ? (
            <div className="flex flex-wrap items-center gap-3">
              <p className="text-sm text-muted-foreground">
                El reporte no está disponible en este momento.
              </p>
              <Button
                type="button"
                size="sm"
                variant="outline"
                onClick={() => { void reporte.refetch() }}
              >
                Reintentar
              </Button>
            </div>
          ) : reporte.data.asesores.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              No tienes asesores activos a cargo todavía.
            </p>
          ) : (
            <ul
              aria-label="Derivaciones por asesor de mi equipo"
              className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
            >
              {reporte.data.asesores.map((asesor, indice) => (
                <li key={asesor.asesor_id}>
                  <TarjetaAsesor
                    asesor={asesor}
                    tc={tc}
                    borradorHoy={borradorPorAsesor.get(asesor.asesor_id) ?? 0}
                    delay={indice * 60}
                  />
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <div className="grid items-start gap-5 lg:grid-cols-[minmax(0,1.15fr)_minmax(360px,0.85fr)]">
        <Card>
          <SectionHead
            icon={SendHorizontal}
            title="Derivar hoy"
            right={leadsPorRepartir.length > 0 ? (
              <Badge color={SEMAFORO.atencion} variant="outline" dot>
                {leadsPorRepartir.length} en bandeja
              </Badge>
            ) : undefined}
          />
          <BandejaDerivacion
            leads={leadsPorRepartir}
            asesores={ambito.vendedores}
            ahora={ahora}
            borrador={borrador}
            guardando={derivar.isPending}
            bloqueado={yo?.demo === true || !rangoValido || reporte.data == null || Boolean(reporte.error)}
            onCambiar={cambiarBorrador}
            onDescartar={() => setBorrador({})}
            onGuardar={() => { void guardarBorrador() }}
          />
        </Card>

        <Card>
          <SectionHead
            icon={Activity}
            title="Guardadas hoy"
            right={reporte.data && reporte.data.movimientos_hoy.length > 0 ? (
              <Badge color={SEMAFORO.atencion} variant="outline" dot>
                {reporte.data.movimientos_hoy.length} por revisar
              </Badge>
            ) : undefined}
          />
          {yo?.demo ? (
            <p className="px-5 pb-4 text-sm text-muted-foreground">
              Las derivaciones guardadas se muestran solo con datos reales.
            </p>
          ) : reporte.isPending && !reporte.data ? (
            <p className="px-5 pb-4 text-sm text-muted-foreground">
              Cargando las derivaciones de hoy…
            </p>
          ) : reporte.data ? (
            <GuardadasHoy
              movimientos={reporte.data.movimientos_hoy}
              devolviendoId={devolviendoId}
              onDevolver={(movimiento) => { void devolverDerivacion(movimiento) }}
            />
          ) : (
            <p className="px-5 pb-4 text-sm text-muted-foreground">
              Cuando el reporte esté disponible, aquí podrás devolver una derivación antes de que sea gestionada.
            </p>
          )}
        </Card>
      </div>

      <p className="text-[11px] text-muted-foreground">
        El historial y el capital responden al período elegido. El borrador de hoy no cambia ningún dueño hasta que guardes el lote.
      </p>
    </div>
  )
}
