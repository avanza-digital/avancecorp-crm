-- MARCHA ATRAS de la F7.2 — reabre el interruptor legacy y retira su acta.
--
-- ⚠️ La fila 20260901200000 del registro NO se borra aqui: retirarla A MANO.
-- ⚠️ Reabrir el interruptor NO lo vuelve peligroso: sigue siendo inejecutable
--    mientras no exista una condicion de producto no-legacy publicada.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $rb_pre$
declare v_acl text; v_n int;
begin
  select p.proacl::text into v_acl from pg_proc p
   where p.oid = 'crm.cerrar_altas_legacy_productos(bigint)'::regprocedure;
  if v_acl is distinct from '{postgres=X/postgres}' then
    raise exception 'rollback F7.2: el interruptor no esta como lo dejo la F7.2 (ACL %)', v_acl;
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = 'crm.cerrar_altas_legacy_productos(bigint)' and estado = 'observacion';
  if v_n <> 1 then
    raise exception 'rollback F7.2: su acta no esta en observacion — el mundo no es el que este guion revierte';
  end if;
end $rb_pre$;

grant execute on function crm.cerrar_altas_legacy_productos(bigint) to authenticated;

-- Retirar el acta: el trigger `no_borrar` lo prohibe salvo con el candado
-- NOMBRADO bajado (doctrina limpieza-leads), y se vuelve a subir aqui mismo.
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_01_no_borrar;
delete from private.f7_piezas_en_observacion
 where firma = 'crm.cerrar_altas_legacy_productos(bigint)';
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_01_no_borrar;

do $rb_post$
declare v_acl text; v_n int; v_verd text;
begin
  select p.proacl::text into v_acl from pg_proc p
   where p.oid = 'crm.cerrar_altas_legacy_productos(bigint)'::regprocedure;
  if v_acl is distinct from '{postgres=X/postgres,authenticated=X/postgres}' then
    raise exception 'rollback F7.2: el ACL no volvio al original (%)', v_acl;
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion;
  if v_n <> 14 then
    raise exception 'rollback F7.2: el libro tiene % piezas, esperaba 14', v_n;
  end if;
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'rollback F7.2: vigilante F7 en rojo: %', v_verd; end if;
end $rb_post$;

select 'ROLLBACK-F7.2-OK: interruptor reabierto y acta retirada' as resultado;
commit;
