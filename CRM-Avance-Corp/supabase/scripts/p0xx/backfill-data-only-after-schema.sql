-- P-0XX: SOLO DATOS. Preparado para un despliegue de esquema seguro y revisado.
-- No ejecutar junto al Merge Request actual: su diff contiene DROPs ajenos.
-- Fuente: migracion S1, bloque DO $backfill$ (sin modificaciones).
-- Requiere private.validar_cuenta_bancaria, las dos tablas de control,
-- origen=perfil, y los triggers de coherencia/auditoria ya instalados.
-- Inserciones con creado_por NULL y marca_actor='migracion:p0xx:s1'.
-- Solo Miguel, tras autorizacion explicita de DML productivo.
-- Los contratos ambiguos o sin cuenta quedan en conciliacion.
-- SHA256 del bloque fuente: 0722f312fc691bd1bee0b20d96ad66d26b03522bab7da7f8ab697728f4b355ba
begin;
set local lock_timeout = '10s';
set local statement_timeout = '15min';
lock table crm.cuentas_bancarias in share row exclusive mode;

do $backfill$
declare
  v_cliente_id uuid;
  v_perfil public.perfiles%rowtype;
  v_moneda text;
  v_banco text;
  v_tipo text;
  v_numero text;
  v_cci text;
  v_titular boolean;
  v_beneficiario_nombre text;
  v_beneficiario_dni text;
  v_normalizada jsonb;
  v_actual crm.cuentas_bancarias%rowtype;
  v_cuenta_id uuid;
  v_contrato_id uuid;
  v_contrato public.contratos%rowtype;
  v_candidatas bigint;
  v_vinculo_id uuid;
begin
  delete from private.conciliacion_cuentas_p0xx;
  for v_cliente_id in
    select p.id from public.perfiles p where p.rol = 'cliente' order by p.id
  loop
    select p.* into v_perfil from public.perfiles p
    where p.id = v_cliente_id and p.rol = 'cliente' for share;
    if not found then continue; end if;

    foreach v_moneda in array array['PEN', 'USD'] loop
      if v_moneda = 'PEN' then
        v_banco := v_perfil.banco;
        v_tipo := v_perfil.tipo_cuenta;
        v_numero := v_perfil.numero_cuenta;
        v_cci := v_perfil.cci;
        v_titular := v_perfil.titular_distinto;
        v_beneficiario_nombre := v_perfil.beneficiario_nombre;
        v_beneficiario_dni := v_perfil.beneficiario_dni;
      else
        v_banco := v_perfil.banco_usd;
        v_tipo := v_perfil.tipo_cuenta_usd;
        v_numero := v_perfil.numero_cuenta_usd;
        v_cci := v_perfil.cci_usd;
        v_titular := v_perfil.titular_distinto_usd;
        v_beneficiario_nombre := v_perfil.beneficiario_nombre_usd;
        v_beneficiario_dni := v_perfil.beneficiario_dni_usd;
      end if;
      if v_banco is null and v_tipo is null and v_numero is null
         and v_cci is null and not coalesce(v_titular, false)
         and v_beneficiario_nombre is null and v_beneficiario_dni is null then
        continue;
      end if;

      -- Una cadena legacy con espacios en sus identificadores no se corrige
      -- automaticamente: operaciones debe confirmar el dato original.
      if coalesce(v_numero, '') ~ '[[:space:]]'
         or coalesce(v_cci, '') ~ '[[:space:]]'
         or (coalesce(v_titular, false)
             and coalesce(v_beneficiario_dni, '') ~ '[[:space:]]') then
        insert into private.conciliacion_cuentas_p0xx
          (clase, cliente_id, moneda, motivo)
        values ('perfil', v_cliente_id, v_moneda, 'perfil_invalido');
        continue;
      end if;

      begin
        v_normalizada := private.validar_cuenta_bancaria(pg_catalog.jsonb_build_object(
          'banco', v_banco, 'tipo_cuenta', v_tipo,
          'numero_cuenta', v_numero, 'cci', v_cci,
          'titular_distinto', coalesce(v_titular, false),
          'beneficiario_nombre', v_beneficiario_nombre,
          'beneficiario_dni', v_beneficiario_dni));
      exception when sqlstate '22023' then
        insert into private.conciliacion_cuentas_p0xx
          (clase, cliente_id, moneda, motivo)
        values ('perfil', v_cliente_id, v_moneda, 'perfil_invalido');
        continue;
      end;

      v_cci := v_normalizada->>'cci';
      select cb.* into v_actual from crm.cuentas_bancarias cb
      where cb.cliente_id = v_cliente_id and cb.moneda = v_moneda
        and cb.cci = v_cci and cb.activa is true
      for update;
      if found then
        if pg_catalog.lower(v_actual.banco) = pg_catalog.lower(v_normalizada->>'banco')
           and v_actual.tipo_cuenta = v_normalizada->>'tipo_cuenta'
           and v_actual.numero_cuenta = v_normalizada->>'numero_cuenta'
           and v_actual.titular_distinto = (v_normalizada->>'titular_distinto')::boolean
           and v_actual.beneficiario_nombre is not distinct from v_normalizada->>'beneficiario_nombre'
           and v_actual.beneficiario_dni is not distinct from v_normalizada->>'beneficiario_dni' then
          continue;
        end if;
        -- La unicidad activa por CCI impide insertar sin reemplazar una cuenta
        -- CRM potencialmente contractual. Esa decision es manual.
        insert into private.conciliacion_cuentas_p0xx
          (clase, cliente_id, moneda, motivo)
        values ('perfil', v_cliente_id, v_moneda, 'mismo_cci_datos_distintos');
        continue;
      end if;

      insert into crm.cuentas_bancarias
        (cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci,
         titular_distinto, beneficiario_nombre, beneficiario_dni,
         activa, origen, creado_por)
      values
        (v_cliente_id, v_moneda, v_normalizada->>'banco',
         v_normalizada->>'tipo_cuenta', v_normalizada->>'numero_cuenta', v_cci,
         (v_normalizada->>'titular_distinto')::boolean,
         v_normalizada->>'beneficiario_nombre', v_normalizada->>'beneficiario_dni',
         true, 'perfil', null)
      returning id into v_cuenta_id;
      insert into private.backfill_cuentas_p0xx
        (tipo, fila_id, cliente_id)
      values ('cuenta', v_cuenta_id, v_cliente_id);
    end loop;
  end loop;

  insert into private.conciliacion_cuentas_p0xx
    (clase, cliente_id, moneda, motivo)
  select 'perfil', cb.cliente_id, cb.moneda, 'varias_activas'
  from crm.cuentas_bancarias cb
  where cb.activa is true
  group by cb.cliente_id, cb.moneda
  having pg_catalog.count(distinct cb.cci) > 1
     and pg_catalog.bool_or(cb.origen = 'perfil');

  for v_contrato_id in
    select ct.id from public.contratos ct
    where not exists (
      select 1 from crm.contrato_cuentas_pago cp where cp.contrato_id = ct.id)
    order by ct.id
  loop
    select ct.* into v_contrato from public.contratos ct
    where ct.id = v_contrato_id for share;
    if not found or exists (
      select 1 from crm.contrato_cuentas_pago cp where cp.contrato_id = v_contrato_id
    ) then continue; end if;

    -- Una sola fila CRM no es inequivoca si el perfil trae una instruccion
    -- invalida o datos distintos para el mismo CCI. El caso va a operaciones.
    if exists (
      select 1 from private.conciliacion_cuentas_p0xx x
      where x.clase = 'perfil' and x.cliente_id = v_contrato.cliente_id
        and x.moneda = v_contrato.moneda
        and x.motivo in ('perfil_invalido', 'mismo_cci_datos_distintos')
    ) then
      insert into private.conciliacion_cuentas_p0xx
        (clase, cliente_id, moneda, contrato_id, motivo)
      values ('contrato', v_contrato.cliente_id, v_contrato.moneda,
              v_contrato.id, 'perfil_conflictivo');
      continue;
    end if;

    select pg_catalog.count(*), (pg_catalog.array_agg(cb.id))[1]
      into v_candidatas, v_cuenta_id
    from crm.cuentas_bancarias cb
    where cb.cliente_id = v_contrato.cliente_id
      and cb.moneda = v_contrato.moneda and cb.activa is true;
    if v_candidatas = 1 then
      -- El trigger de coherencia aborta toda la migracion si la pareja no vale.
      insert into crm.contrato_cuentas_pago
        (contrato_id, cuenta_bancaria_id, creado_por)
      values (v_contrato.id, v_cuenta_id, null)
      returning id into v_vinculo_id;
      insert into private.backfill_cuentas_p0xx
        (tipo, fila_id, cliente_id, contrato_id)
      values ('vinculo', v_vinculo_id, v_contrato.cliente_id, v_contrato.id);
    else
      insert into private.conciliacion_cuentas_p0xx
        (clase, cliente_id, moneda, contrato_id, motivo)
      values ('contrato', v_contrato.cliente_id, v_contrato.moneda,
              v_contrato.id,
              case when v_candidatas = 0 then 'sin_cuenta' else 'cuentas_ambiguas' end);
    end if;
  end loop;
end;
$backfill$;

commit;
