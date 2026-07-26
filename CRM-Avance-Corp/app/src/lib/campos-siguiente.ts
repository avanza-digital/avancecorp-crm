// lib/campos-siguiente.ts — puente entre la SUGERENCIA del motor y los cuatro
// campos del formulario de cierre (tipo / título / fecha / hora), en los dos
// sentidos.
//
// EL BUG QUE ORIGINA ESTE MÓDULO (medido 2026-07-25, no deducido). La misma
// sugerencia se calculaba en DOS sitios de `cerrar-tarea.tsx`: un `useMemo`
// decidía si el panel "Siguiente acción propuesta" se VE, y una copia dentro
// del `onClick` de la opción elegida decidía qué DICE. Una tarea genérica tiene
// UNA sola opción ("Hecha") y nace preseleccionada → ese `onClick` no ocurre
// nunca → el panel salía visible pero EN BLANCO. Dos consecuencias reales:
//
//  1. Silenciosa: `conSiguiente` exige título no vacío, así que el asesor
//     cerraba "Enviar propuesta a Ana" —justo el eslabón POST-REUNIÓN, donde
//     más caro sale perder el hilo— y el lead se caía de la cadencia.
//  2. Dura: si el asesor escribía el título que faltaba y confirmaba,
//     `new Date('T10:00:00-05:00').toISOString()` lanzaba `RangeError` DENTRO
//     del onClick — la tarea NO se cerraba, nadie avisaba, y el diálogo se iba
//     al error boundary. Reproducible también con dos opciones si se BORRA la
//     fecha propuesta.
//
// El arreglo es matar la segunda fuente de verdad, no disparar el onClick a
// mano. Vive en lib/ por lo mismo que `contacto-tarea.ts`: es lógica pura
// testeable y `react(only-export-components)` prohíbe exportar
// no-componentes desde un archivo de componentes.
import { fechaLima, horaLima } from './agenda-derivada'
import type { SugerenciaSiguiente } from './motor-siguiente'
import type { TipoTarea } from './tipos'

/** Lo que el vendedor ve y edita. Fecha/hora SIEMPRE en reloj de Lima (-05:00). */
export interface CamposSiguiente {
  tipo: TipoTarea
  titulo: string
  fecha: string // 'AAAA-MM-DD' (input type=date)
  hora: string // 'HH:MM'      (input type=time)
}

/** Sugerencia del motor → los cuatro campos del formulario. */
export function camposDeSugerencia(s: SugerenciaSiguiente): CamposSiguiente {
  const ms = Date.parse(s.vence_en)
  return { tipo: s.tipo, titulo: s.titulo, fecha: fechaLima(ms), hora: horaLima(ms) }
}

/** Formas EXACTAS que emiten `<input type="date">` y `<input type="time">`. */
const RE_FECHA = /^\d{4}-\d{2}-\d{2}$/
const RE_HORA = /^\d{2}:\d{2}$/

/**
 * Los cuatro campos → ISO UTC, o `null` si NO forman un instante válido (un
 * input date/time vaciado a mano vale '').
 *
 * Devolver null en vez de construir el `Date` en el sitio ES la guarda: ese
 * `RangeError` de arriba salía de un `new Date(...).toISOString()` sin red.
 *
 * ⚠️ VALIDAR LA FORMA NO ES OPCIONAL, y `Number.isFinite` NO basta. Con fecha
 * Y hora vacías la plantilla queda en `'T:00-05:00'`, que **NO es NaN**:
 * `Date.parse` lo interpreta como el 1 de enero del **año 2000** (verificado
 * 2026-07-25). Sin estos dos regex, vaciar los dos campos agendaba la siguiente
 * acción 26 años en el pasado — en silencio y con el toast diciendo que todo
 * salió bien.
 *
 * OJO: esto tampoco valida CALENDARIO. `Date.parse('2026-02-31T10:00:00-05:00')`
 * no es NaN (rueda al 3 de marzo). El `input type=date` ya impide fechas
 * imposibles; aquí se ataja el vacío y la basura.
 */
export function isoDeCampos(c: CamposSiguiente): string | null {
  if (!RE_FECHA.test(c.fecha) || !RE_HORA.test(c.hora)) return null
  const ms = Date.parse(`${c.fecha}T${c.hora}:00-05:00`)
  return Number.isFinite(ms) ? new Date(ms).toISOString() : null
}
