// screens/clientes.tsx — "Mis clientes": la cartera de clientes del PORTAL
// dentro del CRM (espejo de la sección homónima de admin/analista.html). La
// lista sale de la vista crm.clientes_basicos (ya scopeada por rol en el
// servidor); las acciones de alta/corrección reusan el motor del portal que YA
// está en prod (edge crear-cliente + RLS con ventana de 5 h) vía @/data/crm-api.
//
// Quién ve qué: yo.puede_contratar (rol de PORTAL analista/admin/superadmin)
// habilita las acciones de alta; gerencia (directorio) ve la lista sin botones.
// En DEMO no hay backend del portal → estado vacío honesto, sin llamar a la API.
import { useEffect, useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Inbox, RotateCcw, UserPlus2, Users2, WifiOff } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { Dialog } from '@/components/ui/dialog'
import { SectionHead } from '@/components/common/section-head'
import { useAuth } from '@/lib/auth-context'
import { useVentana } from '@/lib/ventana'
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
  return d.toLocaleString('es-PE', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
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
  puedeContratar,
  onCorregir,
  onContrato,
}: {
  cliente: ClienteBasico
  puedeContratar: boolean
  onCorregir: () => void
  onContrato: () => void
}) {
  const ventana = useVentana(cliente.creado_en)
  return (
    <tr className="border-b border-border/60 last:border-0">
      <td className="px-4 py-3">
        <p className="font-semibold text-foreground">{cliente.nombre_completo || '—'}</p>
      </td>
      <td className="px-4 py-3 tabular-nums">{cliente.dni || '—'}</td>
      <td className="max-w-[220px] px-4 py-3 text-xs text-muted-foreground [overflow-wrap:anywhere]">
        {cliente.correo || '—'}
      </td>
      <td className="px-4 py-3 text-xs tabular-nums text-muted-foreground">{cliente.telefono || '—'}</td>
      <td className="px-4 py-3 text-xs text-muted-foreground">{fechaHora(cliente.creado_en)}</td>
      <td className="px-4 py-3">
        {/* Sin verde en el sistema ("positivo" = azul): vigente en accent, vencida en destructive. */}
        <span
          className={`text-xs font-semibold tabular-nums ${ventana.vigente ? 'text-accent' : 'text-destructive'}`}
        >
          {ventana.texto}
        </span>
      </td>
      {puedeContratar && (
        <td className="px-4 py-3">
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
        </td>
      )}
    </tr>
  )
}

export function Clientes() {
  const { yo } = useAuth()
  const esDemo = yo?.demo === true
  const puedeContratar = yo?.puede_contratar === true
  const queryClient = useQueryClient()
  const [modal, setModal] = useState<Modal>(null)

  const { data, isPending, isError, error, refetch, isFetching } = useQuery({
    queryKey: CLAVE_CLIENTES,
    queryFn: ({ signal }) => listarClientes(signal),
    // El demo no tiene backend del portal: ni un solo request (fail-closed).
    enabled: !esDemo,
  })

  // Orden defensivo por creado_en desc: listarClientes ya lo pide al servidor,
  // pero la pantalla no depende de que el transporte lo respete.
  const clientes = useMemo(() => {
    const lista = [...(data ?? [])]
    lista.sort((a, b) => (a.creado_en < b.creado_en ? 1 : a.creado_en > b.creado_en ? -1 : 0))
    return lista
  }, [data])

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

  // ── DEMO: MISMA cartera y reloj de 5 h, poblada con fixtures y SIN backend ────
  //   (ver ClientesDemo — las acciones solo emiten toast "(demo)", cero API).
  if (esDemo) return <ClientesDemo />

  return (
    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
      <Card className="overflow-hidden">
        <SectionHead
          icon={Users2}
          title="Mis clientes"
          right={
            <div className="flex items-center gap-3">
              <span className="text-xs tabular-nums text-muted-foreground">
                Mis clientes: {data ? clientes.length : '—'}
              </span>
              {puedeContratar && (
                <Button size="sm" onClick={() => setModal({ tipo: 'crear' })}>
                  <UserPlus2 aria-hidden /> Nuevo cliente
                </Button>
              )}
            </div>
          }
        />
        {/* Regla de las 5 h — copy del portal (analista.html). */}
        <p className="px-5 pb-3 text-xs text-muted-foreground">
          Solo ves los clientes que tú registraste. El reloj de corrección corre 5 h desde que
          creas cada uno.
        </p>

        {isPending ? (
          <div className="space-y-2 px-5 pb-5" aria-busy>
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-9 w-full" />
          </div>
        ) : isError ? (
          <div className="flex flex-col items-center justify-center gap-3 px-6 py-14 text-center">
            <span className="grid size-11 place-items-center rounded-2xl bg-destructive/10 text-destructive">
              <WifiOff className="size-5" aria-hidden />
            </span>
            <div className="space-y-1">
              <p className="text-sm font-semibold text-foreground">
                {error instanceof Error ? error.message : 'No se pudo cargar tu cartera de clientes.'}
              </p>
              <p className="text-xs text-muted-foreground">
                Revisa tu conexión y vuelve a intentarlo — tu sesión sigue activa.
              </p>
            </div>
            <Button variant="outline" size="sm" disabled={isFetching} onClick={() => void refetch()}>
              <RotateCcw aria-hidden /> Reintentar
            </Button>
          </div>
        ) : clientes.length === 0 ? (
          <div className="flex flex-col items-center justify-center gap-2 px-6 py-14 text-center">
            <span className="grid size-11 place-items-center rounded-2xl bg-muted text-muted-foreground">
              <Inbox className="size-5" aria-hidden />
            </span>
            {/* Copy del estado vacío del portal. */}
            <p className="text-sm font-semibold text-foreground">Aún no registraste clientes.</p>
            {puedeContratar && (
              <p className="text-xs text-muted-foreground">Usa “+ Nuevo cliente”.</p>
            )}
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
                  <th className="px-4 py-3">Registrado</th>
                  <th className="px-4 py-3">Ventana de corrección</th>
                  {puedeContratar && <th className="px-4 py-3 text-right">Acciones</th>}
                </tr>
              </thead>
              <tbody>
                {clientes.map((c) => (
                  <FilaCliente
                    key={c.id}
                    cliente={c}
                    puedeContratar={puedeContratar}
                    onCorregir={() => setModal({ tipo: 'corregir', clienteId: c.id })}
                    onContrato={() =>
                      setModal({ tipo: 'contrato', clienteId: c.id, clienteNombre: c.nombre_completo || 'el cliente' })}
                  />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

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
    </div>
  )
}


/**
 * Cartera de clientes en modo DEMO: reusa FilaCliente (misma tabla + reloj de
 * 5 h por fila) con fixtures ficticios (lib/demo-clientes) cargados por import()
 * dinámico gated → NUNCA toca la API real. Las acciones ("+ Nuevo cliente",
 * "Corregir datos", "+ Contrato") existen pero solo emiten un toast "(demo)":
 * mismo criterio que las acciones demo de leads (cero llamadas al portal).
 */
function ClientesDemo() {
  const { yo } = useAuth()
  const puedeContratar = yo?.puede_contratar === true
  const [clientes, setClientes] = useState<ClienteBasico[] | null>(null)

  useEffect(() => {
    let vivo = true
    // Guard literal (mismo que store.tsx): en prod DEV es false → Rolldown saca
    // el chunk de fixtures del bundle. En demo (DEV + VITE_ENABLE_DEMO) carga aquí.
    if (import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO === 'true') {
      void import('@/lib/demo-clientes').then((m) => {
        if (vivo) setClientes(m.CLIENTES_DEMO)
      })
    }
    return () => {
      vivo = false
    }
  }, [])

  return (
    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
      <Card className="overflow-hidden">
        <SectionHead
          icon={Users2}
          title="Mis clientes"
          right={
            <div className="flex items-center gap-3">
              <span className="text-xs tabular-nums text-muted-foreground">
                Mis clientes: {clientes ? clientes.length : '—'}
              </span>
              {puedeContratar && (
                <Button
                  size="sm"
                  onClick={() => toast.info('Alta de clientes: disponible solo con tu cuenta real (demo)')}
                >
                  <UserPlus2 aria-hidden /> Nuevo cliente
                </Button>
              )}
            </div>
          }
        />
        <p className="px-5 pb-3 text-xs text-muted-foreground">
          Datos de demostración. Solo ves los clientes que tú registraste; el reloj de corrección
          corre 5 h desde que creas cada uno.
        </p>

        {clientes == null ? (
          <div className="space-y-2 px-5 pb-5" aria-busy>
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-9 w-full" />
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
                  <th className="px-4 py-3">Registrado</th>
                  <th className="px-4 py-3">Ventana de corrección</th>
                  {puedeContratar && <th className="px-4 py-3 text-right">Acciones</th>}
                </tr>
              </thead>
              <tbody>
                {clientes.map((c) => (
                  <FilaCliente
                    key={c.id}
                    cliente={c}
                    puedeContratar={puedeContratar}
                    onCorregir={() =>
                      toast.info('Corrección de cliente: disponible solo con tu cuenta real (demo)')}
                    onContrato={() =>
                      toast.info('Nuevo contrato: disponible solo con tu cuenta real (demo)')}
                  />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  )
}
