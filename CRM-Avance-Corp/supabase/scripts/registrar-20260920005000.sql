-- Registra 20260920005000 (crm_gestion_diaria_resultado_llamada) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/gestion-diaria-resultado/generar-registrador.mjs
-- leyendo la migración del archivo: no editar a mano; regenerar. Orden de la
-- casa: PRIMERO aplicar la migración con `db query --linked --file`, DESPUÉS
-- este registrador. Prerrequisito: 20260919211958 (F1) instalada y registrada.
do $reg_gd_resultado$
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := $mig_gd_resultado$-- 20260920005000_crm_gestion_diaria_resultado_llamada.sql
-- Gestión Diaria · FASE 2 — el resultado tipificado de la llamada.
-- Plan aprobado el 19/09/2026: docs/gestion-diaria/PLAN-POR-FASES-2026-09-19.md (Fase 2).
--
-- QUÉ HACE. Cada llamada del CRM se cierra con UNO de siete resultados aprobados
-- por Miguel (no_contesto · volver_a_llamar · agendo_reunion · no_interesado ·
-- numero_errado · no_es_la_persona · pide_otro_producto) y sus efectos ocurren
-- en la MISMA transacción: la tarea siguiente, el descarte con motivo real hacia
-- el Centro de rescate (reabrible por el supervisor) y, si el cliente lo pidió,
-- «No insistir» (Ley 29571). Todo con «Deshacer» de 24 h para quien lo registró.
--
-- CÓMO. No se toca ninguna puerta sellada: la v3 COMPONE sobre los escritores
-- auditados del mundo SLA (patrón `crm.cerrar_reunion_v3`, 20260918213000):
--   · sin tarea → `crm.registrar_actividad_v2` (la actividad nace con id = p_operacion_id);
--   · con tarea → `crm.cerrar_tarea_v2` con `p_resultado_tipo` (el id vuelve en la respuesta).
-- Después escribe el resultado en `crm.actividades.metadata` (ningún trigger lo
-- veta: `trg_audit_actividades_cambio_baja` solo audita) y aplica los efectos.
-- El resultado NO es una columna ni un tipo nuevo: el CHECK de `tipo` queda como está.
--
-- REPLAY (recibo idempotente). El recibo del writer guarda su payload (tipo,
-- detalle, siguiente) y su respuesta, y NO puede actualizarse (trg_sla_recibo_guard:
-- «solo se confirma una vez»). Por eso la v3: (1) delega SIEMPRE, para que el
-- writer valide la identidad del recibo y rechace un contenido distinto (23505);
-- (2) si el recibo ya venía confirmado, no escribe NADA y reconstruye su sobre
-- desde la metadata de la actividad; (3) un replay con otro resultado/submotivo
-- se rechaza con 23505 aunque el payload del writer coincida.
--
-- FALSIFICACIÓN. La policy `actividades_insert` deja al analista insertar
-- actividades con `metadata` libre (camino `insertarActividad` del front). Un
-- `metadata.resultado` fabricado envenenaría la tasa de contacto. Trigger
-- `trg_00_actividades_resultado_solo_nucleo`: las claves del resultado solo
-- entran bajo el GUC `crm.op_resultado_llamada = on`, que ponen (y restauran)
-- únicamente el núcleo y el deshacer. El CHECK de FORMA (NOT VALID + VALIDATE,
-- patrón actividades_creado_en_finito) es la segunda defensa: catálogo cerrado.
--
-- DESHACER (24 h, solo el autor). El log es inmutable: se deshacen los EFECTOS,
-- nunca la llamada. Cancela la tarea creada (por `crm.cerrar_tarea`, con
-- retroceso automático si era cita) y, si el descarte vigente es ESTE
-- (`leads.descartado_en` = el guardado en metadata), lo revierte componiendo
-- sobre `crm.reabrir_lead_fn` (juzga persona y veto, lleva el lead a `nuevo`) y
-- restaura la etapa que tenía al descartarse, salvo `reunion_agendada` → `contactado`
-- (la cita la canceló el sistema y no se restaura: doctrina «sin hecho falso»).
-- Límites declarados: un «No insistir» no se deshace (levantarlo es de Gerencia,
-- crm.levantar_no_contactar); la tarea que la llamada CERRÓ no se reabre
-- (trg_tareas_before_update); las tareas canceladas por el descarte no vuelven;
-- si la cita creada por el resultado fue REPROGRAMADA después, la original ya
-- no está pendiente y la nueva (reagendada_de) sobrevive al deshacer.
--
-- QUIÉN REGISTRA. Los mismos roles que el writer (vendedor, supervisor y
-- gerencia; no existe veto de solo lectura para gerencia desde 20260807123000):
-- el ámbito lo decide private.sla_gestion_permitida. Un supervisor puede
-- registrar «volver a llamar» o «agendó cita» SIN tarea siguiente (la agenda es
-- del analista); al dueño del lead se le exige la tarea.
--
-- DESHACER ES UNA REAPERTURA. Revertir el descarte compone sobre
-- crm.reabrir_lead_fn: abre un CICLO nuevo (ciclo_actual + 1), reinicia el SLA
-- y la tenencia, y el descarte queda asentado (inmutable) en el ledger de
-- episodios. No es «como si no hubiera pasado»: la respuesta lo dice
-- (`ciclo_nuevo`) y la nota del historial lo enlaza. Si la reapertura es
-- imposible (otro lead vivo con el mismo teléfono/documento, persona ya cliente
-- o vetada) el deshacer entero falla con texto humano y no sella nada.
--
-- ORDEN DE CANDADOS (el de la casa, D-13: documento → persona → lead → recibo/
-- tarea). Cuando la operación tocará a la PERSONA («No insistir» o revertir un
-- descarte) se toman antes los candados de identidad con
-- private.bloquear_personas_de_leads (inertes con la bandera apagada), y luego
-- el lead FOR UPDATE; después el writer reserva su recibo (fila propia de
-- (actor, operación): no puede formar ciclo con otro actor) y cerrar_tarea toma
-- la tarea. Los NOWAIT de marcar_no_contactar pueden devolver 40001: el front
-- lo trata como rollback confirmado y el analista reintenta.
--
-- HISTORIAL POR LEAD. La misma migración hace `create or replace` de
-- `private.actividades_de_lead_core` (20260919185718) añadiendo `metadata` a
-- cada ítem (por LISTA BLANCA de claves, como el registro de F1: la metadata de
-- conversiones, fusiones y anulaciones no viaja al drawer), acordado el 19/09
-- con la sesión de «historial por lead» (su gate no sella el md5 del núcleo; sí
-- su forma y ACL, que aquí se conservan). La lista blanca del registro de F1
-- (private.registro_actividad_core) NO se amplía aquí: sus claves nuevas
-- (descartado, no_insista, deshecho_en…) las incorporará la Fase 3, que las lee.
--
-- GATE. `private.assert_gestion_diaria()` pasa a ser el paraguas: la de F1 se
-- RENOMBRA a `assert_gestion_diaria_registro()` (cuerpo intacto) y se añade
-- `assert_gestion_diaria_resultado()` (forma, ACL, CHECK validado, trigger
-- habilitado, md5 propios y md5 de TODO lo que compone). Mutantes solo banco.
--
-- CENSO ANALÍTICO (trinquete rojo): ninguna función nueva usa count( ni sum(1)
-- (intento_n y la evidencia de «no responde» van por cardinality(array_agg()), nunca por la funcion de conteo).
-- El conjunto rojo se compara antes/después y debe quedar idéntico.
--
-- PREREQUISITOS EN PRODUCCIÓN (medidos el 19/09/2026): F1 instalada
-- (20260919211958: private.assert_gestion_diaria() y crm.registro_actividad_fn),
-- historial por lead (20260919185718) y los md5 vivos listados en el preflight.
--
-- REVERSIÓN: supabase/scripts/gestion-diaria-resultado/reversa.sql (retira los
-- objetos nuevos, devuelve el gate de F1 a su nombre y el núcleo del historial a
-- su cuerpo del 19/09; la metadata ya escrita en las actividades se conserva:
-- es historia, no se borra).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- Foto del censo analítico ANTES (patrón 20260919170500): el postflight exige
-- el mismo conjunto y el mismo conjunto rojo.
create temporary table gd_resultado_preflight on commit drop as
select (select coalesce(string_agg(objeto, ',' order by objeto), '') from private.contadores_crudos_leads_citas()) as censo,
       (select coalesce(string_agg(objeto, ',' order by objeto), '') from private.contadores_crudos_leads_citas()
         where not (declarada and huella_ok)) as censo_rojo;

do $preflight$
declare
  v_firma text;
  v_md5 text;
begin
  -- Nada de F2 instalado todavía.
  if to_regprocedure('crm.registrar_llamada_v3(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)') is not null
     or to_regprocedure('crm.deshacer_resultado_llamada(uuid)') is not null
     or to_regprocedure('private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)') is not null
     or to_regprocedure('private.assert_gestion_diaria_resultado()') is not null
     or to_regprocedure('private.assert_gestion_diaria_registro()') is not null
     or to_regprocedure('private.trg_actividades_resultado_solo_nucleo()') is not null
     or exists (select 1 from pg_constraint where conrelid = 'crm.actividades'::regclass and conname = 'actividades_resultado_llamada_forma')
     or exists (select 1 from pg_trigger where tgrelid = 'crm.actividades'::regclass and tgname = 'trg_00_actividades_resultado_solo_nucleo') then
    raise exception 'PREFLIGHT: el resultado de llamada de Gestion Diaria ya esta instalado (total o parcialmente)';
  end if;
  -- F1 (20260919211958) instalada y verde; el historial por lead (20260919185718) presente.
  if to_regprocedure('private.assert_gestion_diaria()') is null
     or to_regprocedure('crm.registro_actividad_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid)') is null
     or private.assert_gestion_diaria() not like 'OK%' then
    raise exception 'PREFLIGHT: falta la Fase 1 de Gestion Diaria (20260919211958) o su gate no esta en verde';
  end if;
  if to_regprocedure('crm.actividades_de_lead_fn(uuid,integer,timestamptz,uuid)') is null
     or to_regprocedure('private.assert_actividades_de_lead_base()') is null then
    raise exception 'PREFLIGHT: falta el historial por lead (20260919185718)';
  end if;
  -- Lo que la v3 compone, EXACTAMENTE como vive en producción (md5 medidos el 19/09/2026).
  for v_firma, v_md5 in select * from (values
    ('crm.registrar_actividad_v2(uuid,uuid,text,text,jsonb)',                    '52a44ac20288a9283801a28047efba18'),
    ('crm.cerrar_tarea_v2(uuid,uuid,text,text,text,jsonb,text,text)',            'f5147d689ec8a213ec9320dad322de4b'),
    ('crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)',                    '5396719dc3133e3e658c59c9f63b3530'),
    ('private.sla_ejecutar_comando(uuid,text,uuid,jsonb)',                       '9f8f1100df419f8d7d70bf4d845adc0d'),
    ('crm.reabrir_lead_fn(uuid)',                                                '9cdac9e10f2efde549bbcbdf810b95d3'),
    ('crm.marcar_no_contactar(uuid,text)',                                       '697e0c59f73377b30e7f13340686061c'),
    ('private.actividades_de_lead_core(uuid,integer,timestamptz,uuid)',          'ef77de1e7f58ee8abe294678a103785c'),
    ('private.trg_gestion_lead_serializada()',                                   '7af0e66b8a4849566e43b514245e1b86'),
    ('private.trg_leads_sync_tareas()',                                          '6874c23294da0027f25475b4e1fc49d7'),
    ('private.trg_sla_recibo_guard()',                                           '903e9260918bc7e100bde650d46c1ee4'),
    ('private.trg_leads_cambio_etapa()',                                         '5e457384188efa3f32cf728d4bc3b2a9'),
    ('private.trg_leads_zz_sello_descarte()',                                    '150d7ae56bb2094733f7620a1362c29e')
  ) as m(firma, md5) loop
    if to_regprocedure(v_firma) is null
       or md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_md5 then
      raise exception 'PREFLIGHT: % no es el texto vivo de produccion del 19/09/2026 (md5 %)',
        v_firma, coalesce(md5(pg_get_functiondef(to_regprocedure(v_firma))), 'ausente');
    end if;
  end loop;
  if to_regprocedure('private.inicio_ciclo_lead(uuid)') is null
     or to_regprocedure('private.sla_gestion_permitida(uuid,uuid)') is null
     or to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.assert_sla_comandos()') is null then
    raise exception 'PREFLIGHT: faltan helpers del mundo SLA (inicio_ciclo_lead, sla_gestion_permitida, rol_crm, assert_sla_comandos)';
  end if;
  -- El catálogo de motivos al que mapean los submotivos, y la metadata sin claves del resultado.
  select pg_get_constraintdef(c.oid) into v_md5 from pg_constraint c
   where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_motivo_descarte_check';
  if v_md5 is null or strpos(v_md5, 'sin_interes') = 0 or strpos(v_md5, 'sin_fondos') = 0 or strpos(v_md5, 'competencia') = 0
     or strpos(v_md5, 'no_responde') = 0 or strpos(v_md5, 'datos_invalidos') = 0 or strpos(v_md5, 'pide_credito') = 0 then
    raise exception 'PREFLIGHT: leads_motivo_descarte_check no tiene el catalogo esperado: %', coalesce(v_md5, 'ausente');
  end if;
  -- Tras una reversa la metadata de las llamadas se CONSERVA (es historia): la
  -- reinstalación la admite siempre que respete el catálogo (así VALIDATE pasa).
  if exists (select 1 from crm.actividades a
             where (a.metadata->>'resultado' is not null and a.metadata->>'resultado' not in (
                      'no_contesto', 'volver_a_llamar', 'agendo_reunion', 'no_interesado',
                      'numero_errado', 'no_es_la_persona', 'pide_otro_producto'))
                or (a.metadata->>'submotivo' is not null and a.metadata->>'submotivo' not in (
                      'sin_fondos_ahora', 'ya_invirtio_con_otro', 'desconfianza', 'no_le_interesa_invertir',
                      'prestamo', 'credito', 'otro'))) then
    raise exception 'PREFLIGHT: hay actividades con resultado/submotivo fuera del catalogo: el CHECK no validaria';
  end if;
  if not has_function_privilege('authenticated', 'crm.registrar_actividad_v2(uuid,uuid,text,text,jsonb)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.cerrar_tarea_v2(uuid,uuid,text,text,text,jsonb,text,text)', 'EXECUTE') then
    raise exception 'PREFLIGHT: los writers v2 no son ejecutables por authenticated';
  end if;
  perform private.assert_sla_nucleo(); perform private.assert_sla_operacion();
  perform private.assert_sla_comandos(); perform private.assert_sla_avisos();
end;
$preflight$;

-- ── CAPA 1 · forma del resultado en crm.actividades.metadata ────────────────
-- De FORMA, no de presencia: los writers v2 siguen insertando sin metadata y el
-- histórico (4 889 llamadas con metadata = {}) sigue siendo válido. `otro` es
-- submotivo de los dos catálogos (una sola lista de valores).
alter table crm.actividades add constraint actividades_resultado_llamada_forma check (
  coalesce(metadata->>'evento', '') <> 'resultado_llamada'
  or (
    metadata->>'resultado' in (
      'no_contesto', 'volver_a_llamar', 'agendo_reunion', 'no_interesado',
      'numero_errado', 'no_es_la_persona', 'pide_otro_producto')
    and (metadata->>'submotivo' is null or metadata->>'submotivo' in (
      'sin_fondos_ahora', 'ya_invirtio_con_otro', 'desconfianza', 'no_le_interesa_invertir',
      'prestamo', 'credito', 'otro'))
  )
) not valid;
alter table crm.actividades validate constraint actividades_resultado_llamada_forma;
comment on constraint actividades_resultado_llamada_forma on crm.actividades is
  'Gestión Diaria F2: toda actividad con evento=resultado_llamada trae un resultado del catálogo cerrado (7) y, si hay submotivo, uno de los 7. De forma, no de presencia; acotado al evento propio para no vetar metadata ajena.';

-- Las claves del resultado solo las escribe el núcleo (o su deshacer), bajo el
-- GUC de transacción `crm.op_resultado_llamada`. Un INSERT del cliente API con
-- `metadata.resultado` muere aquí con 42501.
create function private.trg_actividades_resultado_solo_nucleo() returns trigger
language plpgsql security definer set search_path = '' as $function$
declare
  v_meta jsonb := coalesce(new.metadata, '{}'::jsonb);
begin
  -- Los escritores internos (auth.uid() nulo: backfills, restauraciones del
  -- banco) quedan exentos, como en trg_gestion_lead_serializada. Toda sesión
  -- con identidad, incluida service_role con JWT, pasa por el GUC.
  if (select auth.uid()) is null then
    return new;
  end if;
  -- Claves EXCLUSIVAS del resultado de llamada (ningún escritor vivo las usa:
  -- medido en el banco el 20/09; `tarea_id` la escribe crm.cerrar_reunion y
  -- `descartado`/`siguiente_id`/`motivo_descarte` son nombres genéricos, por
  -- eso NO se reservan). El evento propio se reserva siempre.
  if (v_meta ?| array['resultado', 'submotivo', 'intento_n', 'etapa_al_descartar', 'no_insista',
                      'deshecho_en', 'deshecho_por', 'descarte_revertido', 'cita_no_restaurada']
      or v_meta->>'evento' in ('resultado_llamada', 'resultado_deshecho'))
     and coalesce(pg_catalog.current_setting('crm.op_resultado_llamada', true), 'off') <> 'on' then
    raise exception 'El resultado de una llamada solo lo escribe crm.registrar_llamada_v3 (y crm.deshacer_resultado_llamada)'
      using errcode = '42501';
  end if;
  -- Append-only incluso bajo el GUC: un resultado escrito no se reescribe (el
  -- deshacer AÑADE deshecho_en; nunca cambia resultado ni submotivo).
  if tg_op = 'UPDATE' and old.metadata ? 'resultado'
     and (new.metadata->>'resultado' is distinct from old.metadata->>'resultado'
          or new.metadata->>'submotivo' is distinct from old.metadata->>'submotivo') then
    raise exception 'El resultado de una llamada no se reescribe' using errcode = '42501';
  end if;
  return new;
end;
$function$;
comment on function private.trg_actividades_resultado_solo_nucleo() is
  'Gestión Diaria F2: veta metadata.resultado/submotivo/deshecho_en y evento resultado_llamada/resultado_deshecho salvo bajo el GUC crm.op_resultado_llamada=on (solo el núcleo y el deshacer lo ponen).';
revoke all on function private.trg_actividades_resultado_solo_nucleo()
  from public, anon, authenticated, service_role;
create trigger trg_00_actividades_resultado_solo_nucleo
  before insert or update of metadata on crm.actividades
  for each row execute function private.trg_actividades_resultado_solo_nucleo();

-- ── CAPA 2 · NÚCLEO ─────────────────────────────────────────────────────────
create function private.llamada_registrar(
  p_actor uuid,
  p_operacion_id uuid,
  p_lead_id uuid,
  p_resultado text,
  p_submotivo text,
  p_detalle text,
  p_siguiente jsonb,
  p_tarea_id uuid,
  p_descartar boolean,
  p_no_insista boolean
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_tipo text;
  v_motivo text;
  v_descartar boolean := coalesce(p_descartar, false);
  v_no_insista boolean := coalesce(p_no_insista, false);
  v_sig_tipo text;
  v_vence timestamptz;
  v_vence_lima timestamp;
  v_previa jsonb;
  v_resp jsonb;
  v_actividad uuid;
  v_siguiente uuid;
  v_etapa_antes text;
  v_etapa_al_descartar text;
  v_descartado_en timestamptz;
  v_meta jsonb;
  v_n integer;
  v_intentos integer;
  v_tarea_tipo text;
  v_vendedor uuid;
  v_bloqueo jsonb;
  v_guc_previo text := coalesce(pg_catalog.current_setting('crm.op_resultado_llamada', true), 'off');
begin
  -- ── 1. Validación PURA del input: antes de bloquear ni escribir nada ───────
  if p_actor is null or p_operacion_id is null or p_lead_id is null then
    raise exception 'Operacion, lead y actor son obligatorios' using errcode = '22023';
  end if;
  if p_resultado is null or p_resultado not in (
    'no_contesto', 'volver_a_llamar', 'agendo_reunion', 'no_interesado',
    'numero_errado', 'no_es_la_persona', 'pide_otro_producto') then
    raise exception 'Resultado de llamada invalido' using errcode = '22023';
  end if;
  v_tipo := case when p_resultado in ('no_contesto', 'numero_errado', 'no_es_la_persona')
                 then 'llamada_no_contestada' else 'llamada_realizada' end;

  -- Submotivo: obligatorio y del catálogo en los dos resultados que descartan;
  -- prohibido en el resto. Elige el motivo REAL del catálogo existente.
  if p_resultado = 'no_interesado' then
    if p_submotivo is null or p_submotivo not in (
      'sin_fondos_ahora', 'ya_invirtio_con_otro', 'desconfianza', 'no_le_interesa_invertir', 'otro') then
      raise exception 'Indica por que no le interesa (submotivo)' using errcode = '22023';
    end if;
    v_motivo := case p_submotivo when 'sin_fondos_ahora' then 'sin_fondos'
                                 when 'ya_invirtio_con_otro' then 'competencia'
                                 else 'sin_interes' end;
    v_descartar := true;
  elsif p_resultado = 'pide_otro_producto' then
    if p_submotivo is null or p_submotivo not in ('prestamo', 'credito', 'otro') then
      raise exception 'Indica que producto pide (submotivo)' using errcode = '22023';
    end if;
    v_motivo := 'pide_credito';
    v_descartar := true;
  elsif p_submotivo is not null then
    raise exception 'El submotivo solo acompana a "no le interesa" o "pide otro producto"' using errcode = '22023';
  end if;

  -- Descarte por decisión del analista (decisión #6 de Miguel) o «no responde».
  if v_descartar and p_resultado in ('volver_a_llamar', 'agendo_reunion') then
    raise exception 'Este resultado no descarta al lead' using errcode = '22023';
  end if;
  if v_descartar and p_resultado in ('numero_errado', 'no_es_la_persona') then v_motivo := 'datos_invalidos'; end if;
  if v_descartar and p_resultado = 'no_contesto' then v_motivo := 'no_responde'; end if;
  if v_no_insista and p_resultado not in ('no_interesado', 'pide_otro_producto') then
    raise exception '"No insistir" solo acompana a "no le interesa" o "pide otro producto"' using errcode = '22023';
  end if;

  -- Tarea siguiente: obligatoria en volver_a_llamar (llamada) y agendo_reunion
  -- (reunion); opcional en no_contesto (llamada/whatsapp) y en numero errado /
  -- no es la persona (llamada al 2.º número o reintento); prohibida al descartar.
  if p_siguiente is not null and jsonb_typeof(p_siguiente) <> 'object' then
    raise exception 'La tarea siguiente debe ser un objeto' using errcode = '22023';
  end if;
  v_sig_tipo := p_siguiente->>'tipo';
  if v_descartar and p_siguiente is not null then
    raise exception 'Un lead descartado no recibe tarea siguiente' using errcode = '22023';
  end if;
  if p_resultado = 'volver_a_llamar' and p_siguiente is not null and v_sig_tipo is distinct from 'llamada' then
    raise exception 'Indica cuando volver a llamar (tarea de llamada)' using errcode = '22023';
  elsif p_resultado = 'agendo_reunion' and p_siguiente is not null and v_sig_tipo is distinct from 'reunion' then
    raise exception 'Indica la fecha de la cita (tarea de reunion)' using errcode = '22023';
  elsif p_resultado = 'no_contesto' and p_siguiente is not null and v_sig_tipo not in ('llamada', 'whatsapp') then
    raise exception 'Tras un "no contesto" el siguiente paso es una llamada o un WhatsApp' using errcode = '22023';
  elsif p_resultado in ('numero_errado', 'no_es_la_persona') and p_siguiente is not null and v_sig_tipo is distinct from 'llamada' then
    raise exception 'Tras un numero errado el siguiente paso es una llamada' using errcode = '22023';
  end if;
  if p_siguiente is not null then
    begin
      v_vence := (p_siguiente->>'vence_en')::timestamptz;
    exception when others then
      raise exception 'Fecha de la tarea siguiente invalida' using errcode = '22023';
    end;
    if v_vence is null or not pg_catalog.isfinite(v_vence) or v_vence >= timestamptz '2100-01-01Z' then
      raise exception 'Fecha de la tarea siguiente invalida' using errcode = '22023';
    end if;
  end if;

  -- ── 2. Ámbito y candados ANTES de delegar ──────────────────────────────────
  -- Mismo predicado y mismo texto que el writer (no se revela existencia). El
  -- orden es el de la casa: PERSONA (si habrá «No insistir», como hace
  -- crm.marcar_no_contactar) → LEAD → (recibo, tarea), el mismo que ya usan
  -- cerrar_tarea y el trigger serializado; etapa previa y evidencia se leen
  -- bajo el candado del lead.
  if private.sla_gestion_permitida(p_actor, p_lead_id) is distinct from true then
    raise exception 'Gestion no disponible en tu ambito' using errcode = '42501';
  end if;
  if v_no_insista then
    -- Identidad ANTES del lead, como crm.marcar_no_contactar (documento → persona).
    if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'Registrar "No insistir" requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
    end if;
    perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
    v_bloqueo := private.bloquear_personas_de_leads(array[p_lead_id], null);
  end if;
  select l.etapa, l.vendedor_id into v_etapa_antes, v_vendedor from crm.leads l where l.id = p_lead_id for update;
  -- Tras esperar por el lead, la identidad bloqueada debe seguir siendo la suya
  -- (D-13: documento/persona pudieron cambiar mientras se esperaba) → 40001.
  if v_bloqueo is not null and private.resolver_en_puertas_bajo_candado()
     and not private.lead_dentro_de_bloqueo(p_lead_id, v_bloqueo) then
    raise exception 'La persona del lead cambio mientras se registraba; vuelve a intentarlo' using errcode = '40001';
  end if;

  -- ── 3. ¿Replay? (recibo ya confirmado para este actor y operación) ─────────
  select r.respuesta into v_previa
  from crm.sla_operacion_recibos r
  where r.actor_id = p_actor and r.operacion_id = p_operacion_id;

  if v_previa is null then
    -- Lo TEMPORAL se exige solo a una operación nueva: un reintento tardío de
    -- una operación ya confirmada (respuesta perdida) debe recuperar su recibo,
    -- no morir con 22023 por una fecha que ya pasó (Codex, 19/09).
    if v_vence is not null then
      if v_vence <= pg_catalog.clock_timestamp() then
        raise exception 'La tarea siguiente debe ser futura' using errcode = '22023';
      end if;
      -- Ventana legal de contacto (Ley 29571): L–S 07:00–20:00 Lima para llamada y
      -- WhatsApp. Una cita la acuerda el cliente: solo se exige que sea futura.
      if v_sig_tipo in ('llamada', 'whatsapp') then
        v_vence_lima := v_vence at time zone 'America/Lima';
        if extract(isodow from v_vence_lima) = 7
           or v_vence_lima::time < time '07:00' or v_vence_lima::time >= time '20:00' then
          raise exception 'Solo se contacta de lunes a sabado entre 07:00 y 20:00 (Lima)' using errcode = '22023';
        end if;
      end if;
    end if;
    if v_etapa_antes in ('convertido', 'descartado') then
      raise exception 'El lead esta cerrado' using errcode = '22023';
    end if;
    -- La tarea siguiente se exige al DUEÑO del lead («volver a llamar crea la
    -- tarea sola»); un supervisor registra sin agendar: la agenda es del analista.
    if p_siguiente is null and v_vendedor = p_actor then
      if p_resultado = 'volver_a_llamar' then
        raise exception 'Indica cuando volver a llamar (tarea de llamada)' using errcode = '22023';
      elsif p_resultado = 'agendo_reunion' then
        raise exception 'Indica la fecha de la cita (tarea de reunion)' using errcode = '22023';
      end if;
    end if;
    if p_tarea_id is not null then
      -- Solo una tarea de LLAMADA pendiente de este lead: cerrar aquí una cita
      -- como «completada» la degradaría a sin_clasificar y saltaría la entrevista.
      select t.tipo into v_tarea_tipo from crm.tareas t
      where t.id = p_tarea_id and t.lead_id = p_lead_id and t.activo and t.estado = 'pendiente';
      if v_tarea_tipo is null then
        raise exception 'Tarea no encontrada, cerrada o de otro lead' using errcode = '22023';
      end if;
      if v_tarea_tipo <> 'llamada' then
        raise exception 'Solo una tarea de llamada se cierra con el resultado de una llamada' using errcode = '22023';
      end if;
    end if;
  end if;

  -- ── 4. Delegar SIEMPRE en el writer sellado (identidad del recibo, ámbito,
  --      actividad, tarea siguiente, episodio SLA) ─────────────────────────────
  if p_tarea_id is null then
    v_resp := crm.registrar_actividad_v2(p_operacion_id, p_lead_id, v_tipo, p_detalle, p_siguiente);
    v_actividad := p_operacion_id;
  else
    v_resp := crm.cerrar_tarea_v2(p_operacion_id, p_tarea_id, 'completada', v_tipo, p_detalle, p_siguiente, null, null);
    v_actividad := nullif(v_resp->>'actividad_id', '')::uuid;
    if v_actividad is null then
      raise exception 'El cierre de la tarea no dejo actividad de llamada' using errcode = '23514';
    end if;
  end if;
  if coalesce((v_resp->>'ok')::boolean, false) is not true
     or nullif(v_resp->>'lead_id', '')::uuid is distinct from p_lead_id then
    raise exception 'El servidor no confirmo la gestion' using errcode = '23514';
  end if;
  v_siguiente := nullif(v_resp->>'siguiente_id', '')::uuid;

  -- ── 5. Replay: sin escribir nada, el sobre se reconstruye desde la actividad ─
  if v_previa is not null then
    select a.metadata into v_meta from crm.actividades a where a.id = v_actividad;
    -- El recibo del writer no guarda resultado, submotivo, descarte ni «No
    -- insistir»: se comparan aquí con lo persistido (Codex, 19/09).
    if v_meta->>'evento' is distinct from 'resultado_llamada'
       or v_meta->>'resultado' is distinct from p_resultado
       or v_meta->>'submotivo' is distinct from p_submotivo
       or coalesce((v_meta->>'descartado')::boolean, false) is distinct from v_descartar
       or coalesce((v_meta->>'no_insista')::boolean, false) is distinct from v_no_insista then
      raise exception 'Esta operacion ya corresponde a otro contenido' using errcode = '23505';
    end if;
    return v_resp || pg_catalog.jsonb_build_object(
      'comando', 'registrar_llamada',
      'actividad_id', v_actividad,
      'siguiente_id', nullif(v_meta->>'siguiente_id', '')::uuid,
      'descartado', coalesce((v_meta->>'descartado')::boolean, false),
      'no_insista', coalesce((v_meta->>'no_insista')::boolean, false),
      'resultado', p_resultado,
      'intento_n', (v_meta->>'intento_n')::integer,
      'deshecho', (v_meta ? 'deshecho_en'),
      'etapa', (select l.etapa from crm.leads l where l.id = p_lead_id),
      'replay', true);
  end if;

  -- ── 6. Primera vez: el resultado en la actividad ───────────────────────────
  -- intento_n = llamadas del lead en el ciclo actual, esta incluida (cardinality(array_agg), nunca la funcion de conteo: censo analitico).
  select coalesce(pg_catalog.cardinality(pg_catalog.array_agg(a.id)), 0) into v_n
  from crm.actividades a
  where a.lead_id = p_lead_id
    and a.tipo in ('llamada_realizada', 'llamada_no_contestada')
    and a.creado_en >= coalesce(private.inicio_ciclo_lead(p_lead_id), '-infinity'::timestamptz);

  perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
  update crm.actividades a
     set metadata = a.metadata || pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
       'evento', 'resultado_llamada',
       'resultado', p_resultado,
       'submotivo', p_submotivo,
       'intento_n', v_n,
       'etapa_anterior', v_etapa_antes,
       'siguiente_id', v_siguiente,
       'tarea_id', p_tarea_id,
       'descartado', v_descartar,
       'no_insista', v_no_insista))
   where a.id = v_actividad;
  if not found then
    raise exception 'La actividad de la llamada no existe' using errcode = '23514';
  end if;
  perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc_previo, true);

  -- ── 7. Descarte en la misma operación (hacia el Centro de rescate) ─────────
  if v_descartar then
    if p_resultado = 'no_contesto' then
      -- «No responde» afirma un HECHO: espejo de INTENTOS_MIN_NO_RESPONDE (2) del
      -- front — intentos sin respuesta POSTERIORES a la última conversación,
      -- esta llamada incluida.
      select coalesce(pg_catalog.cardinality(pg_catalog.array_agg(a.id)), 0) into v_intentos
      from crm.actividades a
      where a.lead_id = p_lead_id
        and a.tipo in ('llamada_no_contestada', 'whatsapp_enviado')
        -- Un número errado no es «no responde»: no cuenta como intento sin respuesta.
        and coalesce(a.metadata->>'resultado', '') not in ('numero_errado', 'no_es_la_persona')
        and a.creado_en > coalesce((
          select pg_catalog.max(c.creado_en) from crm.actividades c
          where c.lead_id = p_lead_id
            and c.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')),
          '-infinity'::timestamptz);
      if v_intentos < 2 then
        raise exception '"No responde" exige al menos 2 intentos sin respuesta registrados' using errcode = '22023';
      end if;
    end if;
    select l.etapa into v_etapa_al_descartar from crm.leads l where l.id = p_lead_id;
    -- Las columnas EXACTAS que hoy toca el store (lib/store.tsx descartar):
    -- descartado_en/por los sella trg_leads_zz_sello_descarte; el ledger cierra
    -- el episodio que lee crm.rescate_descartes_mes; las tareas pendientes las
    -- cancela el sistema (trg_leads_sync_tareas).
    update crm.leads
       set etapa = 'descartado', motivo_descarte = v_motivo
     where id = p_lead_id and activo = true and etapa not in ('convertido', 'descartado');
    if not found then
      raise exception 'El lead cambio mientras se registraba; recarga la ficha' using errcode = 'P0409';
    end if;
    select l.descartado_en into v_descartado_en from crm.leads l where l.id = p_lead_id;
    perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
    update crm.actividades a
       set metadata = a.metadata || pg_catalog.jsonb_build_object(
         'etapa_al_descartar', v_etapa_al_descartar,
         'motivo_descarte', v_motivo,
         'descartado_en', v_descartado_en)
     where a.id = v_actividad;
    perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc_previo, true);
  end if;

  -- ── 8. «Pidió que no lo vuelvan a llamar» (Ley 29571): puerta existente ─────
  if v_no_insista then
    perform crm.marcar_no_contactar(p_lead_id, 'Pidio que no lo vuelvan a llamar (resultado de llamada)');
  end if;

  return v_resp || pg_catalog.jsonb_build_object(
    'comando', 'registrar_llamada',
    'actividad_id', v_actividad,
    'siguiente_id', v_siguiente,
    'descartado', v_descartar,
    'no_insista', v_no_insista,
    'resultado', p_resultado,
    'intento_n', v_n,
    'deshecho', false,
    'etapa', (select l.etapa from crm.leads l where l.id = p_lead_id),
    'replay', false);
end;
$function$;

comment on function private.llamada_registrar(uuid, uuid, uuid, text, text, text, jsonb, uuid, boolean, boolean) is
  'NÚCLEO Gestión Diaria F2: valida el resultado tipificado, bloquea el lead, delega en crm.registrar_actividad_v2 / crm.cerrar_tarea_v2 (recibo idempotente), escribe el resultado en metadata bajo crm.op_resultado_llamada, descarta con motivo real y marca No insistir. En replay no escribe: reconstruye el sobre desde la actividad.';
revoke all on function private.llamada_registrar(uuid, uuid, uuid, text, text, text, jsonb, uuid, boolean, boolean)
  from public, anon, authenticated, service_role;

-- ── CAPA 3 · PUERTAS ────────────────────────────────────────────────────────
create function crm.registrar_llamada_v3(
  p_operacion_id uuid,
  p_lead_id uuid,
  p_resultado text,
  p_submotivo text default null,
  p_detalle text default null,
  p_siguiente jsonb default null,
  p_tarea_id uuid default null,
  p_descartar boolean default false,
  p_no_insista boolean default false
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
begin
  -- Mismos roles que el writer (sla_ejecutar_comando); el ámbito lo decide el núcleo.
  if v_uid is null or v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_operacion_id is null or p_lead_id is null or p_resultado is null then
    raise exception 'Operacion, lead y resultado son obligatorios' using errcode = '22023';
  end if;
  return private.llamada_registrar(
    v_uid, p_operacion_id, p_lead_id, p_resultado, p_submotivo,
    nullif(pg_catalog.btrim(coalesce(p_detalle, '')), ''),
    p_siguiente, p_tarea_id, coalesce(p_descartar, false), coalesce(p_no_insista, false));
end;
$function$;
comment on function crm.registrar_llamada_v3(uuid, uuid, text, text, text, jsonb, uuid, boolean, boolean) is
  'PUERTA Gestión Diaria F2: registra una llamada con resultado tipificado (7 del catálogo) y sus efectos en una transacción: tarea siguiente, descarte con submotivo hacia el Centro de rescate, No insistir. Idempotente por p_operacion_id (recibo del mundo SLA). Sobre: {ok, version:2, operacion_id, comando:registrar_llamada, lead_id, actividad_id, siguiente_id, descartado, resultado, intento_n, etapa, replay}.';
revoke all on function crm.registrar_llamada_v3(uuid, uuid, text, text, text, jsonb, uuid, boolean, boolean)
  from public, anon, authenticated, service_role;
grant execute on function crm.registrar_llamada_v3(uuid, uuid, text, text, text, jsonb, uuid, boolean, boolean)
  to authenticated;

create function crm.deshacer_resultado_llamada(p_actividad_id uuid) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_act crm.actividades%rowtype;
  v_lead crm.leads%rowtype;
  v_tarea crm.tareas%rowtype;
  v_tarea_cancelada boolean := false;
  v_descarte_revertido boolean := false;
  v_cita_no_restaurada boolean := false;
  v_restaurar text;
  v_guc_previo text := coalesce(pg_catalog.current_setting('crm.op_resultado_llamada', true), 'off');
  v_nota uuid;
  v_ahora timestamptz;
  v_bloqueo jsonb;
begin
  if v_uid is null or v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_actividad_id is null then
    raise exception 'La actividad es obligatoria' using errcode = '22023';
  end if;
  -- Solo el AUTOR deshace lo suyo; una actividad ajena o inexistente recibe la
  -- misma respuesta (fail-closed, sin revelar existencia).
  -- La fila de la actividad se toma FOR UPDATE: dos «Deshacer» a la vez (doble
  -- clic en el toast, dos pestañas) se serializan aquí y el segundo relee el
  -- sello `deshecho_en` que dejó el primero. Ningún otro escritor actualiza
  -- crm.actividades salvo el núcleo sobre su propia fila recién nacida.
  select * into v_act from crm.actividades a where a.id = p_actividad_id for update;
  if not found or v_act.creado_por is distinct from v_uid then
    raise exception 'Resultado no encontrado o no es tuyo' using errcode = 'P0002';
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  if v_act.metadata->>'evento' is distinct from 'resultado_llamada' then
    raise exception 'Esta actividad no es un resultado de llamada' using errcode = '22023';
  end if;
  if v_act.metadata ? 'deshecho_en' then
    raise exception 'Este resultado ya se deshizo' using errcode = '22023';
  end if;
  if v_act.creado_en < v_ahora - interval '24 hours' then
    raise exception 'Solo se puede deshacer dentro de las 24 horas' using errcode = '22023';
  end if;
  if coalesce((v_act.metadata->>'no_insista')::boolean, false) then
    raise exception 'Este resultado marco "No insistir": esa restriccion solo la levanta Gerencia y no se deshace desde aqui'
      using errcode = 'P0429';
  end if;
  -- Ámbito VIGENTE (el lead pudo cambiar de manos). Candados en el orden de la
  -- casa (documento → persona → lead), el mismo que crm.reabrir_lead_fn: si el
  -- descarte va a revertirse, los de identidad se toman ANTES del lead (una
  -- reapertura concurrente del supervisor no puede cruzarse; Codex, 19/09).
  -- Inertes con la identidad apagada. Se revalida ámbito y descarte DESPUÉS.
  if private.sla_gestion_permitida(v_uid, v_act.lead_id) is distinct from true then
    raise exception 'Gestion no disponible en tu ambito' using errcode = '42501';
  end if;
  if coalesce((v_act.metadata->>'descartado')::boolean, false) then
    if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'Deshacer requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
    end if;
    perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
    v_bloqueo := private.bloquear_personas_de_leads(array[v_act.lead_id], null);
  end if;
  select * into v_lead from crm.leads l where l.id = v_act.lead_id for update;
  if private.sla_gestion_permitida(v_uid, v_act.lead_id) is distinct from true then
    raise exception 'El lead cambio de responsable; recarga la ficha' using errcode = '42501';
  end if;
  if v_bloqueo is not null and private.resolver_en_puertas_bajo_candado()
     and not private.lead_dentro_de_bloqueo(v_lead.id, v_bloqueo) then
    raise exception 'La persona del lead cambio mientras se deshacia; vuelve a intentarlo' using errcode = '40001';
  end if;
  -- La ventana de 24 h se juzga con el reloj DESPUÉS de esperar los candados.
  v_ahora := pg_catalog.clock_timestamp();
  if v_act.creado_en < v_ahora - interval '24 hours' then
    raise exception 'Solo se puede deshacer dentro de las 24 horas' using errcode = '22023';
  end if;

  -- (a) La tarea que ESTE resultado creó, si sigue pendiente: se cancela por la
  --     puerta de cierre (una cita cancelada retrocede la etapa sola).
  if nullif(v_act.metadata->>'siguiente_id', '') is not null then
    select * into v_tarea from crm.tareas t
    where t.id = (v_act.metadata->>'siguiente_id')::uuid and t.lead_id = v_lead.id
      and t.activo and t.estado = 'pendiente';
    if found then
      perform crm.cerrar_tarea(
        v_tarea.id, 'cancelada', null, 'Resultado de llamada deshecho', null, null,
        case when v_tarea.tipo = 'reunion' then 'otro' end);
      v_tarea_cancelada := true;
    end if;
  end if;

  -- (b) El descarte, solo si el vigente es ESTE (mismo sello descartado_en).
  if coalesce((v_act.metadata->>'descartado')::boolean, false)
     and v_lead.etapa = 'descartado'
     and v_lead.descartado_en is not null
     and v_lead.descartado_en = nullif(v_act.metadata->>'descartado_en', '')::timestamptz then
    -- Juzga persona, veto y ámbito; lleva el lead a `nuevo` (D-15) y abre un
    -- ciclo nuevo. Un teléfono/documento ya vivo en OTRO lead (el enfriamiento
    -- de datos_invalidos y pide_credito es de 0 días) se traduce a texto humano;
    -- «ya es cliente» (P0409) y «persona vetada» (P0429) ya lo traen.
    begin
      perform crm.reabrir_lead_fn(v_lead.id);
    exception when unique_violation then
      raise exception 'Ya existe otro lead vivo con ese telefono o documento: el descarte no se puede revertir'
        using errcode = '22023';
    end;
    v_restaurar := v_act.metadata->>'etapa_al_descartar';
    if v_restaurar = 'reunion_agendada' then
      -- La cita la canceló el sistema al descartar y no vuelve: sin cita viva no
      -- hay «reunión agendada» (doctrina de 20260726151751).
      v_restaurar := 'contactado';
      v_cita_no_restaurada := true;
    end if;
    if v_restaurar in ('contactado', 'propuesta_enviada') then
      update crm.leads set etapa = v_restaurar
       where id = v_lead.id and activo = true and etapa = 'nuevo';
    end if;
    v_descarte_revertido := true;
  end if;

  -- (c) Marca en la actividad original + nota en el historial (el log no se borra).
  perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
  update crm.actividades a
     set metadata = a.metadata || pg_catalog.jsonb_build_object('deshecho_en', v_ahora, 'deshecho_por', v_uid)
   where a.id = p_actividad_id;
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (
    v_lead.id, 'nota',
    pg_catalog.format('Resultado de llamada deshecho (%s)%s%s',
      v_act.metadata->>'resultado',
      case when v_tarea_cancelada then ' · tarea siguiente cancelada' else '' end,
      case when v_descarte_revertido then ' · descarte revertido' else '' end),
    pg_catalog.jsonb_build_object(
      'evento', 'resultado_deshecho', 'actividad_id', p_actividad_id,
      'tarea_cancelada', v_tarea_cancelada, 'descarte_revertido', v_descarte_revertido,
      'cita_no_restaurada', v_cita_no_restaurada),
    v_uid)
  returning id into v_nota;
  perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc_previo, true);

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'actividad_id', p_actividad_id,
    'lead_id', v_lead.id,
    'nota_id', v_nota,
    'tarea_cancelada', v_tarea_cancelada,
    'descarte_revertido', v_descarte_revertido,
    'cita_no_restaurada', v_cita_no_restaurada,
    'ciclo_nuevo', (select l.ciclo_actual from crm.leads l where l.id = v_lead.id) > v_lead.ciclo_actual,
    'etapa', (select l.etapa from crm.leads l where l.id = v_lead.id));
end;
$function$;
comment on function crm.deshacer_resultado_llamada(uuid) is
  'PUERTA Gestión Diaria F2: deshace los EFECTOS de un resultado de llamada (≤ 24 h, solo el autor, ámbito vigente): cancela la tarea creada y revierte el descarte si sigue vigente (compone sobre crm.reabrir_lead_fn y restaura la etapa; reunion_agendada vuelve como contactado). La llamada queda en el historial con deshecho_en; deja una nota. No deshace "No insistir" ni reabre la tarea que la llamada cerró.';
revoke all on function crm.deshacer_resultado_llamada(uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.deshacer_resultado_llamada(uuid) to authenticated;

-- ── Historial por lead: cada ítem lleva su metadata (acordado el 19/09) ─────
-- Cuerpo IDÉNTICO al de 20260919185718 salvo `metadata` en la CTE y en el ítem.
-- Forma, volatilidad, search_path y ACL se conservan (create or replace).
create or replace function private.actividades_de_lead_core(
  p_lead uuid,
  p_limite integer,
  p_antes_de timestamptz,
  p_antes_id uuid
) returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  with pagina as (
    select a.id, a.lead_id, a.tipo, a.detalle, a.metadata, a.creado_por, a.creado_en
    from crm.actividades a
    where a.lead_id = p_lead
      and (
        p_antes_de is null
        or a.creado_en < p_antes_de
        or (a.creado_en = p_antes_de and a.id > p_antes_id)
      )
    order by a.creado_en desc, a.id asc
    limit p_limite
  )
  select jsonb_build_object(
    'version', 1,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', pg.id,
          'lead_id', pg.lead_id,
          'tipo', pg.tipo,
          'detalle', pg.detalle,
          -- Lista blanca (la de registro_actividad_core más las claves del
          -- resultado de llamada): la metadata de conversiones, fusiones y
          -- anulaciones no viaja al drawer. Sin count(.
          'metadata', coalesce((
            select jsonb_object_agg(m.clave, m.valor)
            from jsonb_each(pg.metadata) as m(clave, valor)
            where m.clave in (
              'evento', 'resultado', 'submotivo', 'intento_n', 'etapa_anterior', 'etapa_nueva',
              'automatico', 'resultado_reunion', 'modalidad', 'motivo',
              'descartado', 'no_insista', 'deshecho_en', 'siguiente_id', 'tarea_id',
              'motivo_descarte', 'etapa_al_descartar', 'actividad_id',
              'tarea_cancelada', 'descarte_revertido', 'cita_no_restaurada')
          ), '{}'::jsonb),
          'autor_nombre', coalesce(private.nombre_de_autor(pg.creado_por), '—'),
          'creado_en', pg.creado_en
        )
        order by pg.creado_en desc, pg.id asc
      )
      from pagina pg
    ), '[]'::jsonb),
    -- Una sola pasada por el historial del lead para las tres señales
    -- (auditoría RLS del 19/09): bool_or/max filter, nunca count(.
    'senales', (
      select jsonb_build_object(
        'tiene_reunion_realizada', coalesce(bool_or(a.tipo = 'reunion_realizada'), false),
        'tiene_contacto', coalesce(bool_or(a.tipo in (
          'llamada_realizada', 'llamada_no_contestada',
          'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada')), false),
        'ultima_conversacion_en', max(a.creado_en) filter (where a.tipo in (
          'llamada_realizada', 'whatsapp_recibido', 'reunion_realizada'))
      )
      from crm.actividades a
      where a.lead_id = p_lead
    )
  );
$function$;
comment on function private.actividades_de_lead_core(uuid, integer, timestamptz, uuid) is
  'NÚCLEO: página keyset (creado_en desc, id asc) del historial de UN lead bajo la RLS del actor, más las señales «alguna vez» (reunión realizada, contacto, última conversación). Puro: sin auth ni autoridad propia. Desde Gestión Diaria F2 cada ítem lleva su metadata (resultado de llamada).';

-- ── Gate: la de F1 se renombra (cuerpo intacto); la nueva es el paraguas ────
alter function private.assert_gestion_diaria() rename to assert_gestion_diaria_registro;
comment on function private.assert_gestion_diaria_registro() is
  'Trinquete de Gestión Diaria · Fase 1 (registro): puerta y núcleo INVOKER con search_path vacío, EXECUTE solo para authenticated, índice actividades_autor_fecha_idx presente, nombre_de_autor en su forma, y las policies actividades_select/leads_select selladas vía private.assert_actividades_de_lead_base(). La llama private.assert_gestion_diaria().';

create function private.assert_gestion_diaria_resultado() returns text
language plpgsql stable security definer set search_path = '' as $function$
declare
  v_firma text;
  v_md5 text;
  v_id oid;
begin
  -- 1. Puertas: DEFINER, volátiles, search_path vacío, owner postgres, EXECUTE
  --    exactamente para authenticated.
  foreach v_firma in array array[
    'crm.registrar_llamada_v3(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)',
    'crm.deshacer_resultado_llamada(uuid)'
  ] loop
    v_id := to_regprocedure(v_firma);
    if v_id is null or not exists (
      select 1 from pg_proc p
      where p.oid = v_id and p.prosecdef
        and p.proowner = 'postgres'::regrole::oid
        and p.provolatile = 'v'
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'Contrato del resultado de llamada alterado (debe ser DEFINER, volatile, search_path vacio): %', v_firma;
    end if;
    if not has_function_privilege('authenticated', v_id, 'EXECUTE')
       or exists (
         select 1 from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         where p.oid = v_id
           and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
       ) then
      raise exception 'ACL del resultado de llamada alterada: %', v_firma;
    end if;
  end loop;

  -- 2. Núcleo y función del trigger: DEFINER, search_path vacío, owner postgres,
  --    SIN EXECUTE para nadie salvo postgres.
  foreach v_firma in array array[
    'private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)',
    'private.trg_actividades_resultado_solo_nucleo()'
  ] loop
    v_id := to_regprocedure(v_firma);
    if v_id is null or not exists (
      select 1 from pg_proc p
      where p.oid = v_id and p.prosecdef
        and p.proowner = 'postgres'::regrole::oid
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'Nucleo del resultado de llamada alterado (debe ser DEFINER, search_path vacio): %', v_firma;
    end if;
    if exists (
      select 1 from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid = v_id and a.grantee <> 'postgres'::regrole::oid
    ) then
      raise exception 'El nucleo del resultado de llamada tiene EXECUTE fuera de postgres: %', v_firma;
    end if;
  end loop;

  -- 3. El CHECK de forma, VALIDADO y con el catálogo completo.
  if not exists (
    select 1 from pg_constraint c
    where c.conrelid = 'crm.actividades'::regclass
      and c.conname = 'actividades_resultado_llamada_forma'
      and c.contype = 'c' and c.convalidated
      and strpos(pg_get_constraintdef(c.oid), 'no_contesto') > 0
      and strpos(pg_get_constraintdef(c.oid), 'volver_a_llamar') > 0
      and strpos(pg_get_constraintdef(c.oid), 'agendo_reunion') > 0
      and strpos(pg_get_constraintdef(c.oid), 'no_interesado') > 0
      and strpos(pg_get_constraintdef(c.oid), 'numero_errado') > 0
      and strpos(pg_get_constraintdef(c.oid), 'no_es_la_persona') > 0
      and strpos(pg_get_constraintdef(c.oid), 'pide_otro_producto') > 0
      and strpos(pg_get_constraintdef(c.oid), 'submotivo') > 0
      -- La DEFINICIÓN COMPLETA, sellada: un octavo valor conservaría todos los
      -- LIKE de arriba y pasaría (Codex, 19/09). Huella medida en el banco.
      and md5(pg_get_constraintdef(c.oid)) = 'ec46b200b9181592b0f48af06009c4c7'
  ) then
    raise exception 'Falta o cambio el CHECK actividades_resultado_llamada_forma (o no esta validado)';
  end if;

  -- 4. El trigger que veta la falsificación: presente, habilitado, BEFORE
  --    INSERT OR UPDATE OF metadata, con su función.
  if not exists (
    select 1 from pg_trigger t
    where t.tgrelid = 'crm.actividades'::regclass
      and t.tgname = 'trg_00_actividades_resultado_solo_nucleo'
      and t.tgenabled in ('O', 'A')
      and t.tgfoid = to_regprocedure('private.trg_actividades_resultado_solo_nucleo()')
      and pg_get_triggerdef(t.oid) like '%BEFORE INSERT OR UPDATE OF metadata ON crm.actividades FOR EACH ROW%'
  ) then
    raise exception 'Falta, esta deshabilitado o cambio el trigger trg_00_actividades_resultado_solo_nucleo';
  end if;

  -- 5. Los CUERPOS, sellados: los propios (medidos en el banco, dos pasadas) y
  --    los de TODO lo que la v3 compone (texto vivo de producción el 19/09/2026).
  --    Un `create or replace` sobre cualquiera exige re-sellar aquí a conciencia.
  for v_firma, v_md5 in select * from (values
    ('private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)', 'fec6bfd18b0ca26623f84b55daddef64'),
    ('crm.registrar_llamada_v3(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)',        '92d2dcfb4cc03c158a42292980226ba2'),
    ('crm.deshacer_resultado_llamada(uuid)',                                                  '5869117e03ac55d699d248244a71bb31'),
    ('private.trg_actividades_resultado_solo_nucleo()',                                       '19952736370f64026f747c19b54ab38e'),
    ('private.actividades_de_lead_core(uuid,integer,timestamptz,uuid)',                       '805b3489aeab94371328f28229f23fe5'),
    ('crm.registrar_actividad_v2(uuid,uuid,text,text,jsonb)',                                 '52a44ac20288a9283801a28047efba18'),
    ('crm.cerrar_tarea_v2(uuid,uuid,text,text,text,jsonb,text,text)',                         'f5147d689ec8a213ec9320dad322de4b'),
    ('crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)',                                 '5396719dc3133e3e658c59c9f63b3530'),
    ('private.sla_ejecutar_comando(uuid,text,uuid,jsonb)',                                    '9f8f1100df419f8d7d70bf4d845adc0d'),
    ('crm.reabrir_lead_fn(uuid)',                                                             '9cdac9e10f2efde549bbcbdf810b95d3'),
    ('crm.marcar_no_contactar(uuid,text)',                                                    '697e0c59f73377b30e7f13340686061c'),
    ('private.trg_gestion_lead_serializada()',                                                '7af0e66b8a4849566e43b514245e1b86'),
    ('private.trg_leads_sync_tareas()',                                                       '6874c23294da0027f25475b4e1fc49d7'),
    ('private.trg_sla_recibo_guard()',                                                        '903e9260918bc7e100bde650d46c1ee4'),
    ('private.trg_leads_cambio_etapa()',                                                      '5e457384188efa3f32cf728d4bc3b2a9'),
    ('private.trg_leads_zz_sello_descarte()',                                                 '150d7ae56bb2094733f7620a1362c29e')
  ) as m(firma, md5) loop
    if to_regprocedure(v_firma) is null
       or md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_md5 then
      raise exception 'El cuerpo de % cambio: re-sellar el resultado de llamada de Gestion Diaria (md5 %)',
        v_firma, coalesce(md5(pg_get_functiondef(to_regprocedure(v_firma))), 'ausente');
    end if;
  end loop;

  -- 6. El núcleo del historial sigue INVOKER, estable, search_path vacío, con
  --    EXECUTE para authenticated, y entrega metadata.
  v_id := to_regprocedure('private.actividades_de_lead_core(uuid,integer,timestamptz,uuid)');
  if not exists (
    select 1 from pg_proc p
    where p.oid = v_id and not p.prosecdef and p.proowner = 'postgres'::regrole::oid
      and p.provolatile = 's' and p.proconfig @> array['search_path=""']
      and strpos(p.prosrc, 'jsonb_each(pg.metadata) as m(clave, valor)') > 0
  ) or not has_function_privilege('authenticated', v_id, 'EXECUTE') then
    raise exception 'private.actividades_de_lead_core perdio su forma, su EXECUTE o la metadata del item';
  end if;

  -- 7. Los writers v2 y su mundo, por el gate que ya los sella.
  perform private.assert_sla_comandos();

  return 'OK: resultado de llamada — puertas DEFINER selladas (EXECUTE solo authenticated), nucleo y trigger solo postgres, CHECK de forma validado, trigger anti-falsificacion habilitado, cuerpos propios y compuestos con su md5, historial por lead con metadata';
end;
$function$;
comment on function private.assert_gestion_diaria_resultado() is
  'Trinquete de Gestión Diaria · Fase 2 (resultado de llamada): forma y ACL de puertas/núcleo/trigger, CHECK validado, trigger anti-falsificación habilitado, md5 de los cuerpos propios y de todo lo que la v3 compone (writers, reabrir, marcar_no_contactar, triggers), historial por lead con metadata, y private.assert_sla_comandos().';
revoke all on function private.assert_gestion_diaria_resultado()
  from public, anon, authenticated, service_role;

create function private.assert_gestion_diaria() returns text
language plpgsql stable security definer set search_path = '' as $function$
declare
  v_registro text;
  v_resultado text;
begin
  v_registro := private.assert_gestion_diaria_registro();
  v_resultado := private.assert_gestion_diaria_resultado();
  return 'OK: Gestion Diaria [' || v_registro || '] [' || v_resultado || ']';
end;
$function$;
comment on function private.assert_gestion_diaria() is
  'Paraguas del trinquete de Gestión Diaria: llama a assert_gestion_diaria_registro() (F1) y assert_gestion_diaria_resultado() (F2). Crecerá con cada fase.';
revoke all on function private.assert_gestion_diaria()
  from public, anon, authenticated, service_role;

-- ── Mutantes del trinquete de F2 (solo banco) ───────────────────────────────
create function private.assert_gestion_diaria_resultado_mutantes() returns text
language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_detectados integer := 0;
  v_mutacion text;
  v_nombre text;
begin
  if coalesce(current_setting('gestion_diaria.banco', true), '') <> 'on' then
    raise exception 'Los mutantes solo corren en el banco (set gestion_diaria.banco = on)';
  end if;
  for v_nombre, v_mutacion in select * from (values
    ('1 puerta invoker',            'alter function crm.registrar_llamada_v3(uuid, uuid, text, text, text, jsonb, uuid, boolean, boolean) security invoker'),
    ('2 nucleo concedido',          'grant execute on function private.llamada_registrar(uuid, uuid, uuid, text, text, text, jsonb, uuid, boolean, boolean) to authenticated'),
    ('3 sin CHECK',                 'alter table crm.actividades drop constraint actividades_resultado_llamada_forma'),
    ('4 CHECK laxo',                $m$do $x$ begin alter table crm.actividades drop constraint actividades_resultado_llamada_forma; alter table crm.actividades add constraint actividades_resultado_llamada_forma check (true); end $x$$m$),
    ('5 deshacer sin search_path',  'alter function crm.deshacer_resultado_llamada(uuid) reset search_path'),
    ('6 sin trigger',               'drop trigger trg_00_actividades_resultado_solo_nucleo on crm.actividades'),
    ('7 trigger deshabilitado',     'alter table crm.actividades disable trigger trg_00_actividades_resultado_solo_nucleo'),
    ('8 nucleo reescrito',          $m$create or replace function private.llamada_registrar(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_submotivo text, p_detalle text, p_siguiente jsonb, p_tarea_id uuid, p_descartar boolean, p_no_insista boolean) returns jsonb language sql volatile security definer set search_path to '' as $b$ select '{}'::jsonb $b$$m$),
    ('9 historial sin metadata',    $m$create or replace function private.actividades_de_lead_core(p_lead uuid, p_limite integer, p_antes_de timestamptz, p_antes_id uuid) returns jsonb language sql stable security invoker set search_path to '' as $b$ select jsonb_build_object('version', 1, 'items', '[]'::jsonb) $b$$m$),
    ('10 puerta para anon',         'grant execute on function crm.registrar_llamada_v3(uuid, uuid, text, text, text, jsonb, uuid, boolean, boolean) to anon'),
    ('11 deshacer stable',          'alter function crm.deshacer_resultado_llamada(uuid) stable'),
    ('12 reabrir alterada',         'alter function crm.reabrir_lead_fn(uuid) reset lock_timeout'),
    ('13 writer v1 alterado',       'alter function crm.cerrar_tarea(uuid, text, text, text, jsonb, text, text) set lock_timeout = ''3s'''),
    ('14 catalogo ampliado',        $m$do $x$ begin alter table crm.actividades drop constraint actividades_resultado_llamada_forma; alter table crm.actividades add constraint actividades_resultado_llamada_forma check ((metadata->>'resultado' is null or metadata->>'resultado' in ('no_contesto','volver_a_llamar','agendo_reunion','no_interesado','numero_errado','no_es_la_persona','pide_otro_producto','buzon')) and (metadata->>'submotivo' is null or metadata->>'submotivo' in ('sin_fondos_ahora','ya_invirtio_con_otro','desconfianza','no_le_interesa_invertir','prestamo','credito','otro'))); end $x$$m$)
  ) as m(nombre, sql) loop
    begin
      begin
        execute v_mutacion;
      exception when others then
        raise exception 'MUTANTE % NO APLICABLE: %', v_nombre, sqlerrm;
      end;
      perform private.assert_gestion_diaria();
      raise exception 'MUTANTE % NO DETECTADO: paso el gate', v_nombre;
    exception when others then
      if sqlerrm like 'MUTANTE %' then raise; end if;
      v_detectados := v_detectados + 1;
    end;
  end loop;
  return format('OK: %s mutantes detectados por private.assert_gestion_diaria()', v_detectados);
end;
$function$;
comment on function private.assert_gestion_diaria_resultado_mutantes() is
  'Mutantes del trinquete de Gestión Diaria F2 (solo banco, exige set gestion_diaria.banco = on): cada mutación vive en una subtransacción que se deshace; falla si el gate no la detecta o si la mutación no aplica.';
revoke all on function private.assert_gestion_diaria_resultado_mutantes()
  from public, anon, authenticated, service_role;

do $postflight$
begin
  perform private.assert_gestion_diaria();
  perform private.assert_actividades_de_lead();
  -- Los cuatro gates del mundo SLA (verdes). Los otros cuatro controles del
  -- servidor están en ROJO por trabajos ajenos: no se llaman; se exige en
  -- cambio que el censo analítico quede IDÉNTICO (ninguna función nueva cuenta).
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
  if (select coalesce(string_agg(objeto, ',' order by objeto), '') from private.contadores_crudos_leads_citas())
       <> (select censo from gd_resultado_preflight)
     or (select coalesce(string_agg(objeto, ',' order by objeto), '') from private.contadores_crudos_leads_citas()
          where not (declarada and huella_ok)) <> (select censo_rojo from gd_resultado_preflight) then
    raise exception 'POSTFLIGHT: el censo analitico cambio (una funcion nueva cuenta leads o citas)';
  end if;
  if exists (
    select 1 from pg_proc p
    where p.oid in (
      to_regprocedure('private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)'),
      to_regprocedure('crm.registrar_llamada_v3(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)'),
      to_regprocedure('crm.deshacer_resultado_llamada(uuid)'))
      and (lower(p.prosrc) ~ '\mcount\s*\(' or lower(p.prosrc) ~ '\msum\s*\(\s*1\s*\)')
  ) then
    raise exception 'POSTFLIGHT: una funcion nueva cuenta (count( o sum(1))';
  end if;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$mig_gd_resultado$;

  -- 1) PIN: lo que la migración hizo ES verdad — puertas y núcleo con la
  --    definición ensayada, CHECK validado, trigger presente y gate paraguas OK.
  if to_regprocedure('crm.registrar_llamada_v3(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)') is null
     or md5(pg_get_functiondef('crm.registrar_llamada_v3(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)'::regprocedure)) is distinct from '92d2dcfb4cc03c158a42292980226ba2'
     or md5(pg_get_functiondef('private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)'::regprocedure)) is distinct from 'fec6bfd18b0ca26623f84b55daddef64'
     or md5(pg_get_functiondef('crm.deshacer_resultado_llamada(uuid)'::regprocedure)) is distinct from '5869117e03ac55d699d248244a71bb31'
     or not exists (select 1 from pg_constraint where conrelid = 'crm.actividades'::regclass
                    and conname = 'actividades_resultado_llamada_forma' and convalidated)
     or not exists (select 1 from pg_trigger where tgrelid = 'crm.actividades'::regclass
                    and tgname = 'trg_00_actividades_resultado_solo_nucleo' and tgenabled in ('O','A'))
     or to_regprocedure('private.assert_gestion_diaria_registro()') is null
     or private.assert_gestion_diaria() not like 'OK%' then
    raise exception 'registrar gestion diaria F2: la migración 20260920005000 no está aplicada tal cual — aplicarla antes de registrar';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20260919211958') then
    raise exception 'registrar gestion diaria F2: la Fase 1 (20260919211958) no está registrada — registrarla antes';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260920005000' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar gestion diaria F2: la versión 20260920005000 existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260920005000', 'crm_gestion_diaria_resultado_llamada', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed: la fila EXACTA, o se cae la transacción entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260920005000' and name = 'crm_gestion_diaria_resultado_llamada'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar gestion diaria F2: la relectura no encontró la fila exacta';
  end if;
end $reg_gd_resultado$;
