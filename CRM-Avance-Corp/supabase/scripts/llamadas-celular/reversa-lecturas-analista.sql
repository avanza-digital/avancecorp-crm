-- Reversa de 20261005201010_crm_llamadas_celular_lecturas_analista.sql (octava, lecturas de F4-b). Solo quita las dos
-- puertas y su núcleo: sin tablas ni datos, se puede correr en cualquier momento (la pestaña de F4-b deja de mostrar
-- «Qué pasó hoy» y la marca «Celular»). El banco reducido compara la huella del catálogo antes de la octava y después
-- de esta reversa.
--
-- Orden de las reversas: esta → séptima (reversa-enlace-sin-ciclo.sql) → F4-a → corrección → elegibilidad → ingesta →
-- núcleo → datos.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-lecturas-analista.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer)') is null
     or to_regprocedure('crm.actividades_con_llamada_celular_fn(uuid[])') is null then
    raise exception 'REVERSA_LECTURAS_ANALISTA: la migración 20261005201010 no está aplicada';
  end if;
end;
$precondicion$;

drop function crm.llamadas_celular_resueltas_hoy_fn(integer);
drop function crm.actividades_con_llamada_celular_fn(uuid[]);
drop function private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz);
drop function private.actividades_con_llamada_celular(uuid,uuid[]);

do $postcheck$
begin
  if to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer)') is not null
     or to_regprocedure('crm.actividades_con_llamada_celular_fn(uuid[])') is not null
     or to_regprocedure('private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz)') is not null
     or to_regprocedure('private.actividades_con_llamada_celular(uuid,uuid[])') is not null then
    raise exception 'REVERSA_LECTURAS_ANALISTA: no se volvió al estado de las siete migraciones';
  end if;
end;
$postcheck$;

notify pgrst, 'reload schema';
commit;
