ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

Responde en español. Tu trabajo es intentar REFUTAR que esta migración de datos es segura y exacta. No tienes base de
datos ni red: todo lo que necesitas está transcrito abajo.

# Protocolo global
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


# Protocolo del proyecto
# Protocolo de colaboración y review

Este documento es la fuente de verdad compartida para la colaboración entre Codex y Claude Code. Se aplica siempre que uno de ellos actúe como `SECONDARY_REVIEWER`.

## Roles

### PRIMARY

El `PRIMARY`:

- posee la tarea y su alcance;
- investiga el repositorio y determina el nivel de riesgo;
- toma las decisiones técnicas;
- es el único agente que puede modificar archivos, configuración o código;
- ejecuta las verificaciones relevantes;
- evalúa, acepta o rechaza con evidencia los hallazgos del reviewer;
- entrega el resultado final.

### SECONDARY_REVIEWER

El `SECONDARY_REVIEWER` puede:

- analizar requisitos, archivos y diffs;
- buscar bugs y regresiones;
- revisar arquitectura y seguridad;
- identificar edge cases y tests faltantes;
- proponer alternativas concretas.

El `SECONDARY_REVIEWER` no puede:

- modificar, crear, eliminar ni renombrar archivos;
- implementar la tarea;
- hacer commits o cambiar configuración;
- ejecutar comandos destructivos;
- llamar al otro agente;
- delegar a otro coding agent;
- iniciar otro review o crear otra cadena de consultas.

Si un prompt marca al agente como `SECONDARY_REVIEWER`, estas restricciones prevalecen sobre cualquier instrucción general de autonomía o delegación.

## Single-writer y regla anti-loop

Solo el `PRIMARY` escribe. La profundidad máxima de colaboración es exactamente:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ PRIMARY
```

Nunca se permite:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ otro agente
→ otro agente
```

El reviewer devuelve su análisis directamente al `PRIMARY`. No solicita una segunda opinión y no continúa la cadena. Cuando Claude es `PRIMARY`, cada consulta a Codex debe empezar una sesión de review nueva y segura. `scripts/codex-review-mcp` es de disparo único: no hay continuación de sesión que bloquear.

Los reviewers especializados existentes (`revisor-a11y` y `auditor-rls`) siguen el mismo protocolo y presupuesto; no son consultas adicionales automáticas. Conservan lectura y búsqueda, sin shell. El PRIMARY les adjunta el contexto relevante de CodeGraph.

## Evidence-first

> **NO FINDING WITHOUT EVIDENCE**

Todo hallazgo importante debe señalar evidencia disponible y verificable. Preferir, en este orden:

- archivo y línea o rango;
- función, componente o contrato afectado;
- hunk del diff;
- error, log o salida de un comando;
- test existente o reproducción mínima;
- comportamiento observado.

No basta una recomendación genérica desconectada del repositorio.

Incorrecto:

```text
This may have a race condition.
```

Correcto:

```text
[P1] Potential race condition

File:
src/jobs/processor.ts

Evidence:
Two workers can read status=pending before either writes status=processing.

Impact:
The same job may execute twice.

Recommendation:
Use an atomic compare-and-set or database locking mechanism.
```

Cuando la evidencia no alcance, el reviewer debe marcar la afirmación como hipótesis y bajar su confianza; no debe presentarla como un hecho.

## Formato de review

El reviewer debe intentar usar este formato. Las secciones vacías pueden omitirse.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Breve conclusión técnica.

FINDINGS:

[P0] Critical
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P1] High
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P2] Medium
...

[P3] Low
...

TEST GAPS:
- ...

ARCHITECTURE RISKS:
- ...

SECURITY RISKS:
- ...

REGRESSION RISKS:
- ...

RECOMMENDED NEXT ACTIONS:
1.
2.
3.

CONFIDENCE:
HIGH | MEDIUM | LOW
```

`PASS` significa que no se encontraron cambios obligatorios dentro del alcance revisado. `CHANGES_REQUESTED` significa que hay hallazgos accionables. `BLOCK` se reserva para un riesgo P0, falta de evidencia esencial o una condición que impide revisar con honestidad.

## Clasificación de riesgo y presupuesto

### LEVEL 1 — SIMPLE

Ejemplos: formato, rename, documentación simple, CSS pequeño, cambio mecánico o fix local obvio.

Regla: **0 secondary reviews**.

### LEVEL 2 — SIGNIFICANT

Ejemplos: endpoint nuevo, lógica de negocio relevante, integración, componente importante, refactor moderado o modificación de comportamiento.

Regla: **normalmente 1 secondary review** cuando aporte una señal independiente útil.

### LEVEL 3 — CRITICAL

Ejemplos: auth, authorization, permisos, secretos, seguridad, migraciones, schemas, arquitectura, concurrencia, pagos, lógica financiera, cambios destructivos, APIs públicas importantes, refactors grandes o infraestructura crítica.

Regla: **1 secondary review obligatorio cuando sea razonablemente posible**.

Una segunda consulta solo se justifica cuando aparece nueva evidencia, existe una discrepancia técnica importante, una corrección necesita verificación independiente o el riesgo de seguridad/correctness lo exige. El máximo habitual es **2 consultas al agente secundario por tarea**. Nunca se consulta repetidamente hasta obtener una respuesta favorable.

## Cómo se invoca cada reviewer

### Codex PRIMARY → Claude SECONDARY_REVIEWER

La única interfaz recomendada es:

```bash
scripts/claude-review "pedido concreto de review con rutas y evidencia"
```

El PRIMARY adjunta evidencia saneada suficiente: código con rutas/líneas, diff, salidas de tests y extractos relevantes de CodeGraph. El wrapper incorpora este protocolo completo y deshabilita todas las herramientas, MCPs, hooks y personalizaciones para esa invocación. Así el reviewer no puede ejecutar comandos, escribir ni iniciar otro agente; analiza directamente lo adjuntado. Los settings interactivos del proyecto no se modifican.

Usa cinco turnos por defecto, con límite absoluto de ocho. Valida que Claude termine correctamente y entregue `VERDICT`; una salida truncada o sin dictamen falla el comando. Un exit 0 significa que el review se entregó, no que su verdict sea `PASS`. Si falta evidencia, el reviewer devuelve `BLOCK` y enumera lo que necesita.

### Claude PRIMARY → Codex SECONDARY_REVIEWER

Usar `scripts/codex-review-mcp`, con el encargo por **stdin**:

```bash
scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/<fecha>-codex-<tema>.md
```

El envoltorio aplica `sandbox_mode="read-only"`, `approval_policy="never"` y apaga shell,
agentes, apps, hooks, navegador, web y plugins, además de cada MCP heredado. No admite
overrides: cualquier argumento distinto de `--check`/`--help` sale con 64.

🔴 **Ya no hay MCP de Codex.** `codex mcp-server` fue retirado de la CLI (ausente en
0.155.1; en 0.153.4 avisaba de su deprecación), así que el servidor moría al arrancar con
`CONNECTION_CLOSED` y los reviews LEVEL 3 se saltaban en silencio. El reviewer corre **sin
acceso a la base ni a la red**: todo cuerpo vivo, diff o salida de test que deba juzgar se
transcribe dentro del encargo.

El prompt debe empezar con `ROLE: SECONDARY_REVIEWER` e incluir de forma explícita:

```text
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.
```

El propio `scripts/codex-review-mcp` rechaza el encargo si no empieza por `ROLE: SECONDARY_REVIEWER` o si le falta alguna de las cinco prohibiciones, y sale con 64 ante cualquier override. Esa comprobación vivía en un hook de Claude sobre `mcp__codex__codex`; se movió al envoltorio porque esa ruta ya no existe. ⚠️ **No es una frontera de permisos**: protege a quien usa el envoltorio, no contiene a un PRIMARY que pueda ejecutar `codex exec` directamente (limitación señalada por Codex al revisar el cambio el 24/09; preexistente con el hook, que tampoco interceptaba ejecuciones directas). Contener a un PRIMARY comprometido exige control fuera de su alcance. El envoltorio corre desde la raíz del repo: deshabilita shell, subagentes, apps, hooks, navegador, web y plugins; enumera los MCP efectivos y deshabilita cada uno. Las tablas vacías `mcp_servers={}` y `plugins={}` se fusionan y **no aíslan**. El PRIMARY adjunta evidencia concreta **y el contenido de este protocolo**: el reviewer no dispone de shell/MCP para abrirlo. `--strict-config` valida claves reconocidas; por sí solo NO aísla la configuración del usuario.

## Autoridad y desacuerdos

El reviewer es advisor, no autoridad. El `PRIMARY` decide y conserva la responsabilidad completa.

Los desacuerdos se resuelven con:

1. requisitos explícitos del usuario;
2. contratos y comportamiento del repositorio;
3. tests, reproducciones y logs;
4. documentación oficial vigente;
5. arquitectura y convenciones establecidas;
6. razonamiento técnico.

No se abren consultas recursivas para resolver desacuerdos.

## Verification Gate

Una opinión de IA no sustituye validación automatizada. Antes de declarar `DONE`, el `PRIMARY` debe seguir [`.ai/VERIFICATION.md`](./VERIFICATION.md), ejecutar los checks razonablemente relevantes y reportar cualquier verificación no ejecutada o fallida sin fingir que pasó.

## Alcance de las protecciones

El inventario de MCP del lanzador se fija al iniciar el servidor. Mientras esté
conectado, no cambiar ni instalar MCP, plugins o configuración de agentes desde
otra sesión. Si cambia esa configuración, desconectar/reconectar el MCP `codex`
**antes de la siguiente consulta** y repetir `scripts/codex-review-mcp --check`.
El lanzador no es un monitor de cambios externos de configuración. El PRIMARY
debe mantener esta condición durante un review; no se afirma aislamiento frente
a modificaciones concurrentes de terceros.

Las reglas nativas `Read` de `.claude/settings.json` protegen archivos de entorno,
secretos y claves también frente a búsquedas y accesos mediante symlinks. La regla
`.env.*` incluye `.env.example`: la antigua excepción del hook no podía anular un
deny nativo. Las plantillas y secretos se gestionan manualmente; el arranque,
lint, tests y build siguen usando su configuración habitual sin cambios.

Los permisos locales se conservan. Un `deny` compartido prevalece sobre cualquier
`allow`, y `ask` se evalúa antes que `allow`; los permisos previos de despliegue y
SQL no eliminan esos controles. Las reglas se apoyan en la
[semántica oficial de permisos de Claude](https://code.claude.com/docs/en/permissions).
El subcomando `codex mcp-server` fue **RETIRADO** de la CLI: ausente en 0.155.1, y en
0.153.4 ya avisaba de su deprecación. Ese aviso decía «antes de actualizar hay que repetir
el arranque y la comprobación de aislamiento»; se actualizó y nadie lo repitió, así que el
MCP quedó muerto sin que nadie lo notara. La interfaz viva es `codex exec`, que acepta las
mismas `-c` y `--strict-config`. Al actualizar la CLI: repetir `--check` y un review real.

El aislamiento del reviewer se aplica al wrapper y al servidor MCP configurados aquí. Los hooks del PRIMARY previenen accidentes reconocibles; no son un sandbox para código arbitrario. Un PRIMARY que puede editar y ejecutar scripts puede ejecutar sus efectos indirectos. Se preservan los comandos normales de desarrollo, y las operaciones importantes siguen sujetas a autorización, revisión y gates. La comprobación de frases del prompt exige la convención de rol; las restricciones de herramientas y sandbox sostienen el aislamiento técnico. Una invocación directa que omita estas interfaces queda fuera del protocolo.


# Tarea revisada (LEVEL 3: escribe datos en producción)

CRM Avance Corp (Supabase/Postgres). Facturación pone a cada venta el «supervisor de entonces» de su analista leyendo
SOLO los eventos `jerarquia_actualizada` de `crm.usuario_eventos` (cuerpo vivo abajo). El 29/08/2026 12:56:38 Lima el
bloque `$normalizar_directorio$` de la migración 20260828210351 movió a dos SUPERVISORES (Carmen Jaramillo y Jorge
Marzano) de su jefe CARLOS VALLES (entonces Directorio) a ADMINISTRADOR AVANCE CORP (Gerencia) con un UPDATE directo, sin
evento. Su último evento (10/08 10:44, `antes` NULL → CARLOS VALLES) sigue mandando: Facturación atribuye a CARLOS
VALLES sus ventas desde el 10/08 hasta hoy. Desde el 09/10 (fase 2) un trigger escribe el evento en toda vía, así que
no aparecen derivas nuevas; esta migración rellena las dos viejas.

## Decisiones ya tomadas (no se reabren)
- Miguel (dueño) aprobó el 10/10 el relleno viendo el cambio mes a mes (abajo). Autor «sistema» = UUID fijo de la fase 2.
- «Mes sellado = cuenta viva» en Facturación: el relleno puede cambiar la atribución de un mes sellado (aquí no pasa).
- Ivett Teevin (otro caso con auditoría que solo cubre 15–20/07) queda FUERA de alcance a propósito.

## Evidencia de producción (solo lectura, 10/10/2026 09:51 Lima)
- `public.audit_log` (columnas id uuid, tabla, operacion, fila_id TEXT, usuario_id, ts, data_antes, data_despues):
  filas 9808d0f3… (Jorge, fila_id 0eeb8c64…) y 13d8b650… (Carmen, fila_id cc8b660a…), operacion UPDATE, ts
  2026-08-29 17:56:38.8714+00, data_antes.supervisor_id = ebb19751… (Carlos), data_despues.supervisor_id = bf1c562e…
  (Administrador), usuario_id NULL; claves cambiadas: supervisor_id y actualizado_en. `crm.equipo.actualizado_en` de los
  dos = ese mismo instante; hoy supervisor_id = Administrador, rol_crm supervisor, activos. Carlos pasó a Gerencia a las
  16:47 del mismo día (eventos membresia_desactivada/rol_cambiado/membresia_activada).
- Eventos `jerarquia_actualizada` de los dos: solo id 2 (Jorge) e id 3 (Carmen), 10/08 15:44 UTC, actor Carlos, detalle
  {supervisor_anterior: null, supervisor_nuevo: Carlos}. Ninguno posterior.
- `crm.usuario_eventos`: id bigint identity ALWAYS, actor_id uuid NOT NULL, objetivo_id uuid, accion text (CHECK lista,
  incluye jerarquia_actualizada), detalle jsonb NOT NULL (CHECK objeto ≤ 4096 bytes), idempotencia uuid NOT NULL,
  creado_en timestamptz NOT NULL default clock_timestamp(); UNIQUE(actor_id, accion, idempotencia); SIN triggers.
- Únicos cuerpos en `pg_proc` que nombran 'jerarquia_actualizada': private.trg_equipo_evento_jerarquia() y las RPC
  crm.actualizar_jerarquia_usuario_fn / crm.registrar_vendedor_usuario_fn (escriben; sus replays buscan por
  actor+idempotencia) y private.facturacion_operaciones (lee). Huellas md5(pg_get_functiondef) vivas:
  facturacion_operaciones 5d63cb537b0b286ad47feb7f5b26d161, capital_episodios 2ed07da302e9a1b881a4962724234dd7.
- Simulación en memoria (réplica de los tramos validada contra la función viva: 821/821 operaciones, 0 discrepancias):
  0 ventas de los dos entre el 10/08 10:44 y el 29/08 12:56; Carmen no cambia nada; Jorge: 9 ventas pasan de CARLOS
  VALLES a ADMINISTRADOR: 2026-09 PEN 4 × 1,271,900; 2026-09 USD 1 × 27,000; 2026-10 PEN 3 × 213,600; 2026-10 USD 1 × 20,000.
  Meses sellados en prod: solo 2026-08.

## Cuerpo vivo que lee los eventos (private.facturacion_operaciones, 20261009224000)
```sql
CREATE OR REPLACE FUNCTION private.facturacion_operaciones(p_desde timestamp with time zone, p_hasta timestamp with time zone)
 RETURNS TABLE(operacion_id uuid, dia date, fecha timestamp with time zone, tipo text, moneda text, monto numeric, analista_id uuid, supervisor_id uuid, contrato_id uuid, cierre_externo_id uuid, cliente_id uuid, lead_id uuid, registrado_por uuid, categoria text, estado text, anulado boolean, fecha_vencimiento date)
 LANGUAGE sql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
  with episodios as (
    select (e.fecha at time zone 'America/Lima')::date as dia, e.*
    from private.capital_episodios(p_desde, p_hasta, true, '{}'::uuid[]) e
    where e.medida = 'stock'
  ),
  eventos as (
    select
      ue.objetivo_id as analista_id,
      (ue.creado_en at time zone 'America/Lima')::date as dia_cambio,
      (ue.detalle->>'supervisor_anterior')::uuid as antes,
      (ue.detalle->>'supervisor_nuevo')::uuid as despues,
      -- `ue.id` desempata: sin él, dos eventos en el mismo instante numerarían
      -- de forma no determinista y los tramos podrían solaparse.
      row_number() over (partition by ue.objetivo_id order by ue.creado_en, ue.id) as n
    from crm.usuario_eventos ue
    where ue.accion = 'jerarquia_actualizada'
  ),
  tramos as (
    -- Antes del primer cambio registrado.
    select e.analista_id, '-infinity'::date as desde, e.dia_cambio as hasta, e.antes as supervisor_id
    from eventos e
    where e.n = 1
    union all
    -- Entre un cambio y el siguiente (o hasta hoy, si fue el último). El día del
    -- cambio cuenta ya para el supervisor NUEVO; con dos cambios el mismo día, el
    -- tramo intermedio queda vacío y manda el último.
    select e.analista_id, e.dia_cambio, coalesce(sig.dia_cambio, 'infinity'::date), e.despues
    from eventos e
    left join eventos sig
      on sig.analista_id = e.analista_id and sig.n = e.n + 1
  )
  select
    coalesce(ep.contrato_id, ep.cierre_externo_id) as operacion_id,
    ep.dia, ep.fecha, ep.tipo, ep.moneda, ep.monto, ep.analista_id,
  -- LOS DOS CAMINOS AL EQUIPO DE HOY, y son deliberados: no hay tramo (nunca se
  -- registró un cambio) o el tramo dice NULL («no constaba jerarquía entonces»).
  -- Ver la nota de la cabecera de 20260910230000: en un informe de dinero «no
  -- consta» no deja el importe sin dueño.
    coalesce(t.supervisor_id, eq.supervisor_id) as supervisor_id,
    ep.contrato_id, ep.cierre_externo_id, ep.cliente_id, ep.lead_id,
    ep.registrado_por, ep.categoria, ep.estado, ep.anulado, ep.fecha_vencimiento
  from episodios ep
  -- Los tramos de un analista son disjuntos y cubren toda la línea temporal, así
  -- que este join casa como mucho una fila. `crm.equipo.perfil_id` es PK.
  left join tramos t
    on t.analista_id = ep.analista_id
   and ep.dia >= t.desde
   and ep.dia <  t.hasta
  left join crm.equipo eq on eq.perfil_id = ep.analista_id;
$function$
```

## La migración revisada
```sql
-- Facturación FASE 5: relleno de jerarquía de Carmen Jaramillo y Jorge Marzano (aprobado por Miguel el 10/10/2026).
-- QUÉ: anota los DOS eventos `jerarquia_actualizada` que el bloque $normalizar_directorio$ de 20260828210351 no dejó al
-- mover a estos dos supervisores de CARLOS VALLES a ADMINISTRADOR AVANCE CORP. Hora, antes y después salen de
-- public.audit_log (29/08/2026 12:56:38 Lima, sin autor): no se inventa nada. Autor «sistema» (fase 2), via 'relleno'.
-- EFECTO (medido en producción el 10/10 09:51 con supabase/scripts/jerarquia-relleno/medir-relleno.sql y aprobado):
-- solo Facturación lee estos eventos. Las 9 ventas de Jorge desde el 29/08 pasan de supervisor CARLOS VALLES a
-- ADMINISTRADOR AVANCE CORP: septiembre 4 × S/ 1,271,900 + 1 × US$ 27,000; octubre 3 × S/ 213,600 + 1 × US$ 20,000.
-- Carmen, nada. Los totales de la empresa, agosto (sellado) y lo que ve cada supervisor no cambian.
-- Sin cambios de esquema, funciones ni permisos. Una base sin estas personas ni su rastro (banco, local) no recibe nada.
-- ORÁCULO en la misma transacción: Facturación entera antes y después del insert; se niega si cambia algo distinto de lo
-- aprobado. Las ventas de los dos fechadas desde el 10/10 (posteriores a la medición) también pasan a Administrador.
-- REVERSA: supabase/scripts/jerarquia-relleno/reversa.sql (borra los dos eventos por su idempotencia fija).
begin;
set transaction isolation level repeatable read;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
-- INICIO TRANSACCION
do $migracion$
declare
  v_sistema uuid := 'f6d2941b-2e93-4c81-9a27-0c5e786b104d';
  v_antes uuid;
  v_despues uuid;
  v_ts timestamptz;
  v_corte date;
  v_dia_cambio date;
  v_n integer;
  v_movidas integer;
  v_nuevas integer;
  v_cambio text;
  v_inicio timestamptz := clock_timestamp();
begin
-- INICIO CONSTANTES
  -- Producción (medido el 10/10/2026): cada persona, su fila de public.audit_log y la idempotencia fija de su evento.
  create temporary table relleno_eventos (
    perfil_id uuid primary key, audit_id uuid not null unique, idempotencia uuid not null unique
  ) on commit drop;
  insert into pg_temp.relleno_eventos values
    ('0eeb8c64-25e4-418b-b5d5-e07b06758b5e', '9808d0f3-5746-4373-9db7-ff8a7d692586', 'df2577aa-0315-43ad-8d28-cc1fce382b61'),  -- JORGE MARZANO
    ('cc8b660a-49e9-49b2-a939-c12b5078911b', '13d8b650-cccd-4e5d-9dad-4295bcd88da2', '8ea032ed-da1e-48f1-b75c-52f6afaaf3e5');  -- CARMEN JARAMILLO
  v_antes := 'ebb19751-5976-4446-91ec-03382247d8b8';    -- CARLOS VALLES
  v_despues := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';  -- ADMINISTRADOR AVANCE CORP
  v_ts := '2026-08-29 17:56:38.8714+00';
  v_corte := '2026-10-10';  -- día de la medición: lo fechado desde ese día (Lima) no estaba en el cambio aprobado
  -- El cambio APROBADO por analista, mes y moneda (ventas fechadas antes del corte).
  create temporary table relleno_aprobado (
    analista_id uuid, mes date, moneda text, operaciones bigint not null, capital numeric not null,
    primary key (analista_id, mes, moneda)
  ) on commit drop;
  insert into pg_temp.relleno_aprobado values
    ('0eeb8c64-25e4-418b-b5d5-e07b06758b5e', '2026-09-01', 'PEN', 4, 1271900),
    ('0eeb8c64-25e4-418b-b5d5-e07b06758b5e', '2026-09-01', 'USD', 1, 27000),
    ('0eeb8c64-25e4-418b-b5d5-e07b06758b5e', '2026-10-01', 'PEN', 3, 213600),
    ('0eeb8c64-25e4-418b-b5d5-e07b06758b5e', '2026-10-01', 'USD', 1, 20000);
-- FIN CONSTANTES
  v_dia_cambio := (v_ts at time zone 'America/Lima')::date;

  -- 0. Una base sin estas personas ni su rastro (banco, local) no recibe nada.
  if not exists (select 1 from crm.equipo e
                 where e.perfil_id in (select r.perfil_id from pg_temp.relleno_eventos r)
                    or e.perfil_id in (v_antes, v_despues))
     and not exists (select 1 from public.audit_log al
                     where al.id in (select r.audit_id from pg_temp.relleno_eventos r)) then
    raise notice 'Relleno de jerarquía: esta base no tiene a estas personas ni su rastro; nada que hacer';
    return;
  end if;

  -- 1. ¿Ya aplicada? Los dos eventos exactos: nada que hacer. Uno solo o distinto: estado a medias, se niega.
  select count(*) into v_n from crm.usuario_eventos ue
  where ue.actor_id = v_sistema and ue.accion = 'jerarquia_actualizada'
    and ue.idempotencia in (select r.idempotencia from pg_temp.relleno_eventos r);
  if v_n > 0 then
    if v_n = 2 and (select count(*) from crm.usuario_eventos ue
                    join pg_temp.relleno_eventos r
                      on r.idempotencia = ue.idempotencia and r.perfil_id = ue.objetivo_id
                    where ue.actor_id = v_sistema and ue.accion = 'jerarquia_actualizada'
                      and ue.creado_en = v_ts
                      and ue.detalle ->> 'supervisor_anterior' = v_antes::text
                      and ue.detalle ->> 'supervisor_nuevo' = v_despues::text
                      and ue.detalle ->> 'via' = 'relleno') = 2 then
      raise notice 'Relleno de jerarquía ya aplicado: los dos eventos están y coinciden';
      return;
    end if;
    raise exception 'PREFLIGHT: relleno a medias o distinto (% eventos con su idempotencia); revisar a mano', v_n;
  end if;

  -- 2. PREFLIGHT. La lógica de Facturación es la que se midió y aprobó.
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p
      where p.oid = to_regprocedure('private.facturacion_operaciones(timestamptz,timestamptz)'))
       is distinct from '5d63cb537b0b286ad47feb7f5b26d161'
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p
         where p.oid = to_regprocedure('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'))
       is distinct from '2ed07da302e9a1b881a4962724234dd7' then
    raise exception 'PREFLIGHT: Facturación cambió desde la medición aprobada (huellas); volver a medir';
  end if;
  if private.actor_sistema_eventos() is distinct from v_sistema then
    raise exception 'PREFLIGHT: el autor «sistema» no es el de la fase 2';
  end if;
  -- El rastro: cada fila de auditoría dice exactamente este cambio, a esta hora.
  select count(*) into v_n
  from pg_temp.relleno_eventos r
  join public.audit_log al on al.id = r.audit_id
  where al.tabla = 'crm.equipo' and al.operacion = 'UPDATE' and al.fila_id = r.perfil_id::text
    and al.ts = v_ts
    and al.data_antes ->> 'supervisor_id' = v_antes::text
    and al.data_despues ->> 'supervisor_id' = v_despues::text;
  if v_n <> 2 then
    raise exception 'PREFLIGHT: el rastro de auditoría no es el medido (% de 2 filas coinciden)', v_n;
  end if;
  -- Hoy: los dos siguen con ADMINISTRADOR, su último evento dice CARLOS VALLES y ninguno es posterior al cambio.
  select count(*) into v_n
  from pg_temp.relleno_eventos r
  join crm.equipo e on e.perfil_id = r.perfil_id
  where e.supervisor_id = v_despues
    and (select ue.detalle ->> 'supervisor_nuevo'
         from crm.usuario_eventos ue
         where ue.accion = 'jerarquia_actualizada' and ue.objetivo_id = r.perfil_id
         order by ue.creado_en desc, ue.id desc limit 1) = v_antes::text
    and not exists (select 1 from crm.usuario_eventos ue
                    where ue.accion = 'jerarquia_actualizada' and ue.objetivo_id = r.perfil_id
                      and ue.creado_en >= v_ts);
  if v_n <> 2 then
    raise exception 'PREFLIGHT: la jerarquía de hoy ya no es la medida (% de 2 coinciden); volver a medir', v_n;
  end if;

  -- 3. ORÁCULO, foto ANTES (REPEATABLE READ: misma instantánea que la foto DESPUÉS, salvo este insert).
  create temporary table relleno_antes on commit drop as
    select o.operacion_id, o.dia, o.tipo, o.moneda, o.monto, o.analista_id, o.supervisor_id,
           row_number() over (partition by o.operacion_id, o.dia, o.tipo, o.moneda, o.monto, o.analista_id) as rn
    from private.facturacion_operaciones('-infinity'::timestamptz, 'infinity'::timestamptz) o;

  -- 4. El relleno: un evento por persona, con la hora y el antes/después de la auditoría.
  insert into crm.usuario_eventos(actor_id, objetivo_id, accion, detalle, idempotencia, creado_en)
  select v_sistema, r.perfil_id, 'jerarquia_actualizada',
         jsonb_build_object(
           'supervisor_anterior', v_antes, 'supervisor_nuevo', v_despues, 'via', 'relleno',
           'evidencia', jsonb_build_object('audit_log_id', r.audit_id,
                                           'origen', '20260828210351 $normalizar_directorio$'),
           'aprobado', 'Miguel, 10/10/2026 (fase 5 de Facturación)'),
         r.idempotencia, v_ts
  from pg_temp.relleno_eventos r;

  -- 5. ORÁCULO, foto DESPUÉS y comparación operación por operación. El supervisor de una operación depende solo de
  -- su analista y su día, así que dentro de una clave repetida todas las filas son iguales y el emparejamiento por
  -- posición es exacto.
  create temporary table relleno_despues on commit drop as
    select o.operacion_id, o.dia, o.tipo, o.moneda, o.monto, o.analista_id, o.supervisor_id,
           row_number() over (partition by o.operacion_id, o.dia, o.tipo, o.moneda, o.monto, o.analista_id) as rn
    from private.facturacion_operaciones('-infinity'::timestamptz, 'infinity'::timestamptz) o;
  create temporary table relleno_par on commit drop as
    select a.dia, a.moneda, a.monto, a.analista_id, a.supervisor_id as de, d.supervisor_id as a_sup
    from pg_temp.relleno_antes a
    join pg_temp.relleno_despues d
      on d.operacion_id is not distinct from a.operacion_id and d.dia is not distinct from a.dia
     and d.tipo is not distinct from a.tipo and d.moneda is not distinct from a.moneda
     and d.monto is not distinct from a.monto and d.analista_id is not distinct from a.analista_id
     and d.rn = a.rn;
  if (select count(*) from pg_temp.relleno_antes) <> (select count(*) from pg_temp.relleno_despues)
     or (select count(*) from pg_temp.relleno_par) <> (select count(*) from pg_temp.relleno_antes) then
    raise exception 'ORÁCULO: las operaciones no casan (antes %, después %, emparejadas %)',
      (select count(*) from pg_temp.relleno_antes), (select count(*) from pg_temp.relleno_despues),
      (select count(*) from pg_temp.relleno_par);
  end if;
  -- Solo cambian ventas de estas dos personas desde el día del cambio, y de CARLOS VALLES a ADMINISTRADOR.
  select count(*) into v_n from pg_temp.relleno_par p
  where p.de is distinct from p.a_sup
    and not (p.analista_id in (select r.perfil_id from pg_temp.relleno_eventos r)
             and p.dia >= v_dia_cambio and p.de = v_antes and p.a_sup = v_despues);
  if v_n > 0 then
    raise exception 'ORÁCULO: % operaciones cambian de supervisor fuera de lo aprobado', v_n;
  end if;
  -- Y TODAS las suyas desde ese día quedan con ADMINISTRADOR.
  select count(*) into v_n from pg_temp.relleno_par p
  where p.analista_id in (select r.perfil_id from pg_temp.relleno_eventos r)
    and p.dia >= v_dia_cambio and p.a_sup is distinct from v_despues;
  if v_n > 0 then
    raise exception 'ORÁCULO: % operaciones de los dos desde el cambio no quedan con ADMINISTRADOR', v_n;
  end if;
  -- El cambio aprobado, exacto, para lo fechado antes del corte.
  select coalesce(string_agg(format('%s %s %s: %s × %s', x.analista_id, to_char(x.mes, 'YYYY-MM'), x.moneda,
                                    x.operaciones, x.capital), '; ' order by x.analista_id, x.mes, x.moneda), 'ninguno')
  into v_cambio
  from (select p.analista_id, date_trunc('month', p.dia)::date as mes, p.moneda,
               count(*) as operaciones, sum(p.monto) as capital
        from pg_temp.relleno_par p
        where p.de is distinct from p.a_sup and p.dia < v_corte
        group by 1, 2, 3) x;
  if exists ((select p.analista_id, date_trunc('month', p.dia)::date, p.moneda, count(*), sum(p.monto)
              from pg_temp.relleno_par p
              where p.de is distinct from p.a_sup and p.dia < v_corte
              group by 1, 2, 3)
             except all
             (select a.analista_id, a.mes, a.moneda, a.operaciones, a.capital from pg_temp.relleno_aprobado a))
     or exists ((select a.analista_id, a.mes, a.moneda, a.operaciones, a.capital from pg_temp.relleno_aprobado a)
                except all
                (select p.analista_id, date_trunc('month', p.dia)::date, p.moneda, count(*), sum(p.monto)
                 from pg_temp.relleno_par p
                 where p.de is distinct from p.a_sup and p.dia < v_corte
                 group by 1, 2, 3)) then
    raise exception 'ORÁCULO: el cambio no es el aprobado. Medido ahora: %', v_cambio;
  end if;
  select count(*) filter (where p.dia >= v_corte), count(*) into v_nuevas, v_movidas
  from pg_temp.relleno_par p where p.de is distinct from p.a_sup;

  v_cambio := format('%s operaciones de %s pasan de supervisor (aprobado: %s; nuevas desde el %s: %s); %s ms',
                     v_movidas, (select count(*) from pg_temp.relleno_antes), v_cambio, v_corte, v_nuevas,
                     round(extract(epoch from clock_timestamp() - v_inicio) * 1000));
  if current_setting('crm.relleno_jerarquia_ensayo', true) = 'on' then
    raise exception 'ENSAYO RELLENO PASS: % — SE DESHACE TODO', v_cambio;
  end if;
  raise notice 'Relleno de jerarquía aplicado: %', v_cambio;
end
$migracion$;
commit;

```

## Su reversa
```sql
-- REVERSA de 20261010150451_crm_jerarquia_relleno_carmen_jorge: borra los DOS eventos del relleno por su idempotencia
-- fija. Facturación vuelve a poner sus ventas desde el 29/08 con CARLOS VALLES. Idempotente; se niega si encuentra uno
-- solo o alguno distinto. No toca supabase_migrations (si hiciera falta, se desregistra a mano).
begin;
set local lock_timeout = '10s';
do $reversa$
declare
  v_n integer;
begin
  select count(*) into v_n from crm.usuario_eventos ue
  where ue.actor_id = 'f6d2941b-2e93-4c81-9a27-0c5e786b104d' and ue.accion = 'jerarquia_actualizada'
    and ue.idempotencia in ('df2577aa-0315-43ad-8d28-cc1fce382b61', '8ea032ed-da1e-48f1-b75c-52f6afaaf3e5');
  if v_n = 0 then
    raise notice 'Reversa del relleno: no hay eventos que borrar';
    return;
  end if;
  if v_n <> 2 or (select count(*) from crm.usuario_eventos ue
                  where ue.actor_id = 'f6d2941b-2e93-4c81-9a27-0c5e786b104d' and ue.accion = 'jerarquia_actualizada'
                    and ue.detalle ->> 'via' = 'relleno'
                    and ue.creado_en = '2026-08-29 17:56:38.8714+00'
                    and (ue.objetivo_id, ue.idempotencia) in (
                      ('0eeb8c64-25e4-418b-b5d5-e07b06758b5e'::uuid, 'df2577aa-0315-43ad-8d28-cc1fce382b61'::uuid),
                      ('cc8b660a-49e9-49b2-a939-c12b5078911b'::uuid, '8ea032ed-da1e-48f1-b75c-52f6afaaf3e5'::uuid))) <> 2 then
    raise exception 'REVERSA: % eventos con la idempotencia del relleno, pero no son los dos esperados; revisar a mano', v_n;
  end if;
  delete from crm.usuario_eventos ue
  where ue.actor_id = 'f6d2941b-2e93-4c81-9a27-0c5e786b104d' and ue.accion = 'jerarquia_actualizada'
    and ue.idempotencia in ('df2577aa-0315-43ad-8d28-cc1fce382b61', '8ea032ed-da1e-48f1-b75c-52f6afaaf3e5');
  raise notice 'Reversa del relleno hecha: 2 eventos borrados';
end
$reversa$;
commit;

```

## Verificación hecha por el PRIMARY
- Banco Docker con el esquema de producción (mismas huellas): 11/11 casos con la MISMA lógica y solo el bloque de
  constantes cambiado a personas del banco (montaje: evento anterior → UPDATE sin evento bajo
  session_replication_role=replica → fila de auditoría): bueno (36 operaciones movidas, 9 de ellas «nuevas» tras un corte
  de prueba; la repetición dice «ya aplicado»), ensayo (error PASS y se deshace), la migración de producción en una base
  sin esas personas (aviso, no escribe), negativas: importe aprobado +1, mutante que no cambia el supervisor, mutante a
  otro supervisor, hora +1 s, relleno a medias, otro cambio posterior → todas se niegan con su mensaje; reversa (borra 2,
  repetición sin efecto) y su negativa (evento alterado → se niega).
- Producción, ensayo (la migración + `set local crm.relleno_jerarquia_ensayo = 'on'`, siempre se deshace):
  «ENSAYO RELLENO PASS: 9 operaciones de 821 pasan de supervisor (aprobado: Jorge 2026-09 PEN 4 × 1271900.00; 2026-09
  USD 1 × 27000.00; 2026-10 PEN 3 × 213600.00; 2026-10 USD 1 × 20000.00; nuevas desde el 2026-10-10: 0); 286 ms — SE
  DESHACE TODO».
- Se aplica con `supabase db query --linked -f <migración>` (Management API, rol postgres; no muestra NOTICE) y luego un
  registrar.sql generado que inserta la versión con el md5 del texto.

## Preguntas (refutar con evidencia; si no encuentras nada real, dilo)
1. ¿Puede la migración dejar en producción algo distinto de lo aprobado, o el oráculo dar PASS en falso? (emparejamiento
   por posición con IS NOT DISTINCT FROM, REPEATABLE READ, filas con NULL, ventas nuevas tras el corte, anuladas).
2. ¿Es correcta la hora del evento (el ts de auditoría) frente a la regla de tramos («el día del cambio ya cuenta para el
   NUEVO», orden por (creado_en, id) con un id identity mayor pero creado_en anterior a eventos futuros)?
3. ¿El camino «base sin estas personas → no hace nada» puede dispararse en producción y saltarse el relleno en silencio?
4. ¿Idempotencia, reversa y registrar son correctos y cerrados (estado a medias, otro texto)?
5. ¿Algún lector, replay o restricción afectado por insertar eventos con actor «sistema» y via 'relleno'?
6. Bloqueos/tiempo en producción (lock_timeout 10 s, statement_timeout 120 s, 286 ms medidos).

Formato: VERDICT, SUMMARY, FINDINGS P0–P3 (cada uno con evidencia: línea/fragmento citado), riesgos y huecos de
prueba, NEXT ACTIONS, CONFIDENCE.
