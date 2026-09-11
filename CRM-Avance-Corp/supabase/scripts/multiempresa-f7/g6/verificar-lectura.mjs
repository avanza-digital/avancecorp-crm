// Verificación de una captura G6 privada; no consulta ni modifica bases.
import assert from 'node:assert/strict';
import { chmod, readFile, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { verificarContrato } from '../contrato-cliente.mjs';

function centavos(n) {
  assert.equal(typeof n, 'number');
  const valor = Math.round(n * 100);
  assert.ok(Number.isSafeInteger(valor) && Math.abs(valor - n * 100) < 0.00001,
    'Importe fuera de la precisión admitida');
  return valor;
}

function filas(datos, campos) {
  return datos.map(f => JSON.stringify(campos.map(c => c === 'capital'
    ? centavos(f[c]) : f[c]))).sort();
}

export function verificarLectura(e) {
  assert.equal(e.version_g6, 1);
  assert.equal(e.solo_lectura, 'on');
  assert.equal(e.bandera_real, false);
  assert.equal(e.actor_referencia_gerencia, true);
  assert.equal(e.custodia.solo_lectura, 'on');
  assert.equal(e.custodia.rol, 'postgres');
  assert.equal(e.custodia.rol, e.custodia.propietario_f7);
  assert.equal(e.custodia.search_path, '""');
  assert.deepEqual(e.custodia.banderas, e.banderas);
  assert.deepEqual(e.custodia.fotos_selladas, e.fotos_selladas);
  for (const [bandera, valor] of Object.entries({ resolver_en_puertas: true,
    inversiones_escritura: false, ficha_360_neutral: false,
    postventa_neutral: false, metricas_multiempresa_sombra: false })) {
    assert.equal(e.banderas[bandera], valor, bandera);
  }
  assert.ok(e.meses.length > 0);
  assert.deepEqual(e.meses.map(m => m.mes).sort(), e.meses_solicitados);
  assert.equal(new Set(e.meses.map(m => m.mes)).size, e.meses.length);
  assert.equal(e.duplicados_nucleo, 0);
  assert.equal(e.diferencias_identidad, 0);
  assert.equal(e.pendientes_identidad.length, e.personas_referencia.fuentes_sin_identidad);
  assert.equal(new Set(e.pendientes_identidad.map(d => d.fuente_tipo + ':' + d.fuente_id)).size,
    e.pendientes_identidad.length);
  const verificaciones = [];
  for (const m of e.meses) {
    const i = verificarContrato(m.informe);
    assert.equal(i.mes, m.mes);
    assert.equal(i.hasta, m.hasta);
    assert.equal(i.fuentes_duplicadas, 0);
    assert.equal(m.diferencias_por_operacion, 0);
    assert.equal(m.diferencias_capital_publicado_exactas, 0, 'Capital publicado: NUMERIC exacto');
    assert.equal(i.mes_sellado, e.fotos_selladas.some(f => f.periodo === m.mes));
    for (const c of i.conciliacion) {
      assert.equal(c.diferencia_capital, 0);
      assert.equal(c.diferencia_operaciones, 0);
      assert.equal(c.diferencia_atribucion, 0);
    }
    assert.deepEqual(filas(i.atribucion, ['empresa', 'moneda', 'analista_id', 'operaciones', 'capital']),
      filas(m.atribucion_nucleo, ['empresa', 'moneda', 'analista_id', 'operaciones', 'capital']));
    assert.deepEqual(filas(i.tipos_capital, ['empresa', 'moneda', 'tipo_capital', 'operaciones', 'capital']),
      filas(m.tipos_nucleo.map(t => ({ ...t, tipo_capital: t.tipo })),
        ['empresa', 'moneda', 'tipo_capital', 'operaciones', 'capital']));
    // El informe publicado agrupa ambas cooperativas en una categoría.
    // Se reagrupa solo esa dimensión; PEN y USD siempre tienen claves distintas.
    const capital = new Map();
    for (const t of i.tipos_capital) {
      const categoria = t.tipo_capital === 'cooperativa' ? 'cooperativa'
        : t.tipo_capital.replace(/^contrato_/, '');
      const clave = JSON.stringify([t.moneda, categoria]);
      const fila = capital.get(clave) ?? { operaciones: 0, centavos: 0 };
      fila.operaciones += t.operaciones;
      fila.centavos += centavos(t.capital);
      capital.set(clave, fila);
    }
    const publicado = new Map(m.capital_publicado.map(c => [JSON.stringify([c.moneda, c.categoria]),
      { operaciones: c.contratos, centavos: centavos(c.capital_colocado) }]));
    assert.equal(publicado.size, m.capital_publicado.length);
    assert.deepEqual([...capital].sort(), [...publicado].sort(), 'Capital publicado por moneda/categoría');
    const detalles = new Map();
    for (const d of m.detalle_operaciones) {
      const clave = JSON.stringify([d.empresa, d.moneda, d.analista_id]);
      const fila = detalles.get(clave) ?? { operaciones: 0, centavos: 0 };
      fila.operaciones++;
      fila.centavos += centavos(d.capital);
      detalles.set(clave, fila);
    }
    const atribucion = new Map(i.atribucion.map(a => [JSON.stringify([a.empresa, a.moneda, a.analista_id]),
      { operaciones: a.operaciones, centavos: centavos(a.capital) }]));
    assert.deepEqual([...detalles].sort(), [...atribucion].sort(), 'Detalle por inversión y responsable');
    assert.equal(m.detalle_operaciones.length, m.cobertura_capital.operaciones);
    assert.equal(m.detalle_operaciones.filter(d => !d.en_roster).length, m.cobertura_capital.fuera_roster);
    assert.equal(m.detalle_operaciones.filter(d => d.analista_id === null).length, m.cobertura_capital.sin_analista);
    assert.equal(m.detalle_operaciones.filter(d => d.anulado).length, m.cobertura_capital.anulaciones_comerciales);
    assert.equal(new Set(m.detalle_operaciones.map(d => d.fuente_tipo + ':' + d.fuente_id)).size,
      m.detalle_operaciones.length, 'Fuente económica repetida');
    for (const campo of ['total', 'una_empresa', 'dos_empresas', 'tres_empresas',
      'fuentes_sin_identidad', 'fuentes_coherentes', 'fuentes_contradictorias', 'fuentes_sin_enlace']) {
      assert.equal(i.personas[campo], e.personas_referencia[campo], campo);
    }
    assert.deepEqual(filas(i.personas.por_empresa, ['empresa', 'personas']),
      filas(e.personas_referencia.por_empresa, ['empresa', 'personas']));
    assert.deepEqual(filas(i.vencimientos, ['empresa', 'moneda', 'operaciones', 'capital']),
      filas(e.vencimientos_referencia, ['empresa', 'moneda', 'operaciones', 'capital']));
    assert.deepEqual(filas(i.oportunidades, ['empresa', 'personas']),
      filas(e.oportunidades_referencia, ['empresa', 'personas']));
    for (const campo of ['divisor', 'numerador', 'tasa_pct', 'cierres', 'anulados', 'renovaciones', 'upgrades']) {
      assert.equal(i.conversion[campo], m.conversion_nucleo[campo], campo);
    }
    assert.equal(i.conversion.factor_referido, m.conversion_nucleo.factor);
    // Diferencias con el reporte oficial se registran, nunca se silencian:
    // puede existir un ajuste neto, actividad futura o un modelo histórico sellado.
    const c = m.conversion_publicada;
    assert.equal(c.alcance, 'global');
    assert.equal(c.periodo.mes, m.mes.slice(0, 7));
    const diferenciasConversion = {
      divisor: i.conversion.divisor - c.total.divisor,
      numerador: i.conversion.numerador - c.total.numerador,
      tasa_pct: i.conversion.tasa_pct === c.total.conversion_pct ? 0 :
        { sombra: i.conversion.tasa_pct, oficial: c.total.conversion_pct },
      factor: i.conversion.factor_referido - c.ponderacion.referido,
    };
    assert.deepEqual(Object.keys(m.conversion_oficial_exacta).sort(), ['divisor', 'factor', 'numerador', 'tasa_pct']);
    assert.ok(Object.values(m.conversion_oficial_exacta).every(v => typeof v === 'boolean'));
    verificaciones.push({ mes: m.mes, hasta: m.hasta, operaciones: m.detalle_operaciones.length,
      gruposEmpresaMoneda: i.produccion.length, paridadFuentesCapitalAtribucion: 'PASS',
      paridadIdentidadVencimientos: 'PASS', consistenciaOportunidades: 'PASS',
      consistenciaParametrosConversion: 'PASS', capitalOficialNumericExacto: 'PASS',
      diferenciasConversionOficial: diferenciasConversion,
      conversionOficialNumericExacto: m.conversion_oficial_exacta,
      conversionOficial: Object.values(diferenciasConversion).every(v => v === 0) &&
        Object.values(m.conversion_oficial_exacta).every(v => v === true) ? 'PASS' : 'REVISAR',
      operacionesFueraRoster: m.cobertura_capital.fuera_roster,
      mesSellado: i.mes_sellado });
  }
  return { estado: verificaciones.every(v => v.conversionOficial === 'PASS') ? 'PARIDAD_TECNICA_PASS' : 'DIFERENCIAS_PENDIENTES',
    capturadoEn: e.capturado_en, verificaciones,
    cobertura: { fuentesSinIdentidad: e.personas_referencia.fuentes_sin_identidad,
      fuentesSinRelacionF4: e.personas_referencia.fuentes_sin_relacion,
      personas: e.personas_referencia.total,
      cotitularesReales: e.personas_referencia.filas_cotitulares,
      personasEnVariasEmpresas: e.personas_referencia.dos_empresas + e.personas_referencia.tres_empresas,
      personasConVeto: e.personas_referencia.personas_con_veto },
    alcance: 'Paridad interna sobre datos reales; proyección SELECT de F7 OFF, no invocación de su RPC de cifras.',
    g6: 'ABIERTO, revisión humana y financiera pendientes' };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  assert.equal(process.argv.length, 4, 'Uso: verificar-lectura.mjs captura-privada.json resultado.json');
  let resultado;
  let capturaSha256;
  try {
    const captura = await readFile(process.argv[2], 'utf8');
    capturaSha256 = createHash('sha256').update(captura).digest('hex');
    resultado = verificarLectura(JSON.parse(captura));
  } catch (error) {
    // No conserva un PASS anterior si la captura cambió o el lector falló.
    // El detalle de aserciones podría contener nombres: no se publica aquí.
    resultado = { estado: 'FAIL', error: error.code ?? error.name };
  }
  resultado.capturaSha256 = capturaSha256;
  await writeFile(process.argv[3], JSON.stringify(resultado, null, 2) + '\n', { mode: 0o600 });
  await chmod(process.argv[3], 0o600);
  console.log(JSON.stringify(resultado, null, 2));
  if (resultado.estado !== 'PARIDAD_TECNICA_PASS') process.exitCode = 1;
}
