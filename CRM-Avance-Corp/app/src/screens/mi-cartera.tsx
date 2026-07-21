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
// el detalle con cronograma. El gate POR FILA (esMiCliente / esMia) espeja lo
// que el servidor ya valida — jamás se ofrece un botón que el servidor rechazaría.
import { useEffect, useMemo, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { AlarmClock, ChevronRight, Coins, FileStack, Inbox, Search, Users2, Wallet } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Dialog } from '@/components/ui/dialog'
import { Badge } from '@/components/ui/badge'
import { SectionHead } from '@/components/common/section-head'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Paginacion } from '@/components/common/paginacion'
import { StatStrip, type StatChipData } from '@/components/common/stat-strip'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import { ClienteForm } from '@/components/app/cliente-form'
import { ContratoNuevo } from '@/components/app/contrato-nuevo'
import { ContratoDetalle } from '@/components/app/contrato-detalle'
import { ContratoCorregir } from '@/components/app/contrato-corregir'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { can } from '@/lib/roles'
import { money, moneyK, primerNombre } from '@/lib/format'
import { useVentana } from '@/lib/ventana'
import { agruparCartera, resumenCartera, type GrupoCartera } from '@/lib/cartera-vista'
import { carteraDelAmbito, duenoDeCartera, esMiCliente, normalizar } from '@/lib/clientes-vista'
import { type FiltroEstado } from '@/lib/contratos-vista'
import { CATEGORIA_LABEL, ESTADO_COLOR } from '@/lib/contratos-catalogo'
import { paginar } from '@/lib/paginacion'
import { mensajeDeError } from '@/data/crm-api'
import { crmQueryKeys, useClientes, useContratos } from '@/data/crm-queries'
import type { ClienteBasico, ContratoRow, Cuota, Titular } from '@/lib/clientes-tipos'

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

/** Sub-fila de un contrato: la fila entera abre el detalle (Enter/Espacio con el
 *  foco en la fila); "Corregir" solo en lo MÍO con la ventana viva. */
function FilaContratoSub({
  contrato: k,
  colAsesor,
  conAcciones,
  esMia,
  onDetalle,
  onCorregir,
}: {
  contrato: ContratoRow
  colAsesor: boolean
  conAcciones: boolean
  /** creado_por === yo.id — habilita reloj y Corregir de ESTE contrato. */
  esMia: boolean
  onDetalle: () => void
  onCorregir: () => void
}) {
  const ventana = useVentana(esMia ? k.creado_en : null)
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
      className="group cursor-pointer border-b border-border/40 bg-muted/20 transition-colors last:border-0 hover:bg-muted/50 focus-visible:bg-muted/50 focus-visible:outline-none"
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
        <Badge color={ESTADO_COLOR[k.estado]} dot>{k.estado}</Badge>
      </Td>
      {colAsesor && <Td className="hidden md:table-cell" />}
      <Td className="text-right tabular-nums">
        <span className="text-[13px] font-semibold text-foreground">{money(k.capital, k.moneda)}</span>
        <span className="block text-[11px] text-muted-foreground">vence {fechaCorta(k.fecha_vencimiento)}</span>
      </Td>
      {conAcciones && (
        <Td className="text-right">
          {esMia && ventana.vigente ? (
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
          ) : esMia ? (
            <span className="text-[11px] text-muted-foreground" title="La ventana de corrección de 5 horas ya venció">
              {ventana.texto}
            </span>
          ) : (
            <span className="text-xs text-muted-foreground">—</span>
          )}
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
  accionable,
  yoId,
  asesorNombre,
  estadoVisible,
  onNuevoContrato,
  onCorregirCliente,
  onDetalleContrato,
  onCorregirContrato,
}: {
  grupo: GrupoCartera
  expandido: boolean
  onToggle: () => void
  colAsesor: boolean
  /** La tabla pinta la columna Acciones (el usuario contrata en general). */
  conAcciones: boolean
  /** puede_contratar Y la fila es MÍA (regla de cartera) — habilita reloj y botones. */
  accionable: boolean
  yoId: string | null
  asesorNombre: string | null
  /** Con filtro de estado, solo se pintan las sub-filas de ese estado. */
  estadoVisible: FiltroEstado
  onNuevoContrato: () => void
  onCorregirCliente: () => void
  onDetalleContrato: (k: ContratoRow) => void
  onCorregirContrato: (k: ContratoRow) => void
}) {
  const { cliente } = grupo
  const sinContratos = grupo.contratos.length === 0
  const subContratos = estadoVisible === 'todos'
    ? grupo.contratos
    : grupo.contratos.filter((c) => c.estado === estadoVisible)
  // Reloj de la ventana de corrección del CLIENTE (solo en filas propias).
  const ventanaCliente = useVentana(accionable ? cliente.creado_en : null)
  const ident = (
    <div className="min-w-0">
      <p className="max-w-[260px] truncate text-[13px] font-semibold text-foreground" title={cliente.nombre_completo}>
        {cliente.nombre_completo || '—'}
      </p>
      <p className="text-[11px] tabular-nums text-muted-foreground">
        {cliente.dni ? `${cliente.tipo_documento !== 'DNI' ? cliente.tipo_documento + ' ' : ''}${cliente.dni}` : 'sin documento'}
        {cliente.telefono ? ` · ${cliente.telefono}` : ''}
      </p>
    </div>
  )
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
              aria-label={`${expandido ? 'Colapsar' : 'Expandir'} los contratos de ${cliente.nombre_completo || 'este cliente'}`}
              className="flex w-full items-center gap-2 rounded-sm text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
            >
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
            <span className="rounded-full bg-muted px-2 py-0.5 text-[10px] font-medium text-muted-foreground">Sin contratos</span>
          ) : (
            <span className="text-xs text-muted-foreground">
              {grupo.contratosActivos > 0 ? `${grupo.contratosActivos} activo${grupo.contratosActivos > 1 ? 's' : ''}` : 'sin activos'}
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
          {grupo.tieneCapital ? (
            // PEN y USD JAMÁS se suman: se muestran como DOS cifras, ambas con
            // peso propio. Si solo hay dólares, los dólares son la cifra principal
            // (nunca un "S/ 0" grande con el capital real escondido debajo).
            <div className="flex flex-col items-end leading-tight">
              {grupo.capitalActivoPen > 0 && (
                <span className="text-sm font-extrabold text-foreground">{money(grupo.capitalActivoPen, 'PEN')}</span>
              )}
              {grupo.capitalActivoUsd > 0 && (
                <span
                  className={
                    grupo.capitalActivoPen > 0
                      ? 'text-[13px] font-bold text-foreground/90'
                      : 'text-sm font-extrabold text-foreground'
                  }
                >
                  {money(grupo.capitalActivoUsd, 'USD')}
                </span>
              )}
            </div>
          ) : (
            <span className="text-xs text-muted-foreground">{sinContratos ? 'aún no genera ingreso' : 'sin capital vigente'}</span>
          )}
        </Td>
        {conAcciones && (
          <Td className="text-right">
            {accionable ? (
              <div className="flex flex-wrap items-center justify-end gap-1.5">
                {ventanaCliente.vigente && (
                  <Button
                    type="button"
                    size="xs"
                    variant="outline"
                    className={ventanaCliente.ms <= AVISO_VENTANA_MS ? 'text-warning' : undefined}
                    title={`Corregir datos del cliente · ${ventanaCliente.texto} de ventana`}
                    onClick={(e) => {
                      e.stopPropagation()
                      onCorregirCliente()
                    }}
                  >
                    Corregir
                  </Button>
                )}
                <Button
                  type="button"
                  size="xs"
                  onClick={(e) => {
                    e.stopPropagation()
                    onNuevoContrato()
                  }}
                >
                  {sinContratos ? '+ Primer contrato' : '+ Contrato'}
                </Button>
              </div>
            ) : (
              <span className="text-xs text-muted-foreground">—</span>
            )}
          </Td>
        )}
      </tr>
      {expandido &&
        !sinContratos &&
        subContratos.map((c) => (
          <FilaContratoSub
            key={c.id}
            contrato={c}
            colAsesor={colAsesor}
            conAcciones={conAcciones}
            esMia={c.creado_por != null && c.creado_por === yoId}
            onDetalle={() => onDetalleContrato(c)}
            onCorregir={() => onCorregirContrato(c)}
          />
        ))}
    </>
  )
}

/** Vista compartida por la ruta REAL y la DEMO: rótulo por rol, StatStrip de
 *  capital en juego, buscador (cliente o N° de contrato), filtro por estado y la
 *  tabla jerárquica con expandir/colapsar + paginación por cliente. Los datos y
 *  las acciones vienen del caller — esta capa solo decide QUÉ se ve y ofrece. */
function VistaMiCartera({
  grupos,
  demo,
  error,
  yoId,
  puedeContratar,
  onNuevoCliente,
  onNuevoContrato,
  onCorregirCliente,
  onDetalleContrato,
  onCorregirContrato,
}: {
  /** null = cargando. */
  grupos: GrupoCartera[] | null
  demo: boolean
  error: { mensaje: string; reintentando: boolean; reintentar: () => void } | null
  yoId: string | null
  puedeContratar: boolean
  onNuevoCliente: () => void
  onNuevoContrato: (cliente: ClienteBasico) => void
  onCorregirCliente: (cliente: ClienteBasico) => void
  onDetalleContrato: (k: ContratoRow) => void
  onCorregirContrato: (k: ContratoRow) => void
}) {
  const { yo } = useAuth()
  const { equipo } = useCRMData()
  const verEquipo = can(yo?.rol, 'verEquipo')
  const titulo = verEquipo ? 'Cartera' : 'Mi cartera'

  const [q, setQ] = useState('')
  const [fEstado, setFEstado] = useState<FiltroEstado>('todos')
  const [expandidos, setExpandidos] = useState<ReadonlySet<string>>(new Set())
  const [pagina, setPagina] = useState(0)

  const nombres = useMemo(() => new Map(equipo.map((m) => [m.perfil_id, m.nombre_completo])), [equipo])
  const bases = useMemo(() => grupos ?? [], [grupos])
  const resumen = useMemo(() => resumenCartera(bases), [bases])
  const contratosActivosTotal = useMemo(() => bases.reduce((n, g) => n + g.contratosActivos, 0), [bases])

  // Buscador + filtro de estado sobre los GRUPOS. El grupo pasa si el cliente
  // matchea (nombre/doc/correo/teléfono, incl. solo-dígitos) O alguno de sus
  // contratos por N°; y si tiene algún contrato del estado filtrado. Con filtro
  // activo se auto-expanden los grupos para que las sub-filas coincidentes se vean.
  const filtrados = useMemo(() => {
    const nq = normalizar(q.trim())
    const dq = nq.replace(/\D/g, '')
    return bases.filter((g) => {
      if (fEstado !== 'todos' && !g.contratos.some((c) => c.estado === fEstado)) return false
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
  }, [bases, q, fEstado])

  // Al filtrar, auto-expandir los grupos que coinciden POR CONTRATO (para revelar
  // la sub-fila que hizo match), SIN un override global: el usuario puede
  // colapsarlos y el botón "Colapsar" sigue siendo real (aria-expanded refleja el
  // estado verdadero). Solo AÑADE, al cambiar el filtro.
  useEffect(() => {
    const nq = normalizar(q.trim())
    if (nq === '' && fEstado === 'todos') return
    setExpandidos((prev) => {
      let cambio = false
      const sig = new Set(prev)
      for (const g of bases) {
        const matchContrato =
          (fEstado !== 'todos' && g.contratos.some((c) => c.estado === fEstado)) ||
          (nq !== '' && g.contratos.some((c) => normalizar(c.numero_contrato).includes(nq)))
        if (matchContrato && !sig.has(g.cliente.id)) {
          sig.add(g.cliente.id)
          cambio = true
        }
      }
      return cambio ? sig : prev
    })
  }, [bases, q, fEstado])

  const hayFiltro = q.trim() !== '' || fEstado !== 'todos'
  const { visibles, paginas, paginaActual } = paginar(filtrados, pagina)

  // PEN y USD JAMÁS se suman: van en DOS tarjetas separadas para verlos al mismo
  // tiempo. Solo se muestra la tarjeta de la(s) moneda(s) CON capital, y en su
  // orden natural → si el capital es solo en dólares, la tarjeta de Dólares va
  // PRIMERO (nunca un "S/ 0" líder). El hueco que deje una moneda ausente lo
  // ocupa "Contratos activos" para mantener 4 tarjetas.
  const hayPen = resumen.capitalActivoPen > 0
  const hayUsd = resumen.capitalActivoUsd > 0
  const chipsCapital: StatChipData[] = []
  if (hayPen) {
    chipsCapital.push({ icon: Wallet, label: 'Capital invertido · Soles', value: moneyK(resumen.capitalActivoPen), tone: 'primary', sub: 'en contratos activos' })
  }
  if (hayUsd) {
    chipsCapital.push({ icon: Coins, label: 'Capital invertido · Dólares', value: moneyK(resumen.capitalActivoUsd, 'USD'), tone: 'primary', sub: 'en contratos activos' })
  }
  if (chipsCapital.length === 0) {
    chipsCapital.push({ icon: Wallet, label: 'Capital invertido', value: money(0, 'PEN'), tone: 'default', sub: 'sin capital vigente aún' })
  }
  const stats: StatChipData[] = [
    ...chipsCapital,
    {
      icon: AlarmClock,
      label: 'Por vencer ≤30 d',
      value: String(resumen.porVencer30),
      tone: resumen.porVencer30 > 0 ? 'warn' : 'default',
      sub: resumen.porVencer30 > 0 ? 'renovación = ingreso próximo' : 'nada por vencer',
    },
    {
      icon: Users2,
      label: 'Clientes con capital',
      value: `${resumen.clientesConCapital}`,
      sub: `de ${resumen.totalClientes}`,
    },
  ]
  if (stats.length < 4) {
    stats.push({ icon: FileStack, label: 'Contratos activos', value: String(contratosActivosTotal), sub: 'en toda tu cartera' })
  }

  return (
    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
      {bases.length > 0 && <StatStrip stats={stats} />}
      <Card className="overflow-hidden">
        <SectionHead
          icon={Wallet}
          title={titulo}
          right={
            <div className="flex items-center gap-3">
              <span className="text-xs tabular-nums text-muted-foreground">
                {grupos ? `${resumen.totalClientes} clientes` : '—'}
              </span>
              {puedeContratar && (
                <Button size="sm" onClick={onNuevoCliente}>
                  <Users2 aria-hidden /> Nuevo cliente
                </Button>
              )}
            </div>
          }
        />
        <p className="px-5 pb-3 text-xs text-muted-foreground">
          {demo ? 'Datos de demostración. ' : ''}
          {verEquipo
            ? 'Clientes de la empresa con el capital que tienen invertido. Cada cliente agrupa sus contratos; expándelo para verlos.'
            : 'Tus clientes y el capital que tienen invertido contigo. Cada cliente agrupa sus contratos; expándelo para verlos.'}
        </p>

        {grupos == null && !error ? (
          <PanelCargando />
        ) : error ? (
          <PanelError mensaje={error.mensaje} onReintentar={error.reintentar} reintentando={error.reintentando} />
        ) : bases.length === 0 ? (
          <PanelVacio icono={Inbox} titulo={verEquipo ? 'Aún no hay clientes en la cartera.' : 'Aún no tienes clientes en tu cartera.'}>
            {puedeContratar && <p className="text-xs text-muted-foreground">Usa “Nuevo cliente”.</p>}
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
                  onChange={(e) => {
                    setQ(e.target.value)
                    setPagina(0)
                  }}
                />
              </div>
              <div className="w-[190px]">
                <Select
                  aria-label="Filtrar por estado de contrato"
                  value={fEstado}
                  onChange={(e) => {
                    setFEstado(e.target.value as FiltroEstado)
                    setPagina(0)
                  }}
                >
                  <option value="todos">Todos los estados</option>
                  <option value="activo">Activos</option>
                  <option value="vencido">Vencidos</option>
                  <option value="renovado">Renovados</option>
                  <option value="retirado">Retirados</option>
                </Select>
              </div>
              {hayFiltro && (
                <span className="text-xs tabular-nums text-muted-foreground">
                  {filtrados.length} de {bases.length}
                </span>
              )}
            </div>

            {filtrados.length === 0 ? (
              <PanelVacio
                icono={Inbox}
                titulo="Sin resultados"
                detalle={q.trim() ? `Ningún cliente ni contrato coincide con “${q.trim()}”.` : 'Ningún cliente tiene contratos en ese estado.'}
              />
            ) : (
              <TablaEnvoltura ariaLabel={titulo}>
                <TheadCrm>
                  <Th>Cartera / Contrato</Th>
                  <Th className="text-center">Estado</Th>
                  {verEquipo && <Th className="hidden md:table-cell">Asesor</Th>}
                  <Th className="text-right" aria-label="Capital invertido">
                    Capital invertido
                  </Th>
                  {puedeContratar && <Th className="text-right">Acciones</Th>}
                </TheadCrm>
                <tbody>
                  {visibles.map((g) => (
                    <FilaGrupoCliente
                      key={g.cliente.id}
                      grupo={g}
                      expandido={expandidos.has(g.cliente.id)}
                      onToggle={() =>
                        setExpandidos((prev) => {
                          const sig = new Set(prev)
                          if (sig.has(g.cliente.id)) sig.delete(g.cliente.id)
                          else sig.add(g.cliente.id)
                          return sig
                        })}
                      colAsesor={verEquipo}
                      conAcciones={puedeContratar}
                      accionable={puedeContratar && esMiCliente(g.cliente, yoId)}
                      yoId={yoId}
                      asesorNombre={nombres.get(duenoDeCartera(g.cliente) ?? '') ?? null}
                      estadoVisible={fEstado}
                      onNuevoContrato={() => onNuevoContrato(g.cliente)}
                      onCorregirCliente={() => onCorregirCliente(g.cliente)}
                      onDetalleContrato={onDetalleContrato}
                      onCorregirContrato={onCorregirContrato}
                    />
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
        total={filtrados.length}
        onCambio={setPagina}
        ariaLabel="Paginación de la cartera"
      />
    </div>
  )
}

/** Overlay de acciones — uno solo abierto a la vez (como el portal). */
type Overlay =
  | { tipo: 'cliente-crear' }
  | { tipo: 'cliente-corregir'; clienteId: string }
  | { tipo: 'contrato-crear'; clienteId: string; clienteNombre: string }
  | { tipo: 'contrato-detalle'; contrato: ContratoRow }
  | { tipo: 'contrato-corregir'; contrato: ContratoRow }
  | null

export function MiCartera() {
  const { yo } = useAuth()
  const esDemo = yo?.demo === true
  const queryClient = useQueryClient()
  const [overlay, setOverlay] = useState<Overlay>(null)
  const [envioEnCurso, setEnvioEnCurso] = useState(false)

  const clientesQ = useClientes(!esDemo)
  const contratosQ = useContratos(!esDemo)

  const grupos = useMemo(() => {
    if (clientesQ.data == null || contratosQ.data == null) return null
    return agruparCartera(clientesQ.data, contratosQ.data)
  }, [clientesQ.data, contratosQ.data])

  if (esDemo) return <MiCarteraDemo />

  const cerrar = () => setOverlay(null)
  // Cierre BLINDADO de ClienteForm: no cerrar con un envío en vuelo (perdería el
  // aviso del alta parcial: cliente creado, bancarios sin guardar).
  const cerrarSeguro = () => {
    if (envioEnCurso) return
    cerrar()
  }
  // El alta puede terminar PARCIAL (cliente creado, bancarios fallaron): sin onListo
  // en ese camino, el refetch va SIEMPRE al cerrar el alta.
  const cerrarAlta = () => {
    if (envioEnCurso) return
    cerrar()
    void clientesQ.refetch()
    void contratosQ.refetch()
  }

  // Alta exitosa → refrescar cartera y encadenar el contrato (flujo del portal).
  const alClienteCreado = async (id: string) => {
    setOverlay(null)
    const r = await clientesQ.refetch()
    void contratosQ.refetch()
    const nuevo = r.data?.find((c) => c.id === id)
    setOverlay({ tipo: 'contrato-crear', clienteId: id, clienteNombre: nuevo?.nombre_completo ?? 'el cliente' })
  }

  // Corregir cliente → refetch + invalidar clienteDetalle(id) y contratos()
  // (cliente_nombre viaja denormalizado en la vista de contratos: sin invalidarla
  // la sub-fila mostraría el nombre viejo < 30 s).
  const alClienteCorregido = (id: string) => {
    setOverlay(null)
    void clientesQ.refetch()
    void queryClient.invalidateQueries({ queryKey: crmQueryKeys.clienteDetalle(id) })
    void queryClient.invalidateQueries({ queryKey: crmQueryKeys.contratos() })
  }

  // Crear/corregir contrato → invalidar contratos() (prefijo: cubre cronograma+titulares).
  const recargarContratos = () => {
    setOverlay(null)
    void queryClient.invalidateQueries({ queryKey: crmQueryKeys.contratos() })
  }

  const cargando = grupos == null && !(clientesQ.isError || contratosQ.isError)
  const hayError = (clientesQ.isError || contratosQ.isError) && grupos == null

  return (
    <>
      <VistaMiCartera
        grupos={cargando ? null : grupos}
        demo={false}
        error={
          hayError
            ? {
                mensaje: mensajeDeError(clientesQ.error ?? contratosQ.error, 'No se pudo cargar tu cartera.'),
                reintentando: clientesQ.isFetching || contratosQ.isFetching,
                reintentar: () => {
                  void clientesQ.refetch()
                  void contratosQ.refetch()
                },
              }
            : null
        }
        yoId={yo?.id ?? null}
        puedeContratar={yo?.puede_contratar === true}
        onNuevoCliente={() => setOverlay({ tipo: 'cliente-crear' })}
        onNuevoContrato={(c) =>
          setOverlay({ tipo: 'contrato-crear', clienteId: c.id, clienteNombre: c.nombre_completo || c.correo || 'el cliente' })}
        onCorregirCliente={(c) => setOverlay({ tipo: 'cliente-corregir', clienteId: c.id })}
        onDetalleContrato={(k) => setOverlay({ tipo: 'contrato-detalle', contrato: k })}
        onCorregirContrato={(k) => setOverlay({ tipo: 'contrato-corregir', contrato: k })}
      />

      {overlay?.tipo === 'cliente-crear' && (
        <Dialog open onClose={cerrarAlta} ariaLabel="Nuevo cliente">
          <ClienteForm modo="crear" onListo={(id) => void alClienteCreado(id)} onCerrar={cerrarAlta} onEnviandoCambio={setEnvioEnCurso} />
        </Dialog>
      )}
      {overlay?.tipo === 'cliente-corregir' && (
        <Dialog open onClose={cerrarSeguro} ariaLabel="Corregir datos del cliente">
          <ClienteForm modo="corregir" clienteId={overlay.clienteId} onListo={alClienteCorregido} onCerrar={cerrarSeguro} onEnviandoCambio={setEnvioEnCurso} />
        </Dialog>
      )}
      {overlay?.tipo === 'contrato-crear' && (
        <Dialog open onClose={cerrar} ariaLabel="Crear contrato del cliente">
          <ContratoNuevo clienteId={overlay.clienteId} clienteNombre={overlay.clienteNombre} onCreado={recargarContratos} onOmitir={cerrar} />
        </Dialog>
      )}
      {overlay?.tipo === 'contrato-detalle' && (
        <Dialog open onClose={cerrar} ariaLabel={`Detalle del contrato ${overlay.contrato.numero_contrato}`} className="w-[560px]">
          <ContratoDetalle contratoId={overlay.contrato.id} onCerrar={cerrar} />
        </Dialog>
      )}
      {overlay?.tipo === 'contrato-corregir' && (
        <Dialog open onClose={cerrar} ariaLabel={`Corregir contrato ${overlay.contrato.numero_contrato}`} className="w-[560px]">
          <ContratoCorregir contrato={overlay.contrato} onGuardado={recargarContratos} onCerrar={cerrar} />
        </Dialog>
      )}
    </>
  )
}

/**
 * Modo DEMO: reusa VistaMiCartera con fixtures ficticios (lib/demo-clientes)
 * cargados por import() dinámico gated → NUNCA toca la API real. El recorte de
 * ámbito que en real hace el servidor lo espeja carteraDelAmbito; los contratos
 * se limitan a los de los clientes visibles. Las acciones de ESCRITURA solo
 * emiten un toast "(demo)"; el DETALLE sí se abre, con cronograma/co-titulares
 * PRECARGADOS (ContratoDetalle.datos → cero fetch).
 */
function MiCarteraDemo() {
  const { yo } = useAuth()
  const { ambito } = useCRMData()
  const [fixtures, setFixtures] = useState<{
    clientes: ClienteBasico[]
    contratos: ContratoRow[]
    cronogramas: Record<string, Cuota[]>
    titulares: Record<string, Titular[]>
  } | null>(null)
  const [detalle, setDetalle] = useState<ContratoRow | null>(null)

  useEffect(() => {
    let vivo = true
    if (import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO === 'true') {
      void import('@/lib/demo-clientes').then((m) => {
        if (vivo) {
          setFixtures({
            clientes: m.CLIENTES_DEMO,
            contratos: m.CONTRATOS_DEMO,
            cronogramas: m.CRONOGRAMAS_DEMO,
            titulares: m.TITULARES_DEMO,
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
    const contratosVis = fixtures.contratos.filter((k) => idsClientes.has(k.cliente_id))
    return agruparCartera(clientesVis, contratosVis)
  }, [fixtures, yo, ambito])

  const tocaReal = () => toast.info('Disponible solo con tu cuenta real (demo)')

  return (
    <>
      <VistaMiCartera
        grupos={grupos}
        demo
        error={null}
        yoId={yo?.id ?? null}
        puedeContratar={yo?.puede_contratar === true}
        onNuevoCliente={tocaReal}
        onNuevoContrato={tocaReal}
        onCorregirCliente={tocaReal}
        onDetalleContrato={setDetalle}
        onCorregirContrato={tocaReal}
      />

      {detalle && (
        <Dialog open onClose={() => setDetalle(null)} ariaLabel={`Detalle del contrato ${detalle.numero_contrato}`} className="w-[560px]">
          <ContratoDetalle
            contratoId={detalle.id}
            datos={{
              contrato: detalle,
              cuotas: fixtures?.cronogramas[detalle.id] ?? [],
              titulares: fixtures?.titulares[detalle.id] ?? [],
            }}
            onCerrar={() => setDetalle(null)}
          />
        </Dialog>
      )}
    </>
  )
}
