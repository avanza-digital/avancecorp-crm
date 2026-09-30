-- REVERSA de 20260926204051_crm_cambio_cuenta_pago (F3.1).
-- Se NIEGA si ya hay cambios de cuenta registrados (desde ese momento el historial es la única
-- verdad de a dónde se paga cada contrato), si ya hay pagos sellados al registrarse (su constancia
-- se perdería: pasado el primer pago, revertir exige una migración que conserve los datos) o si
-- las piezas vivas no son las ensayadas (huella completa de las 16 funciones: cuerpo, DEFINER,
-- search_path, comentario y EXECUTE sin el dueño).
-- Repone el candado original del enlace contrato→cuenta byte a byte (huella 349a5a7f…).
-- El bucket 'respaldos-cambio-cuenta' se conserva (Storage no permite borrar buckets ni objetos
-- por SQL); sin sus políticas queda cerrado para todo usuario de la API.
begin;
set local lock_timeout = '5s';
do $pre$
declare
  v_funciones integer;
  v_huella text;
begin
  if to_regclass('crm.contrato_cuenta_pago_cambios') is null then
    raise exception 'REVERSA: la F3.1 no está aplicada';
  end if;
  if exists (select 1 from crm.contrato_cuenta_pago_cambios) then
    raise exception 'REVERSA: ya hay cambios de cuenta de pago registrados; no se revierte a ciegas';
  end if;
  -- Un pago sellado al registrarse es una constancia que no existía antes:
  -- revertir la borraría. Solo se admite con sellos 'inferido' (el backfill, que se rehace).
  if exists (select 1 from crm.cuotas_cuenta_pagada where origen <> 'inferido') then
    raise exception 'REVERSA: ya hay pagos sellados desde que se aplicó; revertir borraría su constancia';
  end if;
  select count(*), pg_catalog.md5(pg_catalog.string_agg(linea, E'\n' order by linea))
    into v_funciones, v_huella
  from (
    select p.oid::regprocedure::text || '|' || pg_catalog.md5(p.prosrc) || '|' || p.prosecdef::text || '|'
           || coalesce(pg_catalog.array_to_string(p.proconfig, ','), '-') || '|'
           || coalesce(pg_catalog.md5(pg_catalog.obj_description(p.oid, 'pg_proc')), '-') || '|'
           || coalesce((select pg_catalog.string_agg(g, ',' order by g)
                        from (select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
                                     || ':' || a.privilege_type as g
                              from pg_catalog.aclexplode(p.proacl) a
                              where a.grantee <> p.proowner) acl), '-') as linea
    from pg_catalog.pg_proc p
    where p.oid in (
      select to_regprocedure(f) from pg_catalog.unnest(array[
        'private.admin_banca_vigente(uuid)',
        'private.trg_registro_cuenta_pago_no_borrar()',
        'private.trg_contrato_cuenta_pago_cambios_inmutable()',
        'private.trg_cuotas_cuenta_pagada_solo_resello()',
        'private.sellar_cuenta_cuota_pagada()',
        'private.trg_contrato_cuenta_pago_inmutable()',
        'private.respaldo_cambio_cuenta_permitido(text)',
        'private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)',
        'crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text)',
        'private.contratos_cuenta_pago_cliente_autorizado(uuid)',
        'crm.contratos_cuenta_pago_cliente_fn(uuid)',
        'private.cambios_cuenta_pago_cliente_autorizado(uuid)',
        'crm.cambios_cuenta_pago_cliente_fn(uuid)',
        'private.contratos_vigentes_de_cambio(uuid)',
        'crm.reclamar_aviso_cambio_cuenta(uuid,uuid,boolean)',
        'crm.confirmar_aviso_cambio_cuenta(uuid,uuid,boolean,boolean,text)']) f)
  ) s;
  if v_funciones <> 16 or v_huella is distinct from '21bb1838606355e1161a44fb0b66e809' then
    raise exception 'REVERSA: las piezas vivas no son las de la F3.1 ensayada (% funciones, huella %); no se toca',
      v_funciones, v_huella;
  end if;
end $pre$;

-- Políticas del bucket (el bucket NO se borra por SQL: storage.protect_delete lo impide; sin
-- políticas queda cerrado; si hace falta, se elimina vacío desde el panel de Storage).
drop policy respaldo_cambio_cuenta_insert on storage.objects;
drop policy respaldo_cambio_cuenta_select on storage.objects;
drop policy respaldo_cambio_cuenta_insert_frontera on storage.objects;
drop policy respaldo_cambio_cuenta_select_frontera on storage.objects;
drop policy respaldo_cambio_cuenta_update_frontera on storage.objects;
drop policy respaldo_cambio_cuenta_delete_frontera on storage.objects;
drop policy respaldo_cambio_cuenta_anon_frontera on storage.objects;

-- Sello en public.cronograma_pagos.
drop trigger trg_cronograma_pagos_20_sellar_cuenta_insert on public.cronograma_pagos;
drop trigger trg_cronograma_pagos_20_sellar_cuenta_update on public.cronograma_pagos;

-- Operación, lecturas y aviso.
drop function crm.confirmar_aviso_cambio_cuenta(uuid, uuid, boolean, boolean, text);
drop function crm.reclamar_aviso_cambio_cuenta(uuid, uuid, boolean);
drop function private.contratos_vigentes_de_cambio(uuid);
drop function crm.cambios_cuenta_pago_cliente_fn(uuid);
drop function private.cambios_cuenta_pago_cliente_autorizado(uuid);
drop function crm.contratos_cuenta_pago_cliente_fn(uuid);
drop function private.contratos_cuenta_pago_cliente_autorizado(uuid);
drop function crm.cambiar_cuenta_pago_contratos(uuid,uuid,uuid,uuid[],text,text);
drop function private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text);
drop function private.respaldo_cambio_cuenta_permitido(text);
drop function private.sellar_cuenta_cuota_pagada();

-- Candado original del enlace (antes de retirar el historial al que la versión F3 consulta).
create or replace function private.trg_contrato_cuenta_pago_inmutable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if row(new.id, new.contrato_id, new.cuenta_bancaria_id, new.creado_en)
     is distinct from
     row(old.id, old.contrato_id, old.cuenta_bancaria_id, old.creado_en) then
    raise exception using
      errcode = '22023',
      message = 'La cuenta de pago del contrato es historica y no se reemplaza';
  end if;
  if new.creado_por is distinct from old.creado_por
     and not (
       new.creado_por is null
       and old.creado_por is not null
       and not exists (select 1 from public.perfiles p where p.id = old.creado_por)
     ) then
    raise exception using errcode = '22023', message = 'La autoria del enlace bancario es inmutable';
  end if;
  return new;
end;
$$;
comment on function private.trg_contrato_cuenta_pago_inmutable() is null;

-- Registros (sus triggers se van con ellos) y sus candados.
drop table crm.cambio_cuenta_avisos;
drop table crm.contrato_cuenta_pago_cambios;
drop table crm.cuotas_cuenta_pagada;
drop function private.trg_registro_cuenta_pago_no_borrar();
drop function private.trg_contrato_cuenta_pago_cambios_inmutable();
drop function private.trg_cuotas_cuenta_pagada_solo_resello();
drop function private.admin_banca_vigente(uuid);

do $chk$
begin
  if (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
      where oid = 'private.trg_contrato_cuenta_pago_inmutable()'::regprocedure)
     is distinct from '349a5a7f9a52283c5331aea6d90967f9' then
    raise exception 'REVERSA: el candado repuesto no es el original';
  end if;
  if exists (select 1 from pg_catalog.pg_policies where schemaname = 'storage' and policyname like 'respaldo\_cambio\_cuenta\_%')
     or exists (select 1 from pg_catalog.pg_trigger where tgrelid = 'public.cronograma_pagos'::regclass
                and tgname like 'trg\_cronograma\_pagos\_20\_sellar\_cuenta\_%')
     or to_regprocedure('private.admin_banca_vigente(uuid)') is not null then
    raise exception 'REVERSA: quedaron piezas de la F3.1';
  end if;
end $chk$;
notify pgrst, 'reload schema';
commit;
