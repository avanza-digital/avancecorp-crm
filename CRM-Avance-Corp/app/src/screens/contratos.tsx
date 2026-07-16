// Pantalla "Mis contratos" — espejo de la sección homónima del panel del
// analista del portal (public_html/admin/analista.html + js/admin/analista.js):
// tabla de la cartera con su reloj de 5 h POR FILA (useVentana sobre creado_en),
// "Ver detalle" siempre activo (solo lectura, la RLS ya scopea) y "Corregir"
// SOLO para contratos propios (creado_por === yo.id) con la ventana viva — la
// ventana real la decide el servidor; aquí es cuenta regresiva visual.
// El alta ("+ Contrato") reusa <ContratoNuevo/> (el mismo del convertir del
// lead) precedido de un selector de cliente de la cartera.
import { useCallback, useEffect, useState } from 'react'
import { toast } from 'sonner'
import { FileText, RotateCcw, WifiOff } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
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
import { ContratoNuevo } from '@/components/app/contrato-nuevo'
import { ContratoDetalle } from '@/components/app/contrato-detalle'
import { ContratoCorregir } from '@/components/app/contrato-corregir'
import { CrmApiError, listarClientes, listarMisContratos } from '@/data/crm-api'
import type { ClienteBasico, ContratoRow, Cuota, EstadoContrato, Titular } from '@/lib/clientes-tipos'
import type { CategoriaContrato } from '@/lib/cronograma'
import { useAuth } from '@/lib/auth-context'
import { money } from '@/lib/format'
import { useVentana } from '@/lib/ventana'
import { cn } from '@/lib/utils'

// Categoría: valor en BD → etiqueta visible (con tilde) — espejo de analista.js.
const CATEGORIA_LABEL: Record<CategoriaContrato, string> = {
  nuevo: 'Nuevo',
  renovacion: 'Renovación',
  upgrade: 'Upgrade',
}

// Colores de estado sobre los tokens del CRM (no hay verde: "positivo" = azul).
const ESTADO_COLOR: Record<EstadoContrato, string> = {
  activo: 'var(--accent)',
  vencido: 'var(--warning)',
  renovado: 'var(--chart-4)',
  retirado: 'var(--muted-foreground)',
}

// Fecha + hora local del registro (espejo de fechaHora de analista.js:287-292 —
// toLocaleString SÍ respeta hora/minuto en iOS/WebKit; creado_en es timestamp
// completo, no un 'YYYY-MM-DD', así que new Date(ts) es correcto aquí).
function fechaHora(ts: string | null | undefined): string {
  if (!ts) return '—'
  const d = new Date(ts)
  if (Number.isNaN(d.getTime())) return '—'
  return d.toLocaleString('es-PE', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
}

export function Contratos() {
  const { yo } = useAuth()
  // El demo NO toca la API real: los contratos son datos vivos del portal y una
  // cuenta demo no tiene sesión de Supabase (llamar sería pegarle a prod).
  if (yo?.demo) return <ContratosDemo />
  return <ContratosReales />
}

/**
 * Contratos en modo DEMO: MISMA tabla y reloj de 5 h que la ruta real, pero
 * poblada con fixtures ficticios (lib/demo-clientes) y SIN tocar la API — una
 * sesión demo no tiene Supabase, así que:
 *   - los fixtures llegan por import() dinámico gated (Rolldown los saca de prod),
 *   - "Ver detalle" abre el detalle con el cronograma/co-titulares PRECARGADOS
 *     (ContratoDetalle.datos → cero fetch),
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

  return (
    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
      <div className="flex flex-wrap items-end justify-between gap-2">
        <div>
          <h2 className="text-base font-extrabold text-primary">Mis contratos</h2>
          <p className="text-xs text-muted-foreground">
            Datos de demostración. El alta y la corrección solo operan con tu cuenta real.
          </p>
        </div>
        {yo?.puede_contratar && (
          <Button
            size="sm"
            onClick={() => toast.info('Nuevo contrato: disponible solo con tu cuenta real (demo)')}
          >
            <FileText /> + Contrato
          </Button>
        )}
      </div>

      <Card className="overflow-hidden">
        {contratos == null ? (
          <div className="space-y-2 p-4" aria-busy>
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-3/4" />
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border bg-muted/50 text-left text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                  <th className="px-4 py-3">N° contrato</th>
                  <th className="px-4 py-3">Cliente</th>
                  <th className="px-4 py-3 text-right">Capital</th>
                  <th className="px-4 py-3">Estado</th>
                  <th className="px-4 py-3">Categoría</th>
                  <th className="px-4 py-3">Registrado</th>
                  <th className="px-4 py-3">Ventana de corrección</th>
                  <th className="px-4 py-3 text-right">Acciones</th>
                </tr>
              </thead>
              <tbody>
                {contratos.map((k) => (
                  <FilaContrato
                    key={k.id}
                    contrato={k}
                    esMia={k.creado_por != null && k.creado_por === yo?.id}
                    onDetalle={() => setDetalle(k)}
                    onCorregir={() =>
                      toast.info('Corrección de contrato: disponible solo con tu cuenta real (demo)')}
                  />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

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
    </div>
  )
}

type Panel =
  | { tipo: 'detalle'; contrato: ContratoRow }
  | { tipo: 'corregir'; contrato: ContratoRow }

function ContratosReales() {
  const { yo } = useAuth()
  const [contratos, setContratos] = useState<ContratoRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [panel, setPanel] = useState<Panel | null>(null)
  const [nuevoAbierto, setNuevoAbierto] = useState(false)

  const cargar = useCallback(async (signal?: AbortSignal) => {
    setError(null)
    try {
      const filas = await listarMisContratos(signal)
      if (signal?.aborted) return
      setContratos(filas)
    } catch (e) {
      if (signal?.aborted) return
      setError(e instanceof CrmApiError ? e.message : 'No se pudieron cargar tus contratos.')
    }
  }, [])

  useEffect(() => {
    const ac = new AbortController()
    void cargar(ac.signal)
    return () => ac.abort()
  }, [cargar])

  const cerrarPanel = () => setPanel(null)

  return (
    <div className="mx-auto max-w-[1240px] space-y-4 ac-rise">
      <div className="flex flex-wrap items-end justify-between gap-2">
        <div>
          <h2 className="text-base font-extrabold text-primary">Mis contratos</h2>
          <p className="text-xs text-muted-foreground">
            Contratos que registraste. Corregir regenera el cronograma de cuotas; también con ventana de 5 h.
          </p>
        </div>
        {/* Solo a quien pasará el chequeo de rol de crear_contrato (analista/admin). */}
        {yo?.puede_contratar && (
          <Button size="sm" onClick={() => setNuevoAbierto(true)}>
            <FileText /> + Contrato
          </Button>
        )}
      </div>

      <Card className="overflow-hidden">
        {error ? (
          <div className="flex flex-col items-center justify-center gap-3 px-6 py-14 text-center">
            <WifiOff className="size-6 text-destructive" aria-hidden />
            <p className="text-sm font-semibold text-foreground">{error}</p>
            <Button type="button" variant="outline" size="sm" onClick={() => void cargar()}>
              <RotateCcw /> Reintentar
            </Button>
          </div>
        ) : contratos == null ? (
          <div className="space-y-2 p-4" aria-busy>
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-3/4" />
          </div>
        ) : contratos.length === 0 ? (
          <div className="flex flex-col items-center justify-center gap-2 px-6 py-16 text-center">
            <FileText className="size-6 text-muted-foreground" aria-hidden />
            {/* Texto EXACTO del vacío del portal. */}
            <p className="text-sm font-semibold text-foreground">Aún no registraste contratos.</p>
            {yo?.puede_contratar && (
              <p className="max-w-xs text-xs text-muted-foreground">
                Crea el primero con “+ Contrato” o convirtiendo un lead en cliente.
              </p>
            )}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border bg-muted/50 text-left text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                  <th className="px-4 py-3">N° contrato</th>
                  <th className="px-4 py-3">Cliente</th>
                  <th className="px-4 py-3 text-right">Capital</th>
                  <th className="px-4 py-3">Estado</th>
                  <th className="px-4 py-3">Categoría</th>
                  <th className="px-4 py-3">Registrado</th>
                  <th className="px-4 py-3">Ventana de corrección</th>
                  <th className="px-4 py-3 text-right">Acciones</th>
                </tr>
              </thead>
              <tbody>
                {contratos.map((k) => (
                  <FilaContrato
                    key={k.id}
                    contrato={k}
                    esMia={k.creado_por != null && k.creado_por === yo?.id}
                    onDetalle={() => setPanel({ tipo: 'detalle', contrato: k })}
                    onCorregir={() => setPanel({ tipo: 'corregir', contrato: k })}
                  />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

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
              void cargar()
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
            void cargar()
          }}
        />
      )}
    </div>
  )
}

function FilaContrato({
  contrato: k,
  esMia,
  onDetalle,
  onCorregir,
}: {
  contrato: ContratoRow
  esMia: boolean
  onDetalle: () => void
  onCorregir: () => void
}) {
  // Reloj propio POR FILA (tick de 15 s, se detiene solo al vencer).
  const ventana = useVentana(k.creado_en)

  return (
    <tr className="border-b border-border/60 last:border-0 hover:bg-muted/40">
      <td className="px-4 py-3 font-bold tabular-nums">{k.numero_contrato}</td>
      <td className="px-4 py-3">{k.cliente_nombre ?? '—'}</td>
      <td className="px-4 py-3 text-right font-extrabold tabular-nums text-primary">
        {money(k.capital, k.moneda)}
      </td>
      <td className="px-4 py-3">
        <Badge color={ESTADO_COLOR[k.estado]} dot>{k.estado}</Badge>
      </td>
      <td className="px-4 py-3">
        {k.categoria ? (
          <Badge color="var(--chart-4)">{CATEGORIA_LABEL[k.categoria]}</Badge>
        ) : (
          <span className="text-xs text-muted-foreground">—</span>
        )}
      </td>
      <td className="px-4 py-3 text-xs text-muted-foreground">{fechaHora(k.creado_en)}</td>
      <td
        className={cn(
          'px-4 py-3 text-xs font-semibold tabular-nums',
          ventana.vigente ? 'text-accent' : 'text-destructive',
        )}
      >
        {ventana.texto}
      </td>
      <td className="px-4 py-3">
        <div className="flex flex-wrap justify-end gap-1.5">
          <Button type="button" size="sm" variant="outline" onClick={onDetalle}>
            Ver detalle
          </Button>
          {/* Solo lo MÍO se corrige (el portal lo manda igual y la RLS lo calla;
              acá lo sabemos de antemano y no ofrecemos lo que fallaría). */}
          {esMia && (
            <Button
              type="button"
              size="sm"
              variant="ghost"
              onClick={onCorregir}
              disabled={!ventana.vigente}
              title={ventana.vigente ? undefined : 'La ventana de corrección de 5 horas ya venció'}
            >
              Corregir
            </Button>
          )}
        </div>
      </td>
    </tr>
  )
}

/**
 * Alta desde la pantalla de contratos: primero se elige el cliente de la
 * cartera (vista crm.clientes_basicos) y luego se reusa <ContratoNuevo/> — el
 * MISMO formulario del paso 2 de convertir un lead (numeración fija 2026-01- +
 * 6 dígitos, co-titulares, preview del cronograma).
 */
function NuevoContratoDialog({ onCerrar, onCreado }: { onCerrar: () => void; onCreado: () => void }) {
  const [clientes, setClientes] = useState<ClienteBasico[] | null>(null)
  const [errorClientes, setErrorClientes] = useState<string | null>(null)
  const [clienteId, setClienteId] = useState('')
  const [paso, setPaso] = useState<'cliente' | 'form'>('cliente')

  useEffect(() => {
    const ac = new AbortController()
    listarClientes(ac.signal)
      .then((filas) => {
        if (!ac.signal.aborted) setClientes(filas)
      })
      .catch((e: unknown) => {
        if (ac.signal.aborted) return
        setErrorClientes(e instanceof CrmApiError ? e.message : 'No se pudo cargar tu cartera de clientes.')
      })
    return () => ac.abort()
  }, [])

  const cliente = clientes?.find((c) => c.id === clienteId) ?? null

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
          <p className="text-xs font-semibold text-destructive">{errorClientes}</p>
        ) : clientes == null ? (
          <div className="space-y-2" aria-busy>
            <Skeleton className="h-9 w-full" />
          </div>
        ) : clientes.length === 0 ? (
          <p className="text-xs leading-relaxed text-muted-foreground">
            Tu cartera aún no tiene clientes. Primero crea al cliente (o convierte un lead) y luego su contrato.
          </p>
        ) : (
          <div className="space-y-1.5">
            <Label htmlFor="nc-cliente">Cliente</Label>
            <Select id="nc-cliente" value={clienteId} onChange={(e) => setClienteId(e.target.value)}>
              <option value="">— Seleccionar cliente —</option>
              {clientes.map((c) => (
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
