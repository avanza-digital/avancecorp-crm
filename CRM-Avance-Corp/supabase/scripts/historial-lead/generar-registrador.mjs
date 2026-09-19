#!/usr/bin/env node
// Genera supabase/scripts/registrar-20260919185718.sql leyendo la migración del
// archivo (mismo patrón que cartera-procedencia/generar-registrador.mjs):
// PRIMERO aplicar la migración con `db query --linked --file`, DESPUÉS el
// registrador, que se niega a registrar lo que no pasó. Los md5 de las
// definiciones los midió el ensayo en el banco (verificacion.json): son
// deterministas para el mismo cuerpo y el mismo dueño (postgres).
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
export const VERSION = '20260919185718';
export const NOMBRE = 'crm_actividades_de_lead';
const SALIDA = join(AQUI, '..', `registrar-${VERSION}.sql`);
const PUERTA = 'crm.actividades_de_lead_fn(uuid,integer,timestamptz,uuid)';
const NUCLEO = 'private.actividades_de_lead_core(uuid,integer,timestamptz,uuid)';
const AYUDANTE = 'private.nombre_de_autor(uuid)';
const GATE = 'private.assert_actividades_de_lead()';

function delimitadorLibre(base, ...textos) {
  for (let i = 0; i < 50; i++) {
    const tag = i === 0 ? `$${base}$` : `$${base}_${i}$`;
    if (textos.every((t) => !t.includes(tag))) return tag;
  }
  throw new Error('sin delimitador libre');
}

export function generarRegistrador({ md5Puerta, md5Nucleo, md5Ayudante }) {
  for (const [k, v] of Object.entries({ md5Puerta, md5Nucleo, md5Ayudante })) {
    if (!/^[0-9a-f]{32}$/.test(v)) throw new Error(`${k} inválido`);
  }
  const cuerpo = readFileSync(join(AQUI, '..', '..', 'migrations', `${VERSION}_${NOMBRE}.sql`), 'utf8');
  const tag = delimitadorLibre('mig_historial', cuerpo);
  const tagReg = delimitadorLibre('reg_historial', cuerpo, tag);
  return `-- Registra ${VERSION} (${NOMBRE}) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/historial-lead/generar-registrador.mjs leyendo
-- la migración del archivo: no editar a mano; regenerar. Orden de la casa: PRIMERO
-- aplicar la migración con \`db query --linked --file\`, DESPUÉS este registrador.
do ${tagReg}
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := ${tag}${cuerpo}${tag};

  -- 1) PIN: lo que la migración hizo ES verdad — las tres funciones y el gate
  --    existen con la definición publicada (md5 medidos en el banco) y el gate
  --    propio responde OK en ESTA base.
  if to_regprocedure('${PUERTA}') is null
     or to_regprocedure('${NUCLEO}') is null
     or to_regprocedure('${AYUDANTE}') is null
     or to_regprocedure('${GATE}') is null
     or md5(pg_get_functiondef('${PUERTA}'::regprocedure)) is distinct from '${md5Puerta}'
     or md5(pg_get_functiondef('${NUCLEO}'::regprocedure)) is distinct from '${md5Nucleo}'
     or md5(pg_get_functiondef('${AYUDANTE}'::regprocedure)) is distinct from '${md5Ayudante}' then
    raise exception 'registrar historial por lead: la migración ${VERSION} no está aplicada tal cual — aplicarla antes de registrar';
  end if;
  if private.assert_actividades_de_lead() not like 'OK:%' then
    raise exception 'registrar historial por lead: el gate propio no responde OK';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar historial por lead: la versión ${VERSION} existe con OTRO cuerpo — investigar antes de tocar';
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
    raise exception 'registrar historial por lead: la relectura no encontró la fila exacta';
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
    md5Puerta: v.md5_puerta, md5Nucleo: v.md5_nucleo, md5Ayudante: v.md5_ayudante,
  });
  console.log(`registrador escrito: ${s} (${bytes} bytes)`);
}
