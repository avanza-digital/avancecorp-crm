-- MARCHA ATRAS de la Fase 5.c (ventas al nucleo del dinero).
-- Reemplazo INVERSO con literales de maquina + la pregunta vuelve a su forma F5.b.
begin;
set local lock_timeout = '5s';

do $$
declare v_def text; v_veces integer;
begin
  -- crear_contrato: revierte (a) la pregunta unica -> bloque de roles + P04, y
  -- (b) el endurecimiento `and p.activo` del for-share que agrego la F5.c. Los
  -- dos reemplazos se aplican sobre la MISMA definicion antes de re-crearla, para
  -- que el cuerpo vuelva byte-exact a su forma pre-F5.c (huella cf5ef945...).
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$(select private.puede_registrar_ventas())$rb$, ''))) / length($rb$(select private.puede_registrar_ventas())$rb$);
  if v_veces <> 1 then raise exception 'rollback F5.c: ancla-gate de public.crear_contrato(jsonb,jsonb) aparece % veces', v_veces; end if;
  v_def := replace(v_def, $rb$(select private.puede_registrar_ventas())$rb$, $rb$(
    v_es_analista or v_es_gestor_cartera or v_es_gerencia_crm or v_es_crm_catalogado
  ) or not private.puede_gestionar_cuentas_cliente(v_cliente_id)$rb$);
  v_veces := (length(v_def) - length(replace(v_def, $rb$where p.id = v_cliente_id and p.rol = 'cliente' and p.activo$rb$, ''))) / length($rb$where p.id = v_cliente_id and p.rol = 'cliente' and p.activo$rb$);
  if v_veces <> 1 then raise exception 'rollback F5.c: ancla-activo de public.crear_contrato(jsonb,jsonb) aparece % veces', v_veces; end if;
  v_def := replace(v_def, $rb$where p.id = v_cliente_id and p.rol = 'cliente' and p.activo$rb$, $rb$where p.id = v_cliente_id and p.rol = 'cliente'$rb$);
  execute v_def;
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = 'public.actualizar_contrato(uuid,jsonb,jsonb)'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$not (select private.puede_registrar_ventas())$rb$, ''))) / length($rb$not (select private.puede_registrar_ventas())$rb$);
  if v_veces <> 1 then raise exception 'rollback F5.c: ancla de public.actualizar_contrato(uuid,jsonb,jsonb) aparece % veces', v_veces; end if;
  execute replace(v_def, $rb$not (select private.puede_registrar_ventas())$rb$, $rb$not private.puede_gestionar_cuentas_cliente(v_row.cliente_id)$rb$);
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$not (select private.puede_registrar_ventas())$rb$, ''))) / length($rb$not (select private.puede_registrar_ventas())$rb$);
  if v_veces <> 1 then raise exception 'rollback F5.c: ancla de crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb) aparece % veces', v_veces; end if;
  execute replace(v_def, $rb$not (select private.puede_registrar_ventas())$rb$, $rb$v_uid is null or not private.puede_gestionar_cuentas_cliente(v_cliente_id)$rb$);
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = 'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)'::regprocedure;
  v_veces := (length(v_def) - length(replace(v_def, $rb$not found or not (select private.puede_registrar_ventas())$rb$, ''))) / length($rb$not found or not (select private.puede_registrar_ventas())$rb$);
  if v_veces <> 1 then raise exception 'rollback F5.c: ancla de crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb) aparece % veces', v_veces; end if;
  execute replace(v_def, $rb$not found or not (select private.puede_registrar_ventas())$rb$, $rb$not found or not private.puede_gestionar_cuentas_cliente(v_cliente_id)$rb$);
end $$;

-- La pregunta vuelve a la version F5.b (mas estrecha): admin O miembro CRM.
create or replace function private.puede_registrar_ventas()
returns boolean language sql stable security definer set search_path to ''
as $f$
  select public.es_admin() or private.puede_gestionar_contratos_crm();
$f$;
revoke all on function private.puede_registrar_ventas() from public;

-- Las huellas del trinquete de vigencia (F5.a) vuelven a su valor pre-F5.c:
-- los cuerpos se restauraron byte-exact, asi que la exencion debe apuntar de
-- nuevo a la huella antigua o el guardian quedaria caduco.
update private.analista_vigencia_exenciones
   set huella = '4498215792dc3dd1192fe6b303871bbe',
       razon = 'Gatea por private.puede_gestionar_cuentas_cliente(), que exige la membresia del CRM sin revocar. La revocada rebota ahi antes de escribir una fila.'
 where objeto = 'public.crear_contrato(jsonb,jsonb)';
update private.analista_vigencia_exenciones
   set huella = 'ae74fcb7d0dd994e11bda80497fc7822',
       razon = 'La rama del ANALISTA cierra por private.puede_gestionar_cuentas_cliente(cliente_id), que exige la membresia sin revocar. (Su pregunta directa por membresia_crm_revocada guarda la otra rama, la de gestor de cartera y gerencia.)'
 where objeto = 'public.actualizar_contrato(uuid,jsonb,jsonb)';

do $$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure;
  if v_h is distinct from 'cf5ef9458610b8d74b9a501d9b69835f' then raise exception 'rollback F5.c: public.crear_contrato(jsonb,jsonb) no volvio a su huella (%)', v_h; end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'public.actualizar_contrato(uuid,jsonb,jsonb)'::regprocedure;
  if v_h is distinct from 'e3f2758b3149a69d9cac695397599c33' then raise exception 'rollback F5.c: public.actualizar_contrato(uuid,jsonb,jsonb) no volvio a su huella (%)', v_h; end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'::regprocedure;
  if v_h is distinct from '03993a1bf97f921f22a0cb171fdd878b' then raise exception 'rollback F5.c: crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb) no volvio a su huella (%)', v_h; end if;
  select md5(p.prosrc) into v_h from pg_proc p where p.oid = 'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)'::regprocedure;
  if v_h is distinct from '71d710b60975b19aa76aa7e76a481c29' then raise exception 'rollback F5.c: crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb) no volvio a su huella (%)', v_h; end if;

  -- Con cuerpos y huellas restaurados, el guardian de vigencia (F5.a) vuelve a
  -- verde: si algo quedo caduco, revienta y deshace el rollback.
  perform private.assert_analista_vigencia();
end $$;

commit;
