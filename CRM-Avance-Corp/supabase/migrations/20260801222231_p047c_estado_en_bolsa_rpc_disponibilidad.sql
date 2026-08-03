-- P-047c · Distingue lead vivo SIN dueño (en_bolsa) de lead vivo CON dueño (tomado).
-- Restaurada desde supabase_migrations.schema_migrations de producción.
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

  -- b) ya es cliente del portal (perfiles.telefono no está normalizado: normalizar ambos lados)
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

  -- c) lead vivo: tomado (con dueño) o en_bolsa (sin dueño)
  select l.tenencia_desde, l.vendedor_id, l.asignado_supervisor_id,
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
    if v_lead.vendedor_id is null and v_lead.asignado_supervisor_id is null then
      return jsonb_build_object('estado', 'en_bolsa');
    end if;
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
  'Consulta previa a crear un lead. Estados: no_contactar | ya_es_cliente | tomado | en_bolsa | enfriamiento | libre. SECURITY DEFINER: expone solo nombre del tenedor y fechas, nunca datos de contacto ni montos de leads ajenos.';
