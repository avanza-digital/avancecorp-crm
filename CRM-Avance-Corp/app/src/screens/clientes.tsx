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
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Inbox, RotateCcw, Search, UserPlus2, Users2, WifiOff } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Avatar } from '@/components/ui/avatar'
import { Skeleton } from '@/components/ui/skeleton'
import { Dialog } from '@/components/ui/dialog'
import { SectionHead } from '@/components/common/section-head'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { can } from '@/lib/roles'
import { useVentana } from '@/lib/ventana'
import {
  carteraDelAmbito,
  CLIENTES_POR_PAGINA,
  duenoDeCartera,
  esMiCliente,
  filtrarClientes,
  paginar,
  type FiltroAsesor,
} from '@/lib/clientes-vista'
import { listarClientes } from '@/data/crm-api'
import { crmQueryKeys } from '@/data/crm-queries'
import type { ClienteBasico } from '@/lib/clientes-tipos'
import { ClienteForm } from '@/components/app/cliente-form'
import { ContratoNuevo } from '@/components/app/contrato-nuevo'
import { toast } from 'sonner'

// Claves centralizadas en crm-queries (misma raíz que el resto del CRM: el
// logout con queryClient.clear y las invalidaciones jerárquicas las cubren).
const CLAVE_CLIENTES = crmQueryKeys.clientes()
const CLAVE_CONTRATOS = crmQueryKeys.contratos()

/**
 * Fecha + hora local del registro (espejo de fechaHora de analista.js): para un
 * timestamp completo toLocaleString SÍ respeta hora/minuto en todos los motores
 * (toLocaleDateString las ignora en iOS/WebKit). Aquí `new Date(ts)` es correcto
 * porque creado_en es un timestamp ISO completo, no un 'YYYY-MM-DD' (esos van
 * por fmtFecha, que parsea en local para evitar el bug UTC).
 */
function fechaHora(ts: string): string {
  const d = new Date(ts)
  if (Number.isNaN(d.getTime())) return '—'
  // Con la cartera completa de la empresa, el AÑO es obligatorio (la historia
  // supera los 12 meses; el formato sin año venía del portal, otra escala).
  return d.toLocaleString('es-PE', { day: '2-digit', month: 'short', year: '2-digit', hour: '2-digit', minute: '2-digit' })
}

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
    <tr className="border-b border-border/60 last:border-0">
      <td className="px-4 py-3">
        <div className="flex items-center gap-2.5">
          <Avatar nombre={cliente.nombre_completo} />
          <p className="font-semibold text-foreground">{cliente.nombre_completo || '—'}</p>
        </div>
      </td>
      <td className="px-4 py-3 tabular-nums">
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
      </td>
      <td className="max-w-[220px] px-4 py-3 text-xs text-muted-foreground [overflow-wrap:anywhere]">
        {cliente.correo || '—'}
      </td>
      <td className="px-4 py-3 text-xs tabular-nums text-muted-foreground">{cliente.telefono || '—'}</td>
      {verEquipo && (
        <td className="px-4 py-3">
          {asesorNombre ? (
            <span className="flex items-center gap-1.5">
              <Avatar nombre={asesorNombre} className="size-6 text-[9px]" />
              <span className="text-xs text-muted-foreground">{asesorNombre}</span>
            </span>
          ) : (
            <span className="text-xs text-muted-foreground">—</span>
          )}
        </td>
      )}
      <td className="px-4 py-3 text-xs text-muted-foreground">{fechaHora(cliente.creado_en)}</td>
      {conAcciones && (
        <td className="px-4 py-3">
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
        </td>
      )}
      {conAcciones && (
        <td className="px-4 py-3">
          {accionable ? (
            <div className="flex flex-wrap justify-end gap-1.5">
              <Button
                variant="outline"
                size="sm"
                disabled={!ventana.vigente}
                // El disabled es cortesía visual: la RLS del servidor es la que manda
                // (fuera de ventana el UPDATE devuelve 0 filas, y crm-api lo detecta).
                title={ventana.vigente ? undefined : 'La ventana de corrección de 5 horas ya venció'}
                onClick={onCorregir}
              >
                Corregir datos
              </Button>
              {/* Crear contrato NO tiene ventana (regla del portal): siempre activo. */}
              <Button size="sm" onClick={onContrato}>
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
        </td>
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
          <div className="space-y-2 px-5 pb-5" aria-busy>
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-9 w-full" />
          </div>
        ) : error ? (
          <div className="flex flex-col items-center justify-center gap-3 px-6 py-14 text-center">
            <span className="grid size-11 place-items-center rounded-2xl bg-destructive/10 text-destructive">
              <WifiOff className="size-5" aria-hidden />
            </span>
            <div className="space-y-1">
              <p className="text-sm font-semibold text-foreground">{error.mensaje}</p>
              <p className="text-xs text-muted-foreground">
                Revisa tu conexión y vuelve a intentarlo — tu sesión sigue activa.
              </p>
            </div>
            <Button variant="outline" size="sm" disabled={error.reintentando} onClick={error.reintentar}>
              <RotateCcw aria-hidden /> Reintentar
            </Button>
          </div>
        ) : ordenados.length === 0 ? (
          <div className="flex flex-col items-center justify-center gap-2 px-6 py-14 text-center">
            <span className="grid size-11 place-items-center rounded-2xl bg-muted text-muted-foreground">
              <Inbox className="size-5" aria-hidden />
            </span>
            {/* Copy del estado vacío del portal para el analista; honesto para supervisión. */}
            <p className="text-sm font-semibold text-foreground">
              {verEquipo ? 'Aún no hay clientes en la cartera.' : 'Aún no registraste clientes.'}
            </p>
            {puedeContratar && <p className="text-xs text-muted-foreground">Usa “+ Nuevo cliente”.</p>}
          </div>
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
              <div className="flex flex-col items-center justify-center gap-2 px-6 py-14 text-center">
                <span className="grid size-11 place-items-center rounded-2xl bg-muted text-muted-foreground">
                  <Inbox className="size-5" aria-hidden />
                </span>
                <p className="text-sm font-semibold text-foreground">Sin resultados</p>
                <p className="max-w-xs text-xs text-muted-foreground">
                  {q.trim()
                    ? `Ningún cliente coincide con “${q.trim()}”. Prueba con otro nombre, documento, correo o teléfono.`
                    : 'Ningún cliente coincide con el filtro de asesor.'}
                </p>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-border bg-muted/50 text-left text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                      <th className="px-4 py-3">Nombre</th>
                      <th className="px-4 py-3">Documento</th>
                      <th className="px-4 py-3">Correo</th>
                      <th className="px-4 py-3">Teléfono</th>
                      {verEquipo && <th className="px-4 py-3">Asesor</th>}
                      <th className="px-4 py-3">Registrado</th>
                      {puedeContratar && <th className="px-4 py-3">Ventana de corrección</th>}
                      {puedeContratar && <th className="px-4 py-3 text-right">Acciones</th>}
                    </tr>
                  </thead>
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
                </table>
              </div>
            )}
          </>
        )}
      </Card>

      {items.length > CLIENTES_POR_PAGINA && (
        <nav className="flex items-center justify-between gap-3" aria-label="Paginación de clientes">
          <p className="text-xs tabular-nums text-muted-foreground">
            Página {paginaActual + 1} de {paginas} · {items.length} registros
          </p>
          <div className="flex gap-2">
            <button
              type="button"
              className="rounded-lg border border-border bg-card px-3 py-2 text-xs font-semibold disabled:cursor-not-allowed disabled:opacity-40"
              disabled={paginaActual === 0}
              onClick={() => setPagina((p) => Math.max(0, p - 1))}
            >
              Anterior
            </button>
            <button
              type="button"
              className="rounded-lg border border-border bg-card px-3 py-2 text-xs font-semibold disabled:cursor-not-allowed disabled:opacity-40"
              disabled={paginaActual >= paginas - 1}
              onClick={() => setPagina((p) => Math.min(paginas - 1, p + 1))}
            >
              Siguiente
            </button>
          </div>
        </nav>
      )}
    </div>
  )
}

export function Clientes() {
  const { yo } = useAuth()
  const esDemo = yo?.demo === true
  const queryClient = useQueryClient()
  const [modal, setModal] = useState<Modal>(null)

  const { data, isPending, isError, error, refetch, isFetching } = useQuery({
    queryKey: CLAVE_CLIENTES,
    queryFn: ({ signal }) => listarClientes(signal),
    // El demo no tiene backend del portal: ni un solo request (fail-closed).
    enabled: !esDemo,
  })

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
  const alClienteCorregido = () => {
    setModal(null)
    void refetch()
  }

  // La pantalla Contratos carga fresco al montarse (no lee esta caché todavía);
  // la invalidación queda por si migra a TanStack Query con crmQueryKeys.contratos().
  const alContratoCreado = () => {
    setModal(null)
    void queryClient.invalidateQueries({ queryKey: CLAVE_CONTRATOS })
  }

  // ── DEMO: MISMA vista (buscador/asesor/regla de cartera), fixtures y SIN backend ──
  //   (ver ClientesDemo — las acciones solo emiten toast "(demo)", cero API).
  if (esDemo) return <ClientesDemo />

  return (
    <>
      <VistaCartera
        clientes={isPending || isError ? null : data ?? []}
        demo={false}
        error={
          isError
            ? {
                mensaje: error instanceof Error ? error.message : 'No se pudo cargar tu cartera de clientes.',
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
