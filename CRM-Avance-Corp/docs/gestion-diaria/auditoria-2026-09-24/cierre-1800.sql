-- Auditoría productiva de solo lectura: ejecutar después de las 18:00 Lima.
-- Usa las RPC vigentes y el reloj real. No registra entregas ni decisiones.
begin transaction isolation level read committed read only;
set local statement_timeout = '90s';
set local lock_timeout = '5s';
set local timezone = 'America/Lima';
do $auditoria$
declare
  r record;
  v jsonb;
  alertas jsonb;
  resultado jsonb := '[]';
  indice integer := 0;
begin
  if (clock_timestamp() at time zone 'America/Lima')::date <> date '2026-09-24'
     or (clock_timestamp() at time zone 'America/Lima')::time < time '18:00' then
    raise exception 'Esta auditoría exige el cierre real del 24/09 después de las 18:00 Lima';
  end if;
  for r in select e.perfil_id from crm.equipo e
    where private.rol_crm(e.perfil_id) = 'supervisor' order by e.perfil_id
  loop
    indice := indice + 1;
    perform set_config('request.jwt.claim.sub', r.perfil_id::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', jsonb_build_object('sub',r.perfil_id,'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v := crm.gestion_diaria_avisos_fn();
    execute 'reset role';
    if (v->>'dia') <> '2026-09-24' then raise exception 'Día inesperado'; end if;
    if exists(select 1 from jsonb_array_elements(v->'alertas') a
      where coalesce((a->>'puede_presentar')::boolean,false)
         or coalesce((a->>'puede_posponer')::boolean,false)) then
      raise exception 'El cierre permite presentar o posponer un aviso';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'tipo',a->'tipo','miembros',jsonb_array_length(a->'miembros'),
      'estado',a->'estado','puede_presentar',a->'puede_presentar',
      'puede_posponer',a->'puede_posponer','entrega',a->'entrega',
      'fin_jornada',a->'fin_jornada'
    ) order by a->>'tipo'),'[]') into alertas from jsonb_array_elements(v->'alertas') a;
    resultado := resultado || jsonb_build_array(jsonb_build_object(
      'caso',indice,'dia',v->'dia','generado_en',v->'generado_en',
      'estado_cortes',v->'estado_cortes','avisos_habilitados',v->'avisos_habilitados',
      'alertas',alertas,
      'entregas_hoy',(select count(*) from crm.gestion_diaria_entregas d
        where d.perfil_id=r.perfil_id and d.alerta_id like '%:2026-09-24'),
      'reconocimientos_hoy',(select count(*) from crm.alertas_reconocimientos a
        where a.perfil_id=r.perfil_id and a.alerta_id like '%:2026-09-24' and a.accion='reconocer'),
      'aplazamientos_hoy',(select count(*) from crm.alertas_reconocimientos a
        where a.perfil_id=r.perfil_id and a.alerta_id like '%:2026-09-24' and a.accion='posponer')
    ));
  end loop;
  if indice = 0 then raise exception 'No se encontraron supervisores efectivos'; end if;
  perform set_config('app.auditoria_cierre',resultado::text,true);
end $auditoria$;
select jsonb_build_object(
  'estado','PASS','fecha',clock_timestamp(),'zona','America/Lima',
  'solo_lectura',current_setting('transaction_read_only'),
  'supervisores',current_setting('app.auditoria_cierre')::jsonb,
  'f5_instalada',to_regprocedure('crm.gestion_diaria_pulso_fn(date)') is not null,
  'limite','Auditoría de RPC bajo rol authenticated con contexto de cada supervisor; no es una nueva sesión humana ni una observación de popup.'
) as evidencia;
rollback;
