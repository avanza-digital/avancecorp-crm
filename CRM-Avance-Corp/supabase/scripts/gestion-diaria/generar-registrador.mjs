#!/usr/bin/env node
// Genera supabase/scripts/registrar-20260919211958.sql leyendo la migración del
// archivo (patrón cartera-procedencia/generar-registrador.mjs): PRIMERO aplicar la
// migración con `db query --linked --file`, DESPUÉS el registrador, que se niega
// a registrar lo que no pasó. El md5 de la puerta lo mide ensayar.mjs.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
export const VERSION = '20260919211958';
export const NOMBRE = 'crm_gestion_diaria_registro';
export const PUERTA = 'crm.registro_actividad_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid)';
export const NUCLEO = 'private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid)';
const SALIDA = join(AQUI, '..', `registrar-${VERSION}.sql`);

function delimitadorLibre(base, ...textos) {
  for (let i = 0; i < 50; i++) {
    const tag = i === 0 ? `$${base}$` : `$${base}_${i}$`;
    if (textos.every((t) => !t.includes(tag))) return tag;
  }
  throw new Error('sin delimitador libre');
}

export function generarRegistrador({ md5Puerta, md5Nucleo }) {
  if (!/^[0-9a-f]{32}$/.test(md5Puerta)) throw new Error('md5 de la puerta inválido');
  if (!/^[0-9a-f]{32}$/.test(md5Nucleo)) throw new Error('md5 del núcleo inválido');
  const cuerpo = readFileSync(join(AQUI, '..', '..', 'migrations', `${VERSION}_${NOMBRE}.sql`), 'utf8');
  const tag = delimitadorLibre('mig_gestion_diaria', cuerpo);
  const tagReg = delimitadorLibre('reg_gestion_diaria', cuerpo, tag);
  return `-- Registra ${VERSION} (${NOMBRE}) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/gestion-diaria/generar-registrador.mjs leyendo la
-- migración del archivo: no editar a mano; regenerar. Orden de la casa: PRIMERO
-- aplicar la migración con \`db query --linked --file\`, DESPUÉS este registrador.
do ${tagReg}
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := ${tag}${cuerpo}${tag};

  -- 1) PIN: lo que la migración hizo ES verdad — la puerta existe con la
  --    definición ensayada, el índice está y el gate propio responde OK.
  if to_regprocedure('${PUERTA}') is null
     or md5(pg_get_functiondef('${PUERTA}'::regprocedure)) is distinct from '${md5Puerta}'
     or md5(pg_get_functiondef('${NUCLEO}'::regprocedure)) is distinct from '${md5Nucleo}'
     or not exists (select 1 from pg_indexes where schemaname = 'crm' and indexname = 'actividades_autor_fecha_idx')
     or private.assert_gestion_diaria() not like 'OK%' then
    raise exception 'registrar gestion diaria: la migración ${VERSION} no está aplicada tal cual — aplicarla antes de registrar';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar gestion diaria: la versión ${VERSION} existe con OTRO cuerpo — investigar antes de tocar';
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
    raise exception 'registrar gestion diaria: la relectura no encontró la fila exacta';
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
  const { SALIDA: s, bytes } = escribirRegistrador({ md5Puerta: v.md5_puerta, md5Nucleo: v.md5_nucleo });
  console.log(`registrador escrito: ${s} (${bytes} bytes)`);
}
