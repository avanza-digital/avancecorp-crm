import { useEffect, useId, useRef, useState, type JSX } from 'react'
import { CalendarClock, Info, TriangleAlert, X } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { useCierreMesEstado } from '@/data/crm-queries'
import { useAuth } from '@/lib/auth-context'
import { avisoDelCiclo, type AvisoCierreMes } from '@/lib/cierre-de-mes'
import { fmtDiaMes } from '@/lib/format'
import './aviso-cierre-mes.css'

function AvisoCompacto({ etiqueta, aviso }: { etiqueta: string; aviso: AvisoCierreMes }): JSX.Element {
  const [abierto, setAbierto] = useState(false)
  const id = useId()
  const raiz = useRef<HTMLDivElement>(null)
  const disparador = useRef<HTMLButtonElement>(null)
  const cerrar = () => { setAbierto(false); disparador.current?.focus() }

  useEffect(() => {
    if (!abierto) return
    const fuera = (evento: PointerEvent) => {
      if (!raiz.current?.contains(evento.target as Node)) setAbierto(false)
    }
    const escape = (evento: KeyboardEvent) => {
      if (evento.key === 'Escape') {
        setAbierto(false)
        disparador.current?.focus()
      }
    }
    document.addEventListener('pointerdown', fuera)
    document.addEventListener('keydown', escape)
    return () => {
      document.removeEventListener('pointerdown', fuera)
      document.removeEventListener('keydown', escape)
    }
  }, [abierto])

  return <div className="aviso-cierre-compacto">
    <div ref={raiz} className="aviso-cierre-ancla" onBlur={(evento) => {
      if (!evento.currentTarget.contains(evento.relatedTarget)) setAbierto(false)
    }}>
      <button ref={disparador} type="button" className="aviso-cierre-disparador"
        aria-expanded={abierto} aria-controls={id} onClick={() => setAbierto(v => !v)}>
        {etiqueta}<Info aria-hidden />
      </button>
      {abierto && <section id={id} className="aviso-cierre-detalle" aria-labelledby={`${id}-titulo`}>
        <h2 id={`${id}-titulo`}>{aviso.titulo}</h2>
        <p>{aviso.detalle}</p>
        <button type="button" className="aviso-cierre-cerrar" aria-label="Cerrar detalle del cierre" onClick={cerrar}><X aria-hidden /></button>
      </section>}
    </div>
  </div>
}

/**
 * El aviso del ciclo del CIERRE DE MES, para quien puede actuar (gerencia):
 * del 1 al 10 recuerda cuántos días quedan de ajuste, el día 10 avisa que el
 * sello pasa a las 09:20, y pasado el día sin sellar suena la ALARMA — sin
 * ella, un cron roto es invisible hasta el reclamo de una comisión.
 *
 * Si la consulta cae no hay banner: es advisory (fail-open) y el candado real
 * vive en el servidor. El texto lo decide `avisoDelCiclo` desde el estado que
 * NOMBRA el servidor; aquí solo se pinta.
 */
export function AvisoCierreMesPanel({ compacto = false }: { compacto?: boolean }): JSX.Element | null {
  // DECISIÓN DE ROLES (fijada antes del release, 2026-08-15): el banner lo ve
  // SOLO GERENCIA — es quien puede actuar sobre el ciclo (anular, ajustar,
  // sellar a mano). Analista y supervisor no operan el cierre; el permiso del
  // coordinador en el SERVIDOR existe únicamente para que sus pantallas de
  // metas no fallen al leer `cierre`, no para este aviso. Y apagado en demo
  // DESDE DENTRO: el demo es hermético y esta consulta habla de la maquinaria
  // real. El gate vive aquí y no solo en la pantalla que lo monta: si alguien
  // lo monta en otra mañana, no hereda el olvido.
  const { yo } = useAuth()
  const puedeVerlo = Boolean(yo) && yo?.demo !== true && yo?.rol === 'gerencia'
  const estado = useCierreMesEstado(puedeVerlo)
  const aviso = puedeVerlo && estado.data ? avisoDelCiclo(estado.data) : null
  if (!aviso) return null
  const alarma = aviso.tono === 'alarma'
  const pendiente = estado.data?.pendiente
  if (compacto && !alarma && pendiente) return <AvisoCompacto
    key={`${pendiente.mes}:${pendiente.estado}`}
    etiqueta={`Cierre de ${pendiente.mes_nombre}: ${pendiente.estado === 'hoy' ? 'hoy' : fmtDiaMes(pendiente.cierra_el)}`}
    aviso={aviso}
  />
  const Icono = alarma ? TriangleAlert : CalendarClock
  return (
    <Card
      // El anuncio de un alert lo dispara la INSERCIÓN del nodo: si el estado
      // cambia de 'hoy' a 'atascado' con la pestaña abierta (refetch al
      // reenfocar), mutar el atributo sobre el mismo div no anuncia nada. El
      // key remonta la Card al cambiar el tono y la alarma sí suena.
      key={aviso.tono}
      role={alarma ? 'alert' : undefined}
      className={alarma
        ? `border-destructive/40 bg-destructive/[0.06]${compacto ? ' aviso-cierre-alarma mt-2' : ''}`
        : 'border-primary/25 bg-primary/[0.05]'}
    >
      <CardContent className="flex items-start gap-3 py-4">
        <Icono
          className={`mt-0.5 size-5 shrink-0 ${alarma ? 'text-destructive' : 'text-primary'}`}
          aria-hidden
        />
        <div>
          {/* Solo la PRIMERA letra: `capitalize` pondría Mayúscula En Cada Palabra. */}
          <h2 className="text-sm font-extrabold text-foreground first-letter:uppercase">{aviso.titulo}</h2>
          <p className="mt-1 text-xs text-foreground/70">{aviso.detalle}</p>
        </div>
      </CardContent>
    </Card>
  )
}
