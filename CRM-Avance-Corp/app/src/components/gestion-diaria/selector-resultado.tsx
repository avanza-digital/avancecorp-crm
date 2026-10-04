// Selector «¿Qué pasó con la llamada?»: los siete resultados tipificados con
// sus atajos 1–7 y el botón «Cambiar / Mantener resultado». Es SOLO la
// presentación del paso 1 (refactor del 03/10/2026): Gestión Diaria lo monta
// dentro de `CamposResultado` y la Base para gestión lo adoptará después, para
// que el resultado de una llamada se elija igual en todo el CRM.
//
// CONTROLADO: quien lo monta guarda el resultado (`valor`) y si la lista está a
// la vista (`abierto`); aquí solo se avisa (`onElegir`, `onAlternar`). Lo que sí
// vive aquí, porque es del selector y no de quien lo monta:
// - los atajos 1–7, escuchados en el documento (el foco inicial de un diálogo
//   queda en su contenedor, fuera de este árbol) pero acotados con `dentro`
//   (WCAG 2.1.4), fuera de los campos de texto y sin modificadores. Con la
//   lista contraída solo vale el atajo del resultado ya elegido: así un dígito
//   suelto no cambia el resultado sin querer;
// - el foco tras elegir o alternar, que vuelve al radio elegido (buscado en el
//   div propio del selector, nunca en la pantalla entera);
// - el filtro de opciones (contraído = solo la elegida).
// El foco INICIAL no entra: lo decide quien lo monta (la tarjeta «Ahora» lo
// lleva al primer radio; el diálogo, a su contenedor).
//
// Para congelarlo mientras se guarda, móntalo dentro de un `<fieldset disabled>`
// (radios y «Cambiar resultado» quedan inertes) y pasa `deshabilitado` para que
// los atajos también se ignoren.
import { useEffect, useRef, type JSX, type ReactNode } from 'react'
import { Button } from '@/components/ui/button'
import { RadioGroup, type OpcionRadio } from '@/components/ui/radio-group'
import { esCampoDeTexto } from '@/lib/campo-de-texto'
import { RESULTADOS, type ResultadoLlamada } from '@/lib/resultado-llamada'

/** Ayuda fija con la lista contraída. */
const AYUDA_CONTRAIDO = 'Para elegir otro, usa «Cambiar resultado».'

export interface SelectorResultadoProps {
  /** Resultado elegido; `null` = todavía ninguno. */
  valor: ResultadoLlamada | null
  /** `true` = los siete a la vista; `false` = contraído en el elegido. */
  abierto: boolean
  /** Se eligió `r` (clic o atajo, según `desdeAtajo`). Quien lo monta guarda el
   *  valor y contrae la lista (`abierto = false`), aunque `r` sea el mismo. */
  onElegir: (r: ResultadoLlamada, desdeAtajo: boolean) => void
  /** «Cambiar resultado» / «Mantener resultado»: invertir `abierto`. */
  onAlternar: () => void
  /** ¿La tecla pertenece a ESTA presentación? Fuera de ella los atajos no cuentan. */
  dentro: (objetivo: EventTarget | null) => boolean
  /** Sufijo ÚNICO por instancia: el grupo se llama `resultado-llamada-<nombre>`.
   *  Dos grupos con el mismo `name` fuera de un <form> son UNO para el navegador;
   *  el prefijo es contrato de los e2e (`input[name^="resultado-llamada"]`). */
  nombre: string
  /** Id del div de las opciones (lo controla «Cambiar resultado»). */
  idOpciones: string
  /** Título del grupo (`legend`). */
  leyenda: ReactNode
  /** Ayuda bajo cada resultado. Sin pasar = la de `RESULTADOS`; `null` = sin
   *  ayuda (presentación compacta); un mapa = esas ayudas (la que falte, sin ayuda). */
  detalles?: Partial<Record<ResultadoLlamada, ReactNode>> | null | undefined
  /** Ayuda del grupo con la lista abierta (cómo funcionan los atajos). */
  ayudaAtajos: ReactNode
  /** Piso de 16 px (formularios operativos, el diálogo). */
  grande?: boolean | undefined
  /** Ignora los atajos (p. ej. mientras guarda). No deshabilita radios ni botón:
   *  eso lo hace el `<fieldset disabled>` que lo envuelve. */
  deshabilitado?: boolean | undefined
  invalido?: boolean | undefined
  /** Ids externos que también describen el grupo (se suman a la ayuda propia). */
  describedBy?: string | undefined
}

export function SelectorResultado({
  valor, abierto, onElegir, onAlternar, dentro, nombre, idOpciones, leyenda, detalles, ayudaAtajos, grande = false, deshabilitado = false, invalido, describedBy,
}: SelectorResultadoProps): JSX.Element {
  const contenedor = useRef<HTMLDivElement>(null)
  // Tras elegir o alternar, el foco vuelve al radio elegido: el que se pulsó
  // sigue existiendo, pero el botón que alterna cambia de texto y los otros
  // seis desaparecen al contraer.
  const enfocar = useRef(false)

  const elegir = (r: ResultadoLlamada, desdeAtajo: boolean) => {
    enfocar.current = true
    onElegir(r, desdeAtajo)
  }

  // El listener se monta UNA vez y lee lo último pintado por referencia.
  const elegirRef = useRef(elegir)
  elegirRef.current = elegir
  const dentroRef = useRef(dentro)
  dentroRef.current = dentro
  const estado = useRef({ abierto, valor, deshabilitado })
  estado.current = { abierto, valor, deshabilitado }

  useEffect(() => {
    if (!enfocar.current || !valor) return
    enfocar.current = false
    contenedor.current?.querySelector<HTMLInputElement>(`input[type="radio"][value="${valor}"]`)?.focus()
  }, [abierto, valor])

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.altKey || e.ctrlKey || e.metaKey || e.isComposing || esCampoDeTexto(e.target)) return
      if (!dentroRef.current(e.target)) return
      const r = RESULTADOS.find((x) => x.atajo === e.key)
      if (!r) return
      // El dígito es del selector aunque hoy no haga nada (deshabilitado o
      // contraído en otro resultado): no sigue su camino por la pantalla.
      e.preventDefault()
      const { abierto: estaAbierto, valor: elegido, deshabilitado: congelado } = estado.current
      if (congelado) return
      if (!estaAbierto && r.clave !== elegido) return
      elegirRef.current(r.clave, true)
    }
    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [])

  const opciones: OpcionRadio<ResultadoLlamada>[] = RESULTADOS
    .filter((r) => abierto || r.clave === valor)
    .map((r) => ({
      valor: r.clave,
      etiqueta: r.etiqueta,
      detalle: detalles === undefined ? r.detalle : (detalles?.[r.clave] ?? undefined),
      atajo: r.atajo,
    }))

  return (
    <>
      <div id={idOpciones} ref={contenedor}>
        <RadioGroup<ResultadoLlamada>
          grande={grande} leyenda={leyenda} opciones={opciones} valor={valor} onCambio={(r) => elegir(r, false)} obligatorio
          nombre={`resultado-llamada-${nombre}`} descripcion={abierto ? ayudaAtajos : AYUDA_CONTRAIDO} invalido={invalido} describedBy={describedBy}
        />
      </div>
      {valor && <Button type="button" variant="outline" size={grande ? 'default' : 'sm'} aria-expanded={abierto} aria-controls={idOpciones} onClick={() => {
        enfocar.current = true
        onAlternar()
      }}>{abierto ? 'Mantener resultado' : 'Cambiar resultado'}</Button>}
    </>
  )
}
