#!/usr/bin/env bash
# Monta el BANCO Docker propio del potencial del lead: Postgres de Supabase con el ESQUEMA de
# producción (sin datos). Regla de la casa: banco y worktree propios, no se comparten entornos.
#
# Antes, desde CRM-Avance-Corp/ (solo lectura sobre producción; el volcado no lleva datos):
#   supabase db dump --linked --schema public,crm,private --keep-comments -f /ruta/esquema.sql
#
#   BANCO_CONTENEDOR=avancecorp-potencial-20260930 BANCO_PUERTO=55470 bash banco/montar-banco.sh /ruta/esquema.sql
#
# Después: aplicar las dos migraciones (banco/ciclo-fase1.sh y banco/ciclo-fase2.sh lo hacen).
set -euo pipefail
ESQUEMA="${1:?Uso: montar-banco.sh /ruta/esquema.sql (volcado de producción, solo esquema)}"
C="${BANCO_CONTENEDOR:-avancecorp-potencial-20260930}"
PUERTO="${BANCO_PUERTO:-55470}"
IMAGEN="${BANCO_IMAGEN:-public.ecr.aws/supabase/postgres:17.6.1.105}"   # misma versión que producción (17.6)
[ -f "$ESQUEMA" ] || { echo "No existe $ESQUEMA" >&2; exit 2; }
if docker ps -a --format '{{.Names}}' | grep -qx "$C"; then
  echo "Ya existe un contenedor $C: no se toca. Usa otro BANCO_CONTENEDOR o retíralo tú antes." >&2; exit 2
fi
admin() { docker exec -i -e PGPASSWORD=postgres "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt "$@"; }

docker run -d --name "$C" -e POSTGRES_PASSWORD=postgres -p "127.0.0.1:${PUERTO}:5432" "$IMAGEN" >/dev/null
echo "contenedor $C en 127.0.0.1:$PUERTO; esperando a Postgres…"
# La imagen reinicia Postgres al terminar su inicialización: se exigen dos respuestas seguidas.
listo=0
for _ in $(seq 1 90); do
  if docker exec -e PGPASSWORD=postgres "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -qAt -c "select 1" >/dev/null 2>&1; then
    listo=$((listo + 1)); [ "$listo" -ge 2 ] && break
  else
    listo=0
  fi
  sleep 2
done
[ "$listo" -ge 2 ] || { echo "Postgres no respondió a tiempo" >&2; exit 1; }

# Lo que el volcado espera y la imagen no trae: dos roles de producción y dos extensiones.
admin -c "
do \$\$ begin
  if not exists (select 1 from pg_roles where rolname = 'crm_metricas_bridge') then create role crm_metricas_bridge nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'crm_gestion_diaria_lector') then create role crm_gestion_diaria_lector nologin; end if;
end \$\$;
grant authenticated to crm_gestion_diaria_lector;
create extension if not exists btree_gist with schema extensions;
create extension if not exists pg_trgm with schema extensions;"

docker cp "$ESQUEMA" "$C:/tmp/esquema.sql" >/dev/null
docker exec -e PGPASSWORD=postgres "$C" psql -U supabase_admin -h 127.0.0.1 -d postgres -q -f /tmp/esquema.sql > /tmp/"$C"-carga.log 2>&1 || true
echo "errores de la carga: $(grep -c 'ERROR' /tmp/"$C"-carga.log) (se espera 1: storage.objects no existe en la imagen pelada)"
grep 'ERROR' /tmp/"$C"-carga.log | sort | uniq -c | sort -rn | head -5

# Historial de migraciones (lo usan los registradores) y pg_cron como en producción: dueño y
# permisos de postgres, que es quien aplica las migraciones y corre los jobs.
admin -c "
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations (version text primary key, statements text[], name text);
alter schema supabase_migrations owner to postgres;
alter table supabase_migrations.schema_migrations owner to postgres;
create extension if not exists pg_cron;
grant usage on schema cron to postgres with grant option;
grant all on all tables in schema cron to postgres with grant option;
grant all on all functions in schema cron to postgres with grant option;
grant all on all sequences in schema cron to postgres with grant option;"

# Paridad: comparar estas huellas con las de producción (misma consulta por `supabase db query
# --linked`). Con search_path vacío: el texto de pg_get_functiondef cambia con el search_path.
echo "huellas del banco (comparar con producción):"
admin -c "set search_path = ''; select n.nspname || '|' || count(*) || '|' || md5(string_agg(md5(pg_catalog.pg_get_functiondef(p.oid)), ',' order by p.oid::pg_catalog.regprocedure::text)) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace where n.nspname in ('crm','private') and p.prokind = 'f' group by n.nspname order by 1;" | grep -v '^SET$'
echo "listo. auth.uid() de esta imagen solo lee request.jwt.claim.sub (el de producción también request.jwt.claims): las pruebas fijan las dos."
