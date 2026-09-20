#!/usr/bin/env node
// Genera supabase/scripts/registrar-20260919235100.sql leyendo la migración del
// archivo (mismo patrón que historial-lead/generar-registrador.mjs): PRIMERO
// aplicar la migración con `db query --linked --file`, DESPUÉS el registrador,
// que se niega a registrar lo que no pasó. Los md5 de las definiciones se
// miden EN PRODUCCIÓN tras instalar (verificacion.json): `pg_get_functiondef`
// incluye los comentarios internos, así que una copia del banco sin ellos no
// vale (lección de la Fase 1).
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
export const VERSION = '20260919235100';
export const NOMBRE = 'crm_tareas_pendientes_keyset';
const SALIDA = join(AQUI, '..', `registrar-${VERSION}.sql`);
const PUERTA = 'crm.tareas_pendientes_fn(integer,timestamptz,uuid)';
const NUCLEO = 'private.tareas_pendientes_core(integer,timestamptz,uuid)';
const GATE = 'private.assert_tareas_pendientes()';
const INDICE = 'crm.tareas_pendientes_keyset_idx';

function delimitadorLibre(base, ...textos) {
  for (let i = 0; i < 50; i++) {
    const tag = i === 0 ? `$${base}$` : `$${base}_${i}$`;
    if (textos.every((t) => !t.includes(tag))) return tag;
  }
  throw new Error('sin delimitador libre');
}

export function generarRegistrador({ md5Puerta, md5Nucleo }) {
  for (const [k, v] of Object.entries({ md5Puerta, md5Nucleo })) {
    if (!/^[0-9a-f]{32}$/.test(v)) throw new Error(`${k} inválido`);
  }
  const cuerpo = readFileSync(join(AQUI, '..', '..', 'migrations', `${VERSION}_${NOMBRE}.sql`), 'utf8');
  const tag = delimitadorLibre('mig_tareas', cuerpo);
  const tagReg = delimitadorLibre('reg_tareas', cuerpo, tag);
  return `-- Registra ${VERSION} (${NOMBRE}) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/tareas-pendientes/generar-registrador.mjs leyendo
-- la migración del archivo: no editar a mano; regenerar. Orden de la casa: PRIMERO
-- aplicar la migración con \`db query --linked --file\`, DESPUÉS este registrador.
do ${tagReg}
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := ${tag}${cuerpo}${tag};

  -- 1) PIN: lo que la migración hizo ES verdad — puerta, núcleo, gate e índice
  --    existen con la definición publicada (md5 medidos en producción) y el
  --    gate propio responde OK en ESTA base.
  if to_regprocedure('${PUERTA}') is null
     or to_regprocedure('${NUCLEO}') is null
     or to_regprocedure('${GATE}') is null
     or to_regclass('${INDICE}') is null
     or md5(pg_get_functiondef('${PUERTA}'::regprocedure)) is distinct from '${md5Puerta}'
     or md5(pg_get_functiondef('${NUCLEO}'::regprocedure)) is distinct from '${md5Nucleo}' then
    raise exception 'registrar tareas por cursor: la migración ${VERSION} no está aplicada tal cual — aplicarla antes de registrar';
  end if;
  if private.assert_tareas_pendientes() not like 'OK:%' then
    raise exception 'registrar tareas por cursor: el gate propio no responde OK';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar tareas por cursor: la versión ${VERSION} existe con OTRO cuerpo — investigar antes de tocar';
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
    raise exception 'registrar tareas por cursor: la relectura no encontró la fila exacta';
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
