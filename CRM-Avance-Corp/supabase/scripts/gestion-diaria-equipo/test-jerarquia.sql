-- Sólo el banco exclusivo. Todo fixture, incluso el ciclo, termina en ROLLBACK.
begin;
set local statement_timeout = '60s';
do $$ begin
  if current_database() <> 'gestion_diaria_f4_vista_chvrqh' then
    raise exception 'Oráculo permitido sólo en la copia F4';
  end if;
end $$;
create temporary table f4_jerarquia as
with vendedores as (
  select e.perfil_id, e.supervisor_id from crm.equipo e
  where private.rol_crm(e.perfil_id) = 'vendedor'
    and private.rol_crm(e.supervisor_id) = 'supervisor'
  order by e.perfil_id
)
select (select perfil_id from vendedores limit 1) vendedor,
  (select supervisor_id from vendedores limit 1) supervisor,
  (select perfil_id from vendedores where supervisor_id <> (select supervisor_id from vendedores limit 1) limit 1) ajeno,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id) = 'coordinador' limit 1) puente,
  (select perfil_id from crm.equipo where private.rol_crm(perfil_id) = 'gerencia' limit 1) gerencia,
  (select p.id from public.perfiles p where p.activo and p.rol = 'directorio'
    and (not exists (select 1 from crm.equipo e where e.perfil_id = p.id)
      or private.rol_crm(p.id) = 'directorio') limit 1) lector;
create temporary table f4_ambitos(actor text primary key, sla jsonb, equipo jsonb);
grant select on f4_jerarquia to authenticated;
grant all on f4_ambitos to authenticated;
create function pg_temp.afirmar(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'F4: %', mensaje; end if; end $$;
select pg_temp.afirmar(vendedor is not null and supervisor is not null and ajeno is not null
  and puente is not null and gerencia is not null and lector is not null, 'Faltan actores del banco') from f4_jerarquia;

-- Simula un puente revocado e incluso una jerarquía cíclica accidental. El
-- núcleo de visibilidad canónico los atraviesa sin perder descendientes.
alter table crm.equipo disable trigger user;
update crm.equipo set supervisor_id = (select supervisor from f4_jerarquia), activo = false
  where perfil_id = (select puente from f4_jerarquia);
update crm.equipo set supervisor_id = (select puente from f4_jerarquia)
  where perfil_id = (select vendedor from f4_jerarquia);
update crm.equipo set supervisor_id = (select vendedor from f4_jerarquia)
  where perfil_id = (select supervisor from f4_jerarquia);
alter table crm.equipo enable trigger user;

select set_config('request.jwt.claim.sub', supervisor::text, true) from f4_jerarquia;
-- El núcleo SLA no se concede a authenticated: capturar su oráculo con la
-- misma identidad, luego consultar la nueva puerta con el rol real.
insert into f4_ambitos values ('supervisor', private.sla_operacion_autorizada(null, true), null);
set local role authenticated;
update f4_ambitos set equipo = crm.gestion_diaria_equipo_fn() where actor = 'supervisor';
select pg_temp.afirmar(exists (select 1 from jsonb_array_elements(a.equipo->'equipo') e
  where e->>'analista_id' = j.vendedor::text), 'Desapareció un analista activo bajo puente inactivo')
  from f4_ambitos a, f4_jerarquia j where a.actor = 'supervisor';
select pg_temp.afirmar(not exists (select 1 from jsonb_array_elements(a.equipo->'equipo') e
  where e->>'analista_id' in (j.ajeno::text, j.puente::text)), 'Mostró ajeno o miembro inactivo')
  from f4_ambitos a, f4_jerarquia j where a.actor = 'supervisor';
select pg_temp.afirmar(jsonb_array_length(a.equipo->'equipo') =
  (select cardinality(array_agg(e.perfil_id)) from crm.equipo_visible_fn() e
    where e.activo and e.rol_crm = 'vendedor'), 'Roster difiere del ámbito canónico')
  from f4_ambitos a where a.actor = 'supervisor';
reset role;

select set_config('request.jwt.claim.sub', gerencia::text, true) from f4_jerarquia;
insert into f4_ambitos values ('gerencia', private.sla_operacion_autorizada(null, true), null);
set local role authenticated;
update f4_ambitos set equipo = crm.gestion_diaria_equipo_fn(null, (select supervisor from f4_jerarquia)) where actor = 'gerencia';
select pg_temp.afirmar((a.equipo->'equipo') = (select equipo->'equipo' from f4_ambitos where actor='supervisor'),
  'Gerencia seleccionada pierde el puente o amplía el ámbito') from f4_ambitos a where actor='gerencia';
reset role;

select set_config('request.jwt.claim.sub', lector::text, true) from f4_jerarquia;
insert into f4_ambitos values ('global', private.sla_operacion_autorizada(null, true), null);
set local role authenticated;
select pg_temp.afirmar(private.es_lector_global(), 'El actor no es lector global');
update f4_ambitos set equipo = crm.gestion_diaria_equipo_fn() where actor = 'global';
select pg_temp.afirmar(jsonb_array_length(a.equipo->'equipo') =
  (select cardinality(array_agg(e.perfil_id)) from crm.equipo_visible_fn() e
    where e.activo and e.rol_crm = 'vendedor'), 'Lector global incompleto')
  from f4_ambitos a where a.actor = 'global';
select pg_temp.afirmar(crm.gestion_diaria_equipo_fn(null, j.supervisor)->'equipo'
  = (select equipo->'equipo' from f4_ambitos where actor='supervisor'), 'Lector global en equipo elegido') from f4_jerarquia j;

-- Ausencia en el agregado SLA significa cero SÓLO porque la consulta de
-- origen es completa y corresponde al mismo ámbito autorizado. No caché.
do $$ declare a record; e jsonb; primero integer; incompleto integer; begin
  for a in select * from f4_ambitos loop
    for e in select value from jsonb_array_elements(a.equipo->'equipo') loop
      if a.sla->>'modo' = 'activo' then
        select count(*) filter (where (f#>>'{senales,primera_atencion}')::boolean),
          count(*) filter (where (f#>>'{senales,datos_incompletos}')::boolean)
          into primero, incompleto from jsonb_array_elements(a.sla->'filas') f
          where f#>>'{lead,analista_id}' = e->>'analista_id';
        perform pg_temp.afirmar((e->>'primer_intento_vencido')::integer = primero
          and (e->>'datos_incompletos')::integer = incompleto, 'Agregado SLA distinto del canónico: ' || a.actor);
      else
        perform pg_temp.afirmar(e->>'primer_intento_vencido' is null and e->>'datos_incompletos' is null,
          'SLA no evaluado convertido en cero');
      end if;
    end loop;
  end loop;
end $$;
-- Límite inclusivo de 365 días y rechazo inmediatamente fuera.
select pg_temp.afirmar(crm.gestion_diaria_equipo_fn((now() at time zone 'America/Lima')::date - 365)->>'dia'
  = ((now() at time zone 'America/Lima')::date - 365)::text, 'Rechazó límite de 365 días');
do $$ begin
  perform crm.gestion_diaria_equipo_fn((now() at time zone 'America/Lima')::date - 366);
  raise exception 'F4: aceptó 366 días';
exception when invalid_parameter_value then null; end $$;
reset role;
select 'GESTION_DIARIA_JERARQUIA_OK';
rollback;
