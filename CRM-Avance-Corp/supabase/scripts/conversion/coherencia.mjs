// Las verdades de la conversión que NO dependen del reloj.
//
// Por qué existe: el 21/09, entre dos mediciones separadas por dos horas, el
// índice de septiembre pasó de 3.86 a 3.88 porque una analista cerró un
// referido. Un mes vivo se mueve solo. Por eso NINGÚN gate puede comparar
// contra una foto vieja: daría rojo todos los días sin que nada esté roto.
//
// Lo que sí se puede exigir siempre es la COHERENCIA INTERNA de una foto
// tomada en un instante: cuatro caminos distintos calculan el mismo mes y
// tienen que decir lo mismo. Eso es una alarma de verdad, porque puede fallar.
//
// Todo aquí es puro: recibe una foto ya leída y devuelve los fallos.

/** Compara con la tolerancia de los céntimos de punto que publica el servidor. */
const CASI = 1e-9;
const iguales = (a, b, tol = CASI) => a == null && b == null
  ? true
  : a == null || b == null ? false : Math.abs(Number(a) - Number(b)) <= tol;

const num = (v) => (v == null ? null : Number(v));

/**
 * @returns {{ok: boolean, fallos: Array<{regla: string, detalle: string}>, comprobadas: number}}
 */
export function comprobarCoherencia(foto) {
  const fallos = [];
  const falla = (regla, detalle) => fallos.push({ regla, detalle });
  let comprobadas = 0;
  const c = foto?.caminos;
  if (!c) return { ok: false, fallos: [{ regla: 'forma', detalle: 'la foto no trae `caminos`' }], comprobadas: 0 };

  // 1) LOS CUATRO CAMINOS, CONCILIADOS — no iguales a secas.
  //
  //    🔴 LA VERSIÓN ANTERIOR DE ESTA REGLA ERA INCORRECTA, y lo era de la peor
  //    manera: exigía que los tres caminos publicados fuesen IGUALES al núcleo
  //    directo. Pero el núcleo directo es el BRUTO por construcción (suma los
  //    episodios), y los caminos publicados sirven el NETO (con la deuda por
  //    cierres anulados ya descontada). Mientras no hubo ninguna deuda daba lo
  //    mismo; en cuanto la haya, ESTA REGLA PONDRÍA EN ROJO EL TRABAJO BIEN
  //    HECHO. Lo reprodujo Codex el 22/09: núcleo bruto 3, caminos delegados al
  //    neto 2 -> seis diferencias y gate rojo.
  //
  //    La regla correcta es una conciliación de tres piezas:
  //      · el núcleo directo dice el BRUTO,
  //      · los tres publicados coinciden ENTRE SÍ y dicen el NETO,
  //      · y bruto − neto es EXACTAMENTE la deuda aplicada. Ni más ni menos.
  const nombres = ['nucleo_directo', 'mensual', 'rango', 'distribucion'];
  const publicados = nombres.slice(1);
  const base = c.nucleo_directo;
  const con = foto?.conciliacion;

  //    a) LA FOTO DICE SU VERSIÓN, Y EL GATE LA RESPETA. Una foto v1 se tomó
  //       cuando la regla vieja ERA correcta —no había ninguna deuda posible—,
  //       así que se la juzga con la regla de su tiempo. Exigirle una
  //       conciliación que entonces no existía sería declarar rota una foto
  //       histórica que estaba bien.
  const version = num(foto?.version) || 1;
  const conciliable = version >= 2;

  if (!conciliable) {
    //    Foto v1: la regla de su tiempo —los cuatro iguales— y nada más.
    for (const n of publicados) {
      const v = c[n];
      comprobadas += 1;
      if (!v) { falla('cuatro_caminos', `falta el camino \`${n}\``); continue; }
      for (const campo of ['divisor', 'numerador', 'pct']) {
        if (!iguales(base?.[campo], v[campo])) {
          falla('cuatro_caminos',
            `\`${n}.${campo}\` = ${v[campo]} pero el núcleo directo dice ${base?.[campo]}`);
        }
      }
    }
  }

  //    Foto v2: la conciliación es obligatoria.
  if (conciliable) { comprobadas += 1; }
  if (conciliable && !con) {
    falla('conciliacion', 'la foto se declara versión 2 pero no trae `conciliacion`');
  } else if (conciliable) {
    //  b) El bruto de la conciliación y el del núcleo directo son el MISMO
    //     número. Si no, la conciliación está mirando otra población —por
    //     ejemplo, episodios sin analista que el núcleo sí cuenta— y todo lo
    //     que venga después sería un falso verde.
    comprobadas += 1;
    if (!iguales(con.bruto_numerador, base?.numerador)) {
      falla('conciliacion',
        `el bruto conciliado (${con.bruto_numerador}) no es el del núcleo directo (${base?.numerador}): la conciliación mira otra población`);
    }
    //  c) bruto − neto = deuda aplicada, exactamente.
    comprobadas += 1;
    const diferencia = num(con.bruto_numerador) - num(con.neto_numerador);
    if (!iguales(diferencia, con.deuda_aplicada, 0.0001)) {
      falla('conciliacion',
        `bruto − neto = ${diferencia} pero la deuda aplicada declarada es ${con.deuda_aplicada}`);
    }
    //  d) La deuda APLICADA nunca puede pasar de la PENDIENTE. Al revés sí:
    //     el tope por vendedor (`greatest(num − pend, 0)`) hace que parte de la
    //     deuda no se pueda aplicar cuando supera al bruto de esa persona.
    comprobadas += 1;
    if (num(con.deuda_aplicada) > num(con.deuda_pendiente) + 0.0001) {
      falla('conciliacion',
        `se aplicó más deuda (${con.deuda_aplicada}) de la que hay pendiente (${con.deuda_pendiente})`);
    }
    //  e) Y si alguien quedó topado, la diferencia entre pendiente y aplicada
    //     tiene que estar explicada. Sin nadie topado, deben coincidir.
    comprobadas += 1;
    if (num(con.vendedores_topados) === 0
        && !iguales(con.deuda_aplicada, con.deuda_pendiente, 0.0001)) {
      falla('conciliacion',
        `sin vendedores topados, la deuda aplicada (${con.deuda_aplicada}) debería ser toda la pendiente (${con.deuda_pendiente})`);
    }
  }

  //    f) Los tres publicados coinciden ENTRE SÍ. Ésta es la regla que de
  //       verdad pilla dos pantallas dando números distintos, y no depende de
  //       si hay deuda o no.
  const referencia = c[publicados[0]];
  for (const n of (conciliable ? publicados.slice(1) : [])) {
    const v = c[n];
    comprobadas += 1;
    if (!v) { falla('cuatro_caminos', `falta el camino \`${n}\``); continue; }
    for (const campo of ['divisor', 'numerador', 'pct']) {
      if (!iguales(referencia?.[campo], v[campo])) {
        falla('cuatro_caminos',
          `\`${n}.${campo}\` = ${v[campo]} pero \`${publicados[0]}\` dice ${referencia?.[campo]}`);
      }
    }
  }
  if (conciliable && !referencia) falla('cuatro_caminos', `falta el camino \`${publicados[0]}\``);

  //    g) Y los publicados sirven el NETO, no el bruto. Hoy, sin deuda, neto y
  //       bruto son el mismo número y esto pasa igual; el día que haya deuda,
  //       una pantalla que siga sirviendo el bruto se delata aquí.
  if (conciliable && con) {
    comprobadas += 1;
    if (!iguales(referencia?.numerador, con.neto_numerador)) {
      falla('cuatro_caminos',
        `los caminos publicados dicen ${referencia?.numerador} y el neto conciliado es ${con.neto_numerador}: alguien está sirviendo el bruto`);
    }
  }

  // 2) El porcentaje tiene que ser su propia división. Si el servidor publica
  //    un pct que no sale de su divisor y su numerador, miente sobre sí mismo.
  for (const n of nombres) {
    const v = c[n];
    if (!v) continue;
    comprobadas += 1;
    const d = num(v.divisor); const p = num(v.numerador);
    const esperado = d ? Math.round((10000 * p) / d) / 100 : null;
    if (!iguales(v.pct, esperado, 0.005)) {
      falla('pct_es_su_division', `\`${n}\`: ${p} ÷ ${d} = ${esperado}, pero publica ${v.pct}`);
    }
  }

  // 3) El desglose por tipo y origen tiene que sumar el total. Si no, hay
  //    episodios que entran en el total y no aparecen en ninguna fila.
  if (Array.isArray(foto.desglose)) {
    comprobadas += 2;
    const sumDiv = foto.desglose.reduce((a, x) => a + Number(x.al_divisor ?? 0), 0);
    const sumNum = foto.desglose.reduce((a, x) => a + Number(x.al_numerador ?? 0), 0);
    if (!iguales(sumDiv, base?.divisor)) {
      falla('desglose_suma_el_total', `el desglose suma ${sumDiv} al divisor y el total dice ${base?.divisor}`);
    }
    if (!iguales(sumNum, base?.numerador, 1e-6)) {
      falla('desglose_suma_el_total', `el desglose suma ${sumNum} al numerador y el total dice ${base?.numerador}`);
    }
  }

  // 4) Las filas de analistas más lo que la cobertura DECLARA fuera tienen que
  //    dar el total. Lo que no cuadre aquí es gente que pesa en el porcentaje
  //    de todos sin aparecer en ninguna fila del ranking.
  if (Array.isArray(foto.analistas) && foto.cobertura) {
    comprobadas += 2;
    const fuera = foto.cobertura.fuera_de_roster ?? {};
    const filasDiv = foto.analistas.reduce((a, x) => a + Number(x.divisor ?? 0), 0);
    const filasNum = foto.analistas.reduce((a, x) => a + Number(x.numerador ?? 0), 0);
    const totalDiv = filasDiv + Number(fuera.divisor ?? 0);
    const totalNum = filasNum + Number(fuera.numerador ?? 0);
    if (!iguales(totalDiv, base?.divisor)) {
      falla('las_filas_dan_el_total',
        `filas ${filasDiv} + fuera de roster ${fuera.divisor ?? 0} = ${totalDiv}, pero el total es ${base?.divisor}`);
    }
    if (!iguales(totalNum, base?.numerador, 1e-6)) {
      falla('las_filas_dan_el_total',
        `filas ${filasNum} + fuera de roster ${fuera.numerador ?? 0} = ${totalNum}, pero el total es ${base?.numerador}`);
    }
  }

  // 5) El libro de cierres no puede tener huérfanos por ninguno de los dos
  //    lados: un lead marcado convertido sin fila, o una fila sin la marca.
  if (foto.ledger) {
    comprobadas += 2;
    for (const k of ['convertidos_sin_ledger', 'ledger_sin_etapa_convertido']) {
      if (Number(foto.ledger[k] ?? 0) !== 0) {
        falla('ledger_sin_huerfanos', `\`${k}\` = ${foto.ledger[k]} (tiene que ser 0)`);
      }
    }
  }

  // 6) Un analista con divisor 0 no puede publicar un porcentaje: dividir
  //    entre cero no da 0 %, da «no medible».
  if (Array.isArray(foto.analistas)) {
    for (const a of foto.analistas) {
      comprobadas += 1;
      if (Number(a.divisor ?? 0) === 0 && a.pct != null) {
        falla('sin_divisor_no_hay_pct', `el analista ${a.vendedor_id} tiene divisor 0 y publica ${a.pct} %`);
      }
    }
  }

  return { ok: fallos.length === 0, fallos, comprobadas };
}

/** Qué se movió entre dos fotos. Para el «antes y después» dentro de un branch,
 *  donde los datos NO cambian solos. Contra producción es informativo. */
export function compararFotos(antes, despues) {
  const cambios = [];
  for (const n of ['nucleo_directo', 'mensual', 'rango', 'distribucion']) {
    for (const campo of ['divisor', 'numerador', 'pct']) {
      const a = antes?.caminos?.[n]?.[campo];
      const d = despues?.caminos?.[n]?.[campo];
      if (!iguales(a, d)) cambios.push({ donde: `caminos.${n}.${campo}`, antes: a, despues: d });
    }
  }
  const porId = (l) => new Map((l ?? []).map((x) => [x.vendedor_id, x]));
  const a = porId(antes?.analistas); const d = porId(despues?.analistas);
  for (const [id, fa] of a) {
    const fd = d.get(id);
    if (!fd) { cambios.push({ donde: `analista ${id}`, antes: 'estaba', despues: 'desapareció' }); continue; }
    for (const campo of ['divisor', 'numerador', 'pct']) {
      if (!iguales(fa[campo], fd[campo])) {
        cambios.push({ donde: `analista ${id}.${campo}`, antes: fa[campo], despues: fd[campo] });
      }
    }
  }
  for (const id of d.keys()) if (!a.has(id)) cambios.push({ donde: `analista ${id}`, antes: 'no estaba', despues: 'apareció' });
  return { sin_cambios: cambios.length === 0, cambios };
}
