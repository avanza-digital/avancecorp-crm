-- 20261015000852_crm_plazo_carga_mes.sql
--
-- Plazo de carga por mes, decidido por Gerencia (y reapertura del último mes sellado).
-- Pedido de Miguel (14/10/2026): «necesitamos abrir septiembre porque los analistas se demoraron en cargar sus ventas; una
-- configuración para que gerencia lo decida». Decisiones suyas: SOLO Gerencia decide · SIN tope de fecha · alcance: ampliar el
-- plazo Y reabrir un mes ya sellado desde la pantalla. Especificación: docs/plans/plazo-carga-mes/DISENO.md.
-- La reapertura reproduce, en el mismo orden y con las mismas comprobaciones, el script probado en producción el 14/10
-- (supabase/scripts/reexpresion-septiembre-2026/01-reabrir.sql), sin ALTER TABLE ni GUC: los candados se abren con una
-- autorización atada al MES y a la TRANSACCIÓN de la reapertura (private.reapertura_autoriza).
--
-- REGLA
--   Plazo de carga de un mes M = instante (extremo EXCLUIDO, America/Lima) hasta el que (a) una conversión de M se acredita
--   (private.conversion_decidir_plazo), (b) el ciclo automático no sella M y (c) tampoco crm.cerrar_periodo a mano (las dos usan
--   private.cierre_mes_ventana_desde). Base (la de hoy): 00:00 de Lima del día 11 de M+1 («último día incluido: el 10»).
--   Gerencia fija el último día incluido D: plazo = (D + 1) 00:00 de Lima. D ≥ hoy en Lima, plazo ≥ base, motivo de 5 a 300
--   caracteres, M ≤ mes en curso y con metas publicadas (sin metas no hay cierre: revisión Codex r2). Vale la última decisión
--   (ampliar o acortar mientras M esté abierto).
--   Reabrir = la misma acción sobre un mes sellado con metas, solo si es el ÚLTIMO sellado y el mes ANTERIOR al mes en curso, sin deudas
--   nacidas de M, sin deudas absorbidas por su foto, con foto, y con cada registro tardío de M siendo una venta en cooperativa
--   coherente cuyo analista efectivo tiene meta en M (y ninguna venta en cooperativa de M imputada fuera sin rastro).
--   Al fijar el plazo, las acreditaciones de M «fuera_de_plazo» o «mes_sellado» con acreditado_en < plazo se reevalúan con la
--   misma decisión y la misma exclusión de fuente que el escritor; si la identidad ya tiene otra captación acreditada (regla
--   del escritor, P0409) se dejan como están y se cuentan como conflicto.
--
-- QUÉ HACE (orden: núcleo base → tablas/restricciones/RLS/auditoría → CHECK → núcleo → puertas → permisos → comentarios)
--   0. private.conversion_plazo_base(date): la fórmula de hoy (IMMUTABLE). Va primero porque la tabla nueva la usa en su CHECK.
--   1. crm.reaperturas_mes (respaldo de cada reapertura, SIN datos personales de clientes: los cierres en cooperativa se
--      copian sin documento ni nombre) y crm.plazos_carga_mes (decisiones de Gerencia): RLS sin políticas, sin grants,
--      append-only (UPDATE/DELETE/TRUNCATE rebotan), auditoría private.log_audit_crm de los tres verbos (así también el
--      rastro tardío que se retira queda en public.audit_log, dentro del respaldo). La llave de la reapertura (transacción
--      e instante) la fija un trigger BEFORE INSERT: nadie la elige. Sin negocio_id: el cierre de mes del CRM no tiene
--      inquilino (igual que crm.periodos_cerrados).
--   2. CHECK de crm.conversion_acreditaciones «plazo_hasta = conversion_plazo_hasta(periodo)» (nombre por catálogo) →
--      conversion_acreditaciones_plazo_minimo_check «plazo_hasta >= conversion_plazo_base(periodo)». Con el plazo variable,
--      el CHECK viejo rompería el UPDATE del trigger del sello sobre las filas ya decididas.
--   3. private.conversion_plazo_hasta(date) pasa a STABLE: última decisión de Gerencia o la base. conversion_decidir_plazo y
--      cierre_mes_ventana_desde: IMMUTABLE → STABLE con el cuerpo intacto (ninguna función IMMUTABLE, índice, default ni
--      CHECK depende de ellas: comprobado en el preflight).
--   4. private.reapertura_autoriza(date[, uuid]): ¿hay una reapertura de ESE mes registrada en ESTA transacción (su id y su
--      instante)? Para un cierre en cooperativa, además, ¿lo respaldó esa reapertura? Los tres candados (sello/foto, rastro
--      tardío e imputación de cooperativa, cierre externo) son los cuerpos vivos + una rama que la consulta; la del cierre
--      externo solo deja cambiar la imputación, solo a la fecha comercial y nada más de la fila (revisión auditor-rls, P2).
--   5. private.reapertura_impedimento(date) (UNA regla: la usan la reapertura y la lectura de la pantalla),
--      private.conversion_reevaluar_plazo(date), private.reabrir_mes(date,text,uuid), y el núcleo de las dos puertas:
--      private.fijar_plazo_carga(date,date,text,uuid) y private.plazos_carga_mes_lectura() (capas: la puerta valida,
--      autoriza y delega; no lee ni escribe tablas).
--   6. Puertas (SECURITY DEFINER, search_path vacío, gate explícito: auth.uid() con rol CRM gerencia, si no 42501):
--      crm.fijar_plazo_carga_mes(date,date,text) y crm.plazos_carga_mes_fn(). DEFINER: las tablas no tienen grants y el
--      actor sale de auth.uid(), nunca de un parámetro. Un mes sin sellar por DETRÁS del último sellado no admite plazo
--      (22023): ningún ciclo lo sellará y reevaluarlo solo movería la regla de identidad.
--
--   7. crm.cerrar_periodo: cuerpo vivo + la ventana mirada OTRA VEZ después de tomar los candados (revisión Codex P1).
--      Está declarada en el censo analítico (private.analitica_leads_citas_exenciones): se re-sella su huella en la misma
--      transacción (plantilla de 20261013145852). El primer ensayo en producción (15/10) se negó justo por esto: el banco de
--      solo esquema no tenía la declaración.
--
-- QUÉ NO TOCA: public (salvo el DML que ya hacen los triggers), el cron (la reapertura NO pausa el job 3: con el plazo nuevo
--   en el futuro el ciclo no la vuelve a sellar antes), la forma de crm.cierre_mes_estado_fn (su `cierra_el` refleja el plazo
--   nuevo solo), crm.ciclo_cierre_mes, el escritor de acreditaciones y Facturación.
-- CENSO ANALÍTICO: ninguna función nueva combina crm.leads/«reunion» con count(/sum(1) (la reevaluación cuenta con contadores).
-- TRINQUETES: el postflight compara la foto de F7, analítica, vigencia del analista y auditoría ANTES y DESPUÉS: debe ser igual.
-- CONCURRENCIA: el núcleo de la puerta toma el candado global y el mensual de crm.periodos_cerrados (mismas llamadas que
--   crm.cerrar_periodo) antes de mirar el sello; los escritores de dinero toman el mensual antes de mirar si el mes está
--   sellado; la reevaluación toma después el de la identidad, como el escritor. crm.cerrar_periodo miraba su ventana solo
--   ANTES de tomar los candados: si Gerencia ampliaba el plazo mientras un sello de ese mes esperaba el candado, el sello
--   terminaba igual (con «sin tope», incluso un mes que ya no es el anterior y no se puede reabrir). Ahora la vuelve a mirar
--   con los candados tomados y se niega (revisión Codex P1).
-- AUTORIZACIÓN: vale para TODA la transacción superior que registró la reapertura, incluidas sus subtransacciones (los ids
--   de transacción de Postgres y now() son los de la transacción superior); si se deshace la subtransacción que insertó la
--   fila, la fila desaparece y deja de autorizar. Esa transacción es una sola llamada a la puerta.
-- REVERSA: supabase/scripts/plazo-carga-mes/reversa.sql (se niega si ya hay decisiones o reaperturas).
-- PRUEBAS: supabase/scripts/plazo-carga-mes/ (prueba.sql, mutantes.py, dos-sesiones.py, transporte.py,
--   integracion-permisos.mjs; pasos y resultados en LEEME.md).
-- Aplicar en UN mensaje: `supabase db query --linked --file` (nunca sentencia a sentencia), y registrar después.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local search_path = '';

-- Exclusión de migraciones de la casa (la misma llave que el candado de sesión crm_migracion_funciones) y el candado global
-- del cierre: ningún sello ni publicación de metas en vuelo mientras cambian el plazo y los candados del cierre.
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm_migracion_funciones'));
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
lock table crm.periodos_cerrados in share mode;
-- El censo analítico: crm.cerrar_periodo está declarada en private.analitica_leads_citas_exenciones con la huella de su
-- cuerpo (en producción; un banco de solo esquema no tiene la fila). Esta migración cambia su cuerpo y la re-sella en la misma
-- transacción con la plantilla de 20261013145852 (mismos candados, en el mismo orden).
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('private.analitica_leads_citas_exenciones'),
                                        pg_catalog.hashtext('migracion'));
lock table private.analitica_leads_citas_exenciones in share row exclusive mode;
lock table private.analitica_lc_sello in share row exclusive mode;
lock table private.analitica_leads_citas_tope in share row exclusive mode;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
begin
  -- Lo que se reemplaza o se re-declara, exactamente como está en producción (14/10/2026; md5 de pg_get_functiondef con
  -- search_path vacío).
  if md5(pg_catalog.pg_get_functiondef('private.conversion_plazo_hasta(date)'::regprocedure)) <> '81fb7f2e28e8445e9e7877a18fb41e7c'
     or md5(pg_catalog.pg_get_functiondef('crm.cerrar_periodo(date)'::regprocedure)) <> '70e1ba0467ead3492005d3ac896011ec'
     or md5(pg_catalog.pg_get_functiondef('private.conversion_decidir_plazo(date,timestamptz,timestamptz,timestamptz)'::regprocedure)) <> '07c1c7f09a674b45e115eeef77e69b85'
     or md5(pg_catalog.pg_get_functiondef('private.cierre_mes_ventana_desde(date)'::regprocedure)) <> 'fe15a998e777c4b92d643879b4a73e5f'
     or md5(pg_catalog.pg_get_functiondef('private.trg_cierre_mes_append_only()'::regprocedure)) <> '51d9243063f21df1acba01d8b8002cec'
     or md5(pg_catalog.pg_get_functiondef('private.f4_fuente_inmutable()'::regprocedure)) <> '808b1ac3481ee180f5060bd4e0bc6fa1'
     or md5(pg_catalog.pg_get_functiondef('private.trg_cierres_externos_inmutables()'::regprocedure)) <> '34fd3c383e636353038acca2b42e0535' then
    raise exception 'PREFLIGHT plazo_carga_mes: cambió una de las funciones que se reemplazan; revisar antes de aplicar';
  end if;
  -- Lo que se llama o cuya regla se reproduce sin tocarlo: si cambia, cambian las garantías de esta migración.
  if md5(pg_catalog.pg_get_functiondef('private.rol_crm(uuid)'::regprocedure)) <> '99827f3fe2fbc3cfae5668c30015c758'
     or md5(pg_catalog.pg_get_functiondef('private.analista_efectivo_cierre(uuid)'::regprocedure)) <> '2cf2201f8a01c381a7756293fbdadd46'
     or md5(pg_catalog.pg_get_functiondef('private.conversion_exclusion_fuente(text,uuid)'::regprocedure)) <> 'a4572363b00484774768c9d3d314a6fd'
     or md5(pg_catalog.pg_get_functiondef('private.inversionista_canonica(uuid)'::regprocedure)) <> '34702897135078893b7d3a726b0c1816'
     or md5(pg_catalog.pg_get_functiondef('private.motivo_normalizado(text)'::regprocedure)) <> '08602d4022e0731952cbf61c28efe9d7'
     or md5(pg_catalog.pg_get_functiondef('private.etiqueta_mes_es(date)'::regprocedure)) <> 'c2e79bf87edfd03b540601fe5339aade'
     or md5(pg_catalog.pg_get_functiondef('private.conversion_instante_servidor()'::regprocedure)) <> 'a9b5158d5587d0a77e1de58c8da4b02e'
     or md5(pg_catalog.pg_get_functiondef('private.conversion_acreditar_fuente(uuid,text,uuid,text)'::regprocedure)) <> '581462c4ecbdab349c18655f4850e010'
     or md5(pg_catalog.pg_get_functiondef('private.conversion_fijar_sello_trg()'::regprocedure)) <> '5f9193842119a36b71602398a871334a'
     or md5(pg_catalog.pg_get_functiondef('private.cierre_mes_pendiente(date)'::regprocedure)) <> '1af05605f2ed0cf3d7c978ebe53a1b4b'
     or md5(pg_catalog.pg_get_functiondef('crm.ciclo_cierre_mes()'::regprocedure)) <> '459b9d42bf991712d044f63e494a2a52'
     or md5(pg_catalog.pg_get_functiondef('crm.cierre_mes_estado_fn()'::regprocedure)) <> '6114ee84a35b12499802092b0ff7a963'
     or md5(pg_catalog.pg_get_functiondef('private.log_audit_crm()'::regprocedure)) <> 'c25c2af183b650f4d4c85abedd5bcc97'
     or md5(pg_catalog.pg_get_functiondef('private.log_audit_sin_secretos()'::regprocedure)) <> 'ae7225bc9e86131813ac0328fff4c3ae' then
    raise exception 'PREFLIGHT plazo_carga_mes: cambió una función que esta migración llama o reproduce; revisar antes de aplicar';
  end if;
  if to_regclass('crm.plazos_carga_mes') is not null or to_regclass('crm.reaperturas_mes') is not null
     or to_regprocedure('private.conversion_plazo_base(date)') is not null
     or to_regprocedure('private.reapertura_autoriza(date)') is not null
     or to_regprocedure('private.reapertura_autoriza(date,uuid)') is not null
     or to_regprocedure('private.trg_reaperturas_mes_llave()') is not null
     or to_regprocedure('private.fijar_plazo_carga(date,date,text,uuid)') is not null
     or to_regprocedure('private.plazos_carga_mes_lectura()') is not null
     or to_regprocedure('private.reapertura_impedimento(date)') is not null
     or to_regprocedure('private.conversion_reevaluar_plazo(date)') is not null
     or to_regprocedure('private.reabrir_mes(date,text,uuid)') is not null
     or to_regprocedure('private.trg_plazo_carga_append_only()') is not null
     or to_regprocedure('crm.fijar_plazo_carga_mes(date,date,text)') is not null
     or to_regprocedure('crm.plazos_carga_mes_fn()') is not null then
    raise exception 'PREFLIGHT plazo_carga_mes: los objetos nuevos ya existen';
  end if;
  -- El CHECK que se reemplaza: exactamente uno con esa definición, y ninguno con el nombre nuevo.
  if (select count(*) from pg_catalog.pg_constraint c
       where c.conrelid = 'crm.conversion_acreditaciones'::regclass and c.contype = 'c'
         and pg_catalog.pg_get_constraintdef(c.oid) = 'CHECK ((plazo_hasta = private.conversion_plazo_hasta(periodo_comercial)))') <> 1
     or exists (select 1 from pg_catalog.pg_constraint c
                 where c.conrelid = 'crm.conversion_acreditaciones'::regclass
                   and c.conname = 'conversion_acreditaciones_plazo_minimo_check') then
    raise exception 'PREFLIGHT plazo_carga_mes: el CHECK de plazo de crm.conversion_acreditaciones no es el esperado';
  end if;
  -- Ninguna otra dependencia de catálogo (índice, default, CHECK, vista) sobre las tres que dejan de ser IMMUTABLE.
  if exists (select 1 from pg_catalog.pg_depend d
              where d.refclassid = 'pg_catalog.pg_proc'::regclass
                and d.refobjid in ('private.conversion_plazo_hasta(date)'::regprocedure,
                                   'private.conversion_decidir_plazo(date,timestamptz,timestamptz,timestamptz)'::regprocedure,
                                   'private.cierre_mes_ventana_desde(date)'::regprocedure)
                and not (d.classid = 'pg_catalog.pg_constraint'::regclass
                         and d.objid = (select c.oid from pg_catalog.pg_constraint c
                                         where c.conrelid = 'crm.conversion_acreditaciones'::regclass and c.contype = 'c'
                                           and pg_catalog.pg_get_constraintdef(c.oid)
                                               = 'CHECK ((plazo_hasta = private.conversion_plazo_hasta(periodo_comercial)))'))) then
    raise exception 'PREFLIGHT plazo_carga_mes: algo más depende del plazo IMMUTABLE; revisar antes de aplicar';
  end if;
  -- Y ninguna función IMMUTABLE las llama (plpgsql/sql no registran dependencias: se censa el texto).
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
              where n.nspname not in ('pg_catalog', 'information_schema') and p.provolatile = 'i'
                and p.oid not in ('private.conversion_plazo_hasta(date)'::regprocedure,
                                  'private.conversion_decidir_plazo(date,timestamptz,timestamptz,timestamptz)'::regprocedure,
                                  'private.cierre_mes_ventana_desde(date)'::regprocedure)
                and coalesce(p.prosrc, '') ~ '(conversion_plazo_hasta|conversion_decidir_plazo|cierre_mes_ventana_desde)') then
    raise exception 'PREFLIGHT plazo_carga_mes: una función IMMUTABLE llama al plazo; revisar antes de aplicar';
  end if;
  -- Los candados del cierre están en su modo normal sobre sus tablas.
  if (select count(*) from pg_catalog.pg_trigger t
      where t.tgenabled = 'O' and not t.tgisinternal and (
        (t.tgrelid = 'crm.periodos_cerrados'::regclass and t.tgname = 'trg_periodos_cerrados_00_append_only'
           and t.tgfoid = 'private.trg_cierre_mes_append_only()'::regprocedure)
        or (t.tgrelid = 'crm.cierre_mes_vendedor'::regclass and t.tgname = 'trg_cierre_mes_vendedor_00_append_only'
           and t.tgfoid = 'private.trg_cierre_mes_append_only()'::regprocedure)
        or (t.tgrelid = 'crm.inversion_ajustes_mes_cerrado'::regclass and t.tgname = 'trg_inversion_ajustes_inmutables'
           and t.tgfoid = 'private.f4_fuente_inmutable()'::regprocedure)
        or (t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_cierres_f4_inmutables'
           and t.tgfoid = 'private.f4_fuente_inmutable()'::regprocedure)
        or (t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_cierres_externos_00_inmutables'
           and t.tgfoid = 'private.trg_cierres_externos_inmutables()'::regprocedure))) <> 5 then
    raise exception 'PREFLIGHT plazo_carga_mes: los candados del cierre no están en su modo normal';
  end if;
end
$preflight$;

-- Preflight del censo analítico (re-sellado de crm.cerrar_periodo) y foto de sus registros para el postflight.
create temp table _plazo_censo_antes on commit drop as
  select e.objeto, pg_catalog.to_jsonb(e) as fila from private.analitica_leads_citas_exenciones e;
create temp table _plazo_censo_tope_antes on commit drop as
  select pg_catalog.to_jsonb(t) as fila from private.analitica_leads_citas_tope t;
do $preflight_censo$
declare v_huella text;
begin
  -- Las piezas del censo, como las fija 20261013145852.
  if md5(pg_catalog.pg_get_functiondef('private.contadores_crudos_leads_citas()'::regprocedure)) <> '6a5d2a2ed9e6442aff17d598af6d59da'
     or md5(pg_catalog.pg_get_functiondef('private.huella_exenciones_analitica_lc()'::regprocedure)) <> 'ad7d8cfd4e4f4ae6f1c2c3fecf51bb99' then
    raise exception 'PREFLIGHT plazo_carga_mes: cambió el censo analítico (contadores o huella de la lista); revisar antes de re-sellar';
  end if;
  -- La huella NORMALIZADA del cuerpo vivo de crm.cerrar_periodo (la expresión de private.contadores_crudos_leads_citas).
  select md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_catalog.pg_get_functiondef(p.oid))), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))
    into v_huella from pg_catalog.pg_proc p where p.oid = 'crm.cerrar_periodo(date)'::regprocedure;
  if v_huella is distinct from '8073f806d602fd55532f1f9d4651b7d4' then
    raise exception 'PREFLIGHT plazo_carga_mes: la huella normalizada de crm.cerrar_periodo (%) no es la revisada (8073f806…)', v_huella;
  end if;
  -- Si está declarada (en producción lo está): vigente, reconocida por el censo y con el sello de la lista al día.
  if exists (select 1 from private.analitica_leads_citas_exenciones e where e.objeto = 'crm.cerrar_periodo(date)') then
    if (select e.huella from private.analitica_leads_citas_exenciones e where e.objeto = 'crm.cerrar_periodo(date)') is distinct from '8073f806d602fd55532f1f9d4651b7d4'
       or not exists (select 1 from private.contadores_crudos_leads_citas() c where c.objeto = 'crm.cerrar_periodo(date)' and c.declarada and c.huella_ok)
       or (select s.sello from private.analitica_lc_sello s where s.id) is distinct from private.huella_exenciones_analitica_lc() then
      raise exception 'PREFLIGHT plazo_carga_mes: la declaración analítica de crm.cerrar_periodo no está vigente o el sello del censo no está al día; revisar antes de re-sellar';
    end if;
  end if;
end
$preflight_censo$;

-- Foto de los trinquetes ANTES (F7, analítica, vigencia del analista y auditoría): un cambio que pasa sus propias pruebas
-- puede romper un sello ajeno. Se compara con la de DESPUÉS en el postflight; lo que importa es que NO CAMBIE.
create temp table _plazo_trinquetes (momento text not null, pieza text not null, resultado text not null) on commit drop;
do $foto_antes$
declare v_f text; v_r text;
begin
  foreach v_f in array array['private.assert_f7_piezas_cerradas()', 'private.assert_analitica_leads_citas()',
                             'private.assert_analista_vigencia()', 'private.assert_auditoria()'] loop
    begin
      execute 'select (' || v_f || ')::text' into v_r;
      v_r := 'pasa: ' || coalesce(v_r, '');
    exception when others then
      v_r := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    insert into pg_temp._plazo_trinquetes values ('antes', v_f, v_r);
  end loop;
  insert into pg_temp._plazo_trinquetes
    select 'antes', 'censo analitico', c::text from private.contadores_crudos_leads_citas() c;
  insert into pg_temp._plazo_trinquetes
    select 'antes', 'censo vigencia', c::text from private.puertas_analista_sin_vigencia() c;
  insert into pg_temp._plazo_trinquetes
    select 'antes', 'tablas sin rastro', c::text from private.tablas_sin_rastro() c;
end
$foto_antes$;

-- ── 1 · Núcleo base: la fórmula de hoy ─────────────────────────────────────────────────────────────────────────────────
-- Copia exacta del cuerpo vivo de private.conversion_plazo_hasta (20260927073637): la base no depende de ninguna decisión.
create function private.conversion_plazo_base(p_periodo date)
returns timestamp with time zone
language plpgsql
immutable strict
set search_path = ''
as $function$
begin
  if not pg_catalog.isfinite(p_periodo)
     or p_periodo <> pg_catalog.date_trunc('month', p_periodo::timestamp)::date then
    raise exception 'El periodo debe ser el primer dia de un mes finito'
      using errcode = '22023';
  end if;
  return (p_periodo::timestamp + interval '1 month 10 days')
    at time zone 'America/Lima';
end;
$function$;

-- ── 2 · Tablas (RLS en el mismo paso, sin políticas, sin grants, append-only, auditoría por fila) ────────────────────────
create table crm.reaperturas_mes (
  id uuid primary key default gen_random_uuid(),
  periodo date not null,
  motivo text not null,
  decidido_por uuid not null references public.perfiles (id) on delete restrict,
  reabierto_en timestamp with time zone not null default pg_catalog.now(),
  transaccion xid8 not null default pg_catalog.pg_current_xact_id(),
  respaldo jsonb not null,
  resumen jsonb not null,
  constraint reaperturas_mes_periodo_check
    check (pg_catalog.isfinite(periodo) and periodo = pg_catalog.date_trunc('month', periodo::timestamp)::date),
  constraint reaperturas_mes_motivo_check
    check (motivo = private.motivo_normalizado(motivo) and pg_catalog.char_length(motivo) between 5 and 300),
  constraint reaperturas_mes_respaldo_check
    check (pg_catalog.jsonb_typeof(respaldo) = 'object'
           and respaldo ?& array['sello', 'foto', 'acreditaciones', 'rastros_tardios', 'cierres_externos']),
  constraint reaperturas_mes_resumen_check check (pg_catalog.jsonb_typeof(resumen) = 'object'),
  -- La pareja es la llave que comprueba la autorización: a lo sumo una reapertura por transacción superior, y un id de
  -- transacción repetido tras restaurar un volcado en otro cluster no impide una reapertura legítima (revisión Codex P3).
  constraint reaperturas_mes_transaccion_key unique (transaccion, reabierto_en),
  constraint reaperturas_mes_id_periodo_key unique (id, periodo)
);
alter table crm.reaperturas_mes enable row level security;
create index reaperturas_mes_periodo_idx on crm.reaperturas_mes (periodo, reabierto_en desc, id desc);
create index reaperturas_mes_decidido_por_idx on crm.reaperturas_mes (decidido_por);

create table crm.plazos_carga_mes (
  id uuid primary key default gen_random_uuid(),
  periodo date not null,
  ultimo_dia date not null,
  plazo_hasta timestamp with time zone not null,
  motivo text not null,
  decidido_por uuid not null references public.perfiles (id) on delete restrict,
  decidido_en timestamp with time zone not null default pg_catalog.clock_timestamp(),
  reapertura_id uuid,
  constraint plazos_carga_mes_periodo_check
    check (pg_catalog.isfinite(periodo) and periodo = pg_catalog.date_trunc('month', periodo::timestamp)::date),
  constraint plazos_carga_mes_ultimo_dia_check check (pg_catalog.isfinite(ultimo_dia)),
  constraint plazos_carga_mes_plazo_check
    check (plazo_hasta = ((ultimo_dia + 1)::timestamp at time zone 'America/Lima')),
  constraint plazos_carga_mes_plazo_minimo_check check (plazo_hasta >= private.conversion_plazo_base(periodo)),
  constraint plazos_carga_mes_motivo_check
    check (motivo = private.motivo_normalizado(motivo) and pg_catalog.char_length(motivo) between 5 and 300),
  constraint plazos_carga_mes_reapertura_fkey foreign key (reapertura_id, periodo)
    references crm.reaperturas_mes (id, periodo) on delete restrict,
  constraint plazos_carga_mes_reapertura_key unique (reapertura_id)
);
alter table crm.plazos_carga_mes enable row level security;
create index plazos_carga_mes_periodo_idx on crm.plazos_carga_mes (periodo, decidido_en desc, id desc);
create index plazos_carga_mes_decidido_por_idx on crm.plazos_carga_mes (decidido_por);

create function private.trg_plazo_carga_append_only()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception using
    errcode = 'P0409',
    message = 'Las decisiones de plazo de carga y las reaperturas de mes no se editan ni se borran',
    hint    = 'Para cambiar el plazo, Gerencia fija uno nuevo (crm.fijar_plazo_carga_mes): vale la última decisión.';
end;
$function$;

-- La llave de la autorización (private.reapertura_autoriza) no la elige quien inserta: es SIEMPRE la transacción que
-- inserta y su instante de inicio (revisión auditor-rls, P3: una fila con otra llave, o una vieja que coincidiera en el id
-- de transacción tras restaurar un volcado en otro cluster, no autoriza nada).
create function private.trg_reaperturas_mes_llave()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  new.transaccion := pg_catalog.pg_current_xact_id();
  new.reabierto_en := pg_catalog.now();
  return new;
end;
$function$;

create trigger trg_reaperturas_mes_00_llave before insert on crm.reaperturas_mes
  for each row execute function private.trg_reaperturas_mes_llave();
create trigger trg_reaperturas_mes_00_append_only before update or delete on crm.reaperturas_mes
  for each row execute function private.trg_plazo_carga_append_only();
create trigger trg_reaperturas_mes_no_truncate before truncate on crm.reaperturas_mes
  for each statement execute function private.trg_plazo_carga_append_only();
create trigger trg_audit_reaperturas_mes after insert or update or delete on crm.reaperturas_mes
  for each row execute function private.log_audit_crm();

create trigger trg_plazos_carga_mes_00_append_only before update or delete on crm.plazos_carga_mes
  for each row execute function private.trg_plazo_carga_append_only();
create trigger trg_plazos_carga_mes_no_truncate before truncate on crm.plazos_carga_mes
  for each statement execute function private.trg_plazo_carga_append_only();
create trigger trg_audit_plazos_carga_mes after insert or update or delete on crm.plazos_carga_mes
  for each row execute function private.log_audit_crm();

-- ── 3 · El CHECK de plazo de las acreditaciones: de igualdad a mínimo ──────────────────────────────────────────────────
do $check_plazo$
declare v_nombre text;
begin
  select c.conname into strict v_nombre
    from pg_catalog.pg_constraint c
   where c.conrelid = 'crm.conversion_acreditaciones'::regclass and c.contype = 'c'
     and pg_catalog.pg_get_constraintdef(c.oid) = 'CHECK ((plazo_hasta = private.conversion_plazo_hasta(periodo_comercial)))';
  execute pg_catalog.format('alter table crm.conversion_acreditaciones drop constraint %I', v_nombre);
end
$check_plazo$;
alter table crm.conversion_acreditaciones
  add constraint conversion_acreditaciones_plazo_minimo_check
  check (plazo_hasta >= private.conversion_plazo_base(periodo_comercial));

-- ── 4 · Núcleo: el plazo vigente y su volatilidad ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION private.conversion_plazo_hasta(p_periodo date)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE STRICT
 SET search_path TO ''
AS $function$
declare
  -- La base valida el periodo (22023) antes de leer nada.
  v_base timestamptz := private.conversion_plazo_base(p_periodo);
  v_decidido timestamptz;
begin
  -- 14/10/2026: la última decisión de Gerencia para ese mes (crm.fijar_plazo_carga_mes); sin decisión, la base.
  select d.plazo_hasta into v_decidido
    from crm.plazos_carga_mes d
   where d.periodo = p_periodo
   order by d.decidido_en desc, d.id desc
   limit 1;
  return coalesce(v_decidido, v_base);
end;
$function$;

alter function private.conversion_decidir_plazo(date, timestamptz, timestamptz, timestamptz) stable;
alter function private.cierre_mes_ventana_desde(date) stable;

-- ── 5 · Núcleo: la autorización de la reapertura y los tres candados ───────────────────────────────────────────────────
create function private.reapertura_autoriza(p_periodo date, p_cierre_externo uuid default null)
returns boolean
language sql
stable
set search_path = ''
as $function$
  -- Solo si en ESTA transacción (su id y su instante de inicio, que fija el trigger de la tabla) se registró la reapertura
  -- de ESE mes (private.reabrir_mes); para un cierre en cooperativa, además, que esa reapertura lo haya respaldado (es una
  -- de las ventas registradas tarde que devuelve). Sin GUC: la llave es la fila. Alcance: la transacción SUPERIOR entera,
  -- incluidas sus subtransacciones (el id y now() son los de la superior); deshacer la subtransacción que insertó la fila
  -- la retira y deja de autorizar.
  select exists (
    select 1 from crm.reaperturas_mes r
     where r.periodo = p_periodo
       and r.transaccion = pg_catalog.pg_current_xact_id_if_assigned()
       and r.reabierto_en = pg_catalog.now()
       and (p_cierre_externo is null
            or r.respaldo -> 'cierres_externos'
                 @> pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('id', p_cierre_externo)))
  )
$function$;

-- Cuerpo vivo + la rama de la reapertura (nada más cambia).
CREATE OR REPLACE FUNCTION private.trg_cierre_mes_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- 14/10/2026 (plazo de carga por mes): única excepción. La reapertura de Gerencia (private.reabrir_mes, desde
  -- crm.fijar_plazo_carga_mes) retira el sello y la foto del mes que reabre, en SU transacción y solo de ese mes.
  if tg_op = 'DELETE' and private.reapertura_autoriza(old.periodo) then
    return old;
  end if;
  raise exception using
    errcode = 'P0409',
    message = 'Un mes cerrado no se edita ni se borra',
    hint    = 'Por diseno: lo que haya que corregir de un mes pagado se descuenta en el mes vivo, no se reescribe el mes.';
end;
$function$;

-- Cuerpo vivo (20261005200945) + dos ramas de la reapertura (nada más cambia). Las ramas van anidadas: una expresión que
-- nombra una columna de otra tabla no se prepara para las tablas que no la tienen.
CREATE OR REPLACE FUNCTION private.f4_fuente_inmutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_table_schema='crm' and tg_table_name='inversion_eventos' and tg_op='DELETE' then
    if old.tipo='registro' and exists (
      select 1 from crm.contratos_eliminados_auditoria a
      join private.contrato_eliminaciones r on r.contrato_id=a.contrato_id
      where r.token::text=current_setting('crm.contrato_registro_eliminacion',true)
        and r.solicitado_por=(select auth.uid()) and a.eliminado_por=r.solicitado_por
        and a.snapshot->>'version' in ('3','4')
        and a.snapshot#>>'{inversion,id}'=old.inversion_id::text
        and a.snapshot->'inversion_eventos' @> jsonb_build_array(to_jsonb(old))
    ) then return old; end if;
    -- 05/10/2026: el evento de una inversión de cooperativa que se elimina con copia auditada (crm.eliminar_inversion_fn).
    if private.inversion_eliminacion_autoriza('evento', old.inversion_id, to_jsonb(old)) then return old; end if;
  end if;
  -- 14/10/2026: la reapertura de un mes (private.reabrir_mes) retira el rastro de registro tardío de ESE mes, en SU transacción.
  if tg_table_schema='crm' and tg_table_name='inversion_ajustes_mes_cerrado' and tg_op='DELETE' then
    if private.reapertura_autoriza(old.periodo_origen) then return old; end if;
  end if;
  if tg_table_name in ('inversion_ajustes_mes_cerrado','inversion_eventos','inversion_solicitud_revisiones','inversion_solicitud_correcciones') then
    raise exception 'El historial de una inversión no se modifica ni se elimina' using errcode='P0409';
  end if;
  -- 14/10/2026: la misma reapertura devuelve la venta en cooperativa registrada tarde a su mes comercial: solo cambia la
  -- imputación, solo a la fecha comercial, solo de una venta que esa reapertura respaldó y solo en su transacción. Nada
  -- más de la fila puede cambiar en el mismo UPDATE, tampoco con la válvula crm.op_privilegiada encendida (revisión Codex P2).
  if tg_table_schema='crm' and tg_table_name='cierres_externos' and tg_op='UPDATE' then
    if new.fecha_imputacion is distinct from old.fecha_imputacion
       and new.fecha_imputacion = old.fecha_comercial
       and (pg_catalog.to_jsonb(new) - 'fecha_imputacion') = (pg_catalog.to_jsonb(old) - 'fecha_imputacion')
       and private.reapertura_autoriza(pg_catalog.date_trunc('month', old.fecha_comercial::timestamp)::date, old.id) then
      return new;
    end if;
  end if;
  if new.es_cierre_inicial is distinct from old.es_cierre_inicial
     or new.fecha_comercial is distinct from old.fecha_comercial
     or new.fecha_imputacion is distinct from old.fecha_imputacion
     or new.comprobante_objeto_id is distinct from old.comprobante_objeto_id then
    raise exception 'La clase, las fechas y el comprobante del cierre conservan su registro original' using errcode='P0409';
  end if;
  return new;
end;
$function$;

-- Cuerpo vivo (20261005200945) + la reapertura en la válvula de UPDATE (nada más cambia).
CREATE OR REPLACE FUNCTION private.trg_cierres_externos_inmutables()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if tg_op = 'DELETE' then
    -- Única excepción (05/10/2026): la eliminación auditada de una inversión (crm.eliminar_inversion_fn), con la
    -- llave de un solo uso de SU copia, en SU transacción, del actor de la copia y la fila idéntica a la copiada.
    if private.inversion_eliminacion_autoriza('cierre', old.id, pg_catalog.to_jsonb(old)) then
      return old;
    end if;
    raise exception using
      errcode = 'P0409',
      message = 'Un cierre externo no se elimina: gerencia lo corrige via crm.corregir_cierre_externo',
      hint    = 'El cierre respalda una conversion ya contada; borrar la fila dejaria un convertido sin perfil ni cierre (invariante P4).';
  end if;

  -- 14/10/2026 (plazo de carga por mes): la reapertura de Gerencia (private.reabrir_mes) abre esta válvula SOLO para UPDATE
  -- de una venta que esa reapertura respaldó, en SU transacción, y solo para devolver la imputación a la fecha comercial:
  -- ninguna otra columna de la fila puede cambiar en el mismo UPDATE (revisión auditor-rls, P2).
  if not v_priv
     and (private.reapertura_autoriza(pg_catalog.date_trunc('month', old.fecha_comercial::timestamp)::date, old.id)
          and new.fecha_imputacion is not distinct from old.fecha_comercial
          and (pg_catalog.to_jsonb(new) - 'fecha_imputacion') = (pg_catalog.to_jsonb(old) - 'fecha_imputacion')) is not true then
    raise exception using
      errcode = 'P0409',
      message = 'Un cierre externo solo se corrige via crm.corregir_cierre_externo',
      detail  = pg_catalog.format('cierre %s (lead %s)', old.id, old.lead_id);
  end if;

  -- Con la válvula encendida, las columnas de identidad se restauran en
  -- silencio (no con excepción): la RPC de corrección no las manda, así que
  -- esto es un cinturón contra bugs futuros de rutas DEFINER, no una rama que
  -- un usuario pueda pisar.
  new.id := old.id;
  new.lead_id := old.lead_id;
  new.vendedor_id := old.vendedor_id;
  new.documento_tipo := old.documento_tipo;
  new.documento := old.documento;
  new.nombre_completo := old.nombre_completo;
  new.creado_por := old.creado_por;
  new.creado_en := old.creado_en;

  -- La anulación es de UNA SOLA DIRECCIÓN. Des-anular sería volver a pagar un
  -- cierre que ya se declaró falso, y eso no se hace en silencio desde una ruta
  -- DEFINER: aquí se restaura y punto. (Aquí SÍ con excepción y no en silencio:
  -- si una RPC futura intentara resucitar un cierre anulado, el error tiene que
  -- salir a la superficie, no perderse en un 200 mudo.)
  if old.anulado_en is not null
     and (new.anulado_en is null
          or new.anulado_por is distinct from old.anulado_por
          or new.anulado_en is distinct from old.anulado_en) then
    raise exception using
      errcode = 'P0409',
      message = 'Un cierre externo anulado no se restablece',
      detail  = pg_catalog.format('cierre %s (lead %s), anulado el %s',
                                  old.id, old.lead_id, old.anulado_en);
  end if;
  return new;
end;
$function$;

-- ── 6 · Núcleo: quién se puede reabrir, la reevaluación y la reapertura ───────────────────────────────────────────────
-- UNA regla (la usan private.reabrir_mes y crm.plazos_carga_mes_fn). NULL = se puede reabrir; si no, el motivo para Gerencia.
-- Mismas comprobaciones y en el mismo orden que scripts/reexpresion-septiembre-2026/01-reabrir.sql, más «mes anterior».
create function private.reapertura_impedimento(p_periodo date)
returns text
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_mes_actual date := pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date;
  v_fin date;
  v_mes text;
  v_ultimo date;
  v_meta uuid;
begin
  if p_periodo is null or not pg_catalog.isfinite(p_periodo)
     or p_periodo <> pg_catalog.date_trunc('month', p_periodo::timestamp)::date then
    raise exception 'El periodo debe ser el primer dia de un mes finito' using errcode = '22023';
  end if;
  v_fin := (p_periodo + interval '1 month')::date;
  v_mes := private.etiqueta_mes_es(p_periodo) || ' ' || pg_catalog.to_char(p_periodo, 'YYYY');

  if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = p_periodo) then
    return pg_catalog.format('%s no está cerrado: no hay nada que reabrir', v_mes);
  end if;
  -- 0. Con metas publicadas: el ciclo solo vuelve a sellar meses con metas (private.cierre_mes_pendiente); uno sin metas
  --    quedaría abierto para siempre en cuanto se sellara el siguiente (revisión Codex r2, P2).
  if not exists (select 1 from crm.meta_periodos mp where mp.periodo = p_periodo) then
    return pg_catalog.format('%s no tiene metas publicadas: el ciclo no lo volvería a cerrar', v_mes);
  end if;
  -- 1. El ÚLTIMO mes sellado (reabrir uno con un mes posterior sellado rompería el orden del ciclo y los arrastres) …
  select max(pc.periodo) into v_ultimo from crm.periodos_cerrados pc;
  if v_ultimo > p_periodo then
    return pg_catalog.format('Solo se reabre el último mes cerrado, y %s %s ya está cerrado',
      private.etiqueta_mes_es(v_ultimo), pg_catalog.to_char(v_ultimo, 'YYYY'));
  end if;
  -- … y el mes ANTERIOR al mes en curso (en octubre, solo septiembre).
  if p_periodo <> (v_mes_actual - interval '1 month')::date then
    return pg_catalog.format('Solo se reabre el mes anterior al mes en curso (%s %s)',
      private.etiqueta_mes_es((v_mes_actual - interval '1 month')::date),
      pg_catalog.to_char((v_mes_actual - interval '1 month')::date, 'YYYY'));
  end if;
  if not exists (select 1 from crm.cierre_mes_vendedor f where f.periodo = p_periodo) then
    return pg_catalog.format('El cierre de %s no tiene foto de analistas: revisarlo con soporte antes de reabrir', v_mes);
  end if;
  -- 2. Deudas NACIDAS de M (anular una venta de M después del sello): con el mes abierto se descontarían dos veces.
  if exists (select 1 from crm.ajustes_mes_cerrado a where a.periodo_origen = p_periodo) then
    return pg_catalog.format('Hay deudas nacidas de %s (ventas anuladas después del cierre): reabrirlo las descontaría dos veces. Revisar con soporte', v_mes);
  end if;
  -- 3. Deudas ABSORBIDAS por la foto de M: al retirarla se perdería un descuento ya saldado (el fallo de dinero del 15/08).
  if exists (select 1 from crm.cierre_mes_vendedor f
              where f.periodo = p_periodo
                and (f.ajuste_numerador <> 0 or f.ajuste_pen <> 0 or f.ajuste_usd <> 0)) then
    return pg_catalog.format('El cierre de %s ya descontó deudas de meses anteriores: reabrirlo perdería ese descuento. Revisar con soporte', v_mes);
  end if;
  -- 4. Cada registro tardío de M es una venta en cooperativa con fecha comercial en M, imputada (igual que su rastro) a un
  --    mes posterior y ABIERTO. Uno de contrato u otra forma no se adivina.
  if exists (select 1
               from crm.inversion_ajustes_mes_cerrado ia
               join crm.inversiones i on i.id = ia.inversion_id
               left join crm.cierres_externos ce on ce.id = i.cierre_externo_id
              where ia.periodo_origen = p_periodo
                and (ce.id is null
                     or ce.fecha_comercial is null
                     or ce.fecha_comercial < p_periodo or ce.fecha_comercial >= v_fin
                     or ce.fecha_imputacion is distinct from ia.fecha_imputacion
                     or ce.fecha_imputacion < v_fin
                     or exists (select 1 from crm.periodos_cerrados pc
                                 where pc.periodo = pg_catalog.date_trunc('month', ce.fecha_imputacion::timestamp)::date))) then
    return pg_catalog.format('Hay una venta de %s registrada después del cierre que no es una venta en cooperativa que se pueda devolver al mes (contrato u otra forma): revisar con soporte', v_mes);
  end if;
  --    Su analista efectivo (el mismo que usa el capital) tiene meta en M (última revisión): si no, dejaría de sumar a su cuota.
  select mp.id into v_meta from crm.meta_periodos mp where mp.periodo = p_periodo order by mp.revision desc limit 1;
  if exists (select 1
               from crm.inversion_ajustes_mes_cerrado ia
               join crm.inversiones i on i.id = ia.inversion_id
               join crm.cierres_externos ce on ce.id = i.cierre_externo_id
               cross join lateral (select private.analista_efectivo_cierre(ce.id) as analista_id) ef
              where ia.periodo_origen = p_periodo
                and (ef.analista_id is null
                     or not exists (select 1 from crm.metas_vendedor mv
                                     where mv.meta_periodo_id = v_meta and mv.vendedor_id = ef.analista_id))) then
    return pg_catalog.format('El analista de una venta en cooperativa de %s registrada después del cierre no tiene meta en ese mes: al devolverla dejaría de sumar a su cuota. Revisar con Gerencia', v_mes);
  end if;
  -- 5. Ninguna venta en cooperativa de M imputada a otro mes SIN rastro.
  if exists (select 1 from crm.cierres_externos ce
              where ce.fecha_comercial >= p_periodo and ce.fecha_comercial < v_fin
                and ce.fecha_imputacion >= v_fin
                and not exists (select 1
                                  from crm.inversion_ajustes_mes_cerrado ia
                                  join crm.inversiones i on i.id = ia.inversion_id
                                 where ia.periodo_origen = p_periodo and i.cierre_externo_id = ce.id)) then
    return pg_catalog.format('Hay ventas en cooperativa de %s imputadas a otro mes sin rastro de registro tardío: revisar con soporte', v_mes);
  end if;
  return null;
end;
$function$;

-- Reevaluación de las acreditaciones de un mes con su plazo VIGENTE. Misma decisión (private.conversion_decidir_plazo), misma
-- exclusión de fuente (private.conversion_exclusion_fuente, la del sello) y misma regla de identidad que el escritor
-- (private.conversion_acreditar_fuente). Cuenta con contadores, no con agregados (censo analítico).
create function private.conversion_reevaluar_plazo(p_periodo date)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  v_plazo timestamptz;
  v_sello timestamptz;
  r record;
  v_decision record;
  v_exclusion text;
  v_estado text;
  v_persona uuid;
  v_reevaluadas integer := 0;
  v_conflictos integer := 0;
begin
  if p_periodo is null then
    raise exception 'El periodo debe ser el primer dia de un mes finito' using errcode = '22023';
  end if;
  v_plazo := private.conversion_plazo_hasta(p_periodo);
  select pc.cerrado_en into v_sello from crm.periodos_cerrados pc where pc.periodo = p_periodo;
  for r in
    select ca.id, ca.lead_id, ca.fuente_tipo, ca.fuente_id, ca.fecha_comercial, ca.confirmado_en, ca.vinculado_en
      from crm.conversion_acreditaciones ca
     where ca.periodo_comercial = p_periodo
       and ca.estado in ('fuera_de_plazo', 'mes_sellado')
       and ca.acreditado_en < v_plazo
     order by ca.acreditado_en, ca.id
       for update
  loop
    v_exclusion := private.conversion_exclusion_fuente(r.fuente_tipo, r.fuente_id);
    -- Una fuente que ya no existe la coordina su retiro (private.conversion_coordinar_retiro_fuente), no esta reevaluación.
    if v_exclusion is distinct from 'elegible' and v_exclusion is distinct from 'fuente_demo'
       and v_exclusion is distinct from 'operacion_cartera' then
      continue;
    end if;
    -- La regla del escritor, ANTES de decidir el estado como él (también si la fuente resultará demo o de cartera): una
    -- identidad canónica tiene a lo sumo una captación acreditada desde septiembre. Si ya la tiene otro lead, la fila se
    -- deja como está y se cuenta como conflicto, donde el escritor lanzaría P0409 (revisión Codex P3).
    select private.inversionista_canonica(l.inversionista_id) into v_persona from crm.leads l where l.id = r.lead_id;
    if v_persona is not null then
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.conversion_acreditaciones'),
        pg_catalog.hashtext(v_persona::text));
      if exists (select 1 from crm.conversion_acreditaciones ca
                  where ca.lead_id <> r.lead_id
                    and ca.estado = 'acreditada'
                    and ca.periodo_comercial >= date '2026-09-01'
                    and private.inversionista_canonica(ca.inversionista_id) = v_persona) then
        v_conflictos := v_conflictos + 1;
        continue;
      end if;
    end if;
    select * into v_decision
      from private.conversion_decidir_plazo(r.fecha_comercial, r.confirmado_en, r.vinculado_en, v_sello);
    v_estado := case v_exclusion when 'fuente_demo' then 'fuente_demo'
                                 when 'operacion_cartera' then 'operacion_cartera'
                                 else v_decision.estado end;
    update crm.conversion_acreditaciones
       set estado = v_estado,
           plazo_hasta = v_decision.plazo_hasta,
           actualizado_en = private.conversion_instante_servidor()
     where id = r.id;
    v_reevaluadas := v_reevaluadas + 1;
  end loop;
  return pg_catalog.jsonb_build_object('reevaluadas', v_reevaluadas, 'conflictos', v_conflictos);
end;
$function$;

-- La reapertura: las operaciones de scripts/reexpresion-septiembre-2026/01-reabrir.sql en el mismo orden (respaldo →
-- rastros tardíos → foto → sello → imputación de las ventas tardías → marcas de sello), sin ALTER TABLE ni GUC: la fila de
-- crm.reaperturas_mes ES la autorización de los candados, solo para ese mes y solo en esta transacción.
create function private.reabrir_mes(p_periodo date, p_motivo text, p_por uuid)
returns uuid
language plpgsql
set search_path = ''
as $function$
declare
  v_impedimento text;
  v_sello crm.periodos_cerrados%rowtype;
  v_tardias uuid[];
  v_respaldo jsonb;
  v_resumen jsonb;
  v_id uuid;
  v_n integer;
  v_liberadas integer;
begin
  if p_periodo is null or p_por is null then
    raise exception 'Faltan el mes o quien reabre' using errcode = '22023';
  end if;
  -- Mismos candados que crm.cerrar_periodo (global y mensual, en ese orden), ANTES de mirar el sello. La puerta ya los
  -- tiene: en la misma transacción se vuelven a tomar sin esperar.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
    (p_periodo - date '2000-01-01')::integer);

  v_impedimento := private.reapertura_impedimento(p_periodo);
  if v_impedimento is not null then
    raise exception using errcode = 'P0409', message = v_impedimento;
  end if;

  select * into strict v_sello from crm.periodos_cerrados pc where pc.periodo = p_periodo;
  select coalesce(array_agg(distinct i.cierre_externo_id), '{}'::uuid[]) into v_tardias
    from crm.inversion_ajustes_mes_cerrado ia
    join crm.inversiones i on i.id = ia.inversion_id
   where ia.periodo_origen = p_periodo;

  -- 1. Copia íntegra de lo que se va a retirar o cambiar (estado ANTES).
  v_respaldo := pg_catalog.jsonb_build_object(
    'version', 1,
    'sello', pg_catalog.to_jsonb(v_sello),
    'foto', (select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(f) order by f.vendedor_id), '[]'::jsonb)
               from crm.cierre_mes_vendedor f where f.periodo = p_periodo),
    'acreditaciones', (select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(ca) order by ca.id), '[]'::jsonb)
                         from crm.conversion_acreditaciones ca where ca.periodo_comercial = p_periodo),
    'rastros_tardios', (select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(ia) order by ia.inversion_id), '[]'::jsonb)
                          from crm.inversion_ajustes_mes_cerrado ia where ia.periodo_origen = p_periodo),
    -- Sin datos personales del cliente (documento, tipo y nombre): la fila sigue en crm.cierres_externos y aquí basta lo
    -- que la reapertura cambia (revisión auditor-rls, P3).
    'cierres_externos', (select coalesce(pg_catalog.jsonb_agg(
                                  pg_catalog.to_jsonb(ce) - 'documento' - 'documento_tipo' - 'nombre_completo'
                                  order by ce.id), '[]'::jsonb)
                           from crm.cierres_externos ce where ce.id = any (v_tardias)));
  v_resumen := pg_catalog.jsonb_build_object(
    'foto_retirada', pg_catalog.jsonb_array_length(v_respaldo -> 'foto'),
    'acreditaciones_respaldadas', pg_catalog.jsonb_array_length(v_respaldo -> 'acreditaciones'),
    'acreditaciones_liberadas', (select count(*) from crm.conversion_acreditaciones ca
                                  where ca.periodo_comercial = p_periodo and ca.sellado_en is not null),
    'acreditaciones_que_estaban_incluidas', (select count(*) from crm.conversion_acreditaciones ca
                                              where ca.periodo_comercial = p_periodo and ca.incluida_en_sello),
    'rastros_retirados', pg_catalog.jsonb_array_length(v_respaldo -> 'rastros_tardios'),
    'ventas_devueltas', (select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'cierre_externo_id', ce.id, 'cooperativa', ce.cooperativa, 'monto', ce.monto, 'moneda', ce.moneda,
        'fecha_comercial', ce.fecha_comercial, 'imputada_antes_a', ce.fecha_imputacion,
        'analista_id', private.analista_efectivo_cierre(ce.id), 'anulada', ce.anulado_en is not null)
        order by ce.fecha_comercial, ce.id), '[]'::jsonb)
      from crm.cierres_externos ce where ce.id = any (v_tardias)));

  -- La fila es la autorización: transaccion = la de ESTA reapertura (default pg_current_xact_id()).
  insert into crm.reaperturas_mes (periodo, motivo, decidido_por, respaldo, resumen)
  values (p_periodo, p_motivo, p_por, v_respaldo, v_resumen)
  returning id into v_id;

  -- 2. Rastros tardíos primero: apuntan (FK) al sello.
  delete from crm.inversion_ajustes_mes_cerrado ia where ia.periodo_origen = p_periodo;
  get diagnostics v_n = row_count;
  if v_n <> pg_catalog.jsonb_array_length(v_respaldo -> 'rastros_tardios') then
    raise exception 'REAPERTURA: no se retiraron todos los rastros tardíos del mes';
  end if;
  -- 3. Foto y sello.
  delete from crm.cierre_mes_vendedor f where f.periodo = p_periodo;
  get diagnostics v_n = row_count;
  if v_n <> pg_catalog.jsonb_array_length(v_respaldo -> 'foto') then
    raise exception 'REAPERTURA: no se retiró la foto completa del mes';
  end if;
  delete from crm.periodos_cerrados pc where pc.periodo = p_periodo;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'REAPERTURA: no se retiró el sello del mes';
  end if;
  -- 4. Las ventas en cooperativa registradas tarde vuelven a su mes: imputación = fecha comercial, lo que el sistema pone
  --    cuando se registran a tiempo.
  update crm.cierres_externos ce set fecha_imputacion = ce.fecha_comercial where ce.id = any (v_tardias);
  get diagnostics v_n = row_count;
  if v_n <> pg_catalog.cardinality(v_tardias) then
    raise exception 'REAPERTURA: no se devolvieron todas las ventas registradas tarde';
  end if;
  -- 5. Las acreditaciones vuelven a «sin sellar»: el próximo sello las fija de nuevo. `ajuste_anulacion_en_sello` solo
  --    existe desde 20261012220959: consulta dinámica (una referencia estática a una columna ausente no se prepara).
  if exists (select 1 from pg_catalog.pg_attribute a
              where a.attrelid = 'crm.conversion_acreditaciones'::regclass
                and a.attname = 'ajuste_anulacion_en_sello' and a.attnum > 0 and not a.attisdropped) then
    execute 'update crm.conversion_acreditaciones
                set sellado_en = null, incluida_en_sello = null, ajuste_anulacion_en_sello = null,
                    actualizado_en = pg_catalog.clock_timestamp()
              where periodo_comercial = $1 and sellado_en is not null'
      using p_periodo;
  else
    update crm.conversion_acreditaciones
       set sellado_en = null, incluida_en_sello = null, actualizado_en = pg_catalog.clock_timestamp()
     where periodo_comercial = p_periodo and sellado_en is not null;
  end if;
  get diagnostics v_liberadas = row_count;

  -- Postflight de la reapertura (01-reabrir.sql).
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = p_periodo)
     or exists (select 1 from crm.cierre_mes_vendedor f where f.periodo = p_periodo) then
    raise exception 'REAPERTURA: el mes sigue sellado';
  end if;
  if exists (select 1 from crm.conversion_acreditaciones ca
              where ca.periodo_comercial = p_periodo and ca.sellado_en is not null)
     or v_liberadas <> (v_resumen ->> 'acreditaciones_liberadas')::integer then
    raise exception 'REAPERTURA: quedan acreditaciones del mes marcadas como selladas';
  end if;
  if exists (select 1 from crm.inversion_ajustes_mes_cerrado ia where ia.periodo_origen = p_periodo)
     or exists (select 1 from crm.cierres_externos ce
                 where ce.id = any (v_tardias) and ce.fecha_imputacion is distinct from ce.fecha_comercial) then
    raise exception 'REAPERTURA: una venta registrada tarde no volvió a su mes';
  end if;
  return v_id;
end;
$function$;

-- ── 7 · Núcleo de las dos puertas (la puerta valida, autoriza y delega: no lee ni escribe tablas) ─────────────────────
-- Fija el plazo de un mes (y lo reabre si está sellado). Lo llama SOLO crm.fijar_plazo_carga_mes, con los datos ya
-- validados y el actor sacado de la sesión.
create function private.fijar_plazo_carga(p_periodo date, p_ultimo_dia date, p_motivo text, p_por uuid)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  v_plazo timestamptz;
  v_ultimo_sellado date;
  v_reapertura uuid;
  v_reeval jsonb;
  v_ventas jsonb := '[]'::jsonb;
begin
  if p_periodo is null or p_ultimo_dia is null or p_motivo is null or p_por is null then
    raise exception 'Faltan el mes, el último día, el motivo o quien decide' using errcode = '22023';
  end if;
  v_plazo := (p_ultimo_dia + 1)::timestamp at time zone 'America/Lima';

  -- Mismos candados que crm.cerrar_periodo (global y mensual, en ese orden), ANTES de leer el sello.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
    (p_periodo - date '2000-01-01')::integer);

  -- Un mes sin metas publicadas no tiene cierre: el ciclo no lo sella (private.cierre_mes_pendiente solo mira meses con
  -- metas) y, en cuanto se sellara el siguiente, su plazo quedaría sin sello posible ni decisión modificable (revisión
  -- Codex r2, P2). Va antes de mirar el sello: tampoco se reabre.
  if not exists (select 1 from crm.meta_periodos mp where mp.periodo = p_periodo) then
    raise exception using errcode = '22023',
      message = pg_catalog.format('%s %s no tiene metas publicadas: no tiene cierre ni plazo de carga',
        private.etiqueta_mes_es(p_periodo), pg_catalog.to_char(p_periodo, 'YYYY'));
  end if;

  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = p_periodo) then
    -- Un mes sellado se reabre con la misma acción (o se niega con el motivo: P0409).
    v_reapertura := private.reabrir_mes(p_periodo, p_motivo, p_por);
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'cooperativa', v -> 'cooperativa', 'monto', v -> 'monto', 'moneda', v -> 'moneda',
             'fecha_comercial', v -> 'fecha_comercial', 'imputada_antes_a', v -> 'imputada_antes_a')
             order by v ->> 'fecha_comercial', v ->> 'cierre_externo_id'), '[]'::jsonb)
      into v_ventas
      from crm.reaperturas_mes r
      cross join lateral pg_catalog.jsonb_array_elements(r.resumen -> 'ventas_devueltas') v
     where r.id = v_reapertura;
  else
    -- Un mes sin sellar por DETRÁS del último sellado no lo sella nadie (crm.cerrar_periodo se niega): su plazo no
    -- cambiaría nada y reevaluarlo solo movería la regla de identidad (revisión auditor-rls, P3).
    select max(pc.periodo) into v_ultimo_sellado from crm.periodos_cerrados pc;
    if v_ultimo_sellado > p_periodo then
      raise exception using errcode = '22023',
        message = pg_catalog.format('%s %s quedó por detrás del último mes cerrado (%s %s): ya no admite plazo de carga',
          private.etiqueta_mes_es(p_periodo), pg_catalog.to_char(p_periodo, 'YYYY'),
          private.etiqueta_mes_es(v_ultimo_sellado), pg_catalog.to_char(v_ultimo_sellado, 'YYYY'));
    end if;
  end if;

  insert into crm.plazos_carga_mes (periodo, ultimo_dia, plazo_hasta, motivo, decidido_por, reapertura_id)
  values (p_periodo, p_ultimo_dia, v_plazo, p_motivo, p_por, v_reapertura);

  v_reeval := private.conversion_reevaluar_plazo(p_periodo);

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'mes', pg_catalog.to_char(p_periodo, 'YYYY-MM'),
    'ultimo_dia', p_ultimo_dia,
    'plazo_hasta', v_plazo,
    'reabierto', v_reapertura is not null,
    'reapertura_id', v_reapertura,
    'acreditaciones_reevaluadas', (v_reeval ->> 'reevaluadas')::integer,
    'conflictos_identidad', (v_reeval ->> 'conflictos')::integer,
    'ventas_devueltas', v_ventas);
end;
$function$;

-- Lo que ve Gerencia en la tarjeta «Plazo de carga». Lo llama SOLO crm.plazos_carga_mes_fn.
create function private.plazos_carga_mes_lectura()
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_ahora timestamptz := pg_catalog.now();
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_mes_actual date := pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date;
  v_anterior date;
  v_ultimo_sellado date;
  v_meses jsonb;
begin
  v_anterior := (v_mes_actual - interval '1 month')::date;
  select max(pc.periodo) into v_ultimo_sellado from crm.periodos_cerrados pc;

  -- Meses: los que el ciclo todavía debe sellar (con metas, posteriores al último sellado y anteriores al mes en curso: el
  -- mismo conjunto cuyo mínimo da private.cierre_mes_pendiente), los abiertos con una decisión de Gerencia que todavía
  -- admiten otra (posteriores al último sellado: aunque no tengan metas ni sean ya el mes anterior; revisión Codex P2), el
  -- mes anterior y el mes en curso.
  with meses as (
    select mp.periodo
      from crm.meta_periodos mp
     where mp.periodo < v_mes_actual
       and mp.periodo > coalesce(v_ultimo_sellado, '-infinity'::date)
       and not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = mp.periodo)
    union
    select dd.periodo
      from crm.plazos_carga_mes dd
     where dd.periodo <= v_mes_actual
       and dd.periodo > coalesce(v_ultimo_sellado, '-infinity'::date)
       and not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = dd.periodo)
    union select v_anterior
    union select v_mes_actual
  )
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'mes', pg_catalog.to_char(m.periodo, 'YYYY-MM'),
           'mes_nombre', private.etiqueta_mes_es(m.periodo) || ' ' || pg_catalog.to_char(m.periodo, 'YYYY'),
           'sellado', s.sellado,
           'plazo_base_ultimo_dia', (p.base at time zone 'America/Lima')::date - 1,
           'plazo_ultimo_dia', (p.plazo at time zone 'America/Lima')::date - 1,
           'ampliado', p.plazo > p.base,
           'decision', case when d.id is null then null else pg_catalog.jsonb_build_object(
               'ultimo_dia', d.ultimo_dia, 'motivo', d.motivo, 'decidido_por', d.nombre, 'decidido_en', d.decidido_en) end,
           'reabrible', s.sellado and i.impedimento is null,
           'motivo_no_reabrible', i.impedimento,
           'ultima_reapertura', case when r.id is null then null else pg_catalog.jsonb_build_object(
               'reabierto_en', r.reabierto_en, 'decidido_por', r.nombre) end)
           order by m.periodo), '[]'::jsonb)
    into v_meses
    from (select distinct x.periodo from meses x) m
    cross join lateral (select exists (select 1 from crm.periodos_cerrados pc where pc.periodo = m.periodo) as sellado) s
    cross join lateral (select case when s.sellado then private.reapertura_impedimento(m.periodo) end as impedimento) i
    cross join lateral (select private.conversion_plazo_base(m.periodo) as base,
                               private.conversion_plazo_hasta(m.periodo) as plazo) p
    left join lateral (select dd.id, dd.ultimo_dia, dd.motivo, dd.decidido_en,
                              coalesce(nullif(pg_catalog.btrim(pf.nombre_completo), ''),
                                       '(sin nombre · ' || pg_catalog.left(dd.decidido_por::text, 8) || ')') as nombre
                         from crm.plazos_carga_mes dd
                         left join public.perfiles pf on pf.id = dd.decidido_por
                        where dd.periodo = m.periodo
                        order by dd.decidido_en desc, dd.id desc
                        limit 1) d on true
    left join lateral (select rr.id, rr.reabierto_en,
                              coalesce(nullif(pg_catalog.btrim(pf.nombre_completo), ''),
                                       '(sin nombre · ' || pg_catalog.left(rr.decidido_por::text, 8) || ')') as nombre
                         from crm.reaperturas_mes rr
                         left join public.perfiles pf on pf.id = rr.decidido_por
                        where rr.periodo = m.periodo
                        order by rr.reabierto_en desc, rr.id desc
                        limit 1) r on true;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'hoy', v_hoy,
    'zona', 'America/Lima',
    'meses', v_meses);
end;
$function$;

-- ── 8 · Puertas ────────────────────────────────────────────────────────────────────────────────────────────────────────
-- crm.cerrar_periodo: cuerpo vivo (20261007203000) + la ventana mirada otra vez con los candados tomados (nada más cambia).
-- El ciclo diario la llama: un sello que esperó a una ampliación de Gerencia ahora se niega (22023) y el ciclo lo anota en
-- su `fallo`; al día siguiente el ciclo ya ve el plazo nuevo y no lo intenta.
CREATE OR REPLACE FUNCTION crm.cerrar_periodo(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid         uuid := (select auth.uid());
  v_rol         text;
  v_automatico  boolean;
  v_mes_actual  date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_ini         timestamptz;
  v_fin         timestamptz;
  v_factor      numeric;
  v_periodo_id  uuid;
  v_revision    integer;
  v_suelo       timestamptz;
  v_medible     boolean;
  v_motivo      text;
  v_cobertura   jsonb;
  v_vendedores  integer;
  v_fuera_ranking jsonb := '[]'::jsonb;
  v_pendiente   date;
  v_ventana     timestamptz;
  v_ultimo_sellado date;
begin
  -- 1) Gate. `auth.uid()` nulo = el ciclo automatico (service_role); con uid,
  --    solo gerencia. Un vendedor o un supervisor no cierran meses.
  v_rol := private.rol_crm(v_uid);
  v_automatico := v_uid is null;
  if not v_automatico and v_rol is distinct from 'gerencia' then
    raise exception 'Solo gerencia cierra un mes' using errcode = '42501';
  end if;

  -- 2) El periodo.
  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes' using errcode = '22023';
  end if;
  -- El mes en curso NO se cierra: todavia esta pasando. Y el siguiente tampoco,
  -- obviamente. La ventana de ajuste (del 1 al 10) vive en el mes SIGUIENTE al
  -- que se cierra, asi que aqui basta con exigir que el mes ya haya terminado.
  if p_periodo >= v_mes_actual then
    raise exception 'Un mes solo se cierra cuando ya termino' using errcode = '22023';
  end if;

  -- 2bis) EL CANDADO. Del 1 al 10 del mes siguiente el mes todavia admite
  --    correcciones, asi que NADIE lo sella: ni gerencia ni el ciclo. Sin esto,
  --    el momento de cerrar decide de que mes sale el dinero de una correccion.
  --    Es un SUELO, no una fecha exacta (decision de Miguel, 2026-08-15): pasado
  --    el dia 10 se puede cerrar cualquier dia, para que un fallo del ciclo no
  --    deje el mes atascado bloqueando a todos los siguientes.
  v_ventana := private.cierre_mes_ventana_desde(p_periodo);
  if now() < v_ventana then
    raise exception using
      errcode = '22023',
      message = format('El mes %s no se puede cerrar antes del %s',
                       to_char(p_periodo, 'YYYY-MM'),
                       to_char(v_ventana at time zone 'America/Lima', 'DD/MM/YYYY')),
      hint    = 'Del 1 al 10 hay ventana de ajuste: el mes todavia puede recibir correcciones.';
  end if;

  -- 2ter) EL CERROJO DEL PERIODO. Se toma ANTES de leer `periodos_cerrados` y de
  --    escribir nada, y lo comparte `private.registrar_ajuste_si_mes_cerrado`.
  --    Sin el hay una carrera que PIERDE DINERO EN SILENCIO: una anulacion que
  --    arranca mientras el cierre esta a medias ve el mes todavia ABIERTO —el
  --    sello aun no ha hecho commit—, decide que no hay deuda que registrar, y
  --    la foto que se esta sellando ya habia contado ese cierre. Resultado: un
  --    cierre anulado queda pagado para siempre y sin una linea que lo explique.
  --    Antes era una carrera teorica (alguien tenia que decidir cerrar); con el
  --    ciclo automatico hay una cita fija, mensual y a hora conocida, justo
  --    cuando gerencia esta mirando esos numeros. Mismo patron que usa
  --    `crm.publicar_metas_vendedores`.
  -- CANDADO GLOBAL primero (20260815235500): serializa este sellado con
  -- CUALQUIER publicacion de metas en vuelo — tambien la de OTRO mes. El
  -- trigger del candado toma el mismo global antes de mirar; sin esto,
  -- publicar P durante el sellado de M>P paria metas muertas bajo el suelo.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados')::bigint
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (p_periodo - date '2000-01-01')::integer
  );

  -- 14/10/2026 (plazo de carga por mes, revisión Codex P1): la ventana se vuelve a mirar CON los dos candados. Gerencia
  -- amplía el plazo (crm.fijar_plazo_carga_mes) teniendo estos mismos candados: si este sello leyó el plazo de antes y
  -- esperó, aquí ve el ya confirmado. Sin esto, el mes se sellaba antes del último día que decidió Gerencia.
  v_ventana := private.cierre_mes_ventana_desde(p_periodo);
  if now() < v_ventana then
    raise exception using
      errcode = '22023',
      message = format('El mes %s no se puede cerrar antes del %s',
                       to_char(p_periodo, 'YYYY-MM'),
                       to_char(v_ventana at time zone 'America/Lima', 'DD/MM/YYYY')),
      hint    = 'Gerencia amplió el plazo de carga de ese mes mientras se cerraba: se cerrará cuando venza.';
  end if;

  lock table crm.equipo in share mode;

  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = p_periodo) then
    raise exception using
      errcode = 'P0409',
      message = 'Ese mes ya estaba cerrado',
      hint    = 'Un mes cerrado no se reescribe: lo que haya que corregir se descuenta en el mes vivo.';
  end if;

  -- 2quater) NUNCA POR DETRAS DE UN MES YA SELLADO. La regla de «sin huecos»
  --    del paso 3 protege el orden dado un conjunto de meses FIJO, y el conjunto
  --    no es fijo: `crm.publicar_metas_vendedores` acepta cualquier mes, asi que
  --    unas metas publicadas hacia atras pueden fabricar un «mes pendiente»
  --    anterior a uno que ya se pago. Sellarlo despues reescribiria la historia
  --    por el unico hueco que quedaba, y `private.saldar_ajustes` le cobraria a
  --    ese mes viejo deudas que tocaban al mes vivo.
  --    En el camino normal esto es un no-op: el ciclo siempre va de viejo a
  --    nuevo. Cuesta una consulta y cierra la ultima puerta.
  select max(pc.periodo) into v_ultimo_sellado from crm.periodos_cerrados pc;
  if v_ultimo_sellado is not null and p_periodo < v_ultimo_sellado then
    raise exception using
      errcode = '22023',
      message = format('No se sella %s: %s ya esta cerrado y es posterior',
                       to_char(p_periodo, 'YYYY-MM'), to_char(v_ultimo_sellado, 'YYYY-MM')),
      hint    = 'Los meses se sellan hacia adelante. Un mes que aparece por detras de lo ya pagado se corrige en el mes vivo, no sellandolo.';
  end if;

  -- 3) Sin huecos: no se cierra un mes si queda alguno anterior CON DATOS
  --    abierto. «Con datos» = tiene metas publicadas; un mes sin metas nunca
  --    tuvo nada que pagar y no bloquea la secuencia.
  v_pendiente := private.cierre_mes_pendiente(p_periodo);
  if v_pendiente is not null then
    raise exception using
      errcode = '22023',
      message = format('Falta cerrar %s antes que %s', v_pendiente, p_periodo),
      hint    = 'Los meses se cierran en orden: si no, el que se salta queda abierto para siempre.';
  end if;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
  v_factor := private.peso_referido_conversion(p_periodo);

  select mp.id, mp.revision into v_periodo_id, v_revision
  from crm.meta_periodos mp
  where mp.periodo = p_periodo
  order by mp.revision desc
  limit 1;
  -- Un mes sin metas publicadas se puede cerrar igual: se sella lo que hubo
  -- (conversion sin objetivo). Cerrar es fijar la historia, no premiarla.
  v_revision := coalesce(v_revision, 0);

  -- 4) La cobertura, con el MISMO criterio que la pantalla. Se recalcula aqui en
  --    vez de leerse de `conversion_mensual_fn` porque esa funcion recorta por
  --    `auth.uid()` y el cierre necesita la foto completa.
  select min(la.asignado_en) into v_suelo
  from crm.lead_asignaciones la
  where not la.aproximado;

  if v_suelo is null then
    v_medible := false;
    v_motivo := 'sin_ledger';
  elsif v_ini < v_suelo then
    v_medible := false;
    v_motivo := case
      when p_periodo < date_trunc('month', v_suelo at time zone 'America/Lima')::date
        then 'anterior_al_ledger'
      else 'mes_parcial'
    end;
  else
    v_medible := true;
    v_motivo := null;
  end if;
  v_cobertura := jsonb_build_object(
    'modelo_conversion', 'llegadas_v2',
    'medible', v_medible,
    'suelo_historico', v_suelo,
    'motivo_no_medible', v_motivo
  );

  with conv as materialized (
    select cm.*
    from private.conversion_mensual_por_vendedor(
      v_ini, v_fin, true, '{}'::uuid[], v_factor
    ) cm
  ), prod as materialized (
    select r.*
    from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
  ), car as materialized (
    select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
  ), roster as materialized (
    select distinct mv.vendedor_id
    from crm.metas_vendedor mv
    where mv.meta_periodo_id = v_periodo_id
  ), personas as (
    select c.analista_id as persona_id from conv c where c.analista_id is not null
    union
    select p.vendedor_id from prod p where p.vendedor_id is not null
    union
    select c.vendedor_id from car c where c.vendedor_id is not null
  ), elegibles as (
    select r.vendedor_id as persona_id from roster r
    union
    select p.persona_id
    from personas p
    join crm.equipo e
      on e.perfil_id = p.persona_id and e.rol_crm = 'vendedor'
    join crm.equipo s
      on s.perfil_id = e.supervisor_id and s.rol_crm = 'supervisor'
  ), fuera as (
    select
      p.persona_id,
      coalesce(nullif(btrim(pf.nombre_completo), ''),
               '(sin nombre · ' || left(p.persona_id::text, 8) || ')') as nombre,
      coalesce(e.rol_crm, 'fuera_equipo') as rol_crm,
      case
        when e.rol_crm = 'vendedor' then 'analista_sin_supervisor'
        when e.rol_crm = 'supervisor' then 'supervisor'
        when e.rol_crm = 'gerencia' then 'gerencia'
        else 'fuera_estructura'
      end as motivo
    from personas p
    left join crm.equipo e on e.perfil_id = p.persona_id
    left join public.perfiles pf on pf.id = p.persona_id
    where not exists (
      select 1 from elegibles ok where ok.persona_id = p.persona_id
    )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'persona_id', f.persona_id,
    'nombre', f.nombre,
    'rol_crm', f.rol_crm,
    'motivo', f.motivo,
    'conversion', case when cv.analista_id is null then null else jsonb_build_object(
      'divisor', coalesce(cv.divisor, 0),
      'divisor_aproximado', coalesce(cv.divisor_aproximado, 0),
      'divisor_por_motivo', coalesce(cv.divisor_por_motivo, '{}'::jsonb),
      'cierres_no_referidos', coalesce(cv.cierres_no_referidos, 0),
      'cierres_referidos', coalesce(cv.cierres_referidos, 0),
      'cierres_de_arrastre', coalesce(cv.cierres_de_arrastre, 0),
      'referidos_recibidos', coalesce(cv.referidos_recibidos, 0),
      'numerador', coalesce(cv.numerador, 0)
    ) end,
    'detalles', det.detalles,
    'cartera', jsonb_build_object(
      'conversiones_clientes', coalesce(car.conversiones_clientes, 0),
      'conversiones_renovacion', coalesce(car.conversiones_renovacion, 0),
      'conversiones_upgrade', coalesce(car.conversiones_upgrade, 0),
      'operaciones_renovacion', coalesce(car.operaciones_renovacion, 0),
      'operaciones_upgrade', coalesce(car.operaciones_upgrade, 0),
      'capital_renovado_pen', coalesce(car.capital_renovado_pen, 0),
      'capital_renovado_usd', coalesce(car.capital_renovado_usd, 0),
      'capital_adicional_pen', coalesce(car.capital_adicional_pen, 0),
      'capital_adicional_usd', coalesce(car.capital_adicional_usd, 0),
      'renovaciones_sin_desglose', coalesce(car.renovaciones_sin_desglose, 0)
    )
  ) order by f.nombre, f.persona_id), '[]'::jsonb)
    into v_fuera_ranking
  from fuera f
  left join conv cv on cv.analista_id = f.persona_id
  left join car on car.vendedor_id = f.persona_id
  left join lateral (
    select jsonb_agg(jsonb_build_object(
      'categoria', d.categoria,
      'moneda', d.moneda,
      'capital_objetivo', 0,
      'capital_real', coalesce(pr.capital_real, 0),
      'capital_cumplimiento_pct', null,
      'contratos_objetivo', 0,
      'contratos_real', coalesce(pr.contratos_real, 0),
      'contratos_cumplimiento_pct', null,
      'capital_ajuste', 0,
      'contratos_ajuste', 0
    ) order by array_position(
      array['nuevo','renovacion','upgrade'], d.categoria
    ), d.moneda) as detalles
    from (values
      ('nuevo'::text, 'PEN'::text), ('nuevo', 'USD'),
      ('renovacion', 'PEN'), ('renovacion', 'USD'),
      ('upgrade', 'PEN'), ('upgrade', 'USD')
    ) d(categoria, moneda)
    left join prod pr on pr.vendedor_id = f.persona_id
      and pr.categoria = d.categoria and pr.moneda = d.moneda
  ) det on true;

  v_cobertura := v_cobertura || jsonb_build_object(
    'fuera_ranking', v_fuera_ranking
  );

  -- Sin analista forma parte del total de empresa, no del ranking de personas.
  -- Se congela junto a la foto; una asignación posterior no reescribe el cierre.
  v_cobertura := v_cobertura || coalesce((
    select jsonb_build_object('conversion_sin_analista', to_jsonb(cm) - 'analista_id')
    from private.conversion_mensual_por_vendedor(v_ini, v_fin, true, '{}'::uuid[], v_factor) cm
    where cm.analista_id is null
  ), '{}'::jsonb);

  -- Tope de referidos (07/10/2026): el aporte EXACTO de los referidos por analista queda en la foto. El porcentaje de cada fila está
  -- redondeado y es NULL para quien solo recibe referidos (divisor 0); el total de «aporta» se sirve de aquí, nunca se reconstruye.
  if private.tope_referidos_conversion(p_periodo) is not null then
    v_cobertura := v_cobertura || jsonb_build_object('referidos_aporte', coalesce((
      select jsonb_object_agg(coalesce(r.analista_id::text, 'sin_analista'), r.aporte)
      from private.referidos_aporte_por_analista(v_ini, v_fin, p_periodo, true, '{}'::uuid[], v_factor) r
    ), '{}'::jsonb));
  end if;

  -- El peso de la RENOVACION se guarda CON la foto desde el 23/09/2026. Antes
  -- solo se guardaba el del referido, y el de renovacion se RECONSTRUIA a
  -- partir de el al leer: mientras los dos valieron lo mismo no se noto, pero
  -- en cuanto se separan (migracion 20260923155859) un mes sellado contaria la
  -- renovacion con un peso que no es el que se uso. Y eso, una vez sellado, ya
  -- no se puede recuperar: la foto es la unica memoria de con que se calculo.
  -- Tope de referidos (07/10/2026): la foto guarda el tope con el que se calculó el mes, igual que guarda los pesos.
  insert into crm.periodos_cerrados (
    periodo, cerrado_por, automatico, ponderacion_referido, ponderacion_renovacion,
    tope_referidos_pct, meta_revision, cobertura
  ) values (
    p_periodo,
    case when v_automatico then null else v_uid end,
    v_automatico, v_factor, private.peso_renovacion_conversion(p_periodo),
    private.tope_referidos_conversion(p_periodo),
    v_revision, v_cobertura
  );

  -- 5) La foto. El conjunto de personas es el ROSTER DEL MES (quien tenia meta),
  --    en union con quien PRODUJO aunque no tuviera meta: los dos importan para
  --    una foto de pago, y quien produjo sin meta tiene que quedar registrado
  --    con su nombre en vez de disolverse en un agregado anonimo — que es lo que
  --    hace la pantalla viva, y esta bien alli (privacidad) y mal aqui (pago).
  with conv as (
    select cm.*
    from private.conversion_mensual_por_vendedor(v_ini, v_fin, true, '{}'::uuid[], v_factor) cm
  ), prod as (
    select r.vendedor_id, r.categoria, r.moneda, r.contratos_real, r.capital_real
    from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
  ), car as (
    select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
  ), roster as (
    -- `distinct on`: una fila por persona, pase lo que pase. La foto tiene la
    -- clave (periodo, vendedor), asi que dos metas del mismo vendedor en el
    -- mismo periodo harian reventar el cierre entero con un duplicado — un mes
    -- que no se puede cerrar por una fila repetida es peor que el duplicado.
    -- (Lo cazo el oraculo ejecutando, no leyendo.)
    select distinct on (mv.vendedor_id)
      mv.vendedor_id, mv.supervisor_id, mv.conversion_objetivo, mv.id as meta_vendedor_id
    from crm.metas_vendedor mv
    where mv.meta_periodo_id = v_periodo_id
    order by mv.vendedor_id, mv.id
  ), personas as (
    select vendedor_id from roster
    union
    select analista_id from conv
    union
    select vendedor_id from prod where vendedor_id is not null
    union
    select vendedor_id from car where vendedor_id is not null
  ), foto as (
    select
      pe.vendedor_id,
      r.meta_vendedor_id,
      coalesce(r.supervisor_id, supervisor_actual.perfil_id) as supervisor_id,
      coalesce(r.conversion_objetivo, 0::numeric) as conversion_objetivo
    from personas pe
    left join roster r on r.vendedor_id = pe.vendedor_id
    left join crm.equipo vendedor_actual
      on vendedor_actual.perfil_id = pe.vendedor_id
    left join crm.equipo supervisor_actual
      on supervisor_actual.perfil_id = vendedor_actual.supervisor_id
     and supervisor_actual.rol_crm = 'supervisor'
    where r.meta_vendedor_id is not null
       or (
         vendedor_actual.rol_crm = 'vendedor'
         and supervisor_actual.perfil_id is not null
       )
  )
  insert into crm.cierre_mes_vendedor (
    periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre,
    divisor, divisor_aproximado, divisor_por_motivo,
    cierres_no_referidos, cierres_referidos, cierres_de_arrastre,
    numerador, conversion_pct, estado,
    referidos_recibidos, referidos_dados_de_alta, referidos_aporta_pct, procedencia,
    ajuste_numerador, ajuste_pen, ajuste_usd,
    conversion_objetivo, detalles, cartera
  )
  select
    p_periodo,
    pe.vendedor_id,
    coalesce(nullif(btrim(pf.nombre_completo), ''),
             '(sin nombre · ' || left(pe.vendedor_id::text, 8) || ')'),
    pe.supervisor_id,
    coalesce(nullif(btrim(sup.nombre_completo), ''), '(sin ficha)'),
    coalesce(c.divisor, 0),
    coalesce(c.divisor_aproximado, 0),
    coalesce(c.divisor_por_motivo, '{}'::jsonb),
    coalesce(c.cierres_no_referidos, 0),
    coalesce(c.cierres_referidos, 0),
    coalesce(c.cierres_de_arrastre, 0),
    -- NETO: lo bruto menos lo que este mes absorbio de deudas viejas. Es lo que
    -- se paga, asi que es lo que se sella.
    coalesce(c.numerador, 0::numeric) - sal.aplicado_numerador,
    case when coalesce(c.divisor, 0) > 0
      then round(100.0 * (coalesce(c.numerador, 0::numeric) - sal.aplicado_numerador)
                 / coalesce(c.divisor, 0), 2) end,
    case
      when coalesce(c.divisor, 0) > 0 then 'medible'
      when coalesce(c.referidos_recibidos, 0) > 0 then 'solo_referidos'
      when coalesce(c.cierres_no_referidos, 0) + coalesce(c.cierres_referidos, 0) > 0 then 'solo_arrastre'
      else 'sin_actividad'
    end,
    coalesce(c.referidos_recibidos, 0),
    coalesce(alta.dados_de_alta, 0),
    c.referidos_aporta_pct,
    coalesce(c.procedencia, '[]'::jsonb),
    sal.aplicado_numerador,
    sal.aplicado_pen,
    sal.aplicado_usd,
    pe.conversion_objetivo,
    coalesce(det.detalles, '[]'::jsonb),
    jsonb_build_object(
      'conversiones_clientes', coalesce(car.conversiones_clientes, 0),
      'conversiones_renovacion', coalesce(car.conversiones_renovacion, 0),
      'conversiones_upgrade', coalesce(car.conversiones_upgrade, 0),
      'operaciones_renovacion', coalesce(car.operaciones_renovacion, 0),
      'operaciones_upgrade', coalesce(car.operaciones_upgrade, 0),
      'capital_renovado_pen', coalesce(car.capital_renovado_pen, 0),
      'capital_renovado_usd', coalesce(car.capital_renovado_usd, 0),
      'capital_adicional_pen', coalesce(car.capital_adicional_pen, 0),
      'capital_adicional_usd', coalesce(car.capital_adicional_usd, 0),
      'renovaciones_sin_desglose', coalesce(car.renovaciones_sin_desglose, 0)
    )
  from foto pe
  left join conv c on c.analista_id = pe.vendedor_id
  left join car on car.vendedor_id = pe.vendedor_id
  left join public.perfiles pf on pf.id = pe.vendedor_id
  left join public.perfiles sup on sup.id = pe.supervisor_id
  left join lateral (
    -- El capital bruto del mes por moneda, que es el techo de lo que este mes
    -- puede absorber. PEN y USD por separado: una deuda en soles no se paga con
    -- produccion en dolares.
    -- ⚠️ Va ANTES del `saldar_ajustes` que lo consume: un LATERAL solo puede
    -- mirar a su izquierda.
    select
      coalesce(sum(pr.capital_real) filter (where pr.moneda = 'PEN'), 0) as pen,
      coalesce(sum(pr.capital_real) filter (where pr.moneda = 'USD'), 0) as usd
    from prod pr
    where pr.vendedor_id = pe.vendedor_id
  ) cap on true
  -- Lo que este mes puede absorber de las deudas viejas del vendedor. Es
  -- VOLATIL a proposito: ademas de devolver lo aplicado, DESCUENTA lo saldado y
  -- deja el resto arrastrandose. Se llama una vez por persona, que es la unica
  -- forma en que la cuenta cuadra.
  left join lateral private.saldar_ajustes(
    pe.vendedor_id,
    coalesce(c.numerador, 0::numeric),
    coalesce(cap.pen, 0::numeric),
    coalesce(cap.usd, 0::numeric)
  ) sal on true
  left join lateral (
    select count(*)::int as dados_de_alta
    from crm.leads l
    where l.origen = 'referido'
      and l.creado_en >= v_ini and l.creado_en < v_fin
      and l.creado_por = pe.vendedor_id
  ) alta on true
  left join lateral (
    -- ⚠️ `capital_real` y `contratos_real` van NETOS del descuento que este mes
    -- absorbio, casilla a casilla. Es la correccion de un fallo de DINERO: la
    -- primera version marcaba la deuda como saldada y NO la restaba de ninguna
    -- cifra, asi que el asesor cobraba igual y la deuda desaparecia — miles de
    -- soles perdonados en silencio, sin una sola linea que lo dijera.
    select jsonb_agg(jsonb_build_object(
      'categoria', dimensiones.categoria,
      'moneda', dimensiones.moneda,
      'capital_objetivo', coalesce(d.capital_objetivo, 0),
      'capital_real', greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0),
      'capital_cumplimiento_pct', case when coalesce(d.capital_objetivo, 0) > 0
        then round(100.0 * greatest(coalesce(pr.capital_real, 0) - coalesce(aj.capital, 0), 0)
                   / d.capital_objetivo, 2) end,
      'contratos_objetivo', coalesce(d.contratos_objetivo, 0),
      'contratos_real', greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0),
      'contratos_cumplimiento_pct', case when coalesce(d.contratos_objetivo, 0) > 0
        then round(100.0 * greatest(coalesce(pr.contratos_real, 0) - coalesce(aj.contratos, 0), 0)
                   / d.contratos_objetivo, 2) end,
      'capital_ajuste', coalesce(aj.capital, 0),
      'contratos_ajuste', coalesce(aj.contratos, 0)
    ) order by array_position(
      array['nuevo','renovacion','upgrade'], dimensiones.categoria
    ), dimensiones.moneda) as detalles
    from (values
      ('nuevo'::text, 'PEN'::text), ('nuevo', 'USD'),
      ('renovacion', 'PEN'), ('renovacion', 'USD'),
      ('upgrade', 'PEN'), ('upgrade', 'USD')
    ) dimensiones(categoria, moneda)
    left join crm.metas_vendedor_detalle d
      on d.meta_vendedor_id = pe.meta_vendedor_id
     and d.categoria = dimensiones.categoria
     and d.moneda = dimensiones.moneda
    left join prod pr on pr.vendedor_id = pe.vendedor_id
      and pr.categoria = dimensiones.categoria
     and pr.moneda = dimensiones.moneda
    left join lateral (
      select coalesce((e->>'capital')::numeric, 0) as capital,
             coalesce((e->>'contratos')::int, 0) as contratos
      from jsonb_array_elements(sal.aplicado_detalle) e
      where e->>'categoria' = dimensiones.categoria
        and e->>'moneda' = dimensiones.moneda
      limit 1
    ) aj on true
  ) det on true;

  get diagnostics v_vendedores = row_count;

  -- El rastro del cierre NO se escribe en `crm.actividades`: esa tabla cuelga de
  -- un lead y un cierre de mes no es de ningun lead. El registro lo deja el
  -- trigger de auditoria sobre `crm.periodos_cerrados`, con quien, cuando y que.

  return jsonb_build_object(
    'ok', true,
    'periodo', to_char(p_periodo, 'YYYY-MM'),
    'automatico', v_automatico,
    'vendedores', v_vendedores,
    'meta_revision', v_revision,
    'cobertura', v_cobertura
  );
end;
$function$;

-- Re-sellado de la huella de crm.cerrar_periodo en el censo analítico (plantilla de 20261013145852): solo cambian la huella de
-- su declaración y el sello de la lista; razón, clase y tope no se tocan. Sin declaración (banco de solo esquema), nada.
do $resello$
declare v_huella text; v_n integer;
begin
  select md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_catalog.pg_get_functiondef(p.oid))), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))
    into v_huella from pg_catalog.pg_proc p where p.oid = 'crm.cerrar_periodo(date)'::regprocedure;
  if v_huella is distinct from '4b89856af0ebc6c4e46f6ffef8be61af' then
    raise exception 'RESELLO plazo_carga_mes: la huella normalizada del cuerpo aplicado (%) no es la revisada (4b89856a…)', v_huella;
  end if;
  update private.analitica_leads_citas_exenciones
     set huella = v_huella
   where objeto = 'crm.cerrar_periodo(date)' and huella = '8073f806d602fd55532f1f9d4651b7d4';
  get diagnostics v_n = row_count;
  if v_n = 1 then
    update private.analitica_lc_sello
       set sello = private.huella_exenciones_analitica_lc(), sellado_en = pg_catalog.now()
     where id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then
      raise exception 'RESELLO plazo_carga_mes: se esperaba actualizar un sello del censo y fueron %', v_n;
    end if;
  elsif exists (select 1 from private.analitica_leads_citas_exenciones e where e.objeto = 'crm.cerrar_periodo(date)') then
    raise exception 'RESELLO plazo_carga_mes: la declaración de crm.cerrar_periodo no tenía la huella revisada';
  end if;
end
$resello$;

create function crm.fijar_plazo_carga_mes(p_periodo date, p_ultimo_dia date, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_mes_actual date := pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date;
  v_base timestamptz;
  v_motivo text;
begin
  -- Gate: solo Gerencia (rol CRM efectivo), nunca un parámetro.
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia decide el plazo de carga de un mes' using errcode = '42501';
  end if;

  if p_periodo is null or not pg_catalog.isfinite(p_periodo)
     or p_periodo <> pg_catalog.date_trunc('month', p_periodo::timestamp)::date then
    raise exception 'Elige un mes válido (el primer día del mes)' using errcode = '22023';
  end if;
  if p_periodo > v_mes_actual then
    raise exception 'No se fija el plazo de un mes que todavía no empieza' using errcode = '22023';
  end if;
  if p_ultimo_dia is null or not pg_catalog.isfinite(p_ultimo_dia) then
    raise exception 'Indica el último día en que se puede cargar' using errcode = '22023';
  end if;
  if p_ultimo_dia < v_hoy then
    raise exception using errcode = '22023',
      message = pg_catalog.format('El último día de carga no puede ser anterior a hoy (%s)',
                                  pg_catalog.to_char(v_hoy, 'DD/MM/YYYY'));
  end if;
  v_base := private.conversion_plazo_base(p_periodo);
  if ((p_ultimo_dia + 1)::timestamp at time zone 'America/Lima') < v_base then
    raise exception using errcode = '22023',
      message = pg_catalog.format('El plazo de %s %s no puede terminar antes del %s, su plazo de siempre',
        private.etiqueta_mes_es(p_periodo), pg_catalog.to_char(p_periodo, 'YYYY'),
        pg_catalog.to_char(((v_base at time zone 'America/Lima')::date - 1), 'DD/MM/YYYY'));
  end if;
  v_motivo := private.motivo_normalizado(p_motivo);
  if pg_catalog.char_length(v_motivo) not between 5 and 300 then
    raise exception 'El motivo debe tener entre 5 y 300 caracteres' using errcode = '22023';
  end if;

  return private.fijar_plazo_carga(p_periodo, p_ultimo_dia, v_motivo, v_uid);
end;
$function$;

create function crm.plazos_carga_mes_fn()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia ve y decide los plazos de carga' using errcode = '42501';
  end if;
  return private.plazos_carga_mes_lectura();
end;
$function$;

-- ── 9 · Permisos: tablas sin grants; núcleo solo postgres; puertas para authenticated (el gate va dentro) ──────────────
revoke all on table crm.reaperturas_mes from public, anon, authenticated, service_role;
revoke all on table crm.plazos_carga_mes from public, anon, authenticated, service_role;
revoke all on function private.conversion_plazo_base(date) from public, anon, authenticated, service_role;
revoke all on function private.trg_plazo_carga_append_only() from public, anon, authenticated, service_role;
revoke all on function private.trg_reaperturas_mes_llave() from public, anon, authenticated, service_role;
revoke all on function private.reapertura_autoriza(date, uuid) from public, anon, authenticated, service_role;
revoke all on function private.reapertura_impedimento(date) from public, anon, authenticated, service_role;
revoke all on function private.conversion_reevaluar_plazo(date) from public, anon, authenticated, service_role;
revoke all on function private.reabrir_mes(date, text, uuid) from public, anon, authenticated, service_role;
revoke all on function private.fijar_plazo_carga(date, date, text, uuid) from public, anon, authenticated, service_role;
revoke all on function private.plazos_carga_mes_lectura() from public, anon, authenticated, service_role;
revoke all on function crm.fijar_plazo_carga_mes(date, date, text) from public, anon, authenticated, service_role;
revoke all on function crm.plazos_carga_mes_fn() from public, anon, authenticated, service_role;
grant execute on function crm.fijar_plazo_carga_mes(date, date, text) to authenticated;
grant execute on function crm.plazos_carga_mes_fn() to authenticated;

-- ── 10 · Comentarios ────────────────────────────────────────────────────────────────────────────────────────────────────
comment on table crm.reaperturas_mes is
  'Reaperturas de un mes sellado decididas por Gerencia (crm.fijar_plazo_carga_mes → private.reabrir_mes). Una fila por '
  'reapertura con el respaldo completo de lo que se retiró o cambió. Append-only, sin grants ni políticas. La fila ES la '
  'autorización de los candados del cierre (private.reapertura_autoriza), solo para su mes y su transacción. Sin negocio_id: '
  'el cierre de mes del CRM no tiene inquilino (igual que crm.periodos_cerrados).';
comment on column crm.reaperturas_mes.id is 'Identificador de la reapertura.';
comment on column crm.reaperturas_mes.periodo is 'Mes reabierto (primer día del mes).';
comment on column crm.reaperturas_mes.motivo is 'Motivo escrito por Gerencia (5 a 300 caracteres, sin blancos en los extremos).';
comment on column crm.reaperturas_mes.decidido_por is 'Perfil de Gerencia que reabrió el mes (auth.uid() de la sesión, nunca un parámetro).';
comment on column crm.reaperturas_mes.reabierto_en is
  'Cuándo se reabrió: el instante de inicio de la transacción que reabrió (lo fija el trigger; parte de la llave).';
comment on column crm.reaperturas_mes.transaccion is
  'Transacción que reabrió el mes (la fija el trigger, no quien inserta): con reabierto_en, la llave de '
  'private.reapertura_autoriza. La pareja (transaccion, reabierto_en) es única: una reapertura por transacción superior.';
comment on column crm.reaperturas_mes.respaldo is
  'Estado ANTES de reabrir: sello, foto[], acreditaciones[] del mes, rastros_tardios[] retirados y cierres_externos[] '
  'devueltos (estos SIN documento ni nombre del cliente). Queda también en public.audit_log.';
comment on column crm.reaperturas_mes.resumen is
  'Resumen de la reapertura: foto retirada, acreditaciones respaldadas/liberadas/incluidas, rastros retirados y ventas devueltas.';

comment on table crm.plazos_carga_mes is
  'Decisiones de Gerencia sobre el plazo de carga de un mes (crm.fijar_plazo_carga_mes). Vale la última por mes '
  '(private.conversion_plazo_hasta); sin decisión, la base (día 11 del mes siguiente, 00:00 de Lima). Append-only, sin '
  'grants ni políticas. Sin negocio_id: el cierre de mes del CRM no tiene inquilino (igual que crm.periodos_cerrados).';
comment on column crm.plazos_carga_mes.id is 'Identificador de la decisión.';
comment on column crm.plazos_carga_mes.periodo is 'Mes al que se fija el plazo (primer día del mes).';
comment on column crm.plazos_carga_mes.ultimo_dia is 'Último día incluido en el plazo (fecha de Lima).';
comment on column crm.plazos_carga_mes.plazo_hasta is
  'Fin del plazo, extremo EXCLUIDO: 00:00 de Lima del día siguiente a ultimo_dia. Nunca antes de la base del mes.';
comment on column crm.plazos_carga_mes.motivo is 'Motivo escrito por Gerencia (5 a 300 caracteres, sin blancos en los extremos).';
comment on column crm.plazos_carga_mes.decidido_por is 'Perfil de Gerencia que decidió (auth.uid() de la sesión, nunca un parámetro).';
comment on column crm.plazos_carga_mes.decidido_en is 'Cuándo se decidió; ordena las decisiones (vale la última).';
comment on column crm.plazos_carga_mes.reapertura_id is 'Reapertura que acompañó a la decisión, si el mes estaba sellado (mismo mes).';

comment on constraint conversion_acreditaciones_plazo_minimo_check on crm.conversion_acreditaciones is
  'El plazo guardado nunca es anterior a la base del mes. Desde el 14/10/2026 el plazo es variable (decisión de Gerencia), '
  'así que ya no se exige igualdad con el plazo vigente: la fila guarda el plazo con el que se decidió.';

comment on function private.conversion_plazo_base(date) is
  'Plazo base de carga de un mes: 00:00 de Lima del día 11 del mes siguiente (el día 10 entero es de ajuste). Inmutable y sin '
  'reloj. Valida el periodo (22023).';
comment on function private.conversion_plazo_hasta(date) is
  'Plazo de carga VIGENTE de un mes (extremo excluido): la última decisión de Gerencia en crm.plazos_carga_mes o, sin decisión, '
  'private.conversion_plazo_base. Estable desde el 14/10/2026. Lo usan la acreditación de conversiones y la ventana del sello.';
comment on function private.conversion_decidir_plazo(date, timestamptz, timestamptz, timestamptz) is
  'Decide el estado de una acreditación de conversión con el plazo VIGENTE de su mes (private.conversion_plazo_hasta). '
  'Estable desde el 14/10/2026 (antes inmutable): el plazo lo puede ampliar Gerencia.';
comment on function private.cierre_mes_ventana_desde(date) is
  'Instante en que se abre la ventana de cierre de un mes = su plazo de carga vigente (private.conversion_plazo_hasta): la '
  'última decisión de Gerencia o, sin decisión, el día 11 del mes siguiente a las 00:00 de Lima (el día 10 entero es ventana '
  'de ajuste). Estable desde el 14/10/2026; sin reloj: el que la llama pone el instante.';
comment on function private.reapertura_autoriza(date, uuid) is
  'Autorización de los candados del cierre: true solo si en ESTA transacción (su id y su instante) se registró la '
  'reapertura de ESE mes en crm.reaperturas_mes (private.reabrir_mes) y, si se pasa un cierre en cooperativa, si esa '
  'reapertura lo respaldó. Sin GUC; no se filtra a otro mes, a otra venta ni a otra transacción. Alcance: la transacción '
  'superior entera, incluidas sus subtransacciones (una sola llamada a crm.fijar_plazo_carga_mes).';
comment on function private.trg_reaperturas_mes_llave() is
  'Fija la llave de cada reapertura al insertarla: la transacción actual y su instante de inicio (nadie la elige).';
comment on function private.fijar_plazo_carga(date, date, text, uuid) is
  'Núcleo de crm.fijar_plazo_carga_mes: candados del cierre, reapertura si el mes está sellado (P0409 si no se puede), '
  'negativa para un mes sin metas publicadas o sin sellar detrás del último sellado (22023), decisión y reevaluación. Datos '
  'ya validados.';
comment on function private.plazos_carga_mes_lectura() is
  'Núcleo de crm.plazos_carga_mes_fn: por mes pendiente de sellar, mes anterior y mes en curso, su plazo base y vigente, '
  'la última decisión, si está sellado, si se puede reabrir (private.reapertura_impedimento) y la última reapertura.';
comment on function private.trg_cierre_mes_append_only() is
  'Veta UPDATE y DELETE sobre las dos tablas del cierre de mes. Única excepción (14/10/2026): el DELETE de la reapertura de ese '
  'mes en su transacción (private.reapertura_autoriza). El nombre lleva 00 en el trigger para que corra ANTES que el de auditoria.';
comment on function private.f4_fuente_inmutable() is
  'Candado del historial de inversiones y de las fechas/clase/comprobante de los cierres externos. Excepciones: eliminación '
  'auditada (eventos) y, desde el 14/10/2026, la reapertura de un mes (borra el rastro tardío de ese mes y devuelve la '
  'imputación de su venta en cooperativa a la fecha comercial, en la transacción de la reapertura y sin ningún otro cambio '
  'en la fila).';
comment on function private.trg_cierres_externos_inmutables() is
  'Candado de los cierres externos: no se borran (salvo la eliminación auditada) y solo se corrigen con la válvula '
  'crm.op_privilegiada o, desde el 14/10/2026, en la transacción que reabre su mes: solo la imputación de una venta '
  'respaldada por esa reapertura, solo a su fecha comercial y sin tocar nada más de la fila.';
comment on function private.trg_plazo_carga_append_only() is
  'Veta UPDATE, DELETE y TRUNCATE de crm.plazos_carga_mes y crm.reaperturas_mes: las decisiones y las reaperturas son historia.';
comment on function private.reapertura_impedimento(date) is
  'Por qué NO se puede reabrir un mes (NULL = se puede): sellado, con metas, último sellado, mes anterior al mes en curso, con foto, sin '
  'deudas nacidas ni absorbidas, registros tardíos coherentes (cooperativa, analista con meta) y sin cooperativa imputada '
  'fuera sin rastro. Una sola regla para private.reabrir_mes y crm.plazos_carga_mes_fn.';
comment on function private.conversion_reevaluar_plazo(date) is
  'Reevalúa las acreditaciones de un mes en fuera_de_plazo o mes_sellado con su plazo vigente (misma decisión, exclusión de '
  'fuente e identidad que el escritor). Devuelve {reevaluadas, conflictos}: las que chocan con otra captación acreditada de la '
  'misma identidad se dejan como están.';
comment on function private.reabrir_mes(date, text, uuid) is
  'Reabre un mes sellado (las operaciones de scripts/reexpresion-septiembre-2026/01-reabrir.sql, en el mismo orden): respaldo '
  'en crm.reaperturas_mes, retira rastros tardíos, foto y sello, devuelve las ventas en cooperativa registradas tarde a su mes '
  'y libera las marcas de sello. P0409 con el motivo si no se puede (private.reapertura_impedimento). Sin ALTER TABLE ni GUC.';
comment on function crm.fijar_plazo_carga_mes(date, date, text) is
  'Gerencia fija el último día de carga de un mes (plazo = 00:00 de Lima del día siguiente; nunca antes de la base, desde hoy, '
  'motivo de 5 a 300; solo meses con metas publicadas). Si el mes está sellado lo reabre (P0409 si no se puede). Reevalúa las '
  'acreditaciones del mes. 42501 si no es Gerencia; 22023 si los datos no valen. Valida, autoriza y delega en private.fijar_plazo_carga. DEFINER: las tablas '
  'no tienen grants; el actor sale de auth.uid().';
comment on function crm.plazos_carga_mes_fn() is
  'Lectura de Gerencia (42501 al resto): por mes pendiente de sellar, mes anterior y mes en curso, su plazo base y vigente, la '
  'última decisión, si está sellado, si se puede reabrir (la misma regla que la reapertura) y la última reapertura. Autoriza '
  'y delega en private.plazos_carga_mes_lectura.';

-- ── 11 · Postflight ────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_periodo date;
  v_estado text;
  v_mensaje text;
  v_id uuid;
begin
  -- Tablas: RLS sin políticas, de postgres, sin grants para nadie más, con sus candados y su auditoría.
  if (select pg_catalog.count(*) from pg_catalog.pg_class c
       where c.oid in ('crm.reaperturas_mes'::regclass, 'crm.plazos_carga_mes'::regclass)
         and c.relrowsecurity and c.relowner = 'postgres'::regrole) <> 2
     or exists (select 1 from pg_catalog.pg_policy p
                 where p.polrelid in ('crm.reaperturas_mes'::regclass, 'crm.plazos_carga_mes'::regclass))
     or exists (select 1 from pg_catalog.pg_class c
                 cross join lateral pg_catalog.aclexplode(coalesce(c.relacl, pg_catalog.acldefault('r', c.relowner))) a
                 where c.oid in ('crm.reaperturas_mes'::regclass, 'crm.plazos_carga_mes'::regclass)
                   and a.grantee <> 'postgres'::regrole) then
    raise exception 'POSTFLIGHT plazo_carga_mes: tablas nuevas sin RLS, con políticas o con grants';
  end if;
  if (select pg_catalog.count(*) from pg_catalog.pg_trigger t
       where t.tgrelid in ('crm.reaperturas_mes'::regclass, 'crm.plazos_carga_mes'::regclass)
         and not t.tgisinternal and t.tgenabled = 'O') <> 7
     or exists (select 1 from private.tablas_sin_rastro() s where s.tabla in ('crm.reaperturas_mes', 'crm.plazos_carga_mes')) then
    raise exception 'POSTFLIGHT plazo_carga_mes: faltan los candados o la auditoría de las tablas nuevas';
  end if;
  -- Funciones: dueño, permisos exactos, DEFINER solo en candados y puertas, volatilidad y search_path vacío.
  if exists (
    select 1
      from (values
        ('private.conversion_plazo_base(date)', '{postgres=X/postgres}', false, 'i'),
        ('private.conversion_plazo_hasta(date)', '{postgres=X/postgres}', false, 's'),
        ('private.conversion_decidir_plazo(date,timestamptz,timestamptz,timestamptz)', '{postgres=X/postgres}', false, 's'),
        ('private.cierre_mes_ventana_desde(date)', '{postgres=X/postgres}', false, 's'),
        ('private.reapertura_autoriza(date,uuid)', '{postgres=X/postgres}', false, 's'),
        ('private.trg_plazo_carga_append_only()', '{postgres=X/postgres}', false, 'v'),
        ('private.trg_reaperturas_mes_llave()', '{postgres=X/postgres}', false, 'v'),
        ('private.fijar_plazo_carga(date,date,text,uuid)', '{postgres=X/postgres}', false, 'v'),
        ('private.plazos_carga_mes_lectura()', '{postgres=X/postgres}', false, 's'),
        ('private.reapertura_impedimento(date)', '{postgres=X/postgres}', false, 's'),
        ('private.conversion_reevaluar_plazo(date)', '{postgres=X/postgres}', false, 'v'),
        ('private.reabrir_mes(date,text,uuid)', '{postgres=X/postgres}', false, 'v'),
        ('private.trg_cierre_mes_append_only()', null, true, 'v'),
        ('private.f4_fuente_inmutable()', '{postgres=X/postgres}', true, 'v'),
        ('private.trg_cierres_externos_inmutables()', null, true, 'v'),
        ('crm.cerrar_periodo(date)', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}', true, 'v'),
        ('crm.fijar_plazo_carga_mes(date,date,text)', '{postgres=X/postgres,authenticated=X/postgres}', true, 'v'),
        ('crm.plazos_carga_mes_fn()', '{postgres=X/postgres,authenticated=X/postgres}', true, 's')
      ) e(firma, acl, definer, volatil)
      left join pg_catalog.pg_proc p on p.oid = to_regprocedure(e.firma)
     where p.oid is null
        or p.proowner <> 'postgres'::regrole
        or p.proacl::text is distinct from e.acl
        or p.prosecdef <> e.definer
        or p.provolatile::text <> e.volatil
        or p.proconfig is distinct from array['search_path=""']::text[]
        or pg_catalog.obj_description(p.oid, 'pg_proc') is null
  ) then
    raise exception 'POSTFLIGHT plazo_carga_mes: una función quedó con dueño, permisos, volatilidad, search_path o comentario inesperados';
  end if;
  -- El CHECK nuevo, y ninguno de igualdad.
  if (select pg_catalog.pg_get_constraintdef(c.oid) from pg_catalog.pg_constraint c
       where c.conrelid = 'crm.conversion_acreditaciones'::regclass
         and c.conname = 'conversion_acreditaciones_plazo_minimo_check')
       is distinct from 'CHECK ((plazo_hasta >= private.conversion_plazo_base(periodo_comercial)))'
     or exists (select 1 from pg_catalog.pg_constraint c
                 where c.conrelid = 'crm.conversion_acreditaciones'::regclass and c.contype = 'c'
                   and pg_catalog.pg_get_constraintdef(c.oid) ~ 'conversion_plazo_hasta') then
    raise exception 'POSTFLIGHT plazo_carga_mes: el CHECK de plazo de las acreditaciones no quedó como se esperaba';
  end if;
  -- Sin decisiones, el plazo y la ventana son la base de siempre (día 11 del mes siguiente, 00:00 de Lima).
  if exists (select 1
               from (select pg_catalog.generate_series(date '2025-12-01', date '2027-01-01', interval '1 month')::date as m) g
              where private.conversion_plazo_hasta(g.m) is distinct from private.conversion_plazo_base(g.m)
                 or private.cierre_mes_ventana_desde(g.m) is distinct from private.conversion_plazo_base(g.m)
                 or private.conversion_plazo_base(g.m)
                      is distinct from ((g.m::timestamp + interval '1 month 10 days') at time zone 'America/Lima')) then
    raise exception 'POSTFLIGHT plazo_carga_mes: sin decisiones, el plazo no es el de siempre';
  end if;
  -- La autorización no existe fuera de una reapertura.
  if private.reapertura_autoriza((select max(pc.periodo) from crm.periodos_cerrados pc)) is not false
     or private.reapertura_autoriza((select max(pc.periodo) from crm.periodos_cerrados pc),
                                    (select ce.id from crm.cierres_externos ce order by ce.id limit 1)) is not false then
    raise exception 'POSTFLIGHT plazo_carga_mes: hay autorización de reapertura sin reapertura';
  end if;
  -- «Puesto no es funciona»: intentos que DEBEN rebotar con el candado puesto (si alguno pasara, la migración entera se
  -- revierte con la excepción de abajo; nada queda escrito).
  select max(f.periodo) into v_periodo from crm.cierre_mes_vendedor f;
  if v_periodo is not null then
    begin
      delete from crm.cierre_mes_vendedor f where f.periodo = v_periodo;
      v_estado := 'paso';
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_mensaje = message_text;
    end;
    if v_estado is distinct from 'P0409' or v_mensaje is distinct from 'Un mes cerrado no se edita ni se borra' then
      raise exception 'POSTFLIGHT plazo_carga_mes: el candado de la foto no muerde (% %)', v_estado, v_mensaje;
    end if;
    raise notice 'POSTFLIGHT plazo_carga_mes: rebota la foto de % (candado puesto y mordiendo)', v_periodo;
  else
    raise notice 'POSTFLIGHT plazo_carga_mes: no hay foto sellada que intentar borrar';
  end if;
  select max(pc.periodo) into v_periodo from crm.periodos_cerrados pc;
  if v_periodo is not null then
    begin
      delete from crm.periodos_cerrados pc where pc.periodo = v_periodo;
      v_estado := 'paso';
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_mensaje = message_text;
    end;
    if v_estado is distinct from 'P0409' or v_mensaje is distinct from 'Un mes cerrado no se edita ni se borra' then
      raise exception 'POSTFLIGHT plazo_carga_mes: el candado del sello no muerde (% %)', v_estado, v_mensaje;
    end if;
    raise notice 'POSTFLIGHT plazo_carga_mes: rebota el sello de %', v_periodo;
  else
    raise notice 'POSTFLIGHT plazo_carga_mes: no hay sello que intentar borrar';
  end if;
  select ia.inversion_id into v_id from crm.inversion_ajustes_mes_cerrado ia order by ia.inversion_id limit 1;
  if v_id is not null then
    begin
      delete from crm.inversion_ajustes_mes_cerrado ia where ia.inversion_id = v_id;
      v_estado := 'paso';
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_mensaje = message_text;
    end;
    if v_estado is distinct from 'P0409' then
      raise exception 'POSTFLIGHT plazo_carga_mes: el candado del rastro tardío no muerde (% %)', v_estado, v_mensaje;
    end if;
    raise notice 'POSTFLIGHT plazo_carga_mes: rebota el rastro tardío';
  else
    raise notice 'POSTFLIGHT plazo_carga_mes: no hay rastro tardío que intentar borrar';
  end if;
  select ce.id into v_id from crm.cierres_externos ce order by ce.id limit 1;
  if v_id is not null then
    begin
      update crm.cierres_externos ce set fecha_imputacion = ce.fecha_comercial where ce.id = v_id;
      v_estado := 'paso';
    exception when others then
      get stacked diagnostics v_estado = returned_sqlstate, v_mensaje = message_text;
    end;
    if v_estado is distinct from 'P0409' then
      raise exception 'POSTFLIGHT plazo_carga_mes: el candado del cierre externo no muerde (% %)', v_estado, v_mensaje;
    end if;
    raise notice 'POSTFLIGHT plazo_carga_mes: rebota el cierre externo';
  else
    raise notice 'POSTFLIGHT plazo_carga_mes: no hay cierre externo que intentar editar';
  end if;
  -- Las puertas existen, compilan su primera rama y niegan sin sesión (la migración corre sin auth.uid()).
  begin
    perform crm.fijar_plazo_carga_mes(date '2026-09-01', date '2026-10-20', 'postflight sin sesión');
    v_estado := 'paso';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate;
  end;
  if v_estado is distinct from '42501' then
    raise exception 'POSTFLIGHT plazo_carga_mes: la puerta de escritura no niega sin sesión (%)', v_estado;
  end if;
  begin
    perform crm.plazos_carga_mes_fn();
    v_estado := 'paso';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate;
  end;
  if v_estado is distinct from '42501' then
    raise exception 'POSTFLIGHT plazo_carga_mes: la lectura no niega sin sesión (%)', v_estado;
  end if;
  -- Ninguna función nueva entra al censo analítico.
  if exists (select 1 from private.contadores_crudos_leads_citas() c
              where c.objeto in ('private.conversion_reevaluar_plazo(date)', 'private.reabrir_mes(date,text,uuid)',
                                 'private.reapertura_impedimento(date)', 'crm.fijar_plazo_carga_mes(date,date,text)',
                                 'crm.plazos_carga_mes_fn()', 'private.conversion_plazo_hasta(date)',
                                 'private.fijar_plazo_carga(date,date,text,uuid)', 'private.plazos_carga_mes_lectura()')) then
    raise exception 'POSTFLIGHT plazo_carga_mes: una función nueva entró al censo analítico';
  end if;
  -- El re-sellado: la declaración de crm.cerrar_periodo (si existía) cambió SOLO su huella, a la del cuerpo nuevo; las demás
  -- declaraciones y el tope, intactos; el sello coincide con la lista; el censo la reconoce vigente.
  if (select pg_catalog.count(*) from private.analitica_leads_citas_exenciones)
       <> (select pg_catalog.count(*) from pg_temp._plazo_censo_antes)
     or exists (select 1 from pg_temp._plazo_censo_antes a
                 where a.objeto <> 'crm.cerrar_periodo(date)'
                   and a.fila is distinct from (select pg_catalog.to_jsonb(e) from private.analitica_leads_citas_exenciones e
                                                 where e.objeto = a.objeto))
     or exists (select 1 from pg_temp._plazo_censo_antes a
                 where a.objeto = 'crm.cerrar_periodo(date)'
                   and ((a.fila - 'huella') is distinct from (select pg_catalog.to_jsonb(e) - 'huella'
                                                                from private.analitica_leads_citas_exenciones e
                                                               where e.objeto = a.objeto)
                        or (select e.huella from private.analitica_leads_citas_exenciones e where e.objeto = a.objeto)
                             is distinct from '4b89856af0ebc6c4e46f6ffef8be61af'
                        or not exists (select 1 from private.contadores_crudos_leads_citas() c
                                        where c.objeto = a.objeto and c.declarada and c.huella_ok)))
     or (select coalesce(pg_catalog.jsonb_agg(x.fila order by x.fila::text), '[]'::jsonb) from pg_temp._plazo_censo_tope_antes x)
          is distinct from (select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) order by pg_catalog.to_jsonb(t)::text), '[]'::jsonb)
                              from private.analitica_leads_citas_tope t)
     or (exists (select 1 from private.analitica_lc_sello)
         and (select s.sello from private.analitica_lc_sello s where s.id) is distinct from private.huella_exenciones_analitica_lc()) then
    raise exception 'POSTFLIGHT plazo_carga_mes: el re-sellado del censo analítico no quedó como se esperaba';
  end if;
end
$postflight$;

-- Foto de los trinquetes DESPUÉS: tiene que ser idéntica a la de ANTES.
do $foto_despues$
declare v_f text; v_r text;
begin
  foreach v_f in array array['private.assert_f7_piezas_cerradas()', 'private.assert_analitica_leads_citas()',
                             'private.assert_analista_vigencia()', 'private.assert_auditoria()'] loop
    begin
      execute 'select (' || v_f || ')::text' into v_r;
      v_r := 'pasa: ' || coalesce(v_r, '');
    exception when others then
      v_r := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    insert into pg_temp._plazo_trinquetes values ('despues', v_f, v_r);
  end loop;
  insert into pg_temp._plazo_trinquetes
    select 'despues', 'censo analitico', c::text from private.contadores_crudos_leads_citas() c;
  insert into pg_temp._plazo_trinquetes
    select 'despues', 'censo vigencia', c::text from private.puertas_analista_sin_vigencia() c;
  insert into pg_temp._plazo_trinquetes
    select 'despues', 'tablas sin rastro', c::text from private.tablas_sin_rastro() c;
  if exists (select pieza, resultado from pg_temp._plazo_trinquetes where momento = 'antes'
             except select pieza, resultado from pg_temp._plazo_trinquetes where momento = 'despues')
     or exists (select pieza, resultado from pg_temp._plazo_trinquetes where momento = 'despues'
                except select pieza, resultado from pg_temp._plazo_trinquetes where momento = 'antes')
     or (select pg_catalog.count(*) from pg_temp._plazo_trinquetes where momento = 'antes') < 4 then
    raise exception 'POSTFLIGHT plazo_carga_mes: la foto de los trinquetes cambió: %',
      (select pg_catalog.string_agg(momento || ' · ' || pieza || ' · ' || pg_catalog.left(resultado, 200), ' | ')
         from (select * from pg_temp._plazo_trinquetes t1
                where not exists (select 1 from pg_temp._plazo_trinquetes t2
                                   where t2.momento <> t1.momento and t2.pieza = t1.pieza and t2.resultado = t1.resultado)) d);
  end if;
end
$foto_despues$;

notify pgrst, 'reload schema';
commit;
