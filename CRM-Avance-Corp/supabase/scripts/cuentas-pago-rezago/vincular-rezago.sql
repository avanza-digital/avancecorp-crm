-- VINCULAR EL REZAGO, otra vez. GENERADO por generar-derivados.py: es la carga de
-- 20261001233019_crm_cuentas_pago_motivo_y_rezago.sql, sola y sin tocar ninguna función.
--
-- Cuándo: cuando Operaciones registre la cuenta que le faltaba a un contrato del rezago (o retire
-- la que sobraba) y ese contrato pase a tener UNA sola cuenta activa en su moneda. Vincula
-- exactamente esos contratos; a los demás no los toca. Lanzarlo sin nada que vincular no cambia nada.
-- Se niega si el bloqueo o el diagnóstico vivos no son los de la migración: la regla que aplica
-- tiene que ser la que se ensayó.
--   supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/vincular-rezago.sql
-- La constancia de una corrida anterior en esta misma sesión se vacía ANTES del begin (esa
-- sentencia se confirma sola): si esta corrida se niega, la fila final sale vacía, no repetida.
select pg_catalog.set_config('crm.rezago_vinculos_resultado', '', false);
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  -- La carga decide con lo que lee DESPUÉS de tomar sus candados: solo vale en READ COMMITTED.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'VINCULAR: la transacción debe ir en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
  if (select pg_catalog.count(*)
      from (values
        ('private.exigir_cuenta_pago_cronograma()', 'd7618dcf85653943e62745513b3c4938'),
        ('private.cuenta_pago_diagnostico(uuid[])', 'a1dfb0c46b9365df308801bab9d5481a'),
        ('private.cuentas_pago_motivos_autorizado(uuid[])', '4c45dbbfd85f5de82372b343b0b1dfc0'),
        ('crm.cuentas_pago_motivos_fn(uuid[])', '45898bb671a3bf536375a0fb5fb33ec6')
      ) as f(firma, huella)
      join pg_catalog.pg_proc p on p.oid = pg_catalog.to_regprocedure(f.firma)
      where pg_catalog.md5(p.prosrc) = f.huella) <> 4 then
    raise exception 'VINCULAR: el bloqueo o el diagnóstico vivos no son los de la migración 20261001233019; no se toca nada';
  end if;
  if pg_catalog.to_regclass('private.backfill_cuentas_p0xx') is null
     or pg_catalog.to_regclass('private.conciliacion_cuentas_p0xx') is null then
    raise exception 'VINCULAR: faltan las tablas de rastro o de conciliación';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = 'crm.contrato_cuentas_pago'::regclass
        and t.tgname in ('trg_contrato_cuenta_pago_coherente', 'trg_audit_contrato_cuentas_pago')
        and t.tgenabled = 'O') <> 2 then
    raise exception 'VINCULAR: faltan los triggers de coherencia o de bitácora del vínculo';
  end if;
  if not coalesce((select r.rolbypassrls from pg_catalog.pg_roles r where r.rolname = current_user), false) then
    raise exception 'VINCULAR: quien lo lanza debe poder leer contratos, vínculos y cuentas sin RLS';
  end if;
end;
$precondicion$;

-- ── 4. Carga del rezago: solo donde hay UNA cuenta activa posible ────────────────────────────
-- Candados. La tabla de cuentas en modo EXCLUSIVE, antes que nada: espera a que termine quien
-- esté registrando, cambiando o retirando una cuenta (esos caminos bloquean primero la fila de la
-- cuenta y después escriben; tomar aquí un candado más débil permitiría un abrazo mortal) y,
-- mientras dura la carga, nadie mueve cuentas. Las lecturas siguen permitidas: registrar un pago
-- solo LEE cuentas. Después, cada contrato FOR SHARE —el orden de un pago: contrato → vínculo— y
-- bajo ese candado se vuelve a clasificar. Como en S1, no se toma el candado consultivo del alta.
-- Si la espera pasa de lock_timeout, se cancela todo sin dejar nada a medias.
lock table crm.cuentas_bancarias in exclusive mode;

do $rezago$
declare
  -- Cada relanzamiento deja su propia marca (día de Lima): no se confunde con la carga de la migración.
  c_marca constant text := 'carga:rezago-vinculos:'
    || pg_catalog.to_char(pg_catalog.now() at time zone 'America/Lima', 'YYYYMMDD');
  -- El rezago conocido es de 23 contratos (censo del 01/10/2026). Más candidatos que eso no es
  -- rezago: es que algo cambió (p. ej. vínculos borrados) y no se vincula a ciegas.
  c_tope constant integer := 23;
  v_antes jsonb;
  v_despues jsonb;
  v_candidatos integer;
  v_hechos integer := 0;
  v_rastro integer;
  v_discrepancias integer;
  v_fila record;
  v_d record;
  v_cuenta uuid;
  v_vinculo uuid;
  v_numeros text[] := '{}';
begin
  select coalesce(pg_catalog.jsonb_object_agg(s.caso, s.n), '{}'::jsonb) into v_antes
  from (select d.caso, pg_catalog.count(*) as n
        from private.cuenta_pago_diagnostico() d group by d.caso) s;

  v_candidatos := coalesce((v_antes ->> 'una_cuenta')::integer, 0);
  if v_candidatos > c_tope then
    raise exception 'REZAGO: % contratos por vincular y el rezago conocido es de %; no se toca nada',
      v_candidatos, c_tope;
  end if;

  for v_fila in
    select d.contrato_id
    from private.cuenta_pago_diagnostico() d
    where d.caso = 'una_cuenta'
    order by d.contrato_id
  loop
    perform 1 from public.contratos ct where ct.id = v_fila.contrato_id for share;

    select d.cliente_id, d.moneda, d.numero_contrato into v_d
    from private.cuenta_pago_diagnostico(array[v_fila.contrato_id]) d
    where d.caso = 'una_cuenta';
    if not found then
      continue;
    end if;

    -- La guarda de S1: si el perfil legado de ese cliente y moneda quedó marcado con una
    -- instrucción inválida o distinta para el mismo CCI, la única cuenta no es inequívoca.
    if exists (
      select 1 from private.conciliacion_cuentas_p0xx x
      where x.clase = 'perfil' and x.cliente_id = v_d.cliente_id and x.moneda = v_d.moneda
        and x.motivo in ('perfil_invalido', 'mismo_cci_datos_distintos')
    ) then
      raise exception 'REZAGO: el contrato % tiene una sola cuenta, pero su perfil legado quedó en conciliación; no se vincula nada hasta que Operaciones lo confirme',
        v_d.numero_contrato;
    end if;

    -- STRICT: si no es exactamente una, la migración entera se cancela.
    select cb.id into strict v_cuenta
    from crm.cuentas_bancarias cb
    where cb.cliente_id = v_d.cliente_id
      and cb.moneda = v_d.moneda
      and cb.activa is true;

    -- El trigger de coherencia cancela toda la migración si la pareja no vale.
    insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id, creado_por)
    values (v_fila.contrato_id, v_cuenta, null)
    returning id into v_vinculo;

    insert into private.backfill_cuentas_p0xx (tipo, fila_id, cliente_id, contrato_id, marca_actor)
    values ('vinculo', v_vinculo, v_d.cliente_id, v_fila.contrato_id, c_marca);

    v_hechos := v_hechos + 1;
    v_numeros := v_numeros || v_d.numero_contrato;
  end loop;

  select coalesce(pg_catalog.jsonb_object_agg(s.caso, s.n), '{}'::jsonb) into v_despues
  from (select d.caso, pg_catalog.count(*) as n
        from private.cuenta_pago_diagnostico() d group by d.caso) s;

  -- Nada de pérdida silenciosa: si el antes y el después no cuadran, se cancela todo.
  if v_hechos <> v_candidatos then
    raise exception 'REZAGO: había % contratos por vincular y se vincularon %', v_candidatos, v_hechos;
  end if;
  if coalesce((v_despues ->> 'una_cuenta')::integer, 0) <> 0 then
    raise exception 'REZAGO: quedaron contratos con una sola cuenta posible sin vincular: %', v_despues;
  end if;
  if coalesce((v_despues ->> 'ok')::integer, 0) <> coalesce((v_antes ->> 'ok')::integer, 0) + v_hechos then
    raise exception 'REZAGO: los contratos ok no subieron en lo vinculado (antes %, después %, vinculados %)',
      v_antes, v_despues, v_hechos;
  end if;
  if (v_despues - 'ok' - 'una_cuenta') is distinct from (v_antes - 'ok' - 'una_cuenta') then
    raise exception 'REZAGO: cambió un caso que la carga no debía tocar (antes %, después %)', v_antes, v_despues;
  end if;
  select pg_catalog.count(*) into v_rastro
  from private.backfill_cuentas_p0xx b
  join crm.contrato_cuentas_pago l on l.id = b.fila_id and l.contrato_id = b.contrato_id
  join crm.cuentas_bancarias cb on cb.id = l.cuenta_bancaria_id and cb.cliente_id = b.cliente_id and cb.activa is true
  where b.tipo = 'vinculo' and b.marca_actor = c_marca and b.revertida_en is null
    and b.insertada_en = pg_catalog.now();
  if v_rastro <> v_hechos then
    raise exception 'REZAGO: el rastro (%) no coincide con los vínculos creados (%)', v_rastro, v_hechos;
  end if;
  -- La regla vive en dos sitios (la consulta del bloqueo y el caso 'ok' del diagnóstico): con los
  -- contratos reales delante, no puede haber ni uno en que digan cosas distintas.
  select pg_catalog.count(*) into v_discrepancias
  from private.cuenta_pago_diagnostico() d
  where (d.caso = 'ok') is distinct from exists (
    select 1
    from crm.contrato_cuentas_pago cp
    join public.contratos ct on ct.id = cp.contrato_id
    join crm.cuentas_bancarias cb on cb.id = cp.cuenta_bancaria_id
    where cp.contrato_id = d.contrato_id
      and cb.cliente_id = ct.cliente_id
      and cb.moneda = ct.moneda);
  if v_discrepancias <> 0 then
    raise exception 'REZAGO: en % contratos el diagnóstico y el bloqueo no dicen lo mismo', v_discrepancias;
  end if;

  -- Para la última sentencia del archivo (después del COMMIT): el conteo antes y después.
  perform pg_catalog.set_config('crm.rezago_vinculos_resultado',
    pg_catalog.jsonb_build_object('antes', v_antes, 'despues', v_despues,
      'vinculados', v_hechos, 'contratos', pg_catalog.to_jsonb(v_numeros), 'marca', c_marca)::text, false);
  raise notice 'REZAGO: antes % · después % · vinculados % %', v_antes, v_despues, v_hechos, v_numeros;
end;
$rezago$;

commit;

-- Constancia del conteo por caso antes y después de ESTA corrida (queda en la salida).
select nullif(pg_catalog.current_setting('crm.rezago_vinculos_resultado', true), '')::jsonb as rezago_vinculos;
