-- P-055 F7.0 - EL GATE QUE VIGILA LAS PUERTAS CERRADAS (Fase 7, Ola 0).
--
-- La Fase 7 «ordenar la casa» derriba por el metodo CERRAR -> OBSERVAR (14 dias,
-- decision de Miguel 31/08) -> DERRIBAR, con OK por pieza. Esta ola no cierra ni
-- derriba NADA: instala el aparato de observacion.
--
--  1) private.f7_piezas_en_observacion — la LISTA que el vigia lee a diario, el
--     CANDADO temporal del drop (drop_no_antes_de vive en el servidor) y el
--     registro historico de la fase. Con trinquete propio: fechas que solo
--     crecen, huella/cierre inmutables, ni DELETE ni TRUNCATE (la salida es el
--     estado 'liberada'). ⚠️ Limitacion declarada (la misma de F6.a): el assert
--     NO vigila que esos triggers sigan activos.
--  2) private.assert_f7_piezas_cerradas() — por cada pieza vigilada: sigue
--     existiendo · su cuerpo no cambio (md5) · su ACL sigue siendo el literal
--     esperado · NADIE nuevo la nombra (censo por OID, normalizado sin
--     comentarios, excluyendo el propio conjunto vigilado y los llamadores
--     permitidos) · las 4 superficies que prosrc no ve (policies, defaults,
--     CHECKs, cron) siguen en 0. Las 'demolida' NO renacen. Tabla vacia = rojo.
--  3) private.vigia_f7_piezas() + cron 06:59 (completa la serie 06:29/39/49),
--     escribiendo en private.vigia_alertas (fase 'f7_piezas_cerradas').
--  4) SEED: las 7 gemelas del catalogo cerradas por F5.d el 30/08 (demolibles
--     desde el 13/09). Fechas LITERALES a proposito: el replay de un banco debe
--     reproducirlas tal cual.
--
-- La OBSERVACION honesta (medida, no supuesta): un intento rechazado (42501) NO
-- es detectable desde dentro de la base — el chequeo de EXECUTE corre antes del
-- cuerpo y no hay event triggers (postgres no es superusuario). Este vigia
-- vigila la SUPERFICIE (nadie re-cableo la pieza); los intentos reales se miran
-- en los logs del panel a D+7 y D+14, con fecha y responsable, como revision.
--
-- Censo F1.4: NO aplica (solo censa crm y public; esta tabla es private, como
-- private.vigia_alertas). Censo F6.a: NO aplica (el assert no nombra leads ni
-- citas). Ningun objeto existente se toca; cero cambios en public.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- =====================================================================
-- 0) PREFLIGHT: el mundo que el seed declara, verificado en el instante.
-- =====================================================================
do $$
declare
  v_fn constant text[][] := array[
    array['public.crear_contrato_producto(uuid,jsonb,jsonb)',                     '893c857e27ec6405a3ac6e291458c346'],
    array['public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',           'f0e519cc4ee79c9334ae59a23844b23b'],
    array['public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)','b7e0de18b559ec7fd650619cd22b9cb5'],
    array['crm.crear_contrato_producto(uuid,jsonb,jsonb)',                        '1148d0ca1beb33797995eeff3c579bd4'],
    array['crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',       '06f79b07b4d65dcf50cd4359fb598723'],
    array['crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',              '4156191492c25479be73b0365263d946'],
    array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',   '8640b1246f620ab40558cec2875ada23']
  ];
  v_fila text[]; v_h text; v_acl text;
begin
  foreach v_fila slice 1 in array v_fn loop
    if to_regprocedure(v_fila[1]) is null then
      raise exception 'F7.0 preflight: % no existe', v_fila[1];
    end if;
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'F7.0 preflight: % cambio desde F5.d (huella %)', v_fila[1], v_h;
    end if;
    select p.proacl::text into v_acl from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_acl is distinct from '{postgres=X/postgres}' then
      raise exception 'F7.0 preflight: ACL de % no es la del cierre F5.d (%)', v_fila[1], v_acl;
    end if;
  end loop;

  -- El gate que esta ola instala exige 0 alertas abiertas EN TODAS las fases:
  -- si hoy hubiera alguna vieja sin resolver, el lector naceria en rojo. Se
  -- exige el mundo limpio en el instante de instalar (medido 31/08: 0 abiertas).
  if (select count(*) from private.vigia_alertas where resuelta_en is null) <> 0 then
    raise exception 'F7.0 preflight: hay alertas ABIERTAS en vigia_alertas — resolverlas (o declararlas) antes de instalar su lector';
  end if;

  if to_regprocedure('crm.cerrar_altas_legacy_productos(bigint)') is null then
    raise exception 'F7.0 preflight: el llamador permitido cerrar_altas_legacy_productos no existe';
  end if;
  if to_regprocedure('private.assert_f7_piezas_cerradas()') is not null
     or to_regprocedure('private.veredicto_f7()') is not null then
    raise exception 'F7.0 preflight: el assert o el veredicto ya existen';
  end if;
  -- La TABLA puede existir (sobrevive al rollback por doctrina F6.a): la
  -- creacion de abajo es condicional y el seed es idempotente.
end $$;

-- =====================================================================
-- 1) LA LISTA-CANDADO.
-- =====================================================================
create table if not exists private.f7_piezas_en_observacion (
  firma                 text primary key,
  huella_md5            text not null,
  acl_esperada          text not null,
  llamadores_permitidos text[] not null default '{}',
  -- patron por NOMBRE (no por OID): una homonima en un esquema nuevo daria
  -- ROJO aunque no llame a la vigilada — fail-noisy a proposito; la salida
  -- legitima es declararla en llamadores_permitidos.
  patron_censo          text not null,
  ola                   text not null,
  estado                text not null check (estado in ('observacion', 'cerrada_permanente', 'demolida', 'liberada')),
  cerrada_en            date not null,
  drop_no_antes_de      date,
  ok_miguel             text not null check (length(ok_miguel) >= 20),
  nota                  text,
  constraint f7_obs_ventana check (
    estado <> 'observacion'
    or (drop_no_antes_de is not null and drop_no_antes_de >= cerrada_en + 14)
  )
);
alter table private.f7_piezas_en_observacion enable row level security;

comment on table private.f7_piezas_en_observacion is
  'F7: piezas cerradas en observacion. Es la lista que el vigia 06:59 lee, el candado '
  'temporal del DROP (drop_no_antes_de) y el registro historico. Salida = estado liberada; '
  'jamas DELETE.';

create or replace function private.trg_f7_obs_solo_crece()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.cerrada_en is distinct from old.cerrada_en then
    raise exception 'F7: cerrada_en es inmutable (%)', old.firma using errcode = '42501';
  end if;
  -- Auditoria F7.0 (P1): las columnas que definen el VEREDICTO y la AUTORIDAD
  -- tambien se congelan. El cambio legitimo baja este candado NOMBRADO en un
  -- DO de migracion (doctrina limpieza-leads) y lo re-activa.
  if new.huella_md5 is distinct from old.huella_md5
     or new.acl_esperada is distinct from old.acl_esperada
     or new.patron_censo is distinct from old.patron_censo
     or new.llamadores_permitidos is distinct from old.llamadores_permitidos
     or new.ok_miguel is distinct from old.ok_miguel
     or new.ola is distinct from old.ola then
    raise exception 'F7: la declaracion de % no se reescribe; una pieza que cambia se re-declara por migracion', old.firma
      using errcode = '42501';
  end if;
  if new.firma is distinct from old.firma then
    raise exception 'F7: la firma es la identidad de la fila y no se reescribe' using errcode = '42501';
  end if;
  -- Codex P0-3: la ventana ni encoge NI se resetea via NULL — una vez NULL
  -- (permanente), no se re-adquiere por UPDATE; eso es re-declaracion por
  -- migracion con el candado bajado.
  if old.drop_no_antes_de is not null
     and (new.drop_no_antes_de is null and new.estado <> 'cerrada_permanente'
          or new.drop_no_antes_de < old.drop_no_antes_de) then
    raise exception 'F7: la ventana de % solo puede CRECER', old.firma using errcode = '42501';
  end if;
  if old.drop_no_antes_de is null and new.drop_no_antes_de is not null then
    raise exception 'F7: % no re-adquiere ventana por UPDATE; se re-declara por migracion', old.firma
      using errcode = '42501';
  end if;
  -- Codex P0-2: MAQUINA DE ESTADOS cerrada. Solo observacion->demolida y
  -- observacion->cerrada_permanente. 'liberada' (devolver una pieza al
  -- servicio) y cualquier salida de demolida/cerrada_permanente EXIGEN una
  -- migracion que baje este candado nombrado (doctrina limpieza-leads):
  -- jamas un UPDATE de consola.
  if new.estado is distinct from old.estado then
    if not (old.estado = 'observacion' and new.estado in ('demolida', 'cerrada_permanente')) then
      raise exception 'F7: la transicion %->% de % SOLO por migracion con el candado bajado',
        old.estado, new.estado, old.firma using errcode = '42501';
    end if;
    if new.nota is not distinct from old.nota then
      raise exception 'F7: cambiar el estado de % exige dejar RASTRO en nota (quien y por que)', old.firma
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function private.trg_f7_obs_no_borrar()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception 'F7: una pieza en observacion no se borra (la salida es estado=liberada)'
    using errcode = '42501';
end;
$function$;

drop trigger if exists trg_f7_obs_00_solo_crece on private.f7_piezas_en_observacion;
create trigger trg_f7_obs_00_solo_crece
  before update on private.f7_piezas_en_observacion
  for each row execute function private.trg_f7_obs_solo_crece();
drop trigger if exists trg_f7_obs_01_no_borrar on private.f7_piezas_en_observacion;
create trigger trg_f7_obs_01_no_borrar
  before delete on private.f7_piezas_en_observacion
  for each row execute function private.trg_f7_obs_no_borrar();
drop trigger if exists trg_f7_obs_02_no_truncar on private.f7_piezas_en_observacion;
create trigger trg_f7_obs_02_no_truncar
  before truncate on private.f7_piezas_en_observacion
  for each statement execute function private.trg_f7_obs_no_borrar();

revoke all on function private.trg_f7_obs_solo_crece() from public, anon, authenticated;
revoke all on function private.trg_f7_obs_no_borrar() from public, anon, authenticated;

-- SEED: las 7 de F5.d (fechas literales del cierre real).
insert into private.f7_piezas_en_observacion
  (firma, huella_md5, acl_esperada, llamadores_permitidos, patron_censo, ola, estado,
   cerrada_en, drop_no_antes_de, ok_miguel, nota)
values
  ('public.crear_contrato_producto(uuid,jsonb,jsonb)', '893c857e27ec6405a3ac6e291458c346',
   '{postgres=X/postgres}', array['crm.cerrar_altas_legacy_productos(bigint)'],
   '\mcrear_contrato_producto\s*\(', 'F5.d', 'observacion',
   date '2026-08-30', date '2026-09-13',
   'Publicada F5.d (registro 186) con el ! de Miguel el 30/08; su tabla de OK esta en MIGRACIONES.md',
   'gemela muerta del catalogo versionado'),
  ('public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', 'f0e519cc4ee79c9334ae59a23844b23b',
   '{postgres=X/postgres}', array['crm.cerrar_altas_legacy_productos(bigint)'],
   '\mactualizar_contrato_producto\s*\(', 'F5.d', 'observacion',
   date '2026-08-30', date '2026-09-13',
   'Publicada F5.d (registro 186) con el ! de Miguel el 30/08; su tabla de OK esta en MIGRACIONES.md',
   null),
  ('public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'b7e0de18b559ec7fd650619cd22b9cb5',
   '{postgres=X/postgres}', array['crm.cerrar_altas_legacy_productos(bigint)'],
   '\mactualizar_contrato_con_cuenta_producto\s*\(', 'F5.d', 'observacion',
   date '2026-08-30', date '2026-09-13',
   'Publicada F5.d (registro 186) con el ! de Miguel el 30/08; su tabla de OK esta en MIGRACIONES.md',
   null),
  ('crm.crear_contrato_producto(uuid,jsonb,jsonb)', '1148d0ca1beb33797995eeff3c579bd4',
   '{postgres=X/postgres}', array['crm.cerrar_altas_legacy_productos(bigint)'],
   '\mcrear_contrato_producto\s*\(', 'F5.d', 'observacion',
   date '2026-08-30', date '2026-09-13',
   'Publicada F5.d (registro 186) con el ! de Miguel el 30/08; su tabla de OK esta en MIGRACIONES.md',
   null),
  ('crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)', '06f79b07b4d65dcf50cd4359fb598723',
   '{postgres=X/postgres}', '{}',
   '\mcrear_contrato_con_cuenta_producto\s*\(', 'F5.d', 'observacion',
   date '2026-08-30', date '2026-09-13',
   'Publicada F5.d (registro 186) con el ! de Miguel el 30/08; su tabla de OK esta en MIGRACIONES.md',
   'su nombre no aparece ni en cerrar_altas_legacy_productos'),
  ('crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', '4156191492c25479be73b0365263d946',
   '{postgres=X/postgres}', array['crm.cerrar_altas_legacy_productos(bigint)'],
   '\mactualizar_contrato_producto\s*\(', 'F5.d', 'observacion',
   date '2026-08-30', date '2026-09-13',
   'Publicada F5.d (registro 186) con el ! de Miguel el 30/08; su tabla de OK esta en MIGRACIONES.md',
   null),
  ('crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', '8640b1246f620ab40558cec2875ada23',
   '{postgres=X/postgres}', array['crm.cerrar_altas_legacy_productos(bigint)'],
   '\mactualizar_contrato_con_cuenta_producto\s*\(', 'F5.d', 'observacion',
   date '2026-08-30', date '2026-09-13',
   'Publicada F5.d (registro 186) con el ! de Miguel el 30/08; su tabla de OK esta en MIGRACIONES.md',
   null)
on conflict (firma) do nothing;

-- =====================================================================
-- 2) EL ASSERT.
-- =====================================================================
create function private.assert_f7_piezas_cerradas()
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

revoke all on function private.assert_f7_piezas_cerradas() from public, anon, authenticated;

-- =====================================================================
-- 2-bis) EL VEREDICTO como FUNCION (Codex P1: el gate y su mutante deben
--        ejercitar EL MISMO codigo, no una copia). Tres condiciones:
--        alertas, vigia exacto (dueno incluido, ultima corrida no fallida),
--        y el assert de piezas.
-- =====================================================================
create function private.veredicto_f7()
returns text
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare v_n integer; v_txt text;
begin
  select count(*) into v_n from private.vigia_alertas va where va.resuelta_en is null;
  if v_n > 0 then
    select 'ALERTAS ABIERTAS: ' || string_agg(format('[%s] %s', va.fase, left(va.motivo, 80)), ' · ' order by va.creado_en)
      into v_txt from private.vigia_alertas va where va.resuelta_en is null;
    return v_txt;
  end if;
  if (select count(*) from cron.job j
       where j.jobname = 'crm-f7-piezas-vigia' and j.schedule = '59 6 * * *'
         and j.command = 'select private.vigia_f7_piezas()'
         and j.database = current_database() and j.username = 'postgres' and j.active) <> 1 then
    return 'VIGIA APAGADO O ALTERADO: crm-f7-piezas-vigia no esta exactamente como se declaro';
  end if;
  if exists (
    select 1 from cron.job_run_details d
    join cron.job j on j.jobid = d.jobid and j.jobname = 'crm-f7-piezas-vigia'
    where d.start_time = (select max(d2.start_time) from cron.job_run_details d2 where d2.jobid = j.jobid)
      and d.status = 'failed'
  ) then
    return 'VIGIA CAIDO: la ultima corrida del cron FALLO';
  end if;
  return private.assert_f7_piezas_cerradas();
end;
$function$;

revoke all on function private.veredicto_f7() from public, anon, authenticated;

-- =====================================================================
-- 3) EL VIGIA (molde F6.a: jamas revienta el cron) + 06:59.
-- =====================================================================
create function private.vigia_f7_piezas()
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  begin
    perform private.assert_f7_piezas_cerradas();
  exception when others then
    insert into private.vigia_alertas (fase, motivo) values ('f7_piezas_cerradas', sqlerrm);
  end;
end;
$function$;

revoke all on function private.vigia_f7_piezas() from public, anon, authenticated;

do $$
declare v_jobid bigint;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'crm-f7-piezas-vigia') then
      perform cron.unschedule('crm-f7-piezas-vigia');
    end if;
    v_jobid := cron.schedule('crm-f7-piezas-vigia', '59 6 * * *', 'select private.vigia_f7_piezas()');
    perform cron.alter_job(v_jobid, active => true);
    if (select count(*) from cron.job
         where jobid = v_jobid and jobname = 'crm-f7-piezas-vigia'
           and schedule = '59 6 * * *' and command = 'select private.vigia_f7_piezas()'
           and database = current_database() and username = current_user and active) <> 1 then
      raise exception 'F7.0: el vigia no quedo EXACTAMENTE como se declaro (dueno incluido)';
    end if;
  else
    raise exception 'F7.0: falta pg_cron y la observacion se quedaria sin vigia';
  end if;
end $$;

-- =====================================================================
-- 4) POSTFLIGHT.
-- =====================================================================
do $$
declare v_txt text;
begin
  if (select count(*) from private.f7_piezas_en_observacion) < 7 then
    raise exception 'F7.0 postflight: faltan filas del seed';
  end if;
  -- Codex P1-1: en una RE-aplicacion la tabla sobrevive — se revalida que las
  -- 7 del seed siguen con su declaracion INMUTABLE intacta y que el CHECK de
  -- los 14 dias es el declarado (no una version vieja conservada).
  if (select count(*) from private.f7_piezas_en_observacion o
       where o.ola = 'F5.d'
         and o.acl_esperada = '{postgres=X/postgres}'
         and o.cerrada_en = date '2026-08-30') <> 7 then
    raise exception 'F7.0 postflight: el seed de F5.d no esta integro';
  end if;
  if (select lower(pg_get_constraintdef(c.oid)) from pg_constraint c
       where c.conrelid = 'private.f7_piezas_en_observacion'::regclass
         and c.conname = 'f7_obs_ventana') !~ 'cerrada_en \+ 14' then
    raise exception 'F7.0 postflight: el CHECK de la ventana no codifica los 14 dias';
  end if;
  v_txt := private.assert_f7_piezas_cerradas();
  if v_txt not like 'OK:%' then
    raise exception 'F7.0 postflight: el assert no dio OK (%)', v_txt;
  end if;
  v_txt := private.veredicto_f7();
  if v_txt not like 'OK:%' then
    raise exception 'F7.0 postflight: el VEREDICTO no dio OK (%)', v_txt;
  end if;
  if (select p.proacl::text from pg_proc p where p.oid = 'private.veredicto_f7()'::regprocedure)
     is distinct from '{postgres=X/postgres}' then
    raise exception 'F7.0 postflight: ACL del veredicto no es {postgres=X/postgres}';
  end if;
  if (select p.proacl::text from pg_proc p where p.oid = 'private.assert_f7_piezas_cerradas()'::regprocedure)
     is distinct from '{postgres=X/postgres}' then
    raise exception 'F7.0 postflight: ACL del assert no es {postgres=X/postgres}';
  end if;
  if (select p.proacl::text from pg_proc p where p.oid = 'private.vigia_f7_piezas()'::regprocedure)
     is distinct from '{postgres=X/postgres}' then
    raise exception 'F7.0 postflight: ACL del vigia no es {postgres=X/postgres}';
  end if;
  if (select p.proacl::text from pg_proc p where p.oid = 'private.trg_f7_obs_solo_crece()'::regprocedure)
     is distinct from '{postgres=X/postgres}'
     or (select p.proacl::text from pg_proc p where p.oid = 'private.trg_f7_obs_no_borrar()'::regprocedure)
     is distinct from '{postgres=X/postgres}' then
    raise exception 'F7.0 postflight: ACL de las funciones de trigger no es {postgres=X/postgres}';
  end if;
  -- La tabla: RLS ON, deny-by-default (0 policies), 0 grants a la API.
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'private' and c.relname = 'f7_piezas_en_observacion'
                    and c.relrowsecurity) then
    raise exception 'F7.0 postflight: la tabla quedo sin RLS';
  end if;
  if exists (select 1 from pg_policy pol join pg_class c on c.oid = pol.polrelid
              join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'private' and c.relname = 'f7_piezas_en_observacion') then
    raise exception 'F7.0 postflight: la tabla no debe tener policies';
  end if;
  if exists (
    select 1 from information_schema.role_table_grants g
     where g.table_schema = 'private' and g.table_name = 'f7_piezas_en_observacion'
       and g.grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC')) then
    raise exception 'F7.0 postflight: la tabla tiene grants a la API';
  end if;
  -- Los 3 candados de la tabla, activos.
  if (select count(*) from pg_trigger t
       where t.tgrelid = 'private.f7_piezas_en_observacion'::regclass
         and not t.tgisinternal and t.tgenabled in ('O', 'A')) <> 3 then
    raise exception 'F7.0 postflight: los 3 candados de la tabla no estan activos';
  end if;

  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
