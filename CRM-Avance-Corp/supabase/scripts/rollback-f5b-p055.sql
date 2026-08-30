-- MARCHA ATRAS de la Fase 5.b (una pregunta por capacidad y los pares).
-- Reemplazo INVERSO con literales de maquina (mismos bytes que la ida).
-- ⚠️ La TABLA de pares se conserva (razones declaradas); se retiran los
--    candados, las preguntas nuevas y las conversiones.
begin;
set local lock_timeout = '5s';

do $$
declare v_def text; v_veces integer;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = 'public.crear_contrato_producto(uuid,jsonb,jsonb)'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$if not (select private.puede_registrar_ventas()) then$rb$, ''))) / length($rb$if not (select private.puede_registrar_ventas()) then$rb$);
  if v_veces <> 1 then raise exception 'rollback F5.b: ancla de public.crear_contrato_producto(uuid,jsonb,jsonb) aparece % veces', v_veces; end if;
  execute replace(v_def, $rb$if not (select private.puede_registrar_ventas()) then$rb$, $rb$if not ((select public.es_admin()) or (select public.es_analista())) then$rb$);
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = 'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$if not (select private.puede_registrar_ventas()) then$rb$, ''))) / length($rb$if not (select private.puede_registrar_ventas()) then$rb$);
  if v_veces <> 1 then raise exception 'rollback F5.b: ancla de public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb) aparece % veces', v_veces; end if;
  execute replace(v_def, $rb$if not (select private.puede_registrar_ventas()) then$rb$, $rb$if not ((select public.es_admin()) or (select public.es_analista())) then$rb$);
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = 'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$if not (select private.puede_registrar_ventas()) then$rb$, ''))) / length($rb$if not (select private.puede_registrar_ventas()) then$rb$);
  if v_veces <> 1 then raise exception 'rollback F5.b: ancla de public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) aparece % veces', v_veces; end if;
  execute replace(v_def, $rb$if not (select private.puede_registrar_ventas()) then$rb$, $rb$if not ((select public.es_admin()) or (select public.es_analista())) then$rb$);
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = 'crm.crear_contrato_producto(uuid,jsonb,jsonb)'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$if not (select private.puede_registrar_ventas()) then$rb$, ''))) / length($rb$if not (select private.puede_registrar_ventas()) then$rb$);
  if v_veces <> 1 then raise exception 'rollback F5.b: ancla de crm.crear_contrato_producto(uuid,jsonb,jsonb) aparece % veces', v_veces; end if;
  execute replace(v_def, $rb$if not (select private.puede_registrar_ventas()) then$rb$, $rb$if not private.puede_gestionar_contratos_crm() then$rb$);
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$if not (select private.puede_registrar_ventas()) then$rb$, ''))) / length($rb$if not (select private.puede_registrar_ventas()) then$rb$);
  if v_veces <> 1 then raise exception 'rollback F5.b: ancla de crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb) aparece % veces', v_veces; end if;
  execute replace(v_def, $rb$if not (select private.puede_registrar_ventas()) then$rb$, $rb$if not private.puede_gestionar_contratos_crm() then$rb$);
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = 'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$if not (select private.puede_registrar_ventas()) then$rb$, ''))) / length($rb$if not (select private.puede_registrar_ventas()) then$rb$);
  if v_veces <> 1 then raise exception 'rollback F5.b: ancla de crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb) aparece % veces', v_veces; end if;
  execute replace(v_def, $rb$if not (select private.puede_registrar_ventas()) then$rb$, $rb$if not private.puede_gestionar_contratos_crm() then$rb$);
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = 'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$if not (select private.puede_registrar_ventas()) then$rb$, ''))) / length($rb$if not (select private.puede_registrar_ventas()) then$rb$);
  if v_veces <> 1 then raise exception 'rollback F5.b: ancla de crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) aparece % veces', v_veces; end if;
  execute replace(v_def, $rb$if not (select private.puede_registrar_ventas()) then$rb$, $rb$if not private.puede_gestionar_contratos_crm() then$rb$);
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = 'public.productos_inversion_seleccion_fn(uuid)'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$or not (select private.puede_ver_catalogo_productos()) then$rb$, ''))) / length($rb$or not (select private.puede_ver_catalogo_productos()) then$rb$);
  if v_veces <> 1 then raise exception 'rollback F5.b: ancla de public.productos_inversion_seleccion_fn(uuid) aparece % veces', v_veces; end if;
  execute replace(v_def, $rb$or not (select private.puede_ver_catalogo_productos()) then$rb$, $rb$or not ((select public.es_admin()) or (select private.es_analista_vigente())) then$rb$);
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = 'crm.productos_inversion_seleccion_fn()'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$or not (select private.puede_ver_catalogo_productos()) then$rb$, ''))) / length($rb$or not (select private.puede_ver_catalogo_productos()) then$rb$);
  if v_veces <> 1 then raise exception 'rollback F5.b: ancla de crm.productos_inversion_seleccion_fn() aparece % veces', v_veces; end if;
  execute replace(v_def, $rb$or not (select private.puede_ver_catalogo_productos()) then$rb$, $rb$or (
       private.rol_crm(v_actor) is null
       and not private.es_lector_global()
     ) then$rb$);
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = 'public.cerrar_contrato(uuid,text,uuid)'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$IF NOT (es_admin() OR private.es_gerencia_crm_activa()) THEN$rb$, ''))) / length($rb$IF NOT (es_admin() OR private.es_gerencia_crm_activa()) THEN$rb$);
  if v_veces <> 1 then raise exception 'rollback F5.b: ancla de public.cerrar_contrato(uuid,text,uuid) aparece % veces', v_veces; end if;
  execute replace(v_def, $rb$IF NOT (es_admin() OR private.es_gerencia_crm_activa()) THEN$rb$, $rb$IF NOT es_admin() THEN$rb$);
end $$;

drop trigger if exists trg_perfiles_par_autoridad on public.perfiles;
drop trigger if exists trg_equipo_par_autoridad on crm.equipo;
drop trigger if exists trg_pares_autoridad_no_borrar on private.pares_autoridad;
drop trigger if exists trg_pares_autoridad_no_truncar on private.pares_autoridad;
drop function if exists private.trg_perfiles_par_autoridad();
drop function if exists private.trg_equipo_par_autoridad();
drop function if exists private.trg_pares_autoridad_no_borrar();
drop function if exists private.par_autoridad_valido(text, text);
-- NOTA: la higiene del trinquete de vigencia (3 exenciones fuera, tope a 6) NO
-- se revierte: el tope solo baja por diseño y las 3 funciones ya no nombran
-- es_analista tras revertir sus gates -siguen preguntando puede_registrar_ventas
-- hasta que esta marcha atras las devuelva-. Tras el rollback de las funciones,
-- vuelven a nombrar es_analista y RE-ENTRAN al censo: hay que re-declararlas.
insert into private.analista_vigencia_exenciones (objeto, tipo, huella, razon)
select v.objeto, 'funcion',
       -- MISMA normalizacion que el censo de vigencia (F5.a): prosrc, sin lower.
       (select md5(regexp_replace(regexp_replace(p.prosrc,
               '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
          from pg_proc p where p.oid = v.objeto::regprocedure),
       v.razon
  from (values
    ('public.crear_contrato_producto(uuid,jsonb,jsonb)',
     'Su primer gate es del Portal, pero delega en public.crear_contrato, que exige la membresia del CRM: la revocada rebota en la llamada interna sin crear nada.'),
    ('public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
     'Su primer gate es del Portal, pero delega en public.actualizar_contrato, cuya rama de analista cierra por puede_gestionar_cuentas_cliente: la revocada rebota dentro.'),
    ('public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
     'Su primer gate es del Portal, pero delega en crm.actualizar_contrato_con_cuenta, que gatea por private.puede_gestionar_cuentas_cliente(cliente_id) y exige la membresia sin revocar.')
  ) v(objeto, razon)
on conflict (objeto) do update set huella = excluded.huella, razon = excluded.razon;

-- Y el TOPE de vuelta a 9: con las 3 funciones re-nombrando es_analista, el censo
-- vuelve a 9 y un tope de 6 dejaria el trinquete rojo (9 > 6). El guard solo-baja
-- se salta un instante -es una marcha atras deliberada, no una relajacion-.
alter table private.analista_vigencia_tope disable trigger trg_analista_vigencia_tope_solo_baja;
update private.analista_vigencia_tope
   set tope = (select count(*) from private.puertas_analista_sin_vigencia())
 where id;
alter table private.analista_vigencia_tope enable trigger trg_analista_vigencia_tope_solo_baja;
drop function if exists private.puede_registrar_ventas();
drop function if exists private.puede_ver_catalogo_productos();

do $$
declare v_h text; v_v text; v_a text;
begin
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'public.crear_contrato_producto(uuid,jsonb,jsonb)'::regprocedure;
  if v_h is distinct from 'a6ea3a7c41c952d5365c7640fe944aeb' then
    raise exception 'rollback F5.b: public.crear_contrato_producto(uuid,jsonb,jsonb) no volvio a su huella (%)', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)'::regprocedure;
  if v_h is distinct from 'a418a64e8f1273fe6dfae2606cce308e' then
    raise exception 'rollback F5.b: public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb) no volvio a su huella (%)', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)'::regprocedure;
  if v_h is distinct from 'f0d90f4a266a07a50f04b8d3173e597d' then
    raise exception 'rollback F5.b: public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) no volvio a su huella (%)', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'crm.crear_contrato_producto(uuid,jsonb,jsonb)'::regprocedure;
  if v_h is distinct from '081f65a5150a3347cbf897c1d4e12c63' then
    raise exception 'rollback F5.b: crm.crear_contrato_producto(uuid,jsonb,jsonb) no volvio a su huella (%)', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)'::regprocedure;
  if v_h is distinct from 'f3a9c0ae017672f5311f0c3fe86e82ef' then
    raise exception 'rollback F5.b: crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb) no volvio a su huella (%)', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)'::regprocedure;
  if v_h is distinct from '1fb5724cc929aa9396a7e3ae654cf084' then
    raise exception 'rollback F5.b: crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb) no volvio a su huella (%)', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)'::regprocedure;
  if v_h is distinct from 'fd7ab45765786037ef2c9416fe64e53e' then
    raise exception 'rollback F5.b: crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) no volvio a su huella (%)', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'public.productos_inversion_seleccion_fn(uuid)'::regprocedure;
  if v_h is distinct from '0af48d75e921cd8d2033a3a5582fa44d' then
    raise exception 'rollback F5.b: public.productos_inversion_seleccion_fn(uuid) no volvio a su huella (%)', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'crm.productos_inversion_seleccion_fn()'::regprocedure;
  if v_h is distinct from 'b6460ac5f23b4821ddacbc7d982b9c1d' then
    raise exception 'rollback F5.b: crm.productos_inversion_seleccion_fn() no volvio a su huella (%)', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'public.cerrar_contrato(uuid,text,uuid)'::regprocedure;
  if v_h is distinct from 'd2516b0b185e8387c75cb31e6dcaa0f3' then
    raise exception 'rollback F5.b: public.cerrar_contrato(uuid,text,uuid) no volvio a su huella (%)', v_h;
  end if;
  select private.assert_analista_vigencia() into v_v;
  if v_v not like 'OK:%' then raise exception 'rollback F5.b: el trinquete de vigencia quedo rojo: %', v_v; end if;
  select private.assert_analitica_leads_citas() into v_a;
  if v_a not like 'OK:%' then raise exception 'rollback F5.b: el trinquete de analitica quedo rojo: %', v_a; end if;
end $$;

commit;
