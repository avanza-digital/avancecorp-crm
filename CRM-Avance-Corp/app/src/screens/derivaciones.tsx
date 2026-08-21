// screens/derivaciones.tsx — módulo operativo de reparto para Supervisión.
//
// Tiene un solo trabajo: ayudar a decidir el reparto de hoy con la carga
// histórica de cada asesor visible. Gestión de equipo conserva su radiografía
// operativa; esta pantalla concentra filtros, borrador, guardado y devolución.
import { useEffect, useMemo, useState, type JSX, type ReactNode } from 'react'
import { Activity, Check, CheckCircle2, ChevronDown, Inbox, Search, SendHorizontal, Users, X } from 'lucide-react'
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
import { cn } from '@/lib/utils'

type ModoPeriodo = 'ayer' | 'semana' | 'rango'

const GUARDADAS_POR_PAGINA = 5
const LEADS_POR_PAGINA = 20

/**
 * Identidad estable de cada asesor dentro de esta pantalla. No expresa estado ni
 * rendimiento: conecta visualmente tarjeta, borrador y cierre sin depender solo
 * del nombre. La paleta es la misma del CRM y conserva contraste texto/fondo.
 */
const COLORES_ASESOR = [
  'var(--chart-1)',
  'var(--chart-2)',
  'var(--chart-4)',
  'var(--chart-3)',
  'var(--chart-5)',
] as const

function colorDeAsesor(asesorId: string): string {
  const indice = [...asesorId].reduce((total, caracter) => total + caracter.charCodeAt(0), 0)
  return COLORES_ASESOR[indice % COLORES_ASESOR.length] ?? 'var(--accent)'
}

function colorTextoDeAsesor(asesorId: string): string {
  const color = colorDeAsesor(asesorId)
  if (color === 'var(--chart-3)') return 'var(--warning-text)'
  if (color === 'var(--chart-4)') return '#155e75'
  return color
}

function textoPlano(valor: string): string {
  return valor
    .toLocaleLowerCase('es-PE')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
}

interface GrupoUltimoReparto {
  asesorId: string
  asesorNombre: string
  cantidad: number
  pen: number
  usd: number
}

interface UltimoReparto {
  cantidad: number
  pen: number
  usd: number
  grupos: GrupoUltimoReparto[]
}

function resumirReparto(
  borrador: Readonly<Record<string, string>>,
  leads: readonly Lead[],
  asesores: readonly Miembro[],
): UltimoReparto {
  const leadPorId = new Map(leads.map((lead) => [lead.id, lead]))
  const asesorPorId = new Map(asesores.map((asesor) => [asesor.perfil_id, asesor]))
  const grupos = new Map<string, GrupoUltimoReparto>()
  let pen = 0
  let usd = 0

  for (const [leadId, asesorId] of Object.entries(borrador)) {
    const lead = leadPorId.get(leadId)
    const asesor = asesorPorId.get(asesorId)
    const grupo = grupos.get(asesorId) ?? {
      asesorId,
      asesorNombre: asesor?.nombre_completo ?? 'Asesor',
      cantidad: 0,
      pen: 0,
      usd: 0,
    }
    const monto = lead?.monto_estimado ?? 0
    grupo.cantidad += 1
    if (lead?.moneda === 'USD') {
      grupo.usd += monto
      usd += monto
    } else {
      grupo.pen += monto
      pen += monto
    }
    grupos.set(asesorId, grupo)
  }

  return {
    cantidad: Object.keys(borrador).length,
    pen,
    usd,
    grupos: [...grupos.values()].sort((a, b) =>
      a.asesorNombre.localeCompare(b.asesorNombre, 'es-PE')),
  }
}

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
  const color = colorDeAsesor(asesor.asesor_id)
  const colorTexto = colorTextoDeAsesor(asesor.asesor_id)

  return (
    <Card
      className="ac-lift ac-pop relative h-full overflow-hidden p-3 pl-4"
      style={{ animationDelay: `${delay}ms` }}
    >
      <span
        aria-hidden
        className="absolute inset-y-0 left-0 w-1"
        style={{ background: color }}
      />
      <div className="flex items-center gap-2.5">
        <Avatar
          nombre={asesor.asesor_nombre}
          color={colorTexto}
          className="size-7 text-[10px]"
        />
        <div className="min-w-0 flex-1">
          <p className="truncate text-[13px] font-semibold">{asesor.asesor_nombre}</p>
          <p className="text-[11px] text-muted-foreground">
            {asesor.derivados} {asesor.derivados === 1 ? 'lead derivado' : 'leads derivados'}
          </p>
        </div>
        <Badge
          color={colorTexto}
          variant="outline"
          dot
        >
          Hoy {repartidoHoy}
        </Badge>
      </div>

      {borradorHoy > 0 && (
        <div
          className="mt-2 flex items-center justify-between rounded-lg border px-2.5 py-1.5"
          style={{
            borderColor: `color-mix(in srgb, ${color} 28%, var(--border))`,
            background: `color-mix(in srgb, ${color} 7%, var(--card))`,
          }}
        >
          <span className="text-[11px] font-semibold" style={{ color: colorTexto }}>
            Recibirá del borrador
          </span>
          <span className="text-xs font-extrabold tabular-nums" style={{ color: colorTexto }}>
            +{borradorHoy}
          </span>
        </div>
      )}

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

function RutaReparto({
  reporteListo,
  asesores,
  porRepartir,
  enBorrador,
  guardadasHoy,
  ultimoReparto,
}: {
  reporteListo: boolean
  asesores: number
  porRepartir: number
  enBorrador: number
  guardadasHoy: number
  ultimoReparto: UltimoReparto | null
}): JSX.Element {
  const pasos = [
    {
      numero: 1,
      titulo: 'Comparar carga',
      detalle: reporteListo
        ? `${asesores} ${asesores === 1 ? 'asesor disponible' : 'asesores disponibles'}`
        : 'Esperando el reporte del equipo',
      estado: reporteListo ? 'completo' : 'actual',
    },
    {
      numero: 2,
      titulo: 'Preparar reparto',
      detalle: enBorrador > 0
        ? `${enBorrador} ${enBorrador === 1 ? 'lead elegido' : 'leads elegidos'} uno por uno`
        : `${porRepartir} ${porRepartir === 1 ? 'lead pendiente' : 'leads pendientes'}`,
      estado: reporteListo
        ? enBorrador > 0 || ultimoReparto != null ? 'completo' : 'actual'
        : 'pendiente',
    },
    {
      numero: 3,
      titulo: 'Confirmar',
      detalle: ultimoReparto
        ? `${ultimoReparto.cantidad} ${ultimoReparto.cantidad === 1 ? 'lead guardado' : 'leads guardados'} en el último cierre`
        : enBorrador > 0
          ? 'Revisa y guarda el borrador'
          : `${guardadasHoy} ${guardadasHoy === 1 ? 'derivación guardada hoy' : 'derivaciones guardadas hoy'}`,
      estado: ultimoReparto ? 'completo' : enBorrador > 0 ? 'actual' : 'pendiente',
    },
  ] as const

  return (
    <Card className="overflow-hidden" role="region" aria-label="Flujo para derivar leads">
      <div className="border-b border-border bg-muted/20 px-4 py-2.5 sm:px-5">
        <p className="text-[10px] font-bold uppercase tracking-[0.14em] text-muted-foreground">
          Ruta de reparto
        </p>
      </div>
      <ol className="grid divide-y divide-border sm:grid-cols-3 sm:divide-x sm:divide-y-0">
        {pasos.map((paso) => {
          const actual = paso.estado === 'actual'
          const completo = paso.estado === 'completo'
          return (
            <li
              key={paso.numero}
              aria-current={actual ? 'step' : undefined}
              className={cn(
                'flex min-w-0 items-center gap-3 px-4 py-3.5 sm:px-5',
                actual && 'bg-accent/[0.045]',
                completo && 'bg-primary/[0.025]',
              )}
            >
              <span
                aria-hidden
                className={cn(
                  'grid size-8 shrink-0 place-items-center rounded-full border text-xs font-extrabold tabular-nums',
                  actual && 'border-accent bg-accent text-accent-foreground shadow-sm',
                  completo && 'border-primary bg-primary text-primary-foreground',
                  !actual && !completo && 'border-border bg-card text-muted-foreground',
                )}
              >
                {completo ? <Check className="size-4" /> : paso.numero}
              </span>
              <div className="min-w-0">
                <p className={cn('text-xs font-extrabold', actual && 'text-accent')}>
                  {paso.numero}. {paso.titulo}
                </p>
                <p className="mt-0.5 truncate text-[11px] text-muted-foreground" title={paso.detalle}>
                  {paso.detalle}
                </p>
              </div>
            </li>
          )
        })}
      </ol>
    </Card>
  )
}

function ResumenUltimoReparto({
  resumen,
  onCerrar,
}: {
  resumen: UltimoReparto
  onCerrar: () => void
}): JSX.Element {
  return (
    <div
      role="status"
      aria-live="polite"
      className="mx-5 mb-4 overflow-hidden rounded-xl border border-accent/25 bg-accent/[0.045] shadow-sm"
    >
      <div className="flex items-start gap-3 px-3.5 py-3">
        <span className="grid size-8 shrink-0 place-items-center rounded-full bg-accent text-accent-foreground">
          <CheckCircle2 className="size-4.5" aria-hidden />
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-extrabold text-primary">Reparto guardado</p>
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            {resumen.cantidad} {resumen.cantidad === 1 ? 'lead enviado' : 'leads enviados'}
            {' · '}{moneyK(resumen.pen)}
            {resumen.usd > 0 ? ` + ${moneyK(resumen.usd, 'USD')}` : ''}
          </p>
          <ul aria-label="Resumen del último reparto por asesor" className="mt-2 flex flex-wrap gap-1.5">
            {resumen.grupos.map((grupo) => {
              const color = colorDeAsesor(grupo.asesorId)
              const colorTexto = colorTextoDeAsesor(grupo.asesorId)
              return (
                <li
                  key={grupo.asesorId}
                  className="rounded-full border px-2.5 py-1 text-[11px] font-bold"
                  style={{
                    color: colorTexto,
                    borderColor: `color-mix(in srgb, ${color} 30%, var(--border))`,
                    background: `color-mix(in srgb, ${color} 7%, var(--card))`,
                  }}
                >
                  {grupo.asesorNombre} · {grupo.cantidad} {grupo.cantidad === 1 ? 'lead' : 'leads'}
                </li>
              )
            })}
          </ul>
        </div>
        <button
          type="button"
          aria-label="Cerrar resumen del último reparto"
          onClick={onCerrar}
          className="grid size-8 shrink-0 place-items-center rounded-lg text-muted-foreground transition-colors hover:bg-accent/10 hover:text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/30"
        >
          <X className="size-4" aria-hidden />
        </button>
      </div>
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
  const [busqueda, setBusqueda] = useState('')
  const [pagina, setPagina] = useState(0)
  const asesorPorId = useMemo(
    () => new Map(asesores.map((asesor) => [asesor.perfil_id, asesor])),
    [asesores],
  )
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
  const leadsFiltrados = useMemo(() => {
    const consulta = textoPlano(busqueda.trim())
    if (!consulta) return leads
    return leads.filter((lead) => {
      const asesor = asesorPorId.get(borrador[lead.id] ?? '')
      return textoPlano([
        lead.nombre_completo,
        origenLabel(lead.origen),
        lead.distrito ?? '',
        asesor?.nombre_completo ?? '',
      ].join(' ')).includes(consulta)
    })
  }, [asesorPorId, borrador, busqueda, leads])
  const paginaLeads = paginar(leadsFiltrados, pagina, LEADS_POR_PAGINA)

  if (leads.length === 0) {
    return (
      <p className="px-5 pb-4 text-sm text-muted-foreground">
        No hay leads por repartir — bandeja limpia.
      </p>
    )
  }

  return (
    <div className="px-5 pb-4">
      <div className="mb-3 flex flex-col gap-2.5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-[11px] text-muted-foreground">
            Elige el asesor de cada lead. Puedes cambiarlo o quitarlo antes de guardar el lote.
          </p>
          <p className="mt-0.5 text-[10px] font-semibold text-muted-foreground">
            La asignación se realiza siempre uno por uno.
          </p>
        </div>
        <div className="flex items-center gap-2 sm:w-[310px]">
          <div className="relative min-w-0 flex-1">
            <Search
              aria-hidden
              className="pointer-events-none absolute left-3 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground"
            />
            <input
              type="search"
              value={busqueda}
              aria-label="Buscar leads por repartir"
              placeholder="Buscar lead, origen o distrito"
              onChange={(event) => {
                setBusqueda(event.target.value)
                setPagina(0)
              }}
              className="h-9 w-full rounded-lg border border-input bg-background pl-9 pr-3 text-xs shadow-sm outline-none transition focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/30"
            />
          </div>
          <span className="shrink-0 text-[11px] font-bold tabular-nums text-muted-foreground">
            {leadsFiltrados.length}/{leads.length}
          </span>
        </div>
      </div>
      {bloqueado && (
        <p role="status" className="mb-3 rounded-lg border border-border bg-muted/35 px-3 py-2 text-xs text-muted-foreground">
          Para derivar, primero carga un reporte válido del equipo.
        </p>
      )}
      {leadsFiltrados.length === 0 ? (
        <div className="rounded-xl border border-dashed border-border bg-muted/15 px-4 py-8 text-center">
          <Search className="mx-auto size-5 text-muted-foreground" aria-hidden />
          <p className="mt-2 text-sm font-bold">No hay leads que coincidan</p>
          <p className="mt-1 text-xs text-muted-foreground">
            Cambia la búsqueda para volver a la bandeja completa.
          </p>
          <Button
            type="button"
            size="sm"
            variant="outline"
            className="mt-3"
            onClick={() => {
              setBusqueda('')
              setPagina(0)
            }}
          >
            Limpiar búsqueda
          </Button>
        </div>
      ) : (
        <div className="space-y-2">
          {paginaLeads.visibles.map((lead) => {
            const dias = diasDesdeReferencia(lead.creado_en, ahora)
            const asesorId = borrador[lead.id] ?? ''
            const elegido = asesorId !== ''
            const asesorElegido = asesorPorId.get(asesorId)
            const color = elegido ? colorDeAsesor(asesorId) : null
            const colorTexto = elegido ? colorTextoDeAsesor(asesorId) : null
            return (
              <div
                key={lead.id}
                className="relative flex flex-col gap-2.5 overflow-hidden rounded-xl border border-border p-3 transition-colors sm:flex-row sm:items-center"
                style={color ? {
                  borderColor: `color-mix(in srgb, ${color} 34%, var(--border))`,
                  background: `color-mix(in srgb, ${color} 4.5%, var(--card))`,
                } : undefined}
              >
                {color && (
                  <span
                    aria-hidden
                    className="absolute inset-y-0 left-0 w-1"
                    style={{ background: color }}
                  />
                )}
                <div className={cn('min-w-0 flex-1', elegido && 'pl-1')}>
                  <div className="flex min-w-0 flex-wrap items-center gap-1.5">
                    <p className="min-w-0 truncate text-sm font-semibold">{lead.nombre_completo}</p>
                    {asesorElegido && color && colorTexto && (
                      <span
                        className="inline-flex shrink-0 items-center gap-1 rounded-full border px-2 py-0.5 text-[10px] font-bold"
                        style={{
                          color: colorTexto,
                          borderColor: `color-mix(in srgb, ${color} 30%, var(--border))`,
                          background: `color-mix(in srgb, ${color} 8%, var(--card))`,
                        }}
                      >
                        <span className="size-1.5 rounded-full" style={{ background: color }} aria-hidden />
                        → {asesorElegido.nombre_completo}
                      </span>
                    )}
                  </div>
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
                <div className="flex min-w-0 items-center gap-2 sm:w-[300px] sm:shrink-0">
                  <div className="min-w-0 flex-1">
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
                  </div>
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
          {paginaLeads.paginas > 1 && (
            <div className="border-t border-border pt-3">
              <Paginacion
                paginaActual={paginaLeads.paginaActual}
                paginas={paginaLeads.paginas}
                total={leadsFiltrados.length}
                onCambio={setPagina}
                ariaLabel="Paginación de leads por repartir"
              />
            </div>
          )}
        </div>
      )}

      <div className="sticky bottom-3 z-20 mt-3 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-accent/25 bg-card/95 px-3 py-2.5 shadow-[var(--shadow-pop)] backdrop-blur">
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
        <div className="grid w-full grid-cols-1 gap-2 sm:flex sm:w-auto sm:items-center">
          <Button
            type="button"
            size="sm"
            variant="ghost"
            className="w-full sm:w-auto"
            disabled={guardando || resumen.cantidad === 0}
            onClick={onDescartar}
          >
            Descartar borrador
          </Button>
          <Button
            type="button"
            size="sm"
            className="w-full sm:w-auto"
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
  const grupos = useMemo(() => {
    const porAsesor = new Map<string, {
      asesorId: string
      asesorNombre: string
      movimientos: MovimientoDerivacionHoy[]
      pen: number
      usd: number
      reversibles: number
    }>()
    for (const movimiento of movimientos) {
      const grupo = porAsesor.get(movimiento.asesor_id) ?? {
        asesorId: movimiento.asesor_id,
        asesorNombre: movimiento.asesor_nombre,
        movimientos: [],
        pen: 0,
        usd: 0,
        reversibles: 0,
      }
      grupo.movimientos.push(movimiento)
      if (movimiento.moneda === 'USD') grupo.usd += movimiento.monto_estimado ?? 0
      else grupo.pen += movimiento.monto_estimado ?? 0
      if (movimiento.reversible) grupo.reversibles += 1
      porAsesor.set(movimiento.asesor_id, grupo)
    }
    return [...porAsesor.values()].sort((a, b) =>
      a.asesorNombre.localeCompare(b.asesorNombre, 'es-PE'))
  }, [movimientos])
  const [abiertoId, setAbiertoId] = useState<string | null>(movimientos[0]?.asesor_id ?? null)
  const [paginas, setPaginas] = useState<Record<string, number>>({})

  useEffect(() => {
    if (grupos.length === 0) {
      setAbiertoId(null)
      return
    }
    if (abiertoId != null && !grupos.some((grupo) => grupo.asesorId === abiertoId)) {
      setAbiertoId(grupos[0]?.asesorId ?? null)
    }
  }, [abiertoId, grupos])

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
        Abre un asesor para revisar sus leads. Puedes devolverlos mientras no tengan gestión.
      </p>
      <ul
        aria-label="Derivaciones guardadas hoy"
        className="mt-3 space-y-2.5"
      >
        {grupos.map((grupo) => {
          const abierto = abiertoId === grupo.asesorId
          const color = colorDeAsesor(grupo.asesorId)
          const colorTexto = colorTextoDeAsesor(grupo.asesorId)
          const paginaGrupo = paginar(
            grupo.movimientos,
            paginas[grupo.asesorId] ?? 0,
            GUARDADAS_POR_PAGINA,
          )
          const contenidoId = `derivaciones-asesor-${grupo.asesorId}`
          return (
            <li
              key={grupo.asesorId}
              className="overflow-hidden rounded-xl border border-border bg-card"
              style={abierto ? {
                borderColor: `color-mix(in srgb, ${color} 28%, var(--border))`,
              } : undefined}
            >
              <button
                type="button"
                aria-expanded={abierto}
                aria-controls={contenidoId}
                onClick={() => setAbiertoId((actual) => actual === grupo.asesorId ? null : grupo.asesorId)}
                className="flex w-full items-center gap-2.5 px-3 py-3 text-left transition-colors hover:bg-muted/35 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-inset focus-visible:ring-ring/30"
              >
                <Avatar
                  nombre={grupo.asesorNombre}
                  color={colorTexto}
                  className="size-8 text-[10px]"
                />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-bold">{grupo.asesorNombre}</p>
                  <p className="truncate text-[11px] text-muted-foreground">
                    {grupo.movimientos.length} {grupo.movimientos.length === 1 ? 'lead' : 'leads'}
                    {' · '}{moneyK(grupo.pen)}
                    {grupo.usd > 0 ? ` + ${moneyK(grupo.usd, 'USD')}` : ''}
                  </p>
                </div>
                <Badge
                  color={grupo.reversibles > 0 ? SEMAFORO.atencion : SEMAFORO.ok}
                  variant="outline"
                >
                  {grupo.reversibles > 0
                    ? `${grupo.reversibles} ${grupo.reversibles === 1 ? 'reversible' : 'reversibles'}`
                    : 'Gestionados'}
                </Badge>
                <ChevronDown
                  aria-hidden
                  className={cn('size-4 shrink-0 text-muted-foreground transition-transform', abierto && 'rotate-180')}
                />
              </button>

              {abierto && (
                <div id={contenidoId} className="border-t border-border bg-muted/[0.12] px-3 py-3">
                  <ul
                    aria-label={`Leads derivados a ${grupo.asesorNombre}`}
                    className="space-y-2"
                  >
                    {paginaGrupo.visibles.map((movimiento) => (
                      <li
                        key={`${movimiento.lead_id}-${movimiento.derivado_en}`}
                        className="flex flex-col gap-2 rounded-lg border border-border bg-card p-2.5 sm:flex-row sm:items-center"
                      >
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-xs font-semibold">{movimiento.nombre_completo}</p>
                          <p className="truncate text-[10.5px] text-muted-foreground">
                            {movimiento.monto_estimado != null
                              ? moneyK(movimiento.monto_estimado, movimiento.moneda)
                              : 'Sin monto'}
                            {' · '}
                            {movimiento.reversible ? 'Aún puede volver a la bandeja' : 'El asesor ya registró gestión'}
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
                  {paginaGrupo.paginas > 1 && (
                    <div className="mt-3 border-t border-border pt-3">
                      <Paginacion
                        paginaActual={paginaGrupo.paginaActual}
                        paginas={paginaGrupo.paginas}
                        total={grupo.movimientos.length}
                        onCambio={(pagina) => setPaginas((actual) => ({
                          ...actual,
                          [grupo.asesorId]: pagina,
                        }))}
                        ariaLabel={`Paginación de derivaciones de ${grupo.asesorNombre}`}
                      />
                    </div>
                  )}
                </div>
              )}
            </li>
          )
        })}
      </ul>
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
  const [ultimoReparto, setUltimoReparto] = useState<UltimoReparto | null>(null)
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
    setUltimoReparto(null)
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
    const resumenGuardado = resumirReparto(borrador, leadsPorRepartir, ambito.vendedores)
    try {
      const resultado = await derivar.mutateAsync(derivaciones)
      setBorrador({})
      setUltimoReparto(resumenGuardado)
      toast.success(
        `${resultado.derivados} ${resultado.derivados === 1 ? 'lead derivado' : 'leads derivados'} a tu equipo`,
      )
      try {
        await recargar()
      } catch {
        toast.warning('El reparto fue guardado, pero la pantalla no pudo actualizarse. Recarga para ver los cambios.')
      }
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
  const reporteListo = yo?.demo !== true && rangoValido && reporte.data != null && !reporte.error
  const reversiblesHoy = reporte.data?.movimientos_hoy.filter((movimiento) => movimiento.reversible).length ?? 0
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

      <RutaReparto
        reporteListo={reporteListo}
        asesores={reporte.data?.asesores.length ?? 0}
        porRepartir={leadsPorRepartir.length}
        enBorrador={totalBorrador}
        guardadasHoy={reporte.data?.movimientos_hoy.length ?? 0}
        ultimoReparto={ultimoReparto}
      />

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

      <div className="grid grid-cols-1 items-start gap-5 lg:grid-cols-[minmax(0,1.15fr)_minmax(360px,0.85fr)]">
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
            right={reversiblesHoy > 0 ? (
              <Badge color={SEMAFORO.atencion} variant="outline" dot>
                {reversiblesHoy} {reversiblesHoy === 1 ? 'puede volver' : 'pueden volver'}
              </Badge>
            ) : undefined}
          />
          {ultimoReparto && (
            <ResumenUltimoReparto
              resumen={ultimoReparto}
              onCerrar={() => setUltimoReparto(null)}
            />
          )}
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
