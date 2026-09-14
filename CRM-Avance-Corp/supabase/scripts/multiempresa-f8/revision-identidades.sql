-- F8: diagnóstico dirigido de fuentes sin identidad. SOLO LECTURA.
-- La salida contiene datos personales: conservar fuera de Git, con acceso privado.
-- No ejecutar resolutores, backfills ni funciones mutadoras durante la revisión.
begin isolation level repeatable read read only;
set local statement_timeout = '45s';
set local lock_timeout = '5s';
set local idle_in_transaction_session_timeout = '60s';
set local search_path = '';

with fuentes as materialized (
  select * from private.cartera_f5_fuentes()
), pendientes as materialized (
  select f.*
  from fuentes f
  left join crm.inversionistas i on i.id = f.inversionista_id
  where not coalesce(f.identidad_coherente, false)
     or i.id is null or i.inversionista_canonico_id is not null
), perfiles as materialized (
  select p.id, p.nombre_completo, p.dni, p.tipo_documento, p.rol, p.activo,
    p.asesor_perfil_id, p.creado_en,
    upper(regexp_replace(coalesce(p.dni, ''), '[^A-Za-z0-9]', '', 'g')) as doc_norm
  from public.perfiles p
), casos as (
  select f.*,
    -- Elegir tipo, documento y normalización de UNA misma fuente económica.
    case when f.empresa = 'avance' then p.nombre_completo else ce.nombre_completo end as nombre,
    case when f.empresa = 'avance' then p.tipo_documento else ce.documento_tipo end as tipo_documento,
    case when f.empresa = 'avance' then p.dni else ce.documento end as documento,
    case when f.empresa = 'avance' then p.doc_norm else
      upper(regexp_replace(coalesce(ce.documento, ''), '[^A-Za-z0-9]', '', 'g')) end as doc_norm,
    to_jsonb(p) as perfil,
    case when ce.id is not null then jsonb_build_object(
      'id', ce.id, 'lead_id', ce.lead_id, 'nombre', ce.nombre_completo,
      'tipo_documento', ce.documento_tipo, 'documento', ce.documento,
      'inversionista_id', ce.inversionista_id, 'anulado_en', ce.anulado_en,
      'vendedor_id', ce.vendedor_id
    ) end as cierre,
    to_jsonb(b) as revision_f2
  from pendientes f
  left join perfiles p on p.id = f.perfil_id
  left join crm.cierres_externos ce on ce.id = f.fuente_id and f.empresa <> 'avance'
  left join crm.backfill_multiempresa_mapa b
    on b.fuente = case when f.empresa = 'avance' then 'perfil' else 'cierre' end
    and b.fila_id = case when f.empresa = 'avance' then f.perfil_id else f.fuente_id end
), detalle as (
  select c.*,
    -- Formato válido NO significa documento verificado.
    coalesce(case c.tipo_documento
      when 'DNI' then c.doc_norm ~ '^[0-9]{8}$'
      when 'CE' then c.doc_norm ~ '^[0-9]{9,12}$'
      when 'PASAPORTE' then c.doc_norm ~ '^[A-Z0-9]{6,12}$'
    end, false) as formato_valido,
    coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from (
      select p.*,
        (select count(*) from public.contratos ct where ct.cliente_id = p.id) as contratos,
        coalesce((select jsonb_agg(jsonb_build_object(
          'id', i.id, 'estado', i.estado, 'canonico_id', i.inversionista_canonico_id
        ) order by i.id) from crm.inversionistas i where i.perfil_id = p.id), '[]'::jsonb) as identidades
      from perfiles p
      -- Se revisan colisiones también entre tipos, igual que en el backfill F2.
      where c.doc_norm <> '' and p.doc_norm = c.doc_norm
    ) x), '[]'::jsonb) as perfiles_mismo_documento,
    coalesce((select jsonb_agg(jsonb_build_object(
      'id', d.id, 'inversionista_id', d.inversionista_id,
      'tipo_documento', d.tipo_documento, 'estado', d.estado,
      'verificado', d.verificado, 'fuente', d.fuente,
      'canonico_id', private.inversionista_canonica(d.inversionista_id)
    ) order by d.id) from crm.inversionista_identificadores d
      where c.doc_norm <> '' and d.documento_normalizado = c.doc_norm
    ), '[]'::jsonb) as identificadores_mismo_documento,
    coalesce((select jsonb_agg(jsonb_build_object(
      'id', ce.id, 'empresa', ce.cooperativa, 'nombre', ce.nombre_completo,
      'tipo_documento', ce.documento_tipo, 'coincide_tipo', ce.documento_tipo = c.tipo_documento,
      'inversionista_id', ce.inversionista_id, 'lead_id', ce.lead_id,
      'anulado_en', ce.anulado_en,
      'identidad_de_fuente', fce.inversionista_id,
      'identidad_coherente', fce.identidad_coherente
    ) order by ce.id) from crm.cierres_externos ce
      left join fuentes fce on fce.fuente_id = ce.id and fce.empresa = ce.cooperativa
      where c.doc_norm <> '' and
        upper(regexp_replace(coalesce(ce.documento, ''), '[^A-Za-z0-9]', '', 'g')) = c.doc_norm
    ), '[]'::jsonb) as cierres_mismo_documento,
    coalesce((select jsonb_agg(jsonb_build_object(
      'id', l.id, 'nombre', l.nombre_completo, 'dni', l.dni,
      'perfil_id', l.perfil_id, 'inversionista_id', l.inversionista_id,
      'activo', l.activo, 'etapa', l.etapa, 'no_contactar', l.no_contactar,
      'vendedor_id', l.vendedor_id,
      'es_lead_de_fuente', l.id = c.lead_id,
      'es_lead_del_perfil', l.perfil_id = c.perfil_id,
      -- El campo del lead es DNI. Igual número con CE/PASAPORTE solo es
      -- una señal de colisión a revisar, nunca una identidad tipificada.
      'coincide_dni', c.tipo_documento = 'DNI' and c.doc_norm <> '' and
        upper(regexp_replace(coalesce(l.dni, ''), '[^A-Za-z0-9]', '', 'g')) = c.doc_norm,
      'coincide_numero_otro_tipo', c.tipo_documento <> 'DNI' and c.doc_norm <> '' and
        upper(regexp_replace(coalesce(l.dni, ''), '[^A-Za-z0-9]', '', 'g')) = c.doc_norm,
      'puentes', coalesce((select jsonb_agg(jsonb_build_object(
        'inversionista_id', il.inversionista_id, 'rol', il.rol, 'hasta', il.hasta
      ) order by il.id) from crm.inversionista_leads il where il.lead_id = l.id), '[]'::jsonb)
    ) order by l.id) from crm.leads l
      where l.id = c.lead_id or l.perfil_id = c.perfil_id
        or (c.doc_norm <> '' and
          upper(regexp_replace(coalesce(l.dni, ''), '[^A-Za-z0-9]', '', 'g')) = c.doc_norm)
    ), '[]'::jsonb) as leads_relacionados
  from casos c
)
select jsonb_build_object(
  'observado_en', statement_timestamp(),
  'transaccion_solo_lectura', current_setting('transaction_read_only'),
  'aislamiento', current_setting('transaction_isolation'),
  'fuentes_totales', (select count(*) from fuentes),
  'fuentes_reales', (select count(*) from fuentes where not es_demo),
  'fuentes_demo', (select count(*) from fuentes where es_demo),
  'pendientes_reales', (select count(*) from pendientes where not es_demo),
  'pendientes_demo', (select count(*) from pendientes where es_demo),
  'casos', coalesce((select jsonb_agg(to_jsonb(d) order by d.es_demo, d.empresa, d.fuente_id)
    from detalle d), '[]'::jsonb)
) as revision;
rollback;
