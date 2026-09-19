#!/usr/bin/env node
// Genera supabase/scripts/registrar-20260919170500.sql leyendo la migración del
// archivo (mismo patrón que cartera-origen/generar-registrador.mjs): PRIMERO
// aplicar la migración con `db query --linked --file`, DESPUÉS el registrador,
// que se niega a registrar lo que no pasó. El md5 de la firma nueva lo mide
// ensayar.mjs (verificacion.json): es determinista para el mismo cuerpo.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
export const VERSION = '20260919170500';
export const NOMBRE = 'crm_cartera_filtro_procedencia';
const SALIDA = join(AQUI, '..', `registrar-${VERSION}.sql`);
const F11 = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text)';
const F10 = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text)';

function delimitadorLibre(base, ...textos) {
  for (let i = 0; i < 50; i++) {
    const tag = i === 0 ? `$${base}$` : `$${base}_${i}$`;
    if (textos.every((t) => !t.includes(tag))) return tag;
  }
  throw new Error('sin delimitador libre');
}

export function generarRegistrador({ md5F11 }) {
  if (!/^[0-9a-f]{32}$/.test(md5F11)) throw new Error('md5 de la firma de 11 inválido');
  const cuerpo = readFileSync(join(AQUI, '..', '..', 'migrations', `${VERSION}_${NOMBRE}.sql`), 'utf8');
  const tag = delimitadorLibre('mig_procedencia', cuerpo);
  const tagReg = delimitadorLibre('reg_procedencia', cuerpo, tag);
  return `-- Registra ${VERSION} (${NOMBRE}) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/cartera-procedencia/generar-registrador.mjs leyendo
-- la migración del archivo: no editar a mano; regenerar. Orden de la casa: PRIMERO
-- aplicar la migración con \`db query --linked --file\`, DESPUÉS este registrador.
do ${tagReg}
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := ${tag}${cuerpo}${tag};

  -- 1) PIN: lo que la migración hizo ES verdad — la firma de 11 argumentos existe
  --    con la definición publicada y la de 10 ya no está.
  if to_regprocedure('${F11}') is null
     or to_regprocedure('${F10}') is not null
     or md5(pg_get_functiondef('${F11}'::regprocedure)) is distinct from '${md5F11}' then
    raise exception 'registrar cartera procedencia: la migración ${VERSION} no está aplicada tal cual — aplicarla antes de registrar';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar cartera procedencia: la versión ${VERSION} existe con OTRO cuerpo — investigar antes de tocar';
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
    raise exception 'registrar cartera procedencia: la relectura no encontró la fila exacta';
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
  const { SALIDA: s, bytes } = escribirRegistrador({ md5F11: v.md5_f11 });
  console.log(`registrador escrito: ${s} (${bytes} bytes)`);
}
