#!/usr/bin/env node
// Genera supabase/scripts/registrar-20261019170422.sql leyendo la migración del archivo (patrón de
// gestion-diaria-analista/generar-registrador.mjs): PRIMERO aplicar la migración con `db query --linked --file`,
// DESPUÉS el registrador, que se niega a registrar lo que no pasó. Las huellas las mide ensayar.mjs (verificacion.json).
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const AQUI = dirname(fileURLToPath(import.meta.url));
export const VERSION = '20261019170422';
export const NOMBRE = 'crm_gestion_diaria_llamadas_clientes';
const AYUDANTE = 'private.gestion_diaria_llamadas_clientes_eventos(timestamptz,timestamptz,uuid[])';
const LECTOR = 'private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])';
const AGREGADOR = 'private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])';
const SALIDA = join(AQUI, '..', `registrar-${VERSION}.sql`);
function delimitadorLibre(base, ...textos) {
  for (let i = 0; i < 50; i++) {
    const tag = i === 0 ? `$${base}$` : `$${base}_${i}$`;
    if (textos.every((t) => !t.includes(tag))) return tag;
  }
  throw new Error('sin delimitador libre');
}
export function generarRegistrador({ md5Ayudante, md5Lector, md5Agregador }) {
  for (const [k, v] of Object.entries({ md5Ayudante, md5Lector, md5Agregador })) {
    if (!/^[0-9a-f]{32}$/.test(v)) throw new Error(`${k} inválido`);
  }
  const cuerpo = readFileSync(join(AQUI, '..', '..', 'migrations', `${VERSION}_${NOMBRE}.sql`), 'utf8');
  if (cuerpo.includes('_PENDIENTE_')) throw new Error('la migración aún tiene huellas sin sellar');
  const tag = delimitadorLibre('mig_gd_llamadas_clientes', cuerpo);
  const tagReg = delimitadorLibre('reg_gd_llamadas_clientes', cuerpo, tag);
  return `-- Registra ${VERSION} (${NOMBRE}) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/gestion-diaria-llamadas-clientes/generar-registrador.mjs leyendo la migración del
-- archivo: no editar a mano; regenerar. Orden de la casa: PRIMERO aplicar la migración con \`db query --linked --file\`,
-- DESPUÉS este registrador.
do ${tagReg}
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := ${tag}${cuerpo}${tag};
  -- 1) PIN: lo que la migración hizo ES verdad — ayudante, lector y agregador con la definición ensayada, el gate del
  --    analista con la sección 1b, los tres gates sin placeholders, y el gate de citas VERDE.
  if to_regprocedure('${AYUDANTE}') is null
     or md5(pg_get_functiondef(to_regprocedure('${AYUDANTE}'))) is distinct from '${md5Ayudante}'
     or md5(pg_get_functiondef(to_regprocedure('${LECTOR}'))) is distinct from '${md5Lector}'
     or md5(pg_get_functiondef(to_regprocedure('${AGREGADOR}'))) is distinct from '${md5Agregador}'
     or pg_get_functiondef(to_regprocedure('private.assert_gestion_diaria_analista()')) not like '%-- 1b. El ayudante DEFINER de las llamadas a CLIENTES%'
     or pg_get_functiondef(to_regprocedure('private.assert_gestion_diaria_analista()')) not like '%${md5Ayudante}%'
     or pg_get_functiondef(to_regprocedure('private.assert_gestion_diaria_citas()')) not like '%${md5Agregador}%'
     or pg_get_functiondef(to_regprocedure('private.assert_gestion_diaria_pulso()')) not like '%${md5Lector}%'
     or pg_get_functiondef(to_regprocedure('private.assert_gestion_diaria_analista()')) like '%_PENDIENTE_%'
     or to_regprocedure('private.assert_gestion_diaria_llamadas_clientes_mutantes()') is null
     or coalesce(pg_get_functiondef(to_regprocedure('private.assert_gestion_diaria_analista()')) like '%-- 1b. El ayudante DEFINER de las llamadas a CLIENTES%', false) is not true then
    raise exception 'registrar llamadas a clientes: la migración ${VERSION} NO está aplicada como se ensayó — no se registra';
  end if;
  perform private.assert_gestion_diaria_citas();
  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar llamadas a clientes: la versión ${VERSION} existe con OTRO cuerpo — investigar antes de tocar';
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
    raise exception 'registrar llamadas a clientes: la relectura no encontró la fila exacta';
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
  const { SALIDA: s, bytes } = escribirRegistrador({ md5Ayudante: v.md5_ayudante, md5Lector: v.md5_lector, md5Agregador: v.md5_agregador });
  console.log(`registrador escrito: ${s} (${bytes} bytes)`);
}
