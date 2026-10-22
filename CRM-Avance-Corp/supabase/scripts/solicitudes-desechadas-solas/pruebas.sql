-- ORÁCULO de «el CRM cancela solo las solicitudes de inversión que ya no corresponden» (bloque 2.15: D-58, D-59, D-63, D-66) —
-- se ejecuta en el LABORATORIO (banco Docker local), NUNCA contra producción, y no escribe nada.
--
-- La regla: (1) cuando nace un contrato por el alta del CRM (`crm.crear_contrato_con_cuenta_pdf_v2`), las solicitudes de
-- inversión PREPARADAS de Avance que llevan ese mismo número en `datos.contrato.numero_contrato` y no son la que lo creó pasan
-- a `cancelada` con motivo `numero_contrato_usado` (con cuál contrato); (2) cada noche, las preparadas de Avance cuyo número ya
-- lo usa un contrato que no crearon ellas (red para los contratos nacidos fuera del CRM) y las preparadas de cualquier empresa
-- con 30 días sin confirmarse ni corregirse (`actualizado_en`) se cancelan con motivo `numero_contrato_usado` o `sin_movimiento`,
-- dejando rastro de cuántas. Nunca una con acceso Avance pendiente, con inversión, que ya creó su contrato, confirmada o ya
-- cancelada; nunca la creadora; nunca una de otra empresa por el número; nunca se tumba el alta; nunca se borra nada. La consulta
-- de la solicitud (`crm.solicitud_inversion_fn`) dice el motivo al asesor.
--
-- Este archivo NO se ejecuta a mano: `armar-ensayo.mjs` pega `antes.sql` (montaje), la migración real (sin su
-- `begin;`/`commit;`) y este oráculo dentro de UNA transacción que termina en `rollback`. Con `--sin-migracion` TIENE que salir
-- ROJO por el motivo correcto (el alta entra y las solicitudes siguen preparadas; la tarea no existe; la consulta no dice el
-- motivo). Nunca un error de montaje.
--
-- Casos (los actores y la siembra, en `antes.sql`):
--   R1  El alta v2 como V1 con el número N1 (clave de idempotencia = S16) ENTRA y nace el contrato X con N1, aunque la cancelación
--       de S8 esté forzada a fallar.
--   R2  S1 y S2 quedan canceladas, motivo numero_contrato_usado, detalle {via alta, contrato_id X, numero_contrato N1, cancelada_en},
--       actualizado_en movido.
--   R3  No se tocan: S16 (la creadora), S3 (otro número), S4 (acceso pendiente), S5 (con inversión), S6 (otra empresa), S7 (ya creó
--       su contrato), S9 (ya cancelada: sin motivo), S12, S13, S14, S15 (números ajenos al alta): estado, motivo y actualizado_en
--       exactamente los sembrados.
--   R4  S8 sigue preparada; la pieza del alta, llamada otra vez con X, informa 1 rechazada (S8) y 0 canceladas (S1 y S2 ya no son
--       candidatas).
--   R5  Auditoría: public.audit_log tiene el UPDATE de S1 y S2 con el estado y el motivo, a nombre de V1.
--   R6  Un segundo alta con N1 muere con «El N de contrato N1 ya existe» (P0001) y no cambia nada (ni un contrato más, ninguna
--       cancelación más).
--   R7  La consulta como V1: S1 trae estado cancelada, cancelacion_motivo, cancelacion_detalle y cancelacion_texto con N1; S3 trae
--       las tres claves nulas y, quitadas, es byte a byte lo de antes de la migración.
--   R8  La tarea (corte = now(), 30 días, 200): número usado → S14 cancelada (contrato EX1, vía tarea) y S8 rechazada; sin
--       movimiento → S10, S11 y S18 (upgrade con origen: la continuidad lo deja) canceladas (dias 30, ultimo_movimiento), S12 y
--       S13 intactas, S15 intacta; S17 (reinversión cuyo origen es de otra cooperativa) RECHAZADA por la continuidad de postventa
--       (P0409), intacta e informada —expectativa independiente, ronda 4—; S19 (31 días con memoria idempotente) ni candidata;
--       nunca un aborto; una fila de corrida con esos contadores y el detalle.
--   R9b (ronda 4) Idempotencia con filas completas: la segunda corrida no cambia ninguna fila sembrada ni añade auditoría sobre ellas.
--   R13 (ronda 4, P2-1) La pieza relee el CONTRATO bajo candado (KEY SHARE SKIP LOCKED): S3 (N2) con un detalle cuyo contrato es X
--       (lleva N1) y número N2 → «omitida: el contrato ya no lleva ese numero»; con un contrato inexistente → «omitida: el contrato
--       ya no existe»; S3 intacta.
--   R14 (ronda 4, P2-2) Presupuesto ÚNICO de 200 por corrida: 3 preparadas con el número de EX1 + 250 preparadas de 31 días (en una
--       subtransacción que se deshace) → corrida A cancela exactamente 200 (3 + 197), corrida B 53, corrida C 0.
--   R15 (ronda 4, P2-3) Progreso: 205 preparadas antiguas que un disparador rechaza + 1 válida detrás → la válida se cancela en la
--       PRIMERA corrida (las rechazadas no consumen presupuesto); la segunda corrida no cancela nada más.
--   R9  La tarea otra vez: no cancela nada más (S8 sigue rechazada), deja otra corrida; los contadores lo dicen.
--   R10 La consulta de S10 dice «llevaba 30 días sin confirmarse ni corregirse».
--   R12 (ronda 3, P2 del auditor) La pieza escritora relee el MOTIVO bajo el candado, en una sola sesión: S3 (lleva N2) llamada
--       con el detalle de N1 → «omitida: el numero cambio bajo el candado», intacta; S12 (29 días 23 h) llamada como «sin
--       movimiento» con corte = now() → «omitida: ya no cumple el corte», intacta; S12 con un último movimiento observado que
--       no es el suyo → «omitida: se movio bajo el candado», intacta; control positivo (S12 con corte + 10 días y su último
--       movimiento exacto) → «cancelada», deshecho en una subtransacción (S12 vuelve a preparada). Va ANTES de R11 (que cancela
--       S3 a mano).
--   R11 La cancelación de la pantalla (crm.cancelar_solicitud_inversion_fn) de S3 como V1 sigue funcionando y deja el motivo nulo.
--   K1  Las cuatro piezas con su ficha (postgres, INVOKER, search_path vacío, EXECUTE solo el dueño; vista STABLE; ciclo con
--       lock_timeout); sin EXECUTE para anon, authenticated ni service_role.
--   K2  Las dos puertas: la llamada a la pieza exactamente una vez en el alta v2 y la vista en la consulta; su ficha (dueño, DEFINER,
--       ACL) la de antes; sus comentarios nombran el bloque.
--   K3  Columnas y CHECK en crm.inversion_solicitudes; la tabla de corridas con RLS, sin grants, con auditor completo (la regla de
--       auditoría no la lista) y el trinquete de auditoría da EXACTAMENTE lo mismo que antes.
--   K4  El job crm-solicitudes-desechar activo, 17 7 * * *, select private.solicitudes_desechar_ciclo().
--   K5  Lo que no se toca, intacto (cancelar, confirmar, corregir, resultado público) y el trinquete F7 pasa.
--   K6  Lo diferido sobrevive (set constraints all immediate).

set local statement_timeout = '300s';

do $ensayo$
declare
  v_v1 uuid := pg_temp.g('v1');
  v_c1 uuid := pg_temp.g('c1');
  v_n1 text := current_setting('ensayo.n1');
  v_x uuid;
  v_res text;
  v_j jsonb;
  v_s jsonb;
  v_antes jsonb;
  v_despues jsonb;
  v_corridas integer;
  v_s17 text;
  v_corrida2 uuid;
  v_n integer;
  v_aud_n integer;
  v_filas jsonb;
  v_j2 jsonb;
  v_j3 jsonb;
  v_sm_esperadas integer;
  v_sm_rech integer;
  v_h record;
  v_ficha text;
  v_aud text;
  v_f7 text;
  v_det text;
  r record;
begin
  -- ── R1 · El alta con N1 entra ─────────────────────────────────────────────────────────────────────────────────────────────
  v_res := pg_temp.llamar(v_v1, pg_temp.contrato(v_c1, v_v1, v_n1) || jsonb_build_object('clave_idempotencia', pg_temp.g('s16')));
  perform pg_temp.exigir('R1-alta-entra', v_res like 'ok|%',
    'el alta v2 con el número ' || v_n1 || ' no entró (la cancelación automática no puede tumbar el alta): ' || v_res);
  if v_res like 'ok|%' then
    v_x := (substr(v_res, 4)::jsonb ->> 'id')::uuid;
  end if;
  perform pg_temp.exigir('R1-contrato-nace',
    v_x is not null and exists (select 1 from public.contratos c where c.id = v_x and c.numero_contrato = v_n1)
      and (select count(*) from public.contratos) = current_setting('ensayo.antes.contratos')::integer + 1,
    'no nació exactamente un contrato con ' || v_n1 || ' (' || coalesce(v_x::text, 'sin id') || ')');
  perform pg_temp.exigir('R1-creadora-registrada',
    exists (select 1 from private.contrato_altas_idempotentes a where a.contrato_id = v_x and a.clave = pg_temp.g('s16') and a.actor_id = v_v1),
    'la memoria de idempotencia del alta no apunta a S16 como creadora del contrato');

  -- ── R2 · S1 y S2 canceladas con su motivo ─────────────────────────────────────────────────────────────────────────────────
  for r in select * from (values ('s1'), ('s2')) as t(n) loop
    v_s := pg_temp.sol(pg_temp.g(r.n));
    perform pg_temp.exigir('R2-' || r.n || '-cancelada',
      (v_s ->> 'estado') = 'cancelada' and (v_s ->> 'cancelacion_motivo') = 'numero_contrato_usado',
      format('%s tenía que quedar cancelada con motivo numero_contrato_usado y está «%s» con motivo «%s»', r.n, v_s ->> 'estado', coalesce(v_s ->> 'cancelacion_motivo', 'nulo')));
    perform pg_temp.exigir('R2-' || r.n || '-detalle',
      (v_s -> 'cancelacion_detalle' ->> 'contrato_id') = v_x::text and (v_s -> 'cancelacion_detalle' ->> 'numero_contrato') = v_n1
        and (v_s -> 'cancelacion_detalle' ->> 'via') = 'alta' and (v_s -> 'cancelacion_detalle') ? 'cancelada_en',
      format('el detalle de %s no dice con cuál contrato (X=%s, N1=%s, vía alta, cancelada_en): %s', r.n, v_x, v_n1, coalesce(v_s ->> 'cancelacion_detalle', 'nulo')));
    perform pg_temp.exigir('R2-' || r.n || '-actualizado',
      (v_s ->> 'actualizado_en')::timestamptz > (select actualizado_en from ensayo_siembra where nombre = r.n),
      format('actualizado_en de %s no se movió al cancelarla', r.n));
  end loop;

  -- ── R3 · Lo que no se toca ────────────────────────────────────────────────────────────────────────────────────────────────
  for r in select * from ensayo_siembra where nombre in ('s16', 's3', 's4', 's5', 's6', 's7', 's9', 's12', 's13', 's14', 's15', 's18', 's19') order by nombre loop
    v_s := pg_temp.sol(r.id);
    perform pg_temp.exigir('R3-' || r.nombre || '-intacta',
      (v_s ->> 'estado') = r.estado and (v_s ->> 'cancelacion_motivo') is null and (v_s ->> 'cancelacion_detalle') is null
        and (v_s ->> 'actualizado_en')::timestamptz = r.actualizado_en,
      format('%s cambió y no debía: estado «%s» (sembrado «%s»), motivo «%s», actualizado_en %s (sembrado %s)', r.nombre, v_s ->> 'estado', r.estado,
        coalesce(v_s ->> 'cancelacion_motivo', 'nulo'), v_s ->> 'actualizado_en', r.actualizado_en));
  end loop;

  -- ── R4 · El rechazo forzado de S8 no tumba el alta y queda informado ──────────────────────────────────────────────────────
  v_s := pg_temp.sol(pg_temp.g('s8'));
  perform pg_temp.exigir('R4-s8-sigue-preparada',
    (v_s ->> 'estado') = 'preparada' and (v_s ->> 'cancelacion_motivo') is null,
    'S8 (cuya cancelación rechaza un disparador) tenía que seguir preparada y está «' || (v_s ->> 'estado') || '»');
  v_res := pg_temp.pieza(format('select private.solicitudes_desechar_por_contrato(%L::uuid)', v_x));
  perform pg_temp.exigir('R4-pieza-informa',
    v_res like 'ok|%' and (substr(v_res, 4)::jsonb ->> 'canceladas')::integer = 0 and (substr(v_res, 4)::jsonb ->> 'rechazadas')::integer = 1
      and exists (select 1 from jsonb_array_elements(substr(v_res, 4)::jsonb -> 'solicitudes') e
                   where (e ->> 'solicitud_id') = pg_temp.g('s8')::text and (e ->> 'resultado') like 'rechazada: P0409 ENSAYO: rechazo forzado%'),
    'la pieza del alta, llamada otra vez con el contrato X, tenía que informar 0 canceladas y 1 rechazada (S8, P0409 del disparador): ' || v_res);

  -- ── R5 · Auditoría ────────────────────────────────────────────────────────────────────────────────────────────────────────
  perform pg_temp.exigir('R5-auditoria',
    (select count(*) from public.audit_log l
      where l.tabla = 'crm.inversion_solicitudes' and l.operacion = 'UPDATE'
        and l.fila_id in (pg_temp.g('s1')::text, pg_temp.g('s2')::text)
        and l.data_antes ->> 'estado' = 'preparada' and l.data_despues ->> 'estado' = 'cancelada'
        and l.data_despues ->> 'cancelacion_motivo' = 'numero_contrato_usado' and l.usuario_id = v_v1) = 2,
    'public.audit_log no tiene el UPDATE de S1 y S2 (preparada → cancelada, motivo numero_contrato_usado) a nombre de V1');

  -- ── R6 · Un segundo alta con el mismo número muere y no cambia nada ───────────────────────────────────────────────────────
  v_res := pg_temp.llamar(v_v1, pg_temp.contrato(v_c1, v_v1, v_n1) || jsonb_build_object('clave_idempotencia', gen_random_uuid()));
  perform pg_temp.exigir('R6-segundo-alta-muere',
    v_res like 'P0001|El N de contrato ' || v_n1 || ' ya existe|%',
    'el segundo alta con ' || v_n1 || ' tenía que morir con P0001 «El N de contrato … ya existe»: ' || v_res);
  perform pg_temp.exigir('R6-nada-mas-cambia',
    (select count(*) from public.contratos) = current_setting('ensayo.antes.contratos')::integer + 1
      and (select count(*) from crm.inversion_solicitudes s where s.id in (select id from ensayo_siembra) and s.estado = 'cancelada') = 3,
    'tras el segundo alta cambió algo: contratos o cancelaciones de más (se esperaban 3 canceladas: S1, S2 y S9)');

  -- ── R7 · La consulta dice el motivo; sin motivo, es lo de antes ───────────────────────────────────────────────────────────
  v_res := pg_temp.puerta(v_v1, pg_temp.g('s1'));
  v_j := case when v_res like 'ok|%' then substr(v_res, 4)::jsonb end;
  perform pg_temp.exigir('R7-consulta-motivo',
    v_j is not null and (v_j ->> 'estado') = 'cancelada' and (v_j ->> 'cancelacion_motivo') = 'numero_contrato_usado'
      and (v_j -> 'cancelacion_detalle' ->> 'numero_contrato') = v_n1 and (v_j -> 'cancelacion_detalle' ->> 'via') = 'alta'
      and not (v_j -> 'cancelacion_detalle' ? 'contrato_id')
      and (pg_temp.sol(pg_temp.g('s1')) -> 'cancelacion_detalle' ->> 'contrato_id') = v_x::text
      and (v_j ->> 'cancelacion_texto') = 'El CRM canceló esta solicitud: el número de contrato ' || v_n1 || ' ya lo usa otro contrato.',
    'la consulta de S1 como V1 no trae el motivo, el detalle (sin contrato_id en la respuesta pública; con él en la fila) y el texto esperados: ' || v_res);
  v_res := pg_temp.puerta(v_v1, pg_temp.g('s3'));
  v_j := case when v_res like 'ok|%' then substr(v_res, 4)::jsonb end;
  perform pg_temp.exigir('R7-consulta-sin-motivo',
    v_j is not null and v_j ? 'cancelacion_motivo' and v_j ? 'cancelacion_detalle' and v_j ? 'cancelacion_texto'
      and v_j -> 'cancelacion_motivo' = 'null'::jsonb and v_j -> 'cancelacion_detalle' = 'null'::jsonb and v_j -> 'cancelacion_texto' = 'null'::jsonb,
    'la consulta de S3 (preparada) tenía que traer las tres claves nulas: ' || v_res);
  perform pg_temp.exigir('R7-consulta-byte-a-byte',
    v_j is not null and current_setting('ensayo.antes.s3') like 'ok|%'
      and (v_j - 'cancelacion_motivo' - 'cancelacion_detalle' - 'cancelacion_texto') = substr(current_setting('ensayo.antes.s3'), 4)::jsonb,
    'la consulta de S3, quitadas las tres claves, no es byte a byte la de antes de la migración');

  -- ── R8 · La tarea nocturna ────────────────────────────────────────────────────────────────────────────────────────────────
  v_res := pg_temp.pieza('select count(*)::text::jsonb from crm.solicitudes_desechadas_corridas');
  v_corridas := case when v_res like 'ok|%' then substr(v_res, 4)::integer else -1 end;
  v_res := pg_temp.pieza('select private.solicitudes_desechar_ciclo(now(), 30, 200)');
  v_j := case when v_res like 'ok|%' then substr(v_res, 4)::jsonb end;
  perform pg_temp.exigir('R8-tarea-corre', v_j is not null and v_j ? 'corrida_id', 'la tarea nocturna no corre: ' || v_res);
  v_s := pg_temp.sol(pg_temp.g('s17'));
  v_s17 := coalesce(v_s ->> 'estado', '?') || '/' || coalesce(v_s ->> 'cancelacion_motivo', 'sin motivo');
  if v_j is not null then
    perform set_config('ensayo.s17_resultado', coalesce((select e ->> 'resultado' from jsonb_array_elements(v_j -> 'solicitudes') e
      where (e ->> 'solicitud_id') = pg_temp.g('s17')::text limit 1), 'no fue candidata'), true);
  end if;
  -- Ronda 4 (P2-4): expectativa INDEPENDIENTE del resultado. S17 (reinversión cuyo origen es un cierre de otra cooperativa)
  -- DEBE rechazarla la continuidad de postventa (P0409 «La inversión de origen no está disponible») y quedar intacta; S18
  -- (upgrade con origen) DEBE cancelarse (la guarda deja pasar upgrade preparada → cancelada antes de mirar el origen); S19
  -- (31 días con memoria idempotente) no debe ser ni candidata. Sin movimiento: S10, S11 y S18 = 3 canceladas; S17 = 1 rechazada.
  v_sm_esperadas := 3;
  v_sm_rech := 1;
  perform pg_temp.exigir('R8-s17-reinversion-rechazada',
    (v_s ->> 'estado') = 'preparada' and (v_s ->> 'cancelacion_motivo') is null
      and (v_s ->> 'actualizado_en')::timestamptz = (select actualizado_en from ensayo_siembra where nombre = 's17')
      and coalesce(current_setting('ensayo.s17_resultado', true), '') like 'rechazada: P0409%',
    'S17 (reinversión con origen de otra cooperativa) tenía que quedar preparada e informada como rechazada (P0409 de la continuidad de postventa): '
      || v_s17 || ' · ' || coalesce(current_setting('ensayo.s17_resultado', true), '-'));
  v_s := pg_temp.sol(pg_temp.g('s18'));
  perform pg_temp.exigir('R8-s18-upgrade-cancelado',
    v_j is not null and (v_s ->> 'estado') = 'cancelada' and (v_s ->> 'cancelacion_motivo') = 'sin_movimiento'
      and (v_s -> 'cancelacion_detalle' ->> 'corrida_id') = (v_j ->> 'corrida_id'),
    'S18 (upgrade con origen, 31 días) tenía que cancelarla la tarea (la continuidad deja pasar upgrade preparada → cancelada): ' || coalesce(v_s ->> 'estado', '?'));
  perform pg_temp.exigir('R8-s19-ni-candidata',
    v_j is not null
      and not exists (select 1 from jsonb_array_elements(v_j -> 'solicitudes') e where (e ->> 'solicitud_id') = pg_temp.g('s19')::text)
      and (pg_temp.sol(pg_temp.g('s19')) ->> 'estado') = 'preparada',
    'S19 (31 días, con memoria idempotente) no tenía que ser ni candidata de la pasada de 30 días (exclusión permanente antes del recorrido)');
  perform pg_temp.exigir('R8-contadores',
    v_j is not null
      and (v_j -> 'numero_contrato_usado' ->> 'canceladas')::integer = 1 and (v_j -> 'numero_contrato_usado' ->> 'rechazadas')::integer = 1
      and (v_j -> 'numero_contrato_usado' ->> 'omitidas')::integer = 0
      and (v_j -> 'sin_movimiento' ->> 'canceladas')::integer = v_sm_esperadas and (v_j -> 'sin_movimiento' ->> 'rechazadas')::integer = v_sm_rech
      and (v_j -> 'sin_movimiento' ->> 'omitidas')::integer = 0,
    format('contadores de la tarea distintos de lo esperado (número usado: 1 cancelada —S14—, 1 rechazada —S8—; sin movimiento: %s canceladas, %s rechazadas; S17 %s): %s',
      v_sm_esperadas, v_sm_rech, v_s17, coalesce(v_res, '?')));
  v_s := pg_temp.sol(pg_temp.g('s14'));
  perform pg_temp.exigir('R8-s14-numero-usado-por-la-tarea',
    (v_s ->> 'estado') = 'cancelada' and (v_s ->> 'cancelacion_motivo') = 'numero_contrato_usado'
      and (v_s -> 'cancelacion_detalle' ->> 'contrato_id') = current_setting('ensayo.ex1_id')
      and (v_s -> 'cancelacion_detalle' ->> 'numero_contrato') = current_setting('ensayo.ex1_num')
      and (v_s -> 'cancelacion_detalle' ->> 'via') = 'tarea'
      and (v_s -> 'cancelacion_detalle' ->> 'corrida_id') = (v_j ->> 'corrida_id'),
    'S14 (número de un contrato ya existente, nacido fuera del alta) tenía que cancelarla la tarea con el contrato EX1 y la vía tarea: ' || coalesce(v_s::text, 'nula'));
  for r in select * from (values ('s10'), ('s11')) as t(n) loop
    v_s := pg_temp.sol(pg_temp.g(r.n));
    perform pg_temp.exigir('R8-' || r.n || '-sin-movimiento',
      (v_s ->> 'estado') = 'cancelada' and (v_s ->> 'cancelacion_motivo') = 'sin_movimiento'
        and (v_s -> 'cancelacion_detalle' ->> 'dias') = '30' and (v_s -> 'cancelacion_detalle') ? 'ultimo_movimiento'
        and (v_s -> 'cancelacion_detalle' ->> 'via') = 'tarea' and (v_s -> 'cancelacion_detalle' ->> 'corrida_id') = (v_j ->> 'corrida_id')
        and (v_s -> 'cancelacion_detalle' ->> 'ultimo_movimiento')::timestamptz = (select actualizado_en from ensayo_siembra where nombre = r.n),
      format('%s (sin movimiento) tenía que quedar cancelada con motivo sin_movimiento, 30 días, último movimiento y corrida: %s', r.n, coalesce(v_s::text, 'nula')));
  end loop;
  for r in select * from ensayo_siembra where nombre in ('s12', 's13', 's15', 's4', 's5', 's6', 's7', 's16', 's8', 's19') order by nombre loop
    v_s := pg_temp.sol(r.id);
    perform pg_temp.exigir('R8-' || r.nombre || '-intacta',
      (v_s ->> 'estado') = r.estado and (v_s ->> 'cancelacion_motivo') is null and (v_s ->> 'actualizado_en')::timestamptz = r.actualizado_en,
      format('%s cambió con la tarea y no debía: estado «%s», motivo «%s»', r.nombre, v_s ->> 'estado', coalesce(v_s ->> 'cancelacion_motivo', 'nulo')));
  end loop;
  perform pg_temp.exigir('R8-s8-rechazada-informada',
    v_j is not null and exists (select 1 from jsonb_array_elements(v_j -> 'solicitudes') e
      where (e ->> 'solicitud_id') = pg_temp.g('s8')::text and (e ->> 'motivo') = 'numero_contrato_usado' and (e ->> 'resultado') like 'rechazada: P0409%'),
    'la tarea tenía que informar a S8 como rechazada (P0409 del disparador) en su lista');
  perform pg_temp.exigir('R8-corrida',
    v_corridas = 0 and v_j is not null and to_regclass('crm.solicitudes_desechadas_corridas') is not null
      and pg_temp.pieza(format($q$select to_jsonb(c) from crm.solicitudes_desechadas_corridas c where c.id = %L::uuid$q$, v_j ->> 'corrida_id')) like 'ok|%'
      and (substr(pg_temp.pieza(format($q$select to_jsonb(c) from crm.solicitudes_desechadas_corridas c where c.id = %L::uuid$q$, v_j ->> 'corrida_id')), 4)::jsonb)
          @> jsonb_build_object('dias', 30, 'limite', 200, 'canceladas_numero_usado', 1, 'canceladas_sin_movimiento', v_sm_esperadas, 'omitidas', 0, 'rechazadas', 1 + v_sm_rech),
    format('la corrida no quedó escrita con sus contadores (corridas antes %s; esperado: número usado 1, sin movimiento %s, omitidas 0, rechazadas %s)', v_corridas, v_sm_esperadas, 1 + v_sm_rech));

  -- ── R9 · Idempotente (ronda 4: con filas completas y auditoría = sin efectos duplicados sobre la misma solicitud) ──────────
  v_filas := (select jsonb_agg(to_jsonb(s) order by s.id) from crm.inversion_solicitudes s where s.id in (select id from ensayo_siembra));
  v_aud_n := (select count(*) from public.audit_log a where a.tabla = 'crm.inversion_solicitudes' and a.fila_id in (select id::text from ensayo_siembra));
  v_res := pg_temp.pieza('select private.solicitudes_desechar_ciclo(now(), 30, 200)');
  v_j := case when v_res like 'ok|%' then substr(v_res, 4)::jsonb end;
  v_corrida2 := (v_j ->> 'corrida_id')::uuid;
  perform pg_temp.exigir('R9-idempotente',
    v_j is not null and (v_j -> 'numero_contrato_usado' ->> 'canceladas')::integer = 0 and (v_j -> 'sin_movimiento' ->> 'canceladas')::integer = 0
      and (v_j -> 'numero_contrato_usado' ->> 'rechazadas')::integer = 1
      and (select count(*) from crm.inversion_solicitudes s where s.id in (select id from ensayo_siembra) and s.estado = 'cancelada') = 7
      and pg_temp.pieza('select count(*)::text::jsonb from crm.solicitudes_desechadas_corridas') = 'ok|2',
    'la segunda corrida tenía que cancelar 0 (S8 otra vez rechazada), dejar la segunda fila de corrida y no mover más solicitudes: ' || coalesce(v_res, '?'));
  perform pg_temp.exigir('R9-filas-completas',
    v_filas = (select jsonb_agg(to_jsonb(s) order by s.id) from crm.inversion_solicitudes s where s.id in (select id from ensayo_siembra))
      and v_aud_n = (select count(*) from public.audit_log a where a.tabla = 'crm.inversion_solicitudes' and a.fila_id in (select id::text from ensayo_siembra)),
    'la segunda corrida cambió alguna fila sembrada o añadió auditoría sobre ellas (efectos duplicados sobre la misma solicitud)');

  -- ── R10 · El texto del asesor para «sin movimiento» ───────────────────────────────────────────────────────────────────────
  v_res := pg_temp.puerta(v_v1, pg_temp.g('s10'));
  v_j := case when v_res like 'ok|%' then substr(v_res, 4)::jsonb end;
  perform pg_temp.exigir('R10-texto-sin-movimiento',
    v_j is not null and (v_j ->> 'cancelacion_texto') = 'El CRM canceló esta solicitud: llevaba 30 días sin confirmarse ni corregirse.',
    'la consulta de S10 no trae el texto de «sin movimiento»: ' || v_res);

  -- ── R12 · El motivo se relee bajo el candado (ronda 3, P2 del auditor): con un detalle que ya no es cierto, la pieza omite ──
  -- (Antes de R11, que cancela S3 a mano; S12 tiene que seguir preparada: K3 la usa para el 23514.)
  -- R12a · S3 lleva N2; se la llama como si llevara N1 (el número del contrato X).
  v_res := pg_temp.pieza(format('select to_jsonb(private.solicitud_desechar(%L::uuid, %L, %L::jsonb))', pg_temp.g('s3'), 'numero_contrato_usado',
    jsonb_build_object('via', 'alta', 'contrato_id', v_x, 'numero_contrato', v_n1)::text));
  v_s := pg_temp.sol(pg_temp.g('s3'));
  perform pg_temp.exigir('R12-numero-releido',
    v_res = 'ok|' || to_jsonb('omitida: el numero cambio bajo el candado'::text)::text
      and (v_s ->> 'estado') = 'preparada' and (v_s ->> 'cancelacion_motivo') is null
      and (v_s ->> 'actualizado_en')::timestamptz = (select actualizado_en from ensayo_siembra where nombre = 's3'),
    'S3 (lleva N2) llamada con el detalle de N1 tenía que quedar omitida («el numero cambio bajo el candado») e intacta: ' || v_res || ' · ' || coalesce(v_s ->> 'estado', '?'));
  -- R12b · S12 (29 días 23 h) como «sin movimiento» con corte = now(): ya no cumple el corte.
  v_res := pg_temp.pieza(format('select to_jsonb(private.solicitud_desechar(%L::uuid, %L, %L::jsonb))', pg_temp.g('s12'), 'sin_movimiento',
    jsonb_build_object('via', 'tarea', 'corrida_id', gen_random_uuid(), 'corte', now(), 'dias', 30,
                       'ultimo_movimiento', (select actualizado_en from ensayo_siembra where nombre = 's12'))::text));
  v_s := pg_temp.sol(pg_temp.g('s12'));
  perform pg_temp.exigir('R12-corte-releido',
    v_res = 'ok|' || to_jsonb('omitida: ya no cumple el corte'::text)::text
      and (v_s ->> 'estado') = 'preparada' and (v_s ->> 'cancelacion_motivo') is null
      and (v_s ->> 'actualizado_en')::timestamptz = (select actualizado_en from ensayo_siembra where nombre = 's12'),
    'S12 (29 días 23 h) llamada como sin movimiento con corte = now() tenía que quedar omitida («ya no cumple el corte») e intacta: ' || v_res || ' · ' || coalesce(v_s ->> 'estado', '?'));
  -- R12c · S12 con un corte que sí cumple (now() + 10 días) pero un último movimiento observado que no es el suyo: se movió.
  v_res := pg_temp.pieza(format('select to_jsonb(private.solicitud_desechar(%L::uuid, %L, %L::jsonb))', pg_temp.g('s12'), 'sin_movimiento',
    jsonb_build_object('via', 'tarea', 'corrida_id', gen_random_uuid(), 'corte', now() + interval '10 days', 'dias', 30,
                       'ultimo_movimiento', (select actualizado_en - interval '1 day' from ensayo_siembra where nombre = 's12'))::text));
  v_s := pg_temp.sol(pg_temp.g('s12'));
  perform pg_temp.exigir('R12-movimiento-releido',
    v_res = 'ok|' || to_jsonb('omitida: se movio bajo el candado'::text)::text
      and (v_s ->> 'estado') = 'preparada' and (v_s ->> 'cancelacion_motivo') is null
      and (v_s ->> 'actualizado_en')::timestamptz = (select actualizado_en from ensayo_siembra where nombre = 's12'),
    'S12 llamada con un último movimiento observado distinto del suyo tenía que quedar omitida («se movio bajo el candado») e intacta: ' || v_res || ' · ' || coalesce(v_s ->> 'estado', '?'));
  -- R12d · Control positivo: con el corte cumplido y su último movimiento exacto, la pieza SÍ cancela; se deshace en una
  --        subtransacción (la excepción P0999 revierte el bloque entero) y S12 vuelve a preparada.
  begin
    v_res := pg_temp.pieza(format('select to_jsonb(private.solicitud_desechar(%L::uuid, %L, %L::jsonb))', pg_temp.g('s12'), 'sin_movimiento',
      jsonb_build_object('via', 'tarea', 'corrida_id', gen_random_uuid(), 'corte', now() + interval '10 days', 'dias', 30,
                         'ultimo_movimiento', (select actualizado_en from ensayo_siembra where nombre = 's12'))::text));
    v_s := pg_temp.sol(pg_temp.g('s12'));
    raise exception using errcode = 'P0999',
      message = v_res || ' · ' || coalesce(v_s ->> 'estado', '?') || '/' || coalesce(v_s ->> 'cancelacion_motivo', '-');
  exception when sqlstate 'P0999' then
    v_res := sqlerrm;
  end;
  perform pg_temp.exigir('R12-control-positivo',
    v_res = 'ok|' || to_jsonb('cancelada'::text)::text || ' · cancelada/sin_movimiento',
    'el control positivo (S12 con el corte cumplido y su último movimiento exacto) tenía que cancelar: ' || v_res);
  v_s := pg_temp.sol(pg_temp.g('s12'));
  perform pg_temp.exigir('R12-control-deshecho',
    (v_s ->> 'estado') = 'preparada' and (v_s ->> 'cancelacion_motivo') is null
      and (v_s ->> 'actualizado_en')::timestamptz = (select actualizado_en from ensayo_siembra where nombre = 's12'),
    'S12 tenía que volver a preparada al deshacer el control positivo: ' || coalesce(v_s ->> 'estado', '?'));

  -- ── R13 · El CONTRATO del motivo se relee bajo candado (ronda 4, P2-1) ───────────────────────────────────────────────────
  -- S3 lleva N2: el número coincide con el detalle, pero el contrato X del detalle lleva N1 → la pieza omite y no toca.
  v_res := pg_temp.pieza(format('select to_jsonb(private.solicitud_desechar(%L::uuid, %L, %L::jsonb))', pg_temp.g('s3'), 'numero_contrato_usado',
    jsonb_build_object('via', 'alta', 'contrato_id', v_x, 'numero_contrato', current_setting('ensayo.n2'))::text));
  v_s := pg_temp.sol(pg_temp.g('s3'));
  perform pg_temp.exigir('R13-contrato-releido',
    v_res = 'ok|' || to_jsonb('omitida: el contrato ya no lleva ese numero'::text)::text
      and (v_s ->> 'estado') = 'preparada' and (v_s ->> 'cancelacion_motivo') is null
      and (v_s ->> 'actualizado_en')::timestamptz = (select actualizado_en from ensayo_siembra where nombre = 's3'),
    'S3 (N2) con un detalle cuyo contrato X lleva N1 tenía que quedar omitida («el contrato ya no lleva ese numero») e intacta: ' || v_res || ' · ' || coalesce(v_s ->> 'estado', '?'));
  -- El contrato del detalle ya no existe (eliminado entre la selección y el candado).
  v_res := pg_temp.pieza(format('select to_jsonb(private.solicitud_desechar(%L::uuid, %L, %L::jsonb))', pg_temp.g('s3'), 'numero_contrato_usado',
    jsonb_build_object('via', 'alta', 'contrato_id', gen_random_uuid(), 'numero_contrato', current_setting('ensayo.n2'))::text));
  v_s := pg_temp.sol(pg_temp.g('s3'));
  perform pg_temp.exigir('R13-contrato-inexistente',
    v_res = 'ok|' || to_jsonb('omitida: el contrato ya no existe'::text)::text
      and (v_s ->> 'estado') = 'preparada' and (v_s ->> 'cancelacion_motivo') is null,
    'S3 con un detalle cuyo contrato no existe tenía que quedar omitida («el contrato ya no existe») e intacta: ' || v_res || ' · ' || coalesce(v_s ->> 'estado', '?'));

  -- ── R11 · La cancelación de la pantalla sigue igual (sin motivo) ──────────────────────────────────────────────────────────
  v_res := pg_temp.cancelar_a_mano(v_v1, pg_temp.g('s3'), 0);
  v_s := pg_temp.sol(pg_temp.g('s3'));
  perform pg_temp.exigir('R11-cancelar-a-mano',
    v_res like 'ok|%' and (v_s ->> 'estado') = 'cancelada' and (v_s ->> 'cancelacion_motivo') is null and (v_s ->> 'cancelacion_detalle') is null,
    'la cancelación de la pantalla de S3 como V1 tenía que seguir funcionando y dejar el motivo nulo: ' || v_res || ' · ' || coalesce(v_s ->> 'estado', '?'));

  -- ── R14 · Presupuesto ÚNICO de 200 cancelaciones por corrida (ronda 4, P2-2) ─────────────────────────────────────────────
  -- En una subtransacción que SIEMPRE se deshace (P0999): 3 preparadas de Avance con el número de EX1 (pasada «número usado»)
  -- y 250 preparadas de 31 días sin número (pasada «30 días»). Corrida A: 3 + 197 = 200 exactas; B: 0 + 53; C: 0 + 0.
  begin
    for v_n in 1..3 loop
      perform pg_temp.sembrar('v14n' || v_n, 'avance', current_setting('ensayo.ex1_num'), 'preparada', interval '1 day' + make_interval(secs => v_n));
    end loop;
    for v_n in 1..250 loop
      perform pg_temp.sembrar('v14s' || v_n, 'prodelco', null, 'preparada', interval '31 days' + make_interval(secs => v_n));
    end loop;
    v_res := pg_temp.pieza('select private.solicitudes_desechar_ciclo(now(), 30, 200)');
    v_j := case when v_res like 'ok|%' then substr(v_res, 4)::jsonb else jsonb_build_object('error', v_res) end;
    v_res := pg_temp.pieza('select private.solicitudes_desechar_ciclo(now(), 30, 200)');
    v_j2 := case when v_res like 'ok|%' then substr(v_res, 4)::jsonb else jsonb_build_object('error', v_res) end;
    v_res := pg_temp.pieza('select private.solicitudes_desechar_ciclo(now(), 30, 200)');
    v_j3 := case when v_res like 'ok|%' then substr(v_res, 4)::jsonb else jsonb_build_object('error', v_res) end;
    raise exception using errcode = 'P0999', message = jsonb_build_object(
      'a_nu', v_j -> 'numero_contrato_usado' ->> 'canceladas', 'a_sm', v_j -> 'sin_movimiento' ->> 'canceladas',
      'b_nu', v_j2 -> 'numero_contrato_usado' ->> 'canceladas', 'b_sm', v_j2 -> 'sin_movimiento' ->> 'canceladas',
      'c_nu', v_j3 -> 'numero_contrato_usado' ->> 'canceladas', 'c_sm', v_j3 -> 'sin_movimiento' ->> 'canceladas',
      'a_limite', v_j ->> 'limite', 'error', coalesce(v_j ->> 'error', v_j2 ->> 'error', v_j3 ->> 'error'))::text;
  exception when sqlstate 'P0999' then
    v_j := sqlerrm::jsonb;
  end;
  perform pg_temp.exigir('R14-presupuesto-corrida-a',
    (v_j ->> 'a_nu')::integer = 3 and (v_j ->> 'a_sm')::integer = 197 and (v_j ->> 'a_limite')::integer = 200,
    'la corrida A tenía que cancelar exactamente 200 (3 por número usado + 197 sin movimiento): ' || v_j::text);
  perform pg_temp.exigir('R14-presupuesto-corridas-b-c',
    (v_j ->> 'b_nu')::integer = 0 and (v_j ->> 'b_sm')::integer = 53 and (v_j ->> 'c_nu')::integer = 0 and (v_j ->> 'c_sm')::integer = 0,
    'la corrida B tenía que cancelar las 53 restantes y la C ninguna: ' || v_j::text);
  perform pg_temp.exigir('R14-deshecho',
    (select count(*) from ensayo_siembra where nombre like 'v14%') = 0
      and pg_temp.pieza('select count(*)::text::jsonb from crm.solicitudes_desechadas_corridas') = 'ok|2',
    'la siembra de volumen de R14 tenía que deshacerse entera (siembra y corridas)');

  -- ── R15 · Progreso: las rechazadas no tapan a una candidata válida (ronda 4, P2-3) ───────────────────────────────────────
  -- 205 preparadas de 32 días que el disparador de ensayo rechaza (prefijo del recorrido) + 1 válida de 31 días detrás.
  begin
    for v_n in 1..205 loop
      perform pg_temp.sembrar('v15r' || v_n, 'prodelco', null, 'preparada', interval '32 days' + make_interval(secs => v_n), false, null, true);
    end loop;
    perform pg_temp.sembrar('v15ok', 'prodelco', null, 'preparada', interval '31 days 1 second');
    v_res := pg_temp.pieza('select private.solicitudes_desechar_ciclo(now(), 30, 200)');
    v_j := case when v_res like 'ok|%' then substr(v_res, 4)::jsonb else jsonb_build_object('error', v_res) end;
    v_s := pg_temp.sol(pg_temp.g('v15ok'));
    v_res := pg_temp.pieza('select private.solicitudes_desechar_ciclo(now(), 30, 200)');
    v_j2 := case when v_res like 'ok|%' then substr(v_res, 4)::jsonb else jsonb_build_object('error', v_res) end;
    raise exception using errcode = 'P0999', message = jsonb_build_object(
      'a_sm', v_j -> 'sin_movimiento' ->> 'canceladas', 'a_rech', v_j -> 'sin_movimiento' ->> 'rechazadas',
      'ok_estado', v_s ->> 'estado', 'ok_motivo', v_s ->> 'cancelacion_motivo', 'ok_corrida', v_s -> 'cancelacion_detalle' ->> 'corrida_id',
      'a_corrida', v_j ->> 'corrida_id', 'b_sm', v_j2 -> 'sin_movimiento' ->> 'canceladas', 'b_rech', v_j2 -> 'sin_movimiento' ->> 'rechazadas',
      'error', coalesce(v_j ->> 'error', v_j2 ->> 'error'))::text;
  exception when sqlstate 'P0999' then
    v_j := sqlerrm::jsonb;
  end;
  perform pg_temp.exigir('R15-progreso-corrida-a',
    (v_j ->> 'a_sm')::integer = 1 and (v_j ->> 'a_rech')::integer >= 205
      and (v_j ->> 'ok_estado') = 'cancelada' and (v_j ->> 'ok_motivo') = 'sin_movimiento' and (v_j ->> 'ok_corrida') = (v_j ->> 'a_corrida'),
    'con 205 rechazadas delante, la candidata válida tenía que cancelarse en la PRIMERA corrida (las rechazadas no consumen presupuesto): ' || v_j::text);
  perform pg_temp.exigir('R15-progreso-corrida-b',
    (v_j ->> 'b_sm')::integer = 0 and (v_j ->> 'b_rech')::integer >= 205,
    'la segunda corrida no tenía que cancelar nada más (y volver a informar las rechazadas): ' || v_j::text);
  perform pg_temp.exigir('R15-deshecho',
    (select count(*) from ensayo_siembra where nombre like 'v15%') = 0
      and pg_temp.pieza('select count(*)::text::jsonb from crm.solicitudes_desechadas_corridas') = 'ok|2',
    'la siembra de volumen de R15 tenía que deshacerse entera (siembra y corridas)');

  -- ── K1 · Las piezas ───────────────────────────────────────────────────────────────────────────────────────────────────────
  v_det := null;
  for v_h in
    select * from (values
      ('private.solicitud_desechar(uuid,text,jsonb)', 'postgres|false|v|u|search_path=""|postgres:EXECUTE:false'),
      ('private.solicitudes_desechar_por_contrato(uuid)', 'postgres|false|v|u|search_path=""|postgres:EXECUTE:false'),
      ('private.solicitudes_desechar_ciclo(timestamp with time zone,integer,integer)', 'postgres|false|v|u|search_path="";lock_timeout=10s|postgres:EXECUTE:false'),
      ('private.solicitud_cancelacion_vista(uuid)', 'postgres|false|s|u|search_path=""|postgres:EXECUTE:false')
    ) as h(firma, ficha)
  loop
    v_ficha := pg_temp.ficha(v_h.firma);
    if v_ficha is distinct from v_h.ficha then
      v_det := coalesce(v_det || '; ', '') || v_h.firma || ' → ' || coalesce(v_ficha, 'no existe');
    end if;
    if to_regprocedure(v_h.firma) is not null and (
         has_function_privilege('anon', v_h.firma, 'EXECUTE') or has_function_privilege('authenticated', v_h.firma, 'EXECUTE')
         or has_function_privilege('service_role', v_h.firma, 'EXECUTE')) then
      v_det := coalesce(v_det || '; ', '') || v_h.firma || ' tiene EXECUTE para un rol de la API';
    end if;
  end loop;
  perform pg_temp.exigir('K1-piezas-ficha', v_det is null, 'las piezas no tienen la ficha prevista: ' || coalesce(v_det, ''));

  -- ── K2 · Las dos puertas ──────────────────────────────────────────────────────────────────────────────────────────────────
  perform pg_temp.exigir('K2-alta-llama-a-la-pieza',
    (select cardinality(string_to_array(p.prosrc, 'perform private.solicitudes_desechar_por_contrato(v_contrato_id);')) = 2
       from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure)
      and pg_temp.ficha('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)') = 'postgres|true|v|u|search_path=""|authenticated:EXECUTE:false,postgres:EXECUTE:false'
      and coalesce(obj_description('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure, 'pg_proc'), '') like '%Bloque 2.15%',
    'el alta v2 no llama exactamente una vez a private.solicitudes_desechar_por_contrato(v_contrato_id), o cambió su ficha, o no lleva el comentario del bloque');
  perform pg_temp.exigir('K2-consulta-con-vista',
    (select cardinality(string_to_array(p.prosrc, '||private.solicitud_cancelacion_vista(p_solicitud);')) = 2
       from pg_proc p where p.oid = 'crm.solicitud_inversion_fn(uuid)'::regprocedure)
      and pg_temp.ficha('crm.solicitud_inversion_fn(uuid)') = 'postgres|true|v|u|search_path="";lock_timeout=5s|authenticated:EXECUTE:false,postgres:EXECUTE:false'
      and coalesce(obj_description('crm.solicitud_inversion_fn(uuid)'::regprocedure, 'pg_proc'), '') like '%Bloque 2.15%',
    'la consulta no añade exactamente una vez private.solicitud_cancelacion_vista(p_solicitud), o cambió su ficha, o no lleva el comentario del bloque');

  -- ── K3 · Columnas, CHECK, tabla de corridas y la regla de auditoría ───────────────────────────────────────────────────────
  perform pg_temp.exigir('K3-columnas-y-check',
    (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attname)
       from pg_attribute a where a.attrelid = 'crm.inversion_solicitudes'::regclass and a.attnum > 0 and not a.attisdropped
        and a.attname in ('cancelacion_motivo', 'cancelacion_detalle')) = 'cancelacion_detalle:jsonb,cancelacion_motivo:text'
      and exists (select 1 from pg_constraint c where c.conrelid = 'crm.inversion_solicitudes'::regclass and c.conname = 'inversion_solicitud_cancelacion_coherente')
      and exists (select 1 from pg_constraint c where c.conrelid = 'crm.inversion_solicitudes'::regclass and c.conname = 'inversion_solicitud_cancelacion_motivo_valido')
      and pg_temp.pieza($q$with u as (update crm.inversion_solicitudes set cancelacion_motivo = 'sin_movimiento' where id = current_setting('ensayo.s12')::uuid returning 1) select to_jsonb(count(*)) from u$q$) like '23514|%',
    'faltan las columnas cancelacion_motivo/cancelacion_detalle o sus CHECK (un motivo sobre una preparada tiene que morir con 23514)');
  -- K7 (ronda 3, D-80) · La consulta de runbook con la que el Director lee la última corrida (solo lectura; texto idéntico al
  --     del registro) funciona y trae los contadores y las «rechazadas» de la segunda corrida (S8 y, si la continuidad la
  --     rechazó, S17).
  v_res := pg_temp.pieza($q$select to_jsonb(x) from (
    select c.id, c.creado_en, c.corte, c.dias, c.limite, c.canceladas_numero_usado, c.canceladas_sin_movimiento, c.omitidas, c.rechazadas, c.duracion_ms,
           (select jsonb_agg(e) from jsonb_array_elements(c.detalle) e where e ->> 'resultado' like 'rechazada:%') as rechazadas_detalle
      from crm.solicitudes_desechadas_corridas c
     order by c.creado_en desc
     limit 1) x$q$);
  v_j := case when v_res like 'ok|%' then substr(v_res, 4)::jsonb end;
  perform pg_temp.exigir('K7-consulta-runbook',
    v_j is not null and (v_j ->> 'id') = v_corrida2::text
      and (v_j ->> 'rechazadas')::integer = 1 + v_sm_rech and (v_j ->> 'canceladas_numero_usado')::integer = 0
      and (v_j ->> 'canceladas_sin_movimiento')::integer = 0
      and exists (select 1 from jsonb_array_elements(v_j -> 'rechazadas_detalle') e where (e ->> 'solicitud_id') = pg_temp.g('s8')::text),
    'la consulta de runbook de la última corrida tenía que traer rechazadas = ' || (1 + v_sm_rech) || ' (S8 entre ellas) y 0 canceladas: ' || coalesce(v_res, '?'));
  perform pg_temp.exigir('K3-tabla-corridas',
    to_regclass('crm.solicitudes_desechadas_corridas') is not null
      and exists (select 1 from pg_class c where c.oid = to_regclass('crm.solicitudes_desechadas_corridas') and c.relowner = 'postgres'::regrole::oid and c.relrowsecurity)
      and not exists (select 1 from pg_class c cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
                       where c.oid = to_regclass('crm.solicitudes_desechadas_corridas') and a.grantee <> 'postgres'::regrole::oid)
      and not exists (select 1 from information_schema.role_table_grants g where g.table_schema = 'crm' and g.table_name = 'solicitudes_desechadas_corridas' and g.grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC'))
      and not exists (select 1 from private.tablas_sin_rastro() t where t.tabla = 'crm.solicitudes_desechadas_corridas')
      and (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = to_regclass('crm.solicitudes_desechadas_corridas') and t.tgname = 'trg_audit_solicitudes_desechadas_corridas')
          = 'CREATE TRIGGER trg_audit_solicitudes_desechadas_corridas AFTER INSERT OR DELETE OR UPDATE ON crm.solicitudes_desechadas_corridas FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm()',
    'la tabla de corridas no existe, o no tiene RLS, o tiene grants para la API, o su auditor no es completo (la regla de auditoría la listaría)');
  begin
    perform private.assert_auditoria();
    v_aud := 'pasa';
  exception when others then
    v_aud := 'cae: ' || sqlstate || ' ' || sqlerrm;
  end;
  perform pg_temp.exigir('K3-trinquete-auditoria-idem',
    v_aud = current_setting('ensayo.antes.auditoria'),
    format('private.assert_auditoria() cambió con la migración (antes «%s», ahora «%s»)', left(current_setting('ensayo.antes.auditoria'), 200), left(v_aud, 200)));

  -- ── K4 · El reloj ─────────────────────────────────────────────────────────────────────────────────────────────────────────
  perform pg_temp.exigir('K4-cron',
    to_regclass('cron.job') is not null and (select count(*) from cron.job j where j.jobname = 'crm-solicitudes-desechar' and j.active
      and j.schedule = '17 7 * * *' and j.command = 'select private.solicitudes_desechar_ciclo()') = 1,
    'no hay exactamente un job activo crm-solicitudes-desechar con «17 7 * * *» y «select private.solicitudes_desechar_ciclo()»');

  -- ── K5 · Lo que no se toca, intacto; F7 pasa ──────────────────────────────────────────────────────────────────────────────
  perform pg_temp.exigir('K5-intactas',
    (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.cancelar_solicitud_inversion_fn(uuid,integer)')) = '5e92b8ef8c54b160578463932c1eca1a'
      and (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.confirmar_inversion_revisada_fn(uuid,integer)')) = 'ef53419d436583b116ff68e5a1509855'
      and (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)')) = '3977f1ab0fd4a134c58cf8edd5556ae6'
      and (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.inversion_solicitud_resultado(uuid,jsonb)')) = '26dac93e46ffd7b2b9d12691c7905790',
    'cambió cancelar, confirmar, corregir o el resultado público de la solicitud');
  begin
    v_f7 := private.assert_f7_piezas_cerradas();
  exception when others then
    v_f7 := 'cae: ' || sqlstate || ' ' || sqlerrm;
  end;
  perform pg_temp.exigir('K5-f7-pasa', v_f7 like 'OK:%', 'private.assert_f7_piezas_cerradas() no pasa tras la migración: ' || v_f7);

  -- ── Medidas (no juzgan: documentan) ───────────────────────────────────────────────────────────────────────────────────────
  perform pg_temp.medir(format('medida actores: V1=%s · C1=%s · I1=%s · N1=%s · EX1=%s · EX2=%s · contrato X=%s',
    v_v1, v_c1, pg_temp.g('i1'), v_n1, current_setting('ensayo.ex1_num'), current_setting('ensayo.ex2_num'), coalesce(v_x::text, '-')));
  perform pg_temp.medir(format('medida S17 (origen de reinversión, 31 días): %s · lo que informó la tarea: %s', v_s17,
    coalesce(current_setting('ensayo.s17_resultado', true), '-')));
  perform pg_temp.medir(format('medida huellas: alta v2 antes %s · después %s · consulta antes %s · después %s',
    current_setting('ensayo.antes.pdf_v2'), (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure),
    current_setting('ensayo.antes.consulta'), (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.solicitud_inversion_fn(uuid)'::regprocedure)));
  perform pg_temp.medir(format('medida definiciones: alta v2 %s · consulta %s',
    (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure),
    (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'crm.solicitud_inversion_fn(uuid)'::regprocedure)));
  perform pg_temp.medir(format('medida auditoría antes: %s', left(current_setting('ensayo.antes.auditoria'), 160)));
  -- Para la reversa (ronda 4, P2-5): las definiciones exactas de las cuatro piezas y la forma de la tabla y las columnas que
  -- deja la migración (la reversa las fija y se niega si cambiaron).
  perform pg_temp.medir(format('medida piezas (md5 definición): desechar %s · por_contrato %s · ciclo %s · vista %s',
    (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.solicitud_desechar(uuid,text,jsonb)')),
    (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.solicitudes_desechar_por_contrato(uuid)')),
    (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.solicitudes_desechar_ciclo(timestamp with time zone,integer,integer)')),
    (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure('private.solicitud_cancelacion_vista(uuid)'))));
  -- Ronda 5 (Codex r2, P2): la FICHA COMPLETA de la tabla de corridas (dueño, RLS, ACL, columnas con default, TODAS las
  -- restricciones, índices, disparadores, políticas, comentarios de tabla y columnas) y la de las dos columnas nuevas (tipo,
  -- nulabilidad, default, comentario). La reversa las fija con esta misma expresión.
  perform pg_temp.medir(format('medida ficha tabla «%s»',
    (select 'dueno=' || c.relowner::regrole::text || '|rls=' || c.relrowsecurity::text || '/' || c.relforcerowsecurity::text || '|acl=' || coalesce(c.relacl::text, '-')
       || '|cols=' || coalesce((select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '-'), ',' order by a.attnum)
                                  from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
                                 where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped), '-')
       || '|cons=' || coalesce((select string_agg(x.conname || ':' || pg_get_constraintdef(x.oid), ';' order by x.conname) from pg_constraint x where x.conrelid = c.oid), '-')
       || '|idx=' || coalesce((select string_agg(pg_get_indexdef(i.indexrelid), ';' order by i.indexrelid::regclass::text) from pg_index i where i.indrelid = c.oid), '-')
       || '|trg=' || coalesce((select string_agg(pg_get_triggerdef(t.oid) || '|' || t.tgenabled::text, ';' order by t.tgname) from pg_trigger t where t.tgrelid = c.oid and not t.tgisinternal), '-')
       || '|pol=' || coalesce((select string_agg(p.polname || ':' || p.polcmd::text || ':' || coalesce((select string_agg(rl.rolname, ',' order by rl.rolname) from pg_roles rl where rl.oid = any (p.polroles)), 'public')
                                                 || ':' || coalesce(pg_get_expr(p.polqual, p.polrelid), '-') || ':' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '-'), ';' order by p.polname)
                                  from pg_policy p where p.polrelid = c.oid), '-')
       || '|com=' || coalesce(obj_description(c.oid, 'pg_class'), '-')
       || '|colcom=' || coalesce((select string_agg(a.attname || ':' || coalesce(col_description(c.oid, a.attnum), '-'), ',' order by a.attnum)
                                    from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped), '-')
       from pg_class c where c.oid = to_regclass('crm.solicitudes_desechadas_corridas'))));
  perform pg_temp.medir(format('medida ficha columnas «%s»',
    (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '-') || ':' || coalesce(col_description(a.attrelid, a.attnum), '-'), ',' order by a.attname)
       from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
      where a.attrelid = 'crm.inversion_solicitudes'::regclass and a.attnum > 0 and not a.attisdropped and a.attname in ('cancelacion_motivo', 'cancelacion_detalle'))));
  perform pg_temp.medir(format('medida forma: tabla «%s» · columnas «%s» · checks «%s»',
    (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text, ',' order by a.attnum)
       from pg_attribute a where a.attrelid = to_regclass('crm.solicitudes_desechadas_corridas') and a.attnum > 0 and not a.attisdropped),
    (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text, ',' order by a.attname)
       from pg_attribute a where a.attrelid = 'crm.inversion_solicitudes'::regclass and a.attnum > 0 and not a.attisdropped
        and a.attname in ('cancelacion_motivo', 'cancelacion_detalle')),
    (select string_agg(c.conname || ':' || pg_get_constraintdef(c.oid), ';' order by c.conname) from pg_constraint c
       where c.conrelid = 'crm.inversion_solicitudes'::regclass and c.conname like 'inversion_solicitud_cancelacion_%')));

  -- ── K6 · Lo diferido se comprueba AHORA, no en un COMMIT que nunca llega ──────────────────────────────────────────────────
  begin
    set constraints all immediate;
    perform pg_temp.reg('K6-commit-diferido', '');
  exception when others then
    perform pg_temp.reg('K6', format(E'FALLO K6-commit-diferido: algo de lo sembrado o creado no sobreviviría al COMMIT (%s %s)\n', sqlstate, sqlerrm));
  end;

  -- ── Veredicto, y rollback SIEMPRE ─────────────────────────────────────────────────────────────────────────────────────────
  raise exception E'ENSAYO %:\n%\n%\n%(rollback a propósito — nada queda escrito)',
    case when coalesce(nullif(current_setting('ensayo.fallos', true), ''), '0')::integer = 0 then 'VERDE — 0 fallos'
         else format('ROJO — %s fallo(s)', current_setting('ensayo.fallos')) end,
    coalesce(current_setting('ensayo.informe', true), ''),
    coalesce(current_setting('ensayo.medidas', true), ''),
    coalesce(current_setting('ensayo.oks', true), '');
end;
$ensayo$;
