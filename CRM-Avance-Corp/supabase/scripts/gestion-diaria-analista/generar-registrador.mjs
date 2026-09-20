#!/usr/bin/env node
// Genera supabase/scripts/registrar-20260920041500.sql leyendo la migración del
// archivo (patrón gestion-diaria-resultado/generar-registrador.mjs): PRIMERO
// aplicar la migración con `db query --linked --file`, DESPUÉS el registrador,
// que se niega a registrar lo que no pasó. Los md5 los mide ensayar.mjs.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
export const VERSION = '20260920041500';
export const NOMBRE = 'crm_gestion_diaria_analista';
export const PUERTA = 'crm.gestion_diaria_analista_fn(date,uuid)';
export const CORE = 'private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz,uuid)';
export const LLAMADAS = 'private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])';
export const UMBRALES = 'private.gestion_diaria_umbrales()';
export const REGISTRO_CORE = 'private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid)';
const SALIDA = join(AQUI, '..', `registrar-${VERSION}.sql`);

function delimitadorLibre(base, ...textos) {
  for (let i = 0; i < 50; i++) {
    const tag = i === 0 ? `$${base}$` : `$${base}_${i}$`;
    if (textos.every((t) => !t.includes(tag))) return tag;
  }
  throw new Error('sin delimitador libre');
}

export function generarRegistrador({ md5Puerta, md5Core, md5Llamadas, md5Umbrales, md5RegistroCore }) {
  for (const [k, v] of Object.entries({ md5Puerta, md5Core, md5Llamadas, md5Umbrales, md5RegistroCore })) {
    if (!/^[0-9a-f]{32}$/.test(v)) throw new Error(`${k} inválido`);
  }
  const cuerpo = readFileSync(join(AQUI, '..', '..', 'migrations', `${VERSION}_${NOMBRE}.sql`), 'utf8');
  if (cuerpo.includes('_PENDIENTE_')) throw new Error('la migración aún tiene md5 sin sellar');
  const tag = delimitadorLibre('mig_gd_analista', cuerpo);
  const tagReg = delimitadorLibre('reg_gd_analista', cuerpo, tag);
  return `-- Registra ${VERSION} (${NOMBRE}) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/gestion-diaria-analista/generar-registrador.mjs
-- leyendo la migración del archivo: no editar a mano; regenerar. Orden de la
-- casa: PRIMERO aplicar la migración con \`db query --linked --file\`, DESPUÉS
-- este registrador. Prerrequisito: 20260920005000 (F2) instalada y registrada.
do ${tagReg}
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := ${tag}${cuerpo}${tag};

  -- 1) PIN: lo que la migración hizo ES verdad — puerta y núcleos con la
  --    definición ensayada, el núcleo del registro re-sellado y el paraguas OK.
  if to_regprocedure('${PUERTA}') is null
     or md5(pg_get_functiondef('${PUERTA}'::regprocedure)) is distinct from '${md5Puerta}'
     or md5(pg_get_functiondef('${CORE}'::regprocedure)) is distinct from '${md5Core}'
     or md5(pg_get_functiondef('${LLAMADAS}'::regprocedure)) is distinct from '${md5Llamadas}'
     or md5(pg_get_functiondef('${UMBRALES}'::regprocedure)) is distinct from '${md5Umbrales}'
     or md5(pg_get_functiondef('${REGISTRO_CORE}'::regprocedure)) is distinct from '${md5RegistroCore}'
     or to_regprocedure('private.assert_gestion_diaria_analista()') is null
     or private.assert_gestion_diaria() not like 'OK: Gestion Diaria [OK%] [OK%] [OK%]' then
    raise exception 'registrar gestion diaria F3: la migración ${VERSION} no está aplicada tal cual — aplicarla antes de registrar';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20260920005000') then
    raise exception 'registrar gestion diaria F3: la Fase 2 (20260920005000) no está registrada — registrarla antes';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar gestion diaria F3: la versión ${VERSION} existe con OTRO cuerpo — investigar antes de tocar';
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
    raise exception 'registrar gestion diaria F3: la relectura no encontró la fila exacta';
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
  const { SALIDA: s, bytes } = escribirRegistrador({
    md5Puerta: v.md5_puerta, md5Core: v.md5_core, md5Llamadas: v.md5_llamadas, md5Umbrales: v.md5_umbrales, md5RegistroCore: v.md5_registro_core,
  });
  console.log(`registrador escrito: ${s} (${bytes} bytes)`);
}
