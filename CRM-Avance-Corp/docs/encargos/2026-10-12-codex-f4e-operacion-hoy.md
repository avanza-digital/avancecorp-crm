# Encargo a Codex (SECONDARY_REVIEWER) — F4-e: la operación de hoy para supervisión y gerencia (decimotercera)

ROLE: SECONDARY_REVIEWER.
- NO editas, NO implementas, NO commiteas y NO invocas a otro agente. Solo revisas y devuelves hallazgos con evidencia
  (archivo, línea, fragmento).
- No ves la base ni la red: todo lo que debes juzgar va transcrito aquí.
- Riesgo LEVEL 3 (función `security definer` con control de rol, lecturas de datos de leads). Ronda r1. En español.
- Formato de respuesta: `VEREDICTO: PASS | CHANGES_REQUESTED` y una lista numerada de hallazgos con prioridad
  (P0 bloquea, P1 corrige antes de aplicar, P2 conviene, P3 nota), cada uno con la evidencia y la corrección propuesta.
  Sin hallazgo sin evidencia.

## Contexto (resumen)

Plan «Llamadas desde el celular» (CRM Avance Corp), tarea F6.3.1 / F4-e. Miguel aprobó las definiciones D1–D5 y la
sección 9 del contrato `docs/plans/llamadas-celular/F4E-CONTRATO.md` (10/10 y 12/10/2026). La migración añade una
puerta de SOLO LECTURA que devuelve, para hoy en Lima, las cifras de llamadas del celular por analista y por equipo,
más la salud de los celulares, sin números, leads, ids de evento ni horas exactas. Doce migraciones anteriores ya están
en producción; esta no está aplicada en ningún sitio.

Reglas de la casa que debes contrastar:
- Capas: núcleo INVOKER en `private` sin EXECUTE para nadie; puerta DEFINER en `crm` con `set search_path = ''`,
  EXECUTE solo para `authenticated`, rol y ámbito resueltos en el servidor (`private.llamadas_celular_actor`).
- D4: las cifras de un analista no dependen de quién pregunta (nada de `llamada_celular_visible` ni de la atención
  efectiva por fila). Gerencia usa el roster del pulso (claves de «Actividad del día»); supervisión su subárbol.
- Privacidad: ninguna clave `numero`, `lead_id`, `evento_id`, horas de latido; ningún valor con 7+ dígitos.
- Tres relojes: llamadas de hoy por el momento de la llamada (D2: `recibido_en` si `ocurrio_en` falta o va >5 min por
  delante), resultados de hoy por `actividades.creado_en` (A2), pendientes como foto de ahora dentro de la retención
  (D5) con las deshechas sin corregir aparte y sin tope.

## Qué te pido revisar

1. Seguridad de la puerta DEFINER: ¿puede un vendedor, coordinador, directorio o anon leer algo? ¿Puede un supervisor
   ver otro equipo pasando `p_supervisor_id`? ¿Revela la puerta si un id existe?
2. Corrección de las seis cubetas (disjuntas, suman el total) y de los tres relojes frente al contrato.
3. Rendimiento: una sola pasada por eventos acotada por recepción; el prefiltro `en.actualizado_en >= v_desde` en
   `resultados_hoy` (invariante: un enlace nunca es anterior a su actividad). ¿Hay un caso en que pierda un resultado?
4. La reversa y el registrador (idempotencia, se niegan fuera de orden).
5. Cualquier salto de capa, `when others`, secreto o dato personal que salga.

Verificación hecha por el PRIMARY (Claude) en esta máquina: banco reducido local (`npm run test:llamadas:local`,
pasada 19, 453/453 PASS) con el oráculo O1–O17 y los 25 mutantes de abajo, todos cazados; el gate `test-rls.mjs` y los advisors NO se corrieron aquí
(no hay base Supabase en esta máquina). Resultado detallado en `supabase/migrations/MIGRACIONES.md`.

## Mutantes que el banco local hace morir (nombre → regla)

(se transcriben desde `supabase/scripts/test-llamadas-celular-local.mjs`, `MUTANTES_OPERACION`)
- la supervisión ve analistas de otro equipo (O3)
- otro supervisor como id no se rechaza (O2)
- gerencia con un id que no es supervisor activo no se rechaza (O2)
- el núcleo acepta un actor distinto del autenticado (O1)
- el supervisor ve a un vendedor dado de baja a medias (perfil inactivo)
- gerencia con un supervisor como id ve toda la operación (O2)
- la puerta y el núcleo dejan pasar a los analistas (O1)
- sin el filtro de dirección: las entrantes cuentan (O12)
- los leads de baja cuentan (O11, A4)
- los resultados de hoy por la fecha del enlace y no de la actividad (O8, A2)
- las deshechas cuentan como «con resultado» (O9)
- las deshechas quedan fuera de toda cubeta (O9, O15)
- un resultado deshecho sigue contando como resultado de hoy (O9)
- la ventana del día en UTC (O6)
- un porcentaje de cohortes distintas viaja en el jsonb (O14, O15)
- la cohorte acota la recepción desde hoy en vez de desde ayer (O6)
- D2: manda siempre la hora del celular, aunque vaya adelantada (O16)
- pendientes sin mirar si el lead sigue abierto y contactable (O11)
- pendientes sin tope de retención (O16, D5)
- «de hoy» y «anteriores» intercambiados (O4)
- «sin dato» sin mirar el latido (O13, D1)
- un celular sin latido vale como al día para «sin dato» (O13)
- las cifras según quién pregunta (D4)
- la puerta INVOKER
- el núcleo con EXECUTE para authenticated

## Migración `supabase/migrations/20261012192500_crm_llamadas_celular_operacion_hoy.sql` (transcrita tal cual, con los tres P3 de auditor-rls ya aplicados)

```sql
-- Llamadas desde el celular · decimotercera migración (F4-e, tarea F6.3.1): la operación de hoy para supervisión y
-- gerencia. Contrato aprobado: docs/plans/llamadas-celular/F4E-CONTRATO.md (D1–D5 el 10/10/2026, sección 9 el
-- 12/10/2026; decisiones de Miguel en los PR #249 y #251).
--
-- Qué hace: una puerta de SOLO LECTURA que devuelve, para «hoy» en Lima, las cifras de llamadas del celular por
-- analista y por equipo, más la salud de los celulares, sin números, leads ni horas exactas. Tres relojes, cada uno
-- con su rótulo dentro del jsonb (condición de Miguel: cada cifra dice qué fecha usa):
--   · llamadas_hoy   — cohorte por el MOMENTO DE LA LLAMADA (ocurrio_en; recibido_en si falta o el reloj del celular
--                      va más de 5 min por delante, D2), repartida en seis cubetas disjuntas que suman el total.
--   · resultados_hoy — cohorte por la FECHA DE LA ACTIVIDAD registrada (A2), partida por la vía del enlace.
--   · pendientes     — foto de ahora dentro de la retención (lo sin enlace caduca con la purga, D5); las deshechas sin
--                      corregir aparte y sin tope (la purga no las toca).
-- Atribución a quien marcó (eventos.analista_id, A1); leads de baja no cuentan (A4); lead cerrado después → «ya no
-- piden resultado» (A5); salud de la undécima con sus 7 h (A6); el celular del supervisor va aparte (A7).
-- Ámbito: gerencia con el roster del pulso (mismas claves de equipo que «Actividad del día»; opcionalmente un
-- supervisor activo), supervisión con su subárbol bajo su propio id. Regla D4: las cifras de un analista no dependen
-- de quién pregunta; solo cambia la composición del equipo.
--
-- Capas: núcleo INVOKER en private sin EXECUTE para nadie; puerta DEFINER en crm con EXECUTE solo para authenticated
-- y control de rol por private.llamadas_celular_actor (supervisor y gerencia; los demás, 42501). Sin tablas, sin RLS
-- nuevo, sin índices (los existentes bastan: ver §7 del contrato; el EXPLAIN sobre el banco de Miguel decide).
-- Single-tenant (F2.3.3). La puerta no escribe nada.
-- Reversión: ../scripts/llamadas-celular/reversa-operacion-hoy.sql (drop de las dos funciones; sin datos que conservar).
-- Verificación: npm run test:llamadas:local (pasada 19: oráculo oraculo-operacion-hoy.sql, O1–O17, y sus mutantes).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('private.llamada_celular_contacto_admitido(uuid,text[])') is null then
    raise exception 'LLAMADAS_OPERACION_HOY: falta la duodécima (20261006162813)';
  end if;
  if to_regprocedure('private.celulares_salud_listar(uuid)') is null then
    raise exception 'LLAMADAS_OPERACION_HOY: falta la quinta (20261005143843)';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.celulares_salud_listar(uuid)'::regprocedure), 'estado_latido') = 0 then
    raise exception 'LLAMADAS_OPERACION_HOY: falta la undécima (20261006150254)';
  end if;
  if to_regprocedure('private.gestion_diaria_pulso_roster()') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('private.persona_vetada(uuid)') is null
     or to_regprocedure('private.llamadas_celular_actor(text[])') is null then
    raise exception 'LLAMADAS_OPERACION_HOY: faltan dependencias (roster del pulso, ámbito, veto o actor de llamadas)';
  end if;
  if to_regprocedure('crm.llamadas_celular_operacion_hoy_fn(uuid)') is not null
     or to_regprocedure('private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz)') is not null then
    raise exception 'LLAMADAS_OPERACION_HOY: ya está aplicada; no se sobrescribe';
  end if;
end;
$precondicion$;

-- ── 1. Núcleo: las cifras de hoy del ámbito del actor ────────────────────────────────────────
create function private.llamadas_celular_operacion_hoy(p_actor uuid, p_supervisor_id uuid, p_ahora timestamptz)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_rol     text := private.rol_crm(p_actor);
  -- Hoy en Lima: el mismo molde que private.llamadas_celular_resueltas_hoy.
  v_desde   timestamptz := pg_catalog.date_trunc('day', p_ahora at time zone 'America/Lima') at time zone 'America/Lima';
  -- Retención de lo que no tiene enlace (D5): lo que la purga conserva es lo que se muestra.
  v_dias    integer := coalesce((select pol.dias_retencion_sin_resolver from crm.llamadas_celular_politica pol where pol.singleton), 30);
  v_roster  jsonb;
  v_salud   jsonb;
  v_alcance text;
begin
  -- El actor es siempre quien está autenticado (defensa en profundidad: el roster del pulso y vendedor_ids_visibles
  -- lo exigen por su cuenta; aquí no se confía en que el único llamador sea la puerta).
  if p_actor is null or p_actor is distinct from (select auth.uid()) then
    raise exception using errcode = '42501', message = 'Sin acceso a las llamadas del celular';
  end if;
  if v_rol = 'gerencia' then
    -- Rol efectivo (equipo y perfil activos), el mismo que usa el roster: un supervisor dado de baja a medias no cuenta.
    if p_supervisor_id is not null and private.rol_crm(p_supervisor_id) is distinct from 'supervisor' then
      raise exception using errcode = '22023', message = 'No es un supervisor activo';
    end if;
    -- Las claves de equipo son las de «Actividad del día»: el roster del pulso (vendedores activos visibles con su
    -- supervisor activo más cercano). El roster exige gerencia por sí mismo (gestion_diaria_pulso_autorizar).
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'analista_id', r.analista_id, 'nombre', r.nombre_completo, 'supervisor_id', r.supervisor_id)), '[]'::jsonb)
      into v_roster
    from private.gestion_diaria_pulso_roster() r
    where p_supervisor_id is null or r.supervisor_id = p_supervisor_id;
    v_alcance := case when p_supervisor_id is null then 'operacion' else 'equipo' end;
  elsif v_rol = 'supervisor' then
    -- Un supervisor solo pregunta por su equipo; otro id recibe el 42501 de la familia (no se revela si existe).
    if p_supervisor_id is not null and p_supervisor_id <> p_actor then
      raise exception using errcode = '42501', message = 'Sin acceso a las llamadas del celular';
    end if;
    -- Su subárbol (vendedor_ids_visibles, que exige que el actor sea quien pregunta), solo vendedores con rol efectivo
    -- (equipo y perfil activos, como el roster de gerencia), todos bajo un único equipo con su id.
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'analista_id', e.perfil_id, 'nombre', p.nombre_completo, 'supervisor_id', p_actor)), '[]'::jsonb)
      into v_roster
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where private.rol_crm(e.perfil_id) = 'vendedor'
      and e.perfil_id in (select private.vendedor_ids_visibles(p_actor));
    v_alcance := 'equipo';
  else
    raise exception using errcode = '42501', message = 'Sin acceso a las llamadas del celular';
  end if;

  -- Salud de los celulares vigentes que el actor puede ver (undécima): estado del latido, sin horas exactas.
  v_salud := private.celulares_salud_listar(p_actor);

  return (
    with roster as (
      select r.analista_id, r.nombre, r.supervisor_id
      from pg_catalog.jsonb_to_recordset(v_roster) as r(analista_id uuid, nombre text, supervisor_id uuid)
    ), salientes as (
      -- Base común: SALIENTES de los analistas del ámbito (las entrantes están bloqueadas; las personales y a no-leads
      -- no existen en la tabla). Una sola pasada acotada por recepción: una llamada de hoy no pudo recibirse antes de
      -- ayer y lo que no tiene enlace no sobrevive a la retención. Momento de la llamada (D2): ocurrio_en, salvo que
      -- falte o vaya más de 5 min por delante del servidor (reloj corrido); entonces, recibido_en.
      select e.id, e.analista_id, e.atencion, e.identificacion, e.lead_id, e.recibido_en,
             case when e.ocurrio_en is null or e.ocurrio_en > e.recibido_en + interval '5 minutes'
                  then e.recibido_en else e.ocurrio_en end as momento
      from crm.llamadas_celular_eventos e
      where e.analista_id in (select r.analista_id from roster r)
        and e.direccion = 'saliente'
        and e.recibido_en >= least(v_desde - interval '1 day', p_ahora - pg_catalog.make_interval(days => v_dias))
    ), hoy as (
      -- Cohorte 5.1: identificadas, lead activo (A4), por el momento de la llamada. «Abierto y contactable» con la
      -- atención CRUDA (no la efectiva, que depende de quién mira: D4).
      select s.analista_id, s.atencion,
             (l.etapa not in ('convertido', 'descartado') and not l.no_contactar and not private.persona_vetada(l.id)) as abierto,
             coalesce(a.metadata ? 'deshecho_en', false) as deshecha
      from salientes s
      join crm.leads l on l.id = s.lead_id and l.activo
      left join crm.llamadas_celular_enlaces en on en.evento_id = s.id
      left join crm.actividades a on a.id = en.actividad_id
      where s.identificacion = 'identificado'
        and s.recibido_en >= v_desde - interval '1 day'
        and s.momento >= v_desde and s.momento < v_desde + interval '1 day'
    ), hoy_cubetas as (
      -- Seis cubetas disjuntas que suman el total; el estado se deriva de (atención, enlace, deshecho, lead), en ese orden.
      select h.analista_id, h.atencion,
             case h.atencion
               when 'registrado' then case when h.deshecha and h.abierto then 'deshechas_sin_corregir'
                                           when h.deshecha then 'cerradas_despues'
                                           else 'con_resultado' end
               when 'requiere_resultado' then case when h.abierto then 'sin_resultado' else 'cerradas_despues' end
               when 'descartado_con_motivo' then 'descartadas'
               when 'por_revisar' then 'por_revisar'
             end as cubeta
      from hoy h
    ), llamadas_hoy as (
      select c.analista_id,
             count(*)::integer as total,
             (count(*) filter (where c.cubeta = 'con_resultado'))::integer as con_resultado,
             (count(*) filter (where c.cubeta = 'deshechas_sin_corregir'))::integer as deshechas_sin_corregir,
             (count(*) filter (where c.cubeta = 'sin_resultado'))::integer as sin_resultado,
             (count(*) filter (where c.cubeta = 'cerradas_despues'))::integer as cerradas_despues,
             (count(*) filter (where c.cubeta = 'descartadas'))::integer as descartadas,
             (count(*) filter (where c.cubeta = 'por_revisar'))::integer as por_revisar,
             (count(*) filter (where c.atencion = 'requiere_devolucion'))::integer as requiere_devolucion
      from hoy_cubetas c
      group by c.analista_id
    ), resultados_hoy as (
      -- Cohorte 5.2: enlaces vigentes (actividad no deshecha) cuya ACTIVIDAD nació hoy (A2), atribuidos a quien marcó.
      -- Un enlace nunca es anterior a su actividad, así que actualizado_en >= hoy acota por índice sin perder ninguno.
      select e.analista_id,
             count(*)::integer as total,
             (count(*) filter (where en.via = 'al_colgar'))::integer as al_colgar,
             (count(*) filter (where en.via = 'pestana'))::integer as desde_pestana,
             (count(*) filter (where en.via = 'manual'))::integer as a_mano
      from crm.llamadas_celular_enlaces en
      join crm.actividades a on a.id = en.actividad_id
      join crm.llamadas_celular_eventos e on e.id = en.evento_id
      join crm.leads l on l.id = e.lead_id and l.activo
      where en.actualizado_en >= v_desde
        and a.creado_en >= v_desde and a.creado_en < v_desde + interval '1 day'
        and not (a.metadata ? 'deshecho_en')
        and e.direccion = 'saliente'
        and e.analista_id in (select r.analista_id from roster r)
      group by e.analista_id
    ), pendientes as (
      -- 5.3: foto de ahora dentro de la retención. Sin resultado = atención cruda, sin enlace, lead abierto y contactable.
      -- Por revisar = ambiguas, de la bolsa y reutilizables (con o sin lead; si lo hay, activo).
      select s.analista_id,
             (count(*) filter (where p.pendiente))::integer as total,
             (count(*) filter (where p.pendiente and s.momento >= v_desde))::integer as de_hoy,
             (count(*) filter (where p.pendiente and s.momento < v_desde))::integer as anteriores,
             min(s.momento) filter (where p.pendiente) as mas_antigua,
             (count(*) filter (where s.atencion = 'por_revisar'))::integer as por_revisar
      from salientes s
      left join crm.leads l on l.id = s.lead_id
      cross join lateral (
        select s.atencion = 'requiere_resultado' and l.activo
               and l.etapa not in ('convertido', 'descartado') and not l.no_contactar and not private.persona_vetada(l.id)
               and not exists (select 1 from crm.llamadas_celular_enlaces en where en.evento_id = s.id) as pendiente
      ) p
      where s.recibido_en >= p_ahora - pg_catalog.make_interval(days => v_dias)
        and s.atencion in ('requiere_resultado', 'por_revisar')
        and (s.lead_id is null or l.activo)
      group by s.analista_id
    ), deshechas as (
      -- Deshechas sin corregir, de cualquier fecha (la purga no retira lo enlazado): desde los enlaces hacia la actividad.
      select e.analista_id, count(*)::integer as n
      from crm.llamadas_celular_enlaces en
      join crm.actividades a on a.id = en.actividad_id and a.metadata ? 'deshecho_en'
      join crm.llamadas_celular_eventos e on e.id = en.evento_id
      join crm.leads l on l.id = e.lead_id and l.activo
      where e.direccion = 'saliente'
        and e.analista_id in (select r.analista_id from roster r)
        and l.etapa not in ('convertido', 'descartado') and not l.no_contactar and not private.persona_vetada(l.id)
      group by e.analista_id
    ), salud as (
      -- Solo lo que el contrato publica de cada celular: ni asignación, ni nombre, ni desde cuándo.
      select (c ->> 'analista_id')::uuid as analista_id, c ->> 'etiqueta' as etiqueta, c ->> 'estado_latido' as estado_latido,
             pg_catalog.jsonb_build_object(
               'etiqueta', c -> 'etiqueta', 'estado_latido', c -> 'estado_latido', 'horas_sin_latido', c -> 'horas_sin_latido',
               'reloj_desfasado', c -> 'reloj_desfasado', 'eventos_en_cola', c -> 'eventos_en_cola',
               'version_macro', c -> 'version_macro') as celular
      from pg_catalog.jsonb_array_elements(v_salud) c
    ), celulares as (
      select s.analista_id,
             pg_catalog.jsonb_agg(s.celular order by s.etiqueta) as lista,
             count(*)::integer as vigentes,
             (count(*) filter (where s.estado_latido <> 'al_dia'))::integer as sin_latido,
             bool_or(s.estado_latido = 'al_dia') as alguno_al_dia
      from salud s
      group by s.analista_id
    ), por_analista as (
      select r.analista_id, r.nombre, r.supervisor_id,
             coalesce(lh.total, 0) as lh_total, coalesce(lh.con_resultado, 0) as lh_con_resultado,
             coalesce(lh.deshechas_sin_corregir, 0) as lh_deshechas, coalesce(lh.sin_resultado, 0) as lh_sin_resultado,
             coalesce(lh.cerradas_despues, 0) as lh_cerradas, coalesce(lh.descartadas, 0) as lh_descartadas,
             coalesce(lh.por_revisar, 0) as lh_por_revisar, coalesce(lh.requiere_devolucion, 0) as lh_devolucion,
             coalesce(rh.total, 0) as rh_total, coalesce(rh.al_colgar, 0) as rh_al_colgar,
             coalesce(rh.desde_pestana, 0) as rh_pestana, coalesce(rh.a_mano, 0) as rh_manual,
             coalesce(pe.total, 0) as pe_total, coalesce(pe.de_hoy, 0) as pe_de_hoy, coalesce(pe.anteriores, 0) as pe_anteriores,
             pe.mas_antigua as pe_mas_antigua, coalesce(pe.por_revisar, 0) as pe_por_revisar,
             coalesce(d.n, 0) as de_n,
             coalesce(c.vigentes, 0) as cel_vigentes, coalesce(c.sin_latido, 0) as cel_sin_latido,
             coalesce(c.lista, '[]'::jsonb) as celulares,
             -- D1: «sin dato» = 0 llamadas Y ningún celular vigente al día. Un celular al día con 0 llamadas muestra 0.
             (coalesce(lh.total, 0) = 0 and not coalesce(c.alguno_al_dia, false)) as sin_dato
      from roster r
      left join llamadas_hoy lh on lh.analista_id = r.analista_id
      left join resultados_hoy rh on rh.analista_id = r.analista_id
      left join pendientes pe on pe.analista_id = r.analista_id
      left join deshechas d on d.analista_id = r.analista_id
      left join celulares c on c.analista_id = r.analista_id
    ), niveles as (
      -- Las mismas cifras en tres niveles (g = 0 analista, 2 equipo, 3 operación): los equipos y los totales son SUMAS
      -- de sus analistas; ningún porcentaje viaja en el jsonb (la pantalla los calcula de cada par de la misma cohorte).
      select grouping(pa.analista_id, pa.supervisor_id) as g,
             pa.analista_id, pa.supervisor_id,
             count(*)::integer as analistas,
             (count(*) filter (where pa.sin_dato))::integer as analistas_sin_dato,
             coalesce(sum(pa.cel_vigentes), 0)::integer as celulares_vigentes,
             coalesce(sum(pa.cel_sin_latido), 0)::integer as celulares_sin_latido,
             pg_catalog.jsonb_build_object(
               'llamadas_hoy', pg_catalog.jsonb_build_object(
                 'total', coalesce(sum(pa.lh_total), 0)::integer,
                 'con_resultado', coalesce(sum(pa.lh_con_resultado), 0)::integer,
                 'deshechas_sin_corregir', coalesce(sum(pa.lh_deshechas), 0)::integer,
                 'sin_resultado', coalesce(sum(pa.lh_sin_resultado), 0)::integer,
                 'cerradas_despues', coalesce(sum(pa.lh_cerradas), 0)::integer,
                 'descartadas', coalesce(sum(pa.lh_descartadas), 0)::integer,
                 'por_revisar', coalesce(sum(pa.lh_por_revisar), 0)::integer,
                 'requiere_devolucion', coalesce(sum(pa.lh_devolucion), 0)::integer),
               'resultados_hoy', pg_catalog.jsonb_build_object(
                 'total', coalesce(sum(pa.rh_total), 0)::integer,
                 'al_colgar', coalesce(sum(pa.rh_al_colgar), 0)::integer,
                 'desde_pestana', coalesce(sum(pa.rh_pestana), 0)::integer,
                 'a_mano', coalesce(sum(pa.rh_manual), 0)::integer),
               'pendientes', pg_catalog.jsonb_build_object(
                 'total', coalesce(sum(pa.pe_total), 0)::integer,
                 'de_hoy', coalesce(sum(pa.pe_de_hoy), 0)::integer,
                 'anteriores', coalesce(sum(pa.pe_anteriores), 0)::integer,
                 'mas_antigua_dias', case when min(pa.pe_mas_antigua) is null then null
                                          else pg_catalog.floor(extract(epoch from p_ahora - min(pa.pe_mas_antigua)) / 86400)::integer end,
                 'deshechas_sin_corregir', coalesce(sum(pa.de_n), 0)::integer),
               'por_revisar', coalesce(sum(pa.pe_por_revisar), 0)::integer) as cifras
      from por_analista pa
      group by grouping sets ((pa.analista_id, pa.supervisor_id), (pa.supervisor_id), ())
    )
    select pg_catalog.jsonb_build_object(
      'dia', (v_desde at time zone 'America/Lima')::date,
      'generado_en', p_ahora,
      'alcance', v_alcance,
      'rotulos', pg_catalog.jsonb_build_object(
        'llamadas_hoy', 'Llamadas de hoy (por la hora de la llamada)',
        'resultados_hoy', 'Resultados registrados hoy (de llamadas de cualquier día)',
        'pendientes', pg_catalog.format('Sin resultado ahora (hasta %s días)', v_dias)),
      'totales', (
        select n.cifras || pg_catalog.jsonb_build_object(
                 'celulares_vigentes', n.celulares_vigentes, 'celulares_sin_latido', n.celulares_sin_latido,
                 'analistas_sin_dato', n.analistas_sin_dato)
        from niveles n where n.g = 3),
      'equipos', (
        select coalesce(pg_catalog.jsonb_agg(
                 pg_catalog.jsonb_build_object(
                   'supervisor_id', n.supervisor_id, 'supervisor_nombre', coalesce(p.nombre_completo, 'Sin supervisor'),
                   'analistas', n.analistas, 'celulares_vigentes', n.celulares_vigentes,
                   'celulares_sin_latido', n.celulares_sin_latido, 'analistas_sin_dato', n.analistas_sin_dato) || n.cifras
                 order by p.nombre_completo nulls last, n.supervisor_id), '[]'::jsonb)
        from niveles n
        left join public.perfiles p on p.id = n.supervisor_id
        where n.g = 2),
      'analistas', (
        select coalesce(pg_catalog.jsonb_agg(
                 pg_catalog.jsonb_build_object(
                   'analista_id', pa.analista_id, 'nombre', pa.nombre, 'supervisor_id', pa.supervisor_id,
                   'sin_dato', pa.sin_dato, 'celulares', pa.celulares) || n.cifras
                 order by pa.nombre, pa.analista_id), '[]'::jsonb)
        from por_analista pa
        join niveles n on n.g = 0 and n.analista_id = pa.analista_id),
      -- A7: el celular del supervisor, fuera de analistas[] y sin sumar al equipo. Gerencia: nulo.
      'su_celular', case when v_rol = 'supervisor'
                         then (select coalesce(pg_catalog.jsonb_agg(s.celular order by s.etiqueta), '[]'::jsonb)
                               from salud s where s.analista_id = p_actor)
                         else null end)
  );
end;
$function$;

-- ── 2. Puerta: valida el rol y delega ───────────────────────────────────────────────────────
create function crm.llamadas_celular_operacion_hoy_fn(p_supervisor_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['supervisor', 'gerencia']);
begin
  return private.llamadas_celular_operacion_hoy(v_actor, p_supervisor_id, pg_catalog.statement_timestamp());
end;
$function$;

-- ── 3. Permisos ──────────────────────────────────────────────────────────────────────────────
revoke all on function private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function crm.llamadas_celular_operacion_hoy_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.llamadas_celular_operacion_hoy_fn(uuid) to authenticated;

-- ── 4. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on function private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz) is
  'F4-e (decimotercera): cifras de hoy (Lima) de las llamadas del celular por analista y por equipo, más la salud de los celulares. Tres relojes con su rótulo: llamadas_hoy por el momento de la llamada (ocurrio_en; recibido_en si falta o el reloj va >5 min adelantado, D2) en seis cubetas disjuntas que suman el total; resultados_hoy por la fecha de la actividad (A2) partida por vía; pendientes = foto de ahora dentro de la retención, con las deshechas sin corregir aparte y sin tope (D5). Atribuye a quien marcó (A1); leads de baja no cuentan (A4); lead cerrado después → cerradas_despues (A5); sin_dato = 0 llamadas y ningún celular al día (D1). Ámbito: gerencia con el roster del pulso (claves de «Actividad del día»; p_supervisor_id opcional, 22023 si no es un supervisor activo), supervisión con su subárbol bajo su id (otro id → 42501); regla D4: las cifras de un analista no dependen de quién pregunta. Sin números, leads, ids de evento ni horas de latido. INVOKER; solo la llama la puerta.';
comment on function crm.llamadas_celular_operacion_hoy_fn(uuid) is
  'Puerta de F4-e para la tercera pestaña de «Toda la operación hoy» (gerencia) y el bloque «Su celular» de «Mi equipo hoy» (supervisor): valida el rol (supervisor o gerencia; los demás, 42501 «Sin acceso a las llamadas del celular») y delega en private.llamadas_celular_operacion_hoy con statement_timestamp(). p_supervisor_id: gerencia acota a ese equipo (22023 si no es un supervisor activo); un supervisor solo puede pasar el suyo o nulo. Solo lectura; no escribe bitácora. DEFINER con search_path vacío.';

-- ── 5. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  if (select p.pronargdefaults from pg_catalog.pg_proc p
      where p.oid = 'crm.llamadas_celular_operacion_hoy_fn(uuid)'::regprocedure) <> 1 then
    raise exception 'LLAMADAS_OPERACION_HOY: la puerta debe aceptar la llamada sin parámetros (p_supervisor_id opcional)';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz)'::regprocedure), 'llamada_celular_visible') > 0
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz)'::regprocedure), 'atencion_efectiva') > 0 then
    raise exception 'LLAMADAS_OPERACION_HOY: las cifras no pueden depender de quién pregunta (D4)';
  end if;
  for v_f in
    select * from (values
      ('private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz)', false, null),
      ('crm.llamadas_celular_operacion_hoy_fn(uuid)', true, 'authenticated')
    ) as f(firma, definer, rol)
  loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) is distinct from v_f.definer then
      raise exception 'LLAMADAS_OPERACION_HOY: % debería ser %', v_f.firma,
        case when v_f.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
        and a.grantee <> p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
      or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
      raise exception 'LLAMADAS_OPERACION_HOY: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_OPERACION_HOY: search_path inesperado en %', v_f.firma;
    end if;
    if (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) <> 's' then
      raise exception 'LLAMADAS_OPERACION_HOY: % debería ser STABLE (solo lee)', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_OPERACION_HOY: % sin COMMENT', v_f.firma;
    end if;
    if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure)), 'when others') > 0 then
      raise exception 'LLAMADAS_OPERACION_HOY: % atrapa cualquier error (WHEN OTHERS)', v_f.firma;
    end if;
  end loop;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
```

## Reversa `supabase/scripts/llamadas-celular/reversa-operacion-hoy.sql`

```sql
-- Reversa de 20261012192500_crm_llamadas_celular_operacion_hoy.sql (decimotercera, F4-e). Retira la puerta
-- crm.llamadas_celular_operacion_hoy_fn y el núcleo private.llamadas_celular_operacion_hoy: la huella del catálogo
-- vuelve exactamente a la de las doce. Sin datos que conservar (la puerta solo lee). La pantalla que la consuma
-- (tercera pestaña de gerencia y «Su celular») debe retirarse antes o tolerar la ausencia de la puerta.
--
-- Orden de las reversas: esta → duodécima (reversa-cierre-revision.sql) → undécima → …
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-operacion-hoy.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('crm.llamadas_celular_operacion_hoy_fn(uuid)') is null
     and to_regprocedure('private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz)') is null then
    raise exception 'REVERSA_OPERACION_HOY: la migración 20261012192500 no está aplicada';
  end if;
end;
$precondicion$;

drop function if exists crm.llamadas_celular_operacion_hoy_fn(uuid);
drop function if exists private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz);

do $postcheck$
begin
  if to_regprocedure('crm.llamadas_celular_operacion_hoy_fn(uuid)') is not null
     or to_regprocedure('private.llamadas_celular_operacion_hoy(uuid,uuid,timestamptz)') is not null then
    raise exception 'REVERSA_OPERACION_HOY: no se volvió al estado de las doce';
  end if;
end;
$postcheck$;

notify pgrst, 'reload schema';
commit;
```

## Doble del roster añadido a `supabase/tests/llamadas-celular/base.sql` (solo banco reducido)

```sql
-- ── roster del pulso (DOBLE) ────────────────────────────────────────────────────────────────
-- private.gestion_diaria_pulso_roster real (20260924201358) parte de crm.equipo_visible_fn() (que el banco no tiene) y
-- exige gerencia por private.gestion_diaria_pulso_autorizar. Doble declarado para la decimotercera (F4-e): la misma
-- partición disjunta —vendedores activos con su supervisor activo más cercano, cortando ciclos— sobre crm.equipo, y el
-- mismo 42501 para quien no sea gerencia.
create function private.gestion_diaria_pulso_roster()
returns table(analista_id uuid, nombre_completo text, supervisor_id uuid)
language plpgsql stable security invoker set search_path = '' as $$
begin
  if auth.uid() is null or coalesce(private.rol_crm(auth.uid()), '') <> 'gerencia' then
    raise exception 'Solo gerencia puede consultar toda la operación' using errcode = '42501';
  end if;
  return query
  with recursive vendedores as (
    -- Rol efectivo (equipo y perfil activos), como crm.equipo_visible_fn en la real.
    select e.perfil_id, e.supervisor_id from crm.equipo e where private.rol_crm(e.perfil_id) = 'vendedor'
  ), ascendientes as (
    select v.perfil_id as analista, v.supervisor_id as ancestro, array[v.perfil_id] as camino, 1 as profundidad
    from vendedores v
    union all
    select a.analista, e.supervisor_id, a.camino || a.ancestro, a.profundidad + 1
    from ascendientes a join crm.equipo e on e.perfil_id = a.ancestro
    where a.ancestro is not null and not a.ancestro = any(a.camino)
  )
  select v.perfil_id, p.nombre_completo,
    (select a.ancestro from ascendientes a
      where a.analista = v.perfil_id and private.rol_crm(a.ancestro) = 'supervisor'
      and not a.ancestro = any(a.camino) order by a.profundidad, a.ancestro limit 1)
  from vendedores v join public.perfiles p on p.id = v.perfil_id order by v.perfil_id;
end $$;
```
