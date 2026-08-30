-- ACEPTACION F5.a - PARTE 1: la foto de ANTES.
-- Se ejecuta DENTRO de la transaccion del ensayo, que siempre se deshace.
-- No apaga ningun trigger de produccion: para probar la ventana de 5 horas de la
-- politica de EDICION se dan de alta DOS fichas nuevas (nacen con
-- `creado_en = now()`), una por analista.
--   🔴 Por que no se rejuvenece una ficha existente: `perfiles.creado_en` es
--      INMUTABLE -`trg_proteger_perfiles` hace `NEW.creado_en := OLD.creado_en`
--      en silencio-, de modo que el rejuvenecimiento NO ocurre y el caso
--      positivo mediria 0 filas por un defecto del oraculo. Y apagar ese trigger
--      toma ACCESS EXCLUSIVE sobre `public.perfiles` durante todo el ensayo:
--      congelaria el portal entero, lecturas incluidas.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '180s';

do $$
declare
  v_rev uuid := '4e929ee5-b708-4a97-81f8-945e331f2221';  -- analista viva en el Portal, membresia CRM apagada
  v_ctl uuid := '1de5eba1-e6bb-435d-9eff-74286e881d01';  -- analista viva
  v_id uuid; v_contrato uuid; n integer; t text; b boolean;
begin
  -- Dos fichas nuevas, una por analista.
  foreach v_id in array array[v_rev, v_ctl] loop
    declare v_nuevo uuid := gen_random_uuid();
    begin
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                              email_confirmed_at, created_at, updated_at,
                              raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous)
      values ('00000000-0000-0000-0000-000000000000', v_nuevo, 'authenticated', 'authenticated',
              'f5a-prueba-' || left(v_nuevo::text, 8) || '@ejemplo.invalido', crypt('x', gen_salt('bf')),
              now(), now(), now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, false, false);
      insert into public.perfiles (id, rol, nombre_completo, activo, asesor_perfil_id, creado_por)
      values (v_nuevo, 'cliente', 'CLIENTE DE PRUEBA F5A', true, v_id, v_id);
      if v_id = v_rev then
        perform set_config('f5a.cliente_rev', v_nuevo::text, true);
      else
        perform set_config('f5a.cliente_ctl', v_nuevo::text, true);
      end if;
    end;
  end loop;

  -- Un contrato suyo, y un co-titular temporal para poder DEMOSTRAR esa puerta
  -- (la revocada no tiene co-titulares propios: sin esto, 0 antes y 0 despues no
  -- prueba nada).
  select c.id into v_contrato
    from public.contratos c join public.perfiles cli on cli.id = c.cliente_id
   where cli.rol = 'cliente'
     and (cli.asesor_perfil_id = v_rev or (cli.asesor_perfil_id is null and cli.creado_por = v_rev))
   limit 1;
  perform set_config('f5a.contrato_rev', coalesce(v_contrato::text, ''), true);
  if v_contrato is not null then
    insert into public.contrato_titulares (contrato_id, orden, nombre_completo, tipo_documento, documento, creado_por)
    values (v_contrato, 2, 'CO-TITULAR DE PRUEBA F5A', 'DNI', '00000001', v_rev);
  end if;

  -- ---------------- REVOCADA, ANTES ----------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_rev, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.contratos;                    perform set_config('f5a.a_rev_con', n::text, true);
  select count(*) into n from public.cronograma_pagos;             perform set_config('f5a.a_rev_cuo', n::text, true);
  select count(*) into n from public.perfiles where rol='cliente'; perform set_config('f5a.a_rev_fic', n::text, true);
  select count(*) into n from public.contrato_titulares;           perform set_config('f5a.a_rev_tit', n::text, true);
  begin select count(*) into n from crm.cliente_detalle_fn(current_setting('f5a.cliente_rev')::uuid); t := n::text;
  exception when others then t := 'ERR '||sqlstate; end;           perform set_config('f5a.a_rev_det', t, true);
  begin select count(*) into n from public.productos_inversion_seleccion_fn(null); t := n::text;
  exception when others then t := 'ERR '||sqlstate; end;           perform set_config('f5a.a_rev_pro', t, true);
  begin select public.puede_ver_contrato(current_setting('f5a.contrato_rev')::uuid) into b; t := b::text;
  exception when others then t := 'ERR '||sqlstate; end;           perform set_config('f5a.a_rev_ver', t, true);
  begin select public.contrato_tiene_pagos(current_setting('f5a.contrato_rev')::uuid) into b; t := b::text;
  exception when others then t := 'ERR '||sqlstate; end;           perform set_config('f5a.a_rev_pag', t, true);
  execute 'reset role';

  -- ---------------- CONTROL, ANTES ----------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_ctl, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.contratos;                    perform set_config('f5a.a_ctl_con', n::text, true);
  select count(*) into n from public.cronograma_pagos;             perform set_config('f5a.a_ctl_cuo', n::text, true);
  select count(*) into n from public.perfiles where rol='cliente'; perform set_config('f5a.a_ctl_fic', n::text, true);
  select count(*) into n from public.contrato_titulares;           perform set_config('f5a.a_ctl_tit', n::text, true);
  begin select count(*) into n from crm.cliente_detalle_fn(current_setting('f5a.cliente_ctl')::uuid); t := n::text;
  exception when others then t := 'ERR '||sqlstate; end;           perform set_config('f5a.a_ctl_det', t, true);
  begin select count(*) into n from public.productos_inversion_seleccion_fn(null); t := n::text;
  exception when others then t := 'ERR '||sqlstate; end;           perform set_config('f5a.a_ctl_pro', t, true);
  execute 'reset role';

  -- ---------------- ANON, ANTES ----------------
  perform set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
  execute 'set local role anon';
  begin select count(*) into n from public.contratos; t := n::text;
  exception when others then t := 'ERR '||sqlstate; end;           perform set_config('f5a.a_anon', t, true);
  execute 'reset role';

  perform set_config('request.jwt.claims', '', true);
end $$;
