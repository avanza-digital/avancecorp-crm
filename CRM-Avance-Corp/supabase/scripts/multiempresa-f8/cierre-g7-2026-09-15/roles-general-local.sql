-- Solo banco local g7_cierre_20260915: matriz del modo general, todo ROLLBACK.
begin isolation level read committed;
set local statement_timeout='40s'; set local lock_timeout='2s'; set local search_path='';
do $destino$ begin
  if current_database()<>'g7_cierre_20260915' then raise exception 'Destino local cerrado'; end if;
end; $destino$;
update crm.piloto_f8_control set activo=false where singleton;
update crm.multiempresa_flags set activo=(nombre<>'metricas_multiempresa_sombra');
-- Se agregan contextos ausentes en la copia. FK, triggers y RLS se conservan.
-- Sin contraseñas ni sesiones Auth; estas filas también terminan en ROLLBACK.
create temporary table contextos_g7(id uuid default gen_random_uuid(),caso text,
  rol_portal text,rol_crm text,perfil_activo boolean,equipo_activo boolean);
insert into contextos_g7(caso,rol_portal,rol_crm,perfil_activo,equipo_activo) values
  ('coordinador','analista','coordinador',true,true),
  ('perfil_inactivo','analista','vendedor',false,true),
  ('equipo_inactivo','analista','vendedor',true,false),
  ('directorio_sin_equipo','directorio',null,true,null),
  ('directorio_sin_equipo_inactivo','directorio',null,false,null),
  ('directorio_equipo_inactivo','directorio','directorio',true,false);
insert into auth.users(id,aud,role,email,email_confirmed_at)
  select id,'authenticated','authenticated',id::text||'@g7.example.invalid',now()
  from contextos_g7;
insert into public.perfiles(id,nombre_completo,rol,activo)
  select id,'CONTEXTO SINTETICO G7 '||caso,rol_portal,true from contextos_g7;
insert into crm.equipo(perfil_id,rol_crm,activo,supervisor_id)
  select id,rol_crm,equipo_activo,case when rol_crm='vendedor' then
    (select perfil_id from crm.equipo where rol_crm='supervisor' and activo order by perfil_id limit 1)
    end from contextos_g7 where rol_crm is not null;
update public.perfiles p set activo=false from contextos_g7 c
  where p.id=c.id and not c.perfil_activo;
do $roles$
declare a record; f5 jsonb; f6 jsonb; err5 text; err6 text; err_lista text;
  resultado jsonb:='[]'; lectura boolean; escritura boolean;
  objetivo uuid; fuera jsonb; ficha jsonb; lista jsonb;
  permitidos uuid[]; vistos uuid[]; pagina integer; fila jsonb; fichas_directorio integer;
begin
  -- Directorio también puede consultar perfiles del Portal sin contratos.
  -- La pertenencia a COOPAC por sí sola no habilita identidad ni datos.
  select array_agg(distinct private.inversionista_canonica(i.id)) into permitidos
    from crm.inversionistas i join public.perfiles p on p.id=i.perfil_id where p.rol='cliente';
  for a in select p.id,p.rol,p.activo perfil_activo,e.rol_crm,e.activo equipo_activo,
    e.perfil_id is not null tiene_equipo,coalesce(c.caso,'cuenta_de_base') caso
    from public.perfiles p left join crm.equipo e on e.perfil_id=p.id
    left join contextos_g7 c on c.id=p.id
    order by p.id
  loop
    lectura:=a.perfil_activo and ((coalesce(a.equipo_activo,false)
      and a.rol_crm in('gerencia','supervisor','vendedor','directorio'))
      or (not a.tiene_equipo and a.rol='directorio'));
    lectura:=coalesce(lectura,false);
    escritura:=lectura and coalesce(a.rol_crm in('gerencia','supervisor','vendedor'),false);
    objetivo:=null;
    if escritura and a.rol_crm='vendedor' then
      select f.inversionista_id into objetivo from private.cartera_f5_fuentes_reales() f
      join crm.inversionistas i on i.id=f.inversionista_id
      where i.responsable_relacion_id is not null and i.responsable_relacion_id<>a.id
      order by f.fuente_id limit 1;
    elsif escritura and a.rol_crm='supervisor' then
      select f.inversionista_id into objetivo from private.cartera_f5_fuentes_reales() f
      join crm.inversionistas i on i.id=f.inversionista_id
      join crm.equipo e on e.perfil_id=i.responsable_relacion_id
      where e.supervisor_id is not null and e.supervisor_id<>a.id
      order by f.fuente_id limit 1;
    end if;
    f5:=null;f6:=null;err5:=null;err6:=null;err_lista:=null;lista:=null;fuera:=null;ficha:=null;
    vistos:='{}';pagina:=1;fichas_directorio:=0;
    perform set_config('request.jwt.claim.sub',a.id::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a.id,'role','authenticated')::text,true);
    set local role authenticated;
    begin f5:=crm.cartera_inversionistas_estado_fn(); exception when others then err5:=sqlstate; end;
    begin f6:=crm.postventa_estado_fn(); exception when others then err6:=sqlstate; end;
    if lectura then
      lista:=crm.cartera_inversionistas_fn();
      if objetivo is not null then fuera:=crm.inversionista_ficha_fn(objetivo,1,1); end if;
      if not escritura then
        loop
          if exists(select 1 from jsonb_array_elements(lista->'totales') t where t->>'empresa' is distinct from 'avance') then
            raise exception 'Directorio recibió totales de otra empresa';
          end if;
          for fila in select value from jsonb_array_elements(lista->'filas') loop
            if ((fila->>'inversionista_id')::uuid=any(permitidos)) is not true
              or (fila->>'inversionista_id')::uuid=any(vistos) then
              raise exception 'Directorio recibió persona sin perfil Portal o duplicada';
            end if;
            if exists(select 1 from jsonb_array_elements_text(fila->'empresas') e where e is distinct from 'avance') then
              raise exception 'Directorio recibió empresa ajena en la lista';
            end if;
            vistos:=array_append(vistos,(fila->>'inversionista_id')::uuid);
            ficha:=crm.inversionista_ficha_fn((fila->>'inversionista_id')::uuid,1,1);
            if ficha is null
              or exists(select 1 from jsonb_array_elements(ficha->'inversiones') f where f->>'empresa' is distinct from 'avance')
              or (ficha#>>'{capacidades,nueva_inversion}')::boolean is distinct from false then
              raise exception 'Directorio recibió ficha nula, inversión ajena a Avance o capacidad de escritura';
            end if;
            fichas_directorio:=fichas_directorio+1;
          end loop;
          exit when cardinality(vistos)>=(lista->>'total')::integer;
          if jsonb_array_length(lista->'filas')=0 or pagina>=100 then
            raise exception 'Paginación de Directorio incompleta';
          end if;
          pagina:=pagina+1;lista:=crm.cartera_inversionistas_fn(p_pagina=>pagina);
        end loop;
        if cardinality(vistos) is distinct from (lista->>'total')::integer then
          raise exception 'Directorio no cubrió todas sus páginas';
        end if;
      end if;
    else
      begin lista:=crm.cartera_inversionistas_fn(); exception when others then err_lista:=sqlstate; end;
      if err_lista is distinct from '42501' then raise exception 'Lista accesible al contexto excluido: %',a.caso; end if;
    end if;
    reset role;
    if lectura then
      if err5 is not null or (f5->>'habilitada')::boolean is distinct from true
        or (f5->>'escritura_habilitada')::boolean is distinct from escritura then
        raise exception 'Capacidad F5 inesperada: %, %, %',a.rol_crm,err5,f5;
      end if;
      if (lista->>'total')::integer<1 then raise exception 'Cartera vacía del rol autorizado'; end if;
    elsif err5 is distinct from '42501' and coalesce((f5->>'habilitada')::boolean,false) then
      raise exception 'F5 amplió permisos';
    end if;
    if err5 is not null and err5<>'42501' then raise exception 'Error F5 inesperado: %',err5; end if;
    if escritura then
      if err6 is not null or (f6->>'habilitada')::boolean is distinct from true then raise exception 'F6 no disponible al gestor'; end if;
    elsif err6 is distinct from '42501' and coalesce((f6->>'habilitada')::boolean,false) then raise exception 'F6 amplió permisos';
    end if;
    if err6 is not null and err6<>'42501' then raise exception 'Error F6 inesperado: %',err6; end if;
    if fuera is not null then raise exception 'Fichas fuera de ámbito visibles'; end if;
    resultado:=resultado||jsonb_build_array(jsonb_build_object('caso',a.caso,'rol_crm',a.rol_crm,'rol_perfil',a.rol,
      'perfil_activo',a.perfil_activo,'equipo_activo',a.equipo_activo,'fallback_sin_equipo',not a.tiene_equipo,
      'lectura_esperada',lectura,'escritura_esperada',escritura,'f5',f5,'f6',f6,
      'error_f5',err5,'error_f6',err6,'error_lista',err_lista,'fuera_de_ambito_probado',objetivo is not null,
      'cartera_total',lista->'total','directorio_ficha_avance_probada',ficha is not null,
      'directorio_fichas_comprobadas',fichas_directorio,'directorio_paginas',case when not escritura and lectura then pagina end));
  end loop;
  -- Las pruebas HTTP incorporan clientes nuevos al banco. Todos deben quedar
  -- excluidos de la gestión CRM; no limitar la matriz a las 15 cuentas iniciales.
  if jsonb_array_length(resultado)<>(select count(*) from public.perfiles)
    or jsonb_array_length(resultado)<21 then
    raise exception 'Matriz incompleta: %',jsonb_array_length(resultado);
  end if;
  perform set_config('g7.roles_general',resultado::text,true);
end; $roles$;
select jsonb_build_object('estado','PASS','banco',current_database(),'corte',statement_timestamp(),
  'modo','F8 OFF, F3/F4/F5/F6 ON, F7 OFF; cambios dentro de ROLLBACK',
  'contextos_esperados',(select count(*) from public.perfiles),
  'roles',current_setting('g7.roles_general')::jsonb) evidencia;
rollback;
