ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude. Do not
delegate to another coding agent. Do not create another review chain.

Eres el revisor secundario. Tu único trabajo es **intentar REFUTAR** lo que va
abajo. No lo confirmes por cortesía: búscale el fallo. Si no lo encuentras,
dilo, pero solo después de haberlo intentado en serio.

Trabajas sobre el repo en `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop`
(el CRM vive en `CRM-Avance-Corp/`). Tienes lectura del árbol. **No tienes acceso
a la base de producción.** Los cuerpos VIVOS de hoy (antes del cambio) están
EXACTOS en `CRM-Avance-Corp/supabase/scripts/conversion/reversa-una-sola-pieza.sql`
(copiados de `pg_get_functiondef` en producción el 23/09/2026). Los cuerpos
NUEVOS están en la migración. El diff entre ambos va al final.

---

## LA DECISIÓN

Miguel (dueño) decidió que **Metas deje de calcular la conversión** y use la de
la oficial, sin fusionar payloads. La migración propuesta es
`CRM-Avance-Corp/supabase/migrations/20260923164903_crm_una_sola_pieza_de_conversion.sql`.
**Léela entera antes de opinar.** Respeta capas tabla → núcleo → puerta → pantalla:

- Núcleo, NUEVO: `private.conversion_neta_por_vendedor(p_periodo, p_global, p_visibles)`
  (núcleo bruto + deuda + neto + %) y `private.roster_conversion_mensual(...)`
  (quién sale nombrado en la oficial).
- Puertas que dejan de calcular: `crm.conversion_mensual_sin_cartera_fn` (la
  oficial), `crm.cumplimiento_metas_sin_cartera_fn` (#8) y la lista
  `fuera_ranking` de `crm.cumplimiento_metas_fn` (#7, que además HEREDA el
  payload de la #8).
- Envoltorio que NO se toca pero hereda: `crm.conversion_mensual_fn` (envuelve a
  la oficial). El front valida Metas con `v.strictObject` (`app/src/lib/objetivos.ts`).

## LO QUE DEBES INTENTAR REFUTAR

**A1 — LA IMPORTANTE.** Hoy ningún número se mueve: para cualquier persona (rol
vendedor, supervisor, gerencia, coordinador, lector global `directorio`, y
vendedores inactivos), en el mes vigente y en un mes anterior aún abierto, las
cuatro puertas (`conversion_mensual_sin_cartera_fn`, `conversion_mensual_fn`,
`cumplimiento_metas_sin_cartera_fn`, `cumplimiento_metas_fn`) devuelven EL MISMO
jsonb que antes, salvo `fuente` de la #8/#7 en mes abierto (`rango_vivo` →
`mensual`). Ataca en especial: la fila del núcleo con `analista_id` NULO
(producción sin analista), miembros del roster sin fila en el núcleo (con y sin
deuda), el agregado `fuera` (BRUTO), `motivos_totales`, el orden de
`responsables`, la escala numérica de `numerador` en el jsonb, y el recorte por
ámbito (`p_global`/`p_visibles`) de cada llamador.

**A2.** `private.roster_conversion_mensual` equivale exactamente al CTE
`roster` y al chequeo `v_alcance = 'propio'` que tenía la oficial (mes vigente vs
histórico abierto, `v_meta_periodo_id` nulo, `now()`, duplicados).

**A3.** Los dos únicos efectos LATENTES (hoy sin efecto: 0 meses sellados, 0
deudas) son correctos y coherentes con la oficial: (a) Metas enseña la deuda de
quien no tuvo actividad; (b) `fuera_ranking` publica NETO a quien la oficial
nombra y BRUTO a quien suma sin nombre.

**A4 — seguridad.** Las piezas son SECURITY INVOKER, EXECUTE solo `postgres`, y
solo las llaman puertas SECURITY DEFINER (dueño postgres) que ya autorizaron.
No se abre ninguna vía nueva; los gates de coordinador/lector/vendedor/inactivo
no cambian. La pieza rechaza un mes sellado (22023) y nunca se usa en el cierre
de mes (el sello descuenta al saldar; aquí se descontaría dos veces).

**A5 — censo/trinquete.** Re-sellar la huella de la oficial con la
normalización del censo (`private.contadores_crudos_leads_citas`) y refrescar
`private.analitica_lc_sello` es correcto, y el preflight impide bendecir un
cambio ajeno (exige el trinquete en verde antes). La #7, la #8 y las piezas
siguen fuera del censo.

**A6.** La transacción en REPEATABLE READ con el `lock table` antes de la primera
consulta hace que el antes/después no pueda ver un commit ajeno; el postflight no
puede dar verde por vacuidad.

**A7.** El front vivo (commit `6bf0e84a`) no se rompe: claves idénticas, y
`fuente: v.optional(v.picklist(['mensual','rango_vivo']))`. Nadie en `app/src`
depende de que Metas diga `rango_vivo`.

**A8.** La reversa (`reversa-una-sola-pieza.sql`) devuelve todo exactamente.

## FORMATO DE RESPUESTA

VERDICT · SUMMARY · FINDINGS P0–P3 (cada uno con archivo:línea, el texto exacto o
el contraejemplo concreto; distingue hipótesis de hecho) · RIESGOS Y HUECOS DE
PRUEBA · NEXT ACTIONS · CONFIDENCE. **Sin hallazgo sin evidencia.**

---

## DIFF: cuerpo vivo → cuerpo nuevo de las tres puertas

```diff
--- vivo/crm.conversion_mensual_sin_cartera_fn.sql
+++ nuevo/oficial.sql
@@ -22,5 +22,4 @@
   v_motivo_no_medible text;
   v_motivo_roster text;
-  v_meta_periodo_id uuid;
   v_es_historico_abierto boolean := false;
   v_payload jsonb;
@@ -223,14 +222,9 @@
   end if;
 
-  -- 4) Mes ABIERTO. Si es historico durante la ventana de ajuste, manda la
-  -- ultima publicacion de ESE mes; el vigente conserva el roster operativo.
+  -- 4) Mes ABIERTO. Quien sale NOMBRADO lo decide una sola regla del nucleo,
+  -- `private.roster_conversion_mensual`: el mes vigente conserva el roster
+  -- operativo; uno anterior aun abierto (ventana de ajuste), la ultima
+  -- publicacion de ESE mes.
   v_es_historico_abierto := p_periodo < v_mes_actual;
-  if v_es_historico_abierto then
-    select mp.id into v_meta_periodo_id
-    from crm.meta_periodos mp
-    where mp.periodo = p_periodo
-    order by mp.revision desc
-    limit 1;
-  end if;
 
   v_visibles := case when v_global then '{}'::uuid[]
@@ -264,14 +258,7 @@
 
   if v_alcance = 'propio'
-     and not (
-       (v_es_historico_abierto and exists (
-         select 1 from crm.metas_vendedor mv
-         where mv.meta_periodo_id = v_meta_periodo_id
-           and mv.vendedor_id = v_uid
-       ))
-       or (not v_es_historico_abierto and exists (
-         select 1 from private.roster_metas_vendedores() r
-         where r.vendedor_id = v_uid
-       ))
+     and not exists (
+       select 1 from private.roster_conversion_mensual(p_periodo, false, array[v_uid]) r
+        where r.vendedor_id = v_uid
      ) then
     select vs.motivo
@@ -286,21 +273,11 @@
   with roster as materialized (
     select r.vendedor_id, r.supervisor_id
-    from private.roster_metas_vendedores() r
-    where not v_es_historico_abierto
-      and (v_global or r.vendedor_id = any(v_visibles))
-
-    union all
-
-    select mv.vendedor_id, mv.supervisor_id
-    from crm.metas_vendedor mv
-    where v_es_historico_abierto
-      and mv.meta_periodo_id = v_meta_periodo_id
-      and (v_global or mv.vendedor_id = any(v_visibles))
+    from private.roster_conversion_mensual(p_periodo, v_global, v_visibles) r
   ),
   base as materialized (
-    select cm.*
-    from private.conversion_mensual_por_vendedor(
-      v_ini, v_fin, v_global, v_visibles, v_factor
-    ) cm
+    -- LA CIFRA POR PERSONA sale de UNA sola pieza del nucleo, la misma que usa
+    -- Metas: bruto, deuda de meses ya pagados, neto y porcentaje sobre el neto.
+    select n.*
+    from private.conversion_neta_por_vendedor(p_periodo, v_global, v_visibles) n
   ),
   alta_referidos as materialized (
@@ -313,12 +290,4 @@
       and (v_global or l.creado_por = any(v_visibles))
     group by l.creado_por
-  ),
-  pendientes as materialized (
-    -- Lo que cada vendedor arrastra de meses YA CERRADOS: cierres anulados
-    -- despues de pagar. Se descuenta aqui, en la LECTURA, y no dentro de
-    -- `private.conversion_mensual_por_vendedor`: el cierre de mes ya lo aplica
-    -- al saldar, y si viviera en el nucleo se descontaria dos veces.
-    select ap.vendedor_id, ap.numerador as pendiente, ap.origenes
-    from private.ajuste_pendiente_por_vendedor() ap
   ),
   filas as (
@@ -332,14 +301,11 @@
       coalesce(b.cierres_referidos, 0) as cierres_referidos,
       coalesce(b.cierres_de_arrastre, 0) as cierres_de_arrastre,
-      -- NETO de lo que se le debe descontar, con suelo en cero. El bruto sigue
-      -- siendo recuperable sumandole `ajuste_pendiente`.
-      private.conversion_con_ajuste(b.numerador, pd.pendiente) as numerador,
-      -- El porcentaje se RECALCULA sobre el neto: el que trae el nucleo es el
-      -- del bruto y enseñarlo aqui contradiria al numerador de su propia fila.
-      case when coalesce(b.divisor, 0) > 0
-        then round(100.0 * private.conversion_con_ajuste(b.numerador, pd.pendiente)
-                   / coalesce(b.divisor, 0), 2) end as conversion_pct,
-      coalesce(pd.pendiente, 0::numeric) as ajuste_pendiente,
-      coalesce(pd.origenes, '[]'::jsonb) as ajuste_origenes,
+      -- NETO de lo que se le debe descontar y porcentaje sobre el neto, tal
+      -- como los sirve la pieza. Quien no tiene fila (ni actividad ni deuda)
+      -- queda en cero y sin porcentaje, igual que antes.
+      coalesce(b.numerador, 0::numeric) as numerador,
+      b.conversion_pct,
+      coalesce(b.ajuste_pendiente, 0::numeric) as ajuste_pendiente,
+      coalesce(b.ajuste_origenes, '[]'::jsonb) as ajuste_origenes,
       coalesce(b.procedencia, '[]'::jsonb) as procedencia,
       coalesce(b.referidos_recibidos, 0) as referidos_recibidos,
@@ -349,5 +315,4 @@
     left join base b on b.analista_id = r.vendedor_id
     left join alta_referidos a on a.analista_id = r.vendedor_id
-    left join pendientes pd on pd.vendedor_id = r.vendedor_id
   ),
   fuera as (
@@ -357,12 +322,14 @@
     -- sale), pero desde D8 (Miguel, 27/08/2026) ademas de declararse en
     -- `cobertura.fuera_de_roster` se SUMA al total: por eso aqui se agregan
-    -- tambien los desgloses que `resumen` necesita. BRUTO a proposito: el
-    -- ajuste de meses ya pagados se descuenta por fila del roster
-    -- (`pendientes`) y el ex-roster no tiene fila donde descontarlo.
+    -- tambien los desgloses que `resumen` necesita. BRUTO a proposito
+    -- (`numerador_bruto`): el ajuste de meses ya pagados se descuenta por fila
+    -- del roster y el ex-roster no tiene fila donde descontarlo. Solo cuenta
+    -- quien aparece en el nucleo (`en_nucleo`): una deuda sin actividad no es
+    -- produccion.
     select
       count(b.analista_id)::int as analistas,
       coalesce(sum(b.divisor), 0)::int as divisor,
       coalesce(sum(b.cierres_no_referidos + b.cierres_referidos), 0)::int as cierres,
-      coalesce(sum(b.numerador), 0::numeric) as numerador,
+      coalesce(sum(b.numerador_bruto), 0::numeric) as numerador,
       coalesce(sum(b.divisor_aproximado), 0)::int as divisor_aproximado,
       coalesce(sum(b.cierres_no_referidos), 0)::int as cierres_no_referidos,
@@ -371,5 +338,6 @@
       coalesce(sum(b.referidos_recibidos), 0)::int as referidos_recibidos
     from base b
-    where not exists (select 1 from roster r where r.vendedor_id = b.analista_id)
+    where b.en_nucleo
+      and not exists (select 1 from roster r where r.vendedor_id = b.analista_id)
   ),
   motivos_totales as (
@@ -383,5 +351,6 @@
       select coalesce(b.divisor_por_motivo, '{}'::jsonb)
       from base b
-      where not exists (select 1 from roster r where r.vendedor_id = b.analista_id)
+      where b.en_nucleo
+        and not exists (select 1 from roster r where r.vendedor_id = b.analista_id)
     ) dm, jsonb_each_text(dm.divisor_por_motivo) e
     group by e.key
--- vivo/crm.cumplimiento_metas_sin_cartera_fn.sql
+++ nuevo/metas8.sql
@@ -93,33 +93,17 @@
     from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
   ), conversiones as (
-    -- El MISMO neto que publica crm.conversion_mensual_fn: si esta pantalla
-    -- enseñara el bruto, el mismo asesor tendria dos porcentajes distintos otra
-    -- vez — la deuda que la migracion 20260813212332 vino a borrar.
-    select cm.analista_id as vendedor_id,
-      (cm.cierres_no_referidos+cm.cierres_referidos)::integer as convertidos,
-      cm.divisor::integer as resueltos,
-      -- ⚠️ `pd.numerador`, NO `pd.pendiente`. Aqui `pd` es la FUNCION
-      -- `private.ajuste_pendiente_por_vendedor()`, que devuelve
-      -- (vendedor_id, numerador, capital_pen, capital_usd, origenes) — no tiene
-      -- ninguna columna `pendiente`. El bloque de la conversion, mas arriba, si
-      -- usa `pd.pendiente`, pero alli `pd` es una CTE que renombra
-      -- `ap.numerador as pendiente`: mismo alias, dos cosas distintas.
-      --
-      -- 🔴 ESTO ESTUVO ROTO Y EN VERDE. plpgsql no valida el SQL de un cuerpo al
-      -- crearlo, asi que la funcion se creaba sin protestar y reventaba con
-      -- 42703 en la PRIMERA llamada, para TODOS los roles: la pantalla de metas
-      -- entera. El oraculo daba 20/20 porque nunca la llamaba — solo la
-      -- nombraba en un comentario. Lo cazo el gate de RLS en la branch.
-      private.conversion_con_ajuste(cm.numerador, pd.numerador) as numerador,
-      cm.cierres_no_referidos,
-      cm.cierres_referidos,
-      case when cm.divisor > 0
-        then round(100.0 * private.conversion_con_ajuste(cm.numerador, pd.numerador)
-                   / cm.divisor, 2) end as conversion_real,
-      coalesce(pd.numerador, 0::numeric) as ajuste_pendiente
-    from private.conversion_mensual_por_vendedor(
-      v_ini,v_fin,true,'{}'::uuid[],v_factor) cm
-    left join private.ajuste_pendiente_por_vendedor() pd
-      on pd.vendedor_id = cm.analista_id
+    -- LA CIFRA POR PERSONA ya no se calcula aqui: sale de la MISMA pieza del
+    -- nucleo que usa la oficial (crm.conversion_mensual_sin_cartera_fn), asi que
+    -- Metas y Ranking no pueden enseñar dos porcentajes del mismo asesor. La
+    -- pieza trae tambien la deuda de quien no tuvo actividad en el mes.
+    select n.analista_id as vendedor_id,
+      (n.cierres_no_referidos+n.cierres_referidos)::integer as convertidos,
+      n.divisor::integer as resueltos,
+      n.numerador,
+      n.cierres_no_referidos,
+      n.cierres_referidos,
+      n.conversion_pct as conversion_real,
+      n.ajuste_pendiente
+    from private.conversion_neta_por_vendedor(p_periodo, true, '{}'::uuid[]) n
   ), visibles as (
     select mv.*,p.nombre_completo,s.nombre_completo as supervisor_nombre
@@ -132,10 +116,9 @@
   )
   select jsonb_build_object(
-    -- DECLARACION. RAMA DEL MES ABIERTO: la cifra se CALCULA aqui, sobre
-    -- `private.conversion_mensual_por_vendedor`, pero SI resta la deuda con
-    -- `private.conversion_con_ajuste`. Por eso `rango_vivo` con
-    -- `ajuste_aplicado: true`: coincide con la oficial, pero no se la pidio.
+    -- DECLARACION. RAMA DEL MES ABIERTO: la cifra la sirve la misma pieza del
+    -- nucleo que la oficial (`private.conversion_neta_por_vendedor`), ya neta de
+    -- la deuda. Por eso `mensual`: es la cifra oficial, no un recalculo propio.
     'es_mes_calendario', true,
-    'fuente', 'rango_vivo',
+    'fuente', 'mensual',
     'sellado', false,
     'ajuste_aplicado', true,
--- vivo/crm.cumplimiento_metas_fn.sql
+++ nuevo/metas7.sql
@@ -17,5 +17,4 @@
   v_ini timestamptz;
   v_fin timestamptz;
-  v_factor numeric;
 begin
   if v_uid is null or (v_rol is null and not v_lector) then
@@ -39,5 +38,4 @@
     v_ini := p_periodo::timestamp at time zone 'America/Lima';
     v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
-    v_factor := private.peso_referido_conversion(p_periodo);
     select mp.id into v_periodo_id
     from crm.meta_periodos mp
@@ -47,8 +45,15 @@
 
     with conv as materialized (
-      select cm.*
-      from private.conversion_mensual_por_vendedor(
-        v_ini, v_fin, true, '{}'::uuid[], v_factor
-      ) cm
+      -- La MISMA pieza del nucleo que la oficial y que la #8. Solo quien aparece
+      -- en el nucleo del mes: una deuda sin actividad no crea fila aqui.
+      select n.*
+      from private.conversion_neta_por_vendedor(p_periodo, true, '{}'::uuid[]) n
+      where n.en_nucleo
+    ), nombrados as materialized (
+      -- A quien la oficial NOMBRA en `responsables` le publica el NETO; al resto
+      -- lo suma BRUTO y sin nombre en `cobertura.fuera_de_roster`. Aqui se
+      -- publica, para cada persona, lo mismo que la oficial (C2, auditoria 21/09).
+      select r.vendedor_id
+      from private.roster_conversion_mensual(p_periodo, true, '{}'::uuid[]) r
     ), prod as materialized (
       select r.*
@@ -101,5 +106,8 @@
         'cierres_de_arrastre', coalesce(cv.cierres_de_arrastre, 0),
         'referidos_recibidos', coalesce(cv.referidos_recibidos, 0),
-        'numerador', coalesce(cv.numerador, 0)
+        'numerador', case
+          when exists (select 1 from nombrados nm where nm.vendedor_id = f.persona_id)
+            then coalesce(cv.numerador, 0)
+          else coalesce(cv.numerador_bruto, 0) end
       ) end,
       'detalles', det.detalles,
```

---

## PROTOCOLO GLOBAL (adjunto)

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
