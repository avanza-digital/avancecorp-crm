-- Panel de Superadmin: preparación de reglas, sin activar métricas comerciales.
-- Pendiente de autorización e instalación por el circuito de rama de Supabase.
begin;

create function private.control_citas_config_valida(p_config jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
declare
  v_clave text;
  v_numero numeric;
  v_claves text[] := array['citas_por_lead','entrevistas_porcentaje','depositos_porcentaje',
    'excluir_manuales_base','actividad_manuales','conteo_entrevistas','base_avance',
    'mes_resultado','analista_resultado','mes_inicio','mostrar_meta_citas','base_depositos'];
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object'
    or not p_config ?& v_claves or p_config - v_claves <> '{}'::jsonb then return false; end if;
  foreach v_clave in array array['citas_por_lead','entrevistas_porcentaje','depositos_porcentaje'] loop
    if jsonb_typeof(p_config->v_clave) <> 'number' then return false; end if;
    v_numero := (p_config->>v_clave)::numeric;
    if v_numero * 100 <> trunc(v_numero * 100) then return false; end if;
    if v_clave = 'citas_por_lead' then
      if v_numero < 0.01 or v_numero > 10 then return false; end if;
    elsif v_numero < 1 or v_numero > 100 then return false;
    end if;
  end loop;
  return coalesce(
    jsonb_typeof(p_config->'excluir_manuales_base') = 'boolean'
    and p_config->'mostrar_meta_citas' = 'false'::jsonb
    and p_config->'base_depositos' in ('null'::jsonb, '"personas_entrevistadas"'::jsonb, '"entrevistas"'::jsonb)
    and p_config->'actividad_manuales' in ('null'::jsonb, '"excluir"'::jsonb, '"incluir"'::jsonb)
    and p_config->'conteo_entrevistas' in ('null'::jsonb, '"citas_realizadas"'::jsonb, '"personas_unicas"'::jsonb)
    and p_config->'base_avance' in ('null'::jsonb, '"meta_proyectada"'::jsonb, '"actividad_real"'::jsonb)
    and p_config->'mes_resultado' in ('null'::jsonb, '"asignacion"'::jsonb, '"evento"'::jsonb)
    and p_config->'analista_resultado' in ('null'::jsonb, '"asignacion"'::jsonb, '"evento"'::jsonb)
    and (p_config->'mes_inicio' = 'null'::jsonb or
      (jsonb_typeof(p_config->'mes_inicio') = 'string' and p_config->>'mes_inicio' ~ '^(20[0-9]{2})-(0[1-9]|1[0-2])$')),
    false);
end;
$$;
revoke all on function private.control_citas_config_valida(jsonb) from public, anon, authenticated;

create table crm.control_citas_versiones (
  id uuid primary key default gen_random_uuid(),
  version integer not null unique check (version > 0),
  -- Solo inserta la RPC como propietario; no se concede escritura directa.
  configuracion jsonb not null check (private.control_citas_config_valida(configuracion)),
  estado text not null default 'borrador' check (estado = 'borrador'),
  guardado_en timestamptz not null default now(),
  -- Autor retenido: el proyecto desactiva perfiles con activo=false, no los borra.
  guardado_por uuid not null references public.perfiles(id) on delete no action,
  nota text check (char_length(nota) <= 500)
);
alter table crm.control_citas_versiones enable row level security;
revoke all on table crm.control_citas_versiones from public, anon, authenticated;
comment on table crm.control_citas_versiones is
  'Borradores inmutables del control de Citas. Ningún lector de métricas los aplica todavía.';

create function private.control_citas_version_inmutable()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception using errcode = '42501', message = 'El historial de Citas no se modifica. Guarda una nueva versión.';
end;
$$;
revoke all on function private.control_citas_version_inmutable() from public, anon, authenticated;
create trigger control_citas_version_inmutable before update or delete on crm.control_citas_versiones
  for each row execute function private.control_citas_version_inmutable();
create trigger control_citas_truncado_denegado before truncate on crm.control_citas_versiones
  for each statement execute function private.control_citas_version_inmutable();
create trigger trg_audit_control_citas_versiones after insert or update or delete on crm.control_citas_versiones
  for each row execute function private.log_audit_crm();

create function crm.control_citas_configuracion_fn()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_historial jsonb; v_ultimo jsonb;
begin
  if auth.uid() is null or public.es_superadmin() is not true then
    raise exception using errcode = '42501', message = 'Solo Superadmin puede consultar el control de Citas.';
  end if;
  select coalesce(jsonb_agg(to_jsonb(fila) - 'id' order by fila.version desc), '[]'::jsonb)
    into v_historial from (select * from crm.control_citas_versiones order by version desc limit 20) fila;
  v_ultimo := v_historial->0;
  return jsonb_build_object('version_actual', coalesce((v_ultimo->>'version')::integer, 0),
    'ultimo', v_ultimo, 'historial', v_historial);
end;
$$;

create function crm.guardar_control_citas_fn(p_version_esperada integer, p_configuracion jsonb, p_nota text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_version integer;
begin
  if auth.uid() is null or public.es_superadmin() is not true then
    raise exception using errcode = '42501', message = 'Solo Superadmin puede guardar el control de Citas.';
  end if;
  if p_version_esperada is null or p_version_esperada < 0
    or not private.control_citas_config_valida(p_configuracion)
    or char_length(coalesce(p_nota, '')) > 500 then
    raise exception using errcode = '22023', message = 'La configuración de Citas contiene valores no válidos.';
  end if;
  -- Serializa únicamente esta configuración; evita perder cambios entre sesiones.
  perform pg_catalog.pg_advisory_xact_lock(214731, 1257070);
  select coalesce(max(version), 0) into v_version from crm.control_citas_versiones;
  if v_version <> p_version_esperada then
    -- Conflicto de negocio HTTP 409; no es una transacción que deba reintentarse.
    raise exception using errcode = 'PT409', message = 'La configuración cambió en otra sesión. Carga el último borrador antes de guardar.';
  end if;
  insert into crm.control_citas_versiones(version, configuracion, guardado_por, nota)
    values(v_version + 1, p_configuracion, auth.uid(), nullif(btrim(p_nota), ''));
  return crm.control_citas_configuracion_fn();
end;
$$;

revoke all on function crm.control_citas_configuracion_fn() from public, anon, authenticated;
revoke all on function crm.guardar_control_citas_fn(integer,jsonb,text) from public, anon, authenticated;
grant execute on function crm.control_citas_configuracion_fn() to authenticated;
grant execute on function crm.guardar_control_citas_fn(integer,jsonb,text) to authenticated;
commit;
