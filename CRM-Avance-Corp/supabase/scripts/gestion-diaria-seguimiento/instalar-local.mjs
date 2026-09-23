// Solo el banco sintético que el usuario autorizó. No resetea ni reinstala.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { carpeta, sql, verificarBanco } from '../gestion-diaria-cortes/http/banco.mjs';

assert.deepEqual(process.argv.slice(2), ['--solo-banco-autorizado']);
verificarBanco();
const respaldo = `${carpeta}/gd-f4-antes-etapa4-20260922.dump`;
assert.ok(existsSync(respaldo), 'Falta el respaldo privado del banco anterior a etapa 4');
const archivos = ['20260922184459_crm_gestion_diaria_avisos.sql',
  '20260922185138_crm_gestion_diaria_configuracion.sql', '20260922204125_crm_gestion_diaria_alertas_equipo.sql', '20260922220800_crm_gestion_diaria_avisos_lectura.sql'];
const candidatos = archivos.map(nombre => {
  const fuente = readFileSync(new URL(`../../migrations/${nombre}`, import.meta.url), 'utf8');
  assert.equal((fuente.match(/^begin;$/gm) ?? []).length, 1);
  assert.equal((fuente.match(/^commit;$/gm) ?? []).length, 1);
  return { nombre, sha256: createHash('sha256').update(fuente).digest('hex'), fuente };
});
const instalado = sql("select to_regclass('crm.gestion_diaria_entregas') is not null") === 't';
assert.equal(instalado, false, 'La etapa 4 ya está instalada; no reinstalar');
const politica = JSON.parse(sql('select jsonb_agg(to_jsonb(p) order by version) from crm.politica_gestion_diaria p'));
assert.equal(politica.length, 1);
assert.equal(politica[0].cortes_activos, false);
assert.equal(politica[0].version, 1);
const anteriores = JSON.parse(sql(`select jsonb_agg(jsonb_build_object('firma',p.oid::regprocedure::text,
  'definicion',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner::regrole::text))
  from pg_proc p where p.oid in ('private.assert_gestion_diaria()'::regprocedure,
    'crm.alertas_reconocimientos_sellar()'::regprocedure)`));
const comprobacion = { proyecto: 'gestion-diaria-f4-http', politica, anteriores,
  respaldo, respaldo_sha256: createHash('sha256').update(readFileSync(respaldo)).digest('hex'),
  candidatos: candidatos.map(({nombre,sha256})=>({nombre,sha256})) };
const manifiesto = `${carpeta}/gd-f4-etapa4-instalacion.json`;
assert.equal(existsSync(manifiesto), false, 'Ya hay manifiesto de instalación; revisar el estado antes de continuar');
writeFileSync(`${carpeta}/gd-f4-etapa4-antes.json`, JSON.stringify(comprobacion,null,2)+'\n',{mode:0o600});
sql(`begin; set local lock_timeout='5s';\n${candidatos.map(c=>c.fuente.replace(/^begin;$/m,'').replace(/^commit;$/m,'')).join('\n')}\ncommit;`);
assert.equal(sql('select count(*)=1 and bool_and(version=1 and not cortes_activos) from crm.politica_gestion_diaria'),'t');
writeFileSync(manifiesto,JSON.stringify({...comprobacion, instalado_en:new Date().toISOString()},null,2)+'\n',{mode:0o600,flag:'wx'});
console.log('PASS: cuatro candidatos instalados en gestion-diaria-f4-http con respaldo; política v1 OFF conservada y gates SQL PASS');
