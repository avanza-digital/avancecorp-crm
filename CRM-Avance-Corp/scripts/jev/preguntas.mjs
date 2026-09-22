// Las preguntas que se le hacen a Jev sobre una AUDITORÍA, y la política que
// convierte sus probabilidades en decisiones. Todo aquí es PURO: ni red ni
// claves, para que se pueda probar entero con `node --test`.
//
// Frontera que no se cruza (decidida el 20/09 y escrita en el vault): Jev NO
// juzga dinero, conversión, permisos ni cierre de mes. Aquí solo lee TEXTO
// SOBRE HALLAZGOS —el título, la evidencia citada, el impacto— y nunca una
// cifra del negocio. Los porcentajes los siguen calculando SQL y la sonda.
//
// Todo lo que viene de un hallazgo viaja en campos CON NOMBRE dentro de
// `state`: es dato, no instrucciones. Un hallazgo cuyo texto diga «ignora lo
// anterior» se lee como lo que es, el contenido de un campo.

/** Los ocho defectos confirmados el 21/09. Son las cabezas de grupo: todo
 *  hallazgo pendiente o cae en una de ellas o es algo nuevo. */
export const GRUPOS = {
  C1: {
    what: 'Un mes ya sellado se vuelve a calcular en vivo en las pantallas de rango, en vez de servir la foto guardada del mes',
    not_for: 'Diferencias entre dos cifras que NO vienen de que el mes esté sellado',
    examples: ['el rango no mira periodos_cerrados', 'la distribucion recalcula un mes cerrado'],
  },
  C2: {
    what: 'La misma cifra se publica con la deuda por cierres anulados restada en un sitio y sin restar en otro (neto arriba, bruto abajo)',
    not_for: 'Que el mes este sellado o no; eso es C1',
    examples: ['la alerta usa el bruto', 'el rango no resta el ajuste por anulacion'],
  },
  C3: {
    what: 'La comprobacion que autoriza publicar la cifra se compara consigo misma, asi que nunca puede fallar',
    not_for: 'Que falte una prueba; aqui la prueba existe pero es tautologica',
    examples: ['cuadra=true siempre', 'la sonda llama a la misma funcion con los mismos argumentos'],
  },
  C4: {
    what: 'La deuda por anulaciones se descuenta a la vez en dos meses abiertos porque no lleva periodo',
    not_for: 'Deuda que simplemente no se cobra; eso es C5',
    examples: ['ajuste_pendiente_por_vendedor no recibe periodo', 'entre el dia 1 y el 10 conviven dos meses'],
  },
  C5: {
    what: 'La deuda de una persona que ya salio del equipo nunca se salda ni se declara en ninguna pantalla',
    not_for: 'Deuda imputada dos veces; eso es C4',
    examples: ['solo se cruza con el roster', 'saldar_ajustes solo corre sobre la foto'],
  },
  C6: {
    what: 'La foto que se guarda al sellar el mes escribe un cero fijo en vez de la medida real, o no guarda la comprobacion que si se hizo en vivo',
    not_for: 'Que la foto no se sirva; aqui la foto se sirve pero miente sobre su propia calidad',
    examples: ['cierres_sin_episodio: 0 literal', 'cerrar_periodo no guarda la sonda'],
  },
  C7: {
    what: 'Al quedarse con una sola operacion por cliente y mes se elige primero y se recorta por fechas despues, asi que en un rango parcial una operacion real aporta cero',
    not_for: 'Operaciones que no entran por otra regla',
    examples: ['dedupe antes del recorte', 'la primera del mes cayo fuera del rango'],
  },
  C8: {
    what: 'Una serie por semanas mezcla semanas que llevan meses madurando con semanas que llevan dias, y no publica hasta cuando maduro',
    not_for: 'Series por mes',
    examples: ['ritmo semanal sin madura_hasta', 'cosecha por semana de ingreso'],
  },
  otro: {
    what: 'Un defecto distinto de los ocho anteriores',
    not_for: 'Un caso mas de cualquiera de los ocho, aunque este en otro archivo o en otra pantalla',
    examples: ['el front fabrica ceros cuando la consulta falla', 'una puerta legacy sigue en el front'],
  },
};

export const LENTES = {
  codigo: {
    what: 'Se resuelve leyendo el codigo citado: basta abrir ese archivo y esas lineas para ver si hace lo que el hallazgo dice',
    not_for: 'Afirmaciones sobre lo que es correcto para el negocio, o sobre lo que pasa hoy en produccion',
  },
  negocio: {
    what: 'El codigo hace lo que el hallazgo dice, pero hay que decidir si eso esta MAL: puede ser una regla acordada a proposito',
    not_for: 'Dudas sobre si el codigo dice eso',
    examples: ['el rotulo ya avisa de la regla', 'se decidio asi en una reunion'],
  },
  produccion: {
    what: 'Solo se resuelve consultando la base real: depende de datos, banderas o configuracion de hoy',
    not_for: 'Lo que se puede decidir leyendo el repositorio',
    examples: ['depende de si hay un mes sellado', 'depende de si la bandera esta encendida'],
  },
  ninguna: {
    what: 'Lo adjuntado ya basta: la evidencia citada demuestra el defecto sin ninguna comprobacion mas',
    not_for: 'Casos donde falta cualquier dato para decidir',
  },
};

const texto = (h) => ({
  titulo: h.titulo ?? '',
  severidad_propuesta: h.severidad ?? '',
  capa: h.capa ?? '',
  archivo: (h.archivo ?? '').split('/').slice(-1)[0],
  lineas: h.lineas ?? '',
  evidencia_citada: h.evidencia ?? '',
  impacto_declarado: h.impacto_gerencia ?? '',
});

/** UNA petición por hallazgo con las cuatro preguntas independientes juntas:
 *  corren en paralelo y ninguna ve la respuesta de las otras (patrón fan-out). */
export function triaje(hallazgo) {
  return {
    state: { hallazgo: texto(hallazgo) },
    questions: {
      evidencia: {
        type: 'noul',
        instructions: 'Un auditor afirma `hallazgo.titulo` y adjunta como prueba el texto de `hallazgo.evidencia_citada`. ¿Ese texto adjunto, por si solo, sostiene lo que el titulo afirma?',
        criteria: {
          true: 'El texto adjunto contiene el codigo, el error o el dato concreto que demuestra lo afirmado',
          false: 'El texto adjunto describe, resume, razona o supone, pero no muestra la prueba; o prueba algo distinto de lo que el titulo afirma',
        },
      },
      hipotesis: {
        type: 'noul',
        instructions: 'Leyendo `hallazgo`, ¿el auditor esta suponiendo lo que pasaria (una hipotesis pendiente de comprobar) en vez de describir algo que demuestra que ya ocurre?',
        criteria: {
          true: 'Habla de lo que pasaria, podria o probablemente ocurre; pide comprobarlo',
          false: 'Describe un mecanismo presente en el codigo adjunto, sin condicionales pendientes',
        },
      },
      afecta_cifra: {
        type: 'noul',
        instructions: 'Segun `hallazgo`, ¿el defecto hace que una persona de gerencia vea en pantalla un numero equivocado, o un numero correcto bajo un rotulo que dice otra cosa?',
        criteria: {
          true: 'Cambia el numero publicado, su periodo o su significado',
          false: 'Es higiene interna: duplicacion, orden del codigo, falta de prueba o de comentario, sin cambiar lo que se ve',
        },
      },
      grupo: {
        type: 'choice',
        instructions: 'Un equipo ya tiene ocho defectos confirmados. ¿De cual de ellos es `hallazgo` una cara mas? Elige «otro» solo si no es ninguno.',
        criteria: GRUPOS,
      },
      lente: {
        type: 'choice',
        instructions: 'Para decidir si `hallazgo` es un defecto real, ¿que comprobacion hace falta?',
        criteria: LENTES,
      },
    },
  };
}

/** ¿Qué clase de contador es? El trinquete de analítica tiene un TECHO que solo
 *  puede bajar, y hoy mezcla dos poblaciones muy distintas: lo que mide el
 *  PASADO (y por tanto puede contradecir al núcleo) y lo que inventaría el
 *  PRESENTE (cuántos hay pendientes ahora). Separarlas hace el techo más
 *  estricto donde importa. Jev propone; una persona verifica: esto decide qué
 *  vigila un detector. */
export const CLASES = {
  analitica: {
    what: 'Responde una pregunta sobre el PASADO con un numero que alguien podria comparar con la conversion oficial: cuantos cerraron, que porcentaje, cuanto capital, cuanto tardo, en un periodo ya ocurrido',
    not_for: 'Contar lo que hay pendiente ahora mismo, o contar para validar un lote antes de escribirlo',
    examples: ['conversion del mes', 'tiempos de SLA por etapa', 'produccion por vendedor del periodo', 'embudo de la cohorte que entro en marzo'],
  },
  operativo: {
    what: 'Inventaria el PRESENTE o valida una escritura: cuantos hay pendientes AHORA, cuantos caben en este lote, que dejaria huerfano esta baja, que se reparte hoy. Su respuesta cambia en cuanto alguien trabaja',
    not_for: 'Cualquier cifra de un periodo cerrado que gerencia pueda comparar con otra pantalla',
    examples: ['la cola de accion del vendedor', 'la bandeja por supervisor', 'validar el lote que se deriva', 'mantener la secuencia del ledger'],
  },
  mixta: {
    what: 'Publica AMBAS cosas: una cifra del pasado que sale del nucleo Y ademas conteos crudos del presente o de otra pregunta distinta',
    not_for: 'Las que son claramente solo una de las dos',
    examples: ['sirve la conversion mensual del nucleo y ademas su propia vista de 45 dias'],
  },
};

export function clasificarContador(contador) {
  return {
    state: {
      contador: {
        nombre: (contador.titulo ?? '').split('(')[0],
        razon_declarada: contador.evidencia ?? '',
        datos: contador.impacto_gerencia ?? '',
      },
    },
    questions: {
      clase: {
        type: 'choice',
        instructions: 'Un CRM vigila que nadie invente su propia cuenta de leads y citas por detras de la oficial. Para eso censa las funciones que cuentan en crudo. `contador` es una de ellas, con la razon que sus autores escribieron. ¿Que clase de contador es?',
        criteria: CLASES,
      },
      contradice_al_nucleo: {
        type: 'noul',
        instructions: 'Si este contador diera un numero distinto del que da el nucleo oficial de conversion, ¿alguien de gerencia lo notaria como una contradiccion entre dos pantallas?',
        criteria: {
          true: 'Publica una cifra comparable con la conversion, el capital o los tiempos oficiales',
          false: 'Responde otra pregunta, o su numero solo vive dentro de una operacion',
        },
      },
    },
  };
}

/** Rerank: cuánto ayuda ESTE extracto a resolver ESTA pregunta del auditor.
 *  Una pregunta por par (consulta, extracto), como manda el cookbook. */
export function relevancia(consulta, extracto) {
  return {
    state: { pregunta_del_auditor: consulta, extracto: { de: extracto.de ?? '', texto: extracto.texto ?? '' } },
    questions: {
      relevancia: {
        type: 'score',
        instructions: 'Un auditor tiene que responder `pregunta_del_auditor` y dispone de `extracto`. ¿Cuanto acerca este extracto a la respuesta?',
        criteria: [
          'No dice nada util para esa pregunta',
          'Habla del mismo tema pero no responde nada',
          'Aporta una pieza del contexto; hacen falta otros extractos',
          'Contiene lo que decide la respuesta',
        ],
      },
    },
  };
}

/** Revisión estancada: el reviewer y el autor ya no aportan, solo repiten. */
export function estancada(hilo) {
  return {
    state: {
      hilo_de_revision: {
        asunto: hilo.asunto ?? '',
        rondas: (hilo.rondas ?? []).map((r) => ({ quien: r.quien ?? '', dice: r.dice ?? '' })),
      },
    },
    questions: {
      aporta_nuevo: {
        type: 'noul',
        instructions: 'En `hilo_de_revision`, la ultima ronda ¿aporta evidencia o un argumento que no estuviera ya en las rondas anteriores?',
        criteria: {
          true: 'Trae un archivo, una linea, un dato o un razonamiento nuevo',
          false: 'Repite, reformula o insiste en lo ya dicho',
        },
      },
      pide_lo_mismo: {
        type: 'noul',
        instructions: 'En `hilo_de_revision`, ¿se esta volviendo a preguntar lo mismo con otras palabras, como si se buscara una respuesta distinta a la que ya se dio?',
        criteria: {
          true: 'La misma peticion reaparece reformulada tras haber sido contestada',
          false: 'Cada ronda avanza sobre un punto distinto',
        },
      },
      decidible: {
        type: 'noul',
        instructions: 'Con lo dicho en `hilo_de_revision`, ¿hay ya suficiente para que una persona decida, aunque las partes no se hayan puesto de acuerdo?',
        criteria: {
          true: 'Las dos posturas estan expuestas con su evidencia',
          false: 'Falta una comprobacion concreta que nadie ha hecho todavia',
        },
      },
    },
  };
}

/** ¿El cambio cierra el hallazgo, o solo lo tapa? */
export function resuelto(hallazgo, cambio) {
  return {
    state: {
      hallazgo: texto(hallazgo),
      cambio_propuesto: { descripcion: cambio.descripcion ?? '', diff: cambio.diff ?? '' },
    },
    questions: {
      elimina_causa: {
        type: 'noul',
        instructions: '`hallazgo` describe un defecto y `cambio_propuesto` el cambio hecho para arreglarlo. ¿El cambio elimina la causa descrita en el hallazgo?',
        criteria: {
          true: 'Toca el mecanismo que el hallazgo senala, de modo que el defecto ya no puede ocurrir por ahi',
          false: 'Toca otra cosa, o toca el sitio pero deja intacto el mecanismo descrito',
        },
      },
      solo_oculta: {
        type: 'noul',
        instructions: '¿`cambio_propuesto` se limita a esconder el sintoma —un rotulo, un aviso, un valor por defecto, una rama que deja de pintarse— dejando el calculo equivocado donde estaba?',
        criteria: {
          true: 'Cambia lo que se muestra o se calla, no lo que se calcula',
          false: 'Cambia el calculo, el dato o la regla',
        },
      },
      abre_otro: {
        type: 'noul',
        instructions: 'Comparando `cambio_propuesto` con `hallazgo`, ¿el cambio deja a la vista un problema nuevo: otra pantalla que ahora muestra algo distinto, un caso sin cubrir, o una regla que se contradice?',
        criteria: {
          true: 'Se ve un efecto colateral sin resolver',
          false: 'No se aprecia ninguno con lo adjuntado',
        },
      },
    },
  };
}

// ── Política: del número a la decisión ──────────────────────────────────────
// CALIBRADO el 21/09 contra los 41 hallazgos que ya tenían veredicto humano
// (`veredictos-adversariales.tsv`) y contra las 65 agrupaciones de P0/P1
// revisadas a mano. Lo medido, sin adornos:
//
//   · `evidencia` NO predice el veredicto humano: AUC 0.47 (azar). Con las
//     reglas del negocio delante (`reglas.mjs`) sube solo a 0.61. Por eso esta
//     política NUNCA descarta un hallazgo por la respuesta de Jev: la reporta
//     como señal y manda a una persona. Para decidir «¿esto es un defecto?»
//     hay que leer el cuerpo entero de la función, y eso no cabe en el estado.
//   · `grupo` SÍ funciona por encima de 0.80: de 12 agrupaciones con esa
//     confianza, las 12 eran correctas. Por debajo aparecen los errores
//     («un mes sin metas no se puede sellar» → C1 con 0.60, mal).
//
// Si cambian las preguntas o el modelo, se vuelve a medir antes de subir
// ningún umbral: `scripts/jev/README.md` tiene el procedimiento.
export const UMBRALES = { si: 0.8, no: 0.2, confianza: 0.8 };

export function decidir(respuestas, umbrales = UMBRALES) {
  const n = (k) => respuestas[k]?.noul;
  const c = (k) => respuestas[k]?.choice;
  const conf = (k) => respuestas[k]?.confidence ?? 0;
  const ev = n('evidencia');
  const grupo = conf('grupo') >= umbrales.confianza ? c('grupo') : 'revisar';
  const lente = conf('lente') >= umbrales.confianza ? c('lente') : 'revisar';
  return {
    // Señal, no veredicto: medida en AUC 0.47, no autoriza a descartar nada.
    evidencia: ev,
    evidencia_baja: typeof ev === 'number' ? ev < umbrales.no : null,
    es_hipotesis: typeof n('hipotesis') === 'number' ? n('hipotesis') >= umbrales.si : null,
    afecta_cifra: typeof n('afecta_cifra') === 'number' ? n('afecta_cifra') >= umbrales.si : null,
    grupo,
    grupo_confianza: conf('grupo'),
    lente,
    lente_confianza: conf('lente'),
    // Un duplicado de un defecto YA confirmado no necesita otra verificación:
    // se arregla con su grupo. Lo demás va a una persona o a su lente.
    accion: grupo !== 'otro' && grupo !== 'revisar' ? `adjuntar_a_${grupo}`
      : lente === 'ninguna' ? 'aceptar_sin_verificar'
      : lente === 'revisar' ? 'revisar_humano'
      : `verificar_${lente}`,
  };
}

export function veredictoResuelto(respuestas, umbrales = UMBRALES) {
  const n = (k) => respuestas[k]?.noul ?? null;
  const elimina = n('elimina_causa');
  const oculta = n('solo_oculta');
  const otro = n('abre_otro');
  const cierra = elimina !== null && elimina >= umbrales.si
    && (oculta === null || oculta < umbrales.no);
  return {
    cierra,
    elimina_causa: elimina,
    solo_oculta: oculta,
    abre_otro: otro,
    motivo: cierra ? (otro !== null && otro >= umbrales.si ? 'cierra_pero_abre_otro' : 'cierra')
      : oculta !== null && oculta >= umbrales.si ? 'solo_tapa_el_sintoma'
      : elimina !== null && elimina < umbrales.no ? 'no_toca_la_causa'
      : 'dudoso_revisar_humano',
  };
}

export function veredictoEstancada(respuestas, umbrales = UMBRALES) {
  const n = (k) => respuestas[k]?.noul ?? null;
  const nuevo = n('aporta_nuevo');
  const repite = n('pide_lo_mismo');
  const decidible = n('decidible');
  // Calibrado el 21/09 sobre dos hilos reales de la auditoría de conversiones:
  //   estancado (C3, 5 rondas repitiendo): aporta_nuevo 0.11 · pide_lo_mismo 0.79
  //   vivo      (C2, el revisor trae un contraejemplo): 0.63 · 0.11
  // Las dos señales separan de sobra; exigir además `pide_lo_mismo >= 0.8`
  // dejaba pasar el hilo estancado por una centésima. Manda `aporta_nuevo`,
  // que es la pregunta directa, y `pide_lo_mismo` solo acompaña.
  const estancado = nuevo !== null && nuevo < umbrales.no && (repite === null || repite > 0.5);
  return {
    estancada: estancado,
    aporta_nuevo: nuevo,
    pide_lo_mismo: repite,
    decidible,
    accion: estancado
      ? (decidible !== null && decidible >= 0.5 ? 'cerrar_y_decidir' : 'parar_y_pedir_la_comprobacion_que_falta')
      : 'seguir',
  };
}
