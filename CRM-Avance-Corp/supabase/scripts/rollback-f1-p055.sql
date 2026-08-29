-- MARCHA ATRAS de la Fase 1 del PLAN MAESTRO P-055 (migraciones 20260828190000,
-- 190500, 191000 y 191500). Escrito ANTES de aplicar nada, con las definiciones
-- VIVAS leidas de produccion el 2026-08-28.
--
-- POR QUE ESTE ARCHIVO EXISTE: aunque la Fase 1 es ENTERAMENTE ADITIVA -no borra
-- ni recrea ningun trigger, ni reemplaza ninguna funcion-, un cambio sobre
-- produccion sin marcha atras escrita no se publica. Aqui esta, con las
-- comprobaciones que dicen si el servidor quedo como estaba.
-- El cuerpo de `crear_contrato` de aqui abajo esta anclado por md5:
-- f50b62e1a9839d2fb68363b8a53e7603.
--
-- COMO SE USA: se aplica ENTERO y en este orden. Es idempotente en lo que
-- borra (`drop trigger if exists`) y termina comprobando que el mundo quedo
-- como estaba antes de la Fase 1.
--
-- OJO: no deshace filas de `public.audit_log` ya escritas por los triggers
-- nuevos; esas quedan, y esta bien que queden (un rastro no se borra).

-- == 1. Quitar lo que la Fase 1 anadio ======================================
drop trigger if exists trg_audit_contrato_titulares on public.contrato_titulares;
drop trigger if exists trg_audit_actividades_cliente on crm.actividades_cliente;
drop trigger if exists trg_audit_cronograma_pago_alta_baja on public.cronograma_pagos;
drop trigger if exists trg_audit_actividades_cambio_baja on crm.actividades;

-- == 2. Lo que NO hay que restaurar, y por que =============================
-- `trg_audit_actividades` (el auditor del alta de la gestion del lead) y
-- `trg_audit_cronograma_pago` (el del pago, con su clausula WHEN) NO se tocan en
-- la Fase 1: siguen exactamente como estaban, asi que aqui no hay nada que
-- devolver. Su forma viva, por si alguna vez hiciera falta, esta en el anexo.

-- == 3. La malla anti-NaN ====================================================
alter table public.cronograma_pagos drop constraint if exists cronograma_pagos_monto_programado_valido;
alter table public.cronograma_pagos drop constraint if exists cronograma_pagos_monto_pagado_valido;
alter table crm.cierre_mes_vendedor drop constraint if exists cierre_mes_vendedor_numerador_finito;
alter table crm.cierre_mes_vendedor drop constraint if exists cierre_mes_vendedor_conversion_pct_finito;
alter table crm.cierre_mes_vendedor drop constraint if exists cierre_mes_vendedor_referidos_aporta_pct_finito;
alter table crm.cierre_mes_vendedor drop constraint if exists cierre_mes_vendedor_ajuste_numerador_finito;
alter table crm.cierre_mes_vendedor drop constraint if exists cierre_mes_vendedor_ajuste_pen_finito;
alter table crm.cierre_mes_vendedor drop constraint if exists cierre_mes_vendedor_ajuste_usd_finito;
alter table crm.cierre_mes_vendedor drop constraint if exists cierre_mes_vendedor_conversion_objetivo_finito;
alter table crm.ajustes_mes_cerrado drop constraint if exists ajustes_mes_cerrado_capital_pen_finito;
alter table crm.ajustes_mes_cerrado drop constraint if exists ajustes_mes_cerrado_capital_usd_finito;
alter table crm.ajustes_mes_cerrado drop constraint if exists ajustes_mes_cerrado_numerador_finito;
alter table crm.ajustes_mes_cerrado drop constraint if exists ajustes_mes_cerrado_pendiente_numerador_finito;
alter table crm.ajustes_mes_cerrado drop constraint if exists ajustes_mes_cerrado_pendiente_pen_finito;
alter table crm.ajustes_mes_cerrado drop constraint if exists ajustes_mes_cerrado_pendiente_usd_finito;
alter table crm.periodos_cerrados drop constraint if exists periodos_cerrados_ponderacion_referido_finito;

-- == 4. Los permisos, exactamente como estaban ==============================
-- Estado original medido el 28/08: ACL de fabrica `arwdDxtm` para anon y
-- authenticated en las 10 tablas, y EXECUTE de PUBLIC en las 5 RPC.
grant truncate, references, trigger, maintain on table
  public.asesores,
  public.audit_log,
  public.contrato_titulares,
  public.contratos,
  public.cronograma_pagos,
  public.documentos,
  public.novedades,
  public.novedades_leidas,
  public.perfiles,
  public.suscripciones_push
to anon, authenticated;

alter default privileges for role postgres in schema public
  grant truncate, references, trigger, maintain on tables to anon, authenticated;

grant execute on function
  public.admin_pagos_metricas(),
  public.admin_pagos_resumen(),
  public.dashboard_admin_metricas(),
  public.pagos_admin_metricas_globales(),
  public.pagos_admin_resumen_contratos(text,text,text,integer,integer)
to public;

-- == 5. `public.crear_contrato` NO se toca en la Fase 1 =====================
-- La cuarta migracion -el cerrojo de la numeracion automatica- salio de la fase
-- por decision de Miguel el 28/08: esa numeracion no se necesita todavia. Vive
-- aparcada en `supabase/snippets/NO-APLICAR-numeracion-automatica-contratos.sql`
-- y NO se aplica, asi que aqui no hay nada que revertir.

-- == 6. Comprobacion: el mundo quedo como antes de la Fase 1 ================
do $verificar$
declare
  v_md5 text;
  v_malo text[] := '{}';
begin
  -- `crear_contrato` no la toca la Fase 1; si su md5 cambio, fue otra cosa.
  select md5(p.prosrc) into v_md5 from pg_catalog.pg_proc p
  where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure;
  if v_md5 is distinct from 'f50b62e1a9839d2fb68363b8a53e7603' then
    raise notice 'AVISO: crear_contrato esta en md5 % (la Fase 1 no la toca)', v_md5;
  end if;
  if exists (select 1 from pg_catalog.pg_trigger t
             where t.tgrelid = 'public.contrato_titulares'::regclass
               and t.tgname = 'trg_audit_contrato_titulares') then
    v_malo := v_malo || 'sigue el auditor de co-titulares';
  end if;
  if not exists (select 1 from pg_catalog.pg_trigger t
                 where t.tgrelid = 'crm.actividades'::regclass
                   and t.tgname = 'trg_audit_actividades' and t.tgtype = 5) then
    v_malo := v_malo || 'trg_audit_actividades ya no es AFTER INSERT (no deberia haberse tocado)';
  end if;
  if exists (select 1 from pg_catalog.pg_trigger t
             where t.tgrelid = 'crm.actividades'::regclass
               and t.tgname = 'trg_audit_actividades_cambio_baja') then
    v_malo := v_malo || 'sigue el auditor de cambio/baja de la gestion del lead';
  end if;
  if not exists (select 1 from pg_catalog.pg_trigger t
                 where t.tgrelid = 'public.cronograma_pagos'::regclass
                   and t.tgname = 'trg_audit_cronograma_pago' and t.tgqual is not null) then
    v_malo := v_malo || 'el auditor de UPDATE de cuotas perdio su WHEN';
  end if;
  if not has_table_privilege('anon', 'public.contratos', 'TRUNCATE') then
    v_malo := v_malo || 'los permisos de fabrica no volvieron';
  end if;
  if exists (select 1 from pg_catalog.pg_constraint c where c.conname like '%_finito'
             and c.conrelid in ('crm.cierre_mes_vendedor'::regclass,
                                'crm.ajustes_mes_cerrado'::regclass,
                                'crm.periodos_cerrados'::regclass)) then
    v_malo := v_malo || 'quedan guardianes anti-NaN de la Fase 1';
  end if;
  if array_length(v_malo, 1) is not null then
    raise exception 'LA MARCHA ATRAS NO QUEDO LIMPIA: %', array_to_string(v_malo, ' | ');
  end if;
  raise notice 'MARCHA ATRAS OK: el servidor quedo como antes de la Fase 1';
end
$verificar$;

-- == Anexo: las definiciones VIVAS que la Fase 1 NO toca ====================
-- Ninguna se recrea arriba. Se copian aqui porque son la unica copia fuera de la
-- base, y una de ellas -el WHEN del auditor de cuotas- se puso a mano el
-- 2026-06-13 y no existe en ninguna migracion del repositorio:
--
-- CREATE TRIGGER trg_audit_actividades AFTER INSERT ON crm.actividades
--   FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm();
--
--
-- CREATE TRIGGER trg_audit_cronograma_pago AFTER UPDATE ON public.cronograma_pagos
--   FOR EACH ROW
--   WHEN (((old.estado IS DISTINCT FROM new.estado)
--       OR (old.monto_pagado IS DISTINCT FROM new.monto_pagado)
--       OR (old.fecha_pago_real IS DISTINCT FROM new.fecha_pago_real)
--       OR (old.registrado_por IS DISTINCT FROM new.registrado_por)))
--   EXECUTE FUNCTION log_audit_change();
