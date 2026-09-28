ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md (its content is transcribed at the end).

Responde en español. Formato: VERDICT (PASS / CHANGES_REQUESTED / BLOCK), SUMMARY, FINDINGS P0–P3
con evidencia, TEST GAPS, CONFIDENCE. Sin hallazgo sin evidencia. Omite secciones vacías.

# Encargo: CONFIRMAR el cierre de tu P2 (filtro rojo/ámbar sin salida) — commit d301f693 — LEVEL 1

Arreglo: `nivelVigente` = `nivelEquipo` solo si ese nivel conserva integrantes; todo el filtrado,
`aria-pressed` y «Ver todos» usan `nivelVigente`. Prueba nueva: filtro «1 en rojo» → la agenda se
refresca sin no-shows → «Sin alertas en el equipo» y la lista vuelve entera. El e2e ahora busca el
enlace por `/en Seguimiento$/` porque dice «Ver los N en Seguimiento» cuando hay más casos.
Verificación: `npm run check` PASS (4598/4598); e2e Docker 17/17 PASS.

¿Queda cerrado? No repitas hallazgos cerrados.

## DIFF
```diff
commit d301f6930722ffd749272d4fd9ab0c00d78795d9
Author: Miguel Briceño <avancecorp26@gmail.com>
Date:   Sun Sep 27 14:46:15 2026 -0500

    CRM: Hoy del supervisor — el filtro rojo/ámbar se anula si su nivel se vacía (Codex)
    
    Y el e2e busca el enlace a Seguimiento por su final («… en Seguimiento»):
    ahora dice cuántos casos hay cuando son más que las filas visibles.
    
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>

diff --git a/CRM-Avance-Corp/app/e2e/hoy-supervisor-mando.spec.ts b/CRM-Avance-Corp/app/e2e/hoy-supervisor-mando.spec.ts
index 9a48974f..dee59b35 100644
--- a/CRM-Avance-Corp/app/e2e/hoy-supervisor-mando.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/hoy-supervisor-mando.spec.ts
@@ -21,7 +21,7 @@ test('supervisor: decide primero, cola filtrada en el servidor y detalle — tod
   const lista = page.getByRole('list', { name: /^Pendientes del equipo/ })
   await expect(lista.locator(':scope > li')).toHaveCount(7)
   expect(pedidos.at(-1)).toMatchObject({ p_limite: 7, p_senal: 'pendientes', p_cursor: null })
-  await expect(page.getByRole('link', { name: /Ver todo en Seguimiento/ })).toHaveAttribute('href', '#/seguimiento')
+  await expect(page.getByRole('link', { name: /en Seguimiento$/ })).toHaveAttribute('href', '#/seguimiento')
   await page.screenshot({ path: test.info().outputPath('hoy-supervisor-1440x900.png'), animations: 'disabled' })
 
   // Abrir la ficha con teclado y volver con Esc: el foco regresa a la fila
diff --git a/CRM-Avance-Corp/app/e2e/sla-operacion.spec.ts b/CRM-Avance-Corp/app/e2e/sla-operacion.spec.ts
index b1fd70f6..defb5490 100644
--- a/CRM-Avance-Corp/app/e2e/sla-operacion.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/sla-operacion.spec.ts
@@ -170,7 +170,7 @@ for (const rol of ['gerencia', 'supervisor'] as const) {
     const antesDelModulo = pedidos.length
     await expect(page.getByRole('button', { name: 'Seguimiento', exact: true })).toBeVisible()
     if (rol === 'supervisor') {
-      await page.getByRole('link', { name: /Ver todo en Seguimiento/ }).click()
+      await page.getByRole('link', { name: /en Seguimiento$/ }).click()
       await expect(page).toHaveURL(/#\/seguimiento$/)
     } else await irASeguimiento(page)
     await expect.poll(() => pedidos.length).toBeGreaterThan(antesDelModulo)
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
index 288ef4c2..b50b40fb 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.test.tsx
@@ -768,6 +768,23 @@ describe('Hoy · supervisor — puesto de mando: todo número se abre, segunda t
     expect(within(equipo()).getAllByRole('listitem')).toHaveLength(todas)
   })
 
+  it('si el nivel elegido se queda sin nadie tras una actualización, la lista vuelve entera (Codex)', () => {
+    METRICAS_AGENDA = agenda([{ vendedor_id: JORGE, nombre: 'JORGE HUAMÁN', no_asistio: 2 }])
+    LEADS = [
+      lead({ creado_en: '2026-09-26T14:00:00Z' }),
+      lead({ id: 'l-4', nombre_completo: 'LEAD DE JORGE', vendedor_id: JORGE, creado_en: '2026-09-26T14:00:00Z' }),
+    ]
+    const { rerender } = montar()
+    fireEvent.click(screen.getByRole('button', { name: '1 en rojo' }))
+    const equipo = () => screen.getByRole('list', { name: 'Analistas del equipo' })
+    expect(within(equipo()).getAllByRole('listitem')).toHaveLength(1)
+    // La agenda se refresca y Jorge ya no tiene no-shows: nadie en rojo.
+    METRICAS_AGENDA = agenda([{ vendedor_id: JORGE, nombre: 'JORGE HUAMÁN' }])
+    rerender(<HoySupervisorMando />)
+    expect(screen.getByText('Sin alertas en el equipo')).toBeInTheDocument()
+    expect(within(equipo()).getAllByRole('listitem').length).toBeGreaterThan(1)
+  })
+
   it('con más casos que filas, el enlace dice cuántos hay y lleva a Seguimiento', () => {
     RESPONDER = (filtros) => ({ data: pagina(colaTodo(), { filtros: { ...filtros }, total_items: 12, totales: { pendientes: 12 } }), error: null, isFetching: false })
     montar()
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
index 563c0dd6..b6c50d89 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/supervisor-mando.tsx
@@ -238,6 +238,11 @@ function PuestoDeMando(): JSX.Element {
     [rank, rezagosConfirmados],
   )
   const semaforoEquipo = conteoSemaforoEquipo([...lecturas.values()])
+  // El filtro por nivel se anula solo si ese nivel se queda sin nadie (una
+  // actualización resolvió las alertas): nunca una lista vacía sin salida.
+  const nivelVigente = nivelEquipo != null && (nivelEquipo === 'critico' ? semaforoEquipo.rojo : semaforoEquipo.ambar) > 0
+    ? nivelEquipo
+    : null
 
   // ── 1 · Decide primero: las mismas reglas de la franja clásica ──
   // Fail-closed por fuente: un candidato solo existe si su fuente llegó bien,
@@ -610,16 +615,16 @@ function PuestoDeMando(): JSX.Element {
                         {i > 0 && <span aria-hidden>·</span>}
                         <button
                           type="button"
-                          aria-pressed={nivelEquipo === nivel}
+                          aria-pressed={nivelVigente === nivel}
                           disabled={n === 0}
                           onClick={() => setNivelEquipo((actual) => (actual === nivel ? null : nivel))}
-                          className={cn(CLASE_CIFRA, 'disabled:cursor-default disabled:no-underline', nivelEquipo === nivel && 'font-bold text-foreground underline')}
+                          className={cn(CLASE_CIFRA, 'disabled:cursor-default disabled:no-underline', nivelVigente === nivel && 'font-bold text-foreground underline')}
                         >
                           {numero(n)} {texto}
                         </button>
                       </span>
                     ))}
-                    {nivelEquipo != null && (
+                    {nivelVigente != null && (
                       <button type="button" className={cn(CLASE_CIFRA, 'ml-1 text-accent')} onClick={() => setNivelEquipo(null)}>Ver todos</button>
                     )}
                   </div>
@@ -646,7 +651,7 @@ function PuestoDeMando(): JSX.Element {
           ) : (
             // oxlint-disable-next-line jsx-a11y/no-redundant-roles
             <ul role="list" aria-label="Analistas del equipo" className="border-t border-border/60">
-              {rank.filter((r) => nivelEquipo == null || lecturas.get(r.m.perfil_id)?.nivel === nivelEquipo).map((r) => {
+              {rank.filter((r) => nivelVigente == null || lecturas.get(r.m.perfil_id)?.nivel === nivelVigente).map((r) => {
                 const id = r.m.perfil_id
                 const lectura = lecturas.get(id) ?? { nivel: null, senales: [] }
                 const rezago = rezagosConfirmados.get(id)
```

## PROTOCOLO DEL PROYECTO
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

## PROTOCOLO GLOBAL
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
