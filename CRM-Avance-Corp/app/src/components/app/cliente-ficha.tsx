// Ficha comercial 360 del cliente desde Mi cartera. Comparte la jerarquía
// visual de la ficha de Leads, pero conserva su dominio: contratos, capital,
// próxima acción e historial postventa. La RLS sigue siendo la autoridad.
import { useEffect, useMemo, useRef, useState } from 'react'
import {
  CalendarClock,
  FileText,
  History,
  Landmark,
  RotateCcw,
  TrendingUp,
  UserRound,
  WalletCards,
  WifiOff,
} from 'lucide-react'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { SheetBody, SheetFooter } from '@/components/ui/sheet'
import {
  CuentasClienteMoneda,
  DatoCliente as Dato,
  DatoClienteCopiable,
} from '@/components/app/cliente-cuentas-vista'
import {
  cuentaClienteDesdeRpc,
  cuentasClienteEmbebidas,
  valorCliente as valor,
} from '@/lib/cliente-cuentas-modelo'
import {
  FichaComercialCabecera,
  FichaComercialContacto,
  FichaComercialInversion,
  FichaComercialHistorial,
  FichaComercialContinuidad,
  FichaComercialSeccion,
  FichaComercialSeccionPlegable,
} from '@/components/app/ficha-comercial'
import { CrmApiError, mensajeDeError } from '@/data/crm-api'
import { useActividadesCliente, useClienteFichaComercial, useCuentasBancariasCliente, useHistorialTasaCliente } from '@/data/crm-queries'
import { tasaTxt } from '@/lib/rentabilidad'
import { TIPOS_DOCUMENTO } from '@/lib/documento'
import { fechaHora, money } from '@/lib/format'
import { AYUDA_UPGRADE, CATEGORIA_LABEL, ESTADO_COLOR, ESTADO_CONTRATO_LABEL, ETIQUETA_UPGRADE, MOTIVO_NUEVA_INVERSION_BLOQUEADA } from '@/lib/contratos-catalogo'
import { tareaAEvento } from '@/lib/agenda-derivada'
import { useAhora } from '@/lib/ahora'
import { construirVistaCliente360, type VistaCliente360 } from '@/lib/cliente-ficha-modelo'
import { useCRMData } from '@/lib/store-context'
import { useVentana } from '@/lib/ventana'
import type { GrupoCartera } from '@/lib/cartera-vista'
import type {
  ClienteDetalle as ClienteDetalleDatos,
  ClienteFichaComercial,
  ContratoRow,
  OperacionCartera,
} from '@/lib/clientes-tipos'

export type FocoInicialClienteFicha = 'siguiente-contacto' | 'inversiones' | { tipo: 'contrato'; contratoId: string }

export interface ClienteFichaProps {
  grupo: GrupoCartera
  analistaNombre: string | null
  onCerrar: () => void
  /** Cierra y purga la cartera cuando el servidor confirma que ya no pertenece al ámbito actual. */
  onAccesoRevocado?: ((clienteId: string) => void) | undefined
  /** Actualiza la cartera si la ficha confirma un analista o estado más reciente que la lista. */
  onAsignacionDesactualizada?: ((clienteId: string) => void) | undefined
  /** Fixture completo para la sesión demo. Deshabilita la consulta remota. */
  datos?: ClienteDetalleDatos
  /** Renovaciones y aumentos del cliente, ya recortados al ámbito visible. */
  operaciones?: OperacionCartera[]
  /** La primera lectura de renovaciones y aumentos todavía está en curso. */
  movimientosInversionPendientes?: boolean | undefined
  /** Avisa si no se pudo confirmar la parte económica del historial. */
  movimientosInversionDesactualizados?: { reintentar: () => void; actualizando?: boolean } | null | undefined
  /** Las callbacks existen solo cuando el rol y la fila permiten esa acción. */
  onGestionar?: (() => void) | undefined
  onCorregir?: (() => void) | undefined
  onNuevoContrato?: (() => void) | undefined
  onUpgrade?: (() => void) | undefined
  onDetalleContrato?: ((contrato: ContratoRow) => void) | undefined
  onRenovarContrato?: ((contrato: ContratoRow) => void) | undefined
  operable?: boolean
  motivoNoOperable?: string | null
  edicionGlobal?: boolean
  /** Devuelve el foco al punto comercial que originó una navegación secundaria. */
  focoInicial?: FocoInicialClienteFicha | undefined
  /** Directorio consulta la ficha, pero la banca queda reservada al equipo operativo. */
  puedeVerCuentas?: boolean
  /** Directorio audita identidad y datos, sin iniciar llamadas, WhatsApp ni correo. */
  puedeContactar?: boolean
  /** Marca persistente para que una ficha abierta no parezca una sesión de trabajo real. */
  demo?: boolean
  datosCarteraDesactualizados?: { reintentar: () => void } | null | undefined
}

interface EventoHistorialCliente {
  id: string
  titulo: string
  detalle: string | null
  creadoEn: string
}

const ACTIVIDAD_LABEL = {
  llamada_realizada: 'Llamada contestada',
  llamada_no_contestada: 'Llamada no contestada',
  whatsapp_enviado: 'WhatsApp enviado',
  whatsapp_recibido: 'WhatsApp respondido',
  reunion_realizada: 'Reunión realizada',
  nota: 'Nota comercial',
  reasignacion: 'Asignación actualizada',
} as const

function fechaCorta(iso: string | null): string {
  if (!iso) return 'Sin vencimiento próximo'
  const [anio, mes, dia] = iso.split('-').map(Number)
  if (!anio || !mes || !dia) return 'Fecha por revisar'
  return new Date(Date.UTC(anio, mes - 1, dia)).toLocaleDateString('es-PE', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    timeZone: 'UTC',
  })
}

function CapitalVigente({ vista }: { vista: VistaCliente360 }) {
  if (!vista.tieneCapital) return <span className="text-sm font-bold text-muted-foreground">Sin capital vigente</span>
  return (
    <span className="flex flex-wrap gap-x-2 text-sm font-extrabold tabular-nums text-primary">
      {vista.capitalVigente.PEN > 0 && <span>{money(vista.capitalVigente.PEN, 'PEN')}</span>}
      {vista.capitalVigente.USD > 0 && <span>{money(vista.capitalVigente.USD, 'USD')}</span>}
    </span>
  )
}

/** Firma visual de la ficha: dinero, vencimiento y siguiente contacto en un solo recorrido. */
function RielContinuidad({
  vista,
  ahora,
  puedeAgendar,
}: {
  vista: VistaCliente360
  ahora: number
  puedeAgendar: boolean
}) {
  const proxima = vista.proximaTarea
  const evento = proxima ? tareaAEvento(proxima, ahora) : null
  const vencimientoPendiente = vista.proximoVencimiento != null && vista.proximoVencimiento <= vista.hoyLima
  const items = [
    {
      etiqueta: 'Capital vigente',
      contenido: <CapitalVigente vista={vista} />,
      ayuda: vista.contratosActivos === 1 ? '1 contrato vigente' : `${vista.contratosActivos} contratos vigentes`,
    },
    {
      etiqueta: vencimientoPendiente ? 'Renovación pendiente' : 'Próximo vencimiento',
      contenido: <span className="text-sm font-extrabold text-foreground">{fechaCorta(vista.proximoVencimiento)}</span>,
      ayuda: vencimientoPendiente
        ? 'El siguiente paso para mantener activa la relación'
        : vista.proximoVencimiento
          ? 'Oportunidad para anticipar la renovación'
          : 'Sin renovación inmediata',
    },
    {
      etiqueta: 'Siguiente contacto',
      contenido: (
        <span className="text-sm font-extrabold text-foreground">{evento?.cuando ?? 'Sin contacto programado'}</span>
      ),
      ayuda:
        proxima?.titulo ??
        (puedeAgendar ? 'Agenda una acción para mantener la relación activa' : 'Sin seguimiento programado'),
    },
  ]

  return <FichaComercialContinuidad items={items} />
}

/**
 * Ficha comercial completa. Las cuentas mantienen el contrato de frescura
 * previo; los contratos y el capital llegan del mismo grupo ya scopeado que
 * pinta Mi cartera. Las acciones solo se muestran cuando el caller las autoriza.
 */
export function ClienteFicha({
  grupo,
  analistaNombre,
  onCerrar,
  onAccesoRevocado,
  onAsignacionDesactualizada,
  datos,
  operaciones = [],
  movimientosInversionPendientes = false,
  movimientosInversionDesactualizados = null,
  onGestionar,
  onCorregir,
  onNuevoContrato,
  onUpgrade,
  onDetalleContrato,
  onRenovarContrato,
  operable = true,
  motivoNoOperable = null,
  edicionGlobal = false,
  focoInicial,
  puedeVerCuentas = true,
  puedeContactar = true,
  demo = false,
  datosCarteraDesactualizados = null,
}: ClienteFichaProps) {
  const clienteId = grupo.cliente.id
  const motivoNoOperableId = `cliente-ficha-no-operable-${clienteId}`
  const precargado = datos !== undefined
  const ahora = useAhora()
  const siguienteContactoRef = useRef<HTMLElement>(null)
  const inversionesRef = useRef<HTMLElement>(null)
  const informacionRef = useRef<HTMLElement>(null)
  const historialRef = useRef<HTMLElement>(null)
  const cuentasRef = useRef<HTMLElement>(null)
  const botonesContratoRef = useRef(new Map<string, HTMLButtonElement>())
  const focoTrasDetalle = useRef(false)
  const focoTrasCuentas = useRef(false)
  const focoTrasHistorial = useRef(false)
  const focoTrasMovimientos = useRef(false)
  const focoTrasCartera = useRef(false)
  const focoInicialAplicado = useRef(false)
  const asignacionAvisadaRef = useRef<string | null>(null)
  const [detalleConfirmado, setDetalleConfirmado] = useState<{
    clienteId: string
    datos: ClienteFichaComercial
  } | null>(null)
  const [cuentasAbiertas, setCuentasAbiertas] = useState(false)
  const { tareasDeCliente } = useCRMData()
  const vista = construirVistaCliente360(grupo, tareasDeCliente?.(clienteId) ?? [], ahora)
  const tareasPendientes = vista.tareasPendientes
  const ventanaCliente = useVentana(onCorregir && !edicionGlobal ? grupo.cliente.creado_en : null)
  const qDetalle = useClienteFichaComercial(clienteId, !precargado)

  const accesoRevocado =
    !precargado &&
    qDetalle.isError &&
    qDetalle.error instanceof CrmApiError &&
    (qDetalle.error.code === 'NO_ENCONTRADO' || qDetalle.error.code === '42501')

  // Una copia que ya estaba en TanStack antes de abrir la ficha jamás se usa.
  // Solo una respuesta exitosa obtenida durante ESTA apertura pasa a ser la
  // última fotografía confirmada. Un fallo transitorio posterior la conserva
  // con aviso para no desmontar la ficha ni perder foco/scroll; una revocación
  // la oculta en el mismo render.
  useEffect(() => {
    if (precargado || !qDetalle.isSuccess || !qDetalle.isFetchedAfterMount || qDetalle.data == null) return
    const datosFrescos = qDetalle.data
    setDetalleConfirmado((anterior) =>
      anterior?.clienteId === clienteId && anterior.datos === datosFrescos
        ? anterior
        : { clienteId, datos: datosFrescos },
    )
  }, [clienteId, precargado, qDetalle.data, qDetalle.isFetchedAfterMount, qDetalle.isSuccess])

  const detalleRemoto = !accesoRevocado && detalleConfirmado?.clienteId === clienteId ? detalleConfirmado.datos : null
  const detalle = datos ?? detalleRemoto
  // La ficha trae la asignación y el estado actuales del servidor. Si difieren
  // de la lista que abrió el panel, se espera a que Mi cartera se actualice:
  // así el nombre del analista, las insignias y los botones nunca nacen de una
  // fotografía anterior.
  const asignacionDesactualizada =
    !precargado &&
    detalleRemoto != null &&
    (detalleRemoto.asesor_perfil_id !== grupo.cliente.asesor_perfil_id || detalleRemoto.activo !== grupo.cliente.activo)
  const accesoConfirmado = detalle != null && !asignacionDesactualizada

  useEffect(() => {
    if (!asignacionDesactualizada || detalleRemoto == null) {
      asignacionAvisadaRef.current = null
      return
    }
    const firma = `${clienteId}:${detalleRemoto.asesor_perfil_id ?? 'sin-analista'}:${detalleRemoto.activo}`
    if (asignacionAvisadaRef.current === firma) return
    asignacionAvisadaRef.current = firma
    onAsignacionDesactualizada?.(clienteId)
  }, [asignacionDesactualizada, clienteId, detalleRemoto, onAsignacionDesactualizada])

  // Historial y cuentas solo se solicitan después de una confirmación remota
  // de esta apertura y mientras la asignación coincide con la lista visible.
  // Las cuentas salen de la MISMA RPC del flujo de contrato (ledger
  // crm.cuentas_bancarias + casilla vigente del perfil, deduplicados por el
  // servidor): es la única fuente que incluye las cuentas registradas AL CREAR
  // un contrato — leer solo las columnas embebidas de perfiles las escondía.
  const qPen = useCuentasBancariasCliente(clienteId, 'PEN', puedeVerCuentas && !precargado && accesoConfirmado)
  const qUsd = useCuentasBancariasCliente(clienteId, 'USD', puedeVerCuentas && !precargado && accesoConfirmado)
  const qActividades = useActividadesCliente(clienteId, !precargado && accesoConfirmado)

  // Rentabilidad R3: qué tasa quedó frente a la que dice la política, por contrato (ledger del servidor).
  const historialTasa = useHistorialTasaCliente(grupo.cliente.id, !demo && grupo.contratos.length > 0)
  const observacionPorContrato = useMemo(() => {
    const mapa = new Map<string, NonNullable<NonNullable<typeof historialTasa.data>['contratos'][number]['observacion']>>()
    for (const c of historialTasa.data?.contratos ?? []) if (c.observacion) mapa.set(c.contrato_id, c.observacion)
    return mapa
  }, [historialTasa.data])
  const solicitudesTasaVivas = useMemo(
    () => (historialTasa.data?.solicitudes ?? []).filter((s) => s.vigente),
    [historialTasa.data],
  )
  const eventosHistorial = useMemo(() => {
    const contratosPorId = new Map(grupo.contratos.map((contrato) => [contrato.id, contrato]))
    const eventos: EventoHistorialCliente[] = (qActividades.data ?? []).map((actividad) => ({
      id: `actividad-${actividad.id}`,
      titulo: ACTIVIDAD_LABEL[actividad.tipo],
      detalle: actividad.detalle,
      creadoEn: actividad.creado_en,
    }))
    for (const operacion of operaciones) {
      if (operacion.cliente_id !== clienteId) continue
      const contratoNuevo = contratosPorId.get(operacion.contrato_nuevo_id)
      let detalleOperacion: string
      if (operacion.tipo === 'renovacion') {
        if (!operacion.desglose_completo) {
          detalleOperacion = 'Renovación anterior. El detalle de los montos no está disponible.'
        } else {
          const partes: string[] = []
          if (operacion.capital_renovado != null) {
            partes.push(`Capital renovado: ${money(operacion.capital_renovado, operacion.moneda)}`)
          }
          if (operacion.capital_adicional != null && operacion.capital_adicional > 0) {
            partes.push(`Aporte adicional: ${money(operacion.capital_adicional, operacion.moneda)}`)
          }
          detalleOperacion = partes.length > 0 ? partes.join(' · ') : 'Se registró la renovación de la inversión.'
        }
      } else {
        detalleOperacion = contratoNuevo
          ? `Nueva inversión registrada: ${money(contratoNuevo.capital, contratoNuevo.moneda)}`
          : 'Se registró un aumento de inversión.'
      }
      eventos.push({
        id: `operacion-${operacion.id}`,
        titulo: operacion.tipo === 'renovacion' ? 'Renovación registrada' : 'Aumento de inversión registrado',
        detalle: detalleOperacion,
        creadoEn: operacion.creado_en,
      })
    }
    return eventos.sort((a, b) => b.creadoEn.localeCompare(a.creadoEn) || a.id.localeCompare(b.id))
  }, [clienteId, grupo.contratos, operaciones, qActividades.data])

  // Las cuentas aplican la misma regla y se muestran como una sola fotografía:
  // ambas monedas deben haber terminado de actualizarse después de la apertura.
  // Limitación aceptada (auditoría Codex 2026-08-11): PEN y USD son dos RPC
  // independientes, no una fotografía transaccional — una corrección concurrente
  // entre ambas respuestas puede mezclar monedas de dos versiones. Ventana de
  // milisegundos y ambas copias post-montaje; unificar exigiría una RPC conjunta.
  const cuentasConfirmadas =
    !precargado &&
    puedeVerCuentas &&
    qPen.isSuccess &&
    qPen.isFetchedAfterMount &&
    qUsd.isSuccess &&
    qUsd.isFetchedAfterMount
      ? { pen: qPen.data.map(cuentaClienteDesdeRpc), usd: qUsd.data.map(cuentaClienteDesdeRpc) }
      : null

  const errorDetalle =
    !precargado && qDetalle.isError ? mensajeDeError(qDetalle.error, 'No se pudo cargar el detalle del cliente.') : null
  const errorApertura = detalleRemoto == null ? errorDetalle : null
  const errorActualizacion = detalleRemoto != null && !accesoRevocado ? errorDetalle : null

  const reintentar = () => {
    focoTrasDetalle.current = true
    void qDetalle.refetch()
  }

  const cuentasPen = datos !== undefined ? cuentasClienteEmbebidas(datos, 'PEN') : (cuentasConfirmadas?.pen ?? null)
  const cuentasUsd = datos !== undefined ? cuentasClienteEmbebidas(datos, 'USD') : (cuentasConfirmadas?.usd ?? null)
  // El fallo de las cuentas degrada SOLO su sección (identidad y contacto
  // siguen visibles): vienen de consultas distintas y un fallo operativo del
  // lado bancario (red, RPC, permisos si el gating de fila cambiara) no debe
  // secuestrar una ficha cuya identidad ya está confirmada.
  const cuentasError =
    !precargado && puedeVerCuentas && (qPen.isError || qUsd.isError)
      ? mensajeDeError(qPen.error ?? qUsd.error, 'No se pudieron cargar las cuentas bancarias.')
      : null
  // Con el reintento EN VUELO se muestra la carga, no el alert: así el usuario
  // ve que algo pasa y, si vuelve a fallar, el alert se re-monta y el lector de
  // pantalla lo re-anuncia (un role="alert" que no cambia no se vuelve a leer).
  const cuentasReintentando =
    !precargado && puedeVerCuentas && (qPen.isError || qUsd.isError) && (qPen.isFetching || qUsd.isFetching)

  useEffect(() => {
    if (cuentasError) setCuentasAbiertas(true)
  }, [cuentasError])

  const reintentarCuentas = () => {
    focoTrasCuentas.current = true
    void qPen.refetch()
    void qUsd.refetch()
  }

  // Clientes migrados ANTES de separar nombres/apellidos: solo tienen
  // nombre_completo (mismo criterio esLegacySinSeparar del form de corregir).
  // Sin esto, la ficha mostraba «—» en Nombres y Apellidos con el nombre a la vista.
  const sinSeparar =
    detalle != null && !detalle.nombres?.trim() && !detalle.apellidos?.trim() && detalle.nombre_completo.trim() !== ''

  const nombre = detalle?.nombre_completo || grupo.cliente.nombre_completo || 'Cliente'

  useEffect(() => {
    if (!accesoConfirmado || focoInicial == null || focoInicialAplicado.current) return
    // Radix difiere el autofocus de cierre del overlay anterior a un macrotask.
    // Dos frames colocan este retorno después de ese desmontaje y del autofocus
    // de apertura de la ficha nueva, ya con el destino conectado al DOM.
    let segundoCuadro = 0
    const primerCuadro = window.requestAnimationFrame(() => {
      segundoCuadro = window.requestAnimationFrame(() => {
        const destino =
          focoInicial === 'siguiente-contacto'
            ? siguienteContactoRef.current
            : focoInicial === 'inversiones'
              ? inversionesRef.current
              : (botonesContratoRef.current.get(focoInicial.contratoId) ?? inversionesRef.current)
        if (!destino?.isConnected) return
        destino.focus({ preventScroll: true })
        // El Sheet se remonta con su scroll interno en el inicio. Conservar el
        // foco semántico no basta si el destino queda debajo del viewport (se
        // veía en móvil y quedaba completamente oculto en landscape). El
        // desplazamiento mínimo mantiene visible el punto al que volvió el
        // teclado sin mover innecesariamente el resto de la ficha.
        destino.scrollIntoView?.({ block: 'nearest', inline: 'nearest' })
        focoInicialAplicado.current = document.activeElement === destino
      })
    })
    return () => {
      window.cancelAnimationFrame(primerCuadro)
      window.cancelAnimationFrame(segundoCuadro)
    }
  }, [accesoConfirmado, focoInicial])

  useEffect(() => {
    if (!focoTrasDetalle.current || detalle == null || qDetalle.isFetching) return
    focoTrasDetalle.current = false
    informacionRef.current?.focus()
  }, [detalle, qDetalle.isFetching])

  useEffect(() => {
    if (!focoTrasCuentas.current || cuentasPen == null || cuentasUsd == null || cuentasReintentando) return
    focoTrasCuentas.current = false
    cuentasRef.current?.focus()
  }, [cuentasPen, cuentasUsd, cuentasReintentando])

  useEffect(() => {
    if (!focoTrasHistorial.current || qActividades.isFetching || !qActividades.isSuccess) return
    focoTrasHistorial.current = false
    historialRef.current?.focus()
  }, [qActividades.isFetching, qActividades.isSuccess])

  useEffect(() => {
    if (!focoTrasMovimientos.current || movimientosInversionDesactualizados != null) return
    focoTrasMovimientos.current = false
    historialRef.current?.focus()
  }, [movimientosInversionDesactualizados])

  useEffect(() => {
    if (!focoTrasCartera.current || datosCarteraDesactualizados != null) return
    focoTrasCartera.current = false
    siguienteContactoRef.current?.focus()
  }, [datosCarteraDesactualizados])

  useEffect(() => {
    if (!accesoRevocado) return
    onAccesoRevocado?.(clienteId)
  }, [accesoRevocado, clienteId, onAccesoRevocado])

  if (!accesoConfirmado) {
    return (
      <>
        <FichaComercialCabecera
          avatar={<Avatar nombre={nombre} className="size-10 max-[359px]:hidden" />}
          titulo={nombre}
          onCerrar={onCerrar}
        />
        <SheetBody className="space-y-4">
          {asignacionDesactualizada ? (
            <div
              className="flex flex-col items-center justify-center gap-3 rounded-xl border border-primary/20 bg-primary/[0.035] p-5 text-center"
              role="status"
            >
              <span className="grid size-11 place-items-center rounded-2xl bg-primary/10 text-primary">
                <RotateCcw className="size-5 animate-spin" aria-hidden />
              </span>
              <div className="space-y-1">
                <p className="text-sm font-semibold text-foreground">
                  Estamos actualizando la asignación de este cliente.
                </p>
                <p className="text-xs text-muted-foreground">
                  Espera un momento mientras confirmamos quién debe atenderlo.
                </p>
              </div>
              {onAsignacionDesactualizada && (
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  className="min-h-10"
                  onClick={() => onAsignacionDesactualizada(clienteId)}
                >
                  <RotateCcw aria-hidden /> Actualizar ahora
                </Button>
              )}
            </div>
          ) : errorApertura ? (
            <div
              className="flex flex-col items-center justify-center gap-3 rounded-xl border border-border bg-muted/30 p-5 text-center"
              role="alert"
            >
              <span className="grid size-11 place-items-center rounded-2xl bg-destructive/10 text-destructive">
                <WifiOff className="size-5" aria-hidden />
              </span>
              <p className="text-sm font-semibold text-foreground">{errorApertura}</p>
              {!accesoRevocado && (
                <Button variant="outline" size="sm" className="min-h-10" onClick={reintentar}>
                  <RotateCcw aria-hidden /> Reintentar
                </Button>
              )}
            </div>
          ) : (
            <div className="space-y-3" aria-busy>
              <span className="sr-only">Actualizando la información del cliente</span>
              <Skeleton className="h-28 w-full" />
              <Skeleton className="h-20 w-full" />
              <Skeleton className="h-32 w-full" />
            </div>
          )}
        </SheetBody>
        <SheetFooter>
          <Button type="button" variant="outline" className="min-h-11" onClick={onCerrar}>
            Cerrar
          </Button>
        </SheetFooter>
      </>
    )
  }

  return (
    <>
      <FichaComercialCabecera
        avatar={<Avatar nombre={nombre} className="size-10 max-[359px]:hidden" />}
        titulo={nombre}
        badges={
          <>
            <Badge color={grupo.cliente.activo ? 'var(--accent)' : 'var(--muted-foreground)'} dot>
              {grupo.cliente.activo ? 'Cliente activo' : 'Cliente inactivo'}
            </Badge>
            {demo && <Badge color="var(--chart-4)">Vista demo</Badge>}
            <Badge color="var(--primary)">
              {analistaNombre ? `Analista · ${analistaNombre}` : 'Sin analista asignado'}
            </Badge>
          </>
        }
        resumen={
          <div className="hidden shrink-0 text-right leading-tight sm:block">
            <p className="text-sm font-extrabold tabular-nums text-primary">{vista.contratosActivos}</p>
            <p className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
              {vista.contratosActivos === 1 ? 'contrato vigente' : 'contratos vigentes'}
            </p>
          </div>
        }
        acciones={
          detalle && puedeContactar ? (
            <FichaComercialContacto nombre={nombre} telefono={detalle.telefono} correo={detalle.correo} />
          ) : undefined
        }
        onCerrar={onCerrar}
      />

      <SheetBody className="space-y-6">
        <RielContinuidad vista={vista} ahora={ahora} puedeAgendar={onGestionar != null && operable} />

        {errorActualizacion && (
          <div
            className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-warning/30 bg-warning/10 px-3 py-2.5"
            role="status"
          >
            <p className="text-xs font-semibold text-warning-text">
              No pudimos actualizar la ficha. Estás viendo la última información confirmada.
            </p>
            <Button
              type="button"
              size="sm"
              variant="outline"
              className="min-h-10"
              onClick={reintentar}
              disabled={qDetalle.isFetching}
            >
              <RotateCcw aria-hidden /> {qDetalle.isFetching ? 'Actualizando…' : 'Actualizar'}
            </Button>
          </div>
        )}

        {datosCarteraDesactualizados && (
          <div
            className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-warning/30 bg-warning/10 px-3 py-2.5"
            role="status"
          >
            <p className="text-xs font-semibold text-warning-text">
              No pudimos actualizar el capital y los vencimientos. Estás viendo los últimos datos disponibles.
            </p>
            <Button
              type="button"
              size="sm"
              variant="outline"
              className="min-h-10"
              onClick={() => {
                focoTrasCartera.current = true
                datosCarteraDesactualizados.reintentar()
              }}
            >
              <RotateCcw aria-hidden /> Actualizar
            </Button>
          </div>
        )}

        {!operable && motivoNoOperable && (
          <div
            id={motivoNoOperableId}
            className="rounded-xl border border-warning/30 bg-warning/10 px-3 py-2.5 text-xs font-semibold text-warning-text"
            role="status"
          >
            {motivoNoOperable}
          </div>
        )}

        <FichaComercialSeccion
          icono={CalendarClock}
          titulo="Seguimiento"
          descripcion="Acciones pendientes para mantener activa la relación."
          sectionRef={siguienteContactoRef}
        >
          {tareasPendientes.length === 0 ? (
            <p className="rounded-xl border border-dashed border-border px-3 py-4 text-center text-xs text-muted-foreground">
              {onGestionar && operable ? 'Sin acciones pendientes. Puedes agendar el próximo seguimiento.' : 'Sin acciones pendientes.'}
            </p>
          ) : (
            <ol className="space-y-2">
              {tareasPendientes.slice(0, 3).map((tarea) => {
                const evento = tareaAEvento(tarea, ahora)
                return (
                  <li
                    key={tarea.id}
                    className="flex items-start gap-3 rounded-xl border border-border bg-muted/20 px-3 py-2.5"
                  >
                    <span className="mt-0.5 size-2 shrink-0 rounded-full bg-accent" aria-hidden />
                    <div className="min-w-0 flex-1">
                      <p className="line-clamp-2 text-xs font-bold text-foreground">{tarea.titulo}</p>
                      <p className="mt-0.5 text-[11px] font-semibold text-muted-foreground">{evento.cuando}</p>
                    </div>
                  </li>
                )
              })}
            </ol>
          )}
          {tareasPendientes.length > 3 && (
            <p className="text-center text-[11px] font-semibold text-muted-foreground">
              Y {tareasPendientes.length - 3} seguimiento{tareasPendientes.length - 3 === 1 ? '' : 's'} más en Agenda.
            </p>
          )}
        </FichaComercialSeccion>

        <FichaComercialSeccion
          icono={WalletCards}
          titulo="Inversiones y contratos"
          descripcion="Capital vigente, vencimientos y oportunidades para renovar o registrar un upgrade."
          sectionRef={inversionesRef}
          accion={
            onNuevoContrato || (onUpgrade && grupo.contratos.length > 0) ? (
              <div className="flex flex-wrap justify-end gap-1.5 sm:flex-nowrap sm:shrink-0">
                {onUpgrade && grupo.contratos.length > 0 && (
                  <Button
                    type="button"
                    size="xs"
                    variant="outline"
                    className="min-h-10"
                    onClick={onUpgrade}
                    disabled={!operable}
                    title={AYUDA_UPGRADE}
                    aria-describedby={!operable ? motivoNoOperableId : undefined}
                  >
                    <TrendingUp aria-hidden /> {ETIQUETA_UPGRADE}
                  </Button>
                )}
                {onNuevoContrato && (
                  <Button
                    type="button"
                    size="xs"
                    className="min-h-10"
                    onClick={onNuevoContrato}
                    disabled={!operable || grupo.contratos.length > 0}
                    aria-describedby={[!operable ? motivoNoOperableId : '', grupo.contratos.length > 0 ? `${clienteId}-continuidad-inversion` : ''].filter(Boolean).join(' ') || undefined}
                  >
                    {grupo.contratos.length === 0 ? 'Registrar primera inversión' : 'Registrar nueva inversión'}
                  </Button>
                )}
              </div>
            ) : undefined
          }
        >
          {grupo.contratos.length === 0 ? (
            <p className="rounded-xl border border-dashed border-border px-3 py-4 text-center text-xs text-muted-foreground">
              Este cliente todavía no tiene una inversión registrada.
            </p>
          ) : (
            <>
            {onNuevoContrato && <p id={`${clienteId}-continuidad-inversion`} className="pb-2 text-xs text-muted-foreground">{MOTIVO_NUEVA_INVERSION_BLOQUEADA}</p>}
            {onUpgrade && (
              <p className="pb-2 text-[11px] leading-relaxed text-muted-foreground">{AYUDA_UPGRADE}</p>
            )}
            {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
            <ol role="list" className="space-y-2" aria-label="Contratos del cliente">
              {vista.contratos.map(({ contrato, renovable: llegoFechaFin }) => {
                const renovable = operable && onRenovarContrato != null && llegoFechaFin
                return (
                  <li key={contrato.id}>
                    <FichaComercialInversion
                      badges={<>
                        <Badge color={ESTADO_COLOR[contrato.estado]} dot>{ESTADO_CONTRATO_LABEL[contrato.estado]}</Badge>
                        {contrato.categoria && <Badge color="var(--chart-4)">{CATEGORIA_LABEL[contrato.categoria]}</Badge>}
                      </>}
                      titulo={contrato.producto_nombre}
                      referencia={<>Contrato {contrato.numero_contrato} · Vencimiento: {fechaCorta(contrato.fecha_vencimiento)}</>}
                      capital={money(contrato.capital, contrato.moneda)}
                      observacion={(() => {
                          const obs = observacionPorContrato.get(contrato.id)
                          if (!obs) return null
                          const puntos = obs.tasa_final - obs.tasa_base
                          return (
                            <p className="mt-0.5 text-[11px] tabular-nums text-muted-foreground" data-testid={`tasa-politica-${contrato.id}`}>
                              Tasa {tasaTxt(obs.tasa_final)}
                              {obs.regla === 'historica_legacy'
                                ? ' · anterior a la política'
                                : obs.regla === 'sin_regla'
                                  ? ' · la política no define este caso'
                                  : obs.divergente
                                    ? <> · base {tasaTxt(obs.tasa_base)} ({puntos > 0 ? '+' : ''}{puntos.toLocaleString('es-PE', { maximumFractionDigits: 2 })} <abbr title="puntos" className="no-underline">pts</abbr>{obs.solicitud_id ? ', autorizada por Gerencia' : ', sin autorización'})</>
                                    : ' · en la base de la política'}
                            </p>
                          )
                        })()}
                      acciones={<>
                      {onDetalleContrato && (
                        <Button
                          ref={(elemento) => {
                            if (elemento) botonesContratoRef.current.set(contrato.id, elemento)
                            else botonesContratoRef.current.delete(contrato.id)
                          }}
                          type="button"
                          size="xs"
                          variant="outline"
                          className="min-h-10"
                          onClick={() => onDetalleContrato(contrato)}
                          aria-label={`Ver contrato ${contrato.numero_contrato}`}
                        >
                          <FileText aria-hidden /> Ver contrato
                        </Button>
                      )}
                      {renovable && (
                        <Button
                          type="button"
                          size="xs"
                          className="min-h-10"
                          onClick={() => onRenovarContrato(contrato)}
                          aria-label={`Renovar inversión del contrato ${contrato.numero_contrato}`}
                        >
                          Renovar inversión
                        </Button>
                      )}
                      </>}
                    />
                  </li>
                )
              })}
            </ol>
            </>
          )}
          {solicitudesTasaVivas.length > 0 && (
            <p className="mt-2 text-[11px] text-muted-foreground" data-testid="solicitudes-tasa-cliente">
              {solicitudesTasaVivas.length === 1 ? 'Hay una solicitud de tasa en curso' : `Hay ${solicitudesTasaVivas.length} solicitudes de tasa en curso`} para este cliente
              {' '}({solicitudesTasaVivas.map((sol) => `${tasaTxt(sol.tasa_solicitada)} ${sol.estado_efectivo === 'pendiente' ? 'pendiente' : sol.estado_efectivo === 'aprobada_con_tope' ? `con tope ${tasaTxt(sol.tasa_maxima_autorizada ?? 0)}` : `autorizada hasta ${tasaTxt(sol.tasa_maxima_autorizada ?? 0)}`}`).join(' · ')}).
            </p>
          )}
        </FichaComercialSeccion>

        <FichaComercialSeccion
          icono={UserRound}
          titulo="Información del cliente"
          descripcion="Datos para reconocerlo y contactarlo correctamente."
          sectionRef={informacionRef}
          accion={
            onCorregir && detalle && (edicionGlobal || ventanaCliente.vigente) ? (
              <Button
                type="button"
                size="xs"
                variant="outline"
                className="min-h-10"
                onClick={onCorregir}
                disabled={!operable}
                aria-describedby={!operable ? motivoNoOperableId : undefined}
              >
                Corregir datos
              </Button>
            ) : undefined
          }
        >
          {!detalle ? (
            <div className="space-y-2" aria-busy>
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-24 w-full" />
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-3 rounded-xl border border-border bg-muted/20 p-3 sm:grid-cols-3">
              {sinSeparar ? (
                <Dato etiqueta="Nombres y apellidos">{valor(detalle.nombre_completo)}</Dato>
              ) : (
                <>
                  <Dato etiqueta="Nombres">{valor(detalle.nombres)}</Dato>
                  <Dato etiqueta="Apellidos">{valor(detalle.apellidos)}</Dato>
                </>
              )}
              <Dato etiqueta={TIPOS_DOCUMENTO[detalle.tipo_documento].etiqueta}>{valor(detalle.dni)}</Dato>
              <DatoClienteCopiable etiqueta="Correo" valor={detalle.correo} className="col-span-2 sm:col-span-2" />
              <Dato etiqueta="Teléfono">{valor(detalle.telefono)}</Dato>
              <Dato etiqueta="Registrado el">{fechaHora(detalle.creado_en)}</Dato>
            </div>
          )}
        </FichaComercialSeccion>

        <FichaComercialSeccion
          icono={History}
          titulo="Historial de gestiones"
          descripcion="Contactos, cambios de analista y movimientos de inversión para retomar la relación con contexto."
          sectionRef={historialRef}
        >
          {precargado ? (
            <p className="text-xs text-muted-foreground">
              El historial de gestiones estará disponible al ingresar con tu cuenta de trabajo.
            </p>
          ) : (
            <div className="space-y-3">
              {(qActividades.isPending || movimientosInversionPendientes) && eventosHistorial.length === 0 && (
                <div className="space-y-2" aria-busy>
                  <Skeleton className="h-12 w-full" />
                  <Skeleton className="h-12 w-full" />
                </div>
              )}
              {(qActividades.isPending || movimientosInversionPendientes) && eventosHistorial.length > 0 && (
                <p className="text-xs text-muted-foreground" role="status">
                  Actualizando el historial del cliente…
                </p>
              )}
              {qActividades.isError && (
                <div
                  className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border bg-muted/30 p-3"
                  role="alert"
                >
                  <p className="text-xs font-semibold text-foreground">
                    No pudimos actualizar las conversaciones. Los demás movimientos siguen visibles.
                  </p>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    className="min-h-10"
                    onClick={() => {
                      focoTrasHistorial.current = true
                      void qActividades.refetch()
                    }}
                  >
                    <RotateCcw aria-hidden /> Reintentar
                  </Button>
                </div>
              )}
              {movimientosInversionDesactualizados && (
                <div
                  className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border bg-muted/30 p-3"
                  role="alert"
                >
                  <p className="text-xs font-semibold text-foreground">
                    {operaciones.length > 0
                      ? 'No pudimos actualizar las renovaciones y aumentos. Estás viendo los últimos movimientos disponibles.'
                      : 'No pudimos mostrar las renovaciones y aumentos en este momento.'}
                  </p>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    className="min-h-10"
                    disabled={movimientosInversionDesactualizados.actualizando === true}
                    onClick={() => {
                      focoTrasMovimientos.current = true
                      movimientosInversionDesactualizados.reintentar()
                    }}
                  >
                    <RotateCcw aria-hidden />
                    {movimientosInversionDesactualizados.actualizando === true ? 'Actualizando…' : 'Reintentar'}
                  </Button>
                </div>
              )}
              {!qActividades.isPending &&
                !qActividades.isError &&
                !movimientosInversionPendientes &&
                movimientosInversionDesactualizados == null &&
                eventosHistorial.length === 0 && (
                  <p className="rounded-xl border border-dashed border-border px-3 py-4 text-center text-xs text-muted-foreground">
                    Aún no hay gestiones registradas. Los contactos y movimientos de inversión aparecerán aquí.
                  </p>
                )}
              {eventosHistorial.length > 0 && (
                <FichaComercialHistorial eventos={eventosHistorial} />
              )}
            </div>
          )}
        </FichaComercialSeccion>

        {puedeVerCuentas && (
          <FichaComercialSeccionPlegable
            icono={Landmark}
            titulo="Cuentas para recibir pagos"
            resumen={
              cuentasError
                ? 'No se pudieron actualizar. Abre para reintentar.'
                : cuentasPen == null || cuentasUsd == null || cuentasReintentando
                  ? 'Cargando cuentas…'
                  : `Soles: ${cuentasPen.length} · Dólares: ${cuentasUsd.length}`
            }
            descripcion="Cuentas registradas del cliente. Revisa cada contrato para confirmar la cuenta elegida para sus pagos."
            sectionRef={cuentasRef}
            abierta={cuentasAbiertas}
            onAbiertaChange={setCuentasAbiertas}
          >
            {cuentasError && !cuentasReintentando ? (
              <div
                className="flex flex-col items-center justify-center gap-3 rounded-xl border border-border bg-muted/30 p-4 text-center"
                role="alert"
              >
                <p className="text-sm font-semibold text-foreground">{cuentasError}</p>
                <Button type="button" variant="outline" size="sm" className="min-h-10" onClick={reintentarCuentas}>
                  <RotateCcw aria-hidden /> Reintentar
                </Button>
              </div>
            ) : cuentasPen == null || cuentasUsd == null || cuentasReintentando ? (
              <div className="space-y-3" aria-busy>
                <span className="sr-only">Cargando cuentas bancarias</span>
                <Skeleton className="h-24 w-full" />
                <Skeleton className="h-24 w-full" />
              </div>
            ) : (
              <div className="space-y-3">
                <CuentasClienteMoneda moneda="PEN" cuentas={cuentasPen} uso="pagos" />
                <CuentasClienteMoneda moneda="USD" cuentas={cuentasUsd} uso="pagos" />
              </div>
            )}
          </FichaComercialSeccionPlegable>
        )}
      </SheetBody>

      <SheetFooter className="justify-between">
        <Button type="button" variant="outline" className="min-h-11" onClick={onCerrar}>
          Cerrar
        </Button>
        {onGestionar && (
          <Button
            type="button"
            className="min-h-11"
            onClick={onGestionar}
            disabled={!operable}
            aria-describedby={!operable ? motivoNoOperableId : undefined}
          >
            <CalendarClock aria-hidden /> Agendar seguimiento
          </Button>
        )}
      </SheetFooter>
    </>
  )
}
