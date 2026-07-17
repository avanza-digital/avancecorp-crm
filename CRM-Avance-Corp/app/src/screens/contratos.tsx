// Pantalla "Mis contratos" — espejo de la sección homónima del panel del
// analista del portal (public_html/admin/analista.html + js/admin/analista.js):
// la cartera de contratos con su reloj de 5 h POR FILA (useVentana sobre
// creado_en, SOLO en filas propias: la ventana es una herramienta del asesor
// dueño, no un dato del lector), el detalle de solo lectura al click en la
// fila (siempre disponible, la RLS ya scopea) y "Corregir" SOLO en contratos
// propios (creado_por === yo.id) con la ventana viva — la ventana real la
// decide el servidor; aquí es cuenta regresiva visual.
// El alta ("+ Contrato") reusa <ContratoNuevo/> (el mismo del convertir del
// lead) precedido de un selector de cliente de la cartera.
import { useEffect, useMemo, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { ChevronRight, FileText, Search } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Skeleton } from '@/components/ui/skeleton'
import {
  Dialog,
  DialogBody,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { SectionHead } from '@/components/common/section-head'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Paginacion } from '@/components/common/paginacion'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import { ContratoNuevo } from '@/components/app/contrato-nuevo'
import { ContratoDetalle } from '@/components/app/contrato-detalle'
import { ContratoCorregir } from '@/components/app/contrato-corregir'
import { mensajeDeError } from '@/data/crm-api'
import { crmQueryKeys, useClientes, useContratos } from '@/data/crm-queries'
import { ESTADOS_CONTRATO, type ContratoRow, type Cuota, type Titular } from '@/lib/clientes-tipos'
import { CATEGORIA_LABEL, ESTADO_COLOR } from '@/lib/contratos-catalogo'
import { useAuth } from '@/lib/auth-context'
import { esMiCliente } from '@/lib/clientes-vista'
import { filtrarContratos, type FiltroEstado } from '@/lib/contratos-vista'
import { paginar } from '@/lib/paginacion'
import { fechaHora, money } from '@/lib/format'
import { useVentana } from '@/lib/ventana'
import { cn } from '@/lib/utils'

export function Contratos() {
  const { yo } = useAuth()
  // El demo NO toca la API real: los contratos son datos vivos del portal y una
  // cuenta demo no tiene sesión de Supabase (llamar sería pegarle a prod).
  if (yo?.demo) return <ContratosDemo />
  return <ContratosReales />
}

/** Copy bajo el título — cada rol lee SOLO lo que aplica a él (nada de mentir). */
function copyDeRol(puedeContratar: boolean): string {
  return puedeContratar
    ? 'Contratos que registraste. Corregir regenera el cronograma de cuotas; también con ventana de 5 h.'
    : 'Todos los contratos de la empresa, en solo lectura (el alta y la corrección son del asesor).'
}

/**
 * Fila de la cartera de contratos. Componente aparte porque useVentana es un
 * hook por registro — y SOLO corre en filas propias (creadoEn null = sin
 * timer): en la vista de gerencia no hay 173 intervalos de 15 s marchando para
 * relojes que ese rol ni ve (mismo criterio que FilaCliente en clientes.tsx).
 * La fila entera abre el detalle (tabIndex + Enter/Espacio, patrón de la
 * cartera de leads); SIN role=button — role=row es la semántica que navegan
 * los E2E y los lectores de pantalla.
 */
function FilaContrato({
  contrato: k,
  esMia,
  conAcciones,
  onDetalle,
  onCorregir,
}: {
  contrato: ContratoRow
  /** creado_por === yo.id (regla POR FILA): habilita reloj y Corregir. */
  esMia: boolean
  /** La tabla pinta las columnas Ventana/Acciones (el usuario contrata en general). */
  conAcciones: boolean
  onDetalle: () => void
  onCorregir: () => void
}) {
  // Reloj propio POR FILA (tick de 15 s, se detiene solo al vencer) — solo en lo mío.
  const ventana = useVentana(esMia ? k.creado_en : null)
  const tituloAjena = 'Solo el asesor que registró el contrato puede corregirlo'

  return (
    <tr
      tabIndex={0}
      // aria-label sobre role="row" (role="button" rompería la semántica de tabla)
      aria-label={`Abrir detalle del contrato ${k.numero_contrato}`}
      onClick={onDetalle}
      onKeyDown={(ev) => {
        // Solo con el foco en la FILA misma: el Enter sobre "Corregir" dispara
        // el click del botón y burbujea hasta aquí — no debe abrir el detalle.
        if (ev.target !== ev.currentTarget) return
        if (ev.key === 'Enter' || ev.key === ' ') {
          ev.preventDefault()
          onDetalle()
        }
      }}
      className="group cursor-pointer border-b border-border/60 transition-colors last:border-0 hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none"
    >
      <Td className="whitespace-nowrap text-[13px] font-semibold tabular-nums">{k.numero_contrato}</Td>
      <Td>
        <p className="max-w-[220px] truncate" title={k.cliente_nombre ?? undefined}>
          {k.cliente_nombre ?? '—'}
        </p>
      </Td>
      <Td className="text-right font-extrabold tabular-nums text-primary">
        {money(k.capital, k.moneda)}
      </Td>
      {/* Estado + Categoría FUSIONADAS: dos badges en una celda (fila densa). */}
      <Td>
        <div className="flex flex-wrap items-center gap-1">
          <Badge color={ESTADO_COLOR[k.estado]} dot>{k.estado}</Badge>
          {k.categoria && <Badge color="var(--chart-4)">{CATEGORIA_LABEL[k.categoria]}</Badge>}
        </div>
      </Td>
      <Td className="hidden whitespace-nowrap text-xs tabular-nums text-muted-foreground xl:table-cell">
        {fechaHora(k.creado_en)}
      </Td>
      {conAcciones && (
        <Td>
          {esMia ? (
            // Sin verde en el sistema ("positivo" = azul): vigente accent, vencida destructive.
            <span
              className={cn(
                'whitespace-nowrap text-xs font-semibold tabular-nums',
                ventana.vigente ? 'text-accent' : 'text-destructive',
              )}
            >
              {ventana.texto}
            </span>
          ) : (
            <span className="text-xs text-muted-foreground" title={tituloAjena}>
              —
            </span>
          )}
        </Td>
      )}
      {conAcciones && (
        <Td className="text-right">
          {/* Solo lo MÍO y con la ventana VIVA se corrige (el servidor lo
              revalida igual — P0001 —; acá no se ofrece lo que fallaría). */}
          {esMia && ventana.vigente ? (
            <Button
              type="button"
              size="xs"
              variant="outline"
              onClick={(e) => {
                // La fila entera abre el detalle: el botón no debe arrastrarlo.
                e.stopPropagation()
                onCorregir()
              }}
            >
              Corregir
            </Button>
          ) : (
            <span
              className="block text-right text-xs text-muted-foreground"
              title={esMia ? 'La ventana de corrección de 5 horas ya venció' : tituloAjena}
            >
              —
            </span>
          )}
        </Td>
      )}
      <Td className="text-right">
        <ChevronRight
          className="size-4 text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100"
          aria-hidden
        />
      </Td>
    </tr>
  )
}

/**
 * La vista compartida por la ruta REAL y la DEMO (espejo de VistaCartera en
 * clientes.tsx): header con título/copy por rol, buscador normalizado, filtro
 * por estado, columnas Ventana/Acciones solo para quien contrata, regla esMia
 * POR FILA y paginación client-side. Los datos y las acciones vienen del
 * caller — esta capa solo decide QUÉ se ve y ofrece, y JAMÁS llama a la API
 * (el demo pasa fixtures y error=null; su detalle sigue precargado).
 */
function VistaContratos({
  contratos,
  demo,
  error,
  yoId,
  puedeContratar,
  titulo,
  copy,
  onNuevo,
  onDetalle,
  onCorregir,
}: {
  /** null = cargando (skeleton). */
  contratos: ContratoRow[] | null
  demo: boolean
  /** Solo la ruta real puede fallar; el demo pasa null. */
  error: { mensaje: string; reintentando: boolean; reintentar: () => void } | null
  /** Identidad para la regla POR FILA (esMia = creado_por === yoId). */
  yoId: string | null
  puedeContratar: boolean
  titulo: string
  copy: string
  onNuevo: () => void
  onDetalle: (c: ContratoRow) => void
  onCorregir: (c: ContratoRow) => void
}) {
  const [q, setQ] = useState('')
  const [fEstado, setFEstado] = useState<FiltroEstado>('todos')
  const [pagina, setPagina] = useState(0)

  // `todas` solo para las condiciones de render (narrowing de null); el filtro
  // memoiza sobre el prop directo para no recalcular por identidad nueva.
  const todas = contratos ?? []
  const items = useMemo(() => filtrarContratos(contratos ?? [], q, fEstado), [contratos, q, fEstado])
  const hayFiltro = q.trim() !== '' || fEstado !== 'todos'
  const { visibles, paginas, paginaActual } = paginar(items, pagina)

  return (
    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
      <Card className="overflow-hidden">
        <SectionHead
          icon={FileText}
          title={titulo}
          right={
            <div className="flex items-center gap-3">
              <span className="text-xs tabular-nums text-muted-foreground">
                {titulo}: {contratos ? contratos.length : '—'}
              </span>
              {/* Solo a quien pasará el chequeo de rol de crear_contrato (analista/admin). */}
              {puedeContratar && (
                <Button size="sm" onClick={onNuevo}>
                  <FileText aria-hidden /> + Contrato
                </Button>
              )}
            </div>
          }
        />
        <p className="px-5 pb-3 text-xs text-muted-foreground">
          {demo ? 'Datos de demostración. ' : ''}
          {copy}
        </p>

        {contratos == null && !error ? (
          <PanelCargando />
        ) : error ? (
          <PanelError mensaje={error.mensaje} onReintentar={error.reintentar} reintentando={error.reintentando} />
        ) : todas.length === 0 ? (
          // Texto EXACTO del vacío del portal; honesto para los roles lectores.
          <PanelVacio
            icono={FileText}
            titulo={puedeContratar ? 'Aún no registraste contratos.' : 'Sin contratos en la cartera todavía.'}
          >
            {puedeContratar && (
              <p className="max-w-xs text-xs text-muted-foreground">
                Crea el primero con “+ Contrato” o convirtiendo un lead en cliente.
              </p>
            )}
          </PanelVacio>
        ) : (
          <>
            {/* Buscador + filtro por estado — patrón de la cartera de clientes. */}
            <div className="flex flex-wrap items-center gap-2 px-5 pb-3">
              <div className="relative w-full max-w-sm">
                <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  aria-label="Buscar contratos"
                  placeholder="Buscar por N° de contrato o cliente…"
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
                  aria-label="Filtrar por estado"
                  value={fEstado}
                  onChange={(e) => {
                    setFEstado(e.target.value as FiltroEstado)
                    setPagina(0)
                  }}
                >
                  <option value="todos">Todos los estados</option>
                  {/* Los 4 estados del CHECK del portal, tal cual los pinta el badge. */}
                  {ESTADOS_CONTRATO.map((es) => (
                    <option key={es} value={es}>{es}</option>
                  ))}
                </Select>
              </div>
              {hayFiltro && (
                <span className="text-xs tabular-nums text-muted-foreground">
                  {items.length} de {todas.length}
                </span>
              )}
            </div>

            {items.length === 0 ? (
              <PanelVacio
                icono={FileText}
                titulo="Sin resultados"
                detalle={
                  q.trim()
                    ? `Ningún contrato coincide con “${q.trim()}”. Prueba con otro número o cliente.`
                    : 'Ningún contrato coincide con el filtro de estado.'
                }
              />
            ) : (
              <TablaEnvoltura ariaLabel={titulo}>
                {/* Responsive por PRIORIDAD (th y td llevan clases IDÉNTICAS en
                    pareja): en pantallas angostas cae Registrado (xl). Ventana y
                    Acciones NUNCA se ocultan: son la operación del asesor. */}
                <TheadCrm>
                  <Th>N° contrato</Th>
                  <Th>Cliente</Th>
                  <Th className="text-right">Capital</Th>
                  {/* Estado + Categoría fusionadas en una sola columna (fila densa). */}
                  <Th>Estado</Th>
                  <Th className="hidden xl:table-cell">Registrado</Th>
                  {/* Texto visible corto; aria-label conserva el nombre accesible
                      completo de la columna (mismo criterio que en Clientes). */}
                  {puedeContratar && <Th aria-label="Ventana de corrección">Ventana</Th>}
                  {puedeContratar && <Th className="text-right">Acciones</Th>}
                  <Th className="w-8" aria-hidden />
                </TheadCrm>
                <tbody>
                  {visibles.map((k) => (
                    <FilaContrato
                      key={k.id}
                      contrato={k}
                      esMia={k.creado_por != null && k.creado_por === yoId}
                      conAcciones={puedeContratar}
                      onDetalle={() => onDetalle(k)}
                      onCorregir={() => onCorregir(k)}
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
        total={items.length}
        onCambio={setPagina}
        ariaLabel="Paginación de contratos"
      />
    </div>
  )
}

/**
 * Contratos en modo DEMO: MISMA vista (VistaContratos completa — buscador,
 * filtro por estado, paginación, reloj de 5 h por fila propia) poblada con
 * fixtures ficticios (lib/demo-clientes) y SIN tocar la API — una sesión demo
 * no tiene Supabase, así que:
 *   - los fixtures llegan por import() dinámico gated (Rolldown los saca de prod),
 *   - el click en la fila abre el detalle con el cronograma/co-titulares
 *     PRECARGADOS (ContratoDetalle.datos → cero fetch),
 *   - "+ Contrato" y "Corregir" existen pero solo emiten un toast "(demo)":
 *     jamás llaman al portal (mismo criterio que las acciones demo de leads).
 */
function ContratosDemo() {
  const { yo } = useAuth()
  const [contratos, setContratos] = useState<ContratoRow[] | null>(null)
  const [cronogramas, setCronogramas] = useState<Record<string, Cuota[]>>({})
  const [titulares, setTitulares] = useState<Record<string, Titular[]>>({})
  const [detalle, setDetalle] = useState<ContratoRow | null>(null)

  useEffect(() => {
    let vivo = true
    // Guard literal (mismo que store.tsx): en prod DEV es false → Rolldown
    // elimina el chunk de fixtures. En demo (DEV + VITE_ENABLE_DEMO) carga aquí.
    if (import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO === 'true') {
      void import('@/lib/demo-clientes').then((m) => {
        if (!vivo) return
        setContratos(m.CONTRATOS_DEMO)
        setCronogramas(m.CRONOGRAMAS_DEMO)
        setTitulares(m.TITULARES_DEMO)
      })
    }
    return () => {
      vivo = false
    }
  }, [])

  const puedeContratar = yo?.puede_contratar === true

  return (
    <>
      <VistaContratos
        contratos={contratos}
        demo
        error={null}
        yoId={yo?.id ?? null}
        puedeContratar={puedeContratar}
        titulo={puedeContratar ? 'Mis contratos' : 'Contratos de la cartera'}
        copy="El alta y la corrección solo operan con tu cuenta real."
        onNuevo={() => toast.info('Nuevo contrato: disponible solo con tu cuenta real (demo)')}
        onDetalle={setDetalle}
        onCorregir={() =>
          toast.info('Corrección de contrato: disponible solo con tu cuenta real (demo)')}
      />

      {/* Detalle SOLO LECTURA con datos PRECARGADOS: no fetchea (cero red en demo). */}
      {detalle && (
        <Dialog
          open
          onClose={() => setDetalle(null)}
          ariaLabel={`Detalle del contrato ${detalle.numero_contrato}`}
          className="w-[560px]"
        >
          <ContratoDetalle
            contratoId={detalle.id}
            datos={{
              contrato: detalle,
              cuotas: cronogramas[detalle.id] ?? [],
              titulares: titulares[detalle.id] ?? [],
            }}
            onCerrar={() => setDetalle(null)}
          />
        </Dialog>
      )}
    </>
  )
}

type Panel =
  | { tipo: 'detalle'; contrato: ContratoRow }
  | { tipo: 'corregir'; contrato: ContratoRow }

function ContratosReales() {
  const { yo } = useAuth()
  const queryClient = useQueryClient()
  const [panel, setPanel] = useState<Panel | null>(null)
  const [nuevoAbierto, setNuevoAbierto] = useState(false)

  // Caché COMPARTIDA bajo crmQueryKeys.contratos(): la invalidación que dispara
  // la pantalla Clientes tras crear un contrato refresca ESTA tabla sin reload.
  // El `enabled` es doble defensa del demo (Contratos ya bifurcó arriba, pero
  // una sesión demo no tiene Supabase y ni un request debe salir).
  const {
    data: contratos,
    isPending,
    isError,
    error,
    refetch,
    isFetching,
  } = useContratos(yo?.demo !== true)

  const puedeContratar = yo?.puede_contratar === true
  const cerrarPanel = () => setPanel(null)
  // Tras crear/corregir NO se refetchea a mano: se invalida la clave y TanStack
  // relee (con dedupe/abort). contratos() es PREFIJO de cronograma(id) y
  // titulares(id), así que esta invalidación jerárquica cubre TAMBIÉN el
  // detalle del contrato corregido — obligatorio: actualizar_contrato REGENERA
  // el cronograma y puede reemplazar el set de co-titulares.
  const recargarContratos = () =>
    void queryClient.invalidateQueries({ queryKey: crmQueryKeys.contratos() })

  return (
    <>
      <VistaContratos
        // El error solo gana cuando NO hay nada que mostrar: un refetch de fondo
        // fallido (foco de ventana + retry:false) deja isError=true con la lista
        // aún en caché — tumbar la tabla pintada por un blip de red sería mentirle
        // al usuario que "no se pudieron cargar" contratos que está viendo.
        contratos={isPending || (isError && contratos == null) ? null : contratos ?? []}
        demo={false}
        error={
          isError && contratos == null
            ? {
                // mensajeDeError: los CrmApiError ya vienen es-PE; lo demás cae
                // al texto por defecto (nunca un message crudo en inglés).
                mensaje: mensajeDeError(error, 'No se pudieron cargar tus contratos.'),
                reintentando: isFetching,
                // refetch de TanStack: con señal y dedupe — se acabó la carrera
                // del doble click que tenía el cargar() manual sin AbortController.
                reintentar: () => void refetch(),
              }
            : null
        }
        yoId={yo?.id ?? null}
        puedeContratar={puedeContratar}
        titulo={puedeContratar ? 'Mis contratos' : 'Contratos de la cartera'}
        copy={copyDeRol(puedeContratar)}
        onNuevo={() => setNuevoAbierto(true)}
        onDetalle={(k) => setPanel({ tipo: 'detalle', contrato: k })}
        onCorregir={(k) => setPanel({ tipo: 'corregir', contrato: k })}
      />

      {/* Detalle SOLO LECTURA: siempre disponible, no depende de la ventana. */}
      {panel?.tipo === 'detalle' && (
        <Dialog
          open
          onClose={cerrarPanel}
          ariaLabel={`Detalle del contrato ${panel.contrato.numero_contrato}`}
          className="w-[560px]"
        >
          <ContratoDetalle contratoId={panel.contrato.id} onCerrar={cerrarPanel} />
        </Dialog>
      )}

      {/* Corrección: el servidor revalida creado_por → 5 h → cartera (P0001 si venció). */}
      {panel?.tipo === 'corregir' && (
        <Dialog
          open
          onClose={cerrarPanel}
          ariaLabel={`Corregir contrato ${panel.contrato.numero_contrato}`}
          className="w-[560px]"
        >
          <ContratoCorregir
            contrato={panel.contrato}
            onGuardado={() => {
              setPanel(null)
              recargarContratos()
            }}
            onCerrar={cerrarPanel}
          />
        </Dialog>
      )}

      {nuevoAbierto && (
        <NuevoContratoDialog
          onCerrar={() => setNuevoAbierto(false)}
          onCreado={() => {
            setNuevoAbierto(false)
            recargarContratos()
          }}
        />
      )}
    </>
  )
}

/**
 * Alta desde la pantalla de contratos: primero se elige el cliente de la
 * cartera (vista crm.clientes_basicos) y luego se reusa <ContratoNuevo/> — el
 * MISMO formulario del paso 2 de convertir un lead (numeración fija 2026-01- +
 * 6 dígitos, co-titulares, preview del cronograma).
 */
function NuevoContratoDialog({ onCerrar, onCreado }: { onCerrar: () => void; onCreado: () => void }) {
  const { yo } = useAuth()
  // La MISMA caché que la pantalla Clientes (crmQueryKeys.clientes()): viniendo
  // de allá el selector abre instantáneo (fresca < 30 s) en vez de refetchear.
  // Este diálogo solo se monta en la ruta REAL (ContratosDemo ni lo ofrece).
  const { data: clientes, isError: errorClientes, error: causaClientes } = useClientes()
  const [clienteId, setClienteId] = useState('')
  const [paso, setPaso] = useState<'cliente' | 'form'>('cliente')

  // crear_contrato exige cartera PROPIA: la vista trae el ámbito completo (un
  // supervisor ve a su equipo), pero solo se ofrece lo que el servidor acepta
  // (espejo por fila, mismo criterio que la pantalla Clientes).
  const misClientes = (clientes ?? []).filter((c) => esMiCliente(c, yo?.id))
  const cliente = misClientes.find((c) => c.id === clienteId) ?? null

  if (paso === 'form' && cliente) {
    return (
      <Dialog open onClose={onCerrar} ariaLabel="Crear contrato">
        <ContratoNuevo
          clienteId={cliente.id}
          clienteNombre={cliente.nombre_completo || cliente.correo || 'el cliente'}
          onCreado={() => onCreado()}
          onOmitir={onCerrar}
        />
      </Dialog>
    )
  }

  return (
    <Dialog open onClose={onCerrar} ariaLabel="Nuevo contrato">
      <DialogHeader>
        <DialogTitle>Nuevo contrato</DialogTitle>
        <DialogDescription>Elige al cliente de tu cartera para registrar su contrato.</DialogDescription>
      </DialogHeader>
      <DialogBody className="space-y-3">
        {errorClientes ? (
          <p className="text-xs font-semibold text-destructive">
            {mensajeDeError(causaClientes, 'No se pudo cargar tu cartera de clientes.')}
          </p>
        ) : clientes == null ? (
          <div className="space-y-2" aria-busy>
            <Skeleton className="h-9 w-full" />
          </div>
        ) : misClientes.length === 0 ? (
          <p className="text-xs leading-relaxed text-muted-foreground">
            Tu cartera personal aún no tiene clientes. Primero crea al cliente (o convierte un lead) y luego su contrato — los contratos de tu equipo los crea cada asesor sobre su propia cartera.
          </p>
        ) : (
          <div className="space-y-1.5">
            <Label htmlFor="nc-cliente">Cliente</Label>
            <Select id="nc-cliente" value={clienteId} onChange={(e) => setClienteId(e.target.value)}>
              <option value="">— Seleccionar cliente —</option>
              {misClientes.map((c) => (
                <option key={c.id} value={c.id}>{c.nombre_completo || c.correo || c.id}</option>
              ))}
            </Select>
          </div>
        )}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCerrar}>
          Cancelar
        </Button>
        <Button type="button" size="sm" disabled={!cliente} onClick={() => setPaso('form')}>
          Continuar
        </Button>
      </DialogFooter>
    </Dialog>
  )
}
