-- Reversa de 20261001160219_crm_llamadas_celular_nucleo.sql (F2-c). Retira las puertas y el núcleo;
-- las tablas de 20261001145242 y sus filas QUEDAN (para retirarlas: reversa-datos.sql o
-- reversa-datos-total.sql). Primero se cierra la puerta (revoke) y luego se borra: una llamada en
-- curso no encuentra media API.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-nucleo.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is null then
    raise exception 'REVERSA_NUCLEO: la migración 20261001160219 no está aplicada';
  end if;
end;
$precondicion$;

do $puertas$
declare
  v_f text;
begin
  foreach v_f in array array[
    'crm.llamadas_celular_pendientes_fn(integer)', 'crm.llamada_celular_detalle_fn(uuid)',
    'crm.asociar_llamada_celular(uuid,uuid)', 'crm.enlazar_llamada_celular(uuid,uuid)',
    'crm.descartar_llamada_celular(uuid,text,text)', 'crm.celulares_asignaciones_fn()',
    'crm.asignar_celular(text,uuid)', 'crm.cerrar_asignacion_celular(uuid,text)',
    'crm.rotar_credencial_celular(text)', 'crm.llamadas_celular_politica_fn()',
    'crm.fijar_politica_llamadas_celular(boolean,boolean,integer,integer,integer)'] loop
    if to_regprocedure(v_f) is not null then
      execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
      execute pg_catalog.format('drop function %s', v_f);
    end if;
  end loop;
  -- Núcleo: de quien llama a quien es llamado.
  foreach v_f in array array[
    'private.llamadas_celular_pendientes(uuid,integer)', 'private.llamada_celular_detalle(uuid,uuid)',
    'private.celulares_asignaciones_listar(uuid)',
    'private.llamadas_celular_politica_fijar(uuid,boolean,boolean,integer,integer,integer)',
    'private.celular_rotar_credencial(uuid,text)', 'private.celular_cerrar(uuid,uuid,text)',
    'private.celular_asignar(uuid,text,uuid)', 'private.llamada_celular_descartar(uuid,uuid,text,text)',
    'private.llamada_celular_enlazar(uuid,uuid,uuid)', 'private.llamada_celular_asociar(uuid,uuid,uuid)',
    'private.llamada_celular_ingerir(uuid,jsonb)', 'private.llamadas_celular_actor(text[])',
    'private.llamada_celular_atencion_efectiva(uuid,text,text,uuid)',
    'private.llamada_celular_visible(uuid,uuid,uuid)', 'private.llamada_celular_elegible(uuid,uuid)',
    'private.llamada_celular_candidatos(text[])', 'private.llamada_celular_formas(text)',
    'private.celular_credencial_hash(text)'] loop
    execute pg_catalog.format('drop function if exists %s', v_f);
  end loop;
end;
$puertas$;

do $postcheck$
begin
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where (n.nspname = 'crm' and p.proname in ('llamadas_celular_pendientes_fn', 'llamada_celular_detalle_fn',
                      'asociar_llamada_celular', 'enlazar_llamada_celular', 'descartar_llamada_celular',
                      'celulares_asignaciones_fn', 'asignar_celular', 'cerrar_asignacion_celular',
                      'rotar_credencial_celular', 'llamadas_celular_politica_fn', 'fijar_politica_llamadas_celular'))
                or (n.nspname = 'private' and (p.proname like 'llamada\_celular\_%' or p.proname like 'celular\_%'
                      or p.proname in ('llamadas_celular_actor', 'llamadas_celular_pendientes',
                                       'llamadas_celular_politica_fijar', 'celulares_asignaciones_listar')))) then
    raise exception 'REVERSA_NUCLEO: quedaron funciones del núcleo o puertas sin retirar';
  end if;
  if to_regclass('crm.llamadas_celular_eventos') is null then
    raise exception 'REVERSA_NUCLEO: las tablas de datos no debían tocarse';
  end if;
end;
$postcheck$;

notify pgrst, 'reload schema';
commit;
