-- ACEPTACION F5.a - PARTE 2: la foto de DESPUES, los positivos y los mutantes.
-- Termina SIEMPRE en `raise exception`: el ensayo entero se deshace.
do $$
declare
  v_rev uuid := '4e929ee5-b708-4a97-81f8-945e331f2221';
  v_ctl uuid := '1de5eba1-e6bb-435d-9eff-74286e881d01';
  n integer; b boolean; f text := '';
  d_con integer; d_cuo integer; d_fic integer; d_tit integer; d_det text; d_pro text; d_ver text; d_pag text;
  e_con integer; e_cuo integer; e_fic integer; e_tit integer; e_det text; e_pro text;
  upd_rev integer; upd_ctl integer; anon_d text;
  m2 integer; m4 integer; m5 text; m6 text; m7 text; m8 text; m9 text; m10 text; m11 text;
begin
  -- ================= REVOCADA, DESPUES =================
  perform set_config('request.jwt.claims', json_build_object('sub', v_rev, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into d_con from public.contratos;
  select count(*) into d_cuo from public.cronograma_pagos;
  select count(*) into d_fic from public.perfiles where rol='cliente';
  select count(*) into d_tit from public.contrato_titulares;
  begin select count(*) into n from crm.cliente_detalle_fn(current_setting('f5a.cliente_rev')::uuid); d_det := n::text;
  exception when others then d_det := 'ERR '||sqlstate; end;
  begin select count(*) into n from public.productos_inversion_seleccion_fn(null); d_pro := n::text;
  exception when others then d_pro := 'ERR '||sqlstate; end;
  begin select public.puede_ver_contrato(current_setting('f5a.contrato_rev')::uuid) into b; d_ver := b::text;
  exception when others then d_ver := 'ERR '||sqlstate; end;
  begin select public.contrato_tiene_pagos(current_setting('f5a.contrato_rev')::uuid) into b; d_pag := b::text;
  exception when others then d_pag := 'ERR '||sqlstate; end;
  begin
    update public.perfiles set telefono = coalesce(telefono,'') where id = current_setting('f5a.cliente_rev')::uuid;
    get diagnostics upd_rev = row_count;
  exception when others then upd_rev := -1; end;
  execute 'reset role';

  -- ================= CONTROL, DESPUES (la mitad positiva) =================
  perform set_config('request.jwt.claims', json_build_object('sub', v_ctl, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into e_con from public.contratos;
  select count(*) into e_cuo from public.cronograma_pagos;
  select count(*) into e_fic from public.perfiles where rol='cliente';
  select count(*) into e_tit from public.contrato_titulares;
  begin select count(*) into n from crm.cliente_detalle_fn(current_setting('f5a.cliente_ctl')::uuid); e_det := n::text;
  exception when others then e_det := 'ERR '||sqlstate; end;
  begin select count(*) into n from public.productos_inversion_seleccion_fn(null); e_pro := n::text;
  exception when others then e_pro := 'ERR '||sqlstate; end;
  begin
    update public.perfiles set telefono = coalesce(telefono,'') where id = current_setting('f5a.cliente_ctl')::uuid;
    get diagnostics upd_ctl = row_count;
  exception when others then upd_ctl := -1; end;
  execute 'reset role';

  -- ================= ANON, DESPUES =================
  perform set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
  execute 'set local role anon';
  begin select count(*) into n from public.contratos; anon_d := n::text;
  exception when others then anon_d := 'ERR '||sqlstate; end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);

  -- ================= VEREDICTO DE COMPORTAMIENTO =================
  -- Lo que la revocada tiene que PERDER.
  if d_con <> 0 or d_cuo <> 0 or d_fic <> 0 then f := f || format(' [1] sigue viendo %s/%s/%s;', d_con,d_cuo,d_fic); end if;
  if current_setting('f5a.a_rev_tit')::integer = 0 then f := f || ' [2a] el co-titular de prueba no se creo: la puerta no se puede demostrar;'; end if;
  if d_tit <> 0 then f := f || format(' [2] sigue viendo %s co-titulares;', d_tit); end if;
  if d_det <> '0' then f := f || format(' [3] la ficha 360 le sigue respondiendo (%s);', d_det); end if;
  -- El selector tiene que negar con 42501, no con un error cualquiera.
  if d_pro <> 'ERR 42501' then f := f || format(' [4] el selector de productos no niega con 42501 (%s);', d_pro); end if;
  if d_ver <> 'false' then f := f || format(' [5] puede_ver_contrato le sigue diciendo que si (%s);', d_ver); end if;
  if d_pag <> 'false' then f := f || format(' [6] contrato_tiene_pagos le sigue respondiendo (%s);', d_pag); end if;
  if upd_rev <> 0 then f := f || format(' [7] AUN EDITA fichas (filas=%s);', upd_rev); end if;
  -- Lo que la revocada tenia que tener ANTES (si no, el ensayo no prueba nada).
  if current_setting('f5a.a_rev_con')::integer = 0 then f := f || ' [p1] preflight: no veia contratos ni antes;'; end if;
  if current_setting('f5a.a_rev_det') <> '1' then f := f || format(' [p2] preflight: la ficha 360 no le respondia antes (%s);', current_setting('f5a.a_rev_det')); end if;
  if current_setting('f5a.a_rev_ver') <> 'true' then f := f || format(' [p3] preflight: puede_ver_contrato no le decia que si antes (%s);', current_setting('f5a.a_rev_ver')); end if;
  if current_setting('f5a.a_rev_pro') like 'ERR%' then f := f || format(' [p4] preflight: el selector ya le negaba antes (%s);', current_setting('f5a.a_rev_pro')); end if;

  -- Lo que la analista VIVA no puede perder.
  if e_con::text <> current_setting('f5a.a_ctl_con') or e_cuo::text <> current_setting('f5a.a_ctl_cuo')
     or e_fic::text <> current_setting('f5a.a_ctl_fic') or e_tit::text <> current_setting('f5a.a_ctl_tit') then
    f := f || ' [8] la analista viva PERDIO filas;';
  end if;
  if e_det <> current_setting('f5a.a_ctl_det') then f := f || format(' [9] perdio la ficha 360 (%s -> %s);', current_setting('f5a.a_ctl_det'), e_det); end if;
  if e_pro <> current_setting('f5a.a_ctl_pro') or e_pro like 'ERR%' then f := f || format(' [10] perdio el selector de productos (%s -> %s);', current_setting('f5a.a_ctl_pro'), e_pro); end if;
  if upd_ctl <> 1 then f := f || format(' [11] NO puede editar su ficha reciente (filas=%s);', upd_ctl); end if;
  if anon_d <> current_setting('f5a.a_anon') or anon_d like 'ERR%' then
    f := f || format(' [12] anon cambio de comportamiento (%s -> %s);', current_setting('f5a.a_anon'), anon_d);
  end if;

  -- ================= MUTANTES =================
  -- m2: se deshacen las dos politicas de lectura -> vuelve a ver lo de antes.
  execute $d$ alter policy contratos_analista_select on public.contratos
    using (public.es_analista() and exists (select 1 from public.perfiles cli
      where cli.id = contratos.cliente_id and cli.rol='cliente'
        and (cli.asesor_perfil_id = (select auth.uid())
             or (cli.asesor_perfil_id is null and cli.creado_por = (select auth.uid()))))) $d$;
  execute $d$ alter policy perfiles_analista_select on public.perfiles
    using (public.es_analista() and rol='cliente'
      and (asesor_perfil_id = (select auth.uid())
           or (asesor_perfil_id is null and creado_por = (select auth.uid())))) $d$;
  perform set_config('request.jwt.claims', json_build_object('sub', v_rev, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into m2 from public.contratos;
  execute 'reset role';
  if m2::text <> current_setting('f5a.a_rev_con') then f := f || format(' [m2] esperaba %s, dio %s;', current_setting('f5a.a_rev_con'), m2); end if;

  -- m4: se deshace la politica de EDICION -> la revocada vuelve a poder editar.
  execute $d$ alter policy perfiles_analista_update on public.perfiles
    using (public.es_analista() and rol='cliente' and creado_en > (now() - '05:00:00'::interval)
           and (creado_por = (select auth.uid()) or asesor_perfil_id = (select auth.uid())))
    with check (public.es_analista() and rol='cliente'
           and (creado_por = (select auth.uid()) or asesor_perfil_id = (select auth.uid()))) $d$;
  execute 'set local role authenticated';
  begin
    update public.perfiles set telefono = coalesce(telefono,'') where id = current_setting('f5a.cliente_rev')::uuid;
    get diagnostics m4 = row_count;
  exception when others then m4 := -1; end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  if m4 <> 1 then f := f || format(' [m4] el mutante de EDICION no se nota (filas=%s);', m4); end if;

  -- m5: una puerta nueva sin declarar -> el trinquete revienta.
  execute $d$ create or replace function public.f5a_mutante_puerta() returns boolean
              language sql stable as $g$ select public.es_analista() $g$ $d$;
  begin perform private.assert_analista_vigencia(); m5 := 'NO REVENTO';
  exception when others then m5 := 'revienta'; end;
  execute 'drop function public.f5a_mutante_puerta()';
  if m5 <> 'revienta' then f := f || format(' [m5] el trinquete no caza una puerta nueva (%s);', m5); end if;

  -- m6: subir el tope -> rebota.
  begin update private.analista_vigencia_tope set tope = tope + 5 where id; m6 := 'NO REVENTO';
  exception when others then m6 := 'revienta'; end;
  if m6 <> 'revienta' then f := f || format(' [m6] el tope se dejo subir (%s);', m6); end if;

  -- m7: borrar del equipo -> rebota.
  begin delete from crm.equipo where perfil_id = v_rev; m7 := 'NO REVENTO';
  exception when others then m7 := 'revienta'; end;
  if m7 <> 'revienta' then f := f || format(' [m7] se dejo borrar la fila del equipo (%s);', m7); end if;

  -- m8: la PUERTA DECLARADA sin motivo de verdad -> rebota.
  begin perform crm.purgar_membresia_crm(v_rev, 'porque si'); m8 := 'NO REVENTO';
  exception when others then m8 := 'revienta'; end;
  if m8 <> 'revienta' then f := f || format(' [m8] la purga acepto un motivo vacio (%s);', m8); end if;

  -- m9: la puerta declarada NO esta al alcance de una sesion de persona.
  perform set_config('request.jwt.claims', json_build_object('sub', v_ctl, 'role','authenticated')::text, true);
  execute 'set local role authenticated';
  begin perform crm.purgar_membresia_crm(v_rev, 'intento desde una sesion de persona, no deberia poder'); m9 := 'NO REVENTO';
  exception when others then m9 := 'revienta ' || sqlstate; end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  if m9 not like 'revienta%' then f := f || format(' [m9] una sesion de persona pudo purgar (%s);', m9); end if;

  -- m10: la puerta declarada SI funciona con motivo, y deja lapida.
  --      Se prueba sobre una membresia FABRICADA -que es el caso real de uso:
  --      el fixture del gate y la limpieza de una base de pruebas-. Sobre una
  --      persona con historia NO se puede purgar aunque se quiera: las claves
  --      foraneas de los ledgers que la nombran lo impiden (medido: 23503), lo
  --      que es una segunda red y conviene saberlo.
  declare v_falso uuid := gen_random_uuid();
  begin
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                            email_confirmed_at, created_at, updated_at,
                            raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous)
    values ('00000000-0000-0000-0000-000000000000', v_falso, 'authenticated', 'authenticated',
            'f5a-fabricada-' || left(v_falso::text, 8) || '@ejemplo.invalido', crypt('x', gen_salt('bf')),
            now(), now(), now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, false, false);
    insert into public.perfiles (id, rol, nombre_completo, activo)
    values (v_falso, 'analista', 'MEMBRESIA FABRICADA F5A', true);
    insert into crm.equipo (perfil_id, rol_crm, activo) values (v_falso, 'vendedor', false);
    begin
      perform crm.purgar_membresia_crm(v_falso, 'Ensayo de aceptacion F5.a: comprobar que la puerta declarada purga y deja lapida');
      select count(*) into n from private.membresias_purgadas where perfil_id = v_falso;
      m10 := case when n = 1 and not exists (select 1 from crm.equipo where perfil_id = v_falso)
                  then 'purga con lapida' else 'purga SIN lapida' end;
    exception when others then m10 := 'no purgo: ' || sqlstate; end;
  end;
  if m10 <> 'purga con lapida' then f := f || format(' [m10] la puerta declarada no funciona (%s);', m10); end if;

  -- m11: y la valvula se cierra sola: un borrado suelto despues sigue rebotando.
  begin delete from crm.equipo where activo is false; m11 := 'NO REVENTO';
  exception when others then m11 := 'revienta'; end;
  if m11 <> 'revienta' then f := f || format(' [m11] la valvula se quedo abierta tras la purga (%s);', m11); end if;

  if f <> '' then
    raise exception 'F5.a ROJO:% || REV antes %/%/% tit % det % pro % ver % pag % -> despues %/%/% tit % det % pro % ver % pag % edit % | CTL antes %/%/% det % pro % -> despues %/%/% det % pro % edit % | anon % -> % | m2=% m4=% m5=% m6=% m7=% m8=% m9=% m10=% m11=% (TODO DESHECHO)',
      f, current_setting('f5a.a_rev_con'), current_setting('f5a.a_rev_cuo'), current_setting('f5a.a_rev_fic'),
      current_setting('f5a.a_rev_tit'), current_setting('f5a.a_rev_det'), current_setting('f5a.a_rev_pro'),
      current_setting('f5a.a_rev_ver'), current_setting('f5a.a_rev_pag'),
      d_con,d_cuo,d_fic,d_tit,d_det,d_pro,d_ver,d_pag,upd_rev,
      current_setting('f5a.a_ctl_con'), current_setting('f5a.a_ctl_cuo'), current_setting('f5a.a_ctl_fic'),
      current_setting('f5a.a_ctl_det'), current_setting('f5a.a_ctl_pro'),
      e_con,e_cuo,e_fic,e_det,e_pro,upd_ctl,
      current_setting('f5a.a_anon'), anon_d, m2, m4, m5, m6, m7, m8, m9, m10, m11;
  end if;

  raise exception 'F5.a VERDE || REV antes %/%/% tit % det % pro % ver % pag % -> despues %/%/% tit % det % pro % ver % pag % edit % | CTL antes %/%/% det % pro % -> despues %/%/% det % pro % edit % | anon % -> % | m2=% m4=% m5=% m6=% m7=% m8=% m9=% m10=% m11=% || TODO DESHECHO',
    current_setting('f5a.a_rev_con'), current_setting('f5a.a_rev_cuo'), current_setting('f5a.a_rev_fic'),
    current_setting('f5a.a_rev_tit'), current_setting('f5a.a_rev_det'), current_setting('f5a.a_rev_pro'),
    current_setting('f5a.a_rev_ver'), current_setting('f5a.a_rev_pag'),
    d_con,d_cuo,d_fic,d_tit,d_det,d_pro,d_ver,d_pag,upd_rev,
    current_setting('f5a.a_ctl_con'), current_setting('f5a.a_ctl_cuo'), current_setting('f5a.a_ctl_fic'),
    current_setting('f5a.a_ctl_det'), current_setting('f5a.a_ctl_pro'),
    e_con,e_cuo,e_fic,e_det,e_pro,upd_ctl,
    current_setting('f5a.a_anon'), anon_d, m2, m4, m5, m6, m7, m8, m9, m10, m11;
end $$;
