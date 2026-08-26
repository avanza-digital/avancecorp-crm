// screens/mi-cartera.tsx — la pantalla ÚNICA que fusiona Clientes + Contratos
// del vendedor (decisión de Miguel 2026-07-20). Cada CLIENTE es un grupo que se
// expande y sus CONTRATOS cuelgan como sub-filas; la columna protagonista es el
// CAPITAL EN JUEGO por cliente (suma de sus contratos activos, PEN y USD por
// separado — jamás mezclados). Rótulo por rol: "Mi cartera" para el vendedor,
// "Cartera" para quien supervisa. Cruza CLIENT-SIDE las dos vistas hermanas que
// el servidor ya scopeó por rol (crm.clientes_basicos + crm.contratos_cartera)
// vía el helper puro agruparCartera — CERO backend nuevo.
//
// Las ACCIONES reusan íntegramente los diálogos que ya usan Clientes y Contratos
// (ClienteForm, ContratoNuevo, ContratoDetalle, ContratoCorregir): alta de
// cliente + contrato encadenado, corregir cliente/contrato dentro de la ventana
// de 5 h (la RLS del servidor es la autoridad; aquí el reloj es cortesía) y ver
// el detalle con cronograma. Fuerza de ventas conserva el gate por fila y la
// ventana de 5 h; Gerencia opera el ámbito completo, como revalida el servidor.
import { useCallback, useEffect, useMemo, useRef, useState, type Ref } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import {
  AlarmClock,
  CalendarPlus,
  ChevronRight,
  Coins,
  FileStack,
  Inbox,
  RefreshCw,
  Search,
  TrendingUp,
  UserX,
  Users2,
  Wallet,
} from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Dialog } from '@/components/ui/dialog'
import { Sheet } from '@/components/ui/sheet'
import { Badge } from '@/components/ui/badge'
import { SectionHead } from '@/components/common/section-head'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Paginacion } from '@/components/common/paginacion'
import { StatStrip, type StatChipData } from '@/components/common/stat-strip'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import { ClienteForm } from '@/components/app/cliente-form'
import { ClienteFicha, type FocoInicialClienteFicha } from '@/components/app/cliente-ficha'
import { ClienteGestion } from '@/components/app/cliente-gestion'
import { ContratoNuevo, type ContratoCreadoLocal } from '@/components/app/contrato-nuevo'
import { ContratoDetalle } from '@/components/app/contrato-detalle'
import { ContratoCorregir } from '@/components/app/contrato-corregir'
import { SeccionEnCooperativas } from '@/components/app/cierres-externos-seccion'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { can, puedeEliminarContratos, puedeEscribir } from '@/lib/roles'
import { money, moneyK, primerNombre } from '@/lib/format'
import { useVentana } from '@/lib/ventana'
import { useEsMovil } from '@/lib/media'
import {
  DIAS_ALARMA_RENOVACION,
  agruparCartera,
  idsPorVencer,
  resumenCartera,
  type GrupoCartera,
} from '@/lib/cartera-vista'
import {
  CLAVE_SIN_CONTRATOS,
  MES_TODOS,
  agruparPorMes,
  etiquetaDeMes,
  mesLima,
  ordenDeBloque,
} from '@/lib/cartera-meses'
import { carteraDelAmbito, normalizar, type FiltroAsesor } from '@/lib/clientes-vista'
import { type FiltroEstado } from '@/lib/contratos-vista'
import { CATEGORIA_LABEL, ESTADO_COLOR, ESTADO_CONTRATO_LABEL } from '@/lib/contratos-catalogo'
import { paginar } from '@/lib/paginacion'
import type { ContratoPdfDatos } from '@/lib/contrato-pdf'
import { eliminarContratoConPdf } from '@/lib/contrato-pdf-archivo'
import { mensajeDeError } from '@/data/crm-api'
import {
  INTERVALO_REVALIDACION_CARTERA_MS,
  crmQueryKeys,
  useClientes,
  useContratos,
  useOperacionesCartera,
} from '@/data/crm-queries'
import { fechaLima } from '@/lib/agenda-derivada'
import { useAhora } from '@/lib/ahora'
import { resolverContextoFichaCliente, type ContextoFichaCliente } from '@/lib/cliente-ficha-modelo'
import type {
  ClienteBasico,
  ClienteDetalle as ClienteDetalleDatos,
  ContratoRow,
  CuentaBancariaSeleccionable,
  Cuota,
  OperacionCartera,
  Titular,
} from '@/lib/clientes-tipos'

/**
 * Umbral de aviso de la ventana de corrección: con menos de 30 min vivos el
 * countdown pasa a ámbar. La ventana vencida se pinta en muted, no en rojo
 * (mismo criterio que FilaCliente/FilaContrato: cerrada es estado normal).
 */
const AVISO_VENTANA_MS = 30 * 60_000

/** Fecha corta es-PE de un YYYY-MM-DD (vencimiento) sin deriva de zona. */
function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number)
  if (!y || !m || !d) return '—'
  return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString('es-PE', {
    day: '2-digit',
    month: 'short',
    year: '2-digit',
    timeZone: 'UTC',
  })
}

/** Identidad del cliente (nombre + documento/teléfono). Compartida por la fila
 *  de la tabla (desktop) y la tarjeta (móvil) → una sola fuente de formato. */
function IdentidadCliente({ cliente }: { cliente: ClienteBasico }) {
  // <span> con display block (no <div>/<p>): así es contenido PHRASING válido
  // dentro de un <button> Y su texto forma parte del nombre accesible del botón.
  return (
    <span className="block min-w-0">
      <span className="flex items-center gap-1.5">
        <span
          className="min-w-0 max-w-[260px] truncate text-[13px] font-semibold text-foreground"
          title={cliente.nombre_completo}
        >
          {cliente.nombre_completo || '—'}
        </span>
        {/* Cliente DADO DE BAJA en el portal (perfiles.activo=false). Se marca
            aquí —dentro de la identidad compartida— para que la tabla y la
            tarjeta móvil no puedan divergir, y el texto del Badge entra en el
            nombre accesible del botón: un lector de pantalla anuncia
            "…INACTIVO" junto al nombre, no solo un color. */}
        {!cliente.activo && (
          <Badge
            color="var(--muted-foreground)"
            className="shrink-0"
            title="Dado de baja en el portal — no cuenta en los totales de capital (sus vencimientos sí avisan)"
          >
            inactivo
          </Badge>
        )}
      </span>
      <span className="block text-[11px] tabular-nums text-muted-foreground">
        {cliente.dni
          ? `${cliente.tipo_documento !== 'DNI' ? cliente.tipo_documento + ' ' : ''}${cliente.dni}`
          : 'sin documento'}
        {cliente.telefono ? ` · ${cliente.telefono}` : ''}
      </span>
    </span>
  )
}

/**
 * Capital vigente por cliente. PEN y USD JAMÁS se suman: van como DOS cifras,
 * ambas con peso propio. Si SOLO hay dólares, el USD es la cifra principal (nunca
 * un "S/ 0" grande con el capital real escondido). Regla congelada de Miguel,
 * en un solo lugar para que la tabla y la tarjeta no puedan divergir.
 */
function CapitalInvertido({
  grupo,
  sinContratos,
  alinear = 'end',
}: {
  grupo: GrupoCartera
  sinContratos: boolean
  alinear?: 'end' | 'start'
}) {
  if (!grupo.tieneCapital) {
    return (
      <span className="text-xs text-muted-foreground">
        {sinContratos ? 'Sin inversión registrada' : 'Sin capital vigente'}
      </span>
    )
  }
  return (
    <div className={`flex flex-col leading-tight ${alinear === 'end' ? 'items-end' : 'items-start'}`}>
      {grupo.capitalActivoPen > 0 && (
        <span className="text-sm font-extrabold tabular-nums text-foreground">
          {money(grupo.capitalActivoPen, 'PEN')}
        </span>
      )}
      {grupo.capitalActivoUsd > 0 && (
        <span
          className={
            grupo.capitalActivoPen > 0
              ? 'text-[13px] font-bold tabular-nums text-foreground/90'
              : 'text-sm font-extrabold tabular-nums text-foreground'
          }
        >
          {money(grupo.capitalActivoUsd, 'USD')}
        </span>
      )}
    </div>
  )
}

/** Desglose económico y efecto de conversión de una renovación/aumento. Es el
 * mismo bloque en desktop y móvil, por lo que asesor, supervisor y Gerencia ven
 * exactamente las mismas cifras. El adicional nunca se presenta como otra
 * conversión. */
function DetalleOperacionCapital({
  contrato,
  operacion,
  contratoOrigen,
}: {
  contrato: ContratoRow
  operacion: OperacionCartera | null
  contratoOrigen: ContratoRow | null
}) {
  if (!operacion) return null

  if (operacion.tipo === 'upgrade') {
    return (
      <span className="mt-1 block text-[10px] font-semibold text-muted-foreground">
        Aumento de inversión ·{' '}
        {operacion.elegible_conversion
          ? 'cuenta como conversión de este mes'
          : 'ya fue contado en el mes de la inversión inicial'}
      </span>
    )
  }

  if (!operacion.desglose_completo || operacion.capital_renovado == null || operacion.capital_adicional == null) {
    return (
      <span className="mt-1 block text-[10px] font-semibold text-warning-text">
        Renovación anterior · detalle no disponible
      </span>
    )
  }

  return (
    <span className="mt-1 block text-[10px] leading-snug text-muted-foreground">
      <span className="block">
        {contratoOrigen && (
          <>
            <span className="font-semibold text-foreground/80">
              {money(contratoOrigen.capital, contratoOrigen.moneda)} anterior
            </span>{' '}
            →{' '}
          </>
        )}
        <span className="font-semibold text-foreground/80">
          {money(operacion.capital_renovado, operacion.moneda)} renovado
        </span>{' '}
        +{' '}
        <span className="font-semibold text-primary">
          {money(operacion.capital_adicional, operacion.moneda)} adicional
        </span>{' '}
        = {money(contrato.capital, contrato.moneda)}
      </span>
      <span className="block">Cuenta como 1 conversión. El capital adicional no suma otra conversión.</span>
    </span>
  )
}

/** Props del grupo-cliente, idénticas en la fila (tabla) y la tarjeta (móvil). */
interface PropsFilaGrupo {
  grupo: GrupoCartera
  expandido: boolean
  onToggle: () => void
  colAsesor: boolean
  /** La vista pinta la columna/zona de acciones porque el rol puede escribir. */
  conAcciones: boolean
  /** Puede consultar la ficha porque la fila pertenece a su ámbito visible. */
  consultable: boolean
  /** Puede escribir Y la fila es propia/global: habilita la gestión comercial. */
  gestionable: boolean
  /** puede_contratar Y la fila es MÍA (regla de cartera) — habilita reloj y botones. */
  accionable: boolean
  /** Cliente activo con asesor vendedor/supervisor activo: precondición del servidor. */
  operable: boolean
  /** Explicación visible y accesible cuando las mutaciones comerciales están bloqueadas. */
  motivoNoOperable: string | null
  /** Gerencia opera cualquier fila y no hereda la ventana antifraude del analista. */
  edicionGlobal: boolean
  /** Solo el superadmin del Portal puede corregir contratos ya cerrados. */
  puedeCorregirContratoCerrado: boolean
  yoId: string | null
  asesorNombre: string | null
  /** Día calendario vigente en Lima; se actualiza con el reloj compartido. */
  hoyLima: string
  /** Los contratos del grupo que pasan los filtros vivos (estado y/o «por
   *  vencer»); ya recortados por el caller para que la tabla y las tarjetas
   *  pinten EXACTAMENTE lo mismo. */
  contratosVisibles: ContratoRow[]
  /** ids de contratos que vencen en ≤30 d: se marcan «renovar» en su sub-fila. */
  porVencer: ReadonlySet<string>
  operacionesPorContrato: ReadonlyMap<string, OperacionCartera>
  contratosPorId: ReadonlyMap<string, ContratoRow>
  onNuevoContrato: () => void
  onGestionarCliente: () => void
  onUpgradeCliente: () => void
  onRenovarContrato: (k: ContratoRow) => void
  onDetalleCliente: () => void
  onCorregirCliente: () => void
  onDetalleContrato: (k: ContratoRow) => void
  onCorregirContrato: (k: ContratoRow) => void
}

/** Sub-fila de un contrato: la fila entera abre el detalle (Enter/Espacio con el
 *  foco en la fila); "Corregir" solo en lo MÍO con la ventana viva. */
function FilaContratoSub({
  contrato: k,
  colAsesor,
  conAcciones,
  corregible,
  sinLimiteVentana,
  porVencer,
  renovacionDisponible,
  renovable,
  operacion,
  contratoOrigen,
  onDetalle,
  onCorregir,
  onRenovar,
}: {
  contrato: ContratoRow
  colAsesor: boolean
  conAcciones: boolean
  /** Contrato propio del analista o cualquier contrato para Gerencia. */
  corregible: boolean
  sinLimiteVentana: boolean
  /** Vence en ≤30 d: la fecha se marca con PALABRA («renovar») además de color
   *  — el color solo no es información accesible. */
  porVencer: boolean
  /** La fecha de renovación ya llegó: se diferencia de una oportunidad futura. */
  renovacionDisponible: boolean
  renovable: boolean
  operacion: OperacionCartera | null
  contratoOrigen: ContratoRow | null
  onDetalle: () => void
  onCorregir: () => void
  onRenovar: () => void
}) {
  const ventana = useVentana(corregible && !sinLimiteVentana ? k.creado_en : null)
  const avisoRenovacion = renovacionDisponible ? 'Disponible para renovar' : porVencer ? 'Renovación próxima' : null
  // Ojo con la clase de foco de la <tr>: el outline NATIVO no se quita. El
  // cambio de fondo que antes lo "reemplazaba" (bg-muted/20 → bg-muted/50) da
  // 1.03:1 de contraste —invisible— y encima es idéntico al hover; y en una fila
  // de tabla el ring de Tailwind (box-shadow) es poco fiable con border-collapse.
  // Así que el foco lo marca el navegador y el fondo queda solo como refuerzo.
  return (
    <tr
      tabIndex={0}
      aria-label={`Abrir detalle del contrato ${k.numero_contrato}`}
      onClick={onDetalle}
      onKeyDown={(ev) => {
        // Solo con el foco en la FILA misma (no cuando burbujea desde un botón).
        if (ev.target !== ev.currentTarget) return
        if (ev.key === 'Enter' || ev.key === ' ') {
          ev.preventDefault()
          onDetalle()
        }
      }}
      className="group cursor-pointer border-b border-border/40 bg-muted/20 transition-colors last:border-0 hover:bg-muted/50 focus-visible:bg-muted/50"
    >
      <Td>
        <div className="flex items-center gap-2 pl-7">
          <span className="font-mono text-xs font-semibold text-foreground">{k.numero_contrato}</span>
          {k.categoria && (
            <span className="rounded-full bg-muted px-2 py-0.5 text-[10px] font-medium text-muted-foreground">
              {CATEGORIA_LABEL[k.categoria]}
            </span>
          )}
        </div>
      </Td>
      <Td className="text-center">
        <Badge color={ESTADO_COLOR[k.estado]} dot>
          {ESTADO_CONTRATO_LABEL[k.estado]}
        </Badge>
      </Td>
      {colAsesor && <Td className="hidden md:table-cell" />}
      <Td className="text-right tabular-nums">
        <span className="text-[13px] font-semibold text-foreground">{money(k.capital, k.moneda)}</span>
        {/* `text-warning-text` (ámbar oscuro), NO `text-warning`: a 11 px esto es
            texto pequeño y el ámbar puro da ~3:1 → falla WCAG 4.5:1 (ver index.css). */}
        <span
          className={`block text-[11px] ${avisoRenovacion ? 'font-semibold text-warning-text' : 'text-muted-foreground'}`}
        >
          Vencimiento: {fechaCorta(k.fecha_vencimiento)}
          {avisoRenovacion && ` · ${avisoRenovacion}`}
        </span>
        <DetalleOperacionCapital contrato={k} operacion={operacion} contratoOrigen={contratoOrigen} />
      </Td>
      {conAcciones && (
        <Td className="text-right">
          <div className="flex flex-wrap items-center justify-end gap-1.5">
            {renovable && (
              <Button
                type="button"
                size="xs"
                onClick={(e) => {
                  e.stopPropagation()
                  onRenovar()
                }}
              >
                <RefreshCw aria-hidden /> Renovar inversión
              </Button>
            )}
            {corregible && (sinLimiteVentana || ventana.vigente) ? (
              <Button
                type="button"
                size="xs"
                variant="outline"
                onClick={(e) => {
                  e.stopPropagation()
                  onCorregir()
                }}
              >
                Corregir
              </Button>
            ) : corregible ? (
              <span className="text-[11px] text-muted-foreground" title="La ventana de corrección de 5 horas ya venció">
                {ventana.texto}
              </span>
            ) : !renovable ? (
              <span className="text-xs text-muted-foreground">—</span>
            ) : null}
          </div>
        </Td>
      )}
    </tr>
  )
}

/** Fila del cliente (grupo) + sus sub-filas de contrato cuando está expandido. */
function FilaGrupoCliente({
  grupo,
  expandido,
  onToggle,
  colAsesor,
  conAcciones,
  consultable,
  gestionable,
  accionable,
  operable,
  motivoNoOperable,
  edicionGlobal,
  puedeCorregirContratoCerrado,
  yoId,
  asesorNombre,
  hoyLima,
  contratosVisibles,
  porVencer,
  operacionesPorContrato,
  contratosPorId,
  onNuevoContrato,
  onGestionarCliente,
  onUpgradeCliente,
  onRenovarContrato,
  onDetalleCliente,
  onCorregirCliente,
  onDetalleContrato,
  onCorregirContrato,
}: PropsFilaGrupo) {
  const { cliente } = grupo
  const sinContratos = grupo.contratos.length === 0
  // El analista conserva su ventana; Gerencia puede corregir cualquier cliente.
  const ventanaCliente = useVentana(accionable && !edicionGlobal ? cliente.creado_en : null)
  const motivoId = `cartera-no-operable-${cliente.id}`
  const ident = <IdentidadCliente cliente={cliente} />
  return (
    <>
      <tr
        className={`border-b border-border/60 transition-colors last:border-0 ${sinContratos ? '' : 'cursor-pointer hover:bg-muted/40'}`}
        onClick={sinContratos ? undefined : onToggle}
      >
        <Td>
          {sinContratos ? (
            <div className="flex items-center gap-2">
              <span aria-hidden className="invisible size-4 shrink-0" />
              {ident}
            </div>
          ) : (
            // El toggle es un <button> REAL: operable con Enter/Espacio y
            // anunciado por lectores vía aria-expanded. stopPropagation evita el
            // doble toggle con el onClick de cortesía de la fila (comodidad de ratón).
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation()
                onToggle()
              }}
              aria-expanded={expandido}
              className="flex w-full items-center gap-2 rounded-sm text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
            >
              {/* La ACCIÓN va en sr-only; el nombre + documento/teléfono visibles
                  forman el resto del nombre accesible (un aria-label los pisaría). */}
              <span className="sr-only">{expandido ? 'Colapsar' : 'Expandir'} los contratos de </span>
              <ChevronRight
                aria-hidden
                className={`size-4 shrink-0 text-muted-foreground transition-transform ${expandido ? 'rotate-90 text-accent' : ''}`}
              />
              {ident}
            </button>
          )}
        </Td>
        <Td className="text-center">
          {sinContratos ? (
            <span className="rounded-full bg-muted px-2 py-0.5 text-[10px] font-medium text-muted-foreground">
              Sin contratos
            </span>
          ) : (
            <span className="text-xs text-muted-foreground">
              {grupo.contratosActivos > 0
                ? `${grupo.contratosActivos} contrato${grupo.contratosActivos > 1 ? 's' : ''} vigente${grupo.contratosActivos > 1 ? 's' : ''}`
                : 'Sin contratos vigentes'}
            </span>
          )}
        </Td>
        {colAsesor && (
          <Td className="hidden md:table-cell">
            {asesorNombre ? (
              <span className="text-xs text-muted-foreground" title={asesorNombre}>
                <span aria-hidden>{primerNombre(asesorNombre)}</span>
                <span className="sr-only">{asesorNombre}</span>
              </span>
            ) : (
              <span className="text-xs text-muted-foreground">—</span>
            )}
          </Td>
        )}
        <Td className="text-right tabular-nums">
          <CapitalInvertido grupo={grupo} sinContratos={sinContratos} />
        </Td>
        {conAcciones && (
          <Td className="text-right">
            {consultable ? (
              <div className="flex flex-wrap items-center justify-end gap-1.5">
                {!operable && motivoNoOperable && (
                  <span id={motivoId} className="max-w-48 text-right text-[11px] leading-tight text-muted-foreground">
                    {motivoNoOperable}
                  </span>
                )}
                <Button
                  type="button"
                  size="xs"
                  variant="outline"
                  onClick={(e) => {
                    e.stopPropagation()
                    onDetalleCliente()
                  }}
                >
                  Ver ficha
                </Button>
                {gestionable && (
                  <Button
                    type="button"
                    size="xs"
                    variant="secondary"
                    disabled={!operable}
                    aria-describedby={!operable ? motivoId : undefined}
                    onClick={(e) => {
                      e.stopPropagation()
                      onGestionarCliente()
                    }}
                  >
                    <CalendarPlus aria-hidden /> Ver seguimiento
                  </Button>
                )}
                {accionable && (
                  <>
                    {(edicionGlobal || ventanaCliente.vigente) && (
                      <Button
                        type="button"
                        size="xs"
                        variant="outline"
                        className={!edicionGlobal && ventanaCliente.ms <= AVISO_VENTANA_MS ? 'text-warning' : undefined}
                        title={
                          edicionGlobal
                            ? 'Corregir datos del cliente · Disponible para Gerencia'
                            : `Corregir datos del cliente · ${ventanaCliente.texto}`
                        }
                        disabled={!operable}
                        aria-describedby={!operable ? motivoId : undefined}
                        onClick={(e) => {
                          e.stopPropagation()
                          onCorregirCliente()
                        }}
                      >
                        Corregir datos
                      </Button>
                    )}
                    {!sinContratos && (
                      <Button
                        type="button"
                        size="xs"
                        variant="outline"
                        disabled={!operable}
                        aria-describedby={!operable ? motivoId : undefined}
                        onClick={(e) => {
                          e.stopPropagation()
                          onUpgradeCliente()
                        }}
                      >
                        <TrendingUp aria-hidden /> Aumentar inversión
                      </Button>
                    )}
                    <Button
                      type="button"
                      size="xs"
                      disabled={!operable}
                      aria-describedby={!operable ? motivoId : undefined}
                      onClick={(e) => {
                        e.stopPropagation()
                        onNuevoContrato()
                      }}
                    >
                      {sinContratos ? 'Registrar primera inversión' : 'Registrar nueva inversión'}
                    </Button>
                  </>
                )}
              </div>
            ) : (
              <span className="text-xs text-muted-foreground">—</span>
            )}
          </Td>
        )}
      </tr>
      {expandido &&
        !sinContratos &&
        contratosVisibles.map((c) => (
          <FilaContratoSub
            key={c.id}
            contrato={c}
            colAsesor={colAsesor}
            conAcciones={accionable}
            corregible={
              operable &&
              (puedeCorregirContratoCerrado || (c.estado !== 'renovado' && c.estado !== 'retirado')) &&
              (edicionGlobal || (c.creado_por != null && c.creado_por === yoId))
            }
            sinLimiteVentana={edicionGlobal}
            porVencer={porVencer.has(c.id)}
            renovacionDisponible={(c.estado === 'activo' || c.estado === 'vencido') && c.fecha_vencimiento <= hoyLima}
            renovable={
              accionable &&
              operable &&
              (c.estado === 'activo' || c.estado === 'vencido') &&
              c.fecha_vencimiento <= hoyLima
            }
            operacion={operacionesPorContrato.get(c.id) ?? null}
            contratoOrigen={
              operacionesPorContrato.get(c.id)?.contrato_origen_id
                ? (contratosPorId.get(operacionesPorContrato.get(c.id)!.contrato_origen_id!) ?? null)
                : null
            }
            onDetalle={() => onDetalleContrato(c)}
            onCorregir={() => onCorregirContrato(c)}
            onRenovar={() => onRenovarContrato(c)}
          />
        ))}
    </>
  )
}

// ————————————————————————————————————————————————————————————————————————
// VISTA MÓVIL (< 768 px): la misma cartera como card-stack. La fuerza de ventas
// vende en el celular, así que el teléfono NO scrollea una tabla de 5 columnas.
// Mismo gating por fila que la tabla (props idénticas, PropsFilaGrupo); solo
// cambia la presentación. Se monta EN LUGAR de la tabla (no a la vez) → los
// intervalos de useVentana no se duplican.
// ————————————————————————————————————————————————————————————————————————

/** Sub-tarjeta de un contrato: toda la tarjeta abre el detalle (Enter/Espacio);
 *  "Corregir" solo en lo MÍO con la ventana viva. Objetivo táctil generoso. */
function TarjetaContratoSub({
  contrato: k,
  conAcciones,
  corregible,
  sinLimiteVentana,
  porVencer,
  renovacionDisponible,
  renovable,
  operacion,
  contratoOrigen,
  onDetalle,
  onCorregir,
  onRenovar,
}: {
  contrato: ContratoRow
  conAcciones: boolean
  corregible: boolean
  sinLimiteVentana: boolean
  /** Vence en ≤30 d — misma marca con PALABRA que en la tabla (no solo color). */
  porVencer: boolean
  renovacionDisponible: boolean
  renovable: boolean
  operacion: OperacionCartera | null
  contratoOrigen: ContratoRow | null
  onDetalle: () => void
  onCorregir: () => void
  onRenovar: () => void
}) {
  const ventana = useVentana(corregible && !sinLimiteVentana ? k.creado_en : null)
  const avisoRenovacion = renovacionDisponible ? 'Disponible para renovar' : porVencer ? 'Renovación próxima' : null
  return (
    <div className="flex items-center justify-between gap-2 rounded-lg border border-border/50 bg-muted/20 pr-3 transition-colors focus-within:bg-muted/40">
      {/* El área de info ES el control que abre el detalle: un <button> NATIVO
          (Enter/Espacio gratis, sin role manual) → solo contiene phrasing (<span>).
          Corregir es su HERMANO, nunca anidado: un control focusable por acción. */}
      <button
        type="button"
        onClick={onDetalle}
        className="flex min-w-0 flex-1 items-center justify-between gap-3 rounded-lg px-3 py-2.5 text-left transition-colors hover:bg-muted/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
      >
        {/* Acción en sr-only; el N°, estado, vencimiento y capital visibles forman el nombre. */}
        <span className="sr-only">Abrir detalle del contrato </span>
        <span className="min-w-0">
          <span className="flex flex-wrap items-center gap-x-2 gap-y-1">
            <span className="font-mono text-xs font-semibold text-foreground">{k.numero_contrato}</span>
            <Badge color={ESTADO_COLOR[k.estado]} dot>
              {ESTADO_CONTRATO_LABEL[k.estado]}
            </Badge>
          </span>
          {/* Mismo ámbar OSCURO que en la tabla: a 11 px el `--warning` puro no
              llega a 4.5:1 de contraste. */}
          <span
            className={`mt-0.5 block text-[11px] ${avisoRenovacion ? 'font-semibold text-warning-text' : 'text-muted-foreground'}`}
          >
            {k.categoria ? `${CATEGORIA_LABEL[k.categoria]} · ` : ''}
            Vencimiento: {fechaCorta(k.fecha_vencimiento)}
            {avisoRenovacion && ` · ${avisoRenovacion}`}
          </span>
          <DetalleOperacionCapital contrato={k} operacion={operacion} contratoOrigen={contratoOrigen} />
        </span>
        <span className="shrink-0 text-[13px] font-semibold tabular-nums text-foreground">
          {money(k.capital, k.moneda)}
        </span>
      </button>
      {conAcciones && (renovable || corregible) && (
        <div className="flex shrink-0 flex-col gap-1.5">
          {renovable && (
            <Button type="button" size="xs" onClick={onRenovar}>
              <RefreshCw aria-hidden /> Renovar inversión
            </Button>
          )}
          {corregible &&
            (sinLimiteVentana || ventana.vigente ? (
              <Button type="button" size="xs" variant="outline" onClick={onCorregir}>
                Corregir
              </Button>
            ) : (
              <span
                className="text-center text-[10px] text-muted-foreground"
                title="La ventana de corrección de 5 horas ya venció"
              >
                {ventana.texto}
              </span>
            ))}
        </div>
      )}
    </div>
  )
}

/** Tarjeta del cliente (grupo) + sus sub-tarjetas de contrato al expandir. */
function TarjetaGrupoCliente({
  grupo,
  expandido,
  onToggle,
  colAsesor,
  conAcciones,
  consultable,
  gestionable,
  accionable,
  operable,
  motivoNoOperable,
  edicionGlobal,
  puedeCorregirContratoCerrado,
  yoId,
  asesorNombre,
  hoyLima,
  contratosVisibles,
  porVencer,
  operacionesPorContrato,
  contratosPorId,
  onNuevoContrato,
  onGestionarCliente,
  onUpgradeCliente,
  onRenovarContrato,
  onDetalleCliente,
  onCorregirCliente,
  onDetalleContrato,
  onCorregirContrato,
}: PropsFilaGrupo) {
  const { cliente } = grupo
  const sinContratos = grupo.contratos.length === 0
  const ventanaCliente = useVentana(accionable && !edicionGlobal ? cliente.creado_en : null)
  const motivoId = `cartera-no-operable-${cliente.id}`
  return (
    <div className="overflow-hidden rounded-xl border border-border/60 bg-card">
      {/* Cabecera: identidad (toggle si tiene contratos) + capital invertido. */}
      <div className="flex items-start justify-between gap-3 p-3">
        {sinContratos ? (
          <IdentidadCliente cliente={cliente} />
        ) : (
          <button
            type="button"
            onClick={onToggle}
            aria-expanded={expandido}
            className="flex min-w-0 items-center gap-2 rounded-sm text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
          >
            {/* Acción en sr-only; identidad visible (nombre + doc/teléfono) forma el nombre. */}
            <span className="sr-only">{expandido ? 'Colapsar' : 'Expandir'} los contratos de </span>
            <ChevronRight
              aria-hidden
              className={`size-4 shrink-0 text-muted-foreground transition-transform ${expandido ? 'rotate-90 text-accent' : ''}`}
            />
            <IdentidadCliente cliente={cliente} />
          </button>
        )}
        <div className="shrink-0">
          <CapitalInvertido grupo={grupo} sinContratos={sinContratos} />
        </div>
      </div>

      {/* Meta: contratos activos + asesor (si supervisa). */}
      <div className="flex flex-wrap items-center gap-x-2 gap-y-1 px-3 pb-2 text-[11px] text-muted-foreground">
        {sinContratos ? (
          <span className="rounded-full bg-muted px-2 py-0.5 font-medium">Sin contratos</span>
        ) : (
          <span>
            {grupo.contratosActivos > 0
              ? `${grupo.contratosActivos} contrato${grupo.contratosActivos > 1 ? 's' : ''} vigente${grupo.contratosActivos > 1 ? 's' : ''}`
              : 'Sin contratos vigentes'}
          </span>
        )}
        {colAsesor && asesorNombre && (
          <span title={asesorNombre}>
            · <span aria-hidden>{primerNombre(asesorNombre)}</span>
            <span className="sr-only">{asesorNombre}</span>
          </span>
        )}
      </div>

      {/* Acciones: cartera propia para analistas; ámbito completo para Gerencia. */}
      {conAcciones && consultable && (
        <div className="flex flex-wrap items-center gap-2 px-3 pb-3">
          {!operable && motivoNoOperable && (
            <span id={motivoId} className="basis-full text-xs text-muted-foreground">
              {motivoNoOperable}
            </span>
          )}
          <Button type="button" size="xs" variant="outline" onClick={onDetalleCliente}>
            Ver ficha
          </Button>
          {gestionable && (
            <Button
              type="button"
              size="xs"
              variant="secondary"
              onClick={onGestionarCliente}
              disabled={!operable}
              aria-describedby={!operable ? motivoId : undefined}
            >
              <CalendarPlus aria-hidden /> Ver seguimiento
            </Button>
          )}
          {accionable && (
            <>
              {(edicionGlobal || ventanaCliente.vigente) && (
                <Button
                  type="button"
                  size="xs"
                  variant="outline"
                  className={!edicionGlobal && ventanaCliente.ms <= AVISO_VENTANA_MS ? 'text-warning' : undefined}
                  title={
                    edicionGlobal
                      ? 'Corregir datos del cliente · Disponible para Gerencia'
                      : `Corregir datos del cliente · ${ventanaCliente.texto}`
                  }
                  disabled={!operable}
                  aria-describedby={!operable ? motivoId : undefined}
                  onClick={onCorregirCliente}
                >
                  Corregir datos
                </Button>
              )}
              {!sinContratos && (
                <Button
                  type="button"
                  size="xs"
                  variant="outline"
                  onClick={onUpgradeCliente}
                  disabled={!operable}
                  aria-describedby={!operable ? motivoId : undefined}
                >
                  <TrendingUp aria-hidden /> Aumentar inversión
                </Button>
              )}
              <Button
                type="button"
                size="xs"
                onClick={onNuevoContrato}
                disabled={!operable}
                aria-describedby={!operable ? motivoId : undefined}
              >
                {sinContratos ? 'Registrar primera inversión' : 'Registrar nueva inversión'}
              </Button>
            </>
          )}
        </div>
      )}

      {/* Sub-tarjetas de contrato al expandir. */}
      {expandido && !sinContratos && (
        <div className="space-y-2 border-t border-border/40 bg-muted/10 p-3">
          {contratosVisibles.map((c) => (
            <TarjetaContratoSub
              key={c.id}
              contrato={c}
              conAcciones={accionable}
              corregible={
                operable &&
                (puedeCorregirContratoCerrado || (c.estado !== 'renovado' && c.estado !== 'retirado')) &&
                (edicionGlobal || (c.creado_por != null && c.creado_por === yoId))
              }
              sinLimiteVentana={edicionGlobal}
              porVencer={porVencer.has(c.id)}
              renovacionDisponible={(c.estado === 'activo' || c.estado === 'vencido') && c.fecha_vencimiento <= hoyLima}
              renovable={
                accionable &&
                operable &&
                (c.estado === 'activo' || c.estado === 'vencido') &&
                c.fecha_vencimiento <= hoyLima
              }
              operacion={operacionesPorContrato.get(c.id) ?? null}
              contratoOrigen={
                operacionesPorContrato.get(c.id)?.contrato_origen_id
                  ? (contratosPorId.get(operacionesPorContrato.get(c.id)!.contrato_origen_id!) ?? null)
                  : null
              }
              onDetalle={() => onDetalleContrato(c)}
              onCorregir={() => onCorregirContrato(c)}
              onRenovar={() => onRenovarContrato(c)}
            />
          ))}
        </div>
      )}
    </div>
  )
}

/** Vista compartida por la ruta REAL y la DEMO: rótulo por rol, StatStrip de
 *  capital en juego, buscador (cliente o N° de contrato), filtro por estado y la
 *  cartera partida EN BLOQUES POR MES de cierre, cada uno plegable y con su
 *  propia paginación. En móvil (< 768 px) la tabla se vuelve un card-stack. Los
 *  datos y las acciones vienen del caller — esta capa solo decide QUÉ se ve. */
function VistaMiCartera({
  grupos,
  operaciones,
  desgloseNoDisponible,
  demo,
  error,
  recargaFallida,
  yoId,
  puedeContratar,
  onNuevoCliente,
  onNuevoContrato,
  onGestionarCliente,
  onUpgradeCliente,
  onRenovarContrato,
  onDetalleCliente,
  onCorregirCliente,
  onDetalleContrato,
  onCorregirContrato,
  contenedorRef,
}: {
  /** null = cargando. */
  grupos: GrupoCartera[] | null
  operaciones: OperacionCartera[]
  desgloseNoDisponible: { reintentar: () => void } | null
  demo: boolean
  error: {
    mensaje: string
    reintentando: boolean
    reintentar: () => void
  } | null
  /**
   * Recarga fallida CON datos ya en pantalla. Es un estado distinto de `error`
   * (que solo cubre «no hay nada que mostrar»): TanStack conserva la data previa
   * cuando falla un refetch, así que sin este aviso el asesor seguía viendo su
   * cartera como si estuviera al día. Silencioso = peor que vacío.
   */
  recargaFallida: { reintentar: () => void } | null
  yoId: string | null
  puedeContratar: boolean
  onNuevoCliente: () => void
  onNuevoContrato: (cliente: ClienteBasico) => void
  onGestionarCliente: (contexto: ContextoFichaCliente) => void
  onUpgradeCliente: (cliente: ClienteBasico) => void
  onRenovarContrato: (cliente: ClienteBasico, contrato: ContratoRow) => void
  onDetalleCliente: (contexto: ContextoFichaCliente) => void
  onCorregirCliente: (cliente: ClienteBasico) => void
  onDetalleContrato: (k: ContratoRow) => void
  onCorregirContrato: (k: ContratoRow) => void
  /** Destino de foco cuando una ficha desaparece porque cambió su asignación. */
  contenedorRef?: Ref<HTMLDivElement>
}) {
  const { yo } = useAuth()
  const { equipo } = useCRMData()
  const verEquipo = can(yo?.rol, 'verEquipo')
  const verTodo = can(yo?.rol, 'verTodo')
  const escrituraHabilitada = puedeEscribir(yo?.rol)
  const accionesContractualesHabilitadas = puedeContratar && escrituraHabilitada
  const fichasHabilitadas = can(yo?.rol, 'verCartera')
  const titulo = verTodo ? 'Cartera de la empresa' : verEquipo ? 'Cartera de mi equipo' : 'Mi cartera'
  const esMovil = useEsMovil()
  const ahoraMs = useAhora()
  const hoyLima = fechaLima(ahoraMs)

  const [q, setQ] = useState('')
  const [fEstado, setFEstado] = useState<FiltroEstado>('todos')
  // Filtro por asesor: solo lo usa supervisión (verEquipo). 'todos' | 'sin_asesor' | perfil_id.
  const [fAsesor, setFAsesor] = useState<FiltroAsesor>('todos')
  // Filtro de RENOVACIÓN: deja solo los clientes con un contrato por vencer. Es
  // el aterrizaje del chip «Por vencer ≤30 d» — sin él la alarma no lleva a
  // ninguna fila (el Select filtra por estado de CONTRATO, no por vencimiento).
  const [soloPorVencer, setSoloPorVencer] = useState(false)
  const [expandidos, setExpandidos] = useState<ReadonlySet<string>>(new Set())
  const [pagina, setPagina] = useState(0)
  // Filtro de MES DE CIERRE. Arranca en el mes en curso (decisión de Miguel,
  // 2026-08-14). Si la sesión cruza a un mes nuevo, avanza solo cuando la
  // persona todavía conservaba el mes anterior; una selección manual se respeta.
  const mesActual = mesLima(new Date(ahoraMs).toISOString()) ?? MES_TODOS
  const [fMes, setFMes] = useState<string>(() => mesActual)
  const mesActualAnteriorRef = useRef(mesActual)
  useEffect(() => {
    const anterior = mesActualAnteriorRef.current
    if (anterior === mesActual) return
    setFMes((actual) => (actual === anterior ? mesActual : actual))
    mesActualAnteriorRef.current = mesActual
  }, [mesActual])

  // Roster visible para el filtro 'Sin asesor': importa la asignación explícita,
  // no quién creó la ficha. Así filtro, contador, columna y operabilidad coinciden.
  const rosterIds = useMemo(() => new Set(equipo.map((m) => m.perfil_id)), [equipo])
  const bases = useMemo(() => grupos ?? [], [grupos])
  const contratosPorId = useMemo(
    () => new Map(bases.flatMap((grupo) => grupo.contratos).map((contrato) => [contrato.id, contrato])),
    [bases],
  )
  const operacionesPorContrato = useMemo(
    () => new Map(operaciones.map((operacion) => [operacion.contrato_nuevo_id, operacion])),
    [operaciones],
  )
  // ── Clientes DADOS DE BAJA en el portal (perfiles.activo=false) ────────────
  // Decisión (2026-07-25): se MUESTRAN marcados, pero salen de los TOTALES de
  // dinero. No se excluyen de la lista a propósito: un cliente inactivo puede
  // conservar contratos con capital y cronograma vivos, y esconder la fila
  // haría desaparecer del CRM un documento legal que sigue existiendo — un
  // silencio que nadie puede detectar es peor que el bug que se está
  // corrigiendo (el asesor no podría ni abrir su detalle). Los KPIs de CAPITAL
  // describen la cartera QUE SE GESTIONA: contar ahí a quien ya no es cliente
  // le inflaba al asesor un capital que no puede trabajar.
  // ⚠️ La ALARMA de vencimiento es la EXCEPCIÓN y se calcula sobre `bases`
  // (corrección 2026-07-26): un contrato activo que vence en ≤30 d debe seguir
  // avisando aunque el titular esté dado de baja. La mutación queda bloqueada
  // hasta reactivarlo, pero ocultar el vencimiento lo borraría del radar.
  const enGestion = useMemo(() => bases.filter((g) => g.cliente.activo), [bases])
  const inactivos = bases.length - enGestion.length
  // resumenCartera separa por dentro los dos conceptos: dinero sobre lo
  // gestionable, alarma sobre TODO (+ desglose porVencer30DeBaja).
  const resumen = useMemo(() => resumenCartera(bases, ahoraMs), [bases, ahoraMs])
  // ids de contratos por vencer de TODA la cartera: alimentan el filtro de
  // renovación Y la marca «renovar» de cada sub-fila (una sola fuente).
  const porVencer = useMemo(() => idsPorVencer(bases, ahoraMs), [bases, ahoraMs])
  const contratosActivosTotal = useMemo(() => enGestion.reduce((n, g) => n + g.contratosActivos, 0), [enGestion])
  // Pestillo del toggle «Por vencer»: una vez que hubo algo que renovar, el
  // control se queda montado aunque el conteo baje a 0 (dirá «(0)», que es la
  // verdad). Si se desmontara al apagarlo —el caso real: un refetch renueva el
  // último contrato mientras el filtro está puesto— el botón desaparecería BAJO
  // el foco del usuario y este saltaría a <body>, al inicio del documento.
  const [huboPorVencer, setHuboPorVencer] = useState(false)
  useEffect(() => {
    if (resumen.porVencer30 > 0) setHuboPorVencer(true)
  }, [resumen.porVencer30])

  // Buscador + filtro de estado sobre los GRUPOS. El grupo pasa si el cliente
  // matchea (nombre/doc/correo/teléfono, incl. solo-dígitos) O alguno de sus
  // contratos por N°; y si tiene algún contrato del estado filtrado. Con filtro
  // activo se auto-expanden los grupos para que las sub-filas coincidentes se vean.
  const filtrados = useMemo(() => {
    const nq = normalizar(q.trim())
    const dq = nq.replace(/\D/g, '')
    return bases.filter((g) => {
      // Filtro por asesor (solo supervisión): usa la asignación explícita de la
      // ficha. 'sin_asesor' = asesor null o fuera del roster visible.
      if (verEquipo && fAsesor !== 'todos') {
        const asesorId = g.cliente.asesor_perfil_id
        const asesorVisible = asesorId != null && rosterIds.has(asesorId)
        if (fAsesor === 'sin_asesor') {
          if (asesorVisible) return false
        } else if (asesorId !== fAsesor) {
          return false
        }
      }
      if (fEstado !== 'todos' && !g.contratos.some((c) => c.estado === fEstado)) return false
      // Renovación: el grupo pasa si ALGÚN contrato suyo vence en ≤30 d. Se
      // evalúa sobre `bases` (no sobre `enGestion`) para que el cliente dado de
      // baja con un contrato por vencer sí sea alcanzable desde el chip.
      if (soloPorVencer && !g.contratos.some((c) => porVencer.has(c.id))) return false
      if (!nq) return true
      const c = g.cliente
      if (normalizar(c.nombre_completo).includes(nq)) return true
      if (c.dni != null && normalizar(c.dni).includes(nq)) return true
      if (c.correo != null && normalizar(c.correo).includes(nq)) return true
      if (c.telefono != null) {
        if (normalizar(c.telefono).includes(nq)) return true
        if (dq !== '' && c.telefono.replace(/\D/g, '').includes(dq)) return true
      }
      return g.contratos.some((k) => normalizar(k.numero_contrato).includes(nq))
    })
  }, [bases, q, fEstado, verEquipo, fAsesor, rosterIds, soloPorVencer, porVencer])

  // Al filtrar, auto-expandir los grupos que coinciden POR CONTRATO (para revelar
  // la sub-fila que hizo match), SIN un override global: el usuario puede
  // colapsarlos y el botón "Colapsar" sigue siendo real (aria-expanded refleja el
  // estado verdadero). Solo AÑADE, al cambiar el filtro.
  useEffect(() => {
    const nq = normalizar(q.trim())
    if (nq === '' && fEstado === 'todos' && !soloPorVencer) return
    setExpandidos((prev) => {
      let cambio = false
      const sig = new Set(prev)
      for (const g of bases) {
        const matchContrato =
          (fEstado !== 'todos' && g.contratos.some((c) => c.estado === fEstado)) ||
          // Con el filtro de renovación, el contrato que vence se ve SIN un clic
          // más: la fecha es el dato que el asesor viene a buscar.
          (soloPorVencer && g.contratos.some((c) => porVencer.has(c.id))) ||
          (nq !== '' && g.contratos.some((c) => normalizar(c.numero_contrato).includes(nq)))
        if (matchContrato && !sig.has(g.cliente.id)) {
          sig.add(g.cliente.id)
          cambio = true
        }
      }
      return cambio ? sig : prev
    })
  }, [bases, q, fEstado, soloPorVencer, porVencer])

  const hayFiltro = q.trim() !== '' || fEstado !== 'todos' || fAsesor !== 'todos' || soloPorVencer || fMes !== MES_TODOS

  // ── La cartera repartida por MES DE CIERRE ─────────────────────────────────
  // Los grupos entran con sus contratos YA recortados a los que pasan los otros
  // filtros, para que el resumen del mes cuente exactamente lo que se ve debajo.
  // Un grupo sobrevive al filtro solo si alguno de sus contratos pasa (o si el
  // match fue por el cliente, y entonces se ven todos), así que ningún cliente
  // CON contratos acaba por error en «Clientes sin contrato».
  const meses = useMemo(
    () =>
      agruparPorMes(
        filtrados.map((g) => ({
          ...g,
          contratos: g.contratos.filter(
            (c) => (fEstado === 'todos' || c.estado === fEstado) && (!soloPorVencer || porVencer.has(c.id)),
          ),
        })),
      ),
    [filtrados, fEstado, soloPorVencer, porVencer],
  )

  // Opciones del selector. El MES EN CURSO va SIEMPRE, aunque todavía no tenga
  // ni un cierre: es el valor por defecto, y un `value` que no existe entre las
  // opciones deja el <select> mostrando cualquier cosa. Cuando está vacío, el
  // panel lo dice con todas las letras y ofrece la salida.
  const opcionesMes = useMemo(() => {
    const vistos = new Map(meses.map((m) => [m.clave, m.etiqueta]))
    if (!vistos.has(mesActual) && mesActual !== MES_TODOS) {
      vistos.set(mesActual, etiquetaDeMes(mesActual))
    }
    return [...vistos.entries()]
      .map(([clave, etiqueta]) => ({ clave, etiqueta }))
      .sort((a, b) => ordenDeBloque(a.clave, b.clave))
  }, [meses, mesActual])

  // El bloque elegido: sus grupos son la lista, y sus totales el resumen. Con
  // «todos los meses» no hay bloque y la lista vuelve a ser la cartera entera.
  const bloque = fMes === MES_TODOS ? null : (meses.find((m) => m.clave === fMes) ?? null)
  // Los clientes SIN NINGÚN contrato acompañan siempre al mes elegido, salvo
  // cuando se pide su propio cubo. No son historia de otro mes: son trabajo
  // pendiente, y esta es la pantalla desde la que se les crea el contrato.
  // Dejarlos fuera los volvía inalcanzables salvo por una opción del
  // desplegable que nadie va a buscar — y se llevaba por delante el reparto de
  // «Sin asesor», donde esos clientes son justo los que hay que repartir.
  const sinContratos =
    fMes === CLAVE_SIN_CONTRATOS ? [] : (meses.find((m) => m.clave === CLAVE_SIN_CONTRATOS)?.grupos ?? [])
  const visiblesDelFiltro = fMes === MES_TODOS ? filtrados : [...(bloque?.grupos ?? []), ...sinContratos]
  // El mes es el ÚNICO filtro puesto: entonces un vacío no es «sin resultados»
  // sino «ese mes no tuvo cierres», que es otra cosa y se explica distinto.
  const mesEsElUnicoFiltro =
    fMes !== MES_TODOS && q.trim() === '' && fEstado === 'todos' && fAsesor === 'todos' && !soloPorVencer

  // Al cambiar cualquier filtro se vuelve a la página 1: la lista es otra y una
  // página 3 heredada dejaría la pantalla en blanco.
  useEffect(() => {
    setPagina(0)
  }, [q, fEstado, fAsesor, fMes, soloPorVencer])

  const { visibles, paginas, paginaActual } = paginar(visiblesDelFiltro, pagina)

  // Props del grupo-cliente, idénticas para la fila (tabla) y la tarjeta (móvil):
  // el gating vive AQUÍ (una sola fuente), la presentación decide cómo pintarlo.
  const propsDeGrupo = (g: GrupoCartera): PropsFilaGrupo => {
    const contexto = resolverContextoFichaCliente({
      grupo: g,
      equipo,
      yoId,
      rol: yo?.rol,
      puedeContratar,
    })
    return {
      grupo: g,
      expandido: expandidos.has(g.cliente.id),
      onToggle: () =>
        setExpandidos((prev) => {
          const sig = new Set(prev)
          if (sig.has(g.cliente.id)) sig.delete(g.cliente.id)
          else sig.add(g.cliente.id)
          return sig
        }),
      colAsesor: verEquipo,
      conAcciones: fichasHabilitadas,
      consultable: contexto.consultable,
      gestionable: contexto.gestionable,
      accionable: contexto.accionable,
      operable: contexto.operable,
      motivoNoOperable: contexto.motivoNoOperable,
      edicionGlobal: contexto.edicionGlobal,
      puedeCorregirContratoCerrado: yo?.rol_portal === 'superadmin',
      yoId,
      asesorNombre: contexto.asesorNombre,
      hoyLima,
      // Los dos filtros de contrato se componen en AND (mismo criterio que la
      // lista): con «por vencer» activo la sub-fila que sobra es ruido.
      contratosVisibles: g.contratos.filter(
        (c) => (fEstado === 'todos' || c.estado === fEstado) && (!soloPorVencer || porVencer.has(c.id)),
      ),
      porVencer,
      operacionesPorContrato,
      contratosPorId,
      onNuevoContrato: () => onNuevoContrato(g.cliente),
      onGestionarCliente: () => onGestionarCliente(contexto),
      onUpgradeCliente: () => onUpgradeCliente(g.cliente),
      onRenovarContrato: (contrato) => onRenovarContrato(g.cliente, contrato),
      onDetalleCliente: () => onDetalleCliente(contexto),
      onCorregirCliente: () => onCorregirCliente(g.cliente),
      onDetalleContrato,
      onCorregirContrato,
    }
  }

  // ── Las tarjetas de dinero ─────────────────────────────────────────────────
  // PEN y USD JAMÁS se suman: van en DOS tarjetas separadas para verlos al mismo
  // tiempo. Solo se muestra la tarjeta de la(s) moneda(s) CON capital, y en su
  // orden natural → si el capital es solo en dólares, la tarjeta de Dólares va
  // PRIMERO (nunca un "S/ 0" líder).
  //
  // CON UN MES ELEGIDO cambian de pregunta y de rótulo (decisión de Miguel,
  // 2026-08-14): dejan de medir el saldo VIVO de la cartera y miden lo que se
  // CERRÓ en ese mes — cualquier estado, porque un contrato que ya venció se
  // cerró igual. El rótulo cambia con ellas: una tarjeta que cambia de
  // significado sin cambiar de nombre es una mentira.
  //
  // ⚠️ Salen de `bloque`, que es EL MISMO objeto que alimenta la lista de abajo.
  // Nada de `resumenCartera(bloque.grupos)` —la alarma de renovación vive dentro
  // de esa función y se recortaría por mes gratis y sin avisar— ni de
  // `meses.flatMap(m => m.grupos)`, que contaría tres veces a quien cerró en
  // tres meses.
  const modoMes = fMes !== MES_TODOS
  const mesCorto = etiquetaDeMes(fMes).split(' ')[0]?.toLowerCase() ?? ''
  // Los otros filtros siguen vivos y recortan también el mes: se DICE, o la
  // tarjeta parecería el total del mes cuando es el total de lo buscado.
  const hayOtroFiltro = q.trim() !== '' || fEstado !== 'todos' || fAsesor !== 'todos'
  const subMes = hayOtroFiltro ? 'de lo que estás filtrando' : `registrado en ${mesCorto}`
  const capPen = modoMes ? (bloque?.capitalPen ?? 0) : resumen.capitalActivoPen
  const capUsd = modoMes ? (bloque?.capitalUsd ?? 0) : resumen.capitalActivoUsd
  const etiquetaCapital = (moneda: 'Soles' | 'Dólares') =>
    modoMes ? `Capital registrado en ${mesCorto} · ${moneda}` : `Capital vigente · ${moneda}`
  const subCapital = modoMes ? subMes : 'en contratos vigentes'
  const chipsCapital: StatChipData[] = []
  if (capPen > 0) {
    chipsCapital.push({
      icon: Wallet,
      label: etiquetaCapital('Soles'),
      value: moneyK(capPen),
      tone: 'primary',
      sub: subCapital,
    })
  }
  if (capUsd > 0) {
    chipsCapital.push({
      icon: Coins,
      label: etiquetaCapital('Dólares'),
      value: moneyK(capUsd, 'USD'),
      tone: 'primary',
      sub: subCapital,
    })
  }
  if (chipsCapital.length === 0) {
    chipsCapital.push(
      modoMes
        ? {
            icon: Wallet,
            label: `Cerrado en ${mesCorto}`,
            value: money(0, 'PEN'),
            tone: 'default',
            sub: hayOtroFiltro ? 'nada con esos filtros' : 'sin cierres este mes',
          }
        : {
            icon: Wallet,
            label: 'Capital vigente',
            value: money(0, 'PEN'),
            tone: 'default',
            sub: 'sin capital vigente aún',
          },
    )
  }
  // La alarma cuenta TODA la cartera (incl. clientes dados de baja) — es un
  // aviso, no un total. Cuando parte del conteo viene de bajas se DICE en el
  // sub-texto: mezclarlos en silencio le haría dudar de la cifra al asesor.
  //
  // ⚠️ NO se recorta por mes, aunque el resto de la barra sí (decisión de Miguel,
  // 2026-08-14). Es el ÚNICO radar de renovación del CRM, y el propio botón la
  // saca del mes al encenderla: si la tarjeta contara solo agosto diría 1, la
  // pulsas y aparecerían 3. Con un mes puesto, el sub-texto declara el alcance.
  const deBaja = resumen.porVencer30DeBaja
  const subPorVencer =
    resumen.porVencer30 === 0
      ? 'nada por vencer'
      : deBaja === 0
        ? modoMes
          ? verTodo
            ? 'en toda la empresa, no solo el mes'
            : verEquipo
              ? 'en toda la cartera del equipo, no solo el mes'
              : 'en toda tu cartera, no solo el mes'
          : 'oportunidad de renovación próxima'
        : deBaja === 1
          ? '1 es de un cliente dado de baja'
          : `${deBaja} son de clientes dados de baja`
  const stats: StatChipData[] = [
    ...chipsCapital,
    {
      icon: AlarmClock,
      label: `Por vencer en ${DIAS_ALARMA_RENOVACION} días o menos`,
      value: String(resumen.porVencer30),
      tone: resumen.porVencer30 > 0 ? 'warn' : 'default',
      sub: subPorVencer,
    },
    // Con un mes puesto cuenta a QUIÉNES les cerró ese mes, del mismo objeto que
    // la lista. Sin mes, sigue siendo el conteo de siempre.
    modoMes
      ? {
          icon: Users2,
          label: 'Clientes que cerraron',
          value: `${bloque?.grupos.length ?? 0}`,
          sub: `en ${mesCorto}`,
        }
      : {
          icon: Users2,
          label: 'Clientes con capital vigente',
          value: `${resumen.clientesConCapital}`,
          sub: `de ${resumen.totalClientes}`,
        },
  ]
  if (verEquipo) {
    // Supervisión: el conteo de clientes SIN asesor asignado (null o fuera del
    // roster) — espejo exacto del filtro — con CTA a repartirlos.
    // Sobre `enGestion`: repartir a un cliente dado de baja no es una tarea real.
    const sinAsesor = enGestion.reduce((n, g) => {
      const asesorId = g.cliente.asesor_perfil_id
      return n + (asesorId != null && rosterIds.has(asesorId) ? 0 : 1)
    }, 0)
    // "Sin asesor" reemplaza la última métrica NO monetaria (Clientes con
    // capital vigente) cuando ya hay 4 tarjetas — con capital en PEN y USD serían 5 y se
    // rompería el grid de 4. Los chips de capital (que lideran stats) no se tocan.
    if (stats.length >= 4) stats.pop()
    stats.push({
      icon: UserX,
      label: 'Sin asesor',
      value: String(sinAsesor),
      tone: sinAsesor > 0 ? 'warn' : 'default',
      sub: sinAsesor > 0 ? 'Repártelos: filtro “Sin asesor”' : 'Toda la cartera tiene dueño',
    })
  } else if (stats.length < 4) {
    // El hueco que deja una moneda ausente. Sigue siendo un número GLOBAL, y con
    // un mes puesto es además el testigo de que la cartera sigue de pie cuando
    // las tarjetas de dinero se han ido al mes. No se pone aquí el capital vivo
    // porque en una sola tarjeta habría que elegir moneda —y PEN y USD no se
    // mezclan—: un conteo no tiene ese problema.
    stats.push({
      icon: FileStack,
      label: 'Contratos vigentes',
      value: String(contratosActivosTotal),
      sub: 'en toda tu cartera',
    })
  }

  return (
    <div
      ref={contenedorRef}
      role="region"
      aria-label={titulo}
      tabIndex={-1}
      className="mx-auto max-w-[1240px] space-y-4 ac-rise focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/35"
    >
      <AvisoDegradacion
        activo={recargaFallida != null}
        queReintenta="de tu cartera"
        onReintentar={() => recargaFallida?.reintentar()}
      >
        No se pudo actualizar la cartera. Se muestran los últimos datos cargados, que pueden estar desactualizados.
      </AvisoDegradacion>
      <AvisoDegradacion
        activo={desgloseNoDisponible != null}
        queReintenta="del desglose de renovaciones y aumentos de inversión"
        onReintentar={() => desgloseNoDisponible?.reintentar()}
      >
        La cartera sigue operativa, pero el detalle de renovaciones y aumentos de inversión no está disponible.
      </AvisoDegradacion>
      {bases.length > 0 && <StatStrip stats={stats} />}
      <Card className="overflow-hidden">
        <SectionHead
          icon={Wallet}
          title={titulo}
          className="flex-wrap"
          rightClassName="ml-0 w-full sm:ml-auto sm:w-auto"
          right={
            <div className="flex items-center justify-between gap-3 sm:justify-end">
              {/* El conteo dice lo que MIDE: clientes en gestión. Los dados de
                  baja se cuentan aparte para que la cifra cuadre con las filas
                  visibles (si no, el usuario ve N+1 filas y lee N sin
                  explicación). */}
              <span className="text-xs tabular-nums text-muted-foreground">
                {grupos
                  ? `${resumen.totalClientes} cliente${resumen.totalClientes === 1 ? '' : 's'}${
                      inactivos > 0 ? ` · ${inactivos} inactivo${inactivos === 1 ? '' : 's'}` : ''
                    }`
                  : '—'}
              </span>
              {accionesContractualesHabilitadas && (
                <Button size="sm" className="min-h-10 md:min-h-8" onClick={onNuevoCliente}>
                  <Users2 aria-hidden /> Nuevo cliente
                </Button>
              )}
            </div>
          }
        />
        <p className="px-5 pb-3 text-xs text-muted-foreground">
          {demo ? 'Datos de demostración. ' : ''}
          {verTodo
            ? 'Clientes de la empresa y el capital que tienen invertido. Cada cliente agrupa sus contratos; expándelo para verlos.'
            : verEquipo
              ? 'Clientes de tu equipo y el capital que tienen invertido. Cada cliente agrupa sus contratos; expándelo para verlos.'
              : 'Tus clientes y el capital que tienen invertido en Avance Corp. Cada cliente agrupa sus contratos; expándelo para verlos.'}
          {/* Se dice que la pantalla ARRANCA filtrada: si no, un asesor que no
              haya cerrado nada este mes leería su cartera vacía como un fallo. */}
          {' Empieza mostrando el mes en curso; cambia el mes o elige «Todos los meses» para ver el resto.'}
          {/* La marca «inactivo» se explica en texto, no solo con un tooltip:
              el `title` del Badge no existe en táctil ni con lector de pantalla. */}
          {inactivos > 0 &&
            ' Los marcados «inactivo» están dados de baja en el portal: siguen listados para consultar sus contratos y sus vencimientos siguen avisando, pero no suman a los totales de capital.'}
        </p>

        {grupos == null && !error ? (
          <PanelCargando />
        ) : error ? (
          <PanelError mensaje={error.mensaje} onReintentar={error.reintentar} reintentando={error.reintentando} />
        ) : bases.length === 0 ? (
          <PanelVacio
            icono={Inbox}
            titulo={verEquipo ? 'Aún no hay clientes en la cartera.' : 'Aún no tienes clientes en tu cartera.'}
          >
            {accionesContractualesHabilitadas && <p className="text-xs text-muted-foreground">Usa “Nuevo cliente”.</p>}
          </PanelVacio>
        ) : (
          <>
            <div className="flex flex-wrap items-center gap-2 px-5 pb-3">
              <div className="relative w-full max-w-sm">
                <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  aria-label="Buscar en la cartera"
                  placeholder="Buscar cliente, documento o N° de contrato…"
                  className="pl-9"
                  value={q}
                  onChange={(e) => setQ(e.target.value)}
                />
              </div>
              <div className="w-[190px]">
                <Select
                  aria-label="Filtrar por estado de contrato"
                  value={fEstado}
                  onChange={(e) => setFEstado(e.target.value as FiltroEstado)}
                >
                  <option value="todos">Todos los estados</option>
                  <option value="activo">Contratos vigentes</option>
                  <option value="vencido">Vencidos</option>
                  <option value="renovado">Renovados</option>
                  <option value="retirado">Retirados</option>
                </Select>
              </div>
              {/* Filtro de MES DE CIERRE. Arranca en el mes en curso: el asesor
                  abre y ve lo que lleva cerrado ESTE mes, sin listas de meses
                  que recorrer (decisión de Miguel, 2026-08-14). */}
              <div className="w-[190px]">
                <Select aria-label="Filtrar por mes de cierre" value={fMes} onChange={(e) => setFMes(e.target.value)}>
                  <option value={MES_TODOS}>{etiquetaDeMes(MES_TODOS)}</option>
                  {opcionesMes.map((o) => (
                    <option key={o.clave} value={o.clave}>
                      {o.etiqueta}
                    </option>
                  ))}
                </Select>
              </div>
              {/* Filtro por asesor: solo supervisión (para el vendedor sería su propio
                  nombre). "Sin asesor" aísla los clientes sin dueño para repartirlos. */}
              {verEquipo && (
                <div className="w-[230px]">
                  <Select aria-label="Filtrar por asesor" value={fAsesor} onChange={(e) => setFAsesor(e.target.value)}>
                    <option value="todos">Todos los asesores</option>
                    {equipo
                      .filter((m) => m.activo)
                      .map((m) => (
                        <option key={m.perfil_id} value={m.perfil_id}>
                          {m.nombre_completo}
                        </option>
                      ))}
                    <option value="sin_asesor">Sin asesor</option>
                  </Select>
                </div>
              )}
              {/* Aterrizaje del chip «Por vencer»: el ÚNICO modo de llegar a la
                  fila que vence (el Select filtra por estado de CONTRATO, no por
                  vencimiento, y la fecha solo se lee en gris dentro del grupo).
                  No se pinta si nunca hubo nada que renovar; a partir de ahí se
                  queda (ver `huboPorVencer`): desmontarlo con el filtro puesto
                  dejaría al asesor con una lista vacía y sin botón para salir. */}
              {(huboPorVencer || soloPorVencer) && (
                <button
                  type="button"
                  aria-pressed={soloPorVencer}
                  // Al encender el aviso, el mes se quita: es el ÚNICO radar de
                  // renovación del CRM, y con un mes puesto el contador diría 3
                  // y la lista enseñaría 1 — las otras dos renovaciones no las
                  // vería nadie (decisión de Miguel, 2026-08-14).
                  onClick={() =>
                    setSoloPorVencer((v) => {
                      if (!v) setFMes(MES_TODOS)
                      return !v
                    })
                  }
                  className={`inline-flex h-8 shrink-0 items-center gap-1 rounded-md border px-2.5 text-xs font-semibold transition-colors ${
                    soloPorVencer
                      ? 'border-warning bg-warning/15 text-warning-text'
                      : 'border-border bg-card text-muted-foreground hover:bg-muted'
                  }`}
                >
                  <AlarmClock className="size-3" aria-hidden />
                  Por vencer en {DIAS_ALARMA_RENOVACION} días o menos ({resumen.porVencer30})
                </button>
              )}
              {hayFiltro && (
                <span className="text-xs tabular-nums text-muted-foreground">
                  {visiblesDelFiltro.length} de {bases.length}
                </span>
              )}
            </div>

            {/* Lo que se cerró en el mes elegido. Es el resumen que pidió Miguel,
                y vive pegado a la lista que resume para que no puedan contar
                cosas distintas.
                ⚠️ Dice «cerrados» y NO es la cuota: cuenta todo contrato de un
                cliente del asesor, mientras la cuota le paga por los que
                registró él. Cuando el mes incluye alguno ajeno se DICE — si no,
                vería un capital aquí y otro en Hoy sin explicación. */}
            {bloque != null && bloque.contratos > 0 && (
              <p className="flex flex-wrap items-center gap-x-3 gap-y-1 px-5 pb-3 text-xs tabular-nums text-muted-foreground-strong">
                <span>
                  {bloque.contratos} contrato{bloque.contratos === 1 ? '' : 's'} cerrado
                  {bloque.contratos === 1 ? '' : 's'} en {bloque.etiqueta.toLowerCase()}
                </span>
                {/* Los IMPORTES ya no se repiten aquí: viven en las tarjetas de
                    arriba desde que siguen al mes (decisión de Miguel,
                    2026-08-14). Esta línea se queda solo con lo que las tarjetas
                    no dicen — cuántos contratos son y el aviso de los ajenos —,
                    que es lo que impedía borrarla del todo. */}
                {bloque.registradosPorOtro > 0 && (
                  <span className="text-warning-text">
                    incluye {bloque.registradosPorOtro} contrato
                    {bloque.registradosPorOtro === 1 ? '' : 's'} registrado
                    {bloque.registradosPorOtro === 1 ? '' : 's'} por otra persona
                  </span>
                )}
              </p>
            )}

            {visiblesDelFiltro.length === 0 ? (
              <PanelVacio
                icono={Inbox}
                titulo={mesEsElUnicoFiltro ? `Sin cierres en ${etiquetaDeMes(fMes).toLowerCase()}` : 'Sin resultados'}
                detalle={
                  // El mes SOLO: no es un "sin resultados" cualquiera — la
                  // cartera está entera, simplemente no se cerró nada ese mes.
                  // Y como la pantalla arranca en el mes en curso, este es el
                  // primer estado que ve un asesor que aún no ha cerrado: tiene
                  // que llevar la salida puesta, o se queda mirando un vacío.
                  mesEsElUnicoFiltro
                    ? 'Tus clientes siguen ahí; en ese mes no se cerró ningún contrato.'
                    : q.trim()
                      ? `Ningún cliente ni contrato coincide con “${q.trim()}”.`
                      : // Con DOS o más filtros el vacío puede deberse a cualquiera
                        // de ellos, así que un mensaje neutral no afirma de más.
                        [fAsesor !== 'todos', fEstado !== 'todos', soloPorVencer, fMes !== MES_TODOS].filter(Boolean)
                            .length > 1
                        ? 'Ningún cliente coincide con los filtros aplicados.'
                        : soloPorVencer
                          ? `Ningún contrato vence en los próximos ${DIAS_ALARMA_RENOVACION} días.`
                          : fAsesor === 'sin_asesor'
                            ? 'No hay clientes sin asesor: toda la cartera tiene dueño.'
                            : fAsesor !== 'todos'
                              ? 'Ese asesor no tiene clientes en la cartera.'
                              : 'Ningún cliente tiene contratos en ese estado.'
                }
              >
                {fMes !== MES_TODOS && (
                  <Button size="sm" variant="secondary" onClick={() => setFMes(MES_TODOS)}>
                    Ver toda la cartera
                  </Button>
                )}
              </PanelVacio>
            ) : esMovil ? (
              // Card-stack táctil (< 768 px): una tarjeta por cliente.
              <div role="list" aria-label={titulo} className="space-y-3 px-3 pb-4">
                {visibles.map((g) => (
                  <div role="listitem" key={g.cliente.id}>
                    <TarjetaGrupoCliente {...propsDeGrupo(g)} />
                  </div>
                ))}
              </div>
            ) : (
              <TablaEnvoltura ariaLabel={titulo}>
                <TheadCrm>
                  <Th>Cartera / Contrato</Th>
                  <Th className="text-center">Estado</Th>
                  {verEquipo && <Th className="hidden md:table-cell">Asesor</Th>}
                  <Th className="text-right" aria-label="Capital vigente">
                    Capital vigente
                  </Th>
                  {fichasHabilitadas && <Th className="text-right">Acciones</Th>}
                </TheadCrm>
                <tbody>
                  {visibles.map((g) => (
                    <FilaGrupoCliente key={g.cliente.id} {...propsDeGrupo(g)} />
                  ))}
                </tbody>
              </TablaEnvoltura>
            )}
          </>
        )}
      </Card>

      <Paginacion
        paginaActual={paginaActual}
        paginas={paginas}
        total={visiblesDelFiltro.length}
        onCambio={setPagina}
        ariaLabel="Paginación de la cartera"
      />

      {/* Cierres en COOPAC Qorilazo/Prodelco: personas SIN cuenta de portal.
          Sección aparte de la lista (no hay cliente que agrupar) y con sus
          totales propios — ese dinero no lo administra Avance. Se oculta sola
          si el ámbito no tiene cierres. */}
      <SeccionEnCooperativas demo={demo} />
    </div>
  )
}

/** Overlay de acciones — uno solo abierto a la vez (como el portal). */
type Overlay =
  | { tipo: 'cliente-crear' }
  | {
      tipo: 'cliente-ficha'
      clienteId: string
      focoInicial?: FocoInicialClienteFicha
    }
  | { tipo: 'cliente-gestionar'; clienteId: string; clienteNombre: string }
  | { tipo: 'cliente-corregir'; clienteId: string }
  | {
      tipo: 'contrato-crear'
      clienteId: string
      clienteNombre: string
      upgrade: boolean
    }
  | {
      tipo: 'contrato-renovar'
      clienteId: string
      clienteNombre: string
      contrato: ContratoRow
      firmaTerminosOriginales: string
    }
  | {
      tipo: 'contrato-detalle'
      contrato: ContratoRow
      volverACliente?: {
        clienteId: string
        focoInicial: FocoInicialClienteFicha
      }
    }
  | { tipo: 'contrato-corregir'; contrato: ContratoRow; firmaTerminosOriginales: string }
  | null

function clienteIdDeOverlay(overlay: Overlay): string | null {
  if (overlay == null || overlay.tipo === 'cliente-crear') return null
  if (overlay.tipo === 'contrato-detalle' || overlay.tipo === 'contrato-corregir') {
    return overlay.contrato.cliente_id
  }
  return overlay.clienteId
}

function contratoIdDeOverlay(overlay: Overlay): string | null {
  if (
    overlay?.tipo === 'contrato-renovar' ||
    overlay?.tipo === 'contrato-detalle' ||
    overlay?.tipo === 'contrato-corregir'
  ) {
    return overlay.contrato.id
  }
  return null
}

function contratoSigueRenovable(contrato: ContratoRow, hoyLima: string): boolean {
  return (
    (contrato.estado === 'activo' || contrato.estado === 'vencido') &&
    /^\d{4}-\d{2}-\d{2}$/.test(contrato.fecha_vencimiento) &&
    contrato.fecha_vencimiento <= hoyLima
  )
}

/** Fotografía estable de los términos que una corrección puede cambiar. Se
 * excluyen etiquetas de presentación y metadatos del catálogo para que una
 * recarga inocua no cierre el trabajo del asesor. Las notas se comparan como
 * viajan al servidor: sin espacios exteriores y con vacío equivalente a null. */
function firmaTerminosContrato(contrato: ContratoRow): string {
  return JSON.stringify([
    contrato.numero_contrato.trim(),
    contrato.capital,
    contrato.moneda,
    contrato.tasa_anual,
    contrato.modalidad,
    contrato.tipo_interes,
    contrato.categoria,
    contrato.fecha_inicio,
    contrato.fecha_vencimiento,
    contrato.notas_internas?.trim() || null,
    contrato.producto_condicion_id,
  ])
}

function overlayConservaAcceso(overlay: Overlay, contexto: ContextoFichaCliente | null): boolean {
  if (overlay == null || overlay.tipo === 'cliente-crear') return true
  if (contexto == null) return false
  if (overlay.tipo === 'cliente-ficha' || overlay.tipo === 'contrato-detalle') return contexto.consultable
  if (overlay.tipo === 'cliente-gestionar') return contexto.gestionable && contexto.operable
  return contexto.accionable && contexto.operable
}

interface ContratoConfirmadoParaCierre {
  numero: string
  creadoLocal?: ContratoCreadoLocal
}

export function MiCartera() {
  const { yo } = useAuth()
  const { equipo, recargar } = useCRMData()
  const esDemo = yo?.demo === true
  const queryClient = useQueryClient()
  const [overlay, setOverlay] = useState<Overlay>(null)
  const [envioEnCurso, setEnvioEnCurso] = useState(false)
  const [contratoConfirmado, setContratoConfirmado] = useState<ContratoConfirmadoParaCierre | null>(null)
  const ahoraOverlay = useAhora()
  const contratosFinalizadosRef = useRef(new Set<string>())
  const focoCarteraRef = useRef<HTMLDivElement>(null)
  const recargarStoreRef = useRef(recargar)

  const clientesQ = useClientes(!esDemo)
  const contratosQ = useContratos(!esDemo)
  const operacionesQ = useOperacionesCartera(!esDemo)

  const grupos = useMemo(() => {
    if (clientesQ.data == null || contratosQ.data == null) return null
    return agruparCartera(clientesQ.data, contratosQ.data)
  }, [clientesQ.data, contratosQ.data])
  const clienteOverlayId = clienteIdDeOverlay(overlay)
  const contratoOverlayId = contratoIdDeOverlay(overlay)
  const grupoOverlay =
    clienteOverlayId == null ? null : (grupos?.find((grupo) => grupo.cliente.id === clienteOverlayId) ?? null)
  const contextoOverlay = grupoOverlay
    ? resolverContextoFichaCliente({
        grupo: grupoOverlay,
        equipo,
        yoId: yo?.id,
        rol: yo?.rol,
        puedeContratar: yo?.puede_contratar === true,
      })
    : null
  const grupoFicha = overlay?.tipo === 'cliente-ficha' ? grupoOverlay : null
  const contextoFicha = overlay?.tipo === 'cliente-ficha' ? contextoOverlay : null
  const contratoOverlayActual =
    contratoOverlayId == null
      ? null
      : (grupoOverlay?.contratos.find((contrato) => contrato.id === contratoOverlayId) ?? null)
  const terminosContratoCambiaron =
    contratoOverlayActual != null &&
    (overlay?.tipo === 'contrato-renovar' || overlay?.tipo === 'contrato-corregir') &&
    firmaTerminosContrato(contratoOverlayActual) !== overlay.firmaTerminosOriginales
  const ventanaCorreccionContrato = useVentana(
    overlay?.tipo === 'contrato-corregir' && contextoOverlay?.edicionGlobal !== true
      ? (contratoOverlayActual?.creado_en ?? null)
      : null,
  )
  const correccionContratoBloqueadaPorEstado =
    contratoOverlayActual != null &&
    (contratoOverlayActual.estado === 'renovado' || contratoOverlayActual.estado === 'retirado') &&
    yo?.rol_portal !== 'superadmin'
  const correccionContratoFueraDeAlcance =
    contratoOverlayActual != null &&
    contextoOverlay?.edicionGlobal !== true &&
    (contratoOverlayActual.creado_por !== yo?.id || !ventanaCorreccionContrato.vigente)

  useEffect(() => {
    recargarStoreRef.current = recargar
  }, [recargar])

  // Mientras una ficha o acción del cliente siga abierta, agenda y equipo se
  // vuelven a confirmar cada minuto. En una pestaña oculta se pausa el trabajo;
  // al regresar se actualiza de inmediato.
  useEffect(() => {
    if (esDemo || clienteOverlayId == null) return
    const actualizarContexto = () => {
      if (document.visibilityState !== 'visible') return
      void recargarStoreRef.current()
    }
    const temporizador = window.setInterval(actualizarContexto, INTERVALO_REVALIDACION_CARTERA_MS)
    const alVolver = () => actualizarContexto()
    document.addEventListener('visibilitychange', alVolver)
    return () => {
      window.clearInterval(temporizador)
      document.removeEventListener('visibilitychange', alVolver)
    }
  }, [clienteOverlayId, esDemo])

  const limpiarDatosFicha = useCallback(
    (clienteId: string) => {
      const claves = [
        crmQueryKeys.clienteFichaComercial(clienteId),
        crmQueryKeys.clienteDetalle(clienteId),
        crmQueryKeys.actividadesCliente(clienteId),
        crmQueryKeys.cuentasBancarias(clienteId, 'PEN'),
        crmQueryKeys.cuentasBancarias(clienteId, 'USD'),
      ]
      for (const queryKey of claves) {
        void queryClient.cancelQueries({ queryKey, exact: true })
        queryClient.removeQueries({ queryKey, exact: true })
      }
    },
    [queryClient],
  )

  const limpiarDatosContrato = useCallback(
    (contratoId: string) => {
      void queryClient.cancelQueries({
        queryKey: crmQueryKeys.cronograma(contratoId),
        exact: true,
      })
      void queryClient.cancelQueries({
        queryKey: crmQueryKeys.titulares(contratoId),
        exact: true,
      })
      queryClient.removeQueries({
        queryKey: crmQueryKeys.cronograma(contratoId),
        exact: true,
      })
      queryClient.removeQueries({
        queryKey: crmQueryKeys.titulares(contratoId),
        exact: true,
      })
    },
    [queryClient],
  )

  const limpiarDatosTemporalesCliente = useCallback(
    (clienteId: string) => {
      const contratosDelCliente =
        queryClient
          .getQueryData<ContratoRow[]>(crmQueryKeys.contratos())
          ?.filter((contrato) => contrato.cliente_id === clienteId) ?? []
      for (const contrato of contratosDelCliente) limpiarDatosContrato(contrato.id)
      limpiarDatosFicha(clienteId)
    },
    [limpiarDatosContrato, limpiarDatosFicha, queryClient],
  )

  const retirarClienteDeSesion = useCallback(
    (clienteId: string) => {
      // El cierre visual es inmediato y la copia local se recorta antes de
      // volver a consultar al servidor. Así una respuesta de "fuera de cartera"
      // no deja al cliente ni sus inversiones visibles durante la recarga.
      limpiarDatosTemporalesCliente(clienteId)
      void queryClient.cancelQueries({
        queryKey: crmQueryKeys.clientes(),
        exact: true,
      })
      void queryClient.cancelQueries({
        queryKey: crmQueryKeys.contratos(),
        exact: true,
      })
      void queryClient.cancelQueries({
        queryKey: crmQueryKeys.operacionesCartera(),
        exact: true,
      })
      queryClient.setQueryData<ClienteBasico[]>(crmQueryKeys.clientes(), (actuales) =>
        actuales?.filter((cliente) => cliente.id !== clienteId),
      )
      queryClient.setQueryData<ContratoRow[]>(crmQueryKeys.contratos(), (actuales) =>
        actuales?.filter((contrato) => contrato.cliente_id !== clienteId),
      )
      queryClient.setQueryData<OperacionCartera[]>(crmQueryKeys.operacionesCartera(), (actuales) =>
        actuales?.filter((operacion) => operacion.cliente_id !== clienteId),
      )
      setEnvioEnCurso(false)
      setContratoConfirmado(null)
      setOverlay((actual) => (clienteIdDeOverlay(actual) === clienteId ? null : actual))
      toast.info('Este cliente ya no está asignado a tu cartera. Actualizamos la información disponible.')
      window.setTimeout(() => focoCarteraRef.current?.focus(), 0)

      void queryClient.invalidateQueries({
        queryKey: crmQueryKeys.clientes(),
        exact: true,
      })
      void queryClient.invalidateQueries({
        queryKey: crmQueryKeys.contratos(),
        exact: true,
      })
      void queryClient.invalidateQueries({
        queryKey: crmQueryKeys.operacionesCartera(),
        exact: true,
      })
    },
    [limpiarDatosTemporalesCliente, queryClient],
  )

  const cerrarAccionYaNoDisponible = useCallback(
    (clienteId: string) => {
      limpiarDatosTemporalesCliente(clienteId)
      setEnvioEnCurso(false)
      setContratoConfirmado(null)
      setOverlay((actual) => (clienteIdDeOverlay(actual) === clienteId ? null : actual))
      toast.info('Esta acción ya no está disponible. Actualizamos la ficha del cliente para que puedas consultarla.')
      window.setTimeout(() => focoCarteraRef.current?.focus(), 0)
    },
    [limpiarDatosTemporalesCliente],
  )

  const cerrarContratoYaNoDisponible = useCallback(
    (contratoId: string) => {
      limpiarDatosContrato(contratoId)
      setEnvioEnCurso(false)
      setContratoConfirmado(null)
      setOverlay((actual) => (contratoIdDeOverlay(actual) === contratoId ? null : actual))
      toast.info('Este contrato ya no está disponible. Actualizamos la información del cliente.')
      window.setTimeout(() => focoCarteraRef.current?.focus(), 0)
    },
    [limpiarDatosContrato],
  )

  const cerrarPorCambioDeTerminos = useCallback(
    (contratoId: string) => {
      limpiarDatosContrato(contratoId)
      setEnvioEnCurso(false)
      setContratoConfirmado(null)
      setOverlay((actual) => (contratoIdDeOverlay(actual) === contratoId ? null : actual))
      toast.info('Los datos del contrato cambiaron. Vuelve a abrir para continuar.')
      window.setTimeout(() => focoCarteraRef.current?.focus(), 0)
    },
    [limpiarDatosContrato],
  )

  const actualizarAsignacionCliente = useCallback(
    (_clienteId: string) => {
      void recargarStoreRef.current()
      void queryClient.invalidateQueries({
        queryKey: crmQueryKeys.clientes(),
        exact: true,
      })
      void queryClient.invalidateQueries({
        queryKey: crmQueryKeys.contratos(),
        exact: true,
      })
      void queryClient.invalidateQueries({
        queryKey: crmQueryKeys.operacionesCartera(),
        exact: true,
      })
    },
    [queryClient],
  )

  useEffect(() => {
    if (clienteOverlayId == null || grupos == null) return
    if (grupoOverlay == null || contextoOverlay?.consultable !== true) {
      retirarClienteDeSesion(clienteOverlayId)
      return
    }
    if (contratoOverlayId != null && !grupoOverlay.contratos.some((contrato) => contrato.id === contratoOverlayId)) {
      cerrarContratoYaNoDisponible(contratoOverlayId)
      return
    }
    if (contratoOverlayId != null && terminosContratoCambiaron) {
      cerrarPorCambioDeTerminos(contratoOverlayId)
      return
    }
    if (
      overlay?.tipo === 'contrato-renovar' &&
      contratoOverlayActual != null &&
      !contratoSigueRenovable(contratoOverlayActual, fechaLima(ahoraOverlay))
    ) {
      cerrarAccionYaNoDisponible(clienteOverlayId)
      return
    }
    if (
      overlay?.tipo === 'contrato-corregir' &&
      (correccionContratoBloqueadaPorEstado || correccionContratoFueraDeAlcance)
    ) {
      cerrarAccionYaNoDisponible(clienteOverlayId)
      return
    }
    if (overlayConservaAcceso(overlay, contextoOverlay)) return
    cerrarAccionYaNoDisponible(clienteOverlayId)
  }, [
    cerrarAccionYaNoDisponible,
    cerrarContratoYaNoDisponible,
    cerrarPorCambioDeTerminos,
    contratoOverlayActual,
    correccionContratoBloqueadaPorEstado,
    correccionContratoFueraDeAlcance,
    clienteOverlayId,
    contratoOverlayId,
    contextoOverlay,
    ahoraOverlay,
    grupoOverlay,
    grupos,
    overlay,
    retirarClienteDeSesion,
    terminosContratoCambiaron,
    ventanaCorreccionContrato.vigente,
    yo?.id,
  ])

  if (esDemo) return <MiCarteraDemo />

  const cerrar = () => setOverlay(null)
  const cerrarFicha = () => {
    if (overlay?.tipo === 'cliente-ficha') limpiarDatosFicha(overlay.clienteId)
    setOverlay(null)
  }
  const cerrarDetalleContrato = () => {
    if (overlay?.tipo !== 'contrato-detalle') {
      setOverlay(null)
      return
    }
    limpiarDatosContrato(overlay.contrato.id)
    if (!overlay.volverACliente) {
      setOverlay(null)
      return
    }
    setOverlay({
      tipo: 'cliente-ficha',
      clienteId: overlay.volverACliente.clienteId,
      focoInicial: overlay.volverACliente.focoInicial,
    })
  }
  // Cierre BLINDADO de ClienteForm: no cerrar con un envío en vuelo. Radix cierra
  // con Esc/overlay incondicionalmente y el alta ya está en el servidor.
  const cerrarSeguro = () => {
    if (envioEnCurso) return
    if (overlay?.tipo === 'cliente-corregir') limpiarDatosFicha(overlay.clienteId)
    cerrar()
  }
  // El alta puede cerrarse sin pasar por onListo (el asesor cancela el contrato
  // encadenado): el refetch va SIEMPRE al cerrar el alta.
  const cerrarAlta = () => {
    if (envioEnCurso) return
    cerrar()
    void clientesQ.refetch()
    void contratosQ.refetch()
  }

  const abrirNuevoContrato = (clienteId: string, clienteNombre: string, upgrade = false) => {
    setContratoConfirmado(null)
    setEnvioEnCurso(false)
    setOverlay({ tipo: 'contrato-crear', clienteId, clienteNombre, upgrade })
  }

  const abrirRenovacion = (cliente: ClienteBasico, contrato: ContratoRow) => {
    setContratoConfirmado(null)
    setEnvioEnCurso(false)
    setOverlay({
      tipo: 'contrato-renovar',
      clienteId: cliente.id,
      clienteNombre: cliente.nombre_completo || cliente.correo || 'el cliente',
      contrato,
      firmaTerminosOriginales: firmaTerminosContrato(contrato),
    })
  }

  // Finalizar, Esc y click en overlay convergen aqui. La llave impide que dos
  // eventos de cierre del mismo tick dupliquen la invalidacion.
  const finalizarContratoCreado = (numero: string, creadoLocal?: ContratoCreadoLocal) => {
    const llave = creadoLocal?.id ?? numero
    if (!contratosFinalizadosRef.current.has(llave)) {
      contratosFinalizadosRef.current.add(llave)
      void queryClient.invalidateQueries({
        queryKey: crmQueryKeys.contratos(),
      })
      void queryClient.invalidateQueries({ queryKey: crmQueryKeys.metricas() })
      void queryClient.invalidateQueries({
        queryKey: crmQueryKeys.metricasAmbito(),
      })
      void queryClient.invalidateQueries({
        queryKey: crmQueryKeys.operacionesCartera(),
        exact: true,
      })
    }
    setContratoConfirmado(null)
    setEnvioEnCurso(false)
    setOverlay(null)
  }

  const cerrarContratoNuevo = () => {
    if (envioEnCurso) return
    if (contratoConfirmado) {
      finalizarContratoCreado(contratoConfirmado.numero, contratoConfirmado.creadoLocal)
      return
    }
    setOverlay(null)
  }

  // Alta exitosa → refrescar cartera y encadenar el contrato (flujo del portal).
  const alClienteCreado = async (id: string) => {
    setOverlay(null)
    const r = await clientesQ.refetch()
    void contratosQ.refetch()
    const nuevo = r.data?.find((c) => c.id === id)
    abrirNuevoContrato(id, nuevo?.nombre_completo ?? 'el cliente')
  }

  // Corregir cliente → refetch + invalidar clienteDetalle(id) y contratos()
  // (cliente_nombre viaja denormalizado en la vista de contratos: sin invalidarla
  // la sub-fila mostraría el nombre viejo < 30 s).
  const alClienteCorregido = (id: string) => {
    limpiarDatosFicha(id)
    setOverlay(null)
    void clientesQ.refetch()
    void queryClient.invalidateQueries({ queryKey: crmQueryKeys.contratos() })
  }

  // Crear/corregir contrato → invalidar contratos() (prefijo: cubre cronograma+titulares).
  const recargarContratos = () => {
    if (overlay?.tipo === 'contrato-corregir') limpiarDatosContrato(overlay.contrato.id)
    setOverlay(null)
    void queryClient.invalidateQueries({ queryKey: crmQueryKeys.contratos() })
  }

  const cerrarCorreccionContrato = () => {
    if (overlay?.tipo === 'contrato-corregir') limpiarDatosContrato(overlay.contrato.id)
    setOverlay(null)
  }

  // El servidor decide si la corrección sigue dentro de las 5 horas y, cuando
  // la acepta, reserva una nueva revisión PDF. La UI no intenta anticipar esa
  // decisión con el estado de la revisión anterior.
  const abrirCorreccionContrato = (contrato: ContratoRow) => {
    setOverlay({
      tipo: 'contrato-corregir',
      contrato,
      firmaTerminosOriginales: firmaTerminosContrato(contrato),
    })
  }

  const cargando = grupos == null && !(clientesQ.isError || contratosQ.isError)
  const hayError = (clientesQ.isError || contratosQ.isError) && grupos == null
  // Falló la recarga PERO seguimos con datos: la pantalla es plenamente operable,
  // así que no se bloquea con PanelError — se avisa de que lo que se ve puede
  // estar rancio. Sin esto la cartera se veía idéntica a una recién cargada.
  const recargaFallida = (clientesQ.isError || contratosQ.isError) && grupos != null
  const reintentarCarga = () => {
    void recargarStoreRef.current()
    void clientesQ.refetch()
    void contratosQ.refetch()
    void operacionesQ.refetch()
  }

  return (
    <>
      <VistaMiCartera
        grupos={cargando ? null : grupos}
        operaciones={operacionesQ.data ?? []}
        desgloseNoDisponible={operacionesQ.isError ? { reintentar: () => void operacionesQ.refetch() } : null}
        demo={false}
        error={
          hayError
            ? {
                mensaje: mensajeDeError(clientesQ.error ?? contratosQ.error, 'No se pudo cargar tu cartera.'),
                reintentando: clientesQ.isFetching || contratosQ.isFetching,
                reintentar: reintentarCarga,
              }
            : null
        }
        recargaFallida={recargaFallida ? { reintentar: reintentarCarga } : null}
        yoId={yo?.id ?? null}
        puedeContratar={yo?.puede_contratar === true}
        onNuevoCliente={() => setOverlay({ tipo: 'cliente-crear' })}
        onNuevoContrato={(c) => abrirNuevoContrato(c.id, c.nombre_completo || c.correo || 'el cliente')}
        onGestionarCliente={(contexto) =>
          setOverlay({
            tipo: 'cliente-ficha',
            clienteId: contexto.clienteId,
            focoInicial: 'siguiente-contacto',
          })
        }
        onUpgradeCliente={(c) => abrirNuevoContrato(c.id, c.nombre_completo || c.correo || 'el cliente', true)}
        onRenovarContrato={abrirRenovacion}
        onDetalleCliente={(contexto) => setOverlay({ tipo: 'cliente-ficha', clienteId: contexto.clienteId })}
        onCorregirCliente={(c) => setOverlay({ tipo: 'cliente-corregir', clienteId: c.id })}
        onDetalleContrato={(k) => setOverlay({ tipo: 'contrato-detalle', contrato: k })}
        onCorregirContrato={abrirCorreccionContrato}
        contenedorRef={focoCarteraRef}
      />

      {overlay?.tipo === 'cliente-crear' && (
        <Dialog open onClose={cerrarAlta} ariaLabel="Nuevo cliente">
          <ClienteForm
            modo="crear"
            onListo={(id) => void alClienteCreado(id)}
            onCerrar={cerrarAlta}
            onEnviandoCambio={setEnvioEnCurso}
          />
        </Dialog>
      )}
      {overlay?.tipo === 'cliente-ficha' && grupoFicha && contextoFicha?.consultable && (
        <Sheet
          open
          onClose={cerrarFicha}
          ariaLabel={`Ficha comercial de ${grupoFicha.cliente.nombre_completo || 'cliente'}`}
          className="w-[620px] max-w-full"
        >
          <ClienteFicha
            grupo={grupoFicha}
            asesorNombre={contextoFicha.asesorNombre}
            operaciones={(operacionesQ.data ?? []).filter(
              (operacion) => operacion.cliente_id === grupoFicha.cliente.id,
            )}
            movimientosInversionPendientes={operacionesQ.isPending}
            movimientosInversionDesactualizados={
              operacionesQ.isError
                ? {
                    reintentar: () => void operacionesQ.refetch(),
                    actualizando: operacionesQ.isFetching,
                  }
                : null
            }
            onAccesoRevocado={retirarClienteDeSesion}
            onAsignacionDesactualizada={actualizarAsignacionCliente}
            operable={contextoFicha.operable}
            motivoNoOperable={contextoFicha.motivoNoOperable}
            edicionGlobal={contextoFicha.edicionGlobal}
            focoInicial={overlay.focoInicial}
            puedeVerCuentas={contextoFicha.puedeVerCuentas}
            datosCarteraDesactualizados={recargaFallida ? { reintentar: reintentarCarga } : null}
            onCerrar={cerrarFicha}
            onGestionar={
              contextoFicha.gestionable
                ? () => {
                    limpiarDatosFicha(grupoFicha.cliente.id)
                    setOverlay({
                      tipo: 'cliente-gestionar',
                      clienteId: grupoFicha.cliente.id,
                      clienteNombre: grupoFicha.cliente.nombre_completo || grupoFicha.cliente.correo || 'el cliente',
                    })
                  }
                : undefined
            }
            onCorregir={
              contextoFicha.accionable
                ? () => {
                    limpiarDatosFicha(grupoFicha.cliente.id)
                    setOverlay({
                      tipo: 'cliente-corregir',
                      clienteId: grupoFicha.cliente.id,
                    })
                  }
                : undefined
            }
            onNuevoContrato={
              contextoFicha.accionable
                ? () => {
                    limpiarDatosFicha(grupoFicha.cliente.id)
                    abrirNuevoContrato(
                      grupoFicha.cliente.id,
                      grupoFicha.cliente.nombre_completo || grupoFicha.cliente.correo || 'el cliente',
                    )
                  }
                : undefined
            }
            onUpgrade={
              contextoFicha.accionable
                ? () => {
                    limpiarDatosFicha(grupoFicha.cliente.id)
                    abrirNuevoContrato(
                      grupoFicha.cliente.id,
                      grupoFicha.cliente.nombre_completo || grupoFicha.cliente.correo || 'el cliente',
                      true,
                    )
                  }
                : undefined
            }
            onDetalleContrato={(contrato) => {
              limpiarDatosFicha(grupoFicha.cliente.id)
              setOverlay({
                tipo: 'contrato-detalle',
                contrato,
                volverACliente: {
                  clienteId: grupoFicha.cliente.id,
                  focoInicial: { tipo: 'contrato', contratoId: contrato.id },
                },
              })
            }}
            onRenovarContrato={
              contextoFicha.accionable
                ? (contrato) => {
                    limpiarDatosFicha(grupoFicha.cliente.id)
                    abrirRenovacion(grupoFicha.cliente, contrato)
                  }
                : undefined
            }
          />
        </Sheet>
      )}
      {overlay?.tipo === 'cliente-gestionar' && (
        <Dialog
          open
          onClose={cerrarSeguro}
          ariaLabel={`Agendar seguimiento de ${overlay.clienteNombre || 'cliente'}`}
          className="w-[640px]"
        >
          <ClienteGestion
            clienteId={overlay.clienteId}
            clienteNombre={overlay.clienteNombre}
            onCerrar={cerrarSeguro}
            onEnviandoCambio={setEnvioEnCurso}
          />
        </Dialog>
      )}
      {overlay?.tipo === 'cliente-corregir' && (
        <Dialog open onClose={cerrarSeguro} ariaLabel="Corregir datos del cliente">
          <ClienteForm
            modo="corregir"
            clienteId={overlay.clienteId}
            onListo={alClienteCorregido}
            onCerrar={cerrarSeguro}
            onEnviandoCambio={setEnvioEnCurso}
          />
        </Dialog>
      )}
      {overlay?.tipo === 'contrato-crear' && (
        <Dialog
          open
          onClose={cerrarContratoNuevo}
          ariaLabel={overlay.upgrade ? 'Aumentar inversión del cliente' : 'Registrar nueva inversión del cliente'}
        >
          <ContratoNuevo
            clienteId={overlay.clienteId}
            clienteNombre={overlay.clienteNombre}
            {...(overlay.upgrade ? { categoriaFija: 'upgrade' as const } : {})}
            onConfirmado={(numero, creadoLocal) =>
              setContratoConfirmado(creadoLocal ? { numero, creadoLocal } : { numero })
            }
            onEnviandoCambio={setEnvioEnCurso}
            onCreado={finalizarContratoCreado}
            onOmitir={cerrarContratoNuevo}
          />
        </Dialog>
      )}
      {overlay?.tipo === 'contrato-renovar' && contratoOverlayActual && !terminosContratoCambiaron && (
        <Dialog
          open
          onClose={cerrarContratoNuevo}
          ariaLabel={`Renovar inversión del contrato ${contratoOverlayActual.numero_contrato}`}
        >
          <ContratoNuevo
            clienteId={overlay.clienteId}
            clienteNombre={overlay.clienteNombre}
            categoriaFija="renovacion"
            renovacionOrigen={{
              // La renovación completa nace de la foto capturada al abrir. Una
              // recarga puede actualizar contratoOverlayActual, pero nunca debe
              // convertir el borrador viejo en una escritura sobre la revisión nueva.
              id: overlay.contrato.id,
              revisionContrato: overlay.contrato.revision_contrato,
              numeroContrato: overlay.contrato.numero_contrato,
              capital: overlay.contrato.capital,
              moneda: overlay.contrato.moneda,
              fechaVencimiento: overlay.contrato.fecha_vencimiento,
            }}
            onConfirmado={(numero, creadoLocal) =>
              setContratoConfirmado(creadoLocal ? { numero, creadoLocal } : { numero })
            }
            onEnviandoCambio={setEnvioEnCurso}
            onCreado={finalizarContratoCreado}
            onOmitir={cerrarContratoNuevo}
          />
        </Dialog>
      )}
      {overlay?.tipo === 'contrato-detalle' && contratoOverlayActual && (
        <Dialog
          open
          onClose={cerrarDetalleContrato}
          ariaLabel={`Detalle del contrato ${contratoOverlayActual.numero_contrato}`}
          className="w-[560px]"
        >
          <ContratoDetalle
            contratoId={contratoOverlayActual.id}
            puedeEliminar={puedeEliminarContratos(yo)}
            onEliminar={async () => {
              const volverACliente = overlay.volverACliente
              await eliminarContratoConPdf(contratoOverlayActual.id)
              limpiarDatosContrato(contratoOverlayActual.id)
              await queryClient.invalidateQueries({
                queryKey: crmQueryKeys.contratos(),
              })
              toast.success(`El contrato ${contratoOverlayActual.numero_contrato} se eliminó correctamente.`)
              setOverlay(
                volverACliente
                  ? {
                      tipo: 'cliente-ficha',
                      clienteId: volverACliente.clienteId,
                      focoInicial: 'inversiones',
                    }
                  : null,
              )
            }}
            onCerrar={cerrarDetalleContrato}
          />
        </Dialog>
      )}
      {overlay?.tipo === 'contrato-corregir' && contratoOverlayActual && !terminosContratoCambiaron && (
        <Dialog
          open
          onClose={cerrarCorreccionContrato}
          ariaLabel={`Corregir contrato ${contratoOverlayActual.numero_contrato}`}
          className="w-[560px]"
        >
          <ContratoCorregir
            contrato={contratoOverlayActual}
            revisionEsperada={overlay.contrato.revision_contrato}
            onGuardado={recargarContratos}
            onCerrar={cerrarCorreccionContrato}
          />
        </Dialog>
      )}
    </>
  )
}

/**
 * Modo DEMO: reusa VistaMiCartera con fixtures ficticios (lib/demo-clientes)
 * cargados por import() dinámico gated → NUNCA toca la API real. El recorte de
 * ámbito que en real hace el servidor lo espeja carteraDelAmbito; los contratos
 * se limitan a los de los clientes visibles. El alta de contrato usa el MISMO
 * formulario, pero materializa contrato, cronograma, titulares y foto legal solo
 * en memoria. Los demás writes siguen bloqueados y todo detalle va precargado.
 */
interface ContratoDemoLocal {
  contrato: ContratoRow
  cuotas: Cuota[]
  titulares: Titular[]
  pdfDatos: ContratoPdfDatos
}

function MiCarteraDemo() {
  const { yo } = useAuth()
  const { ambito, equipo } = useCRMData()
  const [fixtures, setFixtures] = useState<{
    clientes: ClienteBasico[]
    contratos: ContratoRow[]
    detallesClientes: Record<string, ClienteDetalleDatos>
    cronogramas: Record<string, Cuota[]>
    titulares: Record<string, Titular[]>
    pdfDatos: Record<string, ContratoPdfDatos>
    identidadesPdf: Record<string, Omit<ContratoPdfDatos, 'contrato'>>
    cuentasClientes: Record<string, Record<'PEN' | 'USD', CuentaBancariaSeleccionable[]>>
  } | null>(null)
  const [detalleCliente, setDetalleCliente] = useState<{
    datos: ClienteDetalleDatos
    clienteId: string
    focoInicial?: FocoInicialClienteFicha
  } | null>(null)
  const [detalleContrato, setDetalleContrato] = useState<{
    contrato: ContratoRow
    volverACliente?: {
      clienteId: string
      focoInicial: FocoInicialClienteFicha
    }
  } | null>(null)
  const [nuevoContrato, setNuevoContrato] = useState<ClienteBasico | null>(null)
  const [contratosLocales, setContratosLocales] = useState<Record<string, ContratoDemoLocal>>({})
  const [envioContratoEnCurso, setEnvioContratoEnCurso] = useState(false)
  const [contratoConfirmado, setContratoConfirmado] = useState<ContratoConfirmadoParaCierre | null>(null)
  const contratosFinalizadosRef = useRef(new Set<string>())

  useEffect(() => {
    let vivo = true
    if (import.meta.env.VITE_ENABLE_DEMO === 'true' && (import.meta.env.DEV || import.meta.env.MODE === 'preview')) {
      void import('@/lib/demo-clientes').then((m) => {
        if (vivo) {
          setFixtures({
            clientes: m.CLIENTES_DEMO,
            contratos: m.CONTRATOS_DEMO,
            detallesClientes: m.DETALLES_CLIENTES_DEMO,
            cronogramas: m.CRONOGRAMAS_DEMO,
            titulares: m.TITULARES_DEMO,
            pdfDatos: m.DATOS_PDF_DEMO,
            identidadesPdf: m.IDENTIDADES_PDF_DEMO,
            cuentasClientes: m.CUENTAS_CLIENTES_DEMO,
          })
        }
      })
    }
    return () => {
      vivo = false
    }
  }, [])

  const grupos = useMemo(() => {
    if (fixtures == null || yo == null) return null
    const idsVisibles = new Set([yo.id, ...ambito.vendedores.map((m) => m.perfil_id)])
    const clientesVis = carteraDelAmbito(fixtures.clientes, idsVisibles, ambito.esGlobal)
    const idsClientes = new Set(clientesVis.map((c) => c.id))
    const contratosVis = [
      ...fixtures.contratos,
      ...Object.values(contratosLocales).map((local) => local.contrato),
    ].filter((k) => idsClientes.has(k.cliente_id))
    return agruparCartera(clientesVis, contratosVis)
  }, [fixtures, yo, ambito, contratosLocales])

  const tocaReal = () => toast.info('Disponible al ingresar con tu cuenta de trabajo.')
  const abrirDetalleCliente = (contexto: ContextoFichaCliente, focoInicial?: FocoInicialClienteFicha) => {
    const detalle = fixtures?.detallesClientes[contexto.clienteId]
    if (!detalle) {
      toast.error('No se encontraron los datos de demostración de este cliente.')
      return
    }
    setDetalleCliente({
      datos: detalle,
      clienteId: contexto.clienteId,
      ...(focoInicial ? { focoInicial } : {}),
    })
  }
  const cerrarDetalleContratoDemo = () => {
    const volverACliente = detalleContrato?.volverACliente
    setDetalleContrato(null)
    if (!volverACliente) return
    const datos = fixtures?.detallesClientes[volverACliente.clienteId]
    if (!datos) return
    setDetalleCliente({
      datos,
      clienteId: volverACliente.clienteId,
      focoInicial: volverACliente.focoInicial,
    })
  }
  const abrirNuevoContrato = (cliente: ClienteBasico) => {
    if (!fixtures?.identidadesPdf[cliente.id]) {
      toast.error('No se encontraron los datos de demostración necesarios para registrar la inversión.')
      return
    }
    setContratoConfirmado(null)
    setEnvioContratoEnCurso(false)
    setNuevoContrato(cliente)
  }
  const validarNumeroContratoDemo = (numero: string): string | null => {
    const existeEnFixture = fixtures?.contratos.some((contrato) => contrato.numero_contrato === numero) ?? false
    const existeLocal = Object.values(contratosLocales).some((local) => local.contrato.numero_contrato === numero)
    return existeEnFixture || existeLocal
      ? `El contrato ${numero} ya se usó en esta demostración. Escribe un número distinto.`
      : null
  }
  const finalizarContratoDemo = (_numero: string, creadoLocal?: ContratoCreadoLocal) => {
    if (!creadoLocal || !fixtures) {
      toast.error('No se pudo mostrar la inversión en Mi cartera.')
      return
    }
    const cliente = fixtures.clientes.find((fila) => fila.id === creadoLocal.input.cliente_id)
    if (!cliente) {
      toast.error('No se encontraron los datos de demostración del cliente.')
      return
    }
    if (contratosFinalizadosRef.current.has(creadoLocal.id)) {
      setContratoConfirmado(null)
      setEnvioContratoEnCurso(false)
      setNuevoContrato(null)
      return
    }
    const numeroContrato = creadoLocal.input.numero_contrato ?? creadoLocal.pdfDatos.contrato.numero
    if (validarNumeroContratoDemo(numeroContrato)) {
      toast.error(`No se incorporó ${numeroContrato}: ese número ya se usó en esta demostración.`)
      return
    }
    contratosFinalizadosRef.current.add(creadoLocal.id)
    const creadoEn = new Date().toISOString()
    const contrato: ContratoRow = {
      id: creadoLocal.id,
      numero_contrato: numeroContrato,
      cliente_id: creadoLocal.input.cliente_id,
      cliente_nombre: cliente.nombre_completo,
      capital: creadoLocal.input.capital,
      moneda: creadoLocal.input.moneda,
      tasa_anual: creadoLocal.input.tasa_anual,
      modalidad: creadoLocal.input.modalidad,
      tipo_interes: creadoLocal.input.tipo_interes,
      categoria: creadoLocal.input.categoria,
      estado: 'activo',
      fecha_inicio: creadoLocal.input.fecha_inicio,
      fecha_vencimiento: creadoLocal.input.fecha_vencimiento,
      notas_internas: creadoLocal.input.notas_internas ?? null,
      creado_por: yo?.id ?? null,
      creado_en: creadoEn,
      revision_contrato: creadoEn,
      producto_condicion_id: 'demo-condicion-contrato-local',
      producto_id: 'demo-producto-contrato-local',
      producto_codigo: 'DEMO-CONTRATO',
      producto_version_id: 'demo-version-contrato-local',
      producto_version: 1,
      producto_nombre: 'Contrato Demo',
      producto_version_estado: 'publicada',
    }
    const cuotas: Cuota[] = creadoLocal.cronograma.map((cuota) => ({
      ...cuota,
      id: `${creadoLocal.id}-cuota-${cuota.numero_cuota}`,
      fecha_pago_real: null,
      monto_pagado: null,
    }))
    const titulares: Titular[] = (creadoLocal.input.titulares ?? []).map((titular, indice) => ({
      ...titular,
      orden: indice + 1,
    }))
    setContratosLocales((actuales) => ({
      ...actuales,
      [creadoLocal.id]: {
        contrato,
        cuotas,
        titulares,
        pdfDatos: creadoLocal.pdfDatos,
      },
    }))
    setContratoConfirmado(null)
    setEnvioContratoEnCurso(false)
    setNuevoContrato(null)
  }

  const cerrarContratoDemo = () => {
    if (envioContratoEnCurso) return
    if (contratoConfirmado) {
      finalizarContratoDemo(contratoConfirmado.numero, contratoConfirmado.creadoLocal)
      return
    }
    setNuevoContrato(null)
  }
  const grupoFichaDemo = detalleCliente
    ? (grupos?.find((grupo) => grupo.cliente.id === detalleCliente.clienteId) ?? null)
    : null
  const contextoFichaDemo = grupoFichaDemo
    ? resolverContextoFichaCliente({
        grupo: grupoFichaDemo,
        equipo,
        yoId: yo?.id,
        rol: yo?.rol,
        puedeContratar: yo?.puede_contratar === true,
      })
    : null

  return (
    <>
      <VistaMiCartera
        grupos={grupos}
        operaciones={[]}
        desgloseNoDisponible={null}
        demo
        error={null}
        recargaFallida={null}
        yoId={yo?.id ?? null}
        puedeContratar={yo?.puede_contratar === true}
        onNuevoCliente={tocaReal}
        onNuevoContrato={abrirNuevoContrato}
        onGestionarCliente={(contexto) => abrirDetalleCliente(contexto, 'siguiente-contacto')}
        onUpgradeCliente={tocaReal}
        onRenovarContrato={tocaReal}
        onDetalleCliente={abrirDetalleCliente}
        onCorregirCliente={tocaReal}
        onDetalleContrato={(contrato) => setDetalleContrato({ contrato })}
        onCorregirContrato={tocaReal}
      />

      {detalleCliente && grupoFichaDemo && contextoFichaDemo && (
        <Sheet
          open
          onClose={() => setDetalleCliente(null)}
          ariaLabel={`Ficha comercial de ${detalleCliente.datos.nombre_completo || 'cliente'}`}
          className="w-[620px] max-w-full"
        >
          <ClienteFicha
            grupo={grupoFichaDemo}
            asesorNombre={contextoFichaDemo.asesorNombre}
            datos={detalleCliente.datos}
            operable={contextoFichaDemo.operable}
            motivoNoOperable={contextoFichaDemo.motivoNoOperable}
            edicionGlobal={contextoFichaDemo.edicionGlobal}
            focoInicial={detalleCliente.focoInicial}
            puedeVerCuentas={contextoFichaDemo.puedeVerCuentas}
            onCerrar={() => setDetalleCliente(null)}
            onGestionar={contextoFichaDemo.gestionable ? tocaReal : undefined}
            onCorregir={contextoFichaDemo.accionable ? tocaReal : undefined}
            onNuevoContrato={
              contextoFichaDemo.accionable
                ? () => {
                    setDetalleCliente(null)
                    abrirNuevoContrato(grupoFichaDemo.cliente)
                  }
                : undefined
            }
            onUpgrade={contextoFichaDemo.accionable ? tocaReal : undefined}
            onDetalleContrato={(contrato) => {
              setDetalleCliente(null)
              setDetalleContrato({
                contrato,
                volverACliente: {
                  clienteId: grupoFichaDemo.cliente.id,
                  focoInicial: { tipo: 'contrato', contratoId: contrato.id },
                },
              })
            }}
            onRenovarContrato={contextoFichaDemo.accionable ? tocaReal : undefined}
          />
        </Sheet>
      )}

      {nuevoContrato && fixtures?.identidadesPdf[nuevoContrato.id] && (
        <Dialog
          open
          onClose={cerrarContratoDemo}
          ariaLabel={`Registrar nueva inversión de ${nuevoContrato.nombre_completo}`}
        >
          <ContratoNuevo
            clienteId={nuevoContrato.id}
            clienteNombre={nuevoContrato.nombre_completo}
            pdfDatosDemo={fixtures.identidadesPdf[nuevoContrato.id]}
            cuentasDemo={fixtures.cuentasClientes[nuevoContrato.id]}
            validarNumero={validarNumeroContratoDemo}
            onConfirmado={(numero, creadoLocal) =>
              setContratoConfirmado(creadoLocal ? { numero, creadoLocal } : { numero })
            }
            onEnviandoCambio={setEnvioContratoEnCurso}
            onCreado={finalizarContratoDemo}
            onOmitir={cerrarContratoDemo}
          />
        </Dialog>
      )}

      {detalleContrato && (
        <Dialog
          open
          onClose={cerrarDetalleContratoDemo}
          ariaLabel={`Detalle del contrato ${detalleContrato.contrato.numero_contrato}`}
          className="w-[560px]"
        >
          <ContratoDetalle
            contratoId={detalleContrato.contrato.id}
            datos={{
              contrato: detalleContrato.contrato,
              cuotas:
                contratosLocales[detalleContrato.contrato.id]?.cuotas ??
                fixtures?.cronogramas[detalleContrato.contrato.id] ??
                [],
              titulares:
                contratosLocales[detalleContrato.contrato.id]?.titulares ??
                fixtures?.titulares[detalleContrato.contrato.id] ??
                [],
              pdfDatos:
                contratosLocales[detalleContrato.contrato.id]?.pdfDatos ??
                fixtures?.pdfDatos[detalleContrato.contrato.id],
            }}
            onCerrar={cerrarDetalleContratoDemo}
          />
        </Dialog>
      )}
    </>
  )
}
