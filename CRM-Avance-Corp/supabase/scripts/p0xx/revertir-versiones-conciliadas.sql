-- Reversa logica de conciliar-versiones.sql, con los mismos parametros/actor.
-- Conserva la historia: crea una version con los datos originales.
-- Rechaza cuentas ya reutilizadas en nuevos contratos o modificadas despues.
do $revertir_versiones$
declare
  v_casos jsonb := pg_catalog.current_setting('p0xx.casos_versionado')::jsonb;
  v_caso jsonb;
  v_ledger private.backfill_cuentas_p0xx%rowtype;
  v_actual crm.cuentas_bancarias%rowtype;
  v_original crm.cuentas_bancarias%rowtype;
  v_nueva uuid;
  v_restauradas integer := 0;
begin
  if current_user <> 'postgres' or (select auth.uid()) is null
     or not coalesce((select public.es_admin()),false)
     or pg_catalog.jsonb_typeof(v_casos) is distinct from 'array'
     or pg_catalog.jsonb_array_length(v_casos) <> 2
     or (select count(distinct x->>'cliente_id')
         from pg_catalog.jsonb_array_elements(v_casos) x) <> 2
     or (select count(distinct x->>'motivo')
         from pg_catalog.jsonb_array_elements(v_casos) x
         where x->>'motivo' in ('formato','titular')) <> 2 then
    raise exception 'P0XX: reversa no autorizada o lote invalido';
  end if;
  for v_caso in select x from pg_catalog.jsonb_array_elements(v_casos) x
      order by x->>'cliente_id'
  loop
    begin
      select b.* into strict v_ledger from private.backfill_cuentas_p0xx b
      where b.tipo='cuenta' and b.cliente_id=(v_caso->>'cliente_id')::uuid
        and b.marca_actor like 'conciliacion:p0xx:'||(v_caso->>'motivo')||':anterior=%'
        and b.revertida_en is null for update;
    exception when no_data_found then continue;
    end;
    select cb.* into strict v_original from crm.cuentas_bancarias cb
    where cb.id = pg_catalog.split_part(v_ledger.marca_actor,':anterior=',2)::uuid;
    perform 1 from public.perfiles p where p.id=v_original.cliente_id for share;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      v_original.cliente_id::text||'|PEN|'||v_original.cci,0));
    select cb.* into strict v_actual from crm.cuentas_bancarias cb
    where cb.id=v_ledger.fila_id for update;
    if v_actual.activa is not true
       or v_original.moneda <> 'PEN'
       or v_actual.moneda <> 'PEN'
       or v_original.activa is not false
       or v_actual.cliente_id <> (v_caso->>'cliente_id')::uuid
       or v_actual.cliente_id <> v_original.cliente_id
       or v_actual.cci <> v_original.cci
       or pg_catalog.md5(private.validar_cuenta_bancaria(
         pg_catalog.to_jsonb(v_actual))::text) is distinct from v_caso->>'huella_perfil'
       or pg_catalog.md5(private.validar_cuenta_bancaria(
         pg_catalog.to_jsonb(v_original))::text) is distinct from v_caso->>'huella_cuenta'
       or exists (select 1 from crm.contrato_cuentas_pago cp
         where cp.cuenta_bancaria_id=v_actual.id) then
      raise exception 'P0XX: la cuenta fue modificada o reutilizada; reversa manual';
    end if;
    v_nueva := crm.registrar_cuenta_cliente(v_actual.cliente_id,
      private.validar_cuenta_bancaria(pg_catalog.to_jsonb(v_original))
        || pg_catalog.jsonb_build_object('moneda','PEN'));
    insert into private.backfill_cuentas_p0xx
      (tipo,fila_id,cliente_id,marca_actor)
    values ('cuenta',v_nueva,v_actual.cliente_id,
      'reversa:p0xx:conciliacion:anterior='||v_actual.id::text);
    update private.backfill_cuentas_p0xx set revertida_en=pg_catalog.clock_timestamp()
    where tipo=v_ledger.tipo and fila_id=v_ledger.fila_id;
    v_restauradas := v_restauradas + 1;
  end loop;
  perform pg_catalog.set_config('p0xx.resultado_reversa',v_restauradas::text,true);
end;
$revertir_versiones$;
