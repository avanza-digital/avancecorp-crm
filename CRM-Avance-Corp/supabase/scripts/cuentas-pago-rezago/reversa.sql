-- REVERSA COMPLETA de 20261001233019_crm_cuentas_pago_motivo_y_rezago.sql: datos y código. GENERADA por generar-derivados.py.
--   · Borra SOLO los vínculos que creó la carga de la migración (marca 'migracion:rezago-vinculos:20261001'
--     en private.backfill_cuentas_p0xx) y les pone revertida_en. La bitácora (public.audit_log)
--     guarda el borrado. Los vínculos de cargas posteriores (vincular-rezago.sql, otra marca) no se tocan.
--   · Repone el bloqueo anterior y quita las tres funciones nuevas (si el código ya se revirtió
--     con reversa-solo-codigo.sql, esta parte no cambia nada).
-- Se NIEGA, sin cambiar nada, si algún contrato vinculado por la carga ya registró un pago
-- (crm.cuotas_cuenta_pagada), un cambio de cuenta (crm.contrato_cuenta_pago_cambios) o un PDF de
-- contrato (su fotografía lleva la cuenta): desde ese momento el vínculo es una instrucción usada
-- y no se borra. Para volver solo al mensaje anterior sin tocar vínculos: reversa-solo-codigo.sql.
-- Solo Miguel, con autorización expresa. Nunca la ejecuta un revisor.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
declare
  v_huella text;
begin
  -- Se decide con lo que se lee DESPUÉS de tomar los candados: solo vale en READ COMMITTED.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'REVERSA: la transacción debe ir en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
  select pg_catalog.md5(p.prosrc) into v_huella
  from pg_catalog.pg_proc p
  where p.oid = pg_catalog.to_regprocedure('private.exigir_cuenta_pago_cronograma()');
  -- El de la migración, o el anterior si el código ya se revirtió.
  if v_huella is null or v_huella not in ('d7618dcf85653943e62745513b3c4938', '5efb8619e4342763ae77df2ee0bb1f61') then
    raise exception 'REVERSA: el bloqueo vivo (%) no es el de la migración 20261001233019 ni el anterior; no se toca',
      coalesce(v_huella, 'no existe');
  end if;
  if exists (
    select 1
    from (values
      ('private.cuenta_pago_diagnostico(uuid[])', 'a1dfb0c46b9365df308801bab9d5481a'),
      ('private.cuentas_pago_motivos_autorizado(uuid[])', '4c45dbbfd85f5de82372b343b0b1dfc0'),
      ('crm.cuentas_pago_motivos_fn(uuid[])', '45898bb671a3bf536375a0fb5fb33ec6')
    ) as f(firma, huella)
    join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(f.firma)
    where pg_catalog.md5(p.prosrc) <> f.huella
  ) then
    raise exception 'REVERSA: alguna función de la migración cambió después; no se toca';
  end if;
end;
$precondicion$;

do $datos$
declare
  c_marca constant text := 'migracion:rezago-vinculos:20261001';
  v_usado text;
  v_esperados integer;
  v_borrados integer;
begin
  if pg_catalog.to_regclass('crm.cuotas_cuenta_pagada') is null
     or pg_catalog.to_regclass('crm.contrato_cuenta_pago_cambios') is null
     or pg_catalog.to_regclass('private.contrato_pdf_jobs') is null
     or pg_catalog.to_regclass('private.contrato_pdfs') is null then
    raise exception 'REVERSA: faltan las tablas con las que se sabe si un vínculo ya se usó; no se borra nada';
  end if;
  -- El criterio «ya registró un pago» depende de que cada pago selle su cuenta: los dos triggers
  -- del sello, habilitados y colgados de su función. (Que estén así AHORA no prueba que lo
  -- estuvieran siempre: si alguna vez se apagaron, esta reversa no se usa sin revisar los pagos.)
  if pg_catalog.to_regprocedure('private.sellar_cuenta_cuota_pagada()') is null
     or (select pg_catalog.count(*) from pg_catalog.pg_trigger t
         where t.tgrelid = 'public.cronograma_pagos'::regclass
           and t.tgname in ('trg_cronograma_pagos_20_sellar_cuenta_insert',
                            'trg_cronograma_pagos_20_sellar_cuenta_update')
           and t.tgfoid = pg_catalog.to_regprocedure('private.sellar_cuenta_cuota_pagada()')
           and t.tgenabled = 'O') <> 2 then
    raise exception 'REVERSA: los triggers que sellan la cuenta de cada pago no están habilitados; no se puede saber si un vínculo ya se usó';
  end if;

  -- Candados en el orden de un pago: el contrato primero (FOR UPDATE, por id). Un pago en curso
  -- termina antes; uno nuevo espera y, al seguir, ya no encuentra el vínculo y se rechaza.
  perform 1
  from public.contratos ct
  where ct.id in (select b.contrato_id from private.backfill_cuentas_p0xx b
                  where b.tipo = 'vinculo' and b.marca_actor = c_marca and b.revertida_en is null)
  order by ct.id
  for update;

  select ct.numero_contrato into v_usado
  from private.backfill_cuentas_p0xx b
  join public.contratos ct on ct.id = b.contrato_id
  where b.tipo = 'vinculo' and b.marca_actor = c_marca and b.revertida_en is null
    and (exists (select 1 from crm.cuotas_cuenta_pagada q where q.contrato_id = b.contrato_id)
         or exists (select 1 from crm.contrato_cuenta_pago_cambios c where c.contrato_id = b.contrato_id)
         or exists (select 1 from private.contrato_pdf_jobs j where j.contrato_id = b.contrato_id)
         or exists (select 1 from private.contrato_pdfs p where p.contrato_id = b.contrato_id))
  order by ct.numero_contrato
  limit 1;
  if v_usado is not null then
    raise exception 'REVERSA: el contrato % ya registró un pago, un cambio de cuenta o un PDF con su vínculo; no se borra nada. Para volver solo al mensaje anterior usa reversa-solo-codigo.sql', v_usado;
  end if;

  -- Se esperan tantos borrados como vínculos de la carga cuyo contrato sigue existiendo (un
  -- contrato eliminado ya se llevó su vínculo en cascada).
  select pg_catalog.count(*) into v_esperados
  from private.backfill_cuentas_p0xx b
  where b.tipo = 'vinculo' and b.marca_actor = c_marca and b.revertida_en is null
    and exists (select 1 from public.contratos ct where ct.id = b.contrato_id);

  delete from crm.contrato_cuentas_pago l
  using private.backfill_cuentas_p0xx b
  where b.tipo = 'vinculo' and b.marca_actor = c_marca and b.revertida_en is null
    and l.id = b.fila_id and l.contrato_id = b.contrato_id;
  get diagnostics v_borrados = row_count;
  if v_borrados <> v_esperados then
    raise exception 'REVERSA: se esperaban % vínculos de la carga y se encontraron %; no se borra nada',
      v_esperados, v_borrados;
  end if;

  update private.backfill_cuentas_p0xx
     set revertida_en = pg_catalog.now()
   where tipo = 'vinculo' and marca_actor = c_marca and revertida_en is null;

  raise notice 'REVERSA: % vínculos de la carga borrados', v_borrados;
end;
$datos$;

-- El bloqueo de antes, byte a byte: texto fuente de 20260925194026 (el postflight lo comprueba por md5).
create or replace function private.exigir_cuenta_pago_cronograma()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.estado is distinct from 'pagado' then
    return new;
  end if;

  -- La cuenta vinculada puede haber sido versionada y estar inactiva: sigue
  -- siendo la instruccion contractual. Bloqueamos la fila del vinculo y del
  -- contrato hasta el COMMIT para no validar una fotografia que se borra o
  -- cambia de cliente/moneda durante el registro del pago.
  perform 1
  from crm.contrato_cuentas_pago cp
  join public.contratos ct on ct.id = cp.contrato_id
  join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
  where cp.contrato_id = new.contrato_id
    and cb.cliente_id = ct.cliente_id
    and cb.moneda = ct.moneda
  for share of cp, ct;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'Sin cuenta de pago — requiere conciliación';
  end if;
  return new;
end;
$function$;
comment on function private.exigir_cuenta_pago_cronograma() is null;

-- Las tres funciones nuevas (la puerta primero). El portal tolera que la puerta no exista: vuelve
-- al texto genérico.
drop function if exists crm.cuentas_pago_motivos_fn(uuid[]);
drop function if exists private.cuentas_pago_motivos_autorizado(uuid[]);
drop function if exists private.cuenta_pago_diagnostico(uuid[]);

-- Sin su código la migración ya no está aplicada: que el registro de versiones tampoco lo diga
-- (volver a aplicarla y a registrarla funciona igual).
do $registro$
begin
  if pg_catalog.to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'delete from supabase_migrations.schema_migrations where version = '
      || pg_catalog.quote_literal('20261001233019');
  end if;
end;
$registro$;

do $postflight$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
      where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure)
     is distinct from '5efb8619e4342763ae77df2ee0bb1f61' then
    raise exception 'REVERSA POSTFLIGHT: el bloqueo no volvió al cuerpo anterior';
  end if;
  if not exists (select 1 from pg_catalog.pg_proc p
                 where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
                   and p.prosecdef and p.proconfig @> array['search_path=""'])
     or exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
                  and a.grantee <> p.proowner)
     or (select p.proacl is null from pg_catalog.pg_proc p
         where p.oid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure) then
    raise exception 'REVERSA POSTFLIGHT: DEFINER, search_path o EXECUTE del bloqueo no quedaron como antes';
  end if;
  if pg_catalog.to_regprocedure('crm.cuentas_pago_motivos_fn(uuid[])') is not null
     or pg_catalog.to_regprocedure('private.cuentas_pago_motivos_autorizado(uuid[])') is not null
     or pg_catalog.to_regprocedure('private.cuenta_pago_diagnostico(uuid[])') is not null then
    raise exception 'REVERSA POSTFLIGHT: quedó alguna función de la migración';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'public.cronograma_pagos'::regclass
        and t.tgname in ('trg_cronograma_pagos_10_exigir_cuenta_pago_insert',
                         'trg_cronograma_pagos_10_exigir_cuenta_pago_update')
        and t.tgfoid = 'private.exigir_cuenta_pago_cronograma()'::regprocedure
        and t.tgenabled = 'O') <> 2 then
    raise exception 'REVERSA POSTFLIGHT: los triggers del bloqueo de pagos no quedaron como estaban';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
