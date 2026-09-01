-- ---------------------------------------------------------------------------
-- COLA F0.5 — excepciones de identidad de inversionistas (SOLO LECTURA)
-- ---------------------------------------------------------------------------
-- Contrato: «Contrato arquitectonico consolidado - identidad unificada de
-- inversionistas (F0 2026-08-31)» + «Censo F0 de identidad unificada -
-- resultado de solo lectura (2026-08-31)» (vault). Esta cola INDIVIDUALIZA
-- las excepciones agregadas del censo F0 en casos accionables y
-- pseudonimizados, para decidir migración / corrección / cuarentena.
-- NO corrige, NO migra, NO enlaza, NO escribe la cola en la base.
--
-- USO (lo ejecuta Camila tras revisar; NUNCA se ejecuta desde una sesión de
-- agente contra producción):
--   npx supabase db query --linked --file supabase/scripts/cola-f05-identidad-inversionistas.sql
--
-- SALVAGUARDAS (idénticas al censo F0):
--   · begin + set transaction read only INMEDIATO; el servidor hace cumplir
--     el solo-lectura, no la disciplina de quien edite este fichero.
--   · timeouts y search_path LOCALES; todo esquema explícito.
--   · una sola sentencia SELECT/CTE; cero DDL, cero DML, cero RPC mutadora.
--   · ROLLBACK final incondicional.
--   · PII CERO: ningún nombre, documento, teléfono, correo, dirección, UUID
--     crudo ni credencial sale por el resultado. Cada caso viaja con un
--     hash determinista (md5 de tipo de entidad + PK) que permite
--     relocalizarlo re-ejecutando ESTA MISMA consulta; el dato real solo se
--     obtiene con una consulta dirigida y autorizada aparte.
--   · grupo_persona_hash: pseudónimo determinista derivado de referencias UUID
--     técnicas (nunca del documento), o del perfil/lead cuando no hay clave, para explicar
--     solapamientos entre categorías sin fusionar nada.
--
-- CONTEXTO DE EJECUCIÓN: sesión postgres (propietaria), igual que el censo
-- F0: los núcleos private.* tienen EXECUTE revocado a los roles API y
-- crm.cierres_externos es deny-by-default. Los núcleos son STABLE (solo
-- SELECT por dentro); la transacción read-only abortaría cualquier escritura.
--
-- CATEGORÍAS (una fila por caso, sin doble conteo DENTRO de cada categoría;
-- el solapamiento ENTRE categorías es legítimo y lo explica el grupo):
--   1  perfil_sin_documento               perfil cliente sin documento
--   2  perfil_documento_invalido          perfil cliente con documento inválido
--   3  clave_compartida_con_otro_rol      un caso por clave documental
--   4  identidad_sin_responsable          identidad A/B sin responsable potencial
--   5  veto_sin_identidad_fuerte          lead no_contactar sin clave A/B
--   6  discrepancia_documental_convertido lead convertido: DNI ≠ fuente heredada
--   7  episodio_conversion_sin_identidad  un caso por episodio (núcleo+factor F0)
--   8  episodio_capital_sin_identidad     un caso por episodio (sin IDs)
--   9  demo_por_confirmar                 cierre Qorilazo 100000 PEN
--   10 senial_debil_agregada              a lo sumo UNA fila por señal, sin PII
-- Más dos filas de control: contexto y reconciliación contra el F0 canónico.
-- ---------------------------------------------------------------------------
begin;
set transaction read only;
set local statement_timeout = '180s';
set local lock_timeout = '5s';
set local idle_in_transaction_session_timeout = '180s';
set local search_path = '';

with
zona as (
  select 'America/Lima'::text as tz, now() as observado_en
),

-- ============================================================================
-- Fuentes normalizadas (mismo universo que el censo F0). La normalización
-- débil (tel/correo/nombre) existe SOLO para la señal agregada; jamás une.
-- ============================================================================
perfiles_doc as (
  select
    p.id,
    p.rol,
    coalesce(p.activo, true) as activo,
    p.tipo_documento as tipo,
    nullif(upper(btrim(p.dni)), '') as doc,
    p.asesor_perfil_id,
    nullif(lower(btrim(p.correo)), '') as correo_n,
    right(nullif(regexp_replace(coalesce(p.telefono, ''), '[^0-9]', '', 'g'), ''), 9) as tel9,
    nullif(lower(regexp_replace(btrim(coalesce(p.nombre_completo, '')), '\s+', ' ', 'g')), '') as nombre_n
  from public.perfiles p
),
perfiles_val as (
  -- el mismo contrato de formato que crm.cierres_externos (espejo de documento.ts)
  select pd.*,
    case
      when pd.doc is null then 'ausente'
      when (pd.tipo = 'DNI'       and pd.doc ~ '^[0-9]{8}$')
        or (pd.tipo = 'CE'        and pd.doc ~ '^[0-9]{9,12}$')
        or (pd.tipo = 'PASAPORTE' and pd.doc ~ '^[A-Z0-9]{6,12}$')
        then 'valido'
      else 'invalido'
    end as doc_estado
  from perfiles_doc pd
),
perfiles_cli as (
  select * from perfiles_val where rol = 'cliente'
),
cierres as (
  select
    ce.id, ce.lead_id, ce.cooperativa,
    ce.documento_tipo as tipo,
    upper(btrim(ce.documento)) as doc,
    ce.vendedor_id, ce.creado_en, ce.anulado_en,
    (ce.anulado_en is null) as vigente,
    ce.monto, ce.moneda,
    nullif(lower(regexp_replace(btrim(ce.nombre_completo), '\s+', ' ', 'g')), '') as nombre_n
  from crm.cierres_externos ce
),
leads_n as (
  select
    l.id, l.etapa, l.activo, l.no_contactar, l.perfil_id, l.contrato_id,
    l.convertido_en, l.vendedor_id, l.creado_en,
    nullif(btrim(l.dni), '') as dni,
    nullif(lower(btrim(l.correo)), '') as correo_n,
    right(nullif(regexp_replace(coalesce(l.telefono, ''), '[^0-9]', '', 'g'), ''), 9) as tel9,
    nullif(lower(regexp_replace(btrim(l.nombre_completo), '\s+', ' ', 'g')), '') as nombre_n,
    (l.activo and l.etapa not in ('convertido', 'descartado')) as vivo,
    (l.etapa = 'convertido') as convertido
  from crm.leads l
),
operaciones_n as (
  select o.id, o.cliente_id, o.vendedor_id, o.tipo, o.periodo, o.fecha_operacion,
         o.moneda, o.elegible_conversion, o.creado_en
  from crm.operaciones_cartera o
),

-- ============================================================================
-- Identidad documental SIMULADA (idéntica al F0): clave = (tipo, documento)
-- ============================================================================
claves_fuentes as (
  select tipo, doc, 'perfil'::text as fuente from perfiles_cli where doc_estado = 'valido'
  union all
  select tipo, doc, 'cierre'::text from cierres
),
fuentes_tecnicas_clave as (
  -- El pseudónimo de persona se deriva exclusivamente de UUID técnicos
  -- aleatorios. NO se hashea el documento: un DNI tiene un espacio de búsqueda
  -- pequeño y un hash directo sería reversible por fuerza bruta.
  select tipo, doc, 'perfil|' || id::text as referencia_tecnica
  from perfiles_val where doc_estado = 'valido'
  union all
  select tipo, doc, 'cierre|' || id::text
  from cierres
),
grupos_clave as (
  select tipo, doc,
    md5('gp-clave-tecnica|' || string_agg(referencia_tecnica, ',' order by referencia_tecnica)) as gp_hash
  from fuentes_tecnicas_clave
  group by tipo, doc
),
claves as (
  select tipo, doc,
    count(*) filter (where fuente = 'perfil') as n_perfiles,
    count(*) filter (where fuente = 'cierre') as n_cierres,
    (select count(*) from perfiles_val pv
      where pv.rol <> 'cliente' and pv.doc_estado = 'valido'
        and pv.tipo = cf.tipo and pv.doc = cf.doc) as n_perfiles_no_cliente
  from claves_fuentes cf
  group by tipo, doc
),
docs_multitipo as (
  select doc from claves group by doc having count(distinct tipo) > 1
),
claves_clasif as (
  -- precedencia por clave, sin doble conteo: E (conflicto) > A (perfil) > B (cierre)
  select k.tipo, k.doc, k.n_perfiles, k.n_cierres, k.n_perfiles_no_cliente,
    (k.doc in (select dm.doc from docs_multitipo dm)) as multitipo,
    case
      when k.n_perfiles > 1 then 'E'
      when k.n_perfiles_no_cliente > 0 then 'E'
      when k.doc in (select dm.doc from docs_multitipo dm) then 'E'
      when k.n_perfiles = 1 then 'A'
      else 'B'
    end as clase
  from claves k
),
identidades as (
  select kk.tipo, kk.doc, kk.clase, kk.n_perfiles, kk.n_cierres
  from claves_clasif kk where kk.clase in ('A', 'B')
),

-- ============================================================================
-- Responsable potencial (misma regla del F0)
-- ============================================================================
resp_perfil as (
  select pc.tipo, pc.doc, pc.asesor_perfil_id
  from perfiles_cli pc
  join identidades i on i.tipo = pc.tipo and i.doc = pc.doc
  where pc.doc_estado = 'valido'
),
resp_cierre as (
  select distinct on (c.tipo, c.doc) c.tipo, c.doc, c.vendedor_id
  from cierres c
  join identidades i on i.tipo = c.tipo and i.doc = c.doc
  where c.vigente
  order by c.tipo, c.doc, c.creado_en desc
),
responsables as (
  select i.tipo, i.doc, i.clase, i.n_perfiles, i.n_cierres,
    coalesce(rp.asesor_perfil_id, rc.vendedor_id) as responsable_id,
    (rp.tipo is not null) as perfil_censado,
    (rc.tipo is not null) as cierre_vigente
  from identidades i
  left join resp_perfil rp on rp.tipo = i.tipo and rp.doc = i.doc
  left join resp_cierre rc on rc.tipo = i.tipo and rc.doc = i.doc
),

-- ============================================================================
-- Vínculo lead → clave documental (solo documental/heredado; nunca señal débil)
-- ============================================================================
lead_identidad as (
  select ln.id as lead_id, ln.no_contactar, ln.vivo, ln.etapa, ln.dni,
    ident.identidad,
    (select kk.clase from claves_clasif kk
      where kk.tipo || '|' || kk.doc = ident.identidad) as clase_clave
  from leads_n ln
  cross join lateral (
    select coalesce(
      (select c.tipo || '|' || c.doc from cierres c where c.lead_id = ln.id),
      (select pv.tipo || '|' || pv.doc from perfiles_val pv
        where pv.id = ln.perfil_id and pv.doc_estado = 'valido'),
      case when ln.dni is not null and exists (
             select 1 from claves k where k.tipo = 'DNI' and k.doc = ln.dni)
           then 'DNI|' || ln.dni end
    ) as identidad
  ) ident
),

-- ============================================================================
-- Discrepancia documental del convertido (mismo criterio del F0, con detalle)
-- ============================================================================
convertidos_discrepantes as (
  -- el campo del lead declara un DNI; la fuente heredada usa otro tipo u otro
  -- valor. El vínculo puede seguir siendo C, pero exige auditoría documental.
  select ln.id as lead_id,
    case when ce.lead_id is not null then 'cierre' else 'perfil' end as via,
    coalesce(ce.tipo, pv.tipo) as tipo_fuente,
    coalesce(ce.doc, pv.doc) as doc_fuente,
    case when coalesce(ce.tipo, pv.tipo) <> 'DNI' then 'tipo' else 'valor' end as difiere_por,
    (ln.dni ~ '^[0-9]{8}$') as lead_dni_valido
  from leads_n ln
  left join cierres ce on ce.lead_id = ln.id
  left join perfiles_val pv on pv.id = ln.perfil_id
  where ln.convertido and ln.dni is not null
    and ((ce.lead_id is not null and (ce.tipo <> 'DNI' or ce.doc <> ln.dni))
      or (ce.lead_id is null and pv.doc is not null
          and (pv.tipo <> 'DNI' or pv.doc <> ln.dni)))
),

-- ============================================================================
-- Episodios de conversión (mismo núcleo, factor real y universo del F0)
-- ============================================================================
limites_mes as (
  select
    date_trunc('month', least(
      coalesce(((select min(coalesce(la.resultado_en, la.finalizado_en))
                   from crm.lead_asignaciones la
                  where la.resultado = 'convertido') at time zone 'America/Lima')::date,
               (now() at time zone 'America/Lima')::date),
      coalesce((select min(o.periodo) from crm.operaciones_cartera o),
               (now() at time zone 'America/Lima')::date)
    )::timestamp)::date as mes_ini,
    date_trunc('month', now() at time zone 'America/Lima')::date as mes_fin
),
meses as (
  select gs::date as mes
  from limites_mes lm,
       generate_series(lm.mes_ini::timestamp, lm.mes_fin::timestamp, interval '1 month') gs
),
factores_mes as (
  -- factor de referido REAL por mes: sellado → foto de periodos_cerrados;
  -- abierto → el peso que usaría hoy el núcleo
  select m.mes,
    (pc.periodo is not null) as sellado,
    case when pc.periodo is not null then pc.ponderacion_referido
         else private.peso_referido_conversion(m.mes) end as factor
  from meses m
  left join crm.periodos_cerrados pc on pc.periodo = m.mes
),
episodios_nucleo as (
  select fm.mes, fm.sellado, ep.tipo, ep.lead_id, ep.operacion_id, ep.anulado,
         ep.fue_referido, ep.aporte_numerador, ep.fecha_numerador
  from factores_mes fm
  cross join lateral private.conversion_episodios(
    (fm.mes::timestamp at time zone 'America/Lima'),
    ((fm.mes + interval '1 month') at time zone 'America/Lima'),
    fm.mes,
    true,
    null::uuid[],
    fm.factor
  ) ep
  where ep.tipo in ('cierre', 'operacion')
),
episodios as (
  -- un episodio de cierre por (mes, lead), como deduplica la lectura viva
  select en.mes, en.sellado, 'cierre'::text as tipo, en.lead_id,
         null::uuid as operacion_id,
         bool_or(en.anulado) as anulado, bool_or(en.fue_referido) as fue_referido,
         max(en.aporte_numerador) as aporte_numerador
  from episodios_nucleo en
  where en.tipo = 'cierre'
  group by en.mes, en.sellado, en.lead_id
  union all
  select en.mes, en.sellado, 'operacion'::text, null::uuid, en.operacion_id,
         en.anulado, en.fue_referido, en.aporte_numerador
  from episodios_nucleo en
  where en.tipo = 'operacion'
),
episodios_sin_identidad as (
  -- NO resoluble = su clave documental no existe con clase A/B (mismo gate
  -- del F0: identidades). Un caso POR EPISODIO; no se agrupan entre sí.
  select e.mes, e.sellado, e.tipo, e.anulado, e.fue_referido, e.aporte_numerador,
    coalesce(e.lead_id, e.operacion_id) as episodio_uid,
    case
      when e.tipo = 'operacion' then 'operacion_cartera'
      when exists (select 1 from cierres c where c.lead_id = e.lead_id) then 'cooperativa'
      else 'avance'
    end as canal,
    gp.gp_hash
  from episodios e
  cross join lateral (
    select case
      when e.tipo = 'operacion' then
        (select pv.tipo || '|' || pv.doc
           from operaciones_n o
           join perfiles_val pv on pv.id = o.cliente_id and pv.doc_estado = 'valido'
           join identidades i on i.tipo = pv.tipo and i.doc = pv.doc
          where o.id = e.operacion_id)
      else
        coalesce(
          (select c.tipo || '|' || c.doc
             from cierres c
             join identidades i on i.tipo = c.tipo and i.doc = c.doc
            where c.lead_id = e.lead_id),
          (select pv.tipo || '|' || pv.doc
             from leads_n ln
             join perfiles_val pv on pv.id = ln.perfil_id and pv.doc_estado = 'valido'
             join identidades i on i.tipo = pv.tipo and i.doc = pv.doc
            where ln.id = e.lead_id))
    end as identidad_ab
  ) ident
  cross join lateral (
    -- Pseudónimo SOLO para explicar solapamientos. Si existe documento, se usa
    -- su grupo derivado de UUID técnicos; nunca un hash directo del documento.
    select case
      when e.tipo = 'operacion' then coalesce(
        (select gc.gp_hash
           from operaciones_n o
           join perfiles_val pv on pv.id = o.cliente_id and pv.doc_estado = 'valido'
           join grupos_clave gc on gc.tipo = pv.tipo and gc.doc = pv.doc
          where o.id = e.operacion_id),
        (select md5('gp-perfil|' || o.cliente_id::text)
           from operaciones_n o where o.id = e.operacion_id))
      else coalesce(
        (select gc.gp_hash from cierres c
           join grupos_clave gc on gc.tipo = c.tipo and gc.doc = c.doc
          where c.lead_id = e.lead_id),
        (select gc.gp_hash
           from leads_n ln
           join perfiles_val pv on pv.id = ln.perfil_id and pv.doc_estado = 'valido'
           join grupos_clave gc on gc.tipo = pv.tipo and gc.doc = pv.doc
          where ln.id = e.lead_id),
        (select md5('gp-perfil|' || ln.perfil_id::text)
           from leads_n ln where ln.id = e.lead_id and ln.perfil_id is not null),
        md5('gp-lead|' || e.lead_id::text))
    end as gp_hash
  ) gp
  where ident.identidad_ab is null
),

-- ============================================================================
-- Episodios de capital sin identidad resoluble (núcleo vivo; sin IDs de salida)
-- ============================================================================
capital_base as materialized (
  -- ±infinity: forma documentada por el propio núcleo (ventanas por día Lima)
  select * from private.capital_episodios(
    '-infinity'::timestamptz, 'infinity'::timestamptz, true, null::uuid[])
),
capital_sin_identidad as (
  select
    case when cb.tipo = 'cooperativa'
         then coalesce((select cx.cooperativa from cierres cx where cx.id = cb.cierre_externo_id),
                       'cooperativa_desconocida')
         else 'avance' end as empresa,
    coalesce(cb.moneda, '(sin moneda)') as moneda,
    coalesce(cb.medida, '(sin medida)') as medida,
    coalesce(cb.estado, '(sin estado)') as estado,
    cb.anulado, cb.monto, cb.mes_comercial, cb.tipo,
    -- referencia determinista del episodio (tipo+medida+PK+estado+mes)
    md5('f05|episodio-capital|' || cb.tipo || '|' || coalesce(cb.medida, '') || '|'
        || coalesce(cb.contrato_id::text, cb.cierre_externo_id::text,
                    cb.lead_id::text, cb.cliente_id::text, 'sin-id')
        || '|' || coalesce(cb.estado, '') || '|'
        || coalesce(to_char(cb.mes_comercial, 'YYYY-MM'), '')) as ref_hash,
    case when cb.tipo = 'cooperativa' then coalesce(
      (select gc.gp_hash from cierres c
        join grupos_clave gc on gc.tipo = c.tipo and gc.doc = c.doc
       where c.id = cb.cierre_externo_id),
      case when cb.cierre_externo_id is not null
           then md5('gp-cierre|' || cb.cierre_externo_id::text) end)
    when cb.cliente_id is not null then coalesce(
      (select gc.gp_hash from perfiles_val pv
        join grupos_clave gc on gc.tipo = pv.tipo and gc.doc = pv.doc
       where pv.id = cb.cliente_id and pv.doc_estado = 'valido'),
      md5('gp-perfil|' || cb.cliente_id::text)) end as gp_hash
  from capital_base cb
  where not exists (
    select 1 from identidades i
    where (cb.tipo = 'cooperativa' and exists (
             select 1 from cierres c where c.id = cb.cierre_externo_id
               and c.tipo = i.tipo and c.doc = i.doc))
       or (cb.tipo <> 'cooperativa' and exists (
             select 1 from perfiles_val pv where pv.id = cb.cliente_id
               and pv.doc_estado = 'valido' and pv.tipo = i.tipo and pv.doc = i.doc))
  )
),

-- ============================================================================
-- Señales débiles (SOLO agregado; a lo sumo una fila por señal, cero PII)
-- ============================================================================
leads_dni_estado as (
  select ln.id,
    case
      when kd.clase in ('A', 'B') then 'D'
      when kd.clase = 'E' then 'E'
      when exists (select 1 from claves k2 where k2.doc = ln.dni and k2.tipo <> 'DNI') then 'E'
      else 'sin_coincidencia'
    end as clase
  from leads_n ln
  left join claves_clasif kd on kd.tipo = 'DNI' and kd.doc = ln.dni
  where not ln.convertido and ln.dni is not null
),
leads_f as (
  select lf.id,
    exists (select 1 from perfiles_cli pc where pc.tel9 is not null and pc.tel9 = lf.tel9) as m_tel,
    exists (select 1 from perfiles_cli pc where pc.correo_n is not null and pc.correo_n = lf.correo_n) as m_correo,
    (exists (select 1 from perfiles_cli pc where pc.nombre_n is not null and pc.nombre_n = lf.nombre_n)
      or exists (select 1 from cierres c where c.nombre_n is not null and c.nombre_n = lf.nombre_n)) as m_nombre
  from leads_n lf
  left join leads_dni_estado lde on lde.id = lf.id
  where not lf.convertido
    and (lf.dni is null or lde.clase = 'sin_coincidencia')
),
seniales as (
  select s.senial, s.n from (
    select 'por_telefono'::text as senial, (select count(*) from leads_f where m_tel) as n
    union all
    select 'por_correo', (select count(*) from leads_f where m_correo)
    union all
    select 'por_nombre', (select count(*) from leads_f where m_nombre)
  ) s
  where s.n > 0
),

-- ============================================================================
-- CASOS (una fila por caso; hash determinista tipo+PK; cero PII)
-- ============================================================================
casos as (

-- 1. perfil cliente sin documento -------------------------------------------
select
  'perfil_sin_documento'::text as categoria,
  'Sin documento no puede nacer identidad automática ni hacerse obligatorio el vínculo de su capital'::text as impacto_comercial,
  'cuarentena'::text as estado_recomendado,
  'Capturar el documento por la puerta vigente del Portal, revalidar formato y repetir el censo antes del backfill'::text as accion_propuesta,
  'public.perfiles'::text as fuente,
  md5('f05|perfil|' || pc.id::text) as referencia_hash,
  md5('gp-perfil|' || pc.id::text) as grupo_persona_hash,
  jsonb_build_object(
    'activo', pc.activo,
    'tiene_asesor', pc.asesor_perfil_id is not null,
    'nota', 'clase E del censo F0; el contrato F0 no crea identidad operativa sin documento verificado') as detalle
from perfiles_cli pc
where pc.doc_estado = 'ausente'

-- 2. perfil cliente con documento inválido ----------------------------------
union all
select
  'perfil_documento_invalido',
  'El formato del documento no pasa el contrato documental: bloquea la identidad automática de esta persona',
  'requiere_correccion',
  'Corregir tipo o valor del documento por la puerta vigente del Portal; no crear identidad hasta que valide',
  'public.perfiles',
  md5('f05|perfil|' || pc.id::text),
  md5('gp-perfil|' || pc.id::text),
  jsonb_build_object(
    'activo', pc.activo,
    'tipo_documento_declarado', pc.tipo,
    'longitud_documento', length(pc.doc),
    'solo_digitos', pc.doc ~ '^[0-9]+$',
    'patron_esperado', case pc.tipo
        when 'DNI' then '8 dígitos'
        when 'CE' then '9 a 12 dígitos'
        when 'PASAPORTE' then '6 a 12 alfanuméricos'
        else '(tipo desconocido)' end)
from perfiles_cli pc
where pc.doc_estado = 'invalido'

-- 3. clave documental de cliente que también existe en otro rol -------------
union all
select
  'clave_compartida_con_otro_rol',
  'La misma clave documental vive en un perfil cliente y en un perfil de otro rol: riesgo de mezclar dos usos de una persona',
  'revision_humana',
  'Confirmar si es el caso legítimo colaborador-inversionista (decisión ya soportada por el modelo) o un dato mal cargado; solo entonces decidir una identidad única',
  'public.perfiles (ambos roles)',
  md5('f05|clave|' || gc.gp_hash),
  gc.gp_hash,
  jsonb_build_object(
    'tipo_documento', kk.tipo,
    'perfiles_cliente', kk.n_perfiles,
    'perfiles_otro_rol', kk.n_perfiles_no_cliente,
    'cierres_externos', kk.n_cierres,
    'roles_no_cliente', (select coalesce(jsonb_agg(distinct pv.rol), '[]'::jsonb)
                           from perfiles_val pv
                          where pv.rol <> 'cliente' and pv.doc_estado = 'valido'
                            and pv.tipo = kk.tipo and pv.doc = kk.doc))
from claves_clasif kk
join grupos_clave gc on gc.tipo = kk.tipo and gc.doc = kk.doc
where kk.n_perfiles_no_cliente > 0

-- 4. identidad A/B sin responsable potencial --------------------------------
union all
select
  'identidad_sin_responsable',
  'Identidad migrable pero sin responsable de relación que la opere comercialmente',
  'requiere_confirmacion',
  'Gerencia asigna responsable de relación en el backfill (regla F0: perfil sin asesor o cierre sin vigencia); sin responsable no se habilitan acciones',
  case when r.clase = 'A' then 'public.perfiles' else 'crm.cierres_externos' end,
  md5('f05|clave|' || gc.gp_hash),
  gc.gp_hash,
  jsonb_build_object(
    'clase', r.clase,
    'tipo_documento', r.tipo,
    'perfil_sin_asesor', r.perfil_censado and r.responsable_id is null,
    'sin_cierre_vigente', r.clase = 'B' and not r.cierre_vigente,
    'n_perfiles', r.n_perfiles,
    'n_cierres', r.n_cierres)
from responsables r
join grupos_clave gc on gc.tipo = r.tipo and gc.doc = r.doc
where r.responsable_id is null

-- 5. veto no_contactar sin identidad fuerte ---------------------------------
union all
select
  'veto_sin_identidad_fuerte',
  'El veto no contactar debe centralizarse por persona (invariante 7 del contrato) y hoy no hay clave A/B a la que subirlo',
  'cuarentena',
  'Mantener el veto a nivel de lead; centralizarlo recién cuando la persona obtenga identidad documental (p. ej. al convertir); jamás vincular por teléfono/correo/nombre',
  'crm.leads',
  md5('f05|lead|' || li.lead_id::text),
  coalesce((select gc.gp_hash from grupos_clave gc
             where gc.tipo || '|' || gc.doc = li.identidad),
           md5('gp-lead|' || li.lead_id::text)),
  jsonb_build_object(
    'vivo', li.vivo,
    'etapa', li.etapa,
    'tiene_dni', li.dni is not null,
    'dni_valido', coalesce(li.dni ~ '^[0-9]{8}$', false),
    'motivo', case
        when li.identidad is null and li.dni is null then 'sin documento en el lead ni fuente heredada'
        when li.identidad is null then 'DNI sin identidad censada todavía'
        when li.clase_clave = 'E' then 'su clave documental está en revisión E'
        else 'clave no clasificada A/B' end)
from lead_identidad li
where li.no_contactar
  and (li.identidad is null or li.clase_clave is null or li.clase_clave = 'E')

-- 6. lead convertido con DNI que difiere de la fuente heredada --------------
union all
select
  'discrepancia_documental_convertido',
  'El vínculo C sigue siendo inequívoco por su fuente, pero el DNI declarado en el lead no coincide: auditar antes del backfill definitivo',
  'requiere_confirmacion',
  'Auditoría documental humana: decidir cuál documento es el verdadero y corregir el equivocado por su puerta de dominio; el backfill C no debe asumir la sustitución',
  case when cd.via = 'cierre' then 'crm.leads + crm.cierres_externos'
       else 'crm.leads + public.perfiles' end,
  md5('f05|lead|' || cd.lead_id::text),
  (select gc.gp_hash from grupos_clave gc
    where gc.tipo = cd.tipo_fuente and gc.doc = cd.doc_fuente),
  jsonb_build_object(
    'via_herencia', cd.via,
    'tipo_documento_fuente', cd.tipo_fuente,
    'difiere_por', cd.difiere_por,
    'lead_dni_valido', cd.lead_dni_valido)
from convertidos_discrepantes cd

-- 7. episodio de conversión sin identidad A/B resoluble ---------------------
union all
select
  'episodio_conversion_sin_identidad',
  'Este episodio no puede deduplicarse por persona: aporta como la regla viva hasta revisión humana y queda fuera del delta proyectado',
  'revision_humana',
  'Resolver primero la excepción documental de la persona (ver grupo); repetir el censo y recién entonces incluirlo en la deduplicación identidad/mes',
  'private.conversion_episodios',
  md5('f05|episodio-conversion|' || esi.tipo || '|' || to_char(esi.mes, 'YYYY-MM')
      || '|' || esi.episodio_uid::text),
  esi.gp_hash,
  jsonb_build_object(
    'mes', to_char(esi.mes, 'YYYY-MM'),
    'mes_sellado', esi.sellado,
    'tipo_episodio', esi.tipo,
    'canal', esi.canal,
    'anulado', esi.anulado,
    'fue_referido', esi.fue_referido,
    'aporte_numerador_ponderado', esi.aporte_numerador)
from episodios_sin_identidad esi

-- 8. episodio de capital sin identidad A/B resoluble (sin IDs) --------------
union all
select
  'episodio_capital_sin_identidad',
  'Capital que no puede vincularse a una persona: bloquea hacer obligatorio el vínculo de identidad en F1+',
  'revision_humana',
  'Mapear al caso documental pendiente de la persona (ver grupo) y revalidar; el monto no se toca, solo se resuelve la identidad',
  'private.capital_episodios',
  csi.ref_hash,
  csi.gp_hash,
  jsonb_build_object(
    'empresa', csi.empresa,
    'moneda', csi.moneda,
    'medida', csi.medida,
    'estado', csi.estado,
    'anulado', csi.anulado,
    'monto_agregado_del_caso', coalesce(csi.monto, 0))
from capital_sin_identidad csi

-- 9. candidato a demo conocido (Qorilazo 100000 PEN) ------------------------
union all
select
  'demo_por_confirmar',
  'Si es demo, infla el capital vigente de Qorilazo (lente con demo vs sin demo del censo F0); crm.cierres_externos no distingue demo',
  'requiere_confirmacion_demo',
  'Miguel confirma si este cierre es el dato DEMO conocido; si lo es, decidir marca o exclusión ANTES del backfill; esta cola no lo asume ni lo modifica',
  'crm.cierres_externos',
  md5('f05|cierre|' || c.id::text),
  (select gc.gp_hash from grupos_clave gc
    where gc.tipo = c.tipo and gc.doc = c.doc),
  jsonb_build_object(
    'cooperativa', c.cooperativa,
    'moneda', c.moneda,
    'monto', c.monto,
    'vigente', c.vigente,
    'tipo_documento', c.tipo)
from cierres c
where c.cooperativa = 'qorilazo' and c.moneda = 'PEN' and c.monto = 100000

-- 10. señales F débiles: a lo sumo UNA fila agregada por señal, cero PII ----
union all
select
  'senial_debil_agregada',
  'Coincidencia solo por señal débil: puede avisar, jamás une identidades (regla 4.2 del contrato)',
  'solo_informativo',
  'Revisión manual opcional al preparar el backfill; ninguna acción automática',
  'crm.leads vs public.perfiles/crm.cierres_externos',
  md5('f05|senial|' || s.senial),
  null::text,
  jsonb_build_object(
    'senial', s.senial,
    'leads_afectados', s.n,
    'nota', 'solo conteo agregado; sin casos individuales para no exponer coincidencias de PII')
from seniales s
),
esperados_f0(categoria, n) as (
  -- Baseline histórica observada a las 16:10:26. No se presenta como verdad
  -- eterna: la reconciliación marca explícitamente cualquier deriva viva.
  values
    ('perfil_sin_documento'::text, 1::bigint),
    ('perfil_documento_invalido', 1),
    ('clave_compartida_con_otro_rol', 2),
    ('identidad_sin_responsable', 5),
    ('veto_sin_identidad_fuerte', 4),
    ('discrepancia_documental_convertido', 1),
    ('episodio_conversion_sin_identidad', 2),
    ('episodio_capital_sin_identidad', 2),
    ('demo_por_confirmar', 1)
),
observados_f05 as (
  select e.categoria, e.n as esperado, count(c.categoria) as observado
  from esperados_f0 e
  left join casos c on c.categoria = e.categoria
  group by e.categoria, e.n
),
gate_reconciliacion as (
  select
    bool_and(o.observado = o.esperado)
      and (select count(*) from identidades where clase = 'A') = 392
      and (select count(*) from identidades where clase = 'B') = 10
      as cuadra_con_f0_canonico,
    jsonb_object_agg(o.categoria, jsonb_build_object(
      'observado', o.observado,
      'esperado_historico', o.esperado,
      'delta', o.observado - o.esperado,
      'cuadra', o.observado = o.esperado)) as categorias
  from observados_f05 o
)

-- ============================================================================
-- RESULTADO ÚNICO: casos + contexto + reconciliación contra el F0 canónico
-- ============================================================================
select * from (

select
  'F05-' || upper(left(md5('caso|' || cs.categoria || '|' || cs.referencia_hash), 12)) as caso_codigo,
  cs.categoria, cs.impacto_comercial, cs.estado_recomendado, cs.accion_propuesta,
  cs.fuente, cs.referencia_hash, cs.grupo_persona_hash, cs.detalle
from casos cs

union all
select
  'F05-CONTEXTO', 'contexto',
  null, 'control',
  'Verificar transaccion_read_only = on y la zona horaria antes de leer la cola',
  'sesion', null, null,
  jsonb_build_object(
    'zona', z.tz,
    'observado_en_lima', to_char(z.observado_en at time zone z.tz, 'YYYY-MM-DD HH24:MI:SS'),
    'transaccion_read_only', current_setting('transaction_read_only'),
    'rol_de_sesion', current_user,
    'nota', 'cola F0.5 pseudonimizada; el caso se relocaliza re-ejecutando esta misma consulta (hashes deterministas de tipo+PK); datos vivos: los conteos pueden variar entre corridas')
from zona z

union all
select
  'F05-RECONCILIACION', 'reconciliacion_f0',
  null, 'control',
  'Si algún conteo no coincide con lo esperado del F0 canónico (16:10:26 Lima), explicar la deriva por actividad viva antes de usar la cola',
  'esta consulta', null, null,
  jsonb_build_object(
    'cuadra_con_f0_canonico', gr.cuadra_con_f0_canonico,
    'gate', case when gr.cuadra_con_f0_canonico
                 then 'APROBADO'
                 else 'DETENER_Y_EXPLICAR_DERIVA' end,
    'categorias', gr.categorias,
    'identidades_automaticas', jsonb_build_object(
      'clase_A_observado', (select count(*) from identidades where clase = 'A'),
      'clase_A_esperado', 392,
      'clase_B_observado', (select count(*) from identidades where clase = 'B'),
      'clase_B_esperado', 10),
    'nota', 'El gate compara con la foto histórica 16:10:26. Si falla, la cola sigue siendo evidencia read-only, pero NO se usa para F1 hasta explicar la deriva. senial_debil_agregada no entra al gate.')
from gate_reconciliacion gr

) cola
order by categoria, caso_codigo;

rollback;
