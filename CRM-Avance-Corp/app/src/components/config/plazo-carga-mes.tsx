import { useEffect, useId, useRef, useState, type JSX } from 'react'
import { CalendarClock, CircleCheck, RefreshCw, TriangleAlert, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { mensajeDeError } from '@/data/crm-api'
import { useFijarPlazoCargaMes, usePlazosCargaMes } from '@/data/crm-queries'
import { useAuth } from '@/lib/auth-context'
import {
  AVISO_PLAZO_VENCIDO,
  CODIGO_PLAZO_NO_DISPONIBLE,
  accionDelMes,
  codigoDeError,
  conMayuscula,
  estadoDelPlazo,
  lineaDecision,
  lineaDelPlazo,
  resumenPlazoFijado,
  type MesPlazoCarga,
  type ResumenPlazoFijado,
} from '@/lib/plazo-carga-mes'
import { useCRMData } from '@/lib/store-context'
import { PlazoCargaDialogo } from './plazo-carga-dialogo'

const CAJA = 'rounded-xl border border-border bg-card text-card-foreground shadow-[var(--shadow-card)]'

/** Lo que tarda Radix en devolver el fondo y el foco al cerrar (setTimeout 0 + un cuadro), con margen. */
const RETRASO_AVISO_MS = 150

/**
 * «Plazo de carga»: hasta qué día cuentan las ventas de cada mes, y la mano de
 * Gerencia para ampliarlo o reabrir el mes ya sellado (pedido de Miguel del
 * 14/10, cuando septiembre se selló con ventas sin cargar).
 *
 * Va junto al aviso del ciclo de cierre porque es la misma decisión vista
 * desde el otro lado: el aviso dice cuándo se sella; esta tarjeta, hasta
 * cuándo se carga y quién lo movió.
 *
 * Solo GERENCIA y nunca en demo, decidido DESDE DENTRO como el aviso: si
 * alguien la monta en otra mañana no hereda el olvido. Qué botón tiene cada mes
 * (ampliar, reabrir o ninguno) lo dice el servidor; aquí solo se pinta.
 */
export function PlazoCargaMesPanel(): JSX.Element | null {
  const { yo } = useAuth()
  const puedeVerlo = Boolean(yo) && yo?.demo !== true && yo?.rol === 'gerencia'
  const consulta = usePlazosCargaMes(puedeVerlo)
  const fijar = useFijarPlazoCargaMes()
  const { recargar } = useCRMData()
  const [editando, setEditando] = useState<string | null>(null)
  const [resultado, setResultado] = useState<ResumenPlazoFijado | null>(null)
  const idTitulo = useId()
  // El título es el ANCLA del foco (tabIndex -1: destino programático, no
  // alcanzable con Tab). Recoge el foco cuando se desmonta el botón que lo
  // tenía —«Reintentar» al volver a pedir, «Cerrar el aviso»—, que si no caería
  // a <body> y obligaría a retabular la pantalla (precedente: aviso-degradacion).
  const ancla = useRef<HTMLHeadingElement>(null)
  const botonReintentar = useRef<HTMLButtonElement>(null)
  const botonCerrarAviso = useRef<HTMLButtonElement>(null)
  const esperandoFoco = useRef(false)
  // El resumen se escribe al CERRAR el diálogo, no al guardar: con el modal
  // abierto, Radix oculta el fondo (aria-hidden) y con él la región que lo
  // anuncia; y el foco vuelve al botón de la fila un cuadro después de cerrar.
  const resumenPendiente = useRef<ResumenPlazoFijado | null>(null)
  const temporizadorAviso = useRef<ReturnType<typeof setTimeout> | null>(null)

  const datos = consulta.data
  const noDisponible = !datos && consulta.isError && codigoDeError(consulta.error) === CODIGO_PLAZO_NO_DISPONIBLE
  const mostrandoError = puedeVerlo && !datos && consulta.isError && !noDisponible
  const errorPrevio = useRef(mostrandoError)

  // En TanStack v5, volver a pedir una consulta sin datos la pone en `pending`
  // en el mismo clic: el bloque de error (y su botón enfocado) se desmonta ya.
  useEffect(() => {
    const desaparecio = errorPrevio.current && !mostrandoError
    errorPrevio.current = mostrandoError
    if (!desaparecio || !esperandoFoco.current) return
    esperandoFoco.current = false
    // Solo si el foco quedó huérfano: si la persona ya se movió, no se le roba.
    const foco = document.activeElement
    if (!foco || foco === document.body) ancla.current?.focus()
  }, [mostrandoError])

  useEffect(() => () => {
    if (temporizadorAviso.current) clearTimeout(temporizadorAviso.current)
  }, [])

  if (!puedeVerlo || noDisponible) return null
  // Sin meses no hay nada que decidir (el servidor siempre manda el mes en curso).
  if (datos && datos.meses.length === 0) return null

  const enEdicion = datos?.meses.find((mes) => mes.mes === editando) ?? null

  function abrir(mes: string) {
    if (temporizadorAviso.current) clearTimeout(temporizadorAviso.current)
    temporizadorAviso.current = null
    setResultado(null)
    setEditando(mes)
  }

  async function guardar(mes: MesPlazoCarga, ultimoDia: string, motivo: string) {
    const acuse = await fijar.mutateAsync({ mes: mes.mes, ultimoDia, motivo })
    resumenPendiente.current = resumenPlazoFijado(acuse, mes.mes_nombre)
    // Reabrir devuelve ventas a su mes y las saca del mes en curso, cuyo
    // cumplimiento el store cargó al entrar (no vive en TanStack): sin esto,
    // Equipo seguiría contándolas donde ya no están.
    if (acuse.reabierto) void recargar()
  }

  function cerrarDialogo() {
    setEditando(null)
    const resumen = resumenPendiente.current
    resumenPendiente.current = null
    if (!resumen) return
    // Después de que Radix devuelva el fondo y el foco (setTimeout 0 + un
    // cuadro): el aviso se anuncia tras el botón, no bajo el modal que se va.
    temporizadorAviso.current = setTimeout(() => {
      temporizadorAviso.current = null
      setResultado(resumen)
    }, RETRASO_AVISO_MS)
  }

  function cerrarAviso() {
    if (document.activeElement === botonCerrarAviso.current) ancla.current?.focus()
    setResultado(null)
  }

  return (
    <section aria-labelledby={idTitulo} aria-busy={!datos && !consulta.isError ? true : undefined} className={CAJA}>
      <header className="flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-border px-5 py-3">
        <CalendarClock className="size-5 shrink-0 text-accent" aria-hidden />
        <h2 ref={ancla} id={idTitulo} tabIndex={-1} className="text-base font-extrabold text-foreground outline-none">Plazo de carga</h2>
        <p className="text-sm text-muted-foreground-strong">Hasta qué día cuentan las ventas de cada mes.</p>
      </header>

      {datos ? (
        <div role="list" aria-label="Plazo de carga por mes" className="divide-y divide-border">
          {datos.meses.map((mes) => (
            <FilaMes key={mes.mes} mes={mes} hoy={datos.hoy} onAccion={() => abrir(mes.mes)} />
          ))}
        </div>
      ) : mostrandoError ? (
        <div className="flex flex-wrap items-center justify-between gap-3 px-5 py-3">
          {/* Solo el mensaje es vivo: con el botón dentro, el anuncio arrastraba «Reintentar». */}
          <p role="status" className="flex items-center gap-2 text-sm font-semibold text-destructive-text">
            <TriangleAlert className="size-4 shrink-0" aria-hidden />
            {mensajeDeError(consulta.error, 'No se pudo leer el plazo de carga.')}
          </p>
          <Button ref={botonReintentar} type="button" variant="outline" className="h-10"
            // Hoy de Gerencia ya tiene otros «Reintentar»: el nombre dice cuál es este.
            aria-label="Reintentar la carga del plazo de carga"
            onClick={() => {
              // Solo hay foco que rescatar si estaba AQUÍ (Safari no enfoca al hacer clic).
              esperandoFoco.current = document.activeElement === botonReintentar.current
              void consulta.refetch()
            }}>
            <RefreshCw aria-hidden /> Reintentar
          </Button>
        </div>
      ) : (
        <div className="space-y-3 px-5 py-4">
          <span className="sr-only">Cargando el plazo de carga…</span>
          <Skeleton className="h-5 w-2/3" aria-hidden />
          <Skeleton className="h-5 w-1/2" aria-hidden />
        </div>
      )}

      <div className={resultado ? 'flex items-start gap-3 border-t border-border bg-accent/[0.05] px-5 py-3' : undefined}>
        {resultado && <CircleCheck className="mt-0.5 size-5 shrink-0 text-accent" aria-hidden />}
        {/* Montada siempre y solo con texto: una región viva que nace con el
            texto no siempre se anuncia, y un botón dentro se leería con él. */}
        <div role="status" className="min-w-0 flex-1 space-y-1">
          {resultado && (
            <>
              <p className="text-base font-bold text-foreground">{resultado.titulo}</p>
              {resultado.lineas.map((linea) => <p key={linea} className="text-sm text-foreground/85">{linea}</p>)}
            </>
          )}
        </div>
        {resultado && (
          <Button ref={botonCerrarAviso} type="button" variant="ghost" size="icon" className="size-10 shrink-0"
            aria-label="Cerrar el aviso del plazo" onClick={cerrarAviso}>
            <X aria-hidden />
          </Button>
        )}
      </div>

      {datos && enEdicion && (
        <PlazoCargaDialogo
          key={enEdicion.mes}
          mes={enEdicion}
          hoy={datos.hoy}
          onConfirmar={(ultimoDia, motivo) => guardar(enEdicion, ultimoDia, motivo)}
          onCerrar={cerrarDialogo}
        />
      )}
    </section>
  )
}

/**
 * Un mes en UNA fila horizontal: lo que dice (nombre · hasta cuándo), quién lo
 * movió y el botón a la derecha. El nombre a 16 px y el detalle a 14 px, como
 * pide Miguel para lo que se lee de un vistazo.
 */
function FilaMes({ mes, hoy, onAccion }: { mes: MesPlazoCarga; hoy: string; onAccion: () => void }) {
  const estado = estadoDelPlazo(mes, hoy)
  const decision = lineaDecision(mes)
  const accion = accionDelMes(mes)
  return (
    <div role="listitem" className="flex flex-wrap items-center justify-between gap-x-6 gap-y-2 px-5 py-3">
      <div className="min-w-0 flex-1 space-y-0.5">
        <p className="text-base text-foreground">
          <strong className="font-bold">{conMayuscula(mes.mes_nombre)}</strong> · {lineaDelPlazo(mes, hoy)}
        </p>
        {estado === 'vencido' && <p className="text-sm font-semibold text-warning-text">{AVISO_PLAZO_VENCIDO}</p>}
        {decision && (
          <p className="text-sm text-muted-foreground-strong [overflow-wrap:anywhere]">
            {decision}{mes.decision && <> · «{mes.decision.motivo}»</>}
          </p>
        )}
        {!accion && mes.motivo_no_reabrible && (
          <p className="text-sm text-muted-foreground-strong">{mes.motivo_no_reabrible}</p>
        )}
      </div>
      {accion && (
        <Button type="button" variant="outline" className="h-10 shrink-0"
          // El nombre visible se repite por fila («Ampliar plazo»): el accesible dice de qué mes.
          aria-label={accion.tipo === 'ampliar' ? `${accion.etiqueta} de ${mes.mes_nombre}` : undefined}
          onClick={onAccion}>
          {accion.etiqueta}
        </Button>
      )}
    </div>
  )
}
