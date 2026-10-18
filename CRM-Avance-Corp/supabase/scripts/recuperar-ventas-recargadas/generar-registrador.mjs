// Genera supabase/scripts/recuperar-ventas-recargadas/registrar.sql a partir del archivo FINAL de la migración (copia del
// generador de reemplazar-inversion-vista-previa). `supabase db query --linked --file` NO registra la versión en
// supabase_migrations.schema_migrations: el registrador se corre DESPUÉS de aplicar (statements = el archivo entero).
// Regenerarlo tras CADA edición de la migración. Uso: node supabase/scripts/recuperar-ventas-recargadas/generar-registrador.mjs
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const VERSION = '20261018032400';
const NOMBRE = 'crm_recuperar_ventas_recargadas';
const migracion = readFileSync(new URL(`../../migrations/${VERSION}_${NOMBRE}.sql`, import.meta.url), 'utf8');
if (migracion.includes('$mig$')) throw new Error('La migración contiene $mig$: cambia la etiqueta del dólar-quote');
const md5 = createHash('md5').update(migracion).digest('hex');

const sql = `-- REGISTRO en supabase_migrations.schema_migrations de ${VERSION}_${NOMBRE}.
-- GENERADO por generar-registrador.mjs: no editar a mano. \`db query --linked --file\` NO registra: correr DESPUÉS de aplicar
-- la migración. Idempotente; se niega si los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- statements = el archivo entero (md5 ${md5}).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('${NOMBRE}_registro'));
do $chk$
begin
  if (
    to_regclass('crm.conversion_ventas_recuperadas') is not null
    and to_regprocedure('private.proteger_venta_recuperada()') is not null
    and (select count(*) from crm.conversion_ventas_recuperadas) = 5
  ) is not true then
    raise exception 'REGISTRO: la migración ${VERSION} no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '${VERSION}' and (coalesce(name, '') <> '${NOMBRE}' or statements is distinct from array[$mig$${migracion}$mig$])) then
    raise exception 'REGISTRO: la versión ${VERSION} ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('${VERSION}', '${NOMBRE}', array[$mig$${migracion}$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '${VERSION}' and name = '${NOMBRE}' and cardinality(statements) = 1
                   and md5(statements[1]) = '${md5}') then
    raise exception 'REGISTRO: la fila ${VERSION} / ${NOMBRE} no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: ${VERSION} / ${NOMBRE} (1 sentencia: el archivo entero)';
end $post$;
commit;
`;
const destino = fileURLToPath(new URL('./registrar.sql', import.meta.url));
writeFileSync(destino, sql);
console.log(`registrar.sql generado (md5 de la migración ${md5})`);
