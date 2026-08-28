#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [migracionesDir, salida] = process.argv.slice(2);
if (!migracionesDir || !salida) {
  throw new Error('uso: c0-1-extraer-funciones.mjs <migrations-dir> <salida.sql>');
}

const requeridas = new Map([
  ['private.vendedor_ids_visibles', '20260803164348_crm_offboarding_gate_activos.sql'],
  ['private.rol_crm', '20260807203740_crm_usuarios_jerarquia_autoservicio.sql'],
  ['private.es_lector_global', '20260807203740_crm_usuarios_jerarquia_autoservicio.sql'],
  ['private.filtrar_desglose_sujetos_crm', '20260807203757_crm_metas_sla_versionados.sql'],
  ['private.roster_metas_vendedores', '20260810163458_crm_roster_metas_fuente_unica.sql'],
  ['private.vendedores_sin_supervisor', '20260810163458_crm_roster_metas_fuente_unica.sql'],
  ['private.peso_referido_conversion', '20260811154434_crm_conversion_mensual_ponderada.sql'],
  ['private.etiqueta_mes_es', '20260811154434_crm_conversion_mensual_ponderada.sql'],
  ['private.cierre_anulado', '20260813235119_crm_anulacion_cierre_avance.sql'],
  ['private.cierre_externo_anulado', '20260813235119_crm_anulacion_cierre_avance.sql'],
  ['private.ajuste_pendiente_por_vendedor', '20260815002100_crm_ajuste_mes_cerrado.sql'],
  ['private.conversion_con_ajuste', '20260815002100_crm_ajuste_mes_cerrado.sql'],
  ['private.cierre_mes_visible', '20260815003742_crm_cierre_mes_lectura.sql'],
  ['private.metricas_cartera_por_vendedor', '20260824231133_crm_gestion_clientes_renovaciones_conversion.sql'],
  ['crm.metricas_cartera_fn', '20260824231133_crm_gestion_clientes_renovaciones_conversion.sql'],
  ['private.conversion_episodios', '20260826233000_crm_f1_conversion_episodios.sql'],
  ['private.conversion_mensual_por_vendedor', '20260826233000_crm_f1_conversion_episodios.sql'],
  ['crm.conversion_mensual_sin_cartera_fn', '20260827154448_crm_f2_6_total_incluye_fuera_de_roster.sql'],
  ['crm.conversion_mensual_fn', '20260824231133_crm_gestion_clientes_renovaciones_conversion.sql'],
  ['crm.metricas_vendedores_fn', '20260827080000_crm_f2_4b_convertidos_sin_cartera.sql'],
]);

function extraerFunciones(texto) {
  const halladas = [];
  const inicio = /create\s+(?:or\s+replace\s+)?function\s+([^\s(]+)\s*\(/gim;
  let coincidencia;
  while ((coincidencia = inicio.exec(texto)) !== null) {
    const desde = coincidencia.index;
    const resto = texto.slice(inicio.lastIndex);
    const apertura = /\bas\s+(\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$)/im.exec(resto);
    if (!apertura) continue;
    const etiqueta = apertura[1];
    const cuerpoDesde = inicio.lastIndex + apertura.index + apertura[0].length;
    const cuerpoHasta = texto.indexOf(etiqueta, cuerpoDesde);
    if (cuerpoHasta < 0) throw new Error(`dollar quote sin cerrar para ${coincidencia[1]}`);
    const puntoComa = texto.indexOf(';', cuerpoHasta + etiqueta.length);
    if (puntoComa < 0) throw new Error(`sentencia sin ; para ${coincidencia[1]}`);
    halladas.push({
      nombre: coincidencia[1].toLowerCase(),
      cuerpo: texto.slice(cuerpoDesde, cuerpoHasta),
      sentencia: texto.slice(desde, puntoComa + 1),
    });
    inicio.lastIndex = puntoComa + 1;
  }
  return halladas;
}

const porArchivo = new Map();
for (const archivo of readdirSync(migracionesDir).filter((f) => f.endsWith('.sql'))) {
  porArchivo.set(archivo, extraerFunciones(readFileSync(join(migracionesDir, archivo), 'utf8')));
}

const orden = [...requeridas.entries()];
const bloques = ['\\set ON_ERROR_STOP on'];
const manifiesto = [];
for (const [nombre, archivo] of orden) {
  const candidatas = (porArchivo.get(archivo) ?? []).filter((f) => f.nombre === nombre);
  if (candidatas.length !== 1) {
    throw new Error(`${nombre}: se esperaba una definicion en ${archivo}; hay ${candidatas.length}`);
  }
  const funcion = candidatas[0];
  bloques.push(`\n-- ${archivo} · md5(prosrc) ${createHash('md5').update(funcion.cuerpo).digest('hex')}\n${funcion.sentencia}`);
  manifiesto.push(`${nombre}|${createHash('md5').update(funcion.cuerpo).digest('hex')}|${archivo}`);
}

writeFileSync(salida, `${bloques.join('\n')}\n`, { flag: 'wx' });
process.stdout.write(`${manifiesto.join('\n')}\n`);
