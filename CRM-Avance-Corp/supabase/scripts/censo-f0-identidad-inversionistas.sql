-- ---------------------------------------------------------------------------
-- CENSO F0 — identidad unificada de inversionistas (SOLO LECTURA)
-- ---------------------------------------------------------------------------
-- Contrato: «Contrato arquitectonico consolidado - identidad unificada de
-- inversionistas (F0 2026-08-31)» (vault). Este censo MIDE; no crea, no
-- enlaza, no fusiona, no corrige. La identidad documental se SIMULA con CTE:
-- no existe (ni se asume) crm.inversionistas, inversionista_id ni naturaleza.
--
-- USO (lo ejecuta Camila tras revisar; NUNCA se ejecuta desde una sesión de
-- agente contra producción):
--   npx supabase db query --linked --file supabase/scripts/censo-f0-identidad-inversionistas.sql
--
-- SALVAGUARDAS:
--   · begin + set transaction read only INMEDIATO: el «solo lectura» lo hace
--     cumplir el servidor, no la disciplina de quien edite este fichero.
--   · timeouts y search_path LOCALES a la transacción; todo esquema explícito.
--   · una sola sentencia SELECT/CTE; cero DDL, cero DML, cero RPC mutadora.
--   · ROLLBACK final incondicional.
--   · PII CERO: ningún documento, teléfono, correo, nombre ni UUID individual
--     sale por el resultado; solo agregados (seccion, metrica, valor, detalle).
--   · Los núcleos private.conversion_episodios / private.capital_episodios y
--     el peso private.peso_referido_conversion se LEEN (son STABLE, solo
--     SELECT por dentro; la transacción read-only abortaría cualquier
--     escritura). Sus md5 vivos salen en 6_evidencia para contrastar con los
--     pines registrados por ATR-1/2/3a (el peso no tiene pin: informativo).
--
-- CONTEXTO DE EJECUCIÓN: requiere la sesión postgres (propietaria de los
-- objetos): los núcleos tienen EXECUTE revocado para todos los roles API y
-- crm.cierres_externos es deny-by-default (cero policies). El propietario
-- lee sin policies; las tablas con FORCE RLS del esquema private no se tocan.
--
-- ZONA HORARIA: todos los meses/fechas se calculan en America/Lima, igual que
-- los núcleos vivos. Los datos son lo OBSERVADO al momento de la corrida
-- (rotulado en la fila 0_contexto). crm.cierres_externos no tiene es_demo:
-- el censo cuenta todo lo registrado (la coop de S/100k demo incluida).
--
-- REGLAS MEDIDAS:
--   1_inventario  inventario y calidad documental por fuente + duplicados,
--                 multitipo, múltiples perfiles, convergencias, contradictorios.
--   2_clases      clases A–F del contrato, con precedencia y sin doble conteo:
--                 A perfil cliente válido único · B cierre externo válido único
--                 C convertido hereda perfil/cierre · D lead DNI = 1 identidad
--                 E revisión humana · F candidatos débiles (SOLO conteos).
--   3_responsable responsable potencial (perfil → asesor; si no, vendedor del
--                 cierre vigente más reciente) y vetos no_contactar.
--   4_conversion  regla viva vs «máximo una conversión por identidad/mes,
--                 primer episodio por confirmación → registro → id; ganador
--                 anulado NO promociona suplente», AMBAS en unidades
--                 PONDERADAS (SUM de aporte_numerador) con el factor de
--                 referido REAL de cada mes: sellado → foto de
--                 crm.periodos_cerrados.ponderacion_referido; abierto →
--                 private.peso_referido_conversion(mes). Solo deduplican las
--                 identidades documentales clase A/B; un episodio con clave
--                 E, ausente o inválida NO se deduplica (grupo técnico
--                 propio) y aporta igual que la regla viva hasta revisión
--                 humana. Delta por mes, sellado/abierto aparte.
--   5_capital     línea base del núcleo por empresa/moneda/medida/estado
--                 (empresa derivada TAMBIÉN en la base, join 1:1 al cierre)
--                 y paridad de ENRIQUECIMIENTO contra la proyección con
--                 identidad simulada. No prueba ninguna función F3.
--   6_evidencia   md5 (pg_get_functiondef y prosrc) de ambos núcleos y de
--                 private.peso_referido_conversion + el indicador REAL de
--                 transacción de solo lectura.
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
-- Fuentes normalizadas. La normalización débil (tel/correo/nombre) existe SOLO
-- para contar candidatos F; jamás produce una unión.
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
  -- El mismo contrato de formato que crm.cierres_externos (espejo de documento.ts)
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
  -- documento ya nace normalizado y con CHECK de formato en la tabla
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
-- Identidad documental SIMULADA: clave = (tipo_documento, documento normalizado)
-- ============================================================================
claves_fuentes as (
  select tipo, doc, 'perfil'::text as fuente from perfiles_cli where doc_estado = 'valido'
  union all
  select tipo, doc, 'cierre'::text from cierres
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
  -- Precedencia por clave, sin doble conteo: E (conflicto) > A (perfil) > B (cierre)
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

-- ============================================================================
-- Clases por entidad (cada entidad cuenta UNA sola vez)
-- ============================================================================
perfiles_clasif as (
  select pc.id,
    case
      when pc.doc_estado = 'ausente'  then 'E:documento_ausente'
      when pc.doc_estado = 'invalido' then 'E:documento_invalido'
      when kk.clase = 'E' and kk.n_perfiles > 1 then 'E:multiples_perfiles'
      when kk.clase = 'E' and kk.n_perfiles_no_cliente > 0 then 'E:perfil_otro_rol_misma_clave'
      when kk.clase = 'E' then 'E:tipo_contradictorio'
      else 'A'
    end as clase
  from perfiles_cli pc
  left join claves_clasif kk on kk.tipo = pc.tipo and kk.doc = pc.doc
),
cierres_clasif as (
  select c.id,
    case
      when kk.clase = 'E' then 'E:clave_en_revision'
      when kk.n_perfiles >= 1 then 'B:convergente_con_perfil'
      else 'B'
    end as clase
  from cierres c
  join claves_clasif kk on kk.tipo = c.tipo and kk.doc = c.doc
),
leads_conv_clasif as (
  -- C hereda la identidad inequívoca de su perfil o de su cierre externo
  select ln.id,
    case
      when ce.lead_id is not null and ln.perfil_id is not null then 'E:doble_via_perfil_y_cierre'
      when ce.lead_id is not null and kc.clase = 'E' then 'E:clave_en_revision'
      when ce.lead_id is not null then 'C:via_cierre'
      when ln.perfil_id is null then 'E:huerfano_sin_perfil_ni_cierre'
      when pv.doc_estado <> 'valido' then 'E:perfil_sin_documento_valido'
      when kp.clase = 'E' then 'E:clave_en_revision'
      else 'C:via_perfil'
    end as clase
  from leads_n ln
  left join cierres ce on ce.lead_id = ln.id
  left join perfiles_val pv on pv.id = ln.perfil_id
  left join claves_clasif kc on ce.lead_id is not null and kc.tipo = ce.tipo and kc.doc = ce.doc
  left join claves_clasif kp on pv.doc is not null and kp.tipo = pv.tipo and kp.doc = pv.doc
  where ln.convertido
),
convertidos_contradictorios as (
  -- El campo del lead declara un DNI. Si la fuente heredada usa CE/PASAPORTE,
  -- o usa DNI con otro valor, el vínculo requiere revisión humana: no se asume
  -- que sea una simple sustitución documental.
  select ln.id
  from leads_n ln
  left join cierres ce on ce.lead_id = ln.id
  left join perfiles_val pv on pv.id = ln.perfil_id
  where ln.convertido and ln.dni is not null
    and ((ce.lead_id is not null and (ce.tipo <> 'DNI' or ce.doc <> ln.dni))
      or (ce.lead_id is null and pv.doc is not null
          and (pv.tipo <> 'DNI' or pv.doc <> ln.dni)))
),
leads_dni_clasif as (
  -- D: lead (no convertido) cuyo DNI coincide con EXACTAMENTE una identidad DNI
  select ln.id, ln.vivo,
    case
      when kd.clase in ('A', 'B') then 'D'
      when kd.clase = 'E' then 'E:clave_en_revision'
      when exists (select 1 from claves k2 where k2.doc = ln.dni and k2.tipo <> 'DNI')
        then 'E:tipo_contradictorio'
      else 'sin_coincidencia'
    end as clase
  from leads_n ln
  left join claves_clasif kd on kd.tipo = 'DNI' and kd.doc = ln.dni
  where not ln.convertido and ln.dni is not null
),
leads_f as (
  -- F: candidatos débiles. SOLO conteos; teléfono/correo/nombre NUNCA unen.
  select lf.id,
    exists (select 1 from perfiles_cli pc where pc.tel9 is not null and pc.tel9 = lf.tel9) as m_tel,
    exists (select 1 from perfiles_cli pc where pc.correo_n is not null and pc.correo_n = lf.correo_n) as m_correo,
    (exists (select 1 from perfiles_cli pc where pc.nombre_n is not null and pc.nombre_n = lf.nombre_n)
      or exists (select 1 from cierres c where c.nombre_n is not null and c.nombre_n = lf.nombre_n)) as m_nombre
  from leads_n lf
  left join leads_dni_clasif ldc on ldc.id = lf.id
  where not lf.convertido
    and (lf.dni is null or ldc.clase = 'sin_coincidencia')
),

-- ============================================================================
-- Responsable potencial y no_contactar (sección 3)
-- ============================================================================
identidades as (
  select kk.tipo, kk.doc, kk.clase from claves_clasif kk where kk.clase in ('A', 'B')
),
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
  select i.tipo, i.doc,
    coalesce(rp.asesor_perfil_id, rc.vendedor_id) as responsable_id,
    case
      when rp.asesor_perfil_id is not null then 'perfil'
      when rc.vendedor_id is not null then 'cierre'
      else 'ausente'
    end as fuente_responsable,
    (rp.asesor_perfil_id is not null and rc.vendedor_id is not null
      and rp.asesor_perfil_id <> rc.vendedor_id) as conflictivo
  from identidades i
  left join resp_perfil rp on rp.tipo = i.tipo and rp.doc = i.doc
  left join resp_cierre rc on rc.tipo = i.tipo and rc.doc = i.doc
),
responsables_estado as (
  select r.*,
    case
      when r.responsable_id is null then 'ausente'
      when exists (select 1 from crm.equipo e where e.perfil_id = r.responsable_id and e.activo)
        then 'vigente'
      else 'inactivo'
    end as estado_responsable
  from responsables r
),
lead_identidad as (
  -- vínculo SOLO documental (o heredado de perfil/cierre); nunca por señal débil
  select ln.id as lead_id, ln.no_contactar, ln.vivo, ident.identidad,
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
veto_conflictos as (
  -- la clave documental porta un veto Y a la vez leads vivos sin veto
  select li.identidad
  from lead_identidad li
  where li.identidad is not null
  group by li.identidad
  having bool_or(li.no_contactar) and bool_or(li.vivo and not li.no_contactar)
),

-- ============================================================================
-- Conversión (sección 4): regla viva vs identidad/mes, con el factor de
-- referido REAL de cada mes y en unidades PONDERADAS (SUM, no COUNT)
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
  -- Factor de referido REAL por mes: si el mes está sellado manda la foto
  -- crm.periodos_cerrados.ponderacion_referido; si está abierto, el peso que
  -- usaría hoy el núcleo: private.peso_referido_conversion(mes).
  select m.mes,
    (pc.periodo is not null) as sellado,
    case when pc.periodo is not null then pc.ponderacion_referido
         else private.peso_referido_conversion(m.mes) end as factor
  from meses m
  left join crm.periodos_cerrados pc on pc.periodo = m.mes
),
episodios_nucleo as (
  -- p_factor = factor real del mes: ambas reglas se comparan en unidades
  -- PONDERADAS. El aporte_numerador del núcleo ya trae la semántica viva:
  -- anulado → 0, referido → factor, resto → 1.
  select fm.mes, ep.tipo, ep.lead_id, ep.operacion_id, ep.anulado,
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
  -- un episodio de cierre por (mes, lead), como deduplica la lectura viva;
  -- se conserva el mayor aporte del grupo (mismo lead ⇒ mismo anulado)
  select en.mes, 'cierre'::text as tipo, en.lead_id, null::uuid as operacion_id,
         bool_or(en.anulado) as anulado, bool_or(en.fue_referido) as fue_referido,
         max(en.aporte_numerador) as aporte_numerador,
         min(en.fecha_numerador) as confirmado_en
  from episodios_nucleo en
  where en.tipo = 'cierre'
  group by en.mes, en.lead_id
  union all
  select en.mes, 'operacion'::text, null::uuid, en.operacion_id,
         en.anulado, en.fue_referido, en.aporte_numerador, en.fecha_numerador
  from episodios_nucleo en
  where en.tipo = 'operacion'
),
episodios_id as (
  -- Deduplica SOLO por identidad documental resoluble: la clave (tipo, doc)
  -- debe existir en claves_clasif con clase A o B (CTE identidades). Un
  -- episodio con clave E, ausente o inválida NO se deduplica con ningún otro:
  -- recibe un grupo técnico por episodio (grupo_dedupe_no_resuelto|…), que NO
  -- es una identidad ni algo provisional, y aporta igual que la regla viva
  -- hasta revisión humana.
  select e.mes, e.tipo, e.anulado, e.fue_referido, e.aporte_numerador,
    e.confirmado_en,
    coalesce(e.lead_id, e.operacion_id) as episodio_uid,
    (ident.identidad_ab is not null) as identidad_resoluble,
    coalesce(ident.identidad_ab,
             'grupo_dedupe_no_resuelto|' || e.tipo || '|'
               || coalesce(e.lead_id, e.operacion_id)::text) as grupo_dedupe,
    case
      when e.tipo = 'operacion' then 'operacion'
      when exists (select 1 from cierres c where c.lead_id = e.lead_id) then 'cooperativa'
      else 'avance'
    end as canal,
    case
      when e.tipo = 'operacion'
        then (select o.creado_en from operaciones_n o where o.id = e.operacion_id)
      else (select ln.convertido_en from leads_n ln where ln.id = e.lead_id)
    end as registrado_en
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
),
ganadores as (
  -- primer episodio por confirmación → registro → id, DENTRO de cada grupo
  -- de dedupe. El ganador se elige INCLUYENDO anulados: un ganador anulado
  -- aporta 0 y NO promociona suplente.
  select ei.*,
    row_number() over (
      partition by ei.mes, ei.grupo_dedupe
      order by ei.confirmado_en asc nulls last, ei.registrado_en asc nulls last, ei.episodio_uid
    ) as orden
  from episodios_id ei
),
combos_mes as (
  -- por construcción solo pueden agrupar >1 los grupos con identidad A/B
  select g.mes, g.grupo_dedupe,
    count(*) filter (where g.canal = 'avance') as n_avance,
    count(*) filter (where g.canal = 'cooperativa') as n_coop,
    count(*) filter (where g.canal = 'operacion') as n_oper
  from ganadores g
  group by g.mes, g.grupo_dedupe
  having count(*) > 1
),
combos_clasif as (
  select cm.mes,
    count(*) as identidades_multi,
    count(*) filter (where cm.n_avance >= 1 and cm.n_coop >= 1) as avance_y_cooperativa,
    count(*) filter (where cm.n_coop >= 2) as cooperativa_y_cooperativa,
    count(*) filter (where cm.n_oper >= 1 and (cm.n_avance >= 1 or cm.n_coop >= 1)) as operacion_y_otro,
    count(*) filter (where cm.n_oper >= 2 and cm.n_avance = 0 and cm.n_coop = 0) as operacion_y_operacion
  from combos_mes cm
  group by cm.mes
),
conv_detalle as (
  -- ambas reglas en unidades PONDERADAS (SUM de aporte_numerador, no COUNT):
  -- viva = todo aporte del núcleo; nueva = el ganador no anulado de cada
  -- grupo A/B, y los episodios no resolubles aportan igual que la regla viva.
  select g.mes,
    sum(g.aporte_numerador)::numeric as viva,
    sum(case
          when not g.identidad_resoluble then g.aporte_numerador
          when g.orden = 1 and not g.anulado then g.aporte_numerador
          else 0
        end)::numeric as nueva,
    count(*) filter (where not g.identidad_resoluble) as episodios_no_resolubles,
    fm.sellado, fm.factor
  from ganadores g
  join factores_mes fm on fm.mes = g.mes
  group by g.mes, fm.sellado, fm.factor
),

-- ============================================================================
-- Capital (sección 5): línea base del núcleo con empresa derivada TAMBIÉN en
-- la base (LEFT JOIN 1:1 al cierre) y proyección que agrega la identidad
-- simulada SIN cambiar filas. La paridad es de ENRIQUECIMIENTO F0; no existe
-- todavía función F3 que probar.
-- ============================================================================
capital_base as materialized (
  -- ±infinity: forma documentada por el propio núcleo (ventanas por día Lima)
  select * from private.capital_episodios(
    '-infinity'::timestamptz, 'infinity'::timestamptz, true, null::uuid[])
),
capital_empresa as (
  -- empresa para la LÍNEA BASE: LEFT JOIN 1:1 (cierres_externos.id es PK);
  -- avance para todo episodio no cooperativo
  select cb.*,
    case when cb.tipo = 'cooperativa'
         then coalesce(cx.cooperativa, 'cooperativa_desconocida')
         else 'avance' end as empresa
  from capital_base cb
  left join cierres cx on cb.tipo = 'cooperativa' and cx.id = cb.cierre_externo_id
),
capital_dim as (
  -- proyección: agrega la identidad simulada SIN cambiar filas
  select cemp.*,
    case when cemp.tipo = 'cooperativa'
         then (select c.tipo || '|' || c.doc from cierres c
                join identidades i on i.tipo = c.tipo and i.doc = c.doc
               where c.id = cemp.cierre_externo_id)
         else (select pv.tipo || '|' || pv.doc from perfiles_val pv
                join identidades i on i.tipo = pv.tipo and i.doc = pv.doc
               where pv.id = cemp.cliente_id and pv.doc_estado = 'valido') end as identidad
  from capital_empresa cemp
),
capital_agg_base as (
  select cb2.empresa, coalesce(cb2.moneda, '(sin moneda)') as moneda,
         coalesce(cb2.medida, '(sin medida)') as medida,
         coalesce(cb2.estado, '(sin estado)') as estado,
         count(*) as n, coalesce(sum(cb2.monto), 0) as monto
  from capital_empresa cb2
  group by 1, 2, 3, 4
),
capital_agg_dim as (
  select cd.empresa, coalesce(cd.moneda, '(sin moneda)') as moneda,
         coalesce(cd.medida, '(sin medida)') as medida,
         coalesce(cd.estado, '(sin estado)') as estado,
         count(*) as n, coalesce(sum(cd.monto), 0) as monto
  from capital_dim cd
  group by 1, 2, 3, 4
),
capital_paridad as (
  -- base vs proyección POR EMPRESA/moneda/medida/estado; conteo y monto
  -- viajan SEPARADOS, jamás sumados en un solo número
  select
    coalesce(sum(abs(coalesce(b.n, 0) - coalesce(d.n, 0))), 0) as dif_conteo,
    coalesce(sum(abs(coalesce(b.monto, 0) - coalesce(d.monto, 0))), 0) as dif_monto
  from capital_agg_base b
  full join capital_agg_dim d using (empresa, moneda, medida, estado)
),
capital_cardinalidad as (
  -- prueba explícita de cardinalidad 1:1 de los dos enriquecimientos
  select (select count(*) from capital_base) as n_base,
         (select count(*) from capital_empresa) as n_empresa,
         (select count(*) from capital_dim) as n_dim
),
capital_filas as (
  select cd.empresa, cd.moneda, cd.medida, coalesce(cd.estado, '(sin estado)') as estado,
         count(*) as n, coalesce(sum(cd.monto), 0) as monto,
         count(*) filter (where cd.identidad is null) as sin_identidad,
         coalesce(sum(cd.monto) filter (where cd.identidad is null), 0) as monto_sin_identidad
  from capital_dim cd
  group by 1, 2, 3, 4
),

-- ============================================================================
-- Evidencia (sección 6)
-- ============================================================================
evidencia as (
  select 'private.conversion_episodios'::text as fn,
         md5(pg_get_functiondef(p.oid)) as def_md5,
         md5(p.prosrc) as prosrc_md5,
         '71213ac03eb32e333723399538d35d83'::text as pin_prosrc,
         null::text as pin_prosrc_alterno
  from pg_catalog.pg_proc p
  where p.oid = 'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure
  union all
  select 'private.capital_episodios',
         md5(pg_get_functiondef(p.oid)),
         md5(p.prosrc),
         '872f5ad4362f66a18f4a3806453f78a0',
         '90f1d8c2342becb94cc3d3e023227078'
  from pg_catalog.pg_proc p
  where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure
  union all
  -- el peso del referido que alimenta p_factor en meses abiertos; sin pin ATR
  -- registrado: la huella es informativa (coincide_pin saldrá null)
  select 'private.peso_referido_conversion',
         md5(pg_get_functiondef(p.oid)),
         md5(p.prosrc),
         null::text,
         null::text
  from pg_catalog.pg_proc p
  where p.oid = 'private.peso_referido_conversion(date)'::regprocedure
)

-- ============================================================================
-- RESULTADO ÚNICO: (seccion, metrica, valor, detalle) — agregado, reproducible
-- ============================================================================
select * from (

select '0_contexto'::text as seccion, 'censo_f0_identidad'::text as metrica,
       null::numeric as valor,
       jsonb_build_object(
         'zona', z.tz,
         'observado_en_lima', to_char(z.observado_en at time zone z.tz, 'YYYY-MM-DD HH24:MI:SS'),
         'transaccion_read_only', current_setting('transaction_read_only'),
         'rol_de_sesion', current_user,
         'nota', 'Datos observados en vivo; solo agregados, PII cero. cierres_externos no distingue demo (sin es_demo).') as detalle
from zona z

-- ------------------------------------------------ 1. inventario y calidad --
union all
select '1_inventario', 'perfiles_cliente_total',
       (select count(*) from perfiles_cli)::numeric,
       jsonb_build_object(
         'activos', (select count(*) from perfiles_cli where activo),
         'inactivos', (select count(*) from perfiles_cli where not activo))

union all
select '1_inventario', 'perfiles_cliente_documento',
       (select count(*) from perfiles_cli)::numeric,
       jsonb_build_object(
         'ausente', (select count(*) from perfiles_cli where doc_estado = 'ausente'),
         'valido', (select count(*) from perfiles_cli where doc_estado = 'valido'),
         'invalido', (select count(*) from perfiles_cli where doc_estado = 'invalido'),
         'valido_por_tipo', (select coalesce(jsonb_object_agg(t.tipo, t.n), '{}'::jsonb)
                               from (select tipo, count(*) as n from perfiles_cli
                                      where doc_estado = 'valido' group by tipo) t))

union all
select '1_inventario', 'perfiles_no_cliente_con_documento_valido',
       (select count(*) from perfiles_val where rol <> 'cliente' and doc_estado = 'valido')::numeric,
       jsonb_build_object(
         'colisionan_con_clave_censada',
         (select count(*) from perfiles_val pv
           where pv.rol <> 'cliente' and pv.doc_estado = 'valido'
             and exists (select 1 from claves k where k.tipo = pv.tipo and k.doc = pv.doc)),
         'nota', 'colaborador-inversionista: si colisiona, es revisión E en el backfill')

union all
select '1_inventario', 'leads_total',
       (select count(*) from leads_n)::numeric,
       jsonb_build_object(
         'vivos', (select count(*) from leads_n where vivo),
         'convertidos', (select count(*) from leads_n where convertido),
         'descartados', (select count(*) from leads_n where etapa = 'descartado'),
         'inactivos', (select count(*) from leads_n where not activo),
         'con_perfil', (select count(*) from leads_n where perfil_id is not null),
         'sin_perfil', (select count(*) from leads_n where perfil_id is null))

union all
select '1_inventario', 'leads_dni',
       (select count(*) from leads_n)::numeric,
       jsonb_build_object(
         'ausente', (select count(*) from leads_n where dni is null),
         'valido', (select count(*) from leads_n where dni ~ '^[0-9]{8}$'),
         'invalido', (select count(*) from leads_n where dni is not null and dni !~ '^[0-9]{8}$'))

union all
select '1_inventario', 'leads_convertidos',
       (select count(*) from leads_n where convertido)::numeric,
       jsonb_build_object(
         'con_perfil', (select count(*) from leads_n where convertido and perfil_id is not null),
         'sin_perfil', (select count(*) from leads_n where convertido and perfil_id is null),
         'con_cierre_externo', (select count(*) from leads_n ln
                                 where ln.convertido
                                   and exists (select 1 from cierres c where c.lead_id = ln.id)),
         'huerfanos', (select count(*) from leads_conv_clasif where clase = 'E:huerfano_sin_perfil_ni_cierre'),
         'doble_via', (select count(*) from leads_conv_clasif where clase = 'E:doble_via_perfil_y_cierre'),
         'contradictorios_dni', (select count(*) from convertidos_contradictorios))

union all
select '1_inventario', 'cierres_' || c.cooperativa,
       count(*)::numeric,
       jsonb_build_object(
         'vigentes', count(*) filter (where c.vigente),
         'anulados', count(*) filter (where not c.vigente),
         'monto_pen_vigente', coalesce(sum(c.monto) filter (
           where c.vigente and c.moneda = 'PEN'), 0),
         'por_tipo_documento',
           (select coalesce(jsonb_object_agg(t.tipo, t.n), '{}'::jsonb)
              from (select c2.tipo, count(*) as n from cierres c2
                     where c2.cooperativa = c.cooperativa group by c2.tipo) t))
from cierres c
group by c.cooperativa

union all
select '1_inventario', 'catalogo_cooperativas',
       (select count(*) from cierres)::numeric,
       jsonb_build_object(
         'qorilazo', (select count(*) from cierres where cooperativa = 'qorilazo'),
         'prodelco', (select count(*) from cierres where cooperativa = 'prodelco'),
         'inesperadas', (select count(*) from cierres
                          where cooperativa not in ('qorilazo', 'prodelco')),
         'esperadas_sin_registros', to_jsonb(array_remove(array[
           case when not exists (select 1 from cierres where cooperativa = 'qorilazo')
                then 'qorilazo' end,
           case when not exists (select 1 from cierres where cooperativa = 'prodelco')
                then 'prodelco' end
         ]::text[], null)),
         'nota', 'catálogo F0 explícito: solo Avance, Qorilazo y Prodelco')

union all
select '1_inventario', 'contratos_total',
       (select count(*) from public.contratos c where not c.es_demo)::numeric,
       jsonb_build_object(
         'demo', (select count(*) from public.contratos c where c.es_demo),
         'por_estado', (select coalesce(jsonb_object_agg(t.estado, t.n), '{}'::jsonb)
                          from (select c.estado, count(*) as n from public.contratos c
                                 where not c.es_demo group by c.estado) t))

union all
select '1_inventario', 'operaciones_cartera_total',
       (select count(*) from operaciones_n)::numeric,
       jsonb_build_object(
         'renovacion', (select count(*) from operaciones_n where tipo = 'renovacion'),
         'upgrade', (select count(*) from operaciones_n where tipo = 'upgrade'),
         'elegibles_conversion', (select count(*) from operaciones_n where elegible_conversion))

union all
select '1_inventario', 'claves_documento_total',
       (select count(*) from claves)::numeric,
       jsonb_build_object(
         'solo_perfil', (select count(*) from claves where n_perfiles >= 1 and n_cierres = 0),
         'solo_cierre', (select count(*) from claves where n_perfiles = 0 and n_cierres >= 1),
         'convergentes_perfil_y_cierre', (select count(*) from claves where n_perfiles >= 1 and n_cierres >= 1))

union all
select '1_inventario', 'duplicados_multiples_perfiles_misma_clave',
       (select count(*) from claves where n_perfiles > 1)::numeric,
       jsonb_build_object(
         'perfiles_involucrados', (select coalesce(sum(n_perfiles), 0) from claves where n_perfiles > 1))

union all
select '1_inventario', 'mismo_documento_en_tipos_distintos',
       (select count(*) from docs_multitipo)::numeric,
       jsonb_build_object(
         'claves_involucradas', (select count(*) from claves_clasif where multitipo))

union all
select '1_inventario', 'convergencias_perfil_cierre',
       (select count(*) from claves where n_perfiles >= 1 and n_cierres >= 1)::numeric,
       jsonb_build_object('nota', 'la misma clave documental existe en public.perfiles y en crm.cierres_externos')

-- ------------------------------------------------------- 2. clases A–F -----
union all
select '2_clases', 'precedencia',
       null::numeric,
       jsonb_build_object(
         'claves', 'E (conflicto) > A (perfil) > B (cierre); una clave, una clase',
         'leads', 'C (convertido hereda) > D (DNI = 1 identidad) > E (revisión) > F (débil, solo conteo)',
         'doble_conteo', 'ninguna entidad aparece en dos clases')

union all
select '2_clases', 'clase_A_claves',
       (select count(*) from claves_clasif where clase = 'A')::numeric,
       jsonb_build_object(
         'con_cierres_convergentes', (select count(*) from claves_clasif where clase = 'A' and n_cierres >= 1))

union all
select '2_clases', 'clase_B_claves',
       (select count(*) from claves_clasif where clase = 'B')::numeric,
       jsonb_build_object('nota', 'identidad nueva solo por cierre externo (sin perfil Portal)')

union all
select '2_clases', 'clase_E_claves',
       (select count(*) from claves_clasif where clase = 'E')::numeric,
       jsonb_build_object(
         'multiples_perfiles', (select count(*) from claves_clasif where clase = 'E' and n_perfiles > 1),
         'perfil_otro_rol_misma_clave', (select count(*) from claves_clasif
                                           where clase = 'E' and n_perfiles_no_cliente > 0),
         'tipo_contradictorio', (select count(*) from claves_clasif
                                  where clase = 'E' and n_perfiles <= 1
                                    and n_perfiles_no_cliente = 0 and multitipo))

union all
select '2_clases', 'clase_A_perfiles',
       (select count(*) from perfiles_clasif where clase = 'A')::numeric,
       jsonb_build_object('universo', 'public.perfiles con rol cliente')

union all
select '2_clases', 'clase_E_perfiles',
       (select count(*) from perfiles_clasif where clase like 'E:%')::numeric,
       (select coalesce(jsonb_object_agg(t.clase, t.n), '{}'::jsonb)
          from (select clase, count(*) as n from perfiles_clasif
                 where clase like 'E:%' group by clase) t)

union all
select '2_clases', 'clase_B_cierres',
       (select count(*) from cierres_clasif where clase like 'B%')::numeric,
       jsonb_build_object(
         'nuevos', (select count(*) from cierres_clasif where clase = 'B'),
         'convergentes_con_perfil', (select count(*) from cierres_clasif where clase = 'B:convergente_con_perfil'),
         'en_revision', (select count(*) from cierres_clasif where clase like 'E:%'))

union all
select '2_clases', 'clase_C_leads_convertidos',
       (select count(*) from leads_conv_clasif where clase like 'C:%')::numeric,
       jsonb_build_object(
         'via_perfil', (select count(*) from leads_conv_clasif where clase = 'C:via_perfil'),
         'via_cierre', (select count(*) from leads_conv_clasif where clase = 'C:via_cierre'))

union all
select '2_clases', 'clase_E_leads_convertidos',
       (select count(*) from leads_conv_clasif where clase like 'E:%')::numeric,
       (select coalesce(jsonb_object_agg(t.clase, t.n), '{}'::jsonb)
          from (select clase, count(*) as n from leads_conv_clasif
                 where clase like 'E:%' group by clase) t)

union all
select '2_clases', 'clase_D_leads',
       (select count(*) from leads_dni_clasif where clase = 'D')::numeric,
       jsonb_build_object(
         'vivos', (select count(*) from leads_dni_clasif where clase = 'D' and vivo),
         'no_vivos', (select count(*) from leads_dni_clasif where clase = 'D' and not vivo))

union all
select '2_clases', 'clase_E_leads_no_convertidos',
       (select count(*) from leads_dni_clasif where clase like 'E:%')::numeric,
       (select coalesce(jsonb_object_agg(t.clase, t.n), '{}'::jsonb)
          from (select clase, count(*) as n from leads_dni_clasif
                 where clase like 'E:%' group by clase) t)

union all
select '2_clases', 'leads_sin_coincidencia_documental',
       (select count(*) from leads_dni_clasif where clase = 'sin_coincidencia')::numeric,
       jsonb_build_object('nota', 'con DNI pero sin identidad censada; la identidad nacería al convertir')

union all
select '2_clases', 'clase_F_candidatos',
       (select count(*) from leads_f where m_tel or m_correo or m_nombre)::numeric,
       jsonb_build_object(
         'por_telefono', (select count(*) from leads_f where m_tel),
         'por_correo', (select count(*) from leads_f where m_correo),
         'por_nombre', (select count(*) from leads_f where m_nombre),
         'universo', (select count(*) from leads_f),
         'nota', 'solo conteos; teléfono/correo/nombre JAMÁS unen identidades')

-- --------------------------------------- 3. responsable y no_contactar -----
union all
select '3_responsable', 'identidades_automaticas',
       (select count(*) from identidades)::numeric,
       jsonb_build_object(
         'clase_A', (select count(*) from identidades where clase = 'A'),
         'clase_B', (select count(*) from identidades where clase = 'B'))

union all
select '3_responsable', 'responsable_potencial',
       (select count(*) from responsables_estado where responsable_id is not null)::numeric,
       jsonb_build_object(
         'desde_perfil', (select count(*) from responsables_estado where fuente_responsable = 'perfil'),
         'desde_cierre', (select count(*) from responsables_estado where fuente_responsable = 'cierre'),
         'ausente', (select count(*) from responsables_estado where estado_responsable = 'ausente'),
         'inactivo', (select count(*) from responsables_estado where estado_responsable = 'inactivo'),
         'conflictivo_perfil_vs_cierre', (select count(*) from responsables_estado where conflictivo),
         'regla', 'perfil → asesor_perfil_id; si no, vendedor snapshot del cierre vigente más reciente')

union all
select '3_responsable', 'vetos_no_contactar',
       (select count(*) from lead_identidad where no_contactar)::numeric,
       jsonb_build_object(
         'vinculables_a_identidad', (select count(*) from lead_identidad
                                      where no_contactar and clase_clave in ('A', 'B')),
         'sobre_clave_en_revision', (select count(*) from lead_identidad
                                      where no_contactar and identidad is not null
                                        and (clase_clave = 'E' or clase_clave is null)),
         'no_vinculables', (select count(*) from lead_identidad where no_contactar and identidad is null),
         'claves_con_conflicto_de_veto', (select count(*) from veto_conflictos),
         'nota', 'conflicto = la clave documental porta un veto y a la vez tiene leads vivos sin veto')

-- ------------------------------------------------------- 4. conversión -----
union all
select '4_conversion', 'mes_' || to_char(cd.mes, 'YYYY-MM'),
       (cd.viva - cd.nueva)::numeric,
       jsonb_build_object(
         'regla_viva_ponderada', cd.viva,
         'regla_identidad_mes_ponderada', cd.nueva,
         'delta_ponderado', cd.viva - cd.nueva,
         'mes_sellado', cd.sellado,
         'factor_referido_usado', cd.factor,
         'factor_fuente', case when cd.sellado
             then 'crm.periodos_cerrados.ponderacion_referido (mes sellado)'
             else 'private.peso_referido_conversion(mes) (mes abierto)' end,
         'episodios_sin_identidad_ab', cd.episodios_no_resolubles,
         'identidades_con_varios_episodios', coalesce(cc.identidades_multi, 0),
         'combinaciones', jsonb_build_object(
           'avance_y_cooperativa', coalesce(cc.avance_y_cooperativa, 0),
           'cooperativa_y_cooperativa', coalesce(cc.cooperativa_y_cooperativa, 0),
           'operacion_y_otro', coalesce(cc.operacion_y_otro, 0),
           'operacion_y_operacion', coalesce(cc.operacion_y_operacion, 0)),
         'nota', 'unidades ponderadas (SUM de aporte_numerador); dedupe solo entre identidades A/B; ganador incluye anulados y un ganador anulado no promociona suplente')
from conv_detalle cd
left join combos_clasif cc on cc.mes = cd.mes

union all
select '4_conversion', 'episodios_sin_identidad_resoluble',
       (select count(*) from episodios_id where not identidad_resoluble)::numeric,
       jsonb_build_object(
         'cierres', (select count(*) from episodios_id where not identidad_resoluble and tipo = 'cierre'),
         'operaciones', (select count(*) from episodios_id where not identidad_resoluble and tipo = 'operacion'),
         'meses_con_episodios_no_resolubles', (select count(distinct mes) from episodios_id where not identidad_resoluble),
         'aporte_ponderado', (select coalesce(sum(aporte_numerador), 0) from episodios_id where not identidad_resoluble),
         'nota', 'clave documental E, ausente o inválida: NO se deduplican entre sí; aportan igual que la regla viva hasta revisión humana; el delta proyectado sale SOLO de identidades A/B')

union all
select '4_conversion', 'total',
       coalesce((select sum(viva - nueva) from conv_detalle), 0)::numeric,
       jsonb_build_object(
         'viva_total_ponderada', coalesce((select sum(viva) from conv_detalle), 0),
         'identidad_total_ponderada', coalesce((select sum(nueva) from conv_detalle), 0),
         'meses_medidos', (select count(*) from conv_detalle),
         'meses_afectados', (select count(*) from conv_detalle where viva <> nueva),
         'meses_afectados_sellados', (select count(*) from conv_detalle where viva <> nueva and sellado),
         'meses_afectados_abiertos', (select count(*) from conv_detalle where viva <> nueva and not sellado),
         'fuente', 'private.conversion_episodios vivo (STABLE, solo SELECT) con el factor de referido real por mes: sellado = foto de crm.periodos_cerrados; abierto = private.peso_referido_conversion')

-- ---------------------------------------------------------- 5. capital -----
union all
select '5_capital',
       'capital_' || cf.empresa || '_' || cf.moneda || '_' || cf.medida || '_' || cf.estado,
       cf.monto::numeric,
       jsonb_build_object(
         'episodios', cf.n,
         'sin_identidad_resoluble', cf.sin_identidad,
         'monto_sin_identidad', cf.monto_sin_identidad)
from capital_filas cf

union all
select '5_capital', 'paridad_enriquecimiento',
       (case when cp.dif_conteo = 0 and cp.dif_monto = 0 then 0 else 1 end)::numeric,
       jsonb_build_object(
         'diferencia_conteo', cp.dif_conteo,
         'diferencia_monto', cp.dif_monto,
         'esperado', 0,
         'valor_semantica', '0 = ambas diferencias son cero; 1 = alguna difiere (ver detalle, conteo y monto separados)',
         'comparacion', 'línea base con empresa derivada vs proyección con identidad simulada, por empresa/moneda/medida/estado',
         'nota', 'paridad de ENRIQUECIMIENTO F0: comprueba que derivar empresa e identidad no altera filas ni montos del núcleo; NO prueba ninguna función F3 (no existe todavía)')
from capital_paridad cp

union all
select '5_capital', 'cardinalidad_enriquecimiento',
       (case when cq.n_base = cq.n_empresa and cq.n_base = cq.n_dim then 0 else 1 end)::numeric,
       jsonb_build_object(
         'episodios_nucleo', cq.n_base,
         'episodios_con_empresa', cq.n_empresa,
         'episodios_con_identidad', cq.n_dim,
         'esperado', 'los tres iguales: LEFT JOIN 1:1 sobre la PK de cierres_externos',
         'valor_semantica', '0 = cardinalidad 1:1 intacta; 1 = algún join duplicó o perdió filas')
from capital_cardinalidad cq

union all
select '5_capital', 'total_empresa_' || te.empresa,
       te.episodios::numeric,
       jsonb_build_object(
         'monto_por_moneda_y_medida', te.montos,
         'nota', 'totales de control por empresa; PEN y USD jamás se suman')
from (
  select t.empresa, sum(t.n) as episodios, jsonb_object_agg(t.k, t.monto) as montos
  from (
    select cd.empresa,
           coalesce(cd.moneda, '(sin moneda)') || '_' || coalesce(cd.medida, '(sin medida)') as k,
           count(*) as n, coalesce(sum(cd.monto), 0) as monto
    from capital_dim cd
    group by 1, 2
  ) t
  group by t.empresa
) te

union all
select '5_capital', 'episodios_sin_identidad_resoluble',
       (select count(*) from capital_dim where identidad is null)::numeric,
       jsonb_build_object(
         'avance', (select count(*) from capital_dim where identidad is null and empresa = 'avance'),
         'cooperativas', (select count(*) from capital_dim where identidad is null and empresa <> 'avance'),
         'nota', 'clientes sin documento válido en el perfil; quedan aparte, sin unión')

-- --------------------------------------------------------- 6. evidencia ----
union all
select '6_evidencia', 'md5_' || ev.fn,
       null::numeric,
       jsonb_build_object(
         'pg_get_functiondef_md5', ev.def_md5,
         'prosrc_md5', ev.prosrc_md5,
         'pin_registrado_prosrc', ev.pin_prosrc,
         'pin_alterno_prosrc', ev.pin_prosrc_alterno,
         'coincide_pin', (ev.prosrc_md5 = ev.pin_prosrc
                           or ev.prosrc_md5 = coalesce(ev.pin_prosrc_alterno, '')))
from evidencia ev

union all
select '6_evidencia', 'transaccion_read_only',
       (case when current_setting('transaction_read_only') = 'on' then 1 else 0 end)::numeric,
       jsonb_build_object('transaction_read_only', current_setting('transaction_read_only'))

) censo
order by seccion, metrica;

rollback;
