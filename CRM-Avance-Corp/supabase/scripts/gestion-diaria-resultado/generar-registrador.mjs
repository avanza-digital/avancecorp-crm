#!/usr/bin/env node
// Genera supabase/scripts/registrar-20260920005000.sql leyendo la migración del
// archivo (patrón gestion-diaria/generar-registrador.mjs): PRIMERO aplicar la
// migración con `db query --linked --file`, DESPUÉS el registrador, que se niega
// a registrar lo que no pasó. Los md5 los mide ensayar.mjs.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
export const VERSION = '20260920005000';
export const NOMBRE = 'crm_gestion_diaria_resultado_llamada';
export const PUERTA = 'crm.registrar_llamada_v3(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)';
export const DESHACER = 'crm.deshacer_resultado_llamada(uuid)';
export const NUCLEO = 'private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)';
export const TRIGGER_FN = 'private.trg_actividades_resultado_solo_nucleo()';
export const HISTORIAL = 'private.actividades_de_lead_core(uuid,integer,timestamptz,uuid)';
const SALIDA = join(AQUI, '..', `registrar-${VERSION}.sql`);

function delimitadorLibre(base, ...textos) {
  for (let i = 0; i < 50; i++) {
    const tag = i === 0 ? `$${base}$` : `$${base}_${i}$`;
    if (textos.every((t) => !t.includes(tag))) return tag;
  }
  throw new Error('sin delimitador libre');
}

export function generarRegistrador({ md5Puerta, md5Nucleo, md5Deshacer }) {
  for (const [k, v] of Object.entries({ md5Puerta, md5Nucleo, md5Deshacer })) {
    if (!/^[0-9a-f]{32}$/.test(v)) throw new Error(`${k} inválido`);
  }
  const cuerpo = readFileSync(join(AQUI, '..', '..', 'migrations', `${VERSION}_${NOMBRE}.sql`), 'utf8');
  if (cuerpo.includes('_PENDIENTE_')) throw new Error('la migración aún tiene md5 sin sellar');
  const tag = delimitadorLibre('mig_gd_resultado', cuerpo);
  const tagReg = delimitadorLibre('reg_gd_resultado', cuerpo, tag);
  return `-- Registra ${VERSION} (${NOMBRE}) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/gestion-diaria-resultado/generar-registrador.mjs
-- leyendo la migración del archivo: no editar a mano; regenerar. Orden de la
-- casa: PRIMERO aplicar la migración con \`db query --linked --file\`, DESPUÉS
-- este registrador. Prerrequisito: 20260919211958 (F1) instalada y registrada.
do ${tagReg}
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := ${tag}${cuerpo}${tag};

  -- 1) PIN: lo que la migración hizo ES verdad — puertas y núcleo con la
  --    definición ensayada, CHECK validado, trigger presente y gate paraguas OK.
  if to_regprocedure('${PUERTA}') is null
     or md5(pg_get_functiondef('${PUERTA}'::regprocedure)) is distinct from '${md5Puerta}'
     or md5(pg_get_functiondef('${NUCLEO}'::regprocedure)) is distinct from '${md5Nucleo}'
     or md5(pg_get_functiondef('${DESHACER}'::regprocedure)) is distinct from '${md5Deshacer}'
     or not exists (select 1 from pg_constraint where conrelid = 'crm.actividades'::regclass
                    and conname = 'actividades_resultado_llamada_forma' and convalidated)
     or not exists (select 1 from pg_trigger where tgrelid = 'crm.actividades'::regclass
                    and tgname = 'trg_00_actividades_resultado_solo_nucleo' and tgenabled in ('O','A'))
     or to_regprocedure('private.assert_gestion_diaria_registro()') is null
     or private.assert_gestion_diaria() not like 'OK%' then
    raise exception 'registrar gestion diaria F2: la migración ${VERSION} no está aplicada tal cual — aplicarla antes de registrar';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20260919211958') then
    raise exception 'registrar gestion diaria F2: la Fase 1 (20260919211958) no está registrada — registrarla antes';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar gestion diaria F2: la versión ${VERSION} existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('${VERSION}', '${NOMBRE}', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed: la fila EXACTA, o se cae la transacción entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and name = '${NOMBRE}'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar gestion diaria F2: la relectura no encontró la fila exacta';
  end if;
end ${tagReg};
`;
}

export function escribirRegistrador(opts) {
  const registrador = generarRegistrador(opts);
  writeFileSync(SALIDA, registrador);
  return { SALIDA, bytes: registrador.length };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const v = JSON.parse(readFileSync(join(AQUI, 'verificacion.json'), 'utf8'));
  const { SALIDA: s, bytes } = escribirRegistrador({ md5Puerta: v.md5_puerta, md5Nucleo: v.md5_nucleo, md5Deshacer: v.md5_deshacer });
  console.log(`registrador escrito: ${s} (${bytes} bytes)`);
}
