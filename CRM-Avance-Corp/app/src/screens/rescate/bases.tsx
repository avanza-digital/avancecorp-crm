// Pestaña «Bases» de la base para gestión (F5, decisiones E1–E14 de Miguel, 03–04/10/2026), para Supervisión y Gerencia:
//  · la HOJA de bases (`crm.seguimiento_bases`): una fila por base con su avance; pastillas pequeñas arriba (las que
//    tienen algo detrás filtran la hoja) y todo número se abre;
//  · «Cargar base»: subir un archivo o armarla con descartados del CRM (E1);
//  · dentro de una base: el reparto (por cantidades o por selección) y el seguimiento por analista, con «Recoger».
// La base abierta vive en la URL (`?rescate_vista=bases&rescate_base=…`). ESTADO DE PRODUCCIÓN (gate de realidad): sin la
// B10 el servidor no conoce `seguimiento_bases` (PGRST202) → «Bases: disponible pronto» y nada más (sin la hoja no se
// podría repartir ni seguir lo que se cargue); con la B10 y sin bases → la hoja vacía con «Cargar base».
import { Suspense, lazy, useEffect, useMemo, useRef, useState, type JSX } from 'react'
import { toast } from 'sonner'
import { Layers, Plus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PanelCargando, PanelVacio } from '@/components/common/estado-panel'
import { Pastilla } from '@/components/base-gestion/filtros-base'
import { HojaBases } from '@/components/bases-cargadas/hoja-bases'
import { DetalleBase } from '@/components/bases-cargadas/detalle-base'
import { DetalleCifraBase, type CifraBaseAbierta } from '@/components/bases-cargadas/detalle-cifra-base'
import { AvisoReintentar, DisponiblePronto } from '@/components/bases-cargadas/piezas-bases'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { useEsMovil } from '@/lib/media'
import { usePuertasBases, useSeguimientoBaseDetalle, useSeguimientoBases } from '@/data/bases-cargadas-queries'
import { analistasDelReparto, supervisoresActivos, type CifraBase, type FilaSeguimientoBases } from '@/lib/bases-cargadas'

type FiltroHoja = 'sin_repartir' | 'sin_tocar' | null

// «Cargar base» (lector de archivos, vista previa, informe, armar desde el CRM) se descarga al abrirla.
const CargarBase = lazy(() => import('@/components/bases-cargadas/cargar-base').then((m) => ({ default: m.CargarBase })))

export function BasesSupervision({ base, onBase }: {
  /** La base abierta (de la URL) o null: la hoja de bases. */
  base: string | null
  onBase: (base: string | null) => void
}): JSX.Element {
  const { yo } = useAuth()
  const { equipo } = useCRMData()
  const esMovil = useEsMovil()
  const ahora = useAhora()
  const puertas = usePuertasBases()
  const lista = useSeguimientoBases(puertas)
  const [cargarAbierta, setCargarAbierta] = useState(false)
  const [filtro, setFiltro] = useState<FiltroHoja>(null)
  const [cifra, setCifra] = useState<CifraBaseAbierta | null>(null)
  const detalle = useSeguimientoBaseDetalle(puertas, cifra && { baseId: cifra.baseId, analistaId: cifra.analistaId, cifra: cifra.cifra })
  const regionHoja = useRef<HTMLDivElement>(null)
  const botonCargar = useRef<HTMLButtonElement>(null)
  const esGerencia = yo?.rol === 'gerencia'
  const supervisores = useMemo(() => supervisoresActivos(equipo), [equipo])

  const filas = lista.data ?? []
  const abierta: FilaSeguimientoBases | null = base ? filas.find((f) => f.base_id === base) ?? null : null
  const analistas = useMemo(
    () => (yo ? analistasDelReparto(equipo, yo, abierta?.supervisor_id ?? null) : []),
    [equipo, yo, abierta?.supervisor_id],
  )
  // Una base de la URL que ya no está en la lista (se retiró, o salió del ámbito) no deja la pantalla en blanco.
  const perdida = base !== null && lista.isSuccess && lista.data !== null && abierta === null
  useEffect(() => {
    if (!perdida) return
    onBase(null)
    toast.info('Esa base ya no está entre tus bases.')
  }, [perdida, onBase])

  if (!yo) return <PanelVacio icono={Layers} titulo="Sin sesión" detalle="Vuelve a entrar para ver las bases." />
  if (lista.isPending) return <div className="rounded-lg border border-border bg-card pt-4"><PanelCargando filas={5} /></div>
  if (lista.isError && lista.data === undefined) {
    return <AvisoReintentar mensaje="No se pudieron cargar las bases." reintentando={lista.isFetching} onReintentar={() => void lista.refetch()} />
  }
  if (lista.data === null) {
    return (
      <DisponiblePronto
        titulo="Bases: disponible pronto"
        detalle="Cargar bases (archivo o desde el CRM), repartirlas a tu equipo y ver si se trabajan llega con la próxima actualización del servidor."
      />
    )
  }

  const abrirCifraBase = (f: FilaSeguimientoBases, c: CifraBase) =>
    setCifra({ baseId: f.base_id, baseNombre: f.nombre, analistaId: null, analistaNombre: null, cifra: c, valor: f[c] })
  const verBase = (baseId: string) => { setFiltro(null); onBase(baseId) }
  const volver = () => {
    const anterior = base
    onBase(null)
    // El foco vuelve a la base de la que se salió (o a la hoja), no a <body>.
    requestAnimationFrame(() => (document.querySelector<HTMLElement>(`[data-foco-clave="base-carga-${anterior}"]`) ?? regionHoja.current)?.focus())
  }
  const sumar = (c: keyof Pick<FilaSeguimientoBases, 'total' | 'sin_repartir' | 'sin_tocar'>) => filas.reduce((s, f) => s + f[c], 0)
  const visibles = filtro ? filas.filter((f) => f[filtro] > 0) : filas
  const alternar = (f: Exclude<FiltroHoja, null>) => setFiltro((x) => (x === f ? null : f))

  return (
    <div className="space-y-4">
      {abierta ? (
        <DetalleBase
          puertas={puertas}
          base={abierta}
          analistas={analistas}
          esMovil={esMovil}
          ahora={ahora}
          onVolver={volver}
          onAbrirCifra={(c) => abrirCifraBase(abierta, c)}
          onAbrirCifraAnalista={(f, c) => setCifra({ baseId: abierta.base_id, baseNombre: abierta.nombre, analistaId: f.analista_id, analistaNombre: f.analista_nombre, cifra: c, valor: f[c] })}
        />
      ) : (
        <>
          <div className="flex flex-wrap items-center justify-between gap-x-6 gap-y-3">
            <section aria-label="Resumen de las bases" className="flex flex-wrap items-center gap-2">
              <Pastilla etiqueta="Bases" valor={filas.length} />
              <Pastilla etiqueta="Contactos" valor={sumar('total')} />
              <Pastilla etiqueta="Sin repartir" valor={sumar('sin_repartir')} presionada={filtro === 'sin_repartir'} pista="ver solo esas bases" onAbrir={sumar('sin_repartir') > 0 || filtro === 'sin_repartir' ? () => alternar('sin_repartir') : undefined} />
              <Pastilla etiqueta="Sin tocar" valor={sumar('sin_tocar')} presionada={filtro === 'sin_tocar'} pista="ver solo esas bases" onAbrir={sumar('sin_tocar') > 0 || filtro === 'sin_tocar' ? () => alternar('sin_tocar') : undefined} />
            </section>
            <Button ref={botonCargar} type="button" className="h-10 pointer-coarse:h-11" onClick={() => setCargarAbierta(true)}>
              <Plus aria-hidden /> Cargar base
            </Button>
          </div>
          {lista.isError && <AvisoReintentar mensaje="No se pudo actualizar la hoja de bases. Se muestran los últimos datos." reintentando={lista.isFetching} onReintentar={() => void lista.refetch()} />}
          {filas.length === 0 ? (
            <div className="rounded-lg border border-border bg-card">
              <PanelVacio
                icono={Layers}
                titulo="Todavía no hay bases"
                detalle={`Carga un Excel con contactos antiguos o arma una base con descartados del CRM; después repártela a tu equipo ${esGerencia ? '(o a cualquier analista)' : ''} y sigue cómo la trabajan.`}
              >
                <Button type="button" className="mt-1 h-10 pointer-coarse:h-11" onClick={() => setCargarAbierta(true)}>
                  <Plus aria-hidden /> Cargar base
                </Button>
              </PanelVacio>
            </div>
          ) : (
            <HojaBases filas={visibles} esMovil={esMovil} onAbrirBase={verBase} onAbrirCifra={abrirCifraBase} regionRef={regionHoja} />
          )}
          <p className="text-sm text-[var(--muted-foreground-strong)]">
            Avance = trabajados ÷ repartidos. Un contacto repartido que nadie toca en 3 días se marca en rojo dentro de su base; nada se mueve solo.
          </p>
        </>
      )}

      {cargarAbierta && (
        <Suspense fallback={<p role="status" className="text-sm text-[var(--muted-foreground-strong)]">Abriendo «Cargar base»…</p>}>
          <CargarBase
            abierta={cargarAbierta}
            puertas={puertas}
            esGerencia={esGerencia}
            supervisores={supervisores}
            onCerrar={() => setCargarAbierta(false)}
            onVerBase={verBase}
          />
        </Suspense>
      )}
      <DetalleCifraBase
        abierta={cifra}
        filas={detalle.data}
        cargando={detalle.isPending}
        error={detalle.isError}
        reintentando={detalle.isFetching}
        onReintentar={async () => (await detalle.refetch()).isSuccess}
        ahora={ahora}
        esMovil={esMovil}
        onCerrar={() => setCifra(null)}
      />
    </div>
  )
}
