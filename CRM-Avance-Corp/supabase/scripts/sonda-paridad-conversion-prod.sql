-- Sonda de PARIDAD de conversión contra PRODUCCIÓN — SOLO LECTURA.
-- Patrón de supabase/scripts/prueba-contrato-cierre-mes-estado-prod.sql:
-- transacción read only, claims de un perfil Gerencia vía set_config (bajo la
-- sesión postgres del operador: no eleva nada), rollback al final.
-- Solo agregados: ningún dato personal sale por la terminal.
begin transaction read only;

do $impersonar$ begin
  perform set_config('request.jwt.claims', json_build_object(
    'sub', (select p.id from public.perfiles p
            where private.rol_crm(p.id) = 'gerencia' and p.activo order by p.id limit 1),
    'role', 'authenticated')::text, true);
end $impersonar$;

-- 0) contexto
select (now() at time zone 'America/Lima')::text as ahora_lima,
  (select count(*) from crm.periodos_cerrados) as periodos_cerrados,
  (select string_agg(periodo::text, ',' order by periodo) from crm.periodos_cerrados) as meses_sellados;

-- 1) núcleo directo (como postgres), septiembre 1..21 Lima
with ep as (
  select * from private.conversion_episodios(
    '2026-09-01 00:00'::timestamp at time zone 'America/Lima',
    '2026-09-22 00:00'::timestamp at time zone 'America/Lima',
    '2026-09-01'::date, true, null, private.peso_referido_conversion('2026-09-01'::date))
)
select 'nucleo_directo_sep_1_21' as sonda,
  sum(aporte_divisor) as divisor, round(sum(aporte_numerador),4) as numerador,
  round(100.0*sum(aporte_numerador)/nullif(sum(aporte_divisor),0),2) as pct,
  count(*) filter (where tipo='recibido') as llegadas,
  count(*) filter (where tipo='recibido' and aporte_divisor=0 and not fue_referido) as manuales,
  count(*) filter (where tipo='recibido' and fue_referido) as referidos,
  count(*) filter (where tipo='cierre' and not anulado and origen in ('landing','formulario')) as cierres_lf,
  count(*) filter (where tipo='cierre' and not anulado and origen='referido') as cierres_ref,
  count(*) filter (where tipo='cierre' and anulado) as cierres_anulados,
  count(*) filter (where tipo='cierre' and not anulado and origen not in ('landing','formulario','referido')) as cierres_otros_origenes,
  count(*) filter (where tipo='operacion') as operaciones,
  round(coalesce(sum(aporte_numerador) filter (where tipo='operacion'),0),4) as aporte_operaciones,
  count(*) filter (where tipo='recibido' and analista_id is null) as llegadas_sin_analista
from ep;

-- 2) M mensual (lo que ven Ranking, Metas, Rendimiento, HOY supervisor/analista)
with m as (select crm.conversion_mensual_fn('2026-09-01'::date) j)
select 'M_conversion_mensual_fn_sep' as sonda,
  j->'total'->>'divisor' as divisor, j->'total'->>'numerador' as numerador, j->'total'->>'conversion_pct' as pct,
  j->'total'->>'cierres_no_referidos' as cnr, j->'total'->>'cierres_referidos' as cr,
  j->'cierre'->>'cerrado' as cerrado, j->>'modelo_conversion' as modelo,
  j->'cobertura' as cobertura, j->'ponderacion' as ponderacion, j->'fuentes' as fuentes,
  (select count(*) from jsonb_array_elements(j->'responsables')) as n_resp,
  (select sum((r->>'divisor')::numeric) from jsonb_array_elements(j->'responsables') r) as sum_div_resp,
  (select round(sum((r->>'numerador')::numeric),4) from jsonb_array_elements(j->'responsables') r) as sum_num_resp,
  (select string_agg(k, ',' order by k) from jsonb_object_keys(j) k) as claves
from m;

-- 3) R rango = mes hasta hoy (héroes de Resumen y Conversiones)
with r as (select crm.metricas_conversiones_fn('2026-09-01'::date, '2026-09-21'::date, null) j)
select 'R_metricas_conversiones_fn_sep_1_21' as sonda,
  j->'nucleo'->>'divisor' as divisor, j->'nucleo'->>'numerador' as numerador, j->'nucleo'->>'conversion_pct' as pct,
  j->'nucleo'->>'cierres_no_referidos' as cnr, j->'nucleo'->>'cierres_referidos' as cr, j->'nucleo'->>'operaciones_cartera' as ops,
  j->'nucleo'->>'llegadas' as llegadas, j->'nucleo'->>'altas_manuales' as manuales, j->'nucleo'->>'referidos_recibidos' as refs,
  j->'nucleo'->>'incluye_cartera' as incluye_cartera, j->'nucleo'->>'base' as base,
  j->'nucleo'->>'peso_referido' as peso_ref, j->'nucleo'->>'peso_renovacion' as peso_ren,
  j->'sondas'->>'cuadra' as cuadra, j->'sondas'->>'paridad_nucleo' as paridad, j->'sondas'->>'paridad_filas' as filas,
  j->'cohorte'->>'leads' as cohorte_leads, j->'cohorte'->>'contratos' as cohorte_cierres, j->'cohorte'->>'conversion_contratos_pct' as cohorte_pct,
  (select round(sum((x->>'nucleo_numerador')::numeric),4) from jsonb_array_elements(j->'responsables') x) as sum_num_resp,
  (select sum((x->>'nucleo_divisor')::numeric) from jsonb_array_elements(j->'responsables') x) as sum_div_resp,
  (select count(*) from jsonb_array_elements(j->'responsables')) as n_resp
from r;

-- 4) K cumplimiento (Metas)
with k as (select crm.cumplimiento_metas_fn('2026-09-01'::date) j)
select 'K_cumplimiento_metas_fn_sep' as sonda,
  (select string_agg(k, ',' order by k) from jsonb_object_keys(j) k) as claves,
  j->'total' as total, j->'conversion' as conversion, j->'gerencia' as gerencia,
  j->'cierre'->>'cerrado' as cerrado, j->>'revision' as revision,
  (select count(*) from jsonb_array_elements(coalesce(j->'vendedores','[]'))) as n_vend,
  (select string_agg(distinct k, ',') from jsonb_array_elements(coalesce(j->'vendedores','[]')) v, jsonb_object_keys(v) k) as claves_vend,
  (select jsonb_agg(v->'conversion') from jsonb_array_elements(coalesce(j->'vendedores','[]')) v) as conv_vend,
  (select count(*) from jsonb_array_elements(coalesce(j->'fuera_ranking','[]'))) as n_fuera
from k;

-- 5) V vendedores (Gestión de equipo, Directorio)
with v as (select crm.metricas_vendedores_fn() j)
select 'V_metricas_vendedores_fn' as sonda, j->>'mes_metrica' as mes, j->'nucleo_total' as nucleo_total, j->'cobertura_conversion' as cobertura,
  (select count(*) from jsonb_array_elements(j->'vendedores')) as n_vend,
  (select round(sum((x->>'nucleo_convertidos')::numeric),2) from jsonb_array_elements(j->'vendedores') x) as sum_convertidos,
  (select round(sum((x->>'nucleo_numerador')::numeric),4) from jsonb_array_elements(j->'vendedores') x) as sum_num,
  (select sum((x->>'nucleo_divisor')::numeric) from jsonb_array_elements(j->'vendedores') x) as sum_div,
  (select string_agg(distinct k, ',') from jsonb_array_elements(j->'vendedores') x, jsonb_object_keys(x) k) as claves_vend
from v;

-- 6) D distribución v3 (Rendimiento inferior / Distribución)
with d as (select crm.metricas_distribucion_leads_v3_fn('2026-09-01'::date, '2026-09-21'::date) j)
select 'D_distribucion_v3_sep_1_21' as sonda,
  j->'resumen'->'conversion'->>'nucleo_divisor' as divisor,
  j->'resumen'->'conversion'->>'nucleo_numerador' as numerador,
  j->'resumen'->'conversion'->>'nucleo_conversion_pct' as pct,
  j->'resumen'->'conversion'->'pen' as punteria_pen,
  j->'sondas' as sondas,
  (select count(*) from jsonb_array_elements(j->'analistas')) as n_analistas,
  (select string_agg(k, ',' order by k) from jsonb_object_keys(j->'resumen'->'conversion') k) as claves_conv
from d;

-- 7) Q cosecha del equipo (Ranking · pestaña Cosecha)
with q as (select crm.metricas_conversiones_equipo_fn('2026-09-01'::date, '2026-09-21'::date) j)
select 'Q_conversiones_equipo_fn_sep_1_21' as sonda,
  (select string_agg(k, ',' order by k) from jsonb_object_keys(j) k) as claves,
  j->'sondas' as sondas, j->'total' as total, j->'cohorte' as cohorte,
  (select count(*) from jsonb_array_elements(coalesce(j->'responsables','[]'))) as n_resp,
  (select sum((x->>'leads')::numeric) from jsonb_array_elements(coalesce(j->'responsables','[]')) x) as sum_leads,
  (select sum((x->>'clientes')::numeric) from jsonb_array_elements(coalesce(j->'responsables','[]')) x) as sum_clientes
from q;

-- 8) integridad del ledger que alimenta el núcleo (agregados)
select 'ledger' as sonda,
  (select count(*) from crm.leads where etapa='convertido') as leads_etapa_convertido,
  (select count(distinct lead_id) from crm.lead_asignaciones where resultado='convertido') as leads_con_cierre_ledger,
  (select count(*) from crm.leads l where l.etapa='convertido'
     and not exists (select 1 from crm.lead_asignaciones la where la.lead_id=l.id and la.resultado='convertido')) as convertidos_sin_ledger,
  (select count(*) from crm.leads l where l.etapa<>'convertido'
     and exists (select 1 from crm.lead_asignaciones la where la.lead_id=l.id and la.resultado='convertido')) as ledger_sin_etapa_convertido,
  (select count(*) from crm.lead_asignaciones where resultado='convertido' and resultado_en is null) as cierres_sin_resultado_en,
  (select count(*) from crm.lead_asignaciones la where la.resultado='convertido' and private.cierre_externo_anulado(la.lead_id)) as cierres_anulados,
  (select count(*) from crm.leads where etapa='convertido' and convertido_en is null) as convertidos_sin_fecha,
  (select count(*) from crm.leads l join crm.lead_asignaciones la on la.lead_id=l.id and la.resultado='convertido'
     where l.convertido_en is not null
       and date_trunc('month', l.convertido_en at time zone 'America/Lima') <> date_trunc('month', coalesce(la.resultado_en, la.finalizado_en) at time zone 'America/Lima')) as mes_convertido_en_distinto_del_ledger,
  (select count(*) from crm.leads where origen not in ('landing','formulario','referido') and etapa='convertido') as convertidos_oficina_otro,
  (select count(*) from crm.leads where alta_manual and origen in ('landing','formulario')) as manuales_lf_total,
  (select count(*) from crm.operaciones_cartera where elegible_conversion) as ops_elegibles,
  (select count(*) from (select cliente_id, periodo from crm.operaciones_cartera where elegible_conversion group by 1,2 having count(*)>1) x) as clientes_mes_con_varias_ops;

-- 9) agosto completo: mensual vs rango (foto vs vivo)
with m as (select crm.conversion_mensual_fn('2026-08-01'::date) j),
     r as (select crm.metricas_conversiones_fn('2026-08-01'::date, '2026-08-31'::date, null) j)
select 'agosto_M_vs_R' as sonda,
  (select j->'total'->>'divisor' from m) as m_div, (select j->'total'->>'numerador' from m) as m_num, (select j->'total'->>'conversion_pct' from m) as m_pct,
  (select j->'cierre'->>'cerrado' from m) as m_cerrado, (select j->>'modelo_conversion' from m) as m_modelo, (select j->'fuentes' from m) as m_fuentes,
  (select j->'nucleo'->>'divisor' from r) as r_div, (select j->'nucleo'->>'numerador' from r) as r_num, (select j->'nucleo'->>'conversion_pct' from r) as r_pct,
  (select j->'sondas'->>'cuadra' from r) as r_cuadra, (select j->'sondas'->>'paridad_nucleo' from r) as r_paridad;

-- 10) puertas de conversión: bandera global y piloto (hipótesis F12 de la auditoría del 21/09)
select 'puertas_conversion' as sonda,
  (select coalesce(activo,false) from crm.multiempresa_flags where nombre='inversiones_escritura') as inversiones_escritura_activo,
  (select count(*) from crm.piloto_f8_miembros) as miembros_piloto_f8,
  (select count(*) from crm.inversion_solicitudes where estado='preparada' and lead_origen_id is not null) as solicitudes_preparadas_con_lead,
  (select count(*) from crm.inversion_solicitudes where estado='confirmada' and lead_origen_id is not null and creado_en >= '2026-09-19') as confirmadas_con_lead_desde_1909,
  (select count(*) from crm.lead_asignaciones where resultado='convertido' and coalesce(resultado_en,finalizado_en) >= '2026-09-19') as cierres_ledger_desde_1909;

rollback;
