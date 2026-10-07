-- Reversa de 20261001212258_crm_llamadas_celular_ingesta.sql (F3-a). Retira las puertas de servicio
-- y de lectura, su núcleo, la tabla técnica private.celulares_estado (contadores del límite y
-- latidos: no es evidencia) y las dos columnas de límite de la política. La evidencia de cada
-- llamada sigue en crm.llamadas_celular_eventos. Primero se cierra la puerta (revoke) y luego se
-- borra: una llamada en curso no encuentra media API.
--
-- Orden de las reversas: ingesta (esta) → núcleo (reversa-nucleo.sql) → datos.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-ingesta.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('crm.ingerir_llamada_celular_servicio(text,jsonb)') is null then
    raise exception 'REVERSA_INGESTA: la migración 20261001212258 no está aplicada';
  end if;
  if to_regclass('private.llamadas_celular_recepciones') is not null then
    raise exception 'REVERSA_INGESTA: la corrección 20261005143843 sigue instalada; primero reversa-correccion.sql';
  end if;
end;
$precondicion$;

do $retiro$
declare
  v_f text;
begin
  foreach v_f in array array[
    'crm.ingerir_llamada_celular_servicio(text,jsonb)', 'crm.registrar_salud_celular_servicio(text,jsonb)',
    'crm.llamadas_celular_bandeja_fn(integer,timestamptz,uuid)', 'crm.celulares_salud_fn()'] loop
    if to_regprocedure(v_f) is not null then
      execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
      execute pg_catalog.format('drop function %s', v_f);
    end if;
  end loop;
  -- Núcleo: de quien llama a quien es llamado.
  foreach v_f in array array[
    'private.celulares_salud_listar(uuid)', 'private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)',
    'private.celular_registrar_salud(uuid,jsonb)', 'private.celular_consumir_envio(uuid)',
    'private.celular_por_credencial(text)'] loop
    execute pg_catalog.format('drop function if exists %s', v_f);
  end loop;
end;
$retiro$;

drop table if exists private.celulares_estado;
drop function if exists private.trg_celulares_estado_candado();
alter table crm.llamadas_celular_politica
  drop constraint if exists llamadas_celular_politica_limites_coherentes,
  drop column if exists limite_envios_minuto,
  drop column if exists limite_envios_dia;

do $postcheck$
begin
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where (n.nspname = 'crm' and p.proname in ('ingerir_llamada_celular_servicio',
                      'registrar_salud_celular_servicio', 'llamadas_celular_bandeja_fn', 'celulares_salud_fn'))
                or (n.nspname = 'private' and p.proname in ('celular_por_credencial', 'celular_consumir_envio',
                      'celular_registrar_salud', 'llamadas_celular_bandeja', 'celulares_salud_listar',
                      'trg_celulares_estado_candado'))) then
    raise exception 'REVERSA_INGESTA: quedaron puertas o núcleo de la ingesta sin retirar';
  end if;
  if to_regclass('private.celulares_estado') is not null
     or exists (select 1 from pg_catalog.pg_attribute a
                where a.attrelid = 'crm.llamadas_celular_politica'::regclass
                  and a.attname in ('limite_envios_minuto', 'limite_envios_dia') and not a.attisdropped) then
    raise exception 'REVERSA_INGESTA: quedaron la tabla técnica o los límites de la política';
  end if;
  if to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is null
     or to_regclass('crm.llamadas_celular_eventos') is null then
    raise exception 'REVERSA_INGESTA: el núcleo y las tablas de F2 no debían tocarse';
  end if;
end;
$postcheck$;

notify pgrst, 'reload schema';
commit;
