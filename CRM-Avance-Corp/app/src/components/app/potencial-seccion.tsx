// Sección «Potencial» de la ficha del lead: los tres botones para marcar y la
// nota que dice qué pasó con la marca o cuándo va a bajar sola.
//
// Quién marca lo decide el servidor (`puede_marcar`: el analista del lead y su
// supervisor, con el lead abierto). A quien no puede se le enseña la marca y
// la nota, sin botones. Con la bandera apagada la sección no existe.
//
// Cuándo y a qué nivel bajará la marca también lo dice el servidor: mientras
// una marca viaja (y hasta que termina la relectura) la nota dice «Guardando la
// marca…» en vez de adelantar una fecha calculada aquí.
//
// Para el lector de pantalla: la nota visible NO es región viva (se anunciaría
// sola al abrir cada ficha). Hay una región `role="status"` aparte, vacía hasta
// que la persona marca en ESTA ficha, que al terminar de guardar dice el nivel
// y la nota final («Estrella. Baja a Tibio…»).
import { useId, useLayoutEffect, useRef, useState, type CSSProperties, type FocusEvent } from 'react'
import { fechaLima } from '@/lib/agenda-derivada'
import { ETIQUETA_POTENCIAL, NIVELES_POTENCIAL, notaPotencial, type NivelPotencial } from '@/lib/potencial'
import type { Lead } from '@/lib/tipos'
import { useMarcarPotencial, usePotencialLead } from '@/data/potencial-queries'
import { ChipPotencial, IconoPotencial } from './potencial-chip'
import { seguirCursorPotencial, sinMovimiento } from './potencial-efectos'

// Diez chispas en abanico: destino, tamaño y retardo fijos (no hay azar que
// haga distinta cada captura).
const CHISPAS = Array.from({ length: 10 }, (_, i) => {
  const angulo = (i / 10) * Math.PI * 2 + (i % 2) * 0.2
  const distancia = 30 + (i % 3) * 10
  return {
    x: Math.round(Math.cos(angulo) * distancia),
    y: Math.round(Math.sin(angulo) * distancia),
    lado: 3 + (i % 2) * 2,
    retardo: (i % 3) * 0.04,
  }
})

/** Chispas doradas al confirmar Estrella. Decorativas: sin movimiento, no salen. */
function Chispas() {
  if (sinMovimiento()) return null
  return (
    <span className="pot-chispas" aria-hidden>
      {CHISPAS.map((c, i) => (
        <span
          // Lista fija que nunca se reordena: el índice es su identidad.
          key={i}
          className="pot-chispa"
          style={{
            width: c.lado,
            height: c.lado,
            marginLeft: -c.lado / 2,
            marginTop: -c.lado / 2,
            animationDelay: `${c.retardo}s`,
            '--pot-dx': `${c.x}px`,
            '--pot-dy': `${c.y}px`,
          } as CSSProperties}
        />
      ))}
    </span>
  )
}

export function SeccionPotencial({ lead }: { lead: Pick<Lead, 'id' | 'etapa'> }) {
  const { habilitada, item } = usePotencialLead(lead.id)
  const { marcar, marcando } = useMarcarPotencial()
  const [chispas, setChispas] = useState(0)
  // ¿La persona marcó en ESTA ficha? Hasta entonces la región viva calla.
  const [marcoAqui, setMarcoAqui] = useState(false)
  const idRotulo = useId()
  const refSeccion = useRef<HTMLElement>(null)
  // ¿El foco está en uno de los tres botones? Si dejan de existir con el foco
  // dentro (ya no se puede marcar), el foco pasa a la sección en vez de perderse.
  const focoEnBotones = useRef(false)

  // El cierre se mira TAMBIÉN aquí: el store pasa el lead a convertido o
  // descartado antes de que el servidor conteste, y en ese instante la marca
  // ya no debe ofrecerse.
  const cerrado = lead.etapa === 'convertido' || lead.etapa === 'descartado'
  const puedeMarcar = habilitada && item != null && item.puede_marcar && !cerrado

  // De capa (no `useEffect`): corre en el mismo commit que desmonta los
  // botones, antes de que el panel de la ficha decida por su cuenta adónde
  // mandar un foco huérfano.
  useLayoutEffect(() => {
    if (puedeMarcar || !focoEnBotones.current) return
    focoEnBotones.current = false
    const activo = document.activeElement
    if (activo == null || activo === document.body) refSeccion.current?.focus()
  }, [puedeMarcar])

  if (!habilitada || !item) return null

  const nota = marcando ? 'Guardando la marca…' : notaPotencial(item, { cerrado, hoy: fechaLima(Date.now()) })
  const anuncio = marcoAqui && !marcando && item.nivel != null ? `${ETIQUETA_POTENCIAL[item.nivel]}. ${nota}` : ''

  const elegir = (nivel: NivelPotencial) => {
    // Una marca a la vez: la anterior aún viaja al servidor. Los botones lo
    // dicen con `aria-disabled` (no `disabled`: quitaría el foco al que se
    // acaba de pulsar); además de esta guarda, el hook corta por su cuenta una
    // segunda marca aunque esta pantalla aún no se haya vuelto a pintar.
    if (marcando) return
    const yaEraEstrella = item.nivel === 'estrella' && item.origen === 'manual'
    marcar(lead.id, nivel)
    setMarcoAqui(true)
    if (nivel === 'estrella' && !yaEraEstrella) setChispas((n) => n + 1)
  }

  const alSalirElFoco = (e: FocusEvent<HTMLButtonElement>) => {
    // Solo es una salida si el foco se fue a OTRO elemento. Cuando los botones
    // se desmontan con el foco dentro no hay destino (`relatedTarget` nulo).
    if (e.relatedTarget instanceof Node) focoEnBotones.current = false
  }

  return (
    <section
      ref={refSeccion}
      tabIndex={-1}
      aria-labelledby={idRotulo}
      className="rounded-lg outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
    >
      <h3 id={idRotulo} className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Potencial</h3>
      {/* UNA región viva, siempre montada y vacía hasta que la persona marque
          aquí: una región que nace con texto no se anuncia, y la nota visible
          se leería sola al abrir cada ficha. */}
      <p role="status" className="sr-only">{anuncio}</p>
      {puedeMarcar ? (
        <div role="group" aria-label="Potencial del lead" aria-busy={marcando ? true : undefined} className="pot-segmento">
          {NIVELES_POTENCIAL.map((nivel) => {
            const activa = item.nivel === nivel
            const estrellaActiva = activa && nivel === 'estrella'
            return (
              <button
                key={nivel}
                type="button"
                aria-pressed={activa}
                aria-disabled={marcando ? true : undefined}
                className={`pot-seg pot-seg--${nivel}`}
                onClick={() => elegir(nivel)}
                onFocus={() => { focoEnBotones.current = true }}
                onBlur={alSalirElFoco}
                {...(estrellaActiva ? { onPointerMove: seguirCursorPotencial } : {})}
              >
                <IconoPotencial nivel={nivel} relleno={estrellaActiva} grosor={2.4} className="pot-seg-ico" />
                {ETIQUETA_POTENCIAL[nivel]}
                {nivel === 'estrella' && chispas > 0 && <Chispas key={chispas} />}
              </button>
            )
          })}
        </div>
      ) : (
        item.nivel != null && <p className="mt-2"><ChipPotencial marca={item} /></p>
      )}
      <p className="pot-nota">{nota}</p>
    </section>
  )
}
