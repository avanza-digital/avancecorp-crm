-- P-047 · Política de enfriamiento + RPC de verificación de disponibilidad de lead
-- Restaurada desde supabase_migrations.schema_migrations de producción.
-- Aditivo: no modifica tablas, índices, triggers ni políticas existentes.

-- 1) Tabla de política editable
create table crm.enfriamiento_politica (
  motivo text primary key
    check (motivo in ('sin_interes','sin_fondos','competencia','no_responde','datos_invalidos','pide_credito','otro')),
  dias integer not null check (dias >= 0),
  actualizado_por uuid references public.perfiles(id),
  actualizado_en timestamptz not null default now()
);

comment on table crm.enfriamiento_politica is
  'Días de espera antes de que una persona descartada pueda reingresarse como lead, según motivo de descarte. Editable solo por gerencia.';

insert into crm.enfriamiento_politica (motivo, dias) values
  ('sin_interes', 30),
  ('sin_fondos', 90),
  ('competencia', 180),
  ('no_responde', 15),
  ('otro', 20),
  ('pide_credito', 0),
  ('datos_invalidos', 0);

-- RLS: lectura para todo usuario autenticado; escritura solo gerencia.
alter table crm.enfriamiento_politica enable row level security;

create policy enfriamiento_select on crm.enfriamiento_politica
  for select to authenticated using (true);

create policy enfriamiento_insert on crm.enfriamiento_politica
  for insert to authenticated
  with check (private.rol_crm(auth.uid()) = 'gerencia');

create policy enfriamiento_update on crm.enfriamiento_politica
  for update to authenticated
  using (private.rol_crm(auth.uid()) = 'gerencia')
  with check (private.rol_crm(auth.uid()) = 'gerencia');

-- Sin policy de DELETE: los 7 motivos son fijos (espejo del CHECK de crm.leads).

-- Auditoría, mismo patrón que el resto del esquema crm.
create trigger trg_audit_enfriamiento_politica
  after insert or delete or update on crm.enfriamiento_politica
  for each row execute function private.log_audit_crm();

-- 2) RPC de verificación previa
create or replace function crm.verificar_disponibilidad_lead(
  p_telefono text,
  p_dni text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tel text;
  v_lead record;
  v_perfil record;
  v_dias integer;
  v_disponible_desde timestamptz;
begin
  v_tel := private.normalizar_telefono(p_telefono);

  if v_tel is null or length(v_tel) = 0 then
    return jsonb_build_object('estado', 'error', 'detalle', 'telefono_invalido');
  end if;

  -- a) no_contactar: terminal, sin datos adicionales
  if exists (
    select 1 from crm.leads l
    where l.no_contactar = true
      and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  ) then
    return jsonb_build_object('estado', 'no_contactar');
  end if;

  -- b) ya es cliente del portal
  -- perfiles.telefono NO está normalizado: normalizar ambos lados
  select per.id, asesor.nombre_completo as asesor_nombre
    into v_perfil
  from public.perfiles per
  left join public.perfiles asesor on asesor.id = per.asesor_perfil_id
  where per.rol = 'cliente'
    and per.activo = true
    and (
      private.normalizar_telefono(per.telefono) = v_tel
      or (p_dni is not null and per.dni = p_dni)
    )
  limit 1;

  if found then
    return jsonb_build_object(
      'estado', 'ya_es_cliente',
      'asesor', coalesce(v_perfil.asesor_nombre, 'sin asesor asignado')
    );
  end if;

  -- c) tomado: lead vivo en cartera de otro (o parkeado en supervisor)
  select l.tenencia_desde,
         coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
    into v_lead
  from crm.leads l
  left join public.perfiles pv on pv.id = l.vendedor_id
  left join public.perfiles ps on ps.id = l.asignado_supervisor_id
  where l.activo = true
    and l.etapa not in ('convertido','descartado')
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  limit 1;

  if found then
    return jsonb_build_object(
      'estado', 'tomado',
      'vendedor', v_lead.tenedor,
      'tenencia_desde', v_lead.tenencia_desde
    );
  end if;

  -- d) enfriamiento: último descarte aún dentro del plazo de su motivo
  select l.motivo_descarte, l.descartado_en,
         pd.nombre_completo as descartado_por_nombre
    into v_lead
  from crm.leads l
  left join public.perfiles pd on pd.id = l.descartado_por
  where l.etapa = 'descartado'
    and l.descartado_en is not null
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  order by l.descartado_en desc
  limit 1;

  if found then
    select ep.dias into v_dias
    from crm.enfriamiento_politica ep
    where ep.motivo = v_lead.motivo_descarte;

    v_dias := coalesce(v_dias, 0);
    v_disponible_desde := v_lead.descartado_en + make_interval(days => v_dias);

    if v_dias > 0 and v_disponible_desde > now() then
      return jsonb_build_object(
        'estado', 'enfriamiento',
        'motivo_descarte', v_lead.motivo_descarte,
        'disponible_desde', v_disponible_desde,
        'descartado_por', v_lead.descartado_por_nombre
      );
    end if;
  end if;

  -- e) libre
  return jsonb_build_object('estado', 'libre');
end;
$$;

comment on function crm.verificar_disponibilidad_lead(text, text) is
  'Consulta previa a crear un lead. Devuelve estado: no_contactar | ya_es_cliente | tomado | enfriamiento | libre. SECURITY DEFINER: expone solo nombre del tenedor y fechas, nunca datos de contacto ni montos de leads ajenos.';

revoke all on function crm.verificar_disponibilidad_lead(text, text) from public;
revoke all on function crm.verificar_disponibilidad_lead(text, text) from anon;
grant execute on function crm.verificar_disponibilidad_lead(text, text) to authenticated;
