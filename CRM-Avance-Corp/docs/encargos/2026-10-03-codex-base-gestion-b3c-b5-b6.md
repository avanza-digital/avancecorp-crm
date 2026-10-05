ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está transcrito aquí.
Formato: VERDICT (PASS/BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia (sección y línea del texto transcrito), NEXT ACTIONS, CONFIDENCE.
Tu tarea es REFUTAR: busca el caso concreto en que esto falla. Si no encuentras ninguno con evidencia, di PASS.

# Encargo: Base para gestión · paquete B3c + B5 + B6 — LEVEL 3 (puertas, núcleo, trigger en crm.leads, datos)

## Contexto (CRM Avance Corp; Supabase/Postgres 17.6; esquema `crm` expuesto, `private` no)
- B1–B3b del módulo están en producción desde el 02/10/2026 (tú revisaste B1–B4 y B3b).
- **Censo analítico** (`private.contadores_crudos_leads_citas()`): toda función cuyo cuerpo (lower, sin comentarios) nombre
  `crm.leads` (regex `\mcrm\.\s*leads\M`) o una palabra que empiece por `reunion` (`\mreunion`), Y use `count(` o `sum(1)`,
  entra al censo; `private.assert_analitica_leads_citas()` exige que esté declarada en `private.analitica_leads_citas_exenciones`
  con la huella de su cuerpo, y el techo de exenciones SOLO BAJA (no se puede declarar nada nuevo). Un vigía diario abre alerta
  si el assert cae. Leído en producción el 03/10: el assert cae desde el 02/10 por 4 funciones de B3/B4 sin declarar
  (`crm.obtener_base_gestion`, `crm.base_gestion_resumen`, `private.base_gestion_intento_core`,
  `private.trg_actividades_enfriamiento_base`) + 1 de otra sesión (`private.gestion_diaria_cola_hechos`, fuera de alcance).
  `crm.rescatar_descartes` SÍ está declarada (clase 'operativo') con huella válida.
- **B3c**: saca del censo las 4 del módulo. Tres cuentan intentos (filas de `crm.actividades` con `metadata->>'evento' =
  'intento_base'`), no leads; su `count(*)` pasa a la nueva `private.base_gestion_intentos_ciclo(uuid[], timestamptz[])` —UNA
  definición para núcleo, enfriamiento y lista (antes eran tres copias del mismo predicado)—. El resumen cuenta «en base» y
  «rellamadas de hoy» sobre la lista de `crm.obtener_base_gestion()` (antes copiaba su predicado) e intentos/reactivaciones por
  dueño vía la nueva `private.base_gestion_leads_de(uuid)` (solo predicado, sin agregados). Doctrina interna del censo: «el
  predicado sobre leads va en una función propia sin agregados; la que agrega no nombra crm.leads».
- **B5**: `crm.obtener_base_gestion` devuelve al final `recibido_en = coalesce(tenencia_desde, creado_en)` (drop + create).
- **B6** (regla de Miguel, decisiones del 03/10): un lead DESCARTADO con seguimiento activo de su analista (último intento de
  la base del ciclo vigente + 7 días, o rellamada agendada en ese ciclo; vale el mayor; día de Lima) no cambia de responsable
  POR NINGUNA VÍA. Se implementa como trigger BEFORE UPDATE en `crm.leads` (WHEN descartado y cambia `vendedor_id`), no
  dentro de `crm.rescatar_descartes` (que no se toca: está declarada en el censo con huella). Vías que cambian `vendedor_id`
  de un descartado (inventario de pg_proc): `crm.rescatar_descartes` (supervisor/gerencia), PATCH directo de la ficha
  (`store.reasignar`, RLS + grants por columna), `crm.tomar_lead_libre(text,text)` (otro analista toma un descartado de > 24 h
  por teléfono/DNI, reabre ciclo nuevo). Excluyen descartados: `crm.derivar_leads_equipo_fn`,
  `crm.fijar_membresia_activa_fn` (bajas: `etapa not in ('convertido','descartado')`), `crm.reasignar_responsable_relacion_fn`
  (etapas abiertas). Una baja (dueño inactivo en crm.equipo/public.perfiles) libera: la regla devuelve NULL.
  El Centro de rescate (`crm.rescate_descartes_mes`) pinta EN GRIS «En gestión por X hasta el día Y» con dos columnas nuevas;
  `estado` NO cambia porque el bundle publicado valida con lista cerrada ('pendiente','rescatado','historial') y descartaría
  la fila; con `puede_rescatar=false` la pinta «Solo historial». El front nuevo muestra el P0409 tal cual.
- Los intentos los escribe SOLO `private.base_gestion_intento_core`, que toma `select … from crm.leads where id = p_lead_id
  for update` antes de escribir la actividad y la rellamada (`crm.leads.proxima_llamada_en`, sellada: solo la escribe el núcleo).
- Todos los cuerpos base son el texto VIVO (md5(prosrc) leídos en producción el 03/10 = banco); cada migración se construye
  con sustituciones exactas y su preflight exige esos md5; cada postflight exige el md5 de los cuerpos nuevos y la ACL exacta.

## Revisión previa del auditor-rls (subagente, solo lectura) y qué se hizo
- P1 «B6 caducaría la exención de `rescatar_descartes`» → ACEPTADO: B6 ya no la toca (candado en el lead).
- P1 «el censo ya cae por B3/B4» → CONFIRMADO en producción → B3c.
- P2 «la ficha salta la regla» → CONFIRMADO en el banco (PATCH pasaba) → candado en el lead (Miguel eligió «toda vía»).
- P2 «faltan casos en test-rls.mjs» → pendiente para el gate (rama + Docker), después de esta revisión.
- P3 «rellamada de un ciclo anterior bloquea» → ACEPTADO: solo cuenta si hay intento en el ciclo vigente.
- P3 «en_gestion_por = dueño actual, ámbito por analista del episodio» → mitigado: el candado ya impide reasignar un descartado
  en gestión; el gris solo aparece en episodios ya filtrados por ámbito. P3 «el supervisor/gerencia que registra un intento
  bloquea su propio reparto» → aceptado como regla (el lead se está trabajando). P3 «`rescate_descartes_meses` sigue contando
  en gris como pendientes» → aceptado (declarada en el censo: no se toca).
- P3 «postflights por fragmentos» → ACEPTADO: md5 de cuerpos + ACL exacta + guardas `is not true`; reversas exigen el cuerpo
  de su migración antes de pisar.

## Resultados en banco Docker (esquema de producción, datos sintéticos)
- B3c: postflight (el censo pierde EXACTAMENTE las 4, no gana nada, sello intacto) PASS; B2 25/25, B3 48/48, B4 17/17.
  Mutante «la ayudante cuenta +1» → B3 y B4 FALLAN.
- B5: postflight PASS; B3 48/48.
- B6: `b6-seguimiento.sql` 29/29 (transcrita abajo). Mutantes: regla que siempre da NULL → FALLA; trigger deshabilitado → FALLA.
- Cadena de reversas B6 → B5 → B3c: las seis funciones vuelven a las huellas de PRODUCCIÓN, sin restos; reaplicación y suites
  en verde. Registradores probados dos veces (no duplican).
- No se prueba «llamar a una función privada sin EXECUTE»: en la imagen Supabase 17.6 local eso tumba el backend (bug de la
  imagen). Se acredita con `has_function_privilege`.

## Preguntas concretas (refuta)
1. ¿El trigger tiene alguna vía de escape o algún falso positivo? (orden de triggers BEFORE: corre tras
   `trg_leads_000_no_contactar_puerta`, `trg_leads_00_devolucion_equipo_solo_rpc`, `trg_leads_00_disponibilidad_update`,
   `trg_leads_00_guard_tenencia`; WHEN se evalúa con el NEW ya modificado por los anteriores). ¿Algún flujo legítimo del
   sistema que cambie `vendedor_id` de un descartado con intento reciente y que ahora se rompa?
2. ¿Carreras? (el trigger corre bajo el lock de la fila que toma el UPDATE; el intento toma FOR UPDATE de la misma fila).
3. B3c: ¿el comportamiento es idéntico al vivo? En especial: el AFTER trigger de enfriamiento ahora cuenta vía una función SQL
   STABLE llamada desde plpgsql VOLATILE (¿ve la fila recién insertada?: la suite B4 pasa 17/17); el resumen ahora llama a
   `crm.obtener_base_gestion()` (DEFINER, mismo `auth.uid()`), ¿mismo ámbito y mismos números?; el reparto de arrays
   alineados por `order by b.id`.
4. ¿El mensaje del P0409 o el detail filtran algo a quien llama por «tomar lead libre» (otro analista)?
5. ¿Preflight/postflight/reversa acreditan lo que dicen?

## B3c · supabase/migrations/20261003162300_crm_base_gestion_conteos_fuera_del_censo.sql (marco; los 4 cuerpos van como diff)
```sql
-- 20261003162300_crm_base_gestion_conteos_fuera_del_censo.sql
--
-- Base para gestión del analista · B3c: las cuatro funciones del módulo salen del CENSO ANALÍTICO.
-- Desde el 02/10 (20:15) `private.assert_analitica_leads_citas()` cae y el vigía de las 06:49 abre una alerta diaria
-- (fase f6a_analitica_leads_citas): `crm.obtener_base_gestion`, `crm.base_gestion_resumen`,
-- `private.base_gestion_intento_core` y `private.trg_actividades_enfriamiento_base` nombran `crm.leads` o «reunion» y
-- usan `count(`, y ninguna está declarada (leído en producción el 03/10). Tres NO cuentan leads: cuentan intentos de la
-- base (filas de crm.actividades). Declarar no cabe (el techo de exenciones solo baja) y no hace falta: se sacan del
-- alcance como manda la doctrina del censo — el predicado sobre leads en su función, el agregado en otra que no la nombra.
-- Plan aprobado por Miguel el 03/10/2026 («sí, en este paquete»).
--
-- QUÉ (create or replace del texto VIVO con sustituciones exactas; firmas, dueños, permisos y comportamiento iguales):
--   · NUEVA `private.base_gestion_intentos_ciclo(uuid[], timestamptz[])` — UNA definición de «intentos del ciclo» (misma
--     ventana D13, mismo desempate de Codex B3 #5) para el núcleo, el enfriamiento y la lista. Antes eran tres copias.
--   · NUEVA `private.base_gestion_leads_de(uuid)` — solo predicado: los leads de un dueño.
--   · `private.base_gestion_intento_core` y `private.trg_actividades_enfriamiento_base` — su `count(*)` pasa a la ayudante.
--   · `crm.obtener_base_gestion` — el CTE `intentos` lee la ayudante (set-based: una llamada con todos los leads).
--   · `crm.base_gestion_resumen` — «en base» y «rellamadas de hoy» cuentan la lista de `crm.obtener_base_gestion` (antes
--     copiaba su predicado); intentos y reactivaciones cuentan actividades por dueño vía `base_gestion_leads_de`.
-- NO toca exenciones ni el sello del trinquete; la alerta de `private.gestion_diaria_cola_hechos` (otra sesión) sigue.
-- PRECONDICIÓN: md5(prosrc) vivos medidos en producción el 03/10 (en el preflight).
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-conteos-fuera-del-censo.sql` (reinstala los cuatro cuerpos vivos y borra
-- las ayudantes). No toca datos. Requiere revertir antes B5 si está aplicada.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    (select md5(p.prosrc) = '65de1a6aaaf88c48cc22df74d8bd3a8a' from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
    and (select md5(p.prosrc) = '58f71178330836139f4c505450ee462a' from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen()'))
    and (select md5(p.prosrc) = '83813e4502f378951b50e91168e4480f' from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)'))
    and (select md5(p.prosrc) = '7b63174495ad8347805d38b2cec82158' from pg_proc p where p.oid = to_regprocedure('private.trg_actividades_enfriamiento_base()'))
    and to_regprocedure('private.base_gestion_intentos_ciclo(uuid[],timestamptz[])') is null
    and to_regprocedure('private.base_gestion_leads_de(uuid)') is null
    and (select count(*) = 4 from private.contadores_crudos_leads_citas() c where c.objeto in (to_regprocedure('crm.obtener_base_gestion(uuid)')::text, to_regprocedure('crm.base_gestion_resumen()')::text, to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)')::text, to_regprocedure('private.trg_actividades_enfriamiento_base()')::text))
  ) is not true then
    raise exception 'PREFLIGHT: los cuerpos vivos no son los medidos el 03/10, B3c ya esta aplicada o las 4 no estan en el censo';
  end if;
end;
$preflight$;

-- Foto del censo y del sello del trinquete: el postflight exige que salgan EXACTAMENTE las cuatro y que nada más cambie.
create temp table _b3c_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;
create temp table _b3c_sello_antes on commit drop as select s.sello from private.analitica_lc_sello s;

-- ── Ayudantes ────────────────────────────────────────────────────────────────────────────────────────────────
create function private.base_gestion_intentos_ciclo(p_leads uuid[], p_desdes timestamptz[])
returns table (lead_id uuid, n integer, ultimo text, ultimo_en timestamptz)
language sql stable security invoker set search_path = '' as $$
  -- Intentos de la base de cada lead desde el inicio de su ventana (D13: el descarte o el fin del último descanso).
  -- UNA definición para el núcleo (intento_n), el enfriamiento (tope de intentos) y la lista (contador y último resultado).
  select a.lead_id, count(*)::integer,
         (array_agg(a.metadata->>'resultado' order by a.creado_en desc, (a.metadata->>'intento_n')::integer desc, a.id desc))[1],
         max(a.creado_en)
    from unnest(p_leads, p_desdes) as u(lead_id, desde)  -- forma de varios arreglos: solo existe sin calificar
    join crm.actividades a on a.lead_id = u.lead_id and a.creado_en >= u.desde
   where a.metadata->>'evento' = 'intento_base'
   group by a.lead_id
$$;
alter function private.base_gestion_intentos_ciclo(uuid[], timestamptz[]) owner to postgres;
revoke all on function private.base_gestion_intentos_ciclo(uuid[], timestamptz[]) from public, anon, authenticated, service_role;
comment on function private.base_gestion_intentos_ciclo(uuid[], timestamptz[]) is
  'B3c (03/10/2026): intentos de la base por lead desde el inicio de su ventana (D13), con el último resultado (desempate por intento_n, Codex B3 #5) y el último instante. Fuente única para private.base_gestion_intento_core (intento_n), private.trg_actividades_enfriamiento_base (tope) y crm.obtener_base_gestion (lista). Solo lee crm.actividades: no es un contador de leads. INVOKER, sin EXECUTE para roles de la API.';

create function private.base_gestion_leads_de(p_vendedor_id uuid)
returns table (lead_id uuid)
language sql stable security invoker set search_path = '' as $$
  -- Solo predicado (sin agregados): los leads de un dueño. Quien agrega sus actividades no nombra la tabla de leads.
  select l.id from crm.leads l where l.vendedor_id = p_vendedor_id
$$;
alter function private.base_gestion_leads_de(uuid) owner to postgres;
revoke all on function private.base_gestion_leads_de(uuid) from public, anon, authenticated, service_role;
comment on function private.base_gestion_leads_de(uuid) is
  'B3c (03/10/2026): solo predicado, sin agregados: los leads cuyo dueño es p_vendedor_id. crm.base_gestion_resumen atribuye por dueño las actividades de la base sin nombrar la tabla de leads en su agregado. INVOKER, sin EXECUTE para roles de la API.';

-- ── Las cuatro, con su conteo en la ayudante ──────────────────────────────────────────────────────────────────
-- [ create or replace function private.base_gestion_intento_core… : cuerpo VIVO + el diff transcrito abajo ]
-- [ create or replace function private.trg_actividades_enfriamiento_base… : cuerpo VIVO + el diff transcrito abajo ]
-- [ create or replace function crm.obtener_base_gestion… : cuerpo VIVO + el diff transcrito abajo ]
-- [ create or replace function crm.base_gestion_resumen… : cuerpo VIVO + el diff transcrito abajo ]

comment on function private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz) is 'Base para gestión (B3, D3/D7-bis/D10/D11): registra un intento sobre un lead descartado del ámbito del actor (7 resultados; volver_a_llamar exige fecha futura ≤ dias_max_rellamada; descanso vigente y No contactar rechazan), escribe la actividad intento_base bajo los dos GUC, fija o limpia proxima_llamada_en y, con agendo_reunion, reactiva en la misma transacción. Idempotente por id = operación (guarda la respuesta). El enfriamiento lo pone el trigger de B4. Solo la llama la puerta crm.registrar_intento_base. B3c (03/10/2026): sus conteos de intentos salen de private.base_gestion_intentos_ciclo; fuera del censo analítico.';
comment on function private.trg_actividades_enfriamiento_base() is 'Base para gestión (B4/B4b, D4/D12/D13): al registrar un intento de la base sin rellamada ni cita, si el lead sigue descartado y los intentos de la ventana vigente (desde el descarte o el fin del último descanso) llegan a max_intentos, fija enfriado_hasta = hoy Lima + dias_enfriamiento. Solo actúa bajo crm.op_base_gestion = on. Constantes en private.base_gestion_constantes(). DEFINER por el molde del sello de B1; search_path vacío, dueño postgres, sin EXECUTE para la API. B3c (03/10/2026): sus conteos de intentos salen de private.base_gestion_intentos_ciclo; fuera del censo analítico.';
comment on function crm.obtener_base_gestion(uuid) is 'Base para gestión (B3): leads descartados vivos del ámbito del actor (analista → los suyos; Supervisión → subárbol; Gerencia → todo), sin «no contactar» ni descanso vigente, con intentos del ciclo, último resultado, próxima rellamada, etapa máxima alcanzada y quién gestiona. Orden: rellamada vencida o de hoy → etapa máxima → menos días desde el descarte. p_vendedor_id filtra un analista dentro del ámbito. DEFINER: ámbito explícito (espejo de leads_select), search_path vacío, EXECUTE solo authenticated. B3c (03/10/2026): sus conteos de intentos salen de private.base_gestion_intentos_ciclo; fuera del censo analítico.';
comment on function crm.base_gestion_resumen() is 'Base para gestión (B3, para F4): por analista activo del ámbito (Supervisión → subárbol; Gerencia → todos), leads en base, rellamadas vencidas o de hoy, intentos de hoy y reactivaciones del mes (Lima), atribuidos al DUEÑO del lead (lo que Supervisión registra sobre un lead del analista cuenta para el analista). Analistas y otros roles: 42501. DEFINER con ámbito explícito, search_path vacío, EXECUTE solo authenticated. B3c (03/10/2026): en base y rellamadas de hoy cuentan la lista de crm.obtener_base_gestion; intentos y reactivaciones, las actividades de private.base_gestion_leads_de. Fuera del censo analítico.';

do $postflight$
begin
  if (
    (select md5(p.prosrc) = 'db8ba2b4df43c84438f216924f20e73d' and p.proacl::text = '{postgres=X/postgres}' and p.prosecdef and p.proowner = 'postgres'::regrole
       from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)'))
    and (select md5(p.prosrc) = 'b60555d169891e2edb96b38e31754654' and p.proacl::text = '{postgres=X/postgres}' and p.prosecdef and p.proowner = 'postgres'::regrole
       from pg_proc p where p.oid = to_regprocedure('private.trg_actividades_enfriamiento_base()'))
    and (select md5(p.prosrc) = '74ed9b893bd45f446189feb05cadc839' and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}' and p.prosecdef and p.proowner = 'postgres'::regrole
       from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
    and (select md5(p.prosrc) = 'b773a7c49fbdfc45133b3405991b1958' and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}' and p.prosecdef and p.proowner = 'postgres'::regrole
       from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen()'))
    and (select md5(p.prosrc) = 'e0c60625a32e95dd950ef24470b360f0' and not p.prosecdef and p.provolatile = 's' and p.proacl::text = '{postgres=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intentos_ciclo(uuid[],timestamptz[])'))
    and (select md5(p.prosrc) = '3d02ee203937083db2233e008f53d757' and not p.prosecdef and p.provolatile = 's' and p.proacl::text = '{postgres=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('private.base_gestion_leads_de(uuid)'))
    and (select md5(pg_get_triggerdef(t.oid)) = '839e077b37bedd046cea7ca8c5d0b903' from pg_trigger t where t.tgname = 'trg_zz_actividades_enfriamiento_base')
    -- El censo pierde EXACTAMENTE las cuatro y no gana nada (ni las ayudantes):
    and not exists (select 1 from private.contadores_crudos_leads_citas() c
                     where c.objeto in (to_regprocedure('crm.obtener_base_gestion(uuid)')::text, to_regprocedure('crm.base_gestion_resumen()')::text, to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)')::text, to_regprocedure('private.trg_actividades_enfriamiento_base()')::text, to_regprocedure('private.base_gestion_intentos_ciclo(uuid[],timestamptz[])')::text, to_regprocedure('private.base_gestion_leads_de(uuid)')::text))
    and not exists (select 1 from private.contadores_crudos_leads_citas() c where c.objeto not in (select a.objeto from pg_temp._b3c_censo_antes a))
    and (select count(*) from pg_temp._b3c_censo_antes) - (select count(*) from private.contadores_crudos_leads_citas()) = 4
    and (select array_agg(s.sello order by s.sello) from private.analitica_lc_sello s)
        is not distinct from (select array_agg(a.sello order by a.sello) from pg_temp._b3c_sello_antes a)
  ) is not true then
    raise exception 'POSTFLIGHT: B3c no dejo los cuerpos esperados, cambio permisos o el censo no perdio exactamente las cuatro';
  end if;
  raise notice 'base_gestion_conteos_fuera_del_censo OK: 4 fuera del censo, 2 ayudantes privadas, cuerpos y permisos verificados';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
```
### diff private.base_gestion_intento_core (vivo → B3c)
```diff
@@ -74,11 +74,10 @@
   end if;
   if v_lead.enfriado_hasta is not null and v_lead.enfriado_hasta > v_hoy then
     raise exception 'El lead esta en descanso hasta el %', to_char(v_lead.enfriado_hasta, 'DD/MM/YYYY') using errcode = '22023';
   end if;
-  select count(*)::integer + 1 into v_n from crm.actividades a
-   where a.lead_id = p_lead_id and a.metadata->>'evento' = 'intento_base'
-     and a.creado_en >= private.base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy);  -- D13
+  -- B3c: los intentos del ciclo se cuentan en private.base_gestion_intentos_ciclo (una sola definición, misma ventana D13).
+  v_n := coalesce((select c.n from private.base_gestion_intentos_ciclo(array[p_lead_id], array[private.base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy)]) c), 0) + 1;  -- D13
   v_tipo := case when p_resultado in ('no_contesto', 'numero_errado', 'no_es_la_persona')
                  then 'llamada_no_contestada' else 'llamada_realizada' end;
   v_meta := jsonb_strip_nulls(jsonb_build_object(
     'evento', 'intento_base', 'via', 'base_gestion', 'resultado', p_resultado, 'intento_n', v_n,
```
### diff private.trg_actividades_enfriamiento_base (vivo → B3c)
```diff
@@ -19,11 +19,10 @@
   if v_lead.id is null or not v_lead.activo or v_lead.etapa <> 'descartado' then
     return null;
   end if;
   select * into v_c from private.base_gestion_constantes();
-  select count(*) into v_n from crm.actividades a
-   where a.lead_id = new.lead_id and a.metadata->>'evento' = 'intento_base'
-     and a.creado_en >= private.base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy);  -- incluye este intento (AFTER); D13
+  -- B3c: los intentos del ciclo se cuentan en private.base_gestion_intentos_ciclo (una sola definición, misma ventana D13).
+  v_n := coalesce((select c.n from private.base_gestion_intentos_ciclo(array[new.lead_id], array[private.base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy)]) c), 0);  -- incluye este intento (AFTER); D13
   if v_n < v_c.max_intentos then
     return null;
   end if;
   v_hasta := v_hoy + v_c.dias_enfriamiento;
```
### diff crm.obtener_base_gestion (vivo → B3c → B5)
```diff
@@ -16,22 +16,22 @@
   return query
   with base as (
     select l.id, l.nombre_completo, l.telefono, l.distrito, l.origen, l.categoria_interes, l.monto_estimado, l.moneda,
            l.motivo_descarte, l.descartado_en, l.proxima_llamada_en, l.enfriado_hasta, l.ciclo_actual, l.vendedor_id,
+           coalesce(l.tenencia_desde, l.creado_en) as recibido_en,  -- B5: cuando le llego el lead a quien lo tiene (el MES del lead)
            private.base_gestion_intentos_desde(l.descartado_en, l.creado_en, l.enfriado_hasta, v_hoy) as desde  -- D13: ventana desde el descarte o desde el fin del ultimo descanso
     from crm.leads l
     where l.activo and l.etapa = 'descartado' and not l.no_contactar
       and (l.enfriado_hasta is null or l.enfriado_hasta <= v_hoy)
       and private.base_gestion_lead_visible(v_uid, v_rol, l.vendedor_id, l.asignado_supervisor_id)
       and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
   ),
   intentos as (
-    select a.lead_id, count(*)::integer as n,
-           (array_agg(a.metadata->>'resultado' order by a.creado_en desc, (a.metadata->>'intento_n')::integer desc, a.id desc))[1] as ultimo,  -- Codex B3 #5: desempate por intento_n
-           max(a.creado_en) as ultimo_en
-    from crm.actividades a join base b on b.id = a.lead_id
-    where a.metadata->>'evento' = 'intento_base' and a.creado_en >= b.desde
-    group by a.lead_id
+    -- B3c: contador, último resultado (desempate por intento_n, Codex B3 #5) y último intento salen de la MISMA definición
+    -- que usan el núcleo y el enfriamiento: private.base_gestion_intentos_ciclo, con la ventana D13 de cada lead.
+    select c.lead_id, c.n, c.ultimo, c.ultimo_en
+    from (select array_agg(b.id order by b.id) as ids, array_agg(b.desde order by b.id) as desdes from base b) q
+    cross join lateral private.base_gestion_intentos_ciclo(q.ids, q.desdes) c
   ),
   ciclo as (
     -- El ciclo vigente empieza en la ultima reapertura (cambio_etapa descartado → nuevo) o, si nunca hubo, al inicio.
     -- Se acota con el propio historial (misma fuente y mismo reloj que los cambios de etapa): robusto frente a
@@ -59,9 +59,9 @@
                                    when 4 then 'propuesta_enviada' when 5 then 'convertido' else 'sin_datos' end,
          coalesce(i.n, 0), i.ultimo, i.ultimo_en,
          b.proxima_llamada_en,
          (b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy),
-         b.enfriado_hasta, b.ciclo_actual, b.vendedor_id, p.nombre_completo
+         b.enfriado_hasta, b.ciclo_actual, b.vendedor_id, p.nombre_completo, b.recibido_en
   from base b
   left join intentos i on i.lead_id = b.id
   left join etapas e on e.lead_id = b.id
   left join public.perfiles p on p.id = b.vendedor_id
```
### diff crm.base_gestion_resumen (vivo → B3c)
```diff
@@ -1,31 +1,36 @@
 
 declare
   v_uid uuid := (select auth.uid());
   v_rol text;
   v_hoy date := (now() at time zone 'America/Lima')::date;
 begin
   v_rol := private.base_gestion_rol(v_uid);
   if v_rol <> 'supervisor' and v_rol <> 'gerencia' then
     raise exception 'Solo Supervision y Gerencia ven el resumen de la base' using errcode = '42501';
   end if;
+  -- B3c (03/10/2026): «en base» y «rellamadas de hoy» cuentan la MISMA lista que ve el analista (crm.obtener_base_gestion:
+  -- una sola definición de la base, antes copiada aquí); intentos y reactivaciones cuentan actividades de los leads de
+  -- cada dueño (private.base_gestion_leads_de, solo predicado). Sin contadores crudos sobre la tabla de leads.
   return query
+  with base as (
+    select g.vendedor_id as dueno, g.rellamada_hoy as hoy from crm.obtener_base_gestion() g
+  )
   select e.perfil_id, p.nombre_completo,
-         (select count(*)::integer from crm.leads l where l.vendedor_id = e.perfil_id and l.activo and l.etapa = 'descartado'
-            and not l.no_contactar and (l.enfriado_hasta is null or l.enfriado_hasta <= v_hoy)),
-         (select count(*)::integer from crm.leads l where l.vendedor_id = e.perfil_id and l.activo and l.etapa = 'descartado'
-            and not l.no_contactar and (l.enfriado_hasta is null or l.enfriado_hasta <= v_hoy)
-            and l.proxima_llamada_en is not null and (l.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy),
+         (select count(*)::integer from base b where b.dueno = e.perfil_id),
+         (select count(*)::integer from base b where b.dueno = e.perfil_id and b.hoy),
          -- Atribucion por DUEÑO del lead: lo que Supervision o Gerencia registran sobre un lead del analista cuenta para el analista.
-         (select count(*)::integer from crm.actividades a join crm.leads l on l.id = a.lead_id
-           where l.vendedor_id = e.perfil_id and a.metadata->>'evento' = 'intento_base'
+         (select count(*)::integer from crm.actividades a join private.base_gestion_leads_de(e.perfil_id) d on d.lead_id = a.lead_id
+           where a.metadata->>'evento' = 'intento_base'
+             and a.creado_en >= (v_hoy::timestamp at time zone 'America/Lima')
              and (a.creado_en at time zone 'America/Lima')::date = v_hoy),
-         (select count(*)::integer from crm.actividades a join crm.leads l on l.id = a.lead_id
-           where l.vendedor_id = e.perfil_id and a.metadata->>'evento' = 'reactivacion_base'
+         (select count(*)::integer from crm.actividades a join private.base_gestion_leads_de(e.perfil_id) d on d.lead_id = a.lead_id
+           where a.metadata->>'evento' = 'reactivacion_base'
+             and a.creado_en >= (date_trunc('month', v_hoy::timestamp) at time zone 'America/Lima')
              and date_trunc('month', a.creado_en at time zone 'America/Lima') = date_trunc('month', v_hoy::timestamp))
   from crm.equipo e
   join public.perfiles p on p.id = e.perfil_id
   where e.rol_crm = 'vendedor' and e.activo and p.activo
     and (v_rol = 'gerencia' or e.perfil_id in (select private.vendedor_ids_visibles(v_uid)))
   order by p.nombre_completo;
 end;
 
```

## B5 · supabase/migrations/20261003162400_crm_base_gestion_mes_del_lead.sql (marco)
```sql
-- 20261003162400_crm_base_gestion_mes_del_lead.sql
--
-- Base para gestión del analista · B5: el MES del lead. Miguel (02/10/2026): «quiero saber qué mes estoy gestionando: mis
-- leads de enero, de marzo, de agosto». `crm.obtener_base_gestion` devuelve una columna más, al final: `recibido_en` =
-- coalesce(tenencia_desde, creado_en), cuándo le llegó el lead a quien lo tiene (criterio de recepción de la casa). La
-- pantalla (rama `crm/base-gestion-front`, c9e772fd) ya la lee como opcional: sin ella no pinta columna ni selector.
-- Plan aprobado por Miguel el 03/10/2026.
--
-- QUÉ: drop + create (cambia el `returns table`) con el texto de B3c más dos sustituciones exactas (la columna en el CTE
-- `base` y en el select final). Mismo orden, ámbito, dueño y permisos (EXECUTE solo authenticated). Su único envoltorio
-- es `crm.base_gestion_resumen` (B3c), que lee `vendedor_id` y `rellamada_hoy`: siguen ahí.
-- PRECONDICIÓN: B3c aplicada (md5 de su cuerpo en el preflight).
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-mes-del-lead.sql` (reinstala la firma y el cuerpo de B3c). No toca datos.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    select md5(p.prosrc) = '74ed9b893bd45f446189feb05cadc839' and not ('recibido_en' = any(p.proargnames))
      from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)')
  ) is not true then
    raise exception 'PREFLIGHT: crm.obtener_base_gestion no tiene el cuerpo de B3c o B5 ya esta aplicada';
  end if;
end;
$preflight$;

drop function crm.obtener_base_gestion(uuid);
-- [ create function crm.obtener_base_gestion… : cuerpo VIVO + el diff transcrito abajo ]
alter function crm.obtener_base_gestion(uuid) owner to postgres;
revoke all on function crm.obtener_base_gestion(uuid) from public, anon, authenticated, service_role;
grant execute on function crm.obtener_base_gestion(uuid) to authenticated;
comment on function crm.obtener_base_gestion(uuid) is 'Base para gestión (B3): leads descartados vivos del ámbito del actor (analista → los suyos; Supervisión → subárbol; Gerencia → todo), sin «no contactar» ni descanso vigente, con intentos del ciclo, último resultado, próxima rellamada, etapa máxima alcanzada y quién gestiona. Orden: rellamada vencida o de hoy → etapa máxima → menos días desde el descarte. p_vendedor_id filtra un analista dentro del ámbito. DEFINER: ámbito explícito (espejo de leads_select), search_path vacío, EXECUTE solo authenticated. B3c (03/10/2026): sus conteos de intentos salen de private.base_gestion_intentos_ciclo; fuera del censo analítico. B5 (03/10/2026): devuelve al final recibido_en = coalesce(tenencia_desde, creado_en), cuándo le llegó el lead a quien lo tiene: el MES por el que se organiza el analista.';

do $postflight$
begin
  if (
    (select md5(p.prosrc) = 'b2629fba517938457b64cdbc5856ee82'
        and p.proargnames[pg_catalog.array_length(p.proargnames, 1)] = 'recibido_en'
        and p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole
        and p.proconfig = array['search_path=""']::text[] and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
    and obj_description(to_regprocedure('crm.obtener_base_gestion(uuid)'), 'pg_proc') like '%B5 (03/10/2026)%'
    and (select md5(p.prosrc) = 'b773a7c49fbdfc45133b3405991b1958' from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen()'))
    and not exists (select 1 from private.contadores_crudos_leads_citas() c where c.objeto = to_regprocedure('crm.obtener_base_gestion(uuid)')::text)
  ) is not true then
    raise exception 'POSTFLIGHT: obtener_base_gestion no devuelve recibido_en, perdio su contrato o volvio al censo';
  end if;
  raise notice 'base_gestion_mes_del_lead OK: recibido_en al final, mismo cuerpo, EXECUTE solo authenticated, fuera del censo';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
```

## B6 · supabase/migrations/20261003162500_crm_base_gestion_seguimiento_activo.sql (marco; el cuerpo del rescate va como diff)
```sql
-- 20261003162500_crm_base_gestion_seguimiento_activo.sql
--
-- Base para gestión del analista · B6: a un lead descartado que su analista está trabajando nadie le cambia el responsable.
-- Miguel (02/10/2026): «evitar que un supervisor reasigne un lead que está siendo trabajado por el analista». Respuestas
-- (03/10): (1) la rellamada agendada vigente TAMBIÉN cuenta; (2) en el Centro de rescate se ve EN GRIS «En gestión por X
-- hasta el día Y», sin poder elegirlo; (3) el candado va en el LEAD, para toda vía: el auditor-rls probó que la ficha
-- (PATCH de vendedor_id) y «tomar lead libre» también movían el lead. Plan aprobado por Miguel el 03/10/2026.
--
-- QUÉ:
--   · NUEVA `private.base_gestion_en_gestion_hasta(uuid)` — la regla, en un solo sitio: último intento de la base del ciclo vigente + 7 días, o la
--     rellamada agendada en ese ciclo; NULL si el dueño ya no está activo (una baja lo libera).
--   · NUEVO trigger `trg_leads_00_seguimiento_activo` (BEFORE UPDATE de crm.leads, WHEN el lead está descartado y cambia su
--     vendedor_id) con `private.trg_leads_guard_seguimiento_activo()` (DEFINER: llama a la ayudante privada): P0409, detail `estado=en_gestion`. Cubre el
--     reparto del rescate (todo el lote falla: corre dentro de su transacción), la ficha y «tomar lead libre».
--   · `crm.rescate_descartes_mes(date)` — drop + create (cambia el `returns table`): `en_gestion_por` y `en_gestion_hasta` al final;
--     `puede_rescatar` = false mientras dure. `estado` NO cambia: el bundle viejo valida una lista cerrada.
--   `crm.rescatar_descartes` NO se toca (está declarada con su huella en el censo analítico: cambiarla la caducaría).
-- PRECONDICIÓN: B3c y B5 aplicadas; cuerpo vivo de rescate_descartes_mes medido en producción el 03/10 (md5 7c6363fb…,
-- de una migración que no está en el repo: su origen consta en el ledger).
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-seguimiento-activo.sql` (quita el trigger, reinstala el cuerpo vivo de
-- rescate_descartes_mes y borra las dos funciones). No toca datos.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    (select md5(p.prosrc) = '7c6363fbc96bc51f14997196e6eb8661' and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}' from pg_proc p where p.oid = to_regprocedure('crm.rescate_descartes_mes(date)'))
    and (select md5(p.prosrc) = 'b2629fba517938457b64cdbc5856ee82' from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
    and to_regprocedure('private.base_gestion_en_gestion_hasta(uuid)') is null
    and to_regprocedure('private.trg_leads_guard_seguimiento_activo()') is null
    and not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_seguimiento_activo')
  ) is not true then
    raise exception 'PREFLIGHT: falta B3c/B5, el cuerpo vivo del rescate no es el medido el 03/10 o B6 ya esta aplicada';
  end if;
end;
$preflight$;

create temp table _b6_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;

-- ── La regla ─────────────────────────────────────────────────────────────────────────────────────────────────
create function private.base_gestion_en_gestion_hasta(p_lead_id uuid)
returns date
language sql stable security invoker set search_path = '' as $$
  -- Hasta qué día (Lima) el lead descartado sigue en gestión de su analista: el último intento de la base del ciclo vigente
  -- (desde descartado_en) + 7 días, o el día de la rellamada agendada en ese ciclo, lo que llegue más lejos. NULL si ya no
  -- está en gestión, si no está descartado o si su dueño ya no está activo (una baja libera sus leads).
  select case when x.hasta >= (pg_catalog.now() at time zone 'America/Lima')::date then x.hasta end
    from (
      select greatest(
               (i.ultimo at time zone 'America/Lima')::date + 7,
               -- La rellamada solo cuenta si la agendó un intento de ESTE ciclo (una de un ciclo anterior no bloquea).
               case when i.ultimo is not null then (l.proxima_llamada_en at time zone 'America/Lima')::date end) as hasta
        from crm.leads l
        cross join lateral (
          select max(a.creado_en) as ultimo
            from crm.actividades a
           where a.lead_id = l.id
             and a.metadata->>'evento' = 'intento_base'
             and a.creado_en >= l.descartado_en
        ) i
       where l.id = p_lead_id
         and l.etapa = 'descartado'
         and exists (select 1 from crm.equipo e join public.perfiles p on p.id = e.perfil_id
                      where e.perfil_id = l.vendedor_id and e.activo and p.activo)
    ) x
$$;
alter function private.base_gestion_en_gestion_hasta(uuid) owner to postgres;
revoke all on function private.base_gestion_en_gestion_hasta(uuid) from public, anon, authenticated, service_role;
comment on function private.base_gestion_en_gestion_hasta(uuid) is
  'B6 (Miguel, 03/10/2026): seguimiento activo de un lead descartado. Último día (Lima) en que sigue en gestión de su analista: último intento de la base del ciclo vigente (desde descartado_en) + 7 días, o el día de la rellamada agendada en ese ciclo, el mayor. NULL si no hay seguimiento activo, si el lead no está descartado o si su dueño ya no está activo. Fuente única del candado (trg_leads_00_seguimiento_activo) y del gris del Centro de rescate. INVOKER, sin EXECUTE para roles de la API.';

-- ── El candado, en el lead ───────────────────────────────────────────────────────────────────────────────────
create function private.trg_leads_guard_seguimiento_activo()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_hasta date;
begin
  -- B6 (Miguel, 03/10/2026): a un lead descartado que su analista está trabajando nadie le cambia el responsable, venga por
  -- el Centro de rescate, la ficha o «tomar lead libre». Una baja (dueño inactivo) lo libera: la ayudante devuelve NULL.
  v_hasta := private.base_gestion_en_gestion_hasta(old.id);
  if v_hasta is not null then
    -- Sin nombres en el mensaje: quien lo intenta por «tomar lead libre» puede no ver al lead ni a su analista.
    raise exception 'Este lead lo está trabajando su analista hasta el %: no se le puede cambiar el responsable',
      pg_catalog.to_char(v_hasta, 'DD/MM/YYYY')
      using errcode = 'P0409',
            detail = pg_catalog.jsonb_build_object('estado', 'en_gestion', 'lead_id', old.id, 'hasta', v_hasta)::text;
  end if;
  return new;
end;
$$;
alter function private.trg_leads_guard_seguimiento_activo() owner to postgres;
revoke all on function private.trg_leads_guard_seguimiento_activo() from public, anon, authenticated, service_role;
comment on function private.trg_leads_guard_seguimiento_activo() is
  'B6 (Miguel, 03/10/2026): candado de seguimiento activo. Rechaza (P0409, detail estado=en_gestion) cambiar el responsable de un lead descartado mientras su analista lo trabaja, por cualquier vía. DEFINER: llama a private.base_gestion_en_gestion_hasta, que ningún rol de la API puede ejecutar; search_path vacío y nombres calificados. El mensaje no nombra al lead ni al analista.';
create trigger trg_leads_00_seguimiento_activo
  before update on crm.leads
  for each row
  when (old.etapa = 'descartado' and new.vendedor_id is distinct from old.vendedor_id)
  execute function private.trg_leads_guard_seguimiento_activo();
comment on trigger trg_leads_00_seguimiento_activo on crm.leads is
  'B6 (03/10/2026): un lead descartado en gestión de su analista no cambia de responsable (rescate, ficha, tomar lead libre). Ver private.trg_leads_guard_seguimiento_activo.';

-- ── El gris del Centro de rescate ────────────────────────────────────────────────────────────────────────────
drop function crm.rescate_descartes_mes(date);
-- [ create function crm.rescate_descartes_mes… : cuerpo VIVO + el diff transcrito abajo ]
alter function crm.rescate_descartes_mes(date) owner to postgres;
revoke all on function crm.rescate_descartes_mes(date) from public, anon, authenticated, service_role;
grant execute on function crm.rescate_descartes_mes(date) to authenticated;
comment on function crm.rescate_descartes_mes(date) is 'Historial mensual sin PII de contacto para Base para gestión. Cada fila es un episodio inmutable del ledger, no el estado actual mutable del lead. B6 (03/10/2026): en_gestion_por y en_gestion_hasta marcan el seguimiento activo del analista (intento de la base hace 7 días o menos, o rellamada vigente de ese ciclo); mientras dure, puede_rescatar = false y la pantalla lo pinta en gris. estado no cambia (el bundle viejo valida una lista cerrada).';

do $postflight$
begin
  if (
    (select md5(p.prosrc) = 'af0701a9e095e1004a64b7e289789d7c' and not p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole
        and p.proconfig = array['search_path=""']::text[] and p.proacl::text = '{postgres=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('private.base_gestion_en_gestion_hasta(uuid)'))
    and (select md5(p.prosrc) = '4aa0e9d46832a9a75bd8bab49af758ed' and p.prosecdef and p.proowner = 'postgres'::regrole
        and p.proconfig = array['search_path=""']::text[] and p.proacl::text = '{postgres=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('private.trg_leads_guard_seguimiento_activo()'))
    and (select md5(pg_get_triggerdef(t.oid)) = '7b08e2d83b66027e850035687ed07feb' and t.tgenabled = 'O'
       from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_seguimiento_activo')
    and (select md5(p.prosrc) = 'd21ca8325c777fb207d5f58df751748f' and p.proargnames[pg_catalog.array_length(p.proargnames, 1)] = 'en_gestion_hasta'
        and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[]
        and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('crm.rescate_descartes_mes(date)'))
    and (select md5(p.prosrc) = '5f4f5ca115f535f6ab8a1209dda19a0f' from pg_proc p where p.oid = to_regprocedure('crm.rescatar_descartes(uuid[],uuid[],boolean)'))
    -- B6 no mueve el censo analítico (ninguna de sus piezas cuenta):
    and not exists (select 1 from private.contadores_crudos_leads_citas() c where c.objeto not in (select a.objeto from pg_temp._b6_censo_antes a))
    and (select count(*) from pg_temp._b6_censo_antes) = (select count(*) from private.contadores_crudos_leads_citas())
  ) is not true then
    raise exception 'POSTFLIGHT: la regla, el candado o el gris no quedaron como se esperaba, o el censo cambio';
  end if;
  raise notice 'base_gestion_seguimiento_activo OK: regla única, candado en el lead para toda vía, gris en el rescate, censo intacto';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
```
### diff crm.rescate_descartes_mes (vivo → B6)
```diff
@@ -41,8 +41,9 @@
       and l.etapa = 'descartado'
       and l.descartado_en is not distinct from la.resultado_en
       and la.motivo_descarte_cierre <> 'datos_invalidos'
       and l.no_contactar is not true
+      and g.hasta is null  -- B6: con seguimiento activo del analista no se puede elegir
     ) as puede_rescatar,
     case
       when l.activo = true
        and l.etapa = 'descartado'
@@ -56,12 +57,24 @@
         where la_posterior.lead_id = la.lead_id
           and la_posterior.asignado_en > la.resultado_en
       ) then 'rescatado'
       else 'historial'
-    end as estado
+    end as estado,
+    p_gestiona.nombre_completo as en_gestion_por,
+    g.hasta as en_gestion_hasta
   from crm.lead_asignaciones la
   join crm.leads l on l.id = la.lead_id
   join public.perfiles p_asesor on p_asesor.id = la.analista_id
+  -- B6 (Miguel, 03/10/2026): seguimiento activo SOLO de los episodios que hoy se podrían rescatar (los demás son historial).
+  left join lateral (
+    select private.base_gestion_en_gestion_hasta(l.id) as hasta
+     where l.activo = true
+       and l.etapa = 'descartado'
+       and l.descartado_en is not distinct from la.resultado_en
+       and la.motivo_descarte_cierre <> 'datos_invalidos'
+       and l.no_contactar is not true
+  ) g on true
+  left join public.perfiles p_gestiona on p_gestiona.id = l.vendedor_id and g.hasta is not null
   where la.resultado = 'descartado'
     and la.resultado_en is not null
     and la.resultado_en >= (v_mes::timestamp at time zone 'America/Lima')
     and la.resultado_en < ((v_mes + interval '1 month')::timestamp at time zone 'America/Lima')
```

## Pruebas · supabase/scripts/base-gestion/b6-seguimiento.sql
```sql
-- B6 · Seguimiento activo en el banco (una transacción, impersonación, ROLLBACK al final). Falla el proceso si hay FAIL.
-- El candado vive en el LEAD (trg_leads_00_seguimiento_activo): se prueba por el rescate, la ficha (PATCH) y «tomar lead libre».
-- Actores y leads: fixtures-b2.sql. S1 supervisa a A y B; S2 a C. LA (A), LB (B), LC (C): descartados con su episodio.
begin;
create temp table r (n serial, caso text, esperado text, obtenido text, ok boolean);
grant all on r to authenticated; grant usage, select on sequence r_n_seq to authenticated;
create function pg_temp.sesion(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text,''), true),
         set_config('request.jwt.claims', case when p is null then '' else json_build_object('sub', p, 'role', 'authenticated')::text end, true);
$$;
grant execute on function pg_temp.sesion(uuid) to authenticated;
create temp table f as select
  'b0000000-0000-4000-8000-000000000002'::uuid a, 'b0000000-0000-4000-8000-000000000012'::uuid b, 'b0000000-0000-4000-8000-000000000013'::uuid c,
  'b0000000-0000-4000-8000-000000000001'::uuid s1, 'b0000000-0000-4000-8000-000000000011'::uuid s2, 'b0000000-0000-4000-8000-000000000003'::uuid g,
  'b0000000-0000-4000-8000-0000000000a1'::uuid la, 'b0000000-0000-4000-8000-0000000000b1'::uuid lb, 'b0000000-0000-4000-8000-0000000000c1'::uuid lc,
  (select la.id from crm.lead_asignaciones la join crm.leads l on l.id = la.lead_id where l.id = 'b0000000-0000-4000-8000-0000000000a1' and la.resultado = 'descartado' and la.resultado_en = l.descartado_en) ep_la,
  (select la.id from crm.lead_asignaciones la join crm.leads l on l.id = la.lead_id where l.id = 'b0000000-0000-4000-8000-0000000000b1' and la.resultado = 'descartado' and la.resultado_en = l.descartado_en) ep_lb,
  (select la.id from crm.lead_asignaciones la join crm.leads l on l.id = la.lead_id where l.id = 'b0000000-0000-4000-8000-0000000000c1' and la.resultado = 'descartado' and la.resultado_en = l.descartado_en) ep_lc,
  (select date_trunc('month', descartado_en at time zone 'America/Lima')::date from crm.leads where id = 'b0000000-0000-4000-8000-0000000000a1') mes,
  (now() at time zone 'America/Lima')::date hoy,
  -- Leídos como postgres: B (otro analista) no ve LA por RLS; «tomar lead libre» llega por el teléfono que le dicta la persona.
  (select telefono from crm.leads where id = 'b0000000-0000-4000-8000-0000000000a1') tel_la,
  (select dni from crm.leads where id = 'b0000000-0000-4000-8000-0000000000a1') dni_la;
grant select on f to authenticated;
-- Los descartes del banco son de ayer: para probar «hace 7 u 8 días» el ciclo tiene que empezar antes. Se mueven 30 días
-- atrás el descarte de LA y LC y su episodio, juntos (el episodio sigue vigente), sin disparar sellos (solo en esta transacción).
set local session_replication_role = replica;
update crm.leads set descartado_en = descartado_en - interval '30 days' where id in ((select la from f), (select lc from f));
do $mover$ begin  -- TODAS las fechas del episodio, para que sus CHECK de orden sigan valiendo
  execute format('update crm.lead_asignaciones set %s where id = any(%L::uuid[])',
    (select string_agg(format('%1$I = %1$I - interval ''30 days''', attname), ', ') from pg_attribute
      where attrelid = 'crm.lead_asignaciones'::regclass and atttypid = 'timestamptz'::regtype and attnum > 0 and not attisdropped),
    (select array[ep_la, ep_lc] from f));
end $mover$;
set local session_replication_role = origin;
create temp table m as select l.id lead_id, date_trunc('month', l.descartado_en at time zone 'America/Lima')::date mes from crm.leads l, f where l.id in (f.la, f.lb, f.lc);
grant select on m to authenticated;
create function pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$ insert into r(caso, esperado, obtenido) values (p_caso, p_esperado, p_obtenido); $$;
grant execute on function pg_temp.caso(text,text,text) to authenticated;
create function pg_temp.err(p_caso text, p_esperado text, p_sql text) returns void language plpgsql as $$
begin execute p_sql; perform pg_temp.caso(p_caso, p_esperado, 'paso'); exception when others then perform pg_temp.caso(p_caso, p_esperado, sqlstate || ' ' || sqlerrm); end $$;
grant execute on function pg_temp.err(text,text,text) to authenticated;
-- Fila del Centro de rescate de un episodio, leída por el actor de la sesión: «puede|por|hasta|estado».
create function pg_temp.fila(p_ep uuid) returns text language sql as $$
  select coalesce((select format('%s|%s|%s|%s', x.puede_rescatar::text, coalesce(x.en_gestion_por, '-'), coalesce(x.en_gestion_hasta::text, '-'), x.estado)
                     from m, crm.rescate_descartes_mes(m.mes) x where x.episodio_id = p_ep and x.lead_id = m.lead_id), 'sin fila'); $$;
grant execute on function pg_temp.fila(uuid) to authenticated;
-- El detail del rechazo de un reparto (con la sesión vigente).
create function pg_temp.detalle_rechazo(p_ep uuid, p_dest uuid) returns jsonb language plpgsql as $$
declare d text;
begin
  perform crm.rescatar_descartes(array[p_ep], array[p_dest]);
  return '{"estado":"paso"}'::jsonb;
exception when sqlstate 'P0409' then
  get stacked diagnostics d = pg_exception_detail;
  return d::jsonb;
when others then
  return pg_catalog.jsonb_build_object('estado', 'otro_error', 'sqlstate', sqlstate);
end $$;

select pg_temp.caso('banco: los tres episodios existen', 'ok', case when (select ep_la is not null and ep_lb is not null and ep_lc is not null from f) then 'ok' else 'faltan' end);

-- ───────── Sin seguimiento: todo como antes ─────────
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1: LA sin intentos → se puede elegir, sin gris', 'true|-|-|pendiente', pg_temp.fila((select ep_la from f)));
reset role;

-- ───────── A registra un intento en LA → 7 días en gestión ─────────
select pg_temp.sesion((select a from f)); set local role authenticated;
select crm.registrar_intento_base(gen_random_uuid(), (select la from f), 'no_contesto', 'sin respuesta');
reset role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1: LA con intento de hoy → gris, por A, hasta hoy+7, estado sigue pendiente (bundle viejo)', (select format('false|BANCO VENDEDOR|%s|pendiente', hoy + 7) from f), pg_temp.fila((select ep_la from f)));
select pg_temp.caso('S1: LB (sin intentos) sigue elegible', 'true|-|-|pendiente', pg_temp.fila((select ep_lb from f)));
select pg_temp.err('S1: repartir LA → P0409 del candado, sin nombres', 'P0409 Este lead lo está trabajando su analista hasta el ' || (select to_char(hoy + 7, 'DD/MM/YYYY') from f) || ': no se le puede cambiar el responsable',
  format('select crm.rescatar_descartes(array[%L]::uuid[], array[%L]::uuid[])', (select ep_la from f), (select b from f)));
select pg_temp.err('S1: lote LA + LB → P0409, todo o nada', 'P0409', format('select crm.rescatar_descartes(array[%L, %L]::uuid[], array[%L]::uuid[])', (select ep_la from f), (select ep_lb from f), (select b from f)));
reset role;
update r set obtenido = split_part(obtenido, ' ', 1) where caso like 'S1: lote LA + LB%';
select pg_temp.caso('S1: tras el lote rechazado, LB sigue descartado y de B', 'descartado/B', (select etapa || '/' || case when vendedor_id = f.b then 'B' else 'otro' end from crm.leads, f where id = f.lb));
select pg_temp.caso('detail del rechazo: estado en_gestion con el lead y la fecha', 'ok',
  (select case when d->>'estado' = 'en_gestion' and d->>'lead_id' = f.la::text and d->>'hasta' = (f.hoy + 7)::text then 'ok' else d::text end
     from f, lateral (select pg_temp.detalle_rechazo(f.ep_la, f.b) d) q));

-- ───────── La ficha (PATCH de vendedor_id, lo que hace store.reasignar) ─────────
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.err('S1: la ficha le cambia el responsable a LA (en gestión) → P0409', 'P0409',
  format('update crm.leads set vendedor_id = %L where id = %L', (select b from f), (select la from f)));
select pg_temp.err('S1: la ficha le cambia el responsable a LB (sin seguimiento) → pasa', 'paso',
  format('update crm.leads set vendedor_id = %L where id = %L', (select a from f), (select lb from f)));
reset role;
update r set obtenido = split_part(obtenido, ' ', 1) where caso = 'S1: la ficha le cambia el responsable a LA (en gestión) → P0409';
select set_config('crm.op_base_gestion', 'off', true);
set local session_replication_role = replica;  -- deja LB como estaba (de B) para los casos siguientes
update crm.leads set vendedor_id = (select b from f) where id = (select lb from f);
set local session_replication_role = origin;

-- ───────── «Tomar lead libre»: otro analista no se lleva un lead en gestión ─────────
select pg_temp.sesion((select b from f)); set local role authenticated;
select pg_temp.err('B toma LA por su teléfono (en gestión de A) → P0409', 'P0409',
  format('select crm.tomar_lead_libre(%L, %L)', (select tel_la from f), (select dni_la from f)));
reset role;
update r set obtenido = split_part(obtenido, ' ', 1) where caso like 'B toma LA%';
select pg_temp.caso('tras el intento de B, LA sigue descartado y de A', 'descartado/A', (select etapa || '/' || case when vendedor_id = f.a then 'A' else 'otro' end from crm.leads, f where id = f.la));

-- ───────── Una baja libera: dueño inactivo → sin seguimiento ─────────
set local session_replication_role = replica;
update crm.equipo set activo = false where perfil_id = (select a from f);
set local session_replication_role = origin;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1: con A dado de baja, LA vuelve a ser elegible', 'true|-|-|pendiente', pg_temp.fila((select ep_la from f)));
reset role;
set local session_replication_role = replica;
update crm.equipo set activo = true where perfil_id = (select a from f);
set local session_replication_role = origin;

-- ───────── Al día 8 sin otro intento, vuelve ─────────
update crm.actividades set creado_en = creado_en - interval '8 days' where lead_id = (select la from f) and metadata->>'evento' = 'intento_base';
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1: intento de hace 8 días → vuelve a ser elegible', 'true|-|-|pendiente', pg_temp.fila((select ep_la from f)));
reset role;
update crm.actividades set creado_en = creado_en + interval '1 day' where lead_id = (select la from f) and metadata->>'evento' = 'intento_base';
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1: intento de hace 7 días → hoy es su último día en gestión', (select format('false|BANCO VENDEDOR|%s|pendiente', hoy) from f), pg_temp.fila((select ep_la from f)));
reset role;

-- ───────── Rellamada vigente (pregunta 1 de Miguel: también cuenta) ─────────
select pg_temp.sesion((select c from f)); set local role authenticated;
select crm.registrar_intento_base(gen_random_uuid(), (select lc from f), 'volver_a_llamar', 'llamar el lunes', now() + interval '9 days');
reset role;
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.caso('S2: LC con rellamada a 9 días → gris hasta el día de la rellamada (más lejos que +7)',
  (select format('false|BANCO VENDEDOR C|%s|pendiente', ((now() + interval '9 days') at time zone 'America/Lima')::date) from f), pg_temp.fila((select ep_lc from f)));
reset role;
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.caso('G: LC también en gris para gerencia', (select format('false|BANCO VENDEDOR C|%s|pendiente', ((now() + interval '9 days') at time zone 'America/Lima')::date) from f), pg_temp.fila((select ep_lc from f)));
reset role;
update crm.actividades set creado_en = creado_en - interval '20 days' where lead_id = (select lc from f) and metadata->>'evento' = 'intento_base';
select set_config('crm.op_base_gestion', 'on', true);  -- el sello solo deja escribir la rellamada al núcleo
update crm.leads set proxima_llamada_en = now() - interval '2 days' where id = (select lc from f);
select set_config('crm.op_base_gestion', 'off', true);
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.caso('S2: rellamada vencida hace 2 días y sin intento reciente → elegible', 'true|-|-|pendiente', pg_temp.fila((select ep_lc from f)));
reset role;
select set_config('crm.op_base_gestion', 'on', true);  -- el sello solo deja escribir la rellamada al núcleo
update crm.leads set proxima_llamada_en = now() + interval '3 days' where id = (select lc from f);
select set_config('crm.op_base_gestion', 'off', true);
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.caso('S2: solo la rellamada vigente (intento viejo) → gris', 'false', split_part(pg_temp.fila((select ep_lc from f)), '|', 1));
reset role;
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.err('G: repartir LC (rellamada vigente) a OTRO analista → P0409', 'P0409', format('select crm.rescatar_descartes(array[%L]::uuid[], array[%L]::uuid[])', (select ep_lc from f), (select a from f)));
reset role;
update r set obtenido = split_part(obtenido, ' ', 1) where caso like 'G: repartir LC%';
-- Una rellamada que quedó de un ciclo ANTERIOR (sin intento en este ciclo) no bloquea:
update crm.actividades set creado_en = creado_en - interval '30 days' where lead_id = (select lc from f) and metadata->>'evento' = 'intento_base';
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.caso('S2: rellamada vigente pero de un ciclo anterior (sin intento en este) → elegible', 'true|-|-|pendiente', pg_temp.fila((select ep_lc from f)));
reset role;


-- ───────── La regla no se expone ─────────
select pg_temp.caso('authenticated sin EXECUTE sobre la ayudante', 'false', has_function_privilege('authenticated', 'private.base_gestion_en_gestion_hasta(uuid)', 'EXECUTE')::text);
select pg_temp.caso('anon sin EXECUTE sobre la ayudante', 'false', has_function_privilege('anon', 'private.base_gestion_en_gestion_hasta(uuid)', 'EXECUTE')::text);
-- NO se prueba llamándola sin permiso: en la imagen Supabase 17.6 eso tumba el backend (memoria
-- postgres-cae-por-permiso-de-funcion, 20/08). Bastan los has_function_privilege de arriba.
select pg_temp.caso('ayudante: lead no descartado → NULL', 'null', coalesce(private.base_gestion_en_gestion_hasta((select id from crm.leads where etapa <> 'descartado' limit 1))::text, 'null'));

-- ───────── Sin seguimiento, el reparto sigue funcionando ─────────
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1: repartir LB (sin seguimiento) a A → 1 rescatado', '1', (crm.rescatar_descartes(array[(select ep_lb from f)], array[(select a from f)]))->>'rescatados');
reset role;

-- ───────── B5: el mes del lead ─────────
select pg_temp.sesion((select a from f)); set local role authenticated;
select pg_temp.caso('B5: A ve recibido_en = coalesce(tenencia_desde, creado_en) en su base', 'ok',
  (select case when bool_and(b.recibido_en is not distinct from coalesce(l.tenencia_desde, l.creado_en)) and count(*) > 0 then 'ok' else 'mal' end
     from crm.obtener_base_gestion() b join crm.leads l on l.id = b.lead_id));
reset role;
select pg_temp.caso('B3c+B5+B6: ninguna pieza del módulo está en el censo analítico', '0',
  (select count(*)::text from private.contadores_crudos_leads_citas() c
    where c.objeto ~ '^(crm|private)\.(obtener_base_gestion|base_gestion_[a-z_]+|rescate_descartes_mes|trg_leads_guard_seguimiento_activo|trg_actividades_enfriamiento_base)\('));

-- ───────── Límite aceptado: devolverlo a su MISMO analista no es reasignar ─────────
-- (el gris impide elegirlo en pantalla; por la RPC, con evitar origen = false, el candado no salta porque el dueño no cambia)
update crm.actividades set creado_en = creado_en + interval '30 days' where lead_id = (select lc from f) and metadata->>'evento' = 'intento_base';
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.caso('S2: LC vuelve a estar en gris (intento del ciclo + rellamada vigente)', 'false', split_part(pg_temp.fila((select ep_lc from f)), '|', 1));
select pg_temp.caso('S2: devolver LC a su MISMO analista C (evitar origen = false) → pasa: el dueño no cambia', '1',
  (crm.rescatar_descartes(array[(select ep_lc from f)], array[(select c from f)], false))->>'rescatados');
reset role;

-- ───────── Resultado ─────────
update r set ok = (obtenido = esperado);
select format('%s %s · esperado %s · obtenido %s', case when ok then 'PASS' else 'FAIL' end, caso, esperado, left(obtenido, 200)) from r order by n;
select format('TOTAL: %s PASS · %s FAIL', count(*) filter (where ok), count(*) filter (where not ok)) from r;
do $$ begin if exists (select 1 from r where not ok) then raise exception 'B6: hay casos FAIL'; end if; end $$;
rollback;
```
