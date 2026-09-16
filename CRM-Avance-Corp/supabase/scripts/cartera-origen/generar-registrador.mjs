#!/usr/bin/env node
// Genera supabase/scripts/registrar-20260916220124.sql leyendo la migración del
// archivo (mismo patrón que generar-registrador-facturacion-supervisor.mjs):
// PRIMERO aplicar la migración con `db query --linked --file`, DESPUÉS el
// registrador, que se niega a registrar lo que no pasó.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const VERSION = '20260916220124';
const NOMBRE = 'crm_cartera_filtro_origen';
const SALIDA = join(AQUI, '..', `registrar-${VERSION}.sql`);
const F10 = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text)';
const F9 = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date)';
const MD5_F10 = 'be33021420cd8ae2edbf58692b45e9eb'; // medido en el banco y en producción (16/09)

function delimitadorLibre(base, ...textos) {
  for (let i = 0; i < 50; i++) {
    const tag = i === 0 ? `$${base}$` : `$${base}_${i}$`;
    if (textos.every((t) => !t.includes(tag))) return tag;
  }
  throw new Error('sin delimitador libre');
}

const cuerpo = readFileSync(join(AQUI, '..', '..', 'migrations', `${VERSION}_${NOMBRE}.sql`), 'utf8');
const tag = delimitadorLibre('mig_origen', cuerpo);
const tagReg = delimitadorLibre('reg_origen', cuerpo, tag);

const registrador = `-- Registra ${VERSION} (${NOMBRE}) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/cartera-origen/generar-registrador.mjs leyendo la
-- migración del archivo: no editar a mano; regenerar. Orden de la casa: PRIMERO
-- aplicar la migración con \`db query --linked --file\`, DESPUÉS este registrador.
do ${tagReg}
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := ${tag}${cuerpo}${tag};

  -- 1) PIN: lo que la migración hizo ES verdad — la firma de 10 argumentos existe
  --    con la definición publicada y la de 9 ya no está.
  if to_regprocedure('${F10}') is null
     or to_regprocedure('${F9}') is not null
     or md5(pg_get_functiondef('${F10}'::regprocedure)) is distinct from '${MD5_F10}' then
    raise exception 'registrar cartera origen: la migración ${VERSION} no está aplicada tal cual — aplicarla antes de registrar';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar cartera origen: la versión ${VERSION} existe con OTRO cuerpo — investigar antes de tocar';
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
    raise exception 'registrar cartera origen: la relectura no encontró la fila exacta';
  end if;
end ${tagReg};
`;
writeFileSync(SALIDA, registrador);
console.log(`registrador escrito: ${SALIDA} (${registrador.length} bytes)`);
