// Genera registrar.sql leyendo la migración del archivo. Orden de la casa: PRIMERO aplicar la
// migración (`supabase db query --linked --file`, que NO registra) y DESPUÉS este guion, que
// se niega a registrar lo que no pasó. statements = el archivo entero, en un solo elemento.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import { VERSION, NOMBRE, F12, F13 } from './generar-reversa.mjs';

export const RUTA_MIGRACION = new URL(`../../migrations/${VERSION}_${NOMBRE}.sql`, import.meta.url);

export function generarRegistrador({ md5F13 }) {
  assert.match(md5F13, /^[0-9a-f]{32}$/);
  const cuerpo = readFileSync(RUTA_MIGRACION, 'utf8');
  const tag = `$migracion_${VERSION}$`;
  for (const reservado of [tag, '$chk$', '$post$']) {
    assert.ok(!cuerpo.includes(reservado), `El delimitador ${reservado} del registrador aparece en la migración`);
  }
  const md5Archivo = createHash('md5').update(cuerpo, 'utf8').digest('hex');
  return `-- REGISTRO en supabase_migrations.schema_migrations de ${VERSION}_${NOMBRE}.
-- \`db query --linked --file\` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se
-- niega si la firma de 13 argumentos no es la publicada o si la versión ya está registrada con
-- otro nombre u otro contenido. statements = el archivo entero (md5 ${md5Archivo}).
-- GENERADO por supabase/scripts/cartera-gestion/generar-registrador.mjs; no editar a mano.
begin;
set local lock_timeout = '5s';
set local search_path = '';
select pg_advisory_xact_lock(hashtext('${NOMBRE}_registro'));
do $chk$
begin
  if (
    to_regprocedure('${F13}') is not null
    and to_regprocedure('${F12}') is null
    and md5(pg_get_functiondef(to_regprocedure('${F13}'))) = '${md5F13}'
  ) is not true then
    raise exception 'REGISTRO: la migración ${VERSION} no está aplicada tal cual; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '${VERSION}' and (coalesce(name, '') <> '${NOMBRE}' or statements is distinct from array[${tag}${cuerpo}${tag}])) then
    raise exception 'REGISTRO: la versión ${VERSION} ya está registrada con otro nombre u otro contenido; investigar antes de tocar';
  end if;
end;
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('${VERSION}', '${NOMBRE}', array[${tag}${cuerpo}${tag}])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '${VERSION}' and name = '${NOMBRE}' and cardinality(statements) = 1
                   and md5(statements[1]) = '${md5Archivo}') then
    raise exception 'REGISTRO: la fila ${VERSION} / ${NOMBRE} no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: ${VERSION} / ${NOMBRE} (1 sentencia: el archivo entero)';
end;
$post$;
commit;
`;
}
