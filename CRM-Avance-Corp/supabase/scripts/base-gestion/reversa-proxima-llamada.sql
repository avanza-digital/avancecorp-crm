-- Reversa de 20261002224851_crm_base_gestion_proxima_llamada.sql (Base para gestión · B1b). Aplicar ANTES que la reversa de B1.
-- Devuelve el sello, el CHECK y las constantes a su forma de B1 (20261002054402), quita el índice y la columna.
-- Solo se pierden las rellamadas agendadas (proxima_llamada_en).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
do $pre$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'leads' and column_name = 'proxima_llamada_en') then
    raise exception 'REVERSA B1b: proxima_llamada_en no existe; nada que revertir';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('crm', 'private') and p.proname <> 'trg_leads_zz_sello_base_gestion'
                and p.prosrc ~ 'proxima_llamada_en|dias_max_rellamada') then
    raise exception 'REVERSA B1b: quedan nucleos/puertas (B3/B4) que usan proxima_llamada_en; revertirlos antes';
  end if;
end;
$pre$;
drop index if exists crm.idx_leads_base_rellamada;
alter table crm.actividades drop constraint if exists actividades_intento_base_forma;
alter table crm.actividades add constraint actividades_intento_base_forma check (
  coalesce(metadata->>'evento', '') <> 'intento_base'
  or (
    coalesce(metadata->>'resultado', '') in (
      'no_contesto', 'volver_a_llamar', 'agendo_reunion', 'no_interesado',
      'numero_errado', 'no_es_la_persona', 'pide_otro_producto')
    and coalesce(metadata->>'intento_n', '') ~ '^[1-9][0-9]{0,5}$'
    and coalesce(metadata->>'ciclo_n', '') ~ '^[1-9][0-9]{0,5}$'
    and (metadata->>'submotivo' is null or metadata->>'submotivo' in (
      'sin_fondos_ahora', 'ya_invirtio_con_otro', 'desconfianza', 'no_le_interesa_invertir',
      'prestamo', 'credito', 'otro'))
    and (coalesce(metadata->>'resultado', '') <> 'volver_a_llamar'
         or coalesce(metadata->>'tarea_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  )
) not valid;
alter table crm.actividades validate constraint actividades_intento_base_forma;
comment on constraint actividades_intento_base_forma on crm.actividades is
  'Base para gestión (B1): toda actividad con evento=intento_base trae resultado del MISMO catálogo cerrado de 7 valores de Gestión Diaria, intento_n y ciclo_n enteros >= 1, submotivo del catálogo si viene, y tarea_id (uuid de la rellamada en crm.tareas) cuando el resultado es volver_a_llamar. De forma, no de presencia.';
drop function private.base_gestion_constantes();
create function private.base_gestion_constantes()
returns table (max_intentos integer, dias_enfriamiento integer)
language sql immutable security invoker set search_path = ''
as $$ select 3, 30; $$;
alter function private.base_gestion_constantes() owner to postgres;
revoke all on function private.base_gestion_constantes() from public, anon, authenticated, service_role;
comment on function private.base_gestion_constantes() is
  'Base para gestión (B1, D4): constantes de negocio en un solo sitio. max_intentos = intentos sin cita ni reactivación que agotan al lead en su ciclo; dias_enfriamiento = días Lima que descansa fuera de la base. Las consumen los núcleos (DEFINER); cambiarlas es una migración.';
create or replace function private.trg_leads_zz_sello_base_gestion()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    return new;  -- migraciones y jobs internos, como el trigger «solo núcleo» de actividades
  end if;
  if coalesce(pg_catalog.current_setting('crm.op_base_gestion', true), 'off') = 'on' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.reactivado_en is not null or new.enfriado_hasta is not null then
      raise exception 'reactivado_en y enfriado_hasta los escribe solo la base para gestion (su nucleo)'
        using errcode = '42501';
    end if;
  elsif new.reactivado_en is distinct from old.reactivado_en
     or new.enfriado_hasta is distinct from old.enfriado_hasta then
    raise exception 'reactivado_en y enfriado_hasta los escribe solo la base para gestion (su nucleo)'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
alter function private.trg_leads_zz_sello_base_gestion() owner to postgres;
revoke all on function private.trg_leads_zz_sello_base_gestion() from public, anon, authenticated, service_role;
comment on function private.trg_leads_zz_sello_base_gestion() is
  'Base para gestión (B1): sello de las columnas reactivado_en y enfriado_hasta de crm.leads. Las acepta solo bajo el GUC de transacción crm.op_base_gestion=on (núcleos de B3/B4 y puerta de Gerencia) o sin usuario (migraciones). DEFINER por el mismo molde que trg_actividades_resultado_solo_nucleo y trg_leads_no_contactar_solo_puerta (INVOKER también valdría): cerrado con search_path vacío, dueño postgres y sin EXECUTE para la API; no lee tablas, no amplía ámbito.';
drop trigger if exists trg_leads_zz_sello_base_gestion on crm.leads;
create trigger trg_leads_zz_sello_base_gestion
  before insert or update of reactivado_en, enfriado_hasta on crm.leads
  for each row execute function private.trg_leads_zz_sello_base_gestion();
alter table crm.leads drop column proxima_llamada_en;
do $post$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'leads' and column_name = 'proxima_llamada_en')
     or (select count(*) from pg_proc p, unnest(p.proargnames) n where p.oid = to_regprocedure('private.base_gestion_constantes()')) <> 2
     or (select array_length(t.tgattr::smallint[], 1) from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_sello_base_gestion') <> 2
     or (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'crm.actividades'::regclass and c.conname = 'actividades_intento_base_forma') not like '%tarea_id%' then
    raise exception 'REVERSA B1b: quedo alguna pieza';
  end if;
  raise notice 'reversa base_gestion_proxima_llamada OK';
end;
$post$;
notify pgrst, 'reload schema';
commit;
