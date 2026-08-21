-- Corrige una regresion del puente de Analistas Portal: con
-- standard_conforming_strings activo, `\\.` llegaba al motor de expresiones
-- regulares como un escape doble y rechazaba correos validos. La clase `[.]`
-- representa el punto literal sin depender del tratamiento de backslashes.

create or replace function crm.buscar_candidato_por_correo_fn(p_correo text)
returns uuid
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_correo text := lower(pg_catalog.btrim(coalesce(p_correo, '')));
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede preparar altas CRM';
  end if;

  if v_correo !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
    raise exception 'Correo invalido';
  end if;

  select p.id into v_id
  from public.perfiles p
  left join crm.equipo e on e.perfil_id = p.id
  where lower(p.correo) = v_correo
    and (p.rol in ('comercial', 'analista') or e.perfil_id is not null)
  limit 1;

  return v_id;
end;
$$;

comment on function crm.buscar_candidato_por_correo_fn(text) is
  'Busca por correo un candidato CRM existente. Solo Gerencia activa; admite perfiles comerciales, Analistas Portal o miembros CRM.';
