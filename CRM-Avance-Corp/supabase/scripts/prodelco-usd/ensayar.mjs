#!/usr/bin/env node
// Ensayo completo de «Prodelco en dólares» sobre una copia local llevada a
// PARIDAD con producción. Nunca toca producción: `banco.mjs` fija el contenedor
// y la base, y no acepta destinos externos.
//
//   node supabase/scripts/prodelco-usd/ensayar.mjs
//
// Pasos, en este orden:
//   1. Copia nueva desde la plantilla y paridad con producción: la definición
//      viva de `crm.corregir_cierre_externo` (las plantillas locales van un
//      commit por detrás) y las CUATRO banderas F4 encendidas, como en
//      producción el 17/09. Sin esto, la ruta F4 —la que escribe la moneda— no
//      se recorrería y el ensayo mediría otra cosa.
//   2. La migración se aplica y su propio postflight manda.
//   3. El oráculo de conducta (10 casos).
//   4. MUTANTES: por cada defensa, alguien que la rompa. Si el oráculo no lo
//      caza, la prueba no prueba nada.
//   5. Segunda aplicación: debe NEGARSE (los escritores ya no son los medidos).
//   6. El registrador: registra, es idempotente y se niega con otro cuerpo.
//   7. La reversa: se niega si hay dólares vivos, y limpia vuelve al estado
//      anterior byte a byte.
//   8. Reinstalación + oráculo, para dejar la copia coherente.
//
// Escribe `verificacion.json` con lo medido.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { db, plantilla, contenedor, ejecutar, sql, objeto, debeFallar } from './banco.mjs';
import { spawnSync } from 'node:child_process';

const AQUI = dirname(fileURLToPath(import.meta.url));
const leer = (rel) => readFileSync(join(AQUI, rel), 'utf8');
const MIG = leer('../../migrations/20260917235656_crm_prodelco_inversiones_en_dolares.sql');
const REG = leer('../registrar-20260917235656.sql');
const REV = leer('./reversa.sql');
const ORA = leer('./test-prodelco-usd.sql');
const sinTx = (s) => s.replace(/^begin;\n/m, '').replace(/^commit;\s*$/m, '');

const ESCRITORES = {
  convertir: 'crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text,integer,numeric)',
  corregir: 'crm.corregir_cierre_externo(uuid,numeric,text,text,text,text,date,text)',
  validar: 'private.inversion_validar_datos(uuid,jsonb,jsonb)',
  confirmar: 'crm.confirmar_inversion_revisada_fn(uuid,integer)',
  correccionF4: 'crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)',
};
// Huellas de producción ANTES de la migración, medidas el 17/09/2026.
const ANTES = {
  convertir: '3f1cded7e40c54c98bcf461665c6f8ff',
  corregir: '894806c9b0a765eff7896f42d51f8bff',
  validar: '96b4e342df9cc08a875bac34ca17a829',
  confirmar: '8ab0be625fecb7916de44286425c0688',
  correccionF4: '3de3d2689706371cdc46f0a29836cb5c',
};
// Huellas DESPUÉS, las que publica la migración.
const DESPUES = {
  convertir: 'f1759833df86b0a7e6f08d21ec2260c4',
  corregir: '93c3c6eb72b37fdf58b537781154ab88',
  validar: '7c7f4bb5d77a7834571af850585f505f',
  confirmar: 'eb671aa677a9ba63fa995510e4f48192',
  correccionF4: 'fe210a25d8a08cfbce923d3ac12ab199',
};

const md5Vivo = (f) => sql(`select coalesce(md5(pg_get_functiondef(to_regprocedure('${f}'))),'-')`);
const definicion = (f) => sql(`select pg_get_functiondef('${f}'::regprocedure)`);
const catalogo = () => sql(`select (select jsonb_object_agg(clave,monedas order by clave) from crm.empresas)::text`);
const checkMoneda = () =>
  sql(`select pg_get_constraintdef(oid) from pg_constraint where conrelid='crm.cierres_externos'::regclass and conname='cierres_externos_moneda_check'`);
const oraculo = () => sql(ORA);
const paso = (n) => console.log(`\n── ${n}`);

// ── 1. Copia nueva y paridad con producción ─────────────────────────────────
paso('1. copia nueva desde la plantilla y paridad con producción');
const admin = (s, base = 'postgres') =>
  spawnSync('docker', ['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', 'supabase_admin', '-d', base, '-c', s], {
    encoding: 'utf8',
  });
assert.equal(admin(`drop database if exists ${db}`).status, 0, 'no se pudo soltar la copia anterior');
assert.equal(
  admin(`create database ${db} template ${plantilla} owner supabase_admin`).status,
  0,
  `no se pudo crear ${db} desde ${plantilla}`,
);
assert.equal(sql('select current_database()'), db, 'la copia no es la esperada');

// `crm.corregir_cierre_externo`: las plantillas locales no traen la guarda de
// `crm.gestion_neutral` que sí tiene producción. Se instala la definición VIVA.
sql(leer('./paridad-corregir-cierre-externo.sql'));
for (const [k, f] of Object.entries(ESCRITORES)) {
  assert.equal(md5Vivo(f), ANTES[k], `la copia no parte de la definición viva de ${f}`);
}
// Las banderas, como producción el 17/09: las cuatro de F3/F4/F5 encendidas.
sql(`update crm.multiempresa_flags set activo=true
     where nombre in ('resolver_en_puertas','inversiones_escritura','ficha_360_neutral','postventa_neutral');
     update crm.multiempresa_flags set activo=false where nombre='metricas_multiempresa_sombra';`);
assert.equal(
  sql(`select activo::text from crm.multiempresa_flags where nombre='inversiones_escritura'`),
  'true',
  'la escritura F4 tiene que estar encendida: es la ruta que escribe la moneda',
);
// La tabla del registro no viene en la plantilla; el registrador la necesita.
admin(
  `create schema if not exists supabase_migrations;
   create table if not exists supabase_migrations.schema_migrations(
     version text primary key, statements text[], name text, created_by text,
     idempotency_key text unique, rollback text[]);
   grant usage on schema supabase_migrations to postgres;
   grant all on supabase_migrations.schema_migrations to postgres;`,
  db,
);
const catalogoAntes = catalogo();
const checkAntes = checkMoneda();
assert.equal(checkAntes, "CHECK ((moneda = 'PEN'::text))", 'el CHECK de partida no es el de producción');
const defsAntes = Object.fromEntries(Object.entries(ESCRITORES).map(([k, f]) => [k, definicion(f)]));
console.log(`   catálogo: ${catalogoAntes}`);

// ── 2. La migración ─────────────────────────────────────────────────────────
paso('2. aplicar la migración (su postflight manda)');
sql(MIG);
assert.equal(catalogo(), '{"avance": ["PEN", "USD"], "prodelco": ["PEN", "USD"], "qorilazo": ["PEN"]}');
assert.equal(checkMoneda(), `CHECK ((moneda = ANY (ARRAY['PEN'::text, 'USD'::text])))`);
for (const [k, f] of Object.entries(ESCRITORES)) assert.equal(md5Vivo(f), DESPUES[k], `${f} no quedó como se esperaba`);
const defsDespues = Object.fromEntries(Object.entries(ESCRITORES).map(([k, f]) => [k, definicion(f)]));
console.log('   catálogo abierto para Prodelco, Qorilazo intacto');

// ── 3. El oráculo ───────────────────────────────────────────────────────────
paso('3. oráculo de conducta');
assert.match(oraculo(), /PRODELCO_USD_OK\|13/, 'el oráculo no quedó verde');
console.log('   PRODELCO_USD_OK · 13 casos');

// ── 4. Mutantes ─────────────────────────────────────────────────────────────
paso('4. mutantes: por cada defensa, alguien que la rompa');
const mutantes = [
  {
    nombre: 'M1 · el escritor vuelve a decir PEN a mano',
    instalar: () => sql(defsAntes.convertir + ';'),
    caza: /PUSD-01/,
    restaurar: () => sql(defsDespues.convertir + ';'),
  },
  {
    nombre: 'M2 · el escritor ignora la cooperativa y mira siempre Prodelco',
    instalar: () =>
      sql(defsDespues.convertir.replace('where e.clave = p_cooperativa', "where e.clave = 'prodelco'") + ';'),
    caza: /PUSD-02/,
    restaurar: () => sql(defsDespues.convertir + ';'),
  },
  {
    nombre: 'M3 · sin la guarda del null (el candado se abriría solo)',
    instalar: () =>
      sql(
        defsDespues.convertir.replace(
          /  if v_monedas is null then\n    raise exception 'Esa cooperativa no esta registrada[^\n]*\n      using errcode = '22023';\n  end if;\n/,
          '',
        ) + ';',
      ),
    caza: /PUSD-05/,
    restaurar: () => sql(defsDespues.convertir + ';'),
  },
  {
    nombre: 'M4 · el insert F4 vuelve a fijar PEN',
    instalar: () =>
      sql(
        defsDespues.confirmar.replace(
          "(v_s.datos->>'monto')::numeric,v_s.datos->>'moneda',",
          "(v_s.datos->>'monto')::numeric,'PEN',",
        ) + ';',
      ),
    caza: /PUSD-10/,
    restaurar: () => sql(defsDespues.confirmar + ';'),
  },
  {
    nombre: 'M6 · la corrección F4 deja de declarar la moneda inmutable',
    instalar: () =>
      sql(
        defsDespues.correccionF4.replace(
          "    or p_datos->'moneda' is distinct from v_s.datos->'moneda'\n",
          '',
        ) + ';',
      ),
    caza: /PUSD-11/,
    restaurar: () => sql(defsDespues.correccionF4 + ';'),
  },
  {
    nombre: 'M7 · gerencia puede cambiar la moneda en un mes sellado',
    instalar: () =>
      sql(defsDespues.corregir.replace(/  if p_moneda is distinct from v_cierre\.moneda then[\s\S]*?\n  end if;\n\n  perform set_config/, '  perform set_config') + ';'),
    caza: /PUSD-13/,
    restaurar: () => sql(defsDespues.corregir + ';'),
  },
  {
    nombre: 'M5 · el CHECK de la tabla vuelve a solo soles',
    instalar: () =>
      sql(`alter table crm.cierres_externos drop constraint cierres_externos_moneda_check;
           alter table crm.cierres_externos add constraint cierres_externos_moneda_check check (moneda='PEN');`),
    caza: /PUSD-01/,
    restaurar: () =>
      sql(`alter table crm.cierres_externos drop constraint cierres_externos_moneda_check;
           alter table crm.cierres_externos add constraint cierres_externos_moneda_check check (moneda = any(array['PEN','USD']));`),
  },
];
const cazados = [];
for (const m of mutantes) {
  m.instalar();
  const r = ejecutar(ORA);
  assert.notEqual(r.status, 0, `${m.nombre}: el oráculo NO lo cazó`);
  assert.match(r.stderr, m.caza, `${m.nombre}: lo cazó otro caso, no el que lo cubre`);
  m.restaurar();
  assert.match(oraculo(), /PRODELCO_USD_OK\|13/, `${m.nombre}: la restauración no dejó el oráculo verde`);
  cazados.push(m.nombre);
  console.log(`   ✔ ${m.nombre}`);
}

// ── 5. Segunda aplicación: fail-closed ──────────────────────────────────────
paso('5. la migración no se aplica dos veces');
debeFallar(sinTx(MIG), /PREFLIGHT: .*no es la definición viva del 17\/09/, 'segunda aplicación');
console.log('   negada por el preflight');

// ── 6. El registrador ───────────────────────────────────────────────────────
paso('6. el registrador');
sql(REG);
const fila = objeto(
  `select jsonb_build_object('name',name,'n',cardinality(statements),'md5',md5(statements[1]))
   from supabase_migrations.schema_migrations where version='20260917235656'`,
);
assert.equal(fila.name, 'crm_prodelco_inversiones_en_dolares');
assert.equal(fila.n, 1);
assert.equal(fila.md5, sql(`select md5(${"$m$"}${MIG}${"$m$"})`), 'el cuerpo registrado no es el del archivo');
sql(REG); // idempotente
debeFallar(
  `update supabase_migrations.schema_migrations set statements=array['-- cuerpo ajeno'] where version='20260917235656';\n${REG}`,
  /existe con OTRO cuerpo/,
  'registrar sobre otro cuerpo',
);
console.log('   registrado, idempotente y fail-closed');

// ── 7. La reversa ───────────────────────────────────────────────────────────
paso('7. la reversa');
const leadLibre = `(select l.id from crm.leads l
  where l.activo and l.etapa not in ('convertido','descartado') and l.vendedor_id is not null
    and private.rol_crm(l.vendedor_id) is not null
    and exists (select 1 from crm.equipo e where e.perfil_id=l.vendedor_id and e.activo) limit 1)`;
debeFallar(
  `create temporary table rev_lead on commit drop as select ${leadLibre} lead;
   select set_config('request.jwt.claim.sub',(select l.vendedor_id from crm.leads l join rev_lead r on r.lead=l.id)::text,true);
   select crm.convertir_lead_externo((select lead from rev_lead),'prodelco',777.00,'USD','DNI','48888888','CENTINELA USD','CENT-USD-REV');
   ${sinTx(REV)}`,
  /hay 1 cierre\(s\) en otra moneda/,
  'reversa con dólares vivos',
);
sql(REV);
assert.equal(catalogo(), catalogoAntes, 'la reversa no devolvió el catálogo');
assert.equal(checkMoneda(), checkAntes, 'la reversa no devolvió el CHECK');
for (const [k, f] of Object.entries(ESCRITORES)) {
  assert.equal(md5Vivo(f), ANTES[k], `la reversa no devolvió ${f} byte a byte`);
}
console.log('   se niega con dólares vivos; limpia devuelve el estado anterior byte a byte');

// ── 8. Reinstalación ────────────────────────────────────────────────────────
paso('8. reinstalación');
sql(MIG);
sql(REG);
assert.match(oraculo(), /PRODELCO_USD_OK\|13/, 'tras reinstalar, el oráculo no quedó verde');
console.log('   reinstalada y verde');

const verificacion = {
  fecha: new Date().toISOString(),
  copia: db,
  plantilla,
  migracion: '20260917235656_crm_prodelco_inversiones_en_dolares.sql',
  md5_migracion: sql(`select md5(${"$m$"}${MIG}${"$m$"})`),
  catalogo_antes: catalogoAntes,
  catalogo_despues: catalogo(),
  check_antes: checkAntes,
  check_despues: checkMoneda(),
  escritores_antes: ANTES,
  escritores_despues: DESPUES,
  oraculo: 'PRODELCO_USD_OK · 13 casos',
  mutantes_cazados: cazados,
  segunda_aplicacion: 'negada por el preflight',
  registrador: 'registra, idempotente, se niega con otro cuerpo',
  reversa: 'se niega con dólares vivos y con solicitudes F4 en otra moneda; limpia devuelve los CINCO escritores byte a byte',
};
writeFileSync(join(AQUI, 'verificacion.json'), JSON.stringify(verificacion, null, 2) + '\n');
console.log('\n✅ ENSAYO COMPLETO — verificacion.json escrito');
