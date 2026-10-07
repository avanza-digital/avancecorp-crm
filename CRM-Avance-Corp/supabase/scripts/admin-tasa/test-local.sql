-- Ejecutar después de la migración dentro de BEGIN/ROLLBACK en un banco local.
-- Ningún resultado se persiste.
alter table crm.productos_inversion disable trigger trg_productos_inversion_inmutables;
alter table crm.politica_rentabilidad disable trigger trg_politica_rentabilidad_inmutable;
update crm.politica_rentabilidad set modo='enforcement'
  where version=(select max(version) from crm.politica_rentabilidad);
alter table crm.politica_rentabilidad enable trigger trg_politica_rentabilidad_inmutable;
-- El fixture no tiene domicilio ni cuenta de pago y no puede producir un PDF
-- válido. Se conserva el wrapper de revisión, pero se simula régimen anterior.
-- La generación documental completa requiere su banco de integración propio.
create or replace function private.contrato_documental_regimen(p_contrato_id uuid)
returns text language sql stable security definer set search_path = ''
as $$ select 'anterior'::text $$;
do $prueba$
declare
  v_admin uuid;
  v_analista uuid;
  v_contrato public.contratos%rowtype;
  v_payload jsonb;
  v_cronograma jsonb;
  v_resultado jsonb;
begin
  if has_function_privilege('anon',
       'crm.corregir_tasa_contrato_admin_pdf_v1(uuid,jsonb,jsonb,text,numeric)', 'EXECUTE')
     or not has_function_privilege('authenticated',
       'crm.corregir_tasa_contrato_admin_pdf_v1(uuid,jsonb,jsonb,text,numeric)', 'EXECUTE') then
    raise exception 'FAIL: grants de la RPC incorrectos';
  end if;
  select id into strict v_admin from public.perfiles
    where rol = 'admin' and activo order by id limit 1;
  select id into strict v_analista from public.perfiles
    where rol = 'analista' and activo order by id limit 1;
  select c.* into strict v_contrato from public.contratos c
    join crm.producto_condiciones pc on pc.id = c.producto_condicion_id
    where c.estado = 'activo' and c.tasa_anual = 12
      and pc.tasa_minima <= 13 and pc.tasa_maxima >= 13
      and c.fecha_vencimiento = (c.fecha_inicio + make_interval(months=>pc.plazo_meses))::date
    order by c.id limit 1;
  -- El fixture local vincula contratos catalogados a un producto técnico
  -- archivado. Adaptarlo solo en este ROLLBACK permite probar la ruta real.
  update crm.productos_inversion p
    set estado='activo', es_legacy=false, permite_altas_legacy=false,
        archivado_en=null, archivado_por=null
    where p.id = (
      select v.producto_id from crm.producto_condiciones pc
      join crm.producto_versiones v on v.id=pc.version_id
      where pc.id=v_contrato.producto_condicion_id
    );
  execute 'alter table crm.productos_inversion enable trigger trg_productos_inversion_inmutables';

  v_payload := jsonb_build_object(
    'cliente_id', v_contrato.cliente_id,
    'numero_contrato', v_contrato.numero_contrato,
    'capital', v_contrato.capital,
    'moneda', v_contrato.moneda,
    'tasa_anual', 13,
    'modalidad', v_contrato.modalidad,
    'tipo_interes', v_contrato.tipo_interes,
    'fecha_inicio', v_contrato.fecha_inicio,
    'fecha_vencimiento', v_contrato.fecha_vencimiento,
    'categoria', v_contrato.categoria,
    'notas_internas', v_contrato.notas_internas
  );
  v_cronograma := jsonb_build_array(jsonb_build_object(
    'numero_cuota', 1,
    'fecha_programada', v_contrato.fecha_vencimiento,
    'monto_programado', 130,
    'tipo', 'cuota'
  ));

  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform crm.corregir_tasa_contrato_admin_pdf_v1(
      v_contrato.id, v_payload, v_cronograma, 'Motivo de prueba local', 12
    );
    raise exception 'FAIL: una sesión anónima corrigió la tasa';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claim.sub', v_analista::text, true);
  begin
    perform crm.corregir_tasa_contrato_admin_pdf_v1(
      v_contrato.id, v_payload, v_cronograma, 'Motivo de prueba local', 12
    );
    raise exception 'FAIL: un analista corrigió la tasa sin Gerencia';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  begin
    perform crm.corregir_tasa_contrato_admin_pdf_v1(
      v_contrato.id, v_payload, v_cronograma, 'no', 12
    );
    raise exception 'FAIL: se aceptó un motivo insuficiente';
  exception when sqlstate '22023' then null;
  end;

  begin
    perform crm.corregir_tasa_contrato_admin_pdf_v1(
      v_contrato.id, v_payload, v_cronograma, 'Motivo válido pero tasa obsoleta', 11
    );
    raise exception 'FAIL: una vista obsoleta sobrescribió la tasa';
  exception when sqlstate '22023' then null;
  end;

  begin
    perform crm.corregir_tasa_contrato_admin_pdf_v1(
      v_contrato.id, jsonb_set(v_payload, '{capital}', to_jsonb(v_contrato.capital + 100)),
      v_cronograma, 'Motivo válido pero también cambió el capital', 12
    );
    raise exception 'FAIL: capital y tasa cambiaron juntos sin Gerencia';
  exception when sqlstate '22023' then null;
  end;

  v_resultado := crm.corregir_tasa_contrato_admin_pdf_v1(
    v_contrato.id, v_payload, v_cronograma, 'Corrección administrativa probada localmente', 12
  );
  -- El observador es diferido; se fuerza mientras la marca de la RPC sigue
  -- activa para comprobar la misma decisión que tomará al COMMIT.
  execute 'set constraints trg_contratos_zz_observar_rentabilidad immediate';
  if coalesce((v_resultado ->> 'ok')::boolean, false) is not true then
    raise exception 'FAIL: la RPC no confirmó la corrección';
  end if;
  if (select tasa_anual from public.contratos where id=v_contrato.id) <> 13 then
    raise exception 'FAIL: la tasa no cambió';
  end if;
  if not exists (
    select 1 from public.cronograma_pagos p
    where p.contrato_id = v_contrato.id and p.monto_programado = 130
  ) then raise exception 'FAIL: el cronograma no quedó actualizado'; end if;
  if not exists (
    select 1 from crm.ledger_rentabilidad l
    where l.contrato_id = v_contrato.id
      and l.detalle ->> 'motivo_correccion_admin' = 'Corrección administrativa probada localmente'
  ) then raise exception 'FAIL: falta el motivo en el ledger'; end if;

  raise notice 'PASS: rol, motivo, tasa, cronograma y ledger con política enforcement';
end;
$prueba$;
