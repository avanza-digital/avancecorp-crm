-- PLANTILLA: renderizar UUID verificados con crear-sql.mjs y revisar el SQL.
-- Primera activación; ejecutar solo después de aprobar equipo y vigencia.
-- actualizado_por identifica al responsable operativo de Gerencia.
-- La sesión administrativa conserva auth.uid() NULL; no simula su firma.
begin isolation level read committed;
set local search_path='';
set local lock_timeout='5s';
set local statement_timeout='30s';
do $activar_f8$
declare
  v_config constant jsonb := '__CONFIG_JSON__'::jsonb;
  v_equipo constant jsonb := v_config->'equipo';
  v_ids uuid[];
  v_responsable uuid := (v_config->>'responsable_id')::uuid;
  v_referencia text := v_config->>'referencia';
  v_motivo text;
  v_inicio timestamptz := statement_timestamp();
  v_vence timestamptz := v_inicio+interval '7 days';
  v_n integer;
begin
  if current_user<>'postgres' or auth.uid() is not null then
    raise exception 'Requiere ejecución administrativa sin suplantar una sesión';
  end if;
  if v_referencia is null or v_referencia !~ '^[A-Z0-9_-]{4,60}$'
    or not exists(select 1 from public.perfiles p join crm.equipo e on e.perfil_id=p.id
      where p.id=v_responsable and p.activo and e.activo and e.rol_crm='gerencia') then
    raise exception 'Falta responsable operativo vigente o referencia de autorización';
  end if;
  v_motivo := 'Piloto F8 ref:'||v_referencia||'; responsable operativo declarado; ejecución administrativa Codex';
  -- Fallar rápido fuera de la llave F8; el trigger repite cobertura bajo ella.
  if exists(select 1 from private.cartera_f5_fuentes_reales() f
    left join crm.inversionistas i on i.id=f.inversionista_id
    where not coalesce(f.identidad_coherente,false) or i.id is null
      or i.inversionista_canonico_id is not null) then
    raise exception 'La cobertura real cambió; conciliar antes de activar';
  end if;
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'El piloto requiere F3 ON y F4-F7 globales OFF';
  end if;
  perform pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'));
  if (select count(*) from crm.piloto_f8_control)<>1
    or not exists(select 1 from crm.piloto_f8_control where singleton
      and not activo and revision=0 and inicia_en is null and vence_en is null)
    or exists(select 1 from crm.piloto_f8_miembros) then
    raise exception 'F8 cambió o ya tuvo participantes; revisar antes de configurar';
  end if;

  select array_agg(x.perfil_id) into v_ids
  from jsonb_to_recordset(v_equipo) x(perfil_id uuid,rol_esperado text,supervisor_id uuid);
  if cardinality(v_ids)<>4 or (select count(distinct x) from unnest(v_ids) x)<>4
    or (select count(*) from jsonb_to_recordset(v_equipo) x(rol_esperado text)
      where x.rol_esperado='gerencia')<>1
    or (select count(*) from jsonb_to_recordset(v_equipo) x(rol_esperado text)
      where x.rol_esperado='supervisor')<>1
    or (select count(*) from jsonb_to_recordset(v_equipo) x(rol_esperado text)
      where x.rol_esperado='vendedor')<>2 then
    raise exception 'Se requiere Gerencia, un supervisor y dos analistas distintos';
  end if;

  select count(*) into v_n
  from jsonb_to_recordset(v_equipo) x(perfil_id uuid,rol_esperado text,supervisor_id uuid)
  join public.perfiles p on p.id=x.perfil_id and p.activo
  join crm.equipo e on e.perfil_id=x.perfil_id and e.activo and e.rol_crm=x.rol_esperado
    and e.supervisor_id is not distinct from x.supervisor_id
  join auth.users u on u.id=x.perfil_id and u.deleted_at is null
    and u.email_confirmed_at is not null
    and (u.banned_until is null or u.banned_until<=statement_timestamp())
  where exists(select 1 from auth.identities i where i.user_id=x.perfil_id and i.provider='email');
  if v_n<>4 then
    raise exception 'Cambió una cuenta, su rol, su acceso o su supervisor; revisar la selección';
  end if;

  -- Evitar bloqueos explícitos de filas ajenas bajo F8: sus writers pueden invertir el orden.
  -- Los INSERT conservan los KEY SHARE implícitos de sus claves foráneas.
  if (select count(*) from crm.multiempresa_flags where nombre in ('resolver_en_puertas',
      'inversiones_escritura','ficha_360_neutral','postventa_neutral','metricas_multiempresa_sombra'))<>5
    or not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'),false)
    or exists(select 1 from crm.multiempresa_flags where nombre in ('inversiones_escritura',
      'ficha_360_neutral','postventa_neutral','metricas_multiempresa_sombra') and activo) then
    raise exception 'El piloto requiere F3 ON y F4-F7 globales OFF';
  end if;

  insert into crm.piloto_f8_miembros
    (perfil_id,rol_esperado,activo,habilitado_desde,vence_en,motivo,actualizado_por)
  select x.perfil_id,x.rol_esperado,true,v_inicio,v_vence,
    v_motivo,v_responsable
  from jsonb_to_recordset(v_equipo) x(perfil_id uuid,rol_esperado text);
  update crm.piloto_f8_control set activo=true,inicia_en=v_inicio,vence_en=v_vence,
    motivo=v_motivo,
    actualizado_por=v_responsable where singleton;
  if not private.piloto_f8_modo_activo()
    or (select count(*) from crm.piloto_f8_miembros)<>4
    or (select count(*) from unnest(v_ids) x where private.piloto_f8_actor_activo(x))<>4
    or array(select perfil_id from crm.piloto_f8_miembros order by perfil_id)
      is distinct from array(select x from unnest(v_ids) x order by x) then
    raise exception 'El alcance final no coincide con los cuatro participantes';
  end if;
end;
$activar_f8$;
select activo,revision,inicia_en,vence_en,
  (select count(*) from crm.piloto_f8_miembros where activo) as participantes
from crm.piloto_f8_control where singleton;
commit;
