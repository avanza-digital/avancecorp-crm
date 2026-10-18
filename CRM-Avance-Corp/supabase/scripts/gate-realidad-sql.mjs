// Dos mediciones administrativas del gate, sin ampliar la API ni sus permisos.
// Opt-in explícito; la CLI usa su sesión local, nunca una clave en argumentos.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const ejecutar = promisify(execFile);
const CONSULTAS = Object.freeze({
  metas_bajo_el_sello: `select count(*)::integer as valor
    from crm.meta_periodos m
    left join crm.periodos_cerrados s on s.periodo = m.periodo
    where m.periodo <= (select max(periodo) from crm.periodos_cerrados)
      and (s.periodo is null or m.revision > s.meta_revision)`,
  conversion_un_solo_nucleo: 'select crm.alarma_conversion_fn() as valor',
});

export function proyectoSQL(args, url) {
  const posicion = args.indexOf('--sql-project-ref');
  if (posicion < 0) return null;
  const ref = args[posicion + 1];
  if (!/^[a-z]{20}$/.test(ref ?? '') || args.lastIndexOf('--sql-project-ref') !== posicion) {
    throw new Error('--sql-project-ref requiere una única referencia válida de proyecto.');
  }
  // Evitar combinar conteos de una base con sellos/conversión de otra.
  if (url !== `https://${ref}.supabase.co` && url !== `https://${ref}.supabase.co/`) {
    throw new Error('El proyecto SQL debe coincidir exactamente con SUPABASE_URL.');
  }
  return ref;
}

export async function medirSQL(clave, proyecto, ejecutarCLI = ejecutar) {
  if (!Object.hasOwn(CONSULTAS, clave) || !/^[a-z]{20}$/.test(proyecto ?? '')) {
    throw new Error('Medición SQL o proyecto no permitido.');
  }
  const sql = `begin read only; set local statement_timeout = '80s';\n${CONSULTAS[clave]};\nrollback;`;
  let stdout;
  try {
    ({ stdout } = await ejecutarCLI('supabase', [
      'db', 'query', '--linked', '--project-ref', proyecto, '--output', 'json', sql,
    ], { timeout: 90_000, maxBuffer: 256 * 1024, encoding: 'utf8' }));
  } catch {
    // Los errores del proceso pueden incluir el entorno/argumentos: no volcarlos.
    throw new Error(`No se pudo medir ${clave} mediante Supabase CLI (sesión, permisos o timeout).`);
  }
  let rows;
  try { ({ rows } = JSON.parse(stdout)); } catch {
    throw new Error('La CLI no devolvió JSON válido; medición incompleta.');
  }
  if (!Array.isArray(rows) || rows.length !== 1 || !Object.hasOwn(rows[0], 'valor')) {
    throw new Error('La CLI no devolvió exactamente una medición; no se presume cero.');
  }
  const valor = rows[0].valor;
  if (clave === 'metas_bajo_el_sello' && (!Number.isSafeInteger(valor) || valor < 0)) {
    throw new Error('Conteo de sellos inválido.');
  }
  if (clave === 'conversion_un_solo_nucleo' &&
      (!valor || typeof valor !== 'object' || Array.isArray(valor) ||
       !Object.hasOwn(valor, 'cuadra') || ![true, false, null].includes(valor.cuadra))) {
    throw new Error('Veredicto de conversión inválido.');
  }
  return valor;
}

export function codigoSalida(resultados, estricto) {
  if (resultados.some(r => r.error)) return 2;
  return estricto && resultados.some(r => r.diverge) ? 1 : 0;
}
