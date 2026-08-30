-- MARCHA ATRAS de P-055 F7.1 (cerrar lo que quedo suelto).
-- Devuelve los EXECUTE originales (v1/v2 directo: postgres HEREDA del dueño
-- crm_metricas_bridge - medido 30/08, el grant restaura el literal al byte),
-- SACA de servicio las 7 filas de esta ola marcandolas 'liberada' (doctrina
-- del libro: jamas DELETE - candado bajado NOMBRADO, doctrina limpieza-leads)
-- y restaura el vigilante de la Ola 0 (sin service_role en el cierre).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- 0) PREFLIGHT anti-pisado: el mundo debe estar en el estado F7.1.
do $$
declare
  v_fn constant text[][] := array[
    array['crm.metricas_distribucion_leads_fn(date,date)',    '{crm_metricas_bridge=X/crm_metricas_bridge}'],
    array['crm.metricas_distribucion_leads_v2_fn(date,date)', '{crm_metricas_bridge=X/crm_metricas_bridge}'],
    array['crm.metricas_cartera_fn(date)',                    '{postgres=X/postgres}'],
    array['crm.metricas_altas_analista_fn(integer)',          '{postgres=X/postgres}'],
    array['crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)', '{postgres=X/postgres}'],
    array['crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)', '{postgres=X/postgres}'],
    array['public.actualizar_numero_contrato(uuid,text,text,text)', '{postgres=X/postgres}']
  ];
  v_fila text[];
begin
  foreach v_fila slice 1 in array v_fn loop
    if (select p.proacl::text from pg_proc p where p.oid = v_fila[1]::regprocedure)
       is distinct from v_fila[2] then
      raise exception 'rollback F7.1: % NO esta en el estado F7.1 (%) - regenerar el rollback', v_fila[1],
        (select p.proacl::text from pg_proc p where p.oid = v_fila[1]::regprocedure);
    end if;
  end loop;
  if (select count(*) from private.f7_piezas_en_observacion
       where ola = 'F7.1' and estado in ('observacion', 'cerrada_permanente')) <> 7 then
    raise exception 'rollback F7.1: el libro no tiene las 7 filas VIGENTES de la ola (¿doble rollback?)';
  end if;
  -- el vigilante debe ser el AMPLIADO de F7.1 (strpos, jamas LIKE):
  if (select strpos(p.prosrc, $srv$'authenticated', 'anon', 'service_role'$srv$)
        from pg_proc p
       where p.oid = 'private.assert_f7_piezas_cerradas()'::regprocedure) = 0 then
    raise exception 'rollback F7.1: el vigilante NO es el ampliado de F7.1 - regenerar el rollback';
  end if;
  -- postgres debe seguir HEREDANDO del dueño de v1/v2 para poder devolverlas:
  if not pg_has_role('postgres', 'crm_metricas_bridge', 'USAGE') then
    raise exception 'rollback F7.1: postgres no HEREDA de crm_metricas_bridge (el grant seria imposible)';
  end if;
end $$;

-- 1) Devolver los EXECUTE (v1/v2 directo: el grant corre COMO el dueño por
--    herencia; medido 30/08 - el ACL resultante es el original al byte).
grant execute on function crm.metricas_distribucion_leads_fn(date,date)    to authenticated;
grant execute on function crm.metricas_distribucion_leads_v2_fn(date,date) to authenticated;

grant execute on function crm.metricas_cartera_fn(date)                        to authenticated, service_role;
grant execute on function crm.metricas_altas_analista_fn(integer)              to authenticated;
grant execute on function crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)     to authenticated;
grant execute on function crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb) to authenticated;
grant execute on function public.actualizar_numero_contrato(uuid,text,text,text) to authenticated, service_role;

-- 2) Sacar de servicio las filas de ESTA ola: estado 'liberada' (la salida
--    doctrinal del libro - JAMAS delete), candado bajado NOMBRADO con rastro.
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion
   set estado = 'liberada',
       nota = coalesce(nota, '') || ' | liberada por rollback de F7.1 (puertas re-abiertas)'
 where ola = 'F7.1' and estado in ('observacion', 'cerrada_permanente');
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

-- 3) Restaurar el vigilante de la Ola 0 (cuerpo al byte de 20260831020000;
--    huella esperada e6f0070260e1fff2757201df8134167b).
create or replace function private.assert_f7_piezas_cerradas()
returns text
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  r record; v_h text; v_acl text; v_n integer; v_p text;
  v_excluidos oid[]; v_permitidos oid[];
  v_obs integer := 0; v_perm integer := 0; v_dem integer := 0; v_lib integer := 0;
begin
  if not exists (select 1 from private.f7_piezas_en_observacion) then
    raise exception 'F7: la tabla de observacion esta VACIA (fail-closed)';
  end if;

  -- El conjunto vigilado entero se excluye de todo censo: las gemelas se
  -- nombran entre si y todas estan congeladas por huella de todos modos.
  select coalesce(array_agg((to_regprocedure(o.firma))::oid), '{}'::oid[]) into v_excluidos
    from private.f7_piezas_en_observacion o
   where to_regprocedure(o.firma) is not null;

  for r in select * from private.f7_piezas_en_observacion order by firma loop
    if r.estado = 'liberada' then
      -- Llegar aqui SOLO es posible por una migracion que bajo el candado
      -- (la maquina de estados lo prohibe por UPDATE): la pieza volvio al
      -- servicio deliberadamente y deja de vigilarse.
      v_lib := v_lib + 1; continue;
    end if;

    if r.estado = 'demolida' then
      if to_regprocedure(r.firma) is not null then
        raise exception 'F7: % RENACIO despues de su demolicion', r.firma;
      end if;
      if r.drop_no_antes_de is not null and current_date < r.drop_no_antes_de then
        raise exception 'F7: % fue demolida ANTES de su ventana (no antes de %)', r.firma, r.drop_no_antes_de;
      end if;
      v_dem := v_dem + 1; continue;
    end if;

    -- observacion / cerrada_permanente: existe, congelada, cerrada.
    if to_regprocedure(r.firma) is null then
      raise exception 'F7: % desaparecio SIN pasar por la demolicion', r.firma;
    end if;
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = r.firma::regprocedure;
    if v_h is distinct from r.huella_md5 then
      raise exception 'F7: el cuerpo de % cambio estando cerrada (huella %)', r.firma, v_h;
    end if;
    select p.proacl::text into v_acl from pg_proc p where p.oid = r.firma::regprocedure;
    if v_acl is distinct from r.acl_esperada then
      raise exception 'F7: % SE REABRIO (ACL %, se esperaba %)', r.firma, v_acl, r.acl_esperada;
    end if;

    v_permitidos := '{}'::oid[];
    foreach v_p in array r.llamadores_permitidos loop
      if to_regprocedure(v_p) is null then
        raise exception 'F7: el llamador permitido % de % ya no resuelve', v_p, r.firma;
      end if;
      v_permitidos := v_permitidos || (to_regprocedure(v_p))::oid;
    end loop;

    -- Codex P0-1: el cuerpo de una funcion SQL-standard vive en prosqlbody
    -- (prosrc queda vacio) — se censan AMBOS textos.
    select count(*) into v_n
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname not in ('pg_catalog', 'information_schema')
       and p.oid <> all (v_excluidos || v_permitidos)
       and lower(replace(
             regexp_replace(regexp_replace(
               coalesce(p.prosrc, '') || ' ' || coalesce(pg_get_function_sqlbody(p.oid), ''),
               '--[^\n]*', ' ', 'g'),
               '/\*.*?\*/', ' ', 'g'), '"', '')) ~ r.patron_censo;
    if v_n <> 0 then
      raise exception 'F7: % funciones NUEVAS nombran a % — alguien empezo a usarla', v_n, r.firma;
    end if;

    -- Codex P0-1: las VISTAS y REGLAS tambien pueden llamarla — se censan.
    select count(*) into v_n
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname not in ('pg_catalog', 'information_schema')
       and c.relkind in ('v', 'm')
       and lower(replace(pg_get_viewdef(c.oid), '"', '')) ~ r.patron_censo;
    if v_n <> 0 then
      raise exception 'F7: % VISTAS nombran a % — alguien la cableo por una vista', v_n, r.firma;
    end if;

    -- Auditoria F7.0 (P1): el parser resuelve MAYUSCULAS y comillas — el censo
    -- tambien: todo texto se normaliza con lower() y sin comillas dobles.
    select (select count(*) from pg_policy pol
             where lower(replace(coalesce(pg_get_expr(pol.polqual, pol.polrelid), ''), '"', '')) ~ r.patron_censo
                or lower(replace(coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), ''), '"', '')) ~ r.patron_censo)
         + (select count(*) from pg_attrdef ad
             where lower(replace(pg_get_expr(ad.adbin, ad.adrelid), '"', '')) ~ r.patron_censo)
         + (select count(*) from pg_constraint c
             where c.contype = 'c' and lower(replace(pg_get_constraintdef(c.oid), '"', '')) ~ r.patron_censo)
         + (select count(*) from cron.job j where lower(replace(j.command, '"', '')) ~ r.patron_censo)
      into v_n;
    if v_n <> 0 then
      raise exception 'F7: % aparece en % superficies (policies/defaults/checks/cron)', r.firma, v_n;
    end if;

    if r.estado = 'observacion' then v_obs := v_obs + 1; else v_perm := v_perm + 1; end if;
  end loop;

  -- Codex P0-4: un GRANT de MEMBRESIA (rol puente hacia postgres) transmite
  -- los privilegios del owner SIN tocar proacl. Cierre transversal: ni
  -- authenticated ni anon pueden alcanzar a postgres por la cadena de roles.
  if exists (
    with recursive alcance as (
      select pr.oid from pg_roles pr where pr.rolname in ('authenticated', 'anon')
      union
      select m.roleid from pg_auth_members m join alcance al on al.oid = m.member
    )
    select 1 from alcance al2 join pg_roles pr2 on pr2.oid = al2.oid where pr2.rolname = 'postgres'
  ) then
    raise exception 'F7: authenticated/anon ALCANZAN a postgres por membresia de roles — puerta trasera de herencia';
  end if;

  return format('OK: %s piezas vigiladas (observacion %s, permanentes %s, demolidas %s, liberadas %s)',
                v_obs + v_perm + v_dem + v_lib, v_obs, v_perm, v_dem, v_lib);
end;
$function$;

-- 4) POSTFLIGHT: ACL originales al literal, libro liberado, vigilante de la
--    Ola 0 de vuelta, candados re-armados.
do $$
declare
  v_fn constant text[][] := array[
    array['crm.metricas_distribucion_leads_fn(date,date)',    '{crm_metricas_bridge=X/crm_metricas_bridge,authenticated=X/crm_metricas_bridge}'],
    array['crm.metricas_distribucion_leads_v2_fn(date,date)', '{crm_metricas_bridge=X/crm_metricas_bridge,authenticated=X/crm_metricas_bridge}'],
    array['crm.metricas_cartera_fn(date)',                    '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'],
    array['crm.metricas_altas_analista_fn(integer)',          '{postgres=X/postgres,authenticated=X/postgres}'],
    array['crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)', '{postgres=X/postgres,authenticated=X/postgres}'],
    array['crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)', '{postgres=X/postgres,authenticated=X/postgres}'],
    array['public.actualizar_numero_contrato(uuid,text,text,text)', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}']
  ];
  v_fila text[]; v_h text; v_txt text;
begin
  foreach v_fila slice 1 in array v_fn loop
    if (select p.proacl::text from pg_proc p where p.oid = v_fila[1]::regprocedure)
       is distinct from v_fila[2] then
      raise exception 'rollback F7.1: % no volvio al ACL original (%)', v_fila[1],
        (select p.proacl::text from pg_proc p where p.oid = v_fila[1]::regprocedure);
    end if;
  end loop;
  if (select count(*) from private.f7_piezas_en_observacion
       where ola = 'F7.1' and estado = 'liberada') <> 7 then
    raise exception 'rollback F7.1: las 7 filas de la ola no quedaron liberadas';
  end if;
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.assert_f7_piezas_cerradas()'::regprocedure;
  if v_h is distinct from 'e6f0070260e1fff2757201df8134167b' then
    raise exception 'rollback F7.1: el vigilante NO volvio al cuerpo de la Ola 0 (huella %)', v_h;
  end if;
  -- el vigilante restaurado sigue dando OK (las liberadas se saltan; las
  -- gemelas de F5.d siguen vigiladas):
  v_txt := private.assert_f7_piezas_cerradas();
  if v_txt not like 'OK:%' then
    raise exception 'rollback F7.1: el vigilante restaurado no da OK (%)', v_txt;
  end if;
  if not exists (select 1 from pg_trigger t
    where t.tgrelid = 'private.f7_piezas_en_observacion'::regclass
      and t.tgname = 'trg_f7_obs_00_solo_crece' and t.tgenabled in ('O','A')) then
    raise exception 'rollback F7.1: el candado solo-crece quedo APAGADO';
  end if;
  if not exists (select 1 from pg_trigger t
    where t.tgrelid = 'private.f7_piezas_en_observacion'::regclass
      and t.tgname = 'trg_f7_obs_01_no_borrar' and t.tgenabled in ('O','A')) then
    raise exception 'rollback F7.1: el candado anti-borrar quedo APAGADO';
  end if;
  if exists (select 1 from pg_auth_members m
              where m.roleid = 'crm_metricas_bridge'::regrole
                and m.member = 'postgres'::regrole and m.set_option) then
    raise exception 'rollback F7.1: la membresia del rol puente gano la opcion SET (nadie debio tocarla)';
  end if;
  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
