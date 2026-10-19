// Exclusivo del stack local de este goal. Sin URL remota, credenciales ni reset.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

export const contenedor = 'supabase_db_avancecorp-recorrido-lead-20261018';
export const ejecutar = (entrada) => spawnSync('docker', ['exec', '-i', contenedor,
  'psql', '-X', '-qAt', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
{ input: '\\set VERBOSITY verbose\n' + entrada, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
export function sql(entrada) {
  const r = ejecutar(entrada);
  assert.equal(r.status, 0, r.stderr || r.error?.message);
  return r.stdout.trim();
}
export const archivo = (ruta) => readFileSync(new URL(ruta, import.meta.url), 'utf8');
export const literal = (valor) => "'" + String(valor).replaceAll("'", "''") + "'";

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [accion, ruta] = process.argv.slice(2);
  if (accion === 'configuracion') {
    assert.ok(ruta, 'Indica la copia local de configuraciones sin datos de clientes.');
    const configuracion = JSON.parse(readFileSync(ruta, 'utf8'));
    const permitidas = new Set(['capital_valoracion_politica', 'configuracion_reparto', 'control_citas_aplicaciones',
      'control_citas_versiones', 'conversion_pesos', 'conversion_politica', 'empresas', 'enfriamiento_politica',
      'gestion_diaria_control_avisos', 'llamadas_celular_politica', 'multiempresa_flags', 'piloto_f8_control',
      'plazos_carga_mes', 'politica_abandono', 'politica_gestion_diaria', 'politica_rentabilidad', 'productos_inversion',
      'sla_operacion_control', 'sla_politica_etapas', 'sla_politica_etapas_operacion', 'sla_politicas']);
    let carga = 'begin; set local session_replication_role=replica;\n';
    for (const [tabla, filas] of Object.entries(configuracion)) {
      assert.ok(tabla.startsWith('crm.') && permitidas.has(tabla.slice(4)), 'Tabla fuera de la copia de configuración');
      assert.ok(Array.isArray(filas));
      assert.equal(sql(`select count(*) from ${tabla};`), '0', `La configuración ${tabla} ya existe; no se sobrescribe.`);
      carga += `insert into ${tabla} select * from jsonb_populate_recordset(null::${tabla},${literal(JSON.stringify(filas))}::jsonb);\n`;
    }
    // Solo carga inicial de configuración del baseline. Las pruebas ejecutan
    // triggers y RLS normales; no modifican implementaciones para lograr PASS.
    carga += 'set local session_replication_role=origin; commit;';
    sql(carga);
    console.log(`PASS: ${Object.keys(configuracion).length} tablas de configuración copiadas al stack local propio.`);
  } else if (accion === 'instalar') {
    // Migraciones ejecutadas como su propietario real, no supabase_admin.
    sql('set role postgres;\n' + archivo('../../migrations/20261019001500_crm_recorrido_evaluacion.sql'));
    sql('set role postgres;\n' + archivo('../../migrations/20261019001501_crm_recorrido_evaluacion_hardening.sql'));
    console.log('PASS: migración de evaluación aplicada únicamente al stack local propio.');
  } else if (accion === 'instalar-oficina') {
    sql('set role postgres;\n' + archivo('../../migrations/20261019001600_crm_recorrido_oficina.sql'));
    sql('set role postgres;\n' + archivo('../../migrations/20261019001601_crm_recorrido_oficina_hardening.sql'));
    console.log('PASS: oficina y hardening aplicados únicamente al stack local propio.');
  } else if (accion === 'test' || accion === 'rendimiento' || accion === 'test-oficina') {
    const rutaTest = { test: './test-evaluacion.sql', rendimiento: './rendimiento.sql', 'test-oficina': './test-oficina.sql' }[accion];
    const r = ejecutar(archivo(rutaTest));
    if (r.stdout) process.stdout.write(r.stdout);
    if (r.stderr) process.stderr.write(r.stderr);
    assert.equal(r.status, 0, 'FAIL: oráculo SQL del recorrido.');
  } else if (accion === 'actualizar-funciones') {
    const migracion = archivo('../../migrations/20261019001500_crm_recorrido_evaluacion.sql');
    const funciones = [...migracion.matchAll(/create(?: or replace)? function[\s\S]+?\bas\s+(\$(?:function)?\$)[\s\S]+?\1;/gi)]
      .map((m) => m[0].replace(/^create(?: or replace)? function/i, 'create or replace function'));
    assert.equal(funciones.length, 9, 'Revisar inventario de funciones antes de actualizar el banco.');
    sql('begin; set local role postgres;\n' + funciones.join('\n') + '\ncommit;');
    console.log('Funciones candidatas actualizadas solo en banco; no sustituye replay integral de la migración.');
  } else {
    throw new Error('Uso: banco.mjs configuracion <json> | instalar | instalar-oficina | test | test-oficina | rendimiento | actualizar-funciones');
  }
}
