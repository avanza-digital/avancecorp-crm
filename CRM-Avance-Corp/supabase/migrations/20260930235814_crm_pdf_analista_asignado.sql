-- El PDF usa el analista asignado al contrato, conservando creado_por como autoría.
-- Snapshot 3 separa ambas identidades. Los snapshots 2 y sus bytes siguen intactos.
-- Desplegar antes el renderer compatible con versiones 2 y 3 en crm-contrato-pdf-v2.
-- No cambia firmas, permisos, tablas, triggers, plantillas ni condiciones económicas.
-- Reversa: supabase/scripts/pdf-analista/reversa.sql. Mantener el renderer dual.

do $preflight$
declare r record;
begin
  for r in select * from (values
    ('private.contrato_pdf_snapshot_v2_base(uuid)','6f187b3cafc2090cc0bd19603d1f101c'),
    ('private.contrato_pdf_anexo_snapshot_base(uuid)','941a9ca9c279b16b2d7a20325f380f5c'),
    ('private.contrato_pdf_anexo_emitido_base(uuid,uuid,uuid,text,text,bigint)','e5892ba09181d7c54c58207e0ee0e7cc')
  ) as v(firma,huella) loop
    if md5(pg_get_functiondef(to_regprocedure(r.firma))) is distinct from r.huella then
      raise exception 'Dependencia PDF cambió: %',r.firma;
    end if;
  end loop;
end;
$preflight$;

CREATE OR REPLACE FUNCTION private.contrato_pdf_snapshot_v2_base(p_contrato_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_contrato public.contratos%rowtype;
  v_cliente public.perfiles%rowtype;
  v_analista public.perfiles%rowtype;
  v_cotitulares jsonb;
  v_cronograma jsonb;
  v_cuenta jsonb;
begin
  select * into strict v_contrato
  from public.contratos c
  where c.id = p_contrato_id;

  select * into strict v_cliente
  from public.perfiles p
  where p.id = v_contrato.cliente_id
    and p.rol = 'cliente';

  if v_contrato.analista_cierre_id is null then
    raise exception 'El contrato no tiene analista asignado para el PDF'
      using errcode = '23514';
  end if;

  select * into strict v_analista
  from public.perfiles p
  where p.id = v_contrato.analista_cierre_id;

  if nullif(btrim(v_contrato.numero_contrato), '') is null
     or nullif(btrim(v_cliente.nombre_completo), '') is null
     or nullif(btrim(v_cliente.tipo_documento), '') is null
     or nullif(btrim(v_cliente.dni), '') is null
     or nullif(btrim(v_cliente.domicilio), '') is null
     or nullif(btrim(v_cliente.correo), '') is null
     or nullif(btrim(v_analista.nombre_completo), '') is null
     or nullif(btrim(v_analista.dni), '') is null
     or nullif(btrim(v_analista.telefono), '') is null
     or nullif(btrim(v_analista.correo), '') is null then
    raise exception
      'Faltan datos legales obligatorios del titular o del analista'
      using errcode = '23514';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', t.id,
        'orden', t.orden,
        'nombreCompleto', t.nombre_completo,
        'tipoDocumento', upper(t.tipo_documento),
        'documento', t.documento
      ) order by t.orden, t.id
    ),
    '[]'::jsonb
  ) into v_cotitulares
  from public.contrato_titulares t
  where t.contrato_id = p_contrato_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', cp.id,
        'numeroCuota', cp.numero_cuota,
        'fechaProgramada', cp.fecha_programada::text,
        'montoProgramado', cp.monto_programado,
        'tipo', cp.tipo
      ) order by cp.numero_cuota, cp.id
    ),
    '[]'::jsonb
  ) into v_cronograma
  from public.cronograma_pagos cp
  where cp.contrato_id = p_contrato_id;

  if jsonb_array_length(v_cronograma) = 0 then
    raise exception 'El contrato no tiene cronograma contractual'
      using errcode = '23514';
  end if;

  select jsonb_build_object(
    'cuentaId', cb.id,
    'moneda', cb.moneda,
    'banco', cb.banco,
    'tipoCuenta', cb.tipo_cuenta,
    'numeroCuenta', cb.numero_cuenta,
    'cci', cb.cci,
    'titularDistinto', cb.titular_distinto,
    'beneficiarioNombre', cb.beneficiario_nombre,
    'beneficiarioDocumento', cb.beneficiario_dni,
    'origen', cb.origen
  ) into v_cuenta
  from crm.contrato_cuentas_pago ccp
  join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
  where ccp.contrato_id = p_contrato_id;

  if v_cuenta is null then
    raise exception 'El contrato no tiene una cuenta de pago contractual'
      using errcode = '23514';
  end if;

  return jsonb_build_object(
    'snapshotVersion', 3,
    'contrato', jsonb_build_object(
      'id', v_contrato.id,
      'numero', v_contrato.numero_contrato,
      'clienteId', v_contrato.cliente_id,
      'capital', v_contrato.capital,
      'moneda', v_contrato.moneda,
      'porcentaje', v_contrato.tasa_anual,
      'modalidad', v_contrato.modalidad,
      'tipoInteres', v_contrato.tipo_interes,
      'categoria', v_contrato.categoria,
      'fechaInicio', v_contrato.fecha_inicio::text,
      'fechaVencimiento', v_contrato.fecha_vencimiento::text,
      'productoCondicionId', v_contrato.producto_condicion_id,
      'creadoPor', v_contrato.creado_por,
      'analistaId', v_contrato.analista_cierre_id
    ),
    'titular', jsonb_build_object(
      'id', v_cliente.id,
      'nombreCompleto', v_cliente.nombre_completo,
      'tipoDocumento', upper(v_cliente.tipo_documento),
      'documento', v_cliente.dni,
      'domicilio', v_cliente.domicilio,
      'correo', v_cliente.correo
    ),
    'analista', jsonb_build_object(
      'id', v_analista.id,
      'nombreCompleto', v_analista.nombre_completo,
      'documento', v_analista.dni,
      'celular', v_analista.telefono,
      'correo', v_analista.correo
    ),
    'cotitulares', v_cotitulares,
    'cronograma', v_cronograma,
    'cuentaPago', v_cuenta
  );
exception when no_data_found then
  raise exception 'Contrato, titular o analista inexistente'
    using errcode = 'P0002';
end;
$function$;


CREATE OR REPLACE FUNCTION private.contrato_pdf_anexo_snapshot_base(p_contrato_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_estado jsonb;
  v_pdf private.contrato_pdfs%rowtype;
begin
  -- Mismo mutex que reclamar/crear_job: nadie cuela una revisión nueva entre
  -- leer el estado y leer el ledger (revisión de Codex, P1).
  perform private.bloquear_fila_contrato_pdf(p_contrato_id);

  -- El archivo visible es el que dice estado_base: trabajo más reciente,
  -- sellado y coherente con el ledger. Una revisión nueva pendiente, un trabajo
  -- en integridad_bloqueada o un contrato sin reserva NO tienen anexo.
  v_estado := private.contrato_pdf_estado_base(p_contrato_id);
  if (v_estado->>'estado') is distinct from 'sellado' then
    raise exception 'El contrato no tiene un PDF sellado del que emitir el anexo'
      using errcode = 'P0002', hint = 'ANEXO_SIN_PDF_SELLADO';
  end if;

  if (v_estado->>'job_id') is not null then
    select * into v_pdf
    from private.contrato_pdfs p
    where p.contrato_id = p_contrato_id
      and p.job_id = (v_estado->>'job_id')::uuid
    order by p.revision desc
    limit 1;
  else
    -- Ledger v1 (sin trabajo server-side): se resuelve por contrato.
    select * into v_pdf
    from private.contrato_pdfs p
    where p.contrato_id = p_contrato_id
    order by p.revision desc
    limit 1;
  end if;
  if not found then
    raise exception 'El contrato no tiene un PDF sellado del que emitir el anexo'
      using errcode = 'P0002', hint = 'ANEXO_SIN_PDF_SELLADO';
  end if;
  if coalesce(v_pdf.snapshot->'snapshotVersion' in ('2'::jsonb, '3'::jsonb), false) is not true then
    raise exception 'El contrato no tiene datos congelados aptos para el anexo'
      using errcode = 'P0002', hint = 'ANEXO_SIN_SNAPSHOT';
  end if;

  return jsonb_build_object(
    'contrato_id', p_contrato_id,
    'pdf_id', v_pdf.id,
    'revision', v_pdf.revision,
    'template_version', v_pdf.template_version,
    'generado_en', v_pdf.generado_en,
    'sha256', v_pdf.sha256,
    'snapshot', v_pdf.snapshot
  );
end;
$function$;


CREATE OR REPLACE FUNCTION private.contrato_pdf_anexo_emitido_base(p_contrato_id uuid, p_actor_id uuid, p_pdf_id uuid, p_template text, p_sha256 text, p_bytes bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_pdf private.contrato_pdfs%rowtype;
  v_id uuid;
begin
  -- El pdf_id tiene que ser un sellado de ESTE contrato con snapshot v2: la
  -- Edge no puede registrar una emisión sobre otra fila.
  select * into v_pdf
  from private.contrato_pdfs p
  where p.id = p_pdf_id and p.contrato_id = p_contrato_id;
  if not found or coalesce(v_pdf.snapshot->'snapshotVersion' in ('2'::jsonb, '3'::jsonb), false) is not true then
    raise exception 'La emisión no corresponde a un PDF sellado de este contrato'
      using errcode = '23514';
  end if;
  insert into private.contrato_pdf_anexo_emisiones (
    contrato_id, pdf_id, revision, template_version_contrato,
    template_anexo, sha256, bytes, actor_id
  ) values (
    p_contrato_id, v_pdf.id, v_pdf.revision, v_pdf.template_version,
    p_template, p_sha256, p_bytes, p_actor_id
  )
  returning id into v_id;
  return jsonb_build_object(
    'emision_id', v_id,
    'contrato_id', p_contrato_id,
    'revision', v_pdf.revision
  );
end;
$function$;

