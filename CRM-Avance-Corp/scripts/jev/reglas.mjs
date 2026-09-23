// Lo que en esta casa YA está decidido. Sin esto, Jev no puede distinguir un
// defecto de una regla acordada: el 21/09, 26 de 41 hallazgos se refutaron por
// «se decidió así», y ninguna de esas decisiones estaba en el texto del
// hallazgo. Medido: sin estas reglas, AUC 0.47 (azar).
//
// Fuente: vault (`Conversion mensual - definicion cerrada`, «Refutados por los
// verificadores», reglas de Miguel) y el dictamen de Codex del 21/09.
export const REGLAS_DECIDIDAS = [
  'La conversion se mide sobre los leads que LLEGARON en el mes; los descartados cuentan en el divisor.',
  'Un lead referido pesa 0.15 en el divisor, no 1: se decidio ponderar, no excluir.',
  'Las altas manuales con origen landing o formulario NO entran en el divisor, pero SI cuentan entero en el numerador cuando cierran. Esa asimetria esta DECIDIDA por Miguel (21/09/2026) y no es un defecto: no se vuelve a levantar como hallazgo.',
  'Para las operaciones de cartera se cuenta UNA por cliente y mes calendario; se decidio el 04/09 que el mes manda sobre el rango.',
  'Solo la anulacion retrocede una conversion: es la unica puerta, y es una sancion al analista, no un borrado del capital.',
  'La cosecha (cerraron / llegaron) es OTRA pregunta distinta del indice comercial, y se publica con su propio rotulo.',
  'Hay UNA sola meta de empresa replicada a cada analista; no es una media de metas distintas.',
  'El bloque «Aporte de X» con un filtro de fuente es global por diseno: numerador de esa fuente sobre la base global.',
  'Las etapas del embudo se infieren y estan rotuladas como inferidas; eso esta decidido y aceptado.',
  'La lectura por RANGO puede ser bruta y legitima si el rotulo lo dice; lo que no puede es presentarse como el indice mensual.',
  'El campo `conversion_pct` legado de metricas_vendedores_fn ya no lo lee nadie en el front.',
  'Un cierre de arrastre (lead de un mes anterior que cierra este mes) suma al numerador del mes de cierre: es la regla, no un error.',
  'El front NUNCA divide: todo porcentaje se sirve calculado desde el servidor. Duplicar el calculo en el navegador es un defecto aunque el numero salga bien.',
  'Ninguna pantalla puede fabricar un 0 cuando la consulta falla: se muestra el fallo, no un cero.',
  'Un numero correcto bajo un rotulo que dice otra cosa (otro periodo, otra pregunta) es tan defecto como un numero mal calculado.',
];

/** Segunda versión del triaje: la pregunta que de verdad se quiere responder
 *  («¿hay que arreglar esto?»), con las reglas decididas delante. */
export function esDefecto(hallazgo) {
  const h = {
    titulo: hallazgo.titulo ?? '',
    archivo: (hallazgo.archivo ?? '').split('/').slice(-1)[0],
    lineas: hallazgo.lineas ?? '',
    evidencia_citada: hallazgo.evidencia ?? '',
    impacto_declarado: hallazgo.impacto_gerencia ?? '',
  };
  return {
    state: { reglas_ya_decididas: REGLAS_DECIDIDAS, hallazgo: h },
    questions: {
      contra_regla: {
        type: 'noul',
        instructions: 'Un auditor reporta `hallazgo`. El equipo ya tomo las decisiones de `reglas_ya_decididas`. ¿Lo que el hallazgo denuncia es precisamente una de esas decisiones, es decir, el comportamiento es intencionado y esta acordado?',
        criteria: {
          true: 'Alguna regla de la lista describe y aprueba justo el comportamiento que el hallazgo denuncia',
          false: 'Ninguna regla de la lista cubre ese comportamiento, o la lista lo prohibe expresamente',
        },
      },
      dano_real: {
        type: 'noul',
        instructions: 'Segun `hallazgo` y teniendo en cuenta `reglas_ya_decididas`, ¿alguien de gerencia acabaria tomando una decision equivocada, o desconfiando del sistema, por culpa de esto?',
        criteria: {
          true: 'Cambia un numero publicado, su periodo o su significado, o hace que dos pantallas se contradigan',
          false: 'Es interno: duplicacion, orden del codigo, falta de prueba, o algo que el rotulo ya advierte',
        },
      },
      arreglar: {
        type: 'noul',
        instructions: 'Todo junto: ¿hay que cambiar el codigo por `hallazgo`, o se puede cerrar explicando que asi esta decidido?',
        criteria: {
          true: 'Hay que cambiar algo: el calculo, el rotulo, la guarda o la prueba',
          false: 'Se cierra sin tocar codigo: esta decidido asi, ya esta rotulado, o no cambia nada que se vea',
        },
      },
    },
  };
}
