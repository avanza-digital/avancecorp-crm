// screens/clientes.tsx — la cartera de clientes del PORTAL dentro del CRM.
// Nació como espejo del panel del ANALISTA (10-20 clientes propios); hoy la
// misma pantalla la viven cuatro roles y se adapta a cada uno:
//   · vendedor: SU cartera ("Mis clientes") con acciones completas en sus filas.
//   · supervisor: su cartera + la de su equipo ("Cartera de clientes") — las
//     acciones SOLO en sus filas propias (regla de cartera POR FILA, abajo) y
//     la columna Asesor dice de quién es cada fila del equipo.
//   · gerencia/directorio: toda la empresa, solo lectura (puede_contratar=false),
//     con buscador/filtro por asesor/paginación para que 164+ filas no sean ruido.
//
// LA REGLA DE CARTERA (espejo del servidor — crear_contrato y
// perfiles_analista_update): una fila es MÍA si asesor_perfil_id = mi uid OR
// (asesor_perfil_id IS NULL AND creado_por = mi uid). El flag global
// puede_contratar NO alcanza: ofrecer "+ Contrato" en una fila ajena termina en
// "Solo puedes crear contratos para clientes de tu cartera" (mismo patrón del
// bug del convertir). esMiCliente (lib/clientes-vista) la espeja POR FILA.
//
// La lista sale de la vista crm.clientes_basicos (ya scopeada por rol en el
// servidor); las acciones reusan el motor del portal que YA está en prod (edge
// crear-cliente + RLS con ventana de 5 h) vía @/data/crm-api. En DEMO no hay
// backend del portal: fixtures gated + recorte de ámbito local (carteraDelAmbito).
import { useEffect, useMemo, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { Inbox, Search, UserPlus2, Users2 } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Dialog } from '@/components/ui/dialog'
import { SectionHead } from '@/components/common/section-head'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Paginacion } from '@/components/common/paginacion'
import { TablaEnvoltura, Td, Th, TheadCrm } from '@/components/common/tabla'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { can } from '@/lib/roles'
import { useVentana } from '@/lib/ventana'
import { fechaHora, primerNombre } from '@/lib/format'
import {
  carteraDelAmbito,
  duenoDeCartera,
  esMiCliente,
  filtrarClientes,
  type FiltroAsesor,
} from '@/lib/clientes-vista'
import { paginar } from '@/lib/paginacion'
import { mensajeDeError } from '@/data/crm-api'
import { crmQueryKeys, useClientes } from '@/data/crm-queries'
import type { ClienteBasico } from '@/lib/clientes-tipos'
import { ClienteForm } from '@/components/app/cliente-form'
import { ContratoNuevo } from '@/components/app/contrato-nuevo'
import { toast } from 'sonner'

/** Copy bajo el título — cada rol lee SOLO lo que aplica a él (nada de mentir). */
function copyDeRol(puedeContratar: boolean, verEquipo: boolean): string {
  if (puedeContratar && verEquipo)
    return 'Ves tu cartera y la de tu equipo. Corriges y contratas solo a tus propios clientes; el reloj de corrección corre 5 h desde que creas cada uno.'
  if (puedeContratar)
    return 'Solo ves los clientes que tú registraste. El reloj de corrección corre 5 h desde que creas cada uno.'
  if (verEquipo)
    return 'Cartera de clientes de toda la empresa, en solo lectura. La columna Asesor dice de quién es cada cliente.'
  return 'Cartera de clientes en solo lectura para tu rol.'
}

/** Estado del panel de acciones: un solo modal abierto a la vez (como el portal). */
type Modal =
  | { tipo: 'crear' }
  | { tipo: 'corregir'; clienteId: string }
  | { tipo: 'contrato'; clienteId: string; clienteNombre: string }
  | null

/**
 * Registrado en fila densa: SOLO la fecha visible — la hora exacta viaja en el
 * title (fechaHora). Aquí `new Date(ts)` es válido por la misma razón que en
 * fechaHora: creado_en es un timestamp ISO completo, no un 'YYYY-MM-DD'.
 */
function soloFecha(ts: string): string {
  const d = new Date(ts)
  if (Number.isNaN(d.getTime())) return '—'
  return d.toLocaleDateString('es-PE', { day: '2-digit', month: 'short', year: '2-digit' })
}

/**
 * Fila de la cartera. Es un componente aparte porque useVentana es un hook por
 * registro: cada fila lleva su propia cuenta regresiva (tick de 15 s que se
 * auto-detiene al vencer), igual que las celdas [data-creado] del portal.
 */
function FilaCliente({
  cliente,
  accionable,
  conAcciones,
  verEquipo,
  asesorNombre,
  onCorregir,
  onContrato,
}: {
  cliente: ClienteBasico
  /** puede_contratar Y la fila es MÍA (regla de cartera) — habilita reloj y botones. */
  accionable: boolean
  /** La tabla pinta las columnas Ventana/Acciones (el usuario contrata en general). */
  conAcciones: boolean
  verEquipo: boolean
  /** Dueño de cartera ya resuelto contra el roster; null → '—'. */
  asesorNombre: string | null
  onCorregir: () => void
  onContrato: () => void
}) {
  // En filas ajenas no corre ningún reloj (creadoEn null = sin timer): la
  // ventana de 5 h es una herramienta del asesor dueño, no un dato del lector.
  const ventana = useVentana(accionable ? cliente.creado_en : null)
  const tituloAjena = asesorNombre
    ? `Cliente de ${asesorNombre}: solo su asesor puede corregirlo o crearle contratos`
    : 'Solo el asesor del cliente puede corregirlo o crearle contratos'
  return (
    <tr className="border-b border-border/60 transition-colors last:border-0 hover:bg-muted/40">
      <Td>
        {/* Sin avatar decorativo: en fila densa el nombre ES el ancla visual;
            truncate + title mantienen la altura constante con nombres largos. */}
        <p
          className="max-w-[240px] truncate text-[13px] font-semibold text-foreground"
          title={cliente.nombre_completo || undefined}
        >
          {cliente.nombre_completo || '—'}
        </p>
      </Td>
      <Td className="hidden tabular-nums md:table-cell">
        {cliente.dni ? (
          <>
            {/* Sigla solo cuando NO es DNI — patrón del portal ('CE 001234567'). */}
            {cliente.tipo_documento !== 'DNI' && (
              <span className="mr-1 text-[11px] text-muted-foreground">{cliente.tipo_documento}</span>
            )}
            {cliente.dni}
          </>
        ) : (
          '—'
        )}
      </Td>
      {/* truncate + title en vez de [overflow-wrap:anywhere]: los correos largos
          hacían filas de altura VARIABLE (70-90 px) — en denso la altura es fija. */}
      <Td className="hidden lg:table-cell">
        <p className="max-w-[200px] truncate text-xs text-muted-foreground" title={cliente.correo || undefined}>
          {cliente.correo || '—'}
        </p>
      </Td>
      <Td className="text-xs tabular-nums text-muted-foreground">{cliente.telefono || '—'}</Td>
      {verEquipo && (
        <Td>
          {asesorNombre ? (
            <span className="text-xs text-muted-foreground" title={asesorNombre}>
              {/* Visible solo el nombre de pila (columna angosta, patrón de la
                  columna Vendedor de cartera); el nombre COMPLETO queda para
                  lectores de pantalla — es el texto accesible que identifica
                  de quién es la fila, y el que navegan los E2E. */}
              <span aria-hidden>{primerNombre(asesorNombre)}</span>
              <span className="sr-only">{asesorNombre}</span>
            </span>
          ) : (
            <span className="text-xs text-muted-foreground">—</span>
          )}
        </Td>
      )}
      <Td
        className="hidden whitespace-nowrap text-xs tabular-nums text-muted-foreground xl:table-cell"
        title={fechaHora(cliente.creado_en)}
      >
        {soloFecha(cliente.creado_en)}
      </Td>
      {conAcciones && (
        <Td>
          {accionable ? (
            // Sin verde en el sistema ("positivo" = azul): vigente en accent, vencida en destructive.
            <span
              className={`text-xs font-semibold tabular-nums ${ventana.vigente ? 'text-accent' : 'text-destructive'}`}
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
        <Td>
          {accionable ? (
            <div className="flex flex-wrap justify-end gap-1.5">
              <Button
                variant="outline"
                size="xs"
                disabled={!ventana.vigente}
                // El disabled es cortesía visual: la RLS del servidor es la que manda
                // (fuera de ventana el UPDATE devuelve 0 filas, y crm-api lo detecta).
                title={ventana.vigente ? undefined : 'La ventana de corrección de 5 horas ya venció'}
                // Texto visible corto (fila densa); el nombre ACCESIBLE conserva el
                // verbo completo — lectores de pantalla y E2E no pierden contexto.
                aria-label="Corregir datos"
                onClick={onCorregir}
              >
                Corregir
              </Button>
              {/* Crear contrato NO tiene ventana (regla del portal): siempre activo. */}
              <Button size="xs" onClick={onContrato}>
                + Contrato
              </Button>
            </div>
          ) : (
            // Fila ajena: NADA de botones que el servidor va a rechazar — el
            // guion dice honesto de quién es el cliente (tooltip).
            <span className="block text-right text-xs text-muted-foreground" title={tituloAjena}>
              —
            </span>
          )}
        </Td>
      )}
    </tr>
  )
}

/**
 * La vista compartida por la ruta REAL y la DEMO: título/copy por rol, buscador
 * normalizado, filtro por asesor (roles con equipo), columna Asesor, regla de
 * cartera por fila y paginación client-side (patrón de cartera.tsx). Los datos
 * y las acciones vienen del caller — esta capa solo decide QUÉ se ve y ofrece.
 */
function VistaCartera({
  clientes,
  demo,
  error,
  onNuevo,
  onCorregir,
  onContrato,
}: {
  /** null = cargando (skeleton). */
  clientes: ClienteBasico[] | null
  demo: boolean
  /** Solo la ruta real puede fallar; el demo pasa null. */
  error: { mensaje: string; reintentando: boolean; reintentar: () => void } | null
  onNuevo: () => void
  onCorregir: (cliente: ClienteBasico) => void
  onContrato: (cliente: ClienteBasico) => void
}) {
  const { yo } = useAuth()
  const { equipo } = useCRMData()
  const puedeContratar = yo?.puede_contratar === true
  // Columna Asesor + filtro por asesor = roles con equipo (supervisor/gerencia/
  // directorio). Para el vendedor la columna sería su propio nombre 164 veces.
  const verEquipo = can(yo?.rol, 'verEquipo')
  // Copy honesto: "Mis clientes" solo es verdad para quien ve SOLO su cartera.
  const titulo = verEquipo ? 'Cartera de clientes' : 'Mis clientes'

  const [q, setQ] = useState('')
  const [fAsesor, setFAsesor] = useState<FiltroAsesor>('todos')
  const [pagina, setPagina] = useState(0)

  // perfil_id → nombre con el roster del store (crm.equipo vía equipo_visible_fn;
  // en demo, EQUIPO_DEMO). Sin match → null y la celda pinta '—'.
  const nombres = useMemo(() => new Map(equipo.map((m) => [m.perfil_id, m.nombre_completo])), [equipo])

  // Orden defensivo por creado_en desc: listarClientes ya lo pide al servidor,
  // pero la pantalla no depende de que el transporte lo respete.
  const ordenados = useMemo(() => {
    const lista = [...(clientes ?? [])]
    lista.sort((a, b) => (a.creado_en < b.creado_en ? 1 : a.creado_en > b.creado_en ? -1 : 0))
    return lista
  }, [clientes])

  // El Set del roster viaja al filtro para que 'Sin asesor' atrape también a
  // los dueños que la columna no puede nombrar (fuera del equipo → '—').
  const rosterIds = useMemo(() => new Set(equipo.map((m) => m.perfil_id)), [equipo])
  const items = useMemo(() => filtrarClientes(ordenados, q, fAsesor, rosterIds), [ordenados, q, fAsesor, rosterIds])
  const hayFiltro = q.trim() !== '' || fAsesor !== 'todos'
  const { visibles, paginas, paginaActual } = paginar(items, pagina)

  return (
    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
      <Card className="overflow-hidden">
        <SectionHead
          icon={Users2}
          title={titulo}
          right={
            <div className="flex items-center gap-3">
              <span className="text-xs tabular-nums text-muted-foreground">
                {titulo}: {clientes ? ordenados.length : '—'}
              </span>
              {puedeContratar && (
                <Button size="sm" onClick={onNuevo}>
                  <UserPlus2 aria-hidden /> Nuevo cliente
                </Button>
              )}
            </div>
          }
        />
        <p className="px-5 pb-3 text-xs text-muted-foreground">
          {demo ? 'Datos de demostración. ' : ''}
          {copyDeRol(puedeContratar, verEquipo)}
        </p>

        {clientes == null && !error ? (
          <PanelCargando />
        ) : error ? (
          <PanelError mensaje={error.mensaje} onReintentar={error.reintentar} reintentando={error.reintentando} />
        ) : ordenados.length === 0 ? (
          // Copy del estado vacío del portal para el analista; honesto para supervisión.
          <PanelVacio
            icono={Inbox}
            titulo={verEquipo ? 'Aún no hay clientes en la cartera.' : 'Aún no registraste clientes.'}
          >
            {puedeContratar && <p className="text-xs text-muted-foreground">Usa “+ Nuevo cliente”.</p>}
          </PanelVacio>
        ) : (
          <>
            {/* Buscador + filtro por asesor (solo roles con equipo) — patrón de cartera.tsx. */}
            <div className="flex flex-wrap items-center gap-2 px-5 pb-3">
              <div className="relative w-full max-w-sm">
                <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  aria-label="Buscar clientes"
                  placeholder="Buscar por nombre, documento, correo o teléfono…"
                  className="pl-9"
                  value={q}
                  onChange={(e) => {
                    setQ(e.target.value)
                    setPagina(0)
                  }}
                />
              </div>
              {verEquipo && (
                <div className="w-[230px]">
                  <Select
                    aria-label="Filtrar por asesor"
                    value={fAsesor}
                    onChange={(e) => {
                      setFAsesor(e.target.value)
                      setPagina(0)
                    }}
                  >
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
              {hayFiltro && (
                <span className="text-xs tabular-nums text-muted-foreground">
                  {items.length} de {ordenados.length}
                </span>
              )}
            </div>

            {items.length === 0 ? (
              <PanelVacio
                icono={Inbox}
                titulo="Sin resultados"
                detalle={
                  q.trim()
                    ? `Ningún cliente coincide con “${q.trim()}”. Prueba con otro nombre, documento, correo o teléfono.`
                    : 'Ningún cliente coincide con el filtro de asesor.'
                }
              />
            ) : (
              <TablaEnvoltura ariaLabel={titulo}>
                {/* Responsive por PRIORIDAD (th y td llevan las mismas clases en
                    pareja): en pantallas angostas cae primero Registrado (xl),
                    luego Correo (lg), luego Documento (md). Ventana/Acciones y
                    Asesor NUNCA se ocultan: son la operación del asesor y la
                    propiedad de cada fila. */}
                <TheadCrm>
                  <Th>Nombre</Th>
                  <Th className="hidden md:table-cell">Documento</Th>
                  <Th className="hidden lg:table-cell">Correo</Th>
                  <Th>Teléfono</Th>
                  {verEquipo && <Th>Asesor</Th>}
                  <Th className="hidden xl:table-cell">Registrado</Th>
                  {/* Texto visible corto; aria-label conserva el nombre accesible
                      completo de la columna (mismo criterio que 'Corregir'). */}
                  {puedeContratar && <Th aria-label="Ventana de corrección">Ventana</Th>}
                  {puedeContratar && <Th className="text-right">Acciones</Th>}
                </TheadCrm>
                <tbody>
                  {visibles.map((c) => (
                    <FilaCliente
                      key={c.id}
                      cliente={c}
                      accionable={puedeContratar && esMiCliente(c, yo?.id)}
                      conAcciones={puedeContratar}
                      verEquipo={verEquipo}
                      asesorNombre={nombres.get(duenoDeCartera(c) ?? '') ?? null}
                      onCorregir={() => onCorregir(c)}
                      onContrato={() => onContrato(c)}
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
        ariaLabel="Paginación de clientes"
      />
    </div>
  )
}

export function Clientes() {
  const { yo } = useAuth()
  const esDemo = yo?.demo === true
  const queryClient = useQueryClient()
  const [modal, setModal] = useState<Modal>(null)

  // Cartera compartida vía useClientes (clave crmQueryKeys.clientes()): la misma
  // caché que abre instantáneo el selector de "+ Contrato" en Contratos. En demo
  // ni un solo request (fail-closed): enabled=false, y ClientesDemo bifurca abajo.
  const { data, isPending, isError, error, refetch, isFetching } = useClientes(!esDemo)

  const cerrarModal = () => setModal(null)
  // Cierre BLINDADO para los modales de ClienteForm: Radix cierra con Esc/overlay
  // incondicionalmente y un cierre con el envío en vuelo pierde el aviso del alta
  // parcial (cliente creado + correo enviado, bancarios sin guardar).
  const [envioEnCurso, setEnvioEnCurso] = useState(false)
  const cerrarSeguro = () => {
    if (envioEnCurso) return
    cerrarModal()
  }
  // El alta puede terminar PARCIAL (cliente creado, bancarios fallaron): en ese
  // camino no hay onListo, así que el refetch va SIEMPRE al cerrar el alta — el
  // cliente nuevo debe aparecer en la cartera aunque el paso 2 haya fallado.
  const cerrarAlta = () => {
    if (envioEnCurso) return
    cerrarModal()
    void refetch()
  }

  // Alta exitosa: refrescar la cartera (sin recargar la página) y encadenar el
  // contrato de una — el flujo natural del portal ("tras crear el usuario,
  // abrimos de una el contrato"). El nombre sale de la lista ya refrescada.
  // El toast de éxito lo emite ClienteForm (tiene el nombre exacto sin esperar
  // el refetch); aquí solo se orquesta — un toast por acción, no dos.
  const alClienteCreado = async (id: string) => {
    setModal(null)
    const refresco = await refetch()
    const nuevo = refresco.data?.find((c) => c.id === id)
    setModal({ tipo: 'contrato', clienteId: id, clienteNombre: nuevo?.nombre_completo ?? 'el cliente' })
  }

  // El toast ('Datos del cliente corregidos.') también lo emite ClienteForm.
  // Además de la lista se invalida clienteDetalle(id): el form precarga de esa
  // clave (staleTime 0) y ningún consumidor debe revivir la versión previa a
  // la corrección desde la caché. Y contratos(): cliente_nombre viaja
  // denormalizado en la vista de contratos — sin invalidarla, la tabla y el
  // detalle mostrarían el nombre viejo mientras la lista siga fresca (< 30 s).
  const alClienteCorregido = (id: string) => {
    setModal(null)
    void refetch()
    void queryClient.invalidateQueries({ queryKey: crmQueryKeys.clienteDetalle(id) })
    void queryClient.invalidateQueries({ queryKey: crmQueryKeys.contratos() })
  }

  // Contratos YA comparte esta caché (useContratos, misma clave): la invalidación
  // marca la lista stale aunque su pantalla esté desmontada, y al navegar hacia
  // allá la tabla relee y pinta el contrato nuevo SIN reload.
  const alContratoCreado = () => {
    setModal(null)
    void queryClient.invalidateQueries({ queryKey: crmQueryKeys.contratos() })
  }

  // ── DEMO: MISMA vista (buscador/asesor/regla de cartera), fixtures y SIN backend ──
  //   (ver ClientesDemo — las acciones solo emiten toast "(demo)", cero API).
  if (esDemo) return <ClientesDemo />

  return (
    <>
      <VistaCartera
        // El error solo gana SIN data (mismo criterio que Contratos): un refetch
        // de fondo fallido no tumba la cartera ya pintada desde caché.
        clientes={isPending || (isError && data == null) ? null : data ?? []}
        demo={false}
        error={
          isError && data == null
            ? {
                // mensajeDeError: los CrmApiError ya vienen es-PE; lo demás cae
                // al texto por defecto (nunca un message crudo en inglés).
                mensaje: mensajeDeError(error, 'No se pudo cargar tu cartera de clientes.'),
                reintentando: isFetching,
                reintentar: () => void refetch(),
              }
            : null
        }
        onNuevo={() => setModal({ tipo: 'crear' })}
        onCorregir={(c) => setModal({ tipo: 'corregir', clienteId: c.id })}
        onContrato={(c) =>
          setModal({ tipo: 'contrato', clienteId: c.id, clienteNombre: c.nombre_completo || 'el cliente' })}
      />

      {/* ── Modales (uno a la vez, como el portal) ──────────────────────────────── */}
      {modal?.tipo === 'crear' && (
        <Dialog open onClose={cerrarAlta} ariaLabel="Nuevo cliente">
          <ClienteForm
            modo="crear"
            onListo={(id) => void alClienteCreado(id)}
            onCerrar={cerrarAlta}
            onEnviandoCambio={setEnvioEnCurso}
          />
        </Dialog>
      )}
      {modal?.tipo === 'corregir' && (
        <Dialog open onClose={cerrarSeguro} ariaLabel="Corregir datos del cliente">
          <ClienteForm
            modo="corregir"
            clienteId={modal.clienteId}
            onListo={alClienteCorregido}
            onCerrar={cerrarSeguro}
            onEnviandoCambio={setEnvioEnCurso}
          />
        </Dialog>
      )}
      {modal?.tipo === 'contrato' && (
        <Dialog open onClose={cerrarModal} ariaLabel="Crear contrato del cliente">
          <ContratoNuevo
            clienteId={modal.clienteId}
            clienteNombre={modal.clienteNombre}
            onCreado={alContratoCreado}
            onOmitir={cerrarModal}
          />
        </Dialog>
      )}
    </>
  )
}

/**
 * Cartera de clientes en modo DEMO: reusa VistaCartera COMPLETA (buscador,
 * columna Asesor, regla de cartera por fila, paginación) con fixtures ficticios
 * (lib/demo-clientes) cargados por import() dinámico gated → NUNCA toca la API
 * real. El recorte de ámbito que en real hace la vista del servidor aquí lo
 * espeja carteraDelAmbito (yo + mis vendedores; gerencia/directorio todo). Las
 * acciones ("+ Nuevo cliente", "Corregir datos", "+ Contrato") existen pero solo
 * emiten un toast "(demo)": mismo criterio que las acciones demo de leads.
 */
function ClientesDemo() {
  const { yo } = useAuth()
  const { ambito } = useCRMData()
  const [fixtures, setFixtures] = useState<ClienteBasico[] | null>(null)

  useEffect(() => {
    let vivo = true
    // Guard literal (mismo que store.tsx): en prod DEV es false → Rolldown saca
    // el chunk de fixtures del bundle. En demo (DEV + VITE_ENABLE_DEMO) carga aquí.
    if (import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO === 'true') {
      void import('@/lib/demo-clientes').then((m) => {
        if (vivo) setFixtures(m.CLIENTES_DEMO)
      })
    }
    return () => {
      vivo = false
    }
  }, [])

  // Espejo del scoping del servidor sobre los fixtures (ver carteraDelAmbito).
  const clientes = useMemo(() => {
    if (fixtures == null || yo == null) return null
    const idsVisibles = new Set([yo.id, ...ambito.vendedores.map((m) => m.perfil_id)])
    return carteraDelAmbito(fixtures, idsVisibles, ambito.esGlobal)
  }, [fixtures, yo, ambito])

  return (
    <VistaCartera
      clientes={clientes}
      demo
      error={null}
      onNuevo={() => toast.info('Alta de clientes: disponible solo con tu cuenta real (demo)')}
      onCorregir={() => toast.info('Corrección de cliente: disponible solo con tu cuenta real (demo)')}
      onContrato={() => toast.info('Nuevo contrato: disponible solo con tu cuenta real (demo)')}
    />
  )
}
