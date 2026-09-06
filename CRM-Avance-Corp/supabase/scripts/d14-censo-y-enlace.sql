-- ============================================================================
-- F2.b [D-14] — re-enlace de higiene ANTES de encender la identidad unificada
-- ============================================================================
-- POR QUÉ: un lead VIVO con documento pero sin enlace ni puente (nació con la bandera apagada, o su
-- DNI llegó por un UPDATE) es invisible para la identidad hasta que alguien lo reabre, lo toma o lo
-- convierte. No es un riesgo de seguridad —las puertas lo cuentan igual por documento desde D-13—,
-- es higiene: la operación lo verá como de su persona desde el primer día.
--
-- CÓMO USARLO: correr la PARTE 1 (solo lectura) el mismo día del encendido. Si devuelve 0 candidatos,
-- no hay nada que hacer y D-14 queda cerrado. Si aparecen casos, revisar los CONFLICTIVOS a mano
-- (una persona con más de un lead vivo NO se enlaza automáticamente: eso lo decide Gerencia) y
-- ejecutar la PARTE 2, que enlaza solo los inequívocos.
--
-- CENSO DEL 06/09/2026 EN PRODUCCIÓN: 11 leads vivos con documento sin enlace ni puente, y NINGUNO
-- de sus documentos corresponde a una persona reconocida ni a un cliente del Portal → 0 candidatos,
-- 0 conflictivos. Nada que enlazar. Repetir el censo antes del `!` de la bandera.
-- ============================================================================

-- ── PARTE 1 · CENSO (solo lectura; no escribe nada) ─────────────────────────────────────────────
with sueltos as (
  select l.id as lead_id, l.dni, l.etapa,
         private.inversionista_por_documento('DNI', l.dni) as persona
  from crm.leads l
  where l.activo and l.dni is not null and btrim(l.dni) <> ''
    and l.inversionista_id is null
    and not exists (select 1 from crm.inversionista_leads il where il.lead_id = l.id)
),
con_persona as (select * from sueltos where persona is not null and etapa not in ('convertido','descartado')),
conflictivos as (
  select c.lead_id, c.persona from con_persona c
  where exists (select 1 from private.leads_de_personas(array[c.persona]) y where y <> c.lead_id)
     or c.persona in (select persona from con_persona group by persona having count(*) > 1)
)
select 'leads vivos con documento y sin enlace' as concepto, count(*)::text as cuantos from sueltos
union all select 'CANDIDATOS a enlazar (persona reconocida, etapa viva, sin conflicto)', count(*)::text
  from con_persona where lead_id not in (select lead_id from conflictivos)
union all select 'CONFLICTIVOS (los revisa Gerencia; NO se enlazan aquí)', count(*)::text from conflictivos;

-- ── PARTE 2 · ENLACE de los inequívocos ────────────────────────────────────────────────────────
-- Descomentar y ejecutar SOLO si la parte 1 devolvió candidatos. Se niega con la bandera encendida
-- (el enlace masivo va ANTES del `!`, con el sistema todavía en su comportamiento de siempre) y usa
-- la válvula `crm.op_privilegiada` porque escribe `leads.inversionista_id`, columna protegida por
-- `trg_leads_protege_inversionista_id`. Deja rastro en public.audit_log por el auditor de la tabla.
--
-- begin;
-- set local lock_timeout = '10s';
-- do $$
-- declare v_n integer;
-- begin
--   if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
--     raise exception 'D-14: la bandera ya está ENCENDIDA; este re-enlace va antes del encendido';
--   end if;
--   perform set_config('crm.op_privilegiada', 'on', true);
--   with sueltos as (
--     select l.id as lead_id, private.inversionista_por_documento('DNI', l.dni) as persona
--     from crm.leads l
--     where l.activo and l.dni is not null and btrim(l.dni) <> '' and l.inversionista_id is null
--       and l.etapa not in ('convertido','descartado')
--       and not exists (select 1 from crm.inversionista_leads il where il.lead_id = l.id)
--   ),
--   con_persona as (select * from sueltos where persona is not null),
--   limpios as (
--     select c.* from con_persona c
--     where not exists (select 1 from private.leads_de_personas(array[c.persona]) y where y <> c.lead_id)
--       and c.persona not in (select persona from con_persona group by persona having count(*) > 1)
--   )
--   update crm.leads l set inversionista_id = x.persona from limpios x where l.id = x.lead_id;
--   get diagnostics v_n = row_count;
--   perform set_config('crm.op_privilegiada', 'off', true);
--   raise notice 'D-14: % leads enlazados a su persona', v_n;
-- end $$;
-- commit;
