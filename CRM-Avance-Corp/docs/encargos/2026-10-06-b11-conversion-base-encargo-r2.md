ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

# Encargo r2 (ÚLTIMA ronda): refutar B11 de «Bases cargadas» (CRM Avance Corp) — LEVEL 3 (datos/conversión)

Tu tarea es intentar REFUTAR que este cambio es correcto y seguro. No tienes base de datos ni red: todo lo que necesitas
está transcrito abajo (diffs exactos contra los cuerpos vivos de producción y resultados medidos). Responde en español.

## Protocolo de revisión (global, transcrito)
# Protocolo global Codex ↔ Claude Code

Aplica al usuario de esta Mac, en cualquier proyecto, aunque no exista `.ai/`.
Las instrucciones del repositorio definen negocio, arquitectura y comandos;
este protocolo define los roles y el aislamiento de las consultas.

## Roles y autoridad

- PRIMARY: posee la tarea, inspecciona, decide, implementa, ejecuta checks,
  evalúa hallazgos y entrega el resultado. Es el único escritor.
- SECONDARY_REVIEWER: analiza evidencia, bugs, regresiones, seguridad,
  arquitectura, casos límite y pruebas faltantes. No escribe archivos, no
  implementa, no hace commits, no cambia configuración, no ejecuta acciones
  destructivas, no llama al otro agente y no delega ni inicia otro review.
- Una tarea normal del usuario define un PRIMARY. Un prompt que comienza con
  `ROLE: SECONDARY_REVIEWER` define un consultor, aunque existan instrucciones
  generales de autonomía. Si le piden otra opinión, devuelve su propio análisis.
- La única cadena permitida es PRIMARY → SECONDARY_REVIEWER → PRIMARY.
- El reviewer es asesor; el PRIMARY decide con evidencia. Un PASS de IA no
  significa que la tarea esté terminada.

## Cuándo consultar

- LEVEL 1: formato, documentación sencilla, CSS pequeño, rename o fix obvio:
  cero consultas.
- LEVEL 2: lógica relevante, integración, endpoint, componente importante o
  refactor moderado: normalmente una consulta si aporta valor independiente.
- LEVEL 3: auth, permisos, secretos, seguridad, schemas/migraciones, arquitectura,
  concurrencia, pagos, lógica financiera, APIs importantes o cambios destructivos:
  una consulta cuando sea razonablemente posible.
- Máximo habitual: dos consultas por tarea, contando reviewers especializados.
  La segunda necesita nueva evidencia, discrepancia importante o corrección de
  riesgo que justifique otra verificación. No repetir hasta conseguir un PASS.
- Las instrucciones explícitas del usuario sobre consultas prevalecen. No
  consultar para confirmar trivialidades ni abrir cadenas recursivas.

## Evidence-first y formato

**NO FINDING WITHOUT EVIDENCE.** Citar archivo/líneas, símbolo, diff, test,
error, log o reproducción. Identificar como hipótesis lo no demostrado.
Omitir secciones vacías y recomendaciones genéricas sin relación con la tarea.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Conclusión técnica breve.

FINDINGS:
[P0 | P1 | P2 | P3] Título
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

TEST GAPS:
- ...
ARCHITECTURE RISKS:
- ...
SECURITY RISKS:
- ...
REGRESSION RISKS:
- ...
RECOMMENDED NEXT ACTIONS:
1. ...
CONFIDENCE:
HIGH | MEDIUM | LOW
```

PASS: sin hallazgos obligatorios en lo revisado. CHANGES_REQUESTED: correcciones
accionables. BLOCK: riesgo crítico o evidencia insuficiente para revisar.
Resolver desacuerdos por requisitos, comportamiento, pruebas y documentación
oficial, no mediante consultas repetitivas.

## Interfaces

Codex PRIMARY usa `~/.local/bin/claude-review`, o el wrapper del repo cuando
sus instrucciones lo requieran. Adjunta código/diff saneado, rutas/líneas,
requisitos y resultados de checks. No enviar secretos. CodeGraph se usa por
el PRIMARY si el proyecto está indexado, nunca se indexa automáticamente.

El wrapper global incorpora este protocolo y, si existe, el protocolo `.ai/`
del proyecto. Claude reviewer tiene todas las herramientas, MCP, hooks y
personalizaciones deshabilitadas; no persiste la sesión. Cinco turnos por
defecto, máximo ocho. Exit 0 indica entrega válida, no necesariamente PASS.
Usa `dontAsk`, sin solicitudes de permiso, y comprueba que el evento de inicio
declare cero herramientas y cero MCP antes de aceptar un resultado único.
Las menciones genéricas a herramientas en el texto del modelo no acreditan
disponibilidad: la comprobación debe usar el inventario efectivo de la CLI.

Claude PRIMARY usa `mcp__codex__codex` con:

```text
sandbox: read-only
approval-policy: never
prompt:
ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
```

Adjuntar el contenido de este protocolo, las reglas relevantes del proyecto y
la evidencia: el reviewer no tiene herramientas para abrirlos. Solo se permite
añadir `model`; no `cwd`, `config` ni overrides de instrucciones. `codex-reply`
está bloqueado; una segunda consulta justificada inicia otro review seguro.

El MCP global usa `~/.local/bin/codex-review-mcp`. Trabaja en una carpeta neutral
de esta instalación para no cargar configuración específica de otros proyectos.
Deshabilita shell, subagentes, apps, hooks, navegador, plugins y cada MCP heredado.
Las tablas vacías TOML se fusionan: no sirven para eliminar los MCP del usuario.
Una entrada MCP local/de proyecto puede tener precedencia; comprobar su
aislamiento antes de usarla. No sustituir una interfaz protegida por una directa.

## Verificación, simultaneidad y límites

Aplicar `~/.config/ai-collaboration/VERIFICATION.md` y los gates concretos del repo.
Dos PRIMARY simultáneos en tareas distintas requieren working trees separados.
No crear worktrees automáticamente; un reviewer read-only no necesita uno.

Los hooks globales de Claude protegen secretos y operaciones peligrosas comunes;
los hooks no analizan los efectos indirectos de scripts arbitrarios. Las reglas
nativas ocultan `.env.*` también en búsquedas; incluyen `.env.example`, que se
gestiona manualmente. El usuario conserva sus modelos, plugins y ajustes normales.

El inventario del MCP se fija al arrancar. No cambiar MCP/plugins/configuración
de agentes durante el review. Tras cambiarlos, reconectar `codex` y ejecutar
`~/.local/bin/codex-review-mcp --check` antes de la siguiente consulta. No se
afirma aislamiento frente a cambios concurrentes de terceros.


## Qué se pide (decisión de negocio CERRADA, no se discute)
E10 de Miguel: el cierre de un contacto de «base cargada por archivo» (origen `base_cargada`) cuenta ENTERO (peso 1) en
el numerador de la conversión del analista que lo consigue y NO entra al divisor (como la regla cerrada del «registro
manual»). Los armados desde el CRM conservan su origen y su regla. «Resultados por origen» NO lleva fila de base.
Conversión = numerador / divisor por analista y mes (Lima). Divisor = llegadas landing/formulario sin alta manual
(private.conversion_episodios, NO se toca). Numerador = cierres ponderados (landing/formulario 1, referido su peso,
oficina y otros 0) + upgrade 1 + renovación su peso. Desde 09/2026 los cierres salen de crm.conversion_acreditaciones.
Regla de Miguel: la anulación de gerencia es la única puerta que puede mover un mes ya liquidado.

## Medido en producción antes (solo lectura, 05/10/2026)
- 0 leads con origen base_cargada; 0 cierres de base (ledger y acreditaciones); crm.periodos_cerrados VACÍA (ningún mes
  sellado); política de acreditación activa.
- El origen de un lead NO se puede cambiar tras el alta (private.leads_before_update lanza P0409); el origen base_cargada
  solo lo pone la carga de bases (trigger con válvula de sesión).
- La lista ('landing','formulario','referido') estaba copiada en 8 funciones; la pantalla «Divisor de coordinación»
  exige en el navegador que formulario + landing + referido_aporte + upgrade + renovacion_aporte = numerador_bruto.
- Rojo PREVIO y ajeno en el censo analítico: private.gestion_diaria_cola_hechos sin declarar (también en prod).
- Dueño de todas las piezas: postgres; las privadas con ACL {postgres=X/postgres}; las dos crm.* con authenticated.
  private.metricas_distribucion_leads_v3_core es INVOKER y la llama private.metricas_distribucion_leads_autorizada
  (DEFINER, dueño postgres); el resto son DEFINER.

## Cabecera de la migración (la explicación del autor)
```sql
-- 20261006042144_crm_bases_cargadas_conversion.sql
--
-- Bases cargadas · B11: el cierre de un contacto de base cargada por archivo cuenta ENTERO (peso 1) para el analista que lo
-- consigue y NO entra al divisor. Decisión E10 de Miguel (`BASE PARA GESTION/BASES-CARGADAS.md`), como la regla cerrada del
-- registro manual. Plan aprobado el 05/10/2026, con dos respuestas: (1) los armados desde el CRM conservan su origen y su
-- regla de siempre (B11 es solo el origen `base_cargada`); (2) «Resultados por origen» NO lleva fila de base cargada.
--
-- MEDIDO EN PRODUCCIÓN (05/10, solo lectura)
--   · Divisor: private.conversion_episodios cuenta llegadas landing/formulario sin alta manual ⇒ base_cargada YA está fuera, y
--     el origen no cambia tras el alta (private.leads_before_update, P0409). El divisor NO se toca.
--   · Numerador: private.conversion_cierres da 1 solo a landing/formulario ⇒ un cierre de base suma 0. Ese es el hueco.
--   · 0 contactos de base, 0 cierres de base, crm.periodos_cerrados vacía: ningún número existente cambia.
--   · La lista ('landing','formulario','referido') estaba COPIADA en 8 piezas: cambiar solo el peso desalinearía los conteos
--     de cierres de su numerador (Rendimiento, Equipo, Distribución, conversión mensual).
--
-- QUÉ HACE
--   1. NUEVA private.conversion_origen_con_cierre(text): UNA definición de qué orígenes cuentan un cierre (landing,
--      formulario, referido, base_cargada). INVOKER, IMMUTABLE, sin ejecutores de la API.
--   2. Mismo texto VIVO, con la lista cambiada por el ayudante (CREATE OR REPLACE: firma, dueño, seguridad y ACL intactos):
--      private.conversion_cierres (sus dos ramas: la 3.ª rama del peso, ya sin el referido, da 1), private.registrar_ajuste_si_
--      mes_cerrado (el ajuste de un mes sellado pesa lo mismo), private.conversion_mensual_por_vendedor (cierres y procedencia),
--      crm.metricas_conversiones_equipo_fn (3), private.metricas_conversiones_implementacion (9),
--      private.metricas_distribucion_leads_v3_core (2) y la sonda de crm.conversion_mensual_sin_cartera_fn.
--   3. Divisor de coordinación: su pantalla exige que las partes sumen el numerador bruto (app/src/lib/conversion-
--      coordinacion.ts, sumaDePartes). private.conversion_divisor_empresa y private.conversion_divisor_empresa_totales ganan
--      `cierres_base_cargada` AL FINAL de su RETURNS TABLE (drop + create con la misma ACL; sus únicos llamadores son
--      private.conversion_divisor_empresa_totales y crm.conversion_divisor_coordinacion_fn, plpgsql, por nombre de columna);
--      `cierres_otros` ya no los incluye; en un mes SELLADO la foto no los guarda ⇒ NULL (no se inventa un 0).
--      crm.conversion_divisor_coordinacion_fn añade la clave `base_cargada` en los dos objetos `cierres`. La pantalla que la
--      entiende se publica ANTES que esta migración (dirección: pantalla primero); la publicada hoy ignora la clave nueva.
--   4. Censo analítico: las cuatro declaraciones de las piezas tocadas se quedan en su fila (clase, tipo, razón y fecha) con la
--      huella del cuerpo nuevo, y se resella (patrón de 20261001212341). El techo no cambia.
-- QUÉ NO CAMBIA: el divisor (private.conversion_episodios), «Resultados por origen» (private.ranking_conversion_origen_mes y
--   la foto del cierre), tablas, policies, grants, triggers, firmas de las puertas de la API y sus ACL.
-- FRENO: el preflight se niega si ya existe algún cierre de un contacto de base (ledger o acreditación): entonces B11 movería
--   un número que ya existe y se revisa con Miguel.
--   Para que ese freno valga hasta el commit, la transacción bloquea antes de su primera lectura las dos tablas donde nace
--   un cierre (crm.lead_asignaciones y crm.conversion_acreditaciones, SHARE ROW EXCLUSIVE NOWAIT): durante la aplicación
--   (menos de un segundo) nadie confirma un cierre nuevo; si alguien escribe en ese instante, se niega y se repite.
--   También se niega si aparece un llamador nuevo de las dos privadas que se recrean (se busca en el texto de las funciones:
--   pg_depend no ve una llamada hecha desde plpgsql) o si cambió alguno de los diez cuerpos, su dueño o su ACL.
-- POSTFLIGHT: huellas medidas en el banco, ninguna copia de la lista, el ayudante dice lo ensayado, las columnas nuevas al
--   final, el censo con los MISMOS rojos que antes (hoy uno ajeno: private.gestion_diaria_cola_hechos sin declarar) y el
--   desglose del Divisor de coordinación del mes en curso sumando su numerador bruto en cada fila.
-- REVERSA: supabase/scripts/base-gestion/reversa-b11.sql (repone los diez cuerpos vivos, las firmas viejas del divisor, sus
--   comentarios y las cuatro huellas; borra el ayudante; se niega si hay cierres de base, porque cambiaría sus números, si
--   otra función ya usa el ayudante o si el censo analítico no está vigente y sellado antes de empezar).

```

## Preflight y ayudante nuevo (texto exacto)
```sql
-- Exclusión de migraciones ANTES de la instantánea: candado de SESIÓN en su propia transacción.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set transaction isolation level repeatable read;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local search_path = '';
set local quote_all_identifiers = off;

-- Nadie registra un cierre mientras esto corre: el candado se toma ANTES de la primera lectura (la instantánea de
-- REPEATABLE READ nace en la primera consulta, es decir, después), así que el freno «no hay cierres de base» vale hasta
-- el commit. NOWAIT: si alguien está escribiendo en ese instante, se niega sin esperar (no puede interbloquearse con
-- nadie ni dejar colgado a un usuario) y se repite. Las lecturas no se bloquean. Va suelto, no en un DO: un DO ya
-- tomaría la instantánea antes de bloquear.
lock table crm.lead_asignaciones, crm.conversion_acreditaciones in share row exclusive mode nowait;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
declare
  r record;
begin
  if not exists (select 1 from pg_locks l
                  where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted and l.mode = 'ExclusiveLock'
                    and l.objsubid = 1
                    and ((l.classid::bigint << 32) | l.objid::bigint) = hashtext('crm_migracion_funciones')::bigint) then
    raise exception 'B11: falta el candado de migraciones' using errcode = 'P0409';
  end if;
  if to_regprocedure('private.conversion_origen_con_cierre(text)') is not null
     or exists (select 1 from pg_proc p where p.proname = 'conversion_origen_con_cierre') then
    raise exception 'B11: el ayudante ya existe (¿B11 ya aplicada?)' using errcode = 'P0409';
  end if;
  -- B7 aplicada: el origen base_cargada existe.
  if not exists (select 1 from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_origen_check'
                  and pg_get_constraintdef(c.oid) like '%base_cargada%') then
    raise exception 'B11: falta el origen base_cargada (B7)' using errcode = 'P0409';
  end if;
  -- Los diez cuerpos vivos, su dueño y su ACL, tal como se ensayaron.
  for r in select * from (values
    ('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])', 'b1d6c336d198036db4ddad83a075ebdb', '{postgres=X/postgres}'),
    ('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)', '00b17e7774f821eb04f0802f18039569', '{postgres=X/postgres}'),
    ('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)', '6e62d66e1c9536a50657245d6e633f56', '{postgres=X/postgres}'),
    ('crm.metricas_conversiones_equipo_fn(date,date)', 'cbae26a3031e01580068c9336baf798b', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.metricas_conversiones_implementacion(date,date,text)', '1a0e7f7fd01977e556a13fea14ddc5aa', '{postgres=X/postgres}'),
    ('private.metricas_distribucion_leads_v3_core(date,date,timestamptz)', 'd73e12275649b756b71de50fd176d697', '{postgres=X/postgres}'),
    ('crm.conversion_mensual_sin_cartera_fn(date)', 'f613d94208b035f241c4e13b351c55be', '{postgres=X/postgres}'),
    ('private.conversion_divisor_empresa(date,date)', '5700d2770d1796440aa0184b035d623a', '{postgres=X/postgres}'),
    ('private.conversion_divisor_empresa_totales(date,date)', 'e97995f5ffd9109fce87f2e5dafb11a6', '{postgres=X/postgres}'),
    ('crm.conversion_divisor_coordinacion_fn(date,date,date)', 'b881b83ca8d4dd2f0f081d736828c8c5', '{postgres=X/postgres,authenticated=X/postgres}')
  ) as v(firma, huella, acl) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(r.firma) and md5(p.prosrc) = r.huella
                    and p.proowner = 'postgres'::regrole and p.proacl::text = r.acl) then
      raise exception 'B11: % cambió desde el ensayo; revisar antes de aplicar', r.firma using errcode = 'P0409';
    end if;
  end loop;
  -- Las dos privadas que se recrean (drop + create) solo tienen los dos llamadores ensayados. pg_depend no ve una
  -- llamada hecha desde plpgsql, así que se mira el texto: un llamador nuevo quedaría roto por el cambio de columnas.
  if exists (select 1 from pg_proc p
              where p.prosrc ~ 'conversion_divisor_empresa(_totales)?\s*\('
                and p.oid not in (to_regprocedure('private.conversion_divisor_empresa_totales(date,date)'),
                                  to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)'))) then
    raise exception 'B11: hay un llamador nuevo del divisor de empresa; revisar antes de aplicar' using errcode = 'P0409';
  end if;
  -- Las cuatro declaraciones del censo analítico existen y están vigentes (su huella = su cuerpo de hoy).
  if (select count(*) from private.analitica_leads_citas_exenciones e
        join pg_proc p on p.oid = to_regprocedure(e.objeto)
       where to_regprocedure(e.objeto) in (to_regprocedure('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'), to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)'), to_regprocedure('private.metricas_conversiones_implementacion(date,date,text)'), to_regprocedure('crm.conversion_mensual_sin_cartera_fn(date)'))
         and e.huella = md5(regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))) <> 4 then
    raise exception 'B11: una declaracion analitica de las funciones tocadas no esta vigente' using errcode = 'P0409';
  end if;
  if (select s.sello from private.analitica_lc_sello s where s.id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'B11: el sello del censo analitico no esta al dia' using errcode = 'P0409';
  end if;
  -- Freno (prometido a Miguel): B11 no cambia ningún número ya existente. Si ya hay un cierre de base, se para y se mira.
  if exists (select 1 from crm.lead_asignaciones la join crm.leads l on l.id = la.lead_id
              where la.resultado = 'convertido' and l.origen = 'base_cargada')
     or exists (select 1 from crm.conversion_acreditaciones ca where ca.origen = 'base_cargada') then
    raise exception 'B11: ya existe un cierre de un contacto de base; revisar con Miguel antes de aplicar' using errcode = 'P0409';
  end if;
end;
$preflight$;

-- Foto del censo ANTES (los rojos ajenos deben seguir exactamente iguales después).
create temporary table b11_censo_antes on commit drop as
  select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c;

-- ── 1 · El ayudante único ─────────────────────────────────────────────────────────────────────────────────────────────
create function private.conversion_origen_con_cierre(p_origen text)
returns boolean
language sql
immutable
parallel safe
security invoker
set search_path = ''
as $$
  select p_origen in ('landing', 'formulario', 'referido', 'base_cargada')
$$;
revoke all on function private.conversion_origen_con_cierre(text) from public, anon, authenticated, service_role;
comment on function private.conversion_origen_con_cierre(text) is
  'B11 (05/10/2026): UNA definición de qué orígenes cuentan un cierre en la conversión: landing, formulario, referido y base_cargada (contactos de una base cargada por archivo: pesan 1 y NO entran al divisor, como la regla cerrada del registro manual). Oficina y los demás orígenes no cuentan. NULL con origen NULL (como el `in` al que reemplaza). El divisor no la usa: lo define private.conversion_episodios (solo landing y formulario sin alta manual). Usada por private.conversion_cierres (peso 1 tras la rama del referido), private.registrar_ajuste_si_mes_cerrado, private.conversion_mensual_por_vendedor, crm.metricas_conversiones_equipo_fn, private.metricas_conversiones_implementacion, private.metricas_distribucion_leads_v3_core y la sonda de crm.conversion_mensual_sin_cartera_fn.';

```

## Diffs EXACTOS: texto vivo de producción → migración (cada cuerpo completo = texto vivo + estos cambios)
### private.conversion_cierres — diff texto vivo (prod) → migración
```diff
--- vivo
+++ b11
@@ -15,7 +15,8 @@
       case when p_periodo is not null then p_factor else
         private.peso_referido_conversion(date_trunc('month',
           coalesce(la.resultado_en, la.finalizado_en) at time zone 'America/Lima')::date) end
-    when l.origen in ('landing', 'formulario') then 1
+    -- B11: landing, formulario y base_cargada pesan 1 (el referido ya salió por su rama).
+    when private.conversion_origen_con_cierre(l.origen) then 1
     else 0 end
 from crm.lead_asignaciones la
 join crm.leads l on l.id = la.lead_id
@@ -38,7 +39,7 @@
     when ca.origen = 'referido' then
       case when p_periodo is not null then p_factor
         else private.peso_referido_conversion(ca.periodo_comercial) end
-    when ca.origen in ('landing', 'formulario') then 1
+    when private.conversion_origen_con_cierre(ca.origen) then 1
     else 0 end
 from crm.conversion_acreditaciones ca
 join crm.leads l on l.id=ca.lead_id

```
### private.registrar_ajuste_si_mes_cerrado — diff texto vivo (prod) → migración
```diff
--- vivo
+++ b11
@@ -52,7 +52,7 @@
     v_acreditado:=v_acreditacion.analista_id;
     v_numerador:=case when v_acreditacion.origen='referido' then
       private.peso_referido_conversion(v_periodo)
-      when v_acreditacion.origen in ('landing','formulario') then 1 else 0 end;
+      when private.conversion_origen_con_cierre(v_acreditacion.origen) then 1 else 0 end;
     if v_acreditado is null or v_numerador<=0 then return null; end if;
     -- Para referidos prevalece el peso de la foto que efectivamente se pagó.
     if exists(select 1 from crm.conversion_acreditaciones ca

```
### private.conversion_mensual_por_vendedor — diff texto vivo (prod) → migración
```diff
--- vivo
+++ b11
@@ -22,7 +22,7 @@
   select e.analista_id, e.lead_id, e.fue_referido, e.mes_origen,
     date_trunc('month', p_ini at time zone 'America/Lima')::date as mes_periodo
   from ep e where e.tipo = 'cierre' and not e.anulado
-    and e.origen in ('landing', 'formulario', 'referido')
+    and private.conversion_origen_con_cierre(e.origen)
 ), motivos as (
   select r.analista_id, r.motivo, count(*)::int as n
   from recibidos r where r.aporte_divisor > 0

```
### crm.metricas_conversiones_equipo_fn — diff texto vivo (prod) → migración
```diff
--- vivo
+++ b11
@@ -149,7 +149,7 @@
     from private.conversion_episodios(
       v_ini, v_cosecha_fin, null::date, true, '{}'::uuid[], v_factor
     ) e
-    where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.lead_id is not null
+    where e.tipo = 'cierre' and not e.anulado and private.conversion_origen_con_cierre(e.origen) and e.lead_id is not null
   ),
   cohorte as materialized (
     select e.lead_id, e.analista_id as vendedor_id,
@@ -169,8 +169,8 @@
     select e.analista_id,
       coalesce(sum(e.aporte_divisor), 0)::int as divisor,
       count(*) filter (where e.tipo = 'recibido' and e.fue_referido)::int as referidos_recibidos,
-      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and not e.fue_referido)::int as cierres_no_referidos,
-      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.fue_referido)::int as cierres_referidos,
+      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and private.conversion_origen_con_cierre(e.origen) and not e.fue_referido)::int as cierres_no_referidos,
+      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and private.conversion_origen_con_cierre(e.origen) and e.fue_referido)::int as cierres_referidos,
       count(*) filter (where e.tipo = 'operacion')::int as operaciones,
       coalesce(sum(e.aporte_numerador), 0)::numeric as numerador
     from ep_flujo e

```
### private.metricas_conversiones_implementacion — diff texto vivo (prod) → migración
```diff
--- vivo
+++ b11
@@ -74,7 +74,7 @@
     from private.conversion_episodios(
       v_ini, v_cosecha_fin, null, true, null, v_factor
     ) e
-    where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.lead_id is not null
+    where e.tipo = 'cierre' and not e.anulado and private.conversion_origen_con_cierre(e.origen) and e.lead_id is not null
   ),
   cohorte_base as materialized (
     -- F1.3b: el capital del lead se mide por los caminos VIVOS y HASTA HOY
@@ -204,8 +204,8 @@
     select e.analista_id,
       coalesce(sum(e.aporte_divisor), 0)::int as divisor,
       count(*) filter (where e.tipo = 'recibido' and e.fue_referido)::int as referidos_recibidos,
-      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and not e.fue_referido)::int as cierres_no_referidos,
-      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.fue_referido)::int as cierres_referidos,
+      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and private.conversion_origen_con_cierre(e.origen) and not e.fue_referido)::int as cierres_no_referidos,
+      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and private.conversion_origen_con_cierre(e.origen) and e.fue_referido)::int as cierres_referidos,
       count(*) filter (where e.tipo = 'operacion')::int as operaciones,
       coalesce(sum(e.aporte_numerador), 0)::numeric as numerador
     from ep_flujo e
@@ -475,14 +475,14 @@
         select count(distinct e.lead_id)::int
         from ep_flujo e
         where e.tipo = 'cierre' and not e.anulado
-          and e.origen in ('landing', 'formulario', 'referido')
+          and private.conversion_origen_con_cierre(e.origen)
           and (p_origen is null or e.origen = p_origen)
       ),
       'aporte_cierres', (
         select coalesce(sum(e.aporte_numerador), 0)
         from ep_flujo e
         where e.tipo = 'cierre' and not e.anulado
-          and e.origen in ('landing', 'formulario', 'referido')
+          and private.conversion_origen_con_cierre(e.origen)
           and (p_origen is null or e.origen = p_origen)
       ),
       -- El total global conserva cierres de bajas, supervisores o autor nulo,
@@ -492,7 +492,7 @@
         select count(distinct e.lead_id)::int
         from ep_flujo e
         where e.tipo = 'cierre' and not e.anulado
-          and e.origen in ('landing', 'formulario', 'referido')
+          and private.conversion_origen_con_cierre(e.origen)
           and (p_origen is null or e.origen = p_origen)
           and (e.analista_id is null or not exists (
             select 1 from vendedores_base vb
@@ -503,7 +503,7 @@
         select coalesce(sum(e.aporte_numerador), 0)
         from ep_flujo e
         where e.tipo = 'cierre' and not e.anulado
-          and e.origen in ('landing', 'formulario', 'referido')
+          and private.conversion_origen_con_cierre(e.origen)
           and (p_origen is null or e.origen = p_origen)
           and (e.analista_id is null or not exists (
             select 1 from vendedores_base vb
@@ -543,7 +543,7 @@
           ) as gs(semana_indice)
           left join ep_flujo e
             on e.tipo = 'cierre' and not e.anulado
-           and e.origen in ('landing', 'formulario', 'referido')
+           and private.conversion_origen_con_cierre(e.origen)
            and (p_origen is null or e.origen = p_origen)
            and (e.fecha_numerador at time zone 'America/Lima')::date
                between p_desde + (gs.semana_indice * 7)
@@ -733,7 +733,7 @@
             ) as gs(semana_indice)
             left join ep_flujo e
               on e.tipo = 'cierre' and not e.anulado
-             and e.origen in ('landing', 'formulario', 'referido')
+             and private.conversion_origen_con_cierre(e.origen)
              and e.analista_id = rr.vendedor_id
              and (p_origen is null or e.origen = p_origen)
              and (e.fecha_numerador at time zone 'America/Lima')::date

```
### private.metricas_distribucion_leads_v3_core — diff texto vivo (prod) → migración
```diff
--- vivo
+++ b11
@@ -72,9 +72,9 @@
       coalesce(sum(e.aporte_divisor), 0)::int as divisor,
       count(*) filter (where e.tipo = 'recibido' and e.fue_referido)::int as referidos_recibidos,
       count(distinct e.lead_id) filter (
-        where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and not e.fue_referido)::int as cierres_no_referidos,
+        where e.tipo = 'cierre' and not e.anulado and private.conversion_origen_con_cierre(e.origen) and not e.fue_referido)::int as cierres_no_referidos,
       count(distinct e.lead_id) filter (
-        where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.fue_referido)::int as cierres_referidos,
+        where e.tipo = 'cierre' and not e.anulado and private.conversion_origen_con_cierre(e.origen) and e.fue_referido)::int as cierres_referidos,
       count(*) filter (where e.tipo = 'operacion')::int as operaciones,
       coalesce(sum(e.aporte_numerador), 0)::numeric as numerador
     from ep e

```
### crm.conversion_mensual_sin_cartera_fn — diff texto vivo (prod) → migración
```diff
--- vivo
+++ b11
@@ -366,7 +366,7 @@
     select count(*)::int as cierres_sin_episodio
     from crm.leads l
     where l.etapa = 'convertido'
-      and l.origen in ('landing', 'formulario', 'referido')
+      and private.conversion_origen_con_cierre(l.origen)
       and l.convertido_en >= v_ini
       and l.convertido_en < v_fin
       and (v_global

```
### private.conversion_divisor_empresa — diff texto vivo (prod) → migración
```diff
--- vivo
+++ b11
@@ -1,5 +1,5 @@
 CREATE OR REPLACE FUNCTION private.conversion_divisor_empresa(p_desde date, p_hasta date)
- RETURNS TABLE(analista_id uuid, nombre text, supervisor_id uuid, supervisor_nombre text, en_nucleo boolean, divisor integer, divisor_formulario integer, divisor_landing integer, numerador numeric, conversion_pct numeric, numerador_bruto numeric, ajuste_pendiente numeric, cierres_formulario integer, cierres_landing integer, cierres_referido integer, cierres_referido_aporte numeric, cierres_oficina integer, cierres_otros integer, upgrade integer, renovacion integer, renovacion_aporte numeric, desglose_disponible boolean)
+ RETURNS TABLE(analista_id uuid, nombre text, supervisor_id uuid, supervisor_nombre text, en_nucleo boolean, divisor integer, divisor_formulario integer, divisor_landing integer, numerador numeric, conversion_pct numeric, numerador_bruto numeric, ajuste_pendiente numeric, cierres_formulario integer, cierres_landing integer, cierres_referido integer, cierres_referido_aporte numeric, cierres_oficina integer, cierres_otros integer, upgrade integer, renovacion integer, renovacion_aporte numeric, desglose_disponible boolean, cierres_base_cargada integer)
  LANGUAGE plpgsql
  STABLE SECURITY DEFINER
  SET search_path TO ''
@@ -81,7 +81,9 @@
            case when f.con_desglose then coalesce((f.cartera ->> 'conversiones_upgrade')::integer, 0) end,
            case when f.con_desglose then coalesce((f.cartera ->> 'conversiones_renovacion')::integer, 0) end,
            case when f.con_desglose then coalesce((f.cartera ->> 'conversiones_renovacion')::integer, 0) * v_peso_renovacion end,
-           f.con_desglose
+           f.con_desglose,
+           -- B11: la foto del cierre no guarda los cierres de base cargada: NULL (no se inventa un 0).
+           null::integer
     from foto f
     left join por_origen o on o.vendedor_id = f.vendedor_id
     order by f.nombre_completo;
@@ -117,7 +119,7 @@
   ),
   cierres as materialized (
     -- De dónde salen los cierres: los MISMOS episodios que suman el numerador,
-    -- agrupados. Formulario y landing aportan 1 por cierre; referido, su peso;
+    -- agrupados. Formulario, landing y base cargada (B11) aportan 1 por cierre; referido, su peso;
     -- oficina no pesa; upgrade aporta 1 y renovación su propio peso.
     select e.analista_id,
            (count(*) filter (where e.tipo = 'cierre' and e.origen = 'formulario'))::integer as cierres_formulario,
@@ -126,7 +128,9 @@
            coalesce(sum(e.aporte_numerador) filter (where e.tipo = 'cierre' and e.origen = 'referido'), 0::numeric) as cierres_referido_aporte,
            (count(*) filter (where e.tipo = 'cierre' and e.origen = 'oficina'))::integer as cierres_oficina,
            -- Otros orígenes admitidos (otro, web, campaña, whatsapp…) tampoco pesan; se cuentan para no esconderlos.
-           (count(*) filter (where e.tipo = 'cierre' and coalesce(e.origen, '') not in ('formulario', 'landing', 'referido', 'oficina')))::integer as cierres_otros,
+           (count(*) filter (where e.tipo = 'cierre' and coalesce(e.origen, '') not in ('formulario', 'landing', 'referido', 'oficina', 'base_cargada')))::integer as cierres_otros,
+           -- B11: contactos de una base cargada por archivo. Pesan 1 y no están en el divisor.
+           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'base_cargada'))::integer as cierres_base_cargada,
            (count(*) filter (where e.tipo = 'operacion' and e.categoria = 'upgrade'))::integer as upgrade,
            (count(*) filter (where e.tipo = 'operacion' and e.categoria = 'renovacion'))::integer as renovacion,
            coalesce(sum(e.aporte_numerador) filter (where e.tipo = 'operacion' and e.categoria = 'renovacion'), 0::numeric) as renovacion_aporte
@@ -162,7 +166,8 @@
          coalesce(c.upgrade, 0),
          coalesce(c.renovacion, 0),
          coalesce(c.renovacion_aporte, 0::numeric),
-         true
+         true,
+         coalesce(c.cierres_base_cargada, 0)
   from base b
   left join por_origen o on o.analista_id is not distinct from b.analista_id
   left join cierres c on c.analista_id is not distinct from b.analista_id

```
### private.conversion_divisor_empresa_totales — diff texto vivo (prod) → migración
```diff
--- vivo
+++ b11
@@ -1,5 +1,5 @@
 CREATE OR REPLACE FUNCTION private.conversion_divisor_empresa_totales(p_desde date, p_hasta date)
- RETURNS TABLE(sellado boolean, peso_referido numeric, peso_renovacion numeric, divisor integer, numerador numeric, conversion_pct numeric, divisor_formulario integer, divisor_landing integer, numerador_bruto numeric, ajuste_pendiente numeric, cierres_formulario integer, cierres_landing integer, cierres_referido integer, cierres_referido_aporte numeric, cierres_oficina integer, cierres_otros integer, upgrade integer, renovacion integer, renovacion_aporte numeric, desglose_disponible boolean, cruza_sellados boolean, sin_analista_presente boolean, sin_analista_divisor integer, sin_analista_numerador numeric)
+ RETURNS TABLE(sellado boolean, peso_referido numeric, peso_renovacion numeric, divisor integer, numerador numeric, conversion_pct numeric, divisor_formulario integer, divisor_landing integer, numerador_bruto numeric, ajuste_pendiente numeric, cierres_formulario integer, cierres_landing integer, cierres_referido integer, cierres_referido_aporte numeric, cierres_oficina integer, cierres_otros integer, upgrade integer, renovacion integer, renovacion_aporte numeric, desglose_disponible boolean, cruza_sellados boolean, sin_analista_presente boolean, sin_analista_divisor integer, sin_analista_numerador numeric, cierres_base_cargada integer)
  LANGUAGE plpgsql
  STABLE SECURITY DEFINER
  SET search_path TO ''
@@ -62,6 +62,8 @@
       coalesce(sum(f.cierres_referido_aporte), 0::numeric) as cierres_referido_aporte,
       coalesce(sum(f.cierres_oficina), 0)::integer as cierres_oficina,
       coalesce(sum(f.cierres_otros), 0)::integer as cierres_otros,
+      -- B11: un mes sellado no la tiene en la foto (NULL); abierto o rango, la suma de las filas.
+      case when v_cierre.periodo is null then coalesce(sum(f.cierres_base_cargada), 0)::integer end as cierres_base_cargada,
       coalesce(sum(f.upgrade), 0)::integer as upgrade,
       coalesce(sum(f.renovacion), 0)::integer as renovacion,
       coalesce(sum(f.renovacion_aporte), 0::numeric) as renovacion_aporte
@@ -110,7 +112,8 @@
     ),
     coalesce((select sa.presente from sin_analista sa limit 1), false),
     (select sa.divisor from sin_analista sa limit 1),
-    (select sa.numerador from sin_analista sa limit 1)
+    (select sa.numerador from sin_analista sa limit 1),
+    case when s.desglose_disponible then s.cierres_base_cargada end
   from suma s;
 end;
 $function$;
```
### crm.conversion_divisor_coordinacion_fn — diff texto vivo (prod) → migración
```diff
--- vivo
+++ b11
@@ -104,7 +104,8 @@
         'referido', v_totales.cierres_referido,
         'referido_aporte', v_totales.cierres_referido_aporte,
         'oficina', v_totales.cierres_oficina,
-        'otros', v_totales.cierres_otros
+        'otros', v_totales.cierres_otros,
+        'base_cargada', v_totales.cierres_base_cargada
       ) end,
       'cartera', case when v_totales.desglose_disponible then pg_catalog.jsonb_build_object(
         'upgrade', v_totales.upgrade,
@@ -138,7 +139,8 @@
             'referido', f.cierres_referido,
             'referido_aporte', f.cierres_referido_aporte,
             'oficina', f.cierres_oficina,
-            'otros', f.cierres_otros
+            'otros', f.cierres_otros,
+            'base_cargada', f.cierres_base_cargada
           ) end,
           'cartera', case when f.desglose_disponible then pg_catalog.jsonb_build_object(
             'upgrade', f.upgrade,

```


## Censo y postflight (texto exacto)
```sql
-- ── 4 · Censo analítico: la declaración se queda en su fila (clase, tipo, razón y fecha) con la huella del cuerpo nuevo ──
update private.analitica_leads_citas_exenciones e set
  huella = md5(regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))
from pg_proc p
where p.oid = to_regprocedure(e.objeto)
  and to_regprocedure(e.objeto) in (to_regprocedure('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'), to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)'), to_regprocedure('private.metricas_conversiones_implementacion(date,date,text)'), to_regprocedure('crm.conversion_mensual_sin_cartera_fn(date)'));
update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc(), sellado_en = now() where id;

-- ── 5 · Postflight ─────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  r record;
  v_cols text;
begin
  for r in select * from (values
    ('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])', '155ce2b12754718388c8ca1644c84c90', '{postgres=X/postgres}'),
    ('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)', 'fec614f0df11c6d411bf132c776cce6e', '{postgres=X/postgres}'),
    ('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)', '2f0f891b41b25c902d6cfd4ab369af5d', '{postgres=X/postgres}'),
    ('crm.metricas_conversiones_equipo_fn(date,date)', '09e538d7be92bf8755411bec0737b34d', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.metricas_conversiones_implementacion(date,date,text)', '309c951204d9cd81a38ed049d1319d06', '{postgres=X/postgres}'),
    ('private.metricas_distribucion_leads_v3_core(date,date,timestamptz)', '41df911eccb0e66021760335145bb0e1', '{postgres=X/postgres}'),
    ('crm.conversion_mensual_sin_cartera_fn(date)', '417defaf8d982bfc628b3469984fa802', '{postgres=X/postgres}'),
    ('private.conversion_divisor_empresa(date,date)', 'bf90ba99a8404c0889606354ef289335', '{postgres=X/postgres}'),
    ('private.conversion_divisor_empresa_totales(date,date)', 'cf38266452df03960ca07d856d59b346', '{postgres=X/postgres}'),
    ('crm.conversion_divisor_coordinacion_fn(date,date,date)', 'b7dd99499a7668938a1417b259bc0626', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.conversion_origen_con_cierre(text)', '3c7ded558914426ea4f6a08830db1b43', '{postgres=X/postgres}')
  ) as v(firma, huella, acl) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(r.firma) and md5(p.prosrc) = r.huella
                    and p.proowner = 'postgres'::regrole and p.proacl::text = r.acl
                    and p.prosecdef = (r.firma not in ('private.conversion_origen_con_cierre(text)', 'private.metricas_distribucion_leads_v3_core(date,date,timestamptz)'))) then
      raise exception 'B11 postflight: % no quedó como se ensayó', r.firma;
    end if;
  end loop;
  -- Ninguna copia de la lista de cierres queda en las piezas tocadas.
  if exists (select 1 from pg_proc p where p.oid in (to_regprocedure('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])'), to_regprocedure('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'), to_regprocedure('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)'), to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)'), to_regprocedure('private.metricas_conversiones_implementacion(date,date,text)'), to_regprocedure('private.metricas_distribucion_leads_v3_core(date,date,timestamptz)'), to_regprocedure('crm.conversion_mensual_sin_cartera_fn(date)'), to_regprocedure('private.conversion_divisor_empresa(date,date)'), to_regprocedure('private.conversion_divisor_empresa_totales(date,date)'), to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)'))
              and (p.prosrc like '%origen in (''landing'', ''formulario'', ''referido'')%'
                   or p.prosrc like '%origen in (''landing'', ''formulario'') then 1%'
                   or p.prosrc like '%origen in (''landing'',''formulario'') then 1%')) then
    raise exception 'B11 postflight: quedó una copia de la lista de orígenes con cierre';
  end if;
  -- El ayudante: los cuatro orígenes que cuentan, ninguno más.
  if not (private.conversion_origen_con_cierre('landing') and private.conversion_origen_con_cierre('formulario')
          and private.conversion_origen_con_cierre('referido') and private.conversion_origen_con_cierre('base_cargada')
          and not private.conversion_origen_con_cierre('oficina') and not private.conversion_origen_con_cierre('otro')
          and not private.conversion_origen_con_cierre('web') and not private.conversion_origen_con_cierre('campania')
          and not private.conversion_origen_con_cierre('whatsapp')
          and private.conversion_origen_con_cierre(null) is null) then
    raise exception 'B11 postflight: el ayudante no dice lo ensayado';
  end if;
  -- La forma nueva del divisor de empresa y de su total: la columna al final, entera.
  select string_agg(a0.attname || ':' || format_type(a0.atttypid, null), ',' order by a0.n) into v_cols
    from pg_proc p, unnest(p.proargnames, p.proargmodes, p.proallargtypes) with ordinality as a0(attname, modo, atttypid, n)
   where p.oid = to_regprocedure('private.conversion_divisor_empresa(date,date)') and a0.modo = 't';
  if v_cols not like '%,desglose_disponible:boolean,cierres_base_cargada:integer' then
    raise exception 'B11 postflight: conversion_divisor_empresa sin la columna de base al final (%)', v_cols;
  end if;
  select string_agg(a0.attname || ':' || format_type(a0.atttypid, null), ',' order by a0.n) into v_cols
    from pg_proc p, unnest(p.proargnames, p.proargmodes, p.proallargtypes) with ordinality as a0(attname, modo, atttypid, n)
   where p.oid = to_regprocedure('private.conversion_divisor_empresa_totales(date,date)') and a0.modo = 't';
  if v_cols not like '%,sin_analista_numerador:numeric,cierres_base_cargada:integer' then
    raise exception 'B11 postflight: conversion_divisor_empresa_totales sin la columna de base al final (%)', v_cols;
  end if;
  -- Censo: las cuatro declaraciones vigentes, el sello al día y los rojos de antes, exactamente los mismos.
  if exists (select 1 from private.contadores_crudos_leads_citas() c
              where to_regprocedure(c.objeto) in (to_regprocedure('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'), to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)'), to_regprocedure('private.metricas_conversiones_implementacion(date,date,text)'), to_regprocedure('crm.conversion_mensual_sin_cartera_fn(date)'))
                and not (c.declarada and c.huella_ok)) then
    raise exception 'B11 postflight: una declaracion analitica tocada no quedo vigente';
  end if;
  if (select s.sello from private.analitica_lc_sello s where s.id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'B11 postflight: el sello del censo no quedo al dia';
  end if;
  if exists ((select tipo, objeto, declarada, huella_ok from pg_temp.b11_censo_antes
              except select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c)
             union all
             (select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c
              except select tipo, objeto, declarada, huella_ok from pg_temp.b11_censo_antes)) then
    raise exception 'B11 postflight: el censo analitico cambio (rojos nuevos o desaparecidos)';
  end if;
  -- Paridad en vivo del Divisor de coordinación: en el mes en curso, las partes suman el bruto en cada fila.
  if exists (select 1 from private.conversion_divisor_empresa(
                 pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date,
                 (pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima') + interval '1 month' - interval '1 day')::date) f
              where f.desglose_disponible and f.numerador_bruto is not null
                and abs(f.cierres_formulario + f.cierres_landing + f.cierres_base_cargada + f.cierres_referido_aporte
                        + f.upgrade + f.renovacion_aporte - f.numerador_bruto) > 0.000001) then
    raise exception 'B11 postflight: el desglose del divisor de coordinación no suma el numerador';
  end if;
end;
$postflight$;

commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
```

## Reversa (reversa-b11.sql): cabecera y sus dos bloques de comprobación (texto exacto)
Entre los dos bloques repone, con CREATE OR REPLACE, el texto vivo de producción de las ocho piezas que no cambian de
firma; hace drop + create de las dos privadas del divisor con su firma vieja, su revoke y su comentario; borra el
ayudante; y actualiza las cuatro huellas del censo y el sello con las mismas dos sentencias de la migración.
```sql
-- reversa-b11.sql — deshace 20261006042144_crm_bases_cargadas_conversion.sql y deja el estado vivo de ANTES, byte a byte:
-- los diez cuerpos (md5 de prosrc de producción, 05/10/2026), las firmas viejas de private.conversion_divisor_empresa y de
-- private.conversion_divisor_empresa_totales (sin cierres_base_cargada) con su ACL y su comentario, el comentario de la puerta
-- de coordinación, las cuatro huellas del censo analítico (resellado) y SIN el ayudante.
-- Se NIEGA si ya hay cierres de contactos de base: revertir les quitaría su peso (un número que la gente ya vio).
-- Se NIEGA también si otra función (fuera de las diez de B11) ya llama al ayudante: borrarlo la dejaría rota y pg_depend
-- no ve esa llamada; y si el censo analítico no está vigente y sellado antes de empezar (no se resella sobre un sello roto).
-- Antes de revertir en producción: publicar la pantalla anterior NO hace falta (la pantalla nueva tolera la clave ausente).
-- Conserva la fila de supabase_migrations.schema_migrations (regla de la casa): anotar la reversa en MIGRACIONES.md.
-- Uso: psql … -X -v ON_ERROR_STOP=1 -c "$(cat supabase/scripts/base-gestion/reversa-b11.sql)"   (un mensaje, como la migración)

do $preflight$
declare r record;
begin
  if not exists (select 1 from pg_locks l
                  where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted and l.mode = 'ExclusiveLock'
                    and l.objsubid = 1
                    and ((l.classid::bigint << 32) | l.objid::bigint) = hashtext('crm_migracion_funciones')::bigint) then
    raise exception 'reversa B11: falta el candado de migraciones' using errcode = 'P0409';
  end if;
  for r in select * from (values
    ('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])', '155ce2b12754718388c8ca1644c84c90', '{postgres=X/postgres}'),
    ('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)', 'fec614f0df11c6d411bf132c776cce6e', '{postgres=X/postgres}'),
    ('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)', '2f0f891b41b25c902d6cfd4ab369af5d', '{postgres=X/postgres}'),
    ('crm.metricas_conversiones_equipo_fn(date,date)', '09e538d7be92bf8755411bec0737b34d', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.metricas_conversiones_implementacion(date,date,text)', '309c951204d9cd81a38ed049d1319d06', '{postgres=X/postgres}'),
    ('private.metricas_distribucion_leads_v3_core(date,date,timestamptz)', '41df911eccb0e66021760335145bb0e1', '{postgres=X/postgres}'),
    ('crm.conversion_mensual_sin_cartera_fn(date)', '417defaf8d982bfc628b3469984fa802', '{postgres=X/postgres}'),
    ('private.conversion_divisor_empresa(date,date)', 'bf90ba99a8404c0889606354ef289335', '{postgres=X/postgres}'),
    ('private.conversion_divisor_empresa_totales(date,date)', 'cf38266452df03960ca07d856d59b346', '{postgres=X/postgres}'),
    ('crm.conversion_divisor_coordinacion_fn(date,date,date)', 'b7dd99499a7668938a1417b259bc0626', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.conversion_origen_con_cierre(text)', '3c7ded558914426ea4f6a08830db1b43', '{postgres=X/postgres}')
  ) as v(firma, huella, acl) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(r.firma) and md5(p.prosrc) = r.huella
                    and p.proowner = 'postgres'::regrole and p.proacl::text = r.acl) then
      raise exception 'reversa B11: % no es el de B11; revisar antes de revertir', r.firma using errcode = 'P0409';
    end if;
  end loop;
  -- Nadie fuera de las piezas de B11 llama al ayudante que se va a borrar (pg_depend no ve las llamadas en el texto).
  if exists (select 1 from pg_proc p
              where p.prosrc like '%conversion_origen_con_cierre%'
                and p.oid not in (to_regprocedure('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])'), to_regprocedure('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'), to_regprocedure('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)'), to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)'), to_regprocedure('private.metricas_conversiones_implementacion(date,date,text)'), to_regprocedure('private.metricas_distribucion_leads_v3_core(date,date,timestamptz)'), to_regprocedure('crm.conversion_mensual_sin_cartera_fn(date)'), to_regprocedure('private.conversion_divisor_empresa(date,date)'), to_regprocedure('private.conversion_divisor_empresa_totales(date,date)'), to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)'),
                                  to_regprocedure('private.conversion_origen_con_cierre(text)'))) then
    raise exception 'reversa B11: otra función ya usa private.conversion_origen_con_cierre; no se puede borrar' using errcode = 'P0409';
  end if;
  -- Las dos privadas del divisor (drop + create) siguen con sus dos únicos llamadores.
  if exists (select 1 from pg_proc p
              where p.prosrc ~ 'conversion_divisor_empresa(_totales)?\s*\('
                and p.oid not in (to_regprocedure('private.conversion_divisor_empresa_totales(date,date)'),
                                  to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)'))) then
    raise exception 'reversa B11: hay un llamador nuevo del divisor de empresa; revisar antes de revertir' using errcode = 'P0409';
  end if;
  -- El censo analítico se resella al final: antes debe estar vigente (las cuatro declaraciones) y con el sello al día.
  if (select count(*) from private.analitica_leads_citas_exenciones e
        join pg_proc p on p.oid = to_regprocedure(e.objeto)
       where to_regprocedure(e.objeto) in (to_regprocedure('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'), to_regprocedure('crm.metricas_conversiones_equipo_fn(date,date)'), to_regprocedure('private.metricas_conversiones_implementacion(date,date,text)'), to_regprocedure('crm.conversion_mensual_sin_cartera_fn(date)'))
         and e.huella = md5(regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))) <> 4 then
    raise exception 'reversa B11: una declaracion analitica de las funciones tocadas no esta vigente' using errcode = 'P0409';
  end if;
  if (select s.sello from private.analitica_lc_sello s where s.id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'reversa B11: el sello del censo analitico no esta al dia' using errcode = 'P0409';
  end if;
  if exists (select 1 from crm.lead_asignaciones la join crm.leads l on l.id = la.lead_id
              where la.resultado = 'convertido' and l.origen = 'base_cargada')
     or exists (select 1 from crm.conversion_acreditaciones ca where ca.origen = 'base_cargada') then
    raise exception 'reversa B11: ya hay cierres de contactos de base; revertir les quitaría su peso' using errcode = 'P0409';
  end if;
end;
$preflight$;

-- … cuerpos vivos de producción, drop del ayudante y resello del censo …

do $postflight$
declare r record;
begin
  for r in select * from (values
    ('private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])', 'b1d6c336d198036db4ddad83a075ebdb', '{postgres=X/postgres}'),
    ('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)', '00b17e7774f821eb04f0802f18039569', '{postgres=X/postgres}'),
    ('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)', '6e62d66e1c9536a50657245d6e633f56', '{postgres=X/postgres}'),
    ('crm.metricas_conversiones_equipo_fn(date,date)', 'cbae26a3031e01580068c9336baf798b', '{postgres=X/postgres,authenticated=X/postgres}'),
    ('private.metricas_conversiones_implementacion(date,date,text)', '1a0e7f7fd01977e556a13fea14ddc5aa', '{postgres=X/postgres}'),
    ('private.metricas_distribucion_leads_v3_core(date,date,timestamptz)', 'd73e12275649b756b71de50fd176d697', '{postgres=X/postgres}'),
    ('crm.conversion_mensual_sin_cartera_fn(date)', 'f613d94208b035f241c4e13b351c55be', '{postgres=X/postgres}'),
    ('private.conversion_divisor_empresa(date,date)', '5700d2770d1796440aa0184b035d623a', '{postgres=X/postgres}'),
    ('private.conversion_divisor_empresa_totales(date,date)', 'e97995f5ffd9109fce87f2e5dafb11a6', '{postgres=X/postgres}'),
    ('crm.conversion_divisor_coordinacion_fn(date,date,date)', 'b881b83ca8d4dd2f0f081d736828c8c5', '{postgres=X/postgres,authenticated=X/postgres}')
  ) as v(firma, huella, acl) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(r.firma) and md5(p.prosrc) = r.huella
                    and p.proowner = 'postgres'::regrole and p.proacl::text = r.acl
                    and p.prosecdef = (r.firma <> 'private.metricas_distribucion_leads_v3_core(date,date,timestamptz)')) then
      raise exception 'reversa B11 postflight: % no volvió al texto vivo', r.firma;
    end if;
  end loop;
  if to_regprocedure('private.conversion_origen_con_cierre(text)') is not null then
    raise exception 'reversa B11 postflight: el ayudante sigue vivo';
  end if;
  if exists (select 1 from pg_proc p where p.prosrc like '%conversion_origen_con_cierre%') then
    raise exception 'reversa B11 postflight: queda una función que nombra al ayudante borrado';
  end if;
  if md5(coalesce(obj_description(to_regprocedure('private.conversion_divisor_empresa(date,date)'), 'pg_proc'), '')) <> md5('Núcleo (30/09/2026, v2 con desglose y rango): conversión por analista con ámbito de toda la empresa, para la puerta de Coordinación, entre dos fechas inclusivas (Lima). Un mes calendario exacto usa la pieza mensual neta (Metas) y, si está sellado, la foto (crm.cierre_mes_vendedor: origenes_ranking y cartera) sin recalcular; cualquier otro rango se calcula en vivo (bruto = neto). Agrupa los episodios de private.conversion_episodios: llegadas por origen (divisor), cierres por origen (formulario, landing, referido con su aporte, oficina sin peso) y cartera (upgrade, renovación con su aporte). numerador_bruto = partes. La fila con analista_id nulo es la producción sin analista atribuible. Sin autorización dentro y sin ejecutores de la API.') then
    raise exception 'reversa B11 postflight: comentario de % sin reponer', 'private.conversion_divisor_empresa(date,date)';
  end if;
  if md5(coalesce(obj_description(to_regprocedure('private.conversion_divisor_empresa_totales(date,date)'), 'pg_proc'), '')) <> md5('Núcleo (30/09/2026, v2 con desglose y rango): total de la empresa y producción sin analista para la puerta de Coordinación, entre dos fechas inclusivas (Lima). Mes abierto o rango: suma de private.conversion_divisor_empresa. Mes sellado: foto por persona + cobertura.fuera_ranking + conversion_sin_analista de crm.periodos_cerrados (solo objetos), la misma suma que la puerta mensual oficial; el desglose solo se sirve si todas las filas de la foto lo traen. Nunca recalcula un mes sellado. Sin autorización dentro y sin ejecutores de la API.') then
    raise exception 'reversa B11 postflight: comentario de % sin reponer', 'private.conversion_divisor_empresa_totales(date,date)';
  end if;
  if md5(coalesce(obj_description(to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)'), 'pg_proc'), '')) <> md5('Puerta (30/09/2026, v2 con desglose de cierres y rango de fechas): conversión por analista de TODA la empresa para Coordinación (OK de Miguel: divisor, desglose por origen, numerador neto y porcentaje; después pidió de dónde salen los cierres —formulario, landing, referido con su peso, oficina sin peso, upgrade y renovación con su peso— y consultar por rango de fechas). Sin argumentos: mes vigente. p_periodo: ese mes (sellado → foto). p_desde + p_hasta: rango inclusivo en Lima, hasta 366 días, sin futuro; un mes calendario exacto se trata como ese mes; otro rango se calcula en vivo (sin ajustes de meses pagados; si toca meses sellados lo declara en periodo.cruza_meses_sellados y fuente.modo = rango_vivo). Los cierres de orígenes que no pesan (oficina y otros) se cuentan aparte. Autoriza con private.puede_operar_reparto_crm() (coordinador o gerencia activas; el resto 42501) y delega en los núcleos: nada se recalcula aquí. Sin PII de leads.') then
    raise exception 'reversa B11 postflight: comentario de % sin reponer', 'crm.conversion_divisor_coordinacion_fn(date,date,date)';
  end if;
  if (select s.sello from private.analitica_lc_sello s where s.id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'reversa B11 postflight: el sello del censo no quedo al dia';
  end if;
  if exists ((select tipo, objeto, declarada, huella_ok from pg_temp.b11_censo_antes
              except select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c)
             union all
             (select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c
              except select tipo, objeto, declarada, huella_ok from pg_temp.b11_censo_antes)) then
    raise exception 'reversa B11 postflight: el censo analitico cambio';
  end if;
end;
$postflight$;

commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
```

## Pantalla (diff exacto, sin los tests)
```diff
diff --git a/CRM-Avance-Corp/app/src/components/app/conversion-coordinacion.tsx b/CRM-Avance-Corp/app/src/components/app/conversion-coordinacion.tsx
index eea756e9..1cf912c1 100644
--- a/CRM-Avance-Corp/app/src/components/app/conversion-coordinacion.tsx
+++ b/CRM-Avance-Corp/app/src/components/app/conversion-coordinacion.tsx
@@ -58,6 +58,7 @@ function SinDato({ motivo }: { motivo: string }) {
 const MOTIVO_SELLADO = 'sin desglose: mes cerrado'
 const MOTIVO_SIN_LLEGADAS = 'sin llegadas'
 const MOTIVO_NO_APLICA = 'no aplica'
+const MOTIVO_BASE_SELLADA = 'la foto del mes cerrado no guarda los cierres de base'
 
 /** «setiembre de 2026» a partir de 'YYYY-MM', sin depender de la zona del navegador. */
 function nombreDelMes(mes: string): string {
@@ -100,9 +101,9 @@ const REFERIDO = { uno: 'referido', varios: 'referidos' }
 const RENOVACION = { uno: 'renovación', varios: 'renovaciones' }
 
 /**
- * Las siete celdas de «Cierres» de una fila, en el MISMO orden que la cabecera:
- * formulario, landing, referido, sin peso (oficina y otros), upgrade, renovación
- * y el total ponderado. La fila «sin analista» pasa por aquí con todo a null para
+ * Las ocho celdas de «Cierres» de una fila, en el MISMO orden que la cabecera:
+ * formulario, landing, base cargada, referido, sin peso (oficina y otros), upgrade,
+ * renovación y el total ponderado. La fila «sin analista» pasa por aquí con todo a null para
  * que sus celdas nunca se desalineen de la cabecera.
  */
 function CeldasCierres({
@@ -125,6 +126,9 @@ function CeldasCierres({
     <>
       <Td className="text-right tabular-nums">{cierres ? numero(cierres.formulario) : <SinDato motivo={motivo} />}</Td>
       <Td className="text-right tabular-nums">{cierres ? numero(cierres.landing) : <SinDato motivo={motivo} />}</Td>
+      <Td className="text-right tabular-nums">
+        {cierres ? <Cifra valor={cierres.base_cargada === undefined ? 0 : cierres.base_cargada} motivo={MOTIVO_BASE_SELLADA} /> : <SinDato motivo={motivo} />}
+      </Td>
       <Td className="text-right tabular-nums">
         {cierres ? <CantidadYAporte cantidad={cierres.referido} aporte={cierres.referido_aporte} nombre={REFERIDO} /> : <SinDato motivo={motivo} />}
       </Td>
@@ -189,6 +193,7 @@ function formulaDelNumerador(datos: DatosConversion): string | null {
   const renovacion = `${numero(cartera.renovacion_aporte)} de renovación (${numero(cartera.renovacion)}${enRango ? '' : ` × ${numero(datos.peso_renovacion)}`})`
   const partes = [
     `${numero(cierres.formulario + cierres.landing)} directos (formulario y landing)`,
+    cierres.base_cargada === null ? 'base cargada: la foto no la guarda' : `${numero(cierres.base_cargada ?? 0)} de base cargada`,
     referidos,
     `${numero(cartera.upgrade)} de upgrade`,
     renovacion,
@@ -339,6 +344,7 @@ export function ConversionCoordinacion() {
     { etiqueta: 'Landing', valor: datos.sellado ? <SinDato motivo={MOTIVO_SELLADO} /> : <Cifra valor={datos.empresa.divisor_landing} motivo={MOTIVO_SIN_LLEGADAS} /> },
     { etiqueta: 'Conversión', valor: <Porcentaje valor={datos.empresa.conversion_pct} /> },
     { etiqueta: 'Cierres directos', valor: datos.empresa.cierres ? numero(datos.empresa.cierres.formulario + datos.empresa.cierres.landing) : <SinDato motivo={MOTIVO_SELLADO} /> },
+    { etiqueta: 'Base cargada', valor: datos.empresa.cierres ? <Cifra valor={datos.empresa.cierres.base_cargada === undefined ? 0 : datos.empresa.cierres.base_cargada} motivo={MOTIVO_BASE_SELLADA} /> : <SinDato motivo={MOTIVO_SELLADO} /> },
     { etiqueta: 'Referidos', valor: datos.empresa.cierres ? <CantidadYAporte cantidad={datos.empresa.cierres.referido} aporte={datos.empresa.cierres.referido_aporte} nombre={REFERIDO} /> : <SinDato motivo={MOTIVO_SELLADO} /> },
     { etiqueta: 'Upgrade', valor: datos.empresa.cartera ? numero(datos.empresa.cartera.upgrade) : <SinDato motivo={MOTIVO_SELLADO} /> },
     { etiqueta: 'Renovación', valor: datos.empresa.cartera ? <CantidadYAporte cantidad={datos.empresa.cartera.renovacion} aporte={datos.empresa.cartera.renovacion_aporte} nombre={RENOVACION} /> : <SinDato motivo={MOTIVO_SELLADO} /> },
@@ -465,12 +471,12 @@ export function ConversionCoordinacion() {
           <div
             role="group"
             aria-label={`Resumen de conversión ${periodoVisible}`}
-            className="grid grid-cols-2 border-b border-border/70 bg-primary/[0.025] sm:grid-cols-4"
+            className="grid grid-cols-2 border-b border-border/70 bg-primary/[0.025] sm:grid-cols-3"
           >
             {chips.map(({ etiqueta, valor }, indice) => (
               <div
                 key={etiqueta}
-                className={`px-5 py-3 ${indice % 2 === 1 ? 'border-l border-border/70' : ''} ${indice % 4 !== 0 ? 'sm:border-l sm:border-border/70' : ''} ${indice >= 2 ? 'border-t border-border/70' : ''} ${indice >= 2 && indice < 4 ? 'sm:border-t-0' : ''}`}
+                className={`px-5 py-3 ${indice % 2 === 1 ? 'border-l border-border/70' : ''} ${indice % 3 !== 0 ? 'sm:border-l sm:border-border/70' : 'sm:border-l-0'} ${indice >= 2 ? 'border-t border-border/70' : ''} ${indice === 2 ? 'sm:border-t-0' : ''}`}
               >
                 <p className="text-[11px] font-semibold text-muted-foreground">{etiqueta}</p>
                 <p className="mt-0.5 text-xl font-extrabold tabular-nums text-primary">{valor}</p>
@@ -513,6 +519,7 @@ export function ConversionCoordinacion() {
                       <Th scope="col" className="text-right">Total</Th>
                       <Th scope="col" className="text-right">Form.</Th>
                       <Th scope="col" className="text-right">Land.</Th>
+                      <Th scope="col" className="text-right">Base <span className="sr-only">cargada</span></Th>
                       <Th scope="col" className="text-right">Referido</Th>
                       <Th scope="col" className="text-right">Sin peso</Th>
                       <Th scope="col" className="text-right">Upgrade</Th>
@@ -524,7 +531,7 @@ export function ConversionCoordinacion() {
                   <Th scope="col" rowSpan={2} className="align-bottom">Analista</Th>
                   <Th scope="col" rowSpan={2} className="hidden align-bottom lg:table-cell">Supervisor</Th>
                   <Th scope="colgroup" colSpan={3} className="text-center">Llegadas</Th>
-                  <Th scope="colgroup" colSpan={7} className="text-center">Cierres</Th>
+                  <Th scope="colgroup" colSpan={8} className="text-center">Cierres</Th>
                   <Th scope="col" rowSpan={2} className="text-right align-bottom">Conversión</Th>
                 </TheadCrm>
                 <tbody>
@@ -557,7 +564,8 @@ export function ConversionCoordinacion() {
           )}
 
           <p className="border-t border-border px-5 py-2 text-sm text-muted-foreground">
-            Referido y Renov. (renovación) van como «cantidad · aporte al numerador». «Sin peso» son los
+            Referido y Renov. (renovación) van como «cantidad · aporte al numerador». «Base» son los
+            cierres de contactos de una base cargada: suman 1 cada uno y no entran a las llegadas. «Sin peso» son los
             cierres de oficina y de otros orígenes, que no suman. Este conteo es distinto del reporte de
             entregas: aquel cuenta lo entregado por fecha de entrega y deja de sumar la entrega que volvió
             a la bandeja antes de gestionarse.
diff --git a/CRM-Avance-Corp/app/src/lib/conversion-coordinacion.ts b/CRM-Avance-Corp/app/src/lib/conversion-coordinacion.ts
index cc7d3b54..223af806 100644
--- a/CRM-Avance-Corp/app/src/lib/conversion-coordinacion.ts
+++ b/CRM-Avance-Corp/app/src/lib/conversion-coordinacion.ts
@@ -27,6 +27,12 @@ const CierresSchema = v.object({
   oficina: EnteroNoNegativoRpcSchema,
   /** Otros orígenes admitidos (web, campaña, whatsapp…): tampoco pesan; se cuentan para no esconderlos. */
   otros: EnteroNoNegativoRpcSchema,
+  /**
+   * Contactos de una base cargada por archivo (B11): cada cierre pesa 1 y no entra al divisor. Un servidor
+   * anterior a B11 no la manda (y entonces esos cierres pesan 0 y van en «otros»): ausente = 0. Null solo en un
+   * mes sellado, porque la foto del cierre no la guarda.
+   */
+  base_cargada: v.optional(v.nullable(EnteroNoNegativoRpcSchema)),
 })
 
 const CarteraSchema = v.object({
@@ -200,9 +206,10 @@ export function fechasDeConsulta(consulta: ConsultaConversion): { desde: string;
 /** Tolerancia para sumas de pesos con decimales (0,15 × n) en coma flotante. */
 const EPSILON = 1e-6
 
-/** Cuánto suman las partes del numerador: cierres directos, referidos con peso, upgrade y renovación con peso. */
+/** Cuánto suman las partes del numerador: cierres directos y de base, referidos con peso, upgrade y renovación con peso. */
 export function sumaDePartes(cierres: CierresConversion, cartera: CarteraConversion): number {
-  return cierres.formulario + cierres.landing + cierres.referido_aporte + cartera.upgrade + cartera.renovacion_aporte
+  return cierres.formulario + cierres.landing + (cierres.base_cargada ?? 0) + cierres.referido_aporte
+    + cartera.upgrade + cartera.renovacion_aporte
 }
 
 function desgloseConsistente(fila: {
@@ -221,6 +228,8 @@ function desgloseConsistente(fila: {
   }
   if (fila.cierres === null || fila.cartera === null) return false
   if (fila.sellado) return fila.numerador_bruto === null && fila.ajuste_pendiente === null
+  // Mes abierto o rango: el servidor siempre sabe cuántos cierres de base hubo.
+  if (fila.cierres.base_cargada === null) return false
   if (fila.numerador_bruto === null || fila.ajuste_pendiente === null || fila.numerador === null) return false
   if (Math.abs(sumaDePartes(fila.cierres, fila.cartera) - fila.numerador_bruto) > EPSILON) return false
   // Por persona: neto = bruto menos lo que arrastra de meses ya pagados, con suelo en cero.
```

## Resultados medidos (06/10/2026; banco Docker con las 933 funciones crm+private de producción: las 922 del 05/10 más la
## migración 20261005200945 «eliminar inversión», ya en producción; huella agregada antes de B11 `933 | 2c2f2612…`)
- Migración aplicada en UN mensaje, como `postgres`: preflight y postflight en verde (0,4 s). Huella después `934 | 2f359f3e…`.
- Paridad A/B (b11-paridad.sql, como Gerencia, ago/sep/oct + rango): 41 salidas (coordinación, conversión mensual sin
  cartera, Equipo, Inteligencia comercial, Distribución v3, conversión mensual por vendedor, divisor de empresa proyectado,
  cierres, crm.conversion_mensual_fn, alarma) con huella IDÉNTICA antes y después; la única diferencia es la clave nueva
  base_cargada = 0. Censo analítico (38 filas) idéntico antes y después.
- Las 11 huellas (md5 de prosrc) tras aplicar = las del postflight.
- Suite de comportamiento (clona un cierre real de octubre como contacto de base y como «otro»): 23/23. Base: numerador
  +1, divisor +0, cierres +1 en mensual/Equipo/Distribución/Inteligencia comercial, coordinación con base +1 y partes =
  bruto en cada fila, sondas de paridad de Equipo y Distribución en verde, la sonda «cierre sin episodio» ve un contacto
  de base convertido sin episodio. «Otro»: +0 y cuenta en «otros». Mes sellado con foto: cierres_base_cargada NULL en filas
  y total; el ajuste de un cierre de base anulado pesa 1; el de «otro», ninguno.
- Mutantes: 16/16 caen (cada copia vieja de cada función, ayudante sin base, base contada como 0, «otros» con base, mes
  sellado con 0 inventado, coordinación sin la clave).
- **Ensayo de DOS SESIONES del freno (nuevo en r2, por tu P1):**
  A · control SIN el candado, con la ventana abierta 2 s tras el preflight: otra sesión confirma un cierre de base y la
      migración se confirma igual → tu carrera existe.
  B · mismo candado en modo espera: un escritor tiene un cierre de base sin confirmar; la migración espera, el escritor
      confirma, y el preflight VE ese cierre y se niega (la instantánea nace después del candado); no se aplica nada.
  C · migración final (NOWAIT) con un escritor a medias: `could not obtain lock on relation`, al instante; huella
      intacta y 0 candados consultivos retenidos.
  D · migración final con la ventana abierta 2 s: el escritor que llega en medio queda en espera 1,6 s, hasta el commit
      de la migración; su cierre nace ya con la regla nueva.
  E · reversa final: con un cierre de base confirmado se niega (freno); con un escritor a medias se niega al instante.
- Frenos en negativo (10/10): con un cierre de base presente, la migración y la reversa se niegan (P0409) y sueltan el
  candado; la reversa se niega si otra función nombra al ayudante, si hay un llamador nuevo del divisor de empresa, si el
  sello del censo no está al día o si una de las cuatro declaraciones caducó; la migración se niega con un llamador nuevo
  del divisor de empresa; ningún rechazo deja nada (huella igual) ni retiene candados.
- Reversa (como `postgres`): deja el banco con las 933 funciones y el censo IDÉNTICOS a antes de B11. Corrida como otro rol
  (supabase_admin) su postflight la rechaza y hace rollback (el dueño de las dos privadas recreadas no sería postgres).
- Gate de RLS completo (test-rls.mjs, siembra + 2817 aserciones) ANTES y DESPUÉS de B11: los mismos 8 rojos de fondo
  (ajenos y previos: R2/hito de activación, una fila bancaria y la bandera potencial_lead), ninguno nuevo; el bloque nuevo de B11 8/8 (núcleo sin EXECUTE para anon/authenticated/service_role,
  ayudante INVOKER e IMMUTABLE, ACL de la puerta intacta, empresa.cierres.base_cargada y la de cada analista enteras en un
  mes abierto, partes = numerador bruto con la base).
- Tiempo de private.metricas_conversiones_implementacion con 366 días (5 corridas, ms): sin B11 {90.2,86.6,87.6,96.9,89.9},
  con B11 {98.7,89.6,88.9,87.7,91.9}; misma salida (md5 igual).
- Registrador: se niega sin la migración; con ella registra 1 sentencia cuyo md5 = el del archivo; idempotente.
- Front: npm run check (oxlint + typecheck + 6201 tests) PASS.

## Qué cambió desde tu r1 (BLOCK) — respuesta del PRIMARY, punto por punto
- **[P1] El freno no excluía escritores → ACEPTADO.** Migración y reversa toman ahora, ANTES de su primera lectura,
  `lock table crm.lead_asignaciones, crm.conversion_acreditaciones in share row exclusive mode nowait` (transcrito arriba,
  en «Preflight» y en «Reversa»). Va suelto y no dentro de un DO porque un DO toma la instantánea antes de ejecutar su
  cuerpo. NOWAIT y no espera: la migración nunca espera con un candado tomado, así que no puede interbloquearse con un
  escritor que toque las dos tablas en otro orden ni dejar colgado a un usuario; si hay contienda, se niega y se repite.
  Esas dos tablas son las únicas que mira el freno; el origen de un lead no cambia tras el alta (trigger, P0409). Ensayo de
  dos sesiones en «Resultados medidos».
- **[P2] Pestaña con el bundle anterior + servidor nuevo + primer cierre de base → ACEPTADO como riesgo operativo, no se
  arregla en el servidor.** Un bundle ya cargado no se puede cambiar desde la base. Mitigación: (a) la pantalla nueva se
  publica antes; (b) el CRM consulta `version.json` cada 60 s y avisa «hay versión nueva»
  (`app/src/lib/version-publicada.ts`, componente `VersionPublicadaAviso` montado en `main.tsx`); (c) la migración se
  aplica después de dar tiempo a recargar (propuesta a Miguel: al día siguiente). Residual: quien ignore el aviso y abra el
  Divisor de coordinación tras el primer cierre de base verá esa tarjeta en error hasta recargar; no se altera ningún dato.
  Hoy hay 0 contactos de base en producción (medido el 05/10).
- **Riesgo «sellar un mes con cierres de base»: DECLARADO, fuera de B11.** `crm.cerrar_periodo` no se ensayó con un cierre
  de base: no hay meses sellados y el ciclo de cierre está en pausa por decisión de Miguel. El numerador sellado sale de
  private.conversion_cierres (que con B11 ya da 1 al cierre de base); la foto no guarda la base aparte y el Divisor de
  coordinación de ese mes mostrará «—» en Base (NULL, sin inventar un 0). Guardar la base en la foto es otro paso.
- **Heurística de llamadores por texto:** se queda como defensa adicional; no es la única (un llamador roto fallaría en su
  primera ejecución y el gate lo vería). La forma `private."conversion_divisor_empresa"(…)` no existe en el repo.
- También desde r1: auditor-rls r2 PASS; la reversa dice que conserva la fila del historial; fila del ledger escrita.

## Revisión interna previa (auditor-rls, 06/10): r1 CHANGES_REQUESTED sin P0/P1 → r2 PASS
- La reversa se niega si otra función nombra al ayudante, si hay un llamador nuevo del divisor de empresa, o si el censo
  analítico no está vigente y sellado; comprueba el candado de migraciones y prosecdef.
- Gate de RLS: bloque propio de B11 (catálogo + contrato) y la paridad del desglose suma `cierres.base_cargada ?? 0`.

## Lo que quiero que intentes refutar en esta ronda (además de lo que encuentres)
0. ¿El candado nuevo cierra de verdad tu P1? ¿Introduce un problema (bloqueo de usuarios, interbloqueo, una tabla que
   falte, un camino por el que el cierre de un contacto de base nazca sin escribir en esas dos tablas)?

1. ¿Algún consumidor (servidor o pantalla) suma partes del numerador o cuenta cierres por origen con otra copia de la lista
   que NO esté en el diff, y quedaría descuadrado con un cierre de base? (p. ej. alarma, metas, ranking, fotos del cierre
   de mes, crm.cerrar_periodo / cierre_mes_vendedor). Si lo afirmas sin texto transcrito que lo pruebe, márcalo HIPÓTESIS.
2. Mes SELLADO: el divisor de coordinación devuelve base NULL (la foto no lo guarda). ¿Es correcto devolver NULL y que la
   pantalla no valide la suma en un mes sellado? ¿Qué pasa cuando se selle por primera vez un mes con cierres de base?
3. ¿El drop + create de las dos funciones privadas puede romper algo en caliente (llamadas concurrentes, planes en caché,
   dependencias), o deja ACL/seguridad distinta?
4. ¿El ayudante con `set search_path` (no inlineable) puede tener un costo relevante en las métricas grandes?
5. ¿La actualización de huellas del censo analítico es correcta o abre una vía para esquivar el trinquete?
6. ¿El orden «pantalla primero, servidor después» es seguro en los dos sentidos (pantalla nueva + servidor viejo;
   pantalla vieja + servidor nuevo)?

Formato: VERDICT (APPROVE / APPROVE_WITH_NITS / BLOCK), SUMMARY, FINDINGS P0–P3 (cada uno con la evidencia transcrita que lo
sostiene; si no la hay, HIPÓTESIS), RISKS / TEST GAPS, NEXT ACTIONS, CONFIDENCE.
