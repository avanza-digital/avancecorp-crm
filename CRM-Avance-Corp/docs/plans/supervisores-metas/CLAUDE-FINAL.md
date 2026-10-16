ROLE: SECONDARY_REVIEWER. Codex is PRIMARY and sole writer. Independent final review only; no tools, no files, no implementation, no delegation or recursive review. Return plain text starting EXACTLY with VERDICT: PASS or VERDICT: CHANGES_REQUESTED or VERDICT: BLOCKED. Then SUMMARY, evidence-backed FINDINGS P0-P3, relevant gaps, RECOMMENDED NEXT ACTIONS and CONFIDENCE. Do not use a Markdown heading before VERDICT. All evidence needed is embedded; do not assume missing code is broken.

This is the second completed review, following your architectural CHANGES_REQUESTED. Review revised implementation for correctness, cross-team exposure, closed months, no double-counting and RPC compatibility. No deployment in scope of this review; local result prepared for promotion. The user expressly asked Claude + JEV help. JEV only selected context, never judged money/permissions.

User: supervisors' own sales count personally and toward own team target since October 2026, and appear at bottom of ranking. No personal target amount supplied. Adopted your compatible outside-ranking contract, no new RPC keys, no synthetic zero-sales rows, own UUID filter before joins, frozen own JSON filter. No changes to financial/conversion kernels, RLS, grants, tables or closure writer.

Evidence adjudication from first review: agregarCumplimientos already strips conversion realized/divisor/numerator. Real risk was conversion target average dilution; explicitly preserve original team target. ATR-4 says money is NOT reduced on cancellation (only conversion), so proposed monetary debt concern was inapplicable. Existing monthly goal membership remains historical; four current supervisors had no October analyst goals in read-only aggregated production query. Backend inside/outside sets are disjoint by UUID. App's supervisores property is DERIVED view data, NOT a new RPC key.

Validation: npm run check PASS (434 files / 6983 unit tests, lint/types/coverage/config/build/bundle/dup). SQL 59 assertions PASS incl 54 JSON reads before/after, global byte-equivalent JSON, scope, cooperatives, inactive profile/membership, role downgrade, frozen November without November operations, no mutation, reversa/reapply. Docker 9 passed, no failures; strengthening new 2 tests with matching live roster UUIDs running now. Cloud Auth/PostgREST/advisors and full migration replay NOT RUN; local PostgreSQL authenticated roles cover this function; production untouched.


FILE .ai/REVIEW_PROTOCOL.md
1: # Protocolo de colaboración y review
2: 
3: Este documento es la fuente de verdad compartida para la colaboración entre Codex y Claude Code. Se aplica siempre que uno de ellos actúe como `SECONDARY_REVIEWER`.
4: 
5: ## Roles
6: 
7: ### PRIMARY
8: 
9: El `PRIMARY`:
10: 
11: - posee la tarea y su alcance;
12: - investiga el repositorio y determina el nivel de riesgo;
13: - toma las decisiones técnicas;
14: - es el único agente que puede modificar archivos, configuración o código;
15: - ejecuta las verificaciones relevantes;
16: - evalúa, acepta o rechaza con evidencia los hallazgos del reviewer;
17: - entrega el resultado final.
18: 
19: ### SECONDARY_REVIEWER
20: 
21: El `SECONDARY_REVIEWER` puede:
22: 
23: - analizar requisitos, archivos y diffs;
24: - buscar bugs y regresiones;
25: - revisar arquitectura y seguridad;
26: - identificar edge cases y tests faltantes;
27: - proponer alternativas concretas.
28: 
29: El `SECONDARY_REVIEWER` no puede:
30: 
31: - modificar, crear, eliminar ni renombrar archivos;
32: - implementar la tarea;
33: - hacer commits o cambiar configuración;
34: - ejecutar comandos destructivos;
35: - llamar al otro agente;
36: - delegar a otro coding agent;
37: - iniciar otro review o crear otra cadena de consultas.
38: 
39: Si un prompt marca al agente como `SECONDARY_REVIEWER`, estas restricciones prevalecen sobre cualquier instrucción general de autonomía o delegación.
40: 
41: ## Single-writer y regla anti-loop
42: 
43: Solo el `PRIMARY` escribe. La profundidad máxima de colaboración es exactamente:
44: 
45: ```text
46: PRIMARY
47: → SECONDARY_REVIEWER
48: → PRIMARY
49: ```
50: 
51: Nunca se permite:
52: 
53: ```text
54: PRIMARY
55: → SECONDARY_REVIEWER
56: → otro agente
57: → otro agente
58: ```
59: 
60: El reviewer devuelve su análisis directamente al `PRIMARY`. No solicita una segunda opinión y no continúa la cadena. Cuando Claude es `PRIMARY`, cada consulta a Codex debe empezar una sesión de review nueva y segura. `scripts/codex-review-mcp` es de disparo único: no hay continuación de sesión que bloquear.
61: 
62: Los reviewers especializados existentes (`revisor-a11y` y `auditor-rls`) siguen el mismo protocolo y presupuesto; no son consultas adicionales automáticas. Conservan lectura y búsqueda, sin shell. El PRIMARY les adjunta el contexto relevante de CodeGraph.
63: 
64: ## Evidence-first
65: 
66: > **NO FINDING WITHOUT EVIDENCE**
67: 
68: Todo hallazgo importante debe señalar evidencia disponible y verificable. Preferir, en este orden:
69: 
70: - archivo y línea o rango;
71: - función, componente o contrato afectado;
72: - hunk del diff;
73: - error, log o salida de un comando;
74: - test existente o reproducción mínima;
75: - comportamiento observado.
76: 
77: No basta una recomendación genérica desconectada del repositorio.
78: 
79: Incorrecto:
80: 
81: ```text
82: This may have a race condition.
83: ```
84: 
85: Correcto:
86: 
87: ```text
88: [P1] Potential race condition
89: 
90: File:
91: src/jobs/processor.ts
92: 
93: Evidence:
94: Two workers can read status=pending before either writes status=processing.
95: 
96: Impact:
97: The same job may execute twice.
98: 
99: Recommendation:
100: Use an atomic compare-and-set or database locking mechanism.
101: ```
102: 
103: Cuando la evidencia no alcance, el reviewer debe marcar la afirmación como hipótesis y bajar su confianza; no debe presentarla como un hecho.
104: 
105: ## Formato de review
106: 
107: El reviewer debe intentar usar este formato. Las secciones vacías pueden omitirse.
108: 
109: ```text
110: VERDICT:
111: PASS | CHANGES_REQUESTED | BLOCK
112: 
113: SUMMARY:
114: Breve conclusión técnica.
115: 
116: FINDINGS:
117: 
118: [P0] Critical
119: File:
120: Lines:
121: Problem:
122: Evidence:
123: Impact:
124: Recommendation:
125: 
126: [P1] High
127: File:
128: Lines:
129: Problem:
130: Evidence:
131: Impact:
132: Recommendation:
133: 
134: [P2] Medium
135: ...
136: 
137: [P3] Low
138: ...
139: 
140: TEST GAPS:
141: - ...
142: 
143: ARCHITECTURE RISKS:
144: - ...
145: 
146: SECURITY RISKS:
147: - ...
148: 
149: REGRESSION RISKS:
150: - ...
151: 
152: RECOMMENDED NEXT ACTIONS:
153: 1.
154: 2.
155: 3.
156: 
157: CONFIDENCE:
158: HIGH | MEDIUM | LOW
159: ```
160: 
161: `PASS` significa que no se encontraron cambios obligatorios dentro del alcance revisado. `CHANGES_REQUESTED` significa que hay hallazgos accionables. `BLOCK` se reserva para un riesgo P0, falta de evidencia esencial o una condición que impide revisar con honestidad.
162: 
163: ## Clasificación de riesgo y presupuesto
164: 
165: ### LEVEL 1 — SIMPLE
166: 
167: Ejemplos: formato, rename, documentación simple, CSS pequeño, cambio mecánico o fix local obvio.
168: 
169: Regla: **0 secondary reviews**.
170: 
171: ### LEVEL 2 — SIGNIFICANT
172: 
173: Ejemplos: endpoint nuevo, lógica de negocio relevante, integración, componente importante, refactor moderado o modificación de comportamiento.
174: 
175: Regla: **normalmente 1 secondary review** cuando aporte una señal independiente útil.
176: 
177: ### LEVEL 3 — CRITICAL
178: 
179: Ejemplos: auth, authorization, permisos, secretos, seguridad, migraciones, schemas, arquitectura, concurrencia, pagos, lógica financiera, cambios destructivos, APIs públicas importantes, refactors grandes o infraestructura crítica.
180: 
181: Regla: **1 secondary review obligatorio cuando sea razonablemente posible**.
182: 
183: Una segunda consulta solo se justifica cuando aparece nueva evidencia, existe una discrepancia técnica importante, una corrección necesita verificación independiente o el riesgo de seguridad/correctness lo exige. El máximo habitual es **2 consultas al agente secundario por tarea**. Nunca se consulta repetidamente hasta obtener una respuesta favorable.
184: 
185: ## Cómo se invoca cada reviewer
186: 
187: ### Codex PRIMARY → Claude SECONDARY_REVIEWER
188: 
189: La única interfaz recomendada es:
190: 
191: ```bash
192: scripts/claude-review "pedido concreto de review con rutas y evidencia"
193: ```
194: 
195: El PRIMARY adjunta evidencia saneada suficiente: código con rutas/líneas, diff, salidas de tests y extractos relevantes de CodeGraph. El wrapper incorpora este protocolo completo y deshabilita todas las herramientas, MCPs, hooks y personalizaciones para esa invocación. Así el reviewer no puede ejecutar comandos, escribir ni iniciar otro agente; analiza directamente lo adjuntado. Los settings interactivos del proyecto no se modifican.
196: 
197: Usa cinco turnos por defecto, con límite absoluto de ocho. Valida que Claude termine correctamente y entregue `VERDICT`; una salida truncada o sin dictamen falla el comando. Un exit 0 significa que el review se entregó, no que su verdict sea `PASS`. Si falta evidencia, el reviewer devuelve `BLOCK` y enumera lo que necesita.
198: 
199: ### Claude PRIMARY → Codex SECONDARY_REVIEWER
200: 
201: Usar `scripts/codex-review-mcp`, con el encargo por **stdin**:
202: 
203: ```bash
204: scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/<fecha>-codex-<tema>.md
205: ```
206: 
207: El envoltorio aplica `sandbox_mode="read-only"`, `approval_policy="never"` y apaga shell,
208: agentes, apps, hooks, navegador, web y plugins, además de cada MCP heredado. No admite
209: overrides: cualquier argumento distinto de `--check`/`--help` sale con 64.
210: 
211: 🔴 **Ya no hay MCP de Codex.** `codex mcp-server` fue retirado de la CLI (ausente en
212: 0.155.1; en 0.153.4 avisaba de su deprecación), así que el servidor moría al arrancar con
213: `CONNECTION_CLOSED` y los reviews LEVEL 3 se saltaban en silencio. El reviewer corre **sin
214: acceso a la base ni a la red**: todo cuerpo vivo, diff o salida de test que deba juzgar se
215: transcribe dentro del encargo.
216: 
217: El prompt debe empezar con `ROLE: SECONDARY_REVIEWER` e incluir de forma explícita:
218: 
219: ```text
220: Do not modify files.
221: Do not implement the task.
222: Do not invoke Claude.
223: Do not delegate to another coding agent.
224: Do not create another review chain.
225: Follow .ai/REVIEW_PROTOCOL.md.
226: ```
227: 
228: El propio `scripts/codex-review-mcp` rechaza el encargo si no empieza por `ROLE: SECONDARY_REVIEWER` o si le falta alguna de las cinco prohibiciones, y sale con 64 ante cualquier override. Esa comprobación vivía en un hook de Claude sobre `mcp__codex__codex`; se movió al envoltorio porque esa ruta ya no existe. ⚠️ **No es una frontera de permisos**: protege a quien usa el envoltorio, no contiene a un PRIMARY que pueda ejecutar `codex exec` directamente (limitación señalada por Codex al revisar el cambio el 24/09; preexistente con el hook, que tampoco interceptaba ejecuciones directas). Contener a un PRIMARY comprometido exige control fuera de su alcance. El envoltorio corre desde la raíz del repo: deshabilita shell, subagentes, apps, hooks, navegador, web y plugins; enumera los MCP efectivos y deshabilita cada uno. Las tablas vacías `mcp_servers={}` y `plugins={}` se fusionan y **no aíslan**. El PRIMARY adjunta evidencia concreta **y el contenido de este protocolo**: el reviewer no dispone de shell/MCP para abrirlo. `--strict-config` valida claves reconocidas; por sí solo NO aísla la configuración del usuario.
229: 
230: ## Autoridad y desacuerdos
231: 
232: El reviewer es advisor, no autoridad. El `PRIMARY` decide y conserva la responsabilidad completa.
233: 
234: Los desacuerdos se resuelven con:
235: 
236: 1. requisitos explícitos del usuario;
237: 2. contratos y comportamiento del repositorio;
238: 3. tests, reproducciones y logs;
239: 4. documentación oficial vigente;
240: 5. arquitectura y convenciones establecidas;
241: 6. razonamiento técnico.
242: 
243: No se abren consultas recursivas para resolver desacuerdos.
244: 
245: ## Verification Gate
246: 
247: Una opinión de IA no sustituye validación automatizada. Antes de declarar `DONE`, el `PRIMARY` debe seguir [`.ai/VERIFICATION.md`](./VERIFICATION.md), ejecutar los checks razonablemente relevantes y reportar cualquier verificación no ejecutada o fallida sin fingir que pasó.
248: 
249: ## Alcance de las protecciones
250: 
251: El inventario de MCP del lanzador se fija al iniciar el servidor. Mientras esté
252: conectado, no cambiar ni instalar MCP, plugins o configuración de agentes desde
253: otra sesión. Si cambia esa configuración, desconectar/reconectar el MCP `codex`
254: **antes de la siguiente consulta** y repetir `scripts/codex-review-mcp --check`.
255: El lanzador no es un monitor de cambios externos de configuración. El PRIMARY
256: debe mantener esta condición durante un review; no se afirma aislamiento frente
257: a modificaciones concurrentes de terceros.
258: 
259: Las reglas nativas `Read` de `.claude/settings.json` protegen archivos de entorno,
260: secretos y claves también frente a búsquedas y accesos mediante symlinks. La regla
261: `.env.*` incluye `.env.example`: la antigua excepción del hook no podía anular un
262: deny nativo. Las plantillas y secretos se gestionan manualmente; el arranque,
263: lint, tests y build siguen usando su configuración habitual sin cambios.
264: 
265: Los permisos locales se conservan. Un `deny` compartido prevalece sobre cualquier
266: `allow`, y `ask` se evalúa antes que `allow`; los permisos previos de despliegue y
267: SQL no eliminan esos controles. Las reglas se apoyan en la
268: [semántica oficial de permisos de Claude](https://code.claude.com/docs/en/permissions).
269: El subcomando `codex mcp-server` fue **RETIRADO** de la CLI: ausente en 0.155.1, y en
270: 0.153.4 ya avisaba de su deprecación. Ese aviso decía «antes de actualizar hay que repetir
271: el arranque y la comprobación de aislamiento»; se actualizó y nadie lo repitió, así que el
272: MCP quedó muerto sin que nadie lo notara. La interfaz viva es `codex exec`, que acepta las
273: mismas `-c` y `--strict-config`. Al actualizar la CLI: repetir `--check` y un review real.
274: 
275: El aislamiento del reviewer se aplica al wrapper y al servidor MCP configurados aquí. Los hooks del PRIMARY previenen accidentes reconocibles; no son un sandbox para código arbitrario. Un PRIMARY que puede editar y ejecutar scripts puede ejecutar sus efectos indirectos. Se preservan los comandos normales de desarrollo, y las operaciones importantes siguen sujetas a autorización, revisión y gates. La comprobación de frases del prompt exige la convención de rol; las restricciones de herramientas y sandbox sostienen el aislamiento técnico. Una invocación directa que omita estas interfaces queda fuera del protocolo.

FILE CRM-Avance-Corp/docs/plans/supervisores-metas/PLAN.md
1: # Ventas propias de supervisores y meta de equipo
2: 
3: Decisiones de Miguel, 16/10/2026:
4: 
5: - Las ventas propias conservan su atribución personal y aportan a la meta del equipo.
6: - Vigencia desde el periodo comercial octubre de 2026; septiembre y anteriores conservan su comportamiento.
7: - Los supervisores aparecen después de todos los analistas en el ranking.
8: - Claude y JEV apoyan la revisión; Codex es el único escritor.
9: - Copia aislada autorizada: `/private/tmp/avancecorp-supervisores-20261016`, desde main `65764411`.
10: 
11: ## Implementación
12: 
13: La migración modifica únicamente `crm.cumplimiento_metas_fn(date)`, cuya firma, ACL, modo de ejecución y claves JSON se conservan. Desde octubre, un supervisor activo recibe en `fuera_ranking` únicamente su propia fila. El filtro por UUID se aplica antes de unir nombres y membresías. Gerencia, Directorio y Coordinación conservan exactamente su respuesta anterior. Analistas no adquieren esta capacidad.
14: 
15: En meses cerrados se filtra la fotografía existente de `periodos_cerrados.cobertura.fuera_ranking` por identidad, rol y motivo. No se recalcula ni se escribe el sello. Sin actividad no se fabrica una fila, igual que en el contrato histórico. La identidad comercial sigue siendo la de la venta, no la del usuario que la cargó.
16: 
17: El adaptador del frontend separa para presentación las filas de supervisor desde octubre, sin añadir ninguna clave a la RPC ni modificar su esquema estricto. El cumplimiento del equipo añade capital y contratos propios por categoría y moneda. Conserva el objetivo de conversión de los analistas; la conversión real sigue viniendo de su RPC canónica. El agregado de empresa continúa sumando las mismas filas exactamente una vez.
18: 
19: Una sección final «Ventas propias de supervisores» muestra la atribución personal y el aporte al equipo, después del ranking de analistas y de los demás responsables externos. No cambia puestos ni desempates de analistas. No se crean metas individuales nuevas: Miguel no fijó una meta personal de supervisor.
20: 
21: ## Compatibilidad y límites
22: 
23: - El servidor y el cliente anterior siguen compartiendo el mismo contrato. El comportamiento visual y la suma al equipo requieren publicar también el cliente actualizado.
24: - Se conserva la pertenencia mensual ya publicada. No se reatribuyen ventas ni se reescriben metas o cambios históricos de rol. En la consulta agregada productiva previa, ninguno de los cuatro supervisores activos tenía una meta de analista en octubre.
25: - Un supervisor sin analistas puede ver su venta con meta cero. Sin actividad se conserva el estado vacío.
26: - CodeGraph fue intentado primero y falló con `unable to open database file`; se usaron consultas y lecturas puntuales. No se reindexó.
27: - No se modifican tablas, triggers, policies, grants ni tipos de retorno. No requiere regenerar `database.types.ts`.
28: 
29: ## Evidencia
30: 
31: - Función productiva leída sin mutaciones: `md5(prosrc)=be18b2feac623d18db695830d70e2a2e`.
32: - Migración y reversa protegidas por huellas; ambas rechazan una definición distinta a la revisada.
33: - Banco PostgreSQL exclusivo vacío, con fixtures sintéticos, triggers activos y llamadas como `authenticated`. Todas las escrituras y DDL se revierten al finalizar.
34: - Matriz de nueve actores en septiembre, octubre y noviembre sellado, antes/después: paridad JSON global y de analistas, aislamiento personal y histórico.
35: - Pruebas unitarias del corte, contratos/capital, meta de conversión, total empresa, ausencia de metas personales y orden final; E2E local en Docker de supervisión, gerencia y regresiones históricas.
36: 
37: Estado: implementado y verificado localmente; pendiente de promoción autorizada. Ver [LEEME del ensayo](../../../supabase/scripts/supervisores-metas/LEEME.md) y [verificación](VERIFICACION.md).

FILE CRM-Avance-Corp/supabase/migrations/20261016180000_crm_supervisores_ventas_equipo.sql
1: -- Ventas propias de supervisores: atribución personal y aporte a su equipo.
2: -- Decisión de Miguel, 16/10/2026. Vigencia desde octubre de 2026.
3: -- Conserva firma, claves JSON y ACL. No cambia public, RLS, metas publicadas,
4: -- fórmula de conversión ni sellos. Reutiliza los núcleos y la foto existentes.
5: begin;
6: set local lock_timeout = '5s';
7: 
8: do $preflight$ begin
9:   if (select md5(p.prosrc) from pg_catalog.pg_proc p
10:       where p.oid = to_regprocedure('crm.cumplimiento_metas_fn(date)'))
11:         is distinct from 'be18b2feac623d18db695830d70e2a2e' then
12:     raise exception 'PREFLIGHT: cambió el cumplimiento revisado';
13:   end if;
14: end $preflight$;
15: 
16: CREATE OR REPLACE FUNCTION crm.cumplimiento_metas_fn(p_periodo date)
17:  RETURNS jsonb
18:  LANGUAGE plpgsql
19:  STABLE SECURITY DEFINER
20:  SET search_path TO ''
21: AS $function$
22: declare
23:   v_uid uuid := (select auth.uid());
24:   v_rol text := private.rol_crm(v_uid);
25:   v_lector boolean := private.es_lector_global() or private.es_coordinador_reportes();
26:   v_base jsonb;
27:   v_vendedores jsonb;
28:   v_fuera_ranking jsonb := '[]'::jsonb;
29:   v_cerrado boolean;
30:   v_global boolean;
31:   v_propia_visible boolean := false;
32:   v_periodo_id uuid;
33:   v_ini timestamptz;
34:   v_fin timestamptz;
35: begin
36:   if v_uid is null or (v_rol is null and not v_lector) then
37:     raise exception 'No autorizado' using errcode = '42501';
38:   end if;
39: 
40:   v_base := crm.cumplimiento_metas_sin_cartera_fn(p_periodo);
41:   v_cerrado := coalesce((v_base #>> '{cierre,cerrado}')::boolean, false);
42: 
43:   -- Desde octubre de 2026, Supervisión recibe únicamente su producción
44:   -- personal. Global conserva EXACTAMENTE el contrato anterior. En meses
45:   -- cerrados manda la foto: no se reconstruye con roles o ventas de hoy.
46:   v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
47:   v_propia_visible := p_periodo >= date '2026-10-01'
48:     and coalesce(v_rol = 'supervisor', false);
49:   if (v_global or v_propia_visible) and v_cerrado then
50:     select coalesce(pc.cobertura->'fuera_ranking', '[]'::jsonb)
51:       into v_fuera_ranking
52:     from crm.periodos_cerrados pc
53:     where pc.periodo = p_periodo;
54:     if not v_global then
55:       select coalesce(jsonb_agg(e.value order by e.ord), '[]'::jsonb)
56:         into v_fuera_ranking
57:       from jsonb_array_elements(v_fuera_ranking) with ordinality e(value, ord)
58:       where e.value->>'persona_id' = v_uid::text
59:         and e.value->>'rol_crm' = 'supervisor'
60:         and e.value->>'motivo' = 'supervisor';
61:     end if;
62:   elsif v_global or v_propia_visible then
63:     v_ini := p_periodo::timestamp at time zone 'America/Lima';
64:     v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
65:     select mp.id into v_periodo_id
66:     from crm.meta_periodos mp
67:     where mp.periodo = p_periodo
68:     order by mp.revision desc
69:     limit 1;
70: 
71:     with conv as materialized (
72:       -- La MISMA pieza del nucleo que la oficial y que la #8. Solo quien aparece
73:       -- en el nucleo del mes: una deuda sin actividad no crea fila aqui.
74:       select n.*
75:       from private.conversion_neta_por_vendedor(p_periodo, true, '{}'::uuid[]) n
76:       where n.en_nucleo
77:     ), nombrados as materialized (
78:       -- A quien la oficial NOMBRA en `responsables` le publica el NETO; al resto
79:       -- lo suma BRUTO y sin nombre en `cobertura.fuera_de_roster`. Aqui se
80:       -- publica, para cada persona, lo mismo que la oficial (C2, auditoria 21/09).
81:       select r.vendedor_id
82:       from private.roster_conversion_mensual(p_periodo, true, '{}'::uuid[]) r
83:     ), prod as materialized (
84:       select r.*
85:       from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
86:     ), car as materialized (
87:       select m.* from private.metricas_cartera_por_vendedor(p_periodo) m
88:   ), personas_fuente as (
89:     select c.analista_id as persona_id from conv c where c.analista_id is not null
90:       union
91:       select p.vendedor_id from prod p where p.vendedor_id is not null
92:       union
93:       select c.vendedor_id from car c where c.vendedor_id is not null
94:     ), personas as (
95:       -- Los núcleos traen el universo. Recortar ANTES de los joins: el conjunto
96:       -- dentro solo contiene los analistas visibles para el actor actual.
97:       select p.persona_id from personas_fuente p
98:       where v_global or (v_propia_visible and p.persona_id = v_uid)
99:     ), dentro as (
100:       select (e.value->>'vendedor_id')::uuid as persona_id
101:       from jsonb_array_elements(coalesce(v_base->'vendedores', '[]'::jsonb)) e
102:     ), fuera as (
103:       select
104:         p.persona_id,
105:         coalesce(nullif(btrim(pf.nombre_completo), ''),
106:                  '(sin nombre · ' || left(p.persona_id::text, 8) || ')') as nombre,
107:         coalesce(eq.rol_crm, 'fuera_equipo') as rol_crm,
108:         case
109:           when eq.rol_crm = 'vendedor' and sup.perfil_id is not null
110:             then 'analista_sin_meta'
111:           when eq.rol_crm = 'vendedor' then 'analista_sin_supervisor'
112:           when eq.rol_crm = 'supervisor' then 'supervisor'
113:           when eq.rol_crm = 'gerencia' then 'gerencia'
114:           else 'fuera_estructura'
115:         end as motivo
116:       from personas p
117:       left join crm.equipo eq on eq.perfil_id = p.persona_id
118:       left join crm.equipo sup
119:         on sup.perfil_id = eq.supervisor_id and sup.rol_crm = 'supervisor'
120:       left join public.perfiles pf on pf.id = p.persona_id
121:       where not exists (
122:         select 1 from dentro d where d.persona_id = p.persona_id
123:       )
124:     )
125:     select coalesce(jsonb_agg(jsonb_build_object(
126:       'persona_id', f.persona_id,
127:       'nombre', f.nombre,
128:       'rol_crm', f.rol_crm,
129:       'motivo', f.motivo,
130:       'conversion', case when cv.analista_id is null then null else jsonb_build_object(
131:         'divisor', coalesce(cv.divisor, 0),
132:         'divisor_aproximado', coalesce(cv.divisor_aproximado, 0),
133:         'divisor_por_motivo', coalesce(cv.divisor_por_motivo, '{}'::jsonb),
134:         'cierres_no_referidos', coalesce(cv.cierres_no_referidos, 0),
135:         'cierres_referidos', coalesce(cv.cierres_referidos, 0),
136:         'cierres_de_arrastre', coalesce(cv.cierres_de_arrastre, 0),
137:         'referidos_recibidos', coalesce(cv.referidos_recibidos, 0),
138:         'numerador', case
139:           when exists (select 1 from nombrados nm where nm.vendedor_id = f.persona_id)
140:             then coalesce(cv.numerador, 0)
141:           else coalesce(cv.numerador_bruto, 0) end
142:       ) end,
143:       'detalles', det.detalles,
144:       'cartera', jsonb_build_object(
145:         'conversiones_clientes', coalesce(car.conversiones_clientes, 0),
146:         'conversiones_renovacion', coalesce(car.conversiones_renovacion, 0),
147:         'conversiones_upgrade', coalesce(car.conversiones_upgrade, 0),
148:         'operaciones_renovacion', coalesce(car.operaciones_renovacion, 0),
149:         'operaciones_upgrade', coalesce(car.operaciones_upgrade, 0),
150:         'capital_renovado_pen', coalesce(car.capital_renovado_pen, 0),
151:         'capital_renovado_usd', coalesce(car.capital_renovado_usd, 0),
152:         'capital_adicional_pen', coalesce(car.capital_adicional_pen, 0),
153:         'capital_adicional_usd', coalesce(car.capital_adicional_usd, 0),
154:         'renovaciones_sin_desglose', coalesce(car.renovaciones_sin_desglose, 0)
155:       )
156:     ) order by f.nombre, f.persona_id), '[]'::jsonb)
157:       into v_fuera_ranking
158:     from fuera f
159:     left join conv cv on cv.analista_id = f.persona_id
160:     left join car on car.vendedor_id = f.persona_id
161:     left join lateral (
162:       select jsonb_agg(jsonb_build_object(
163:         'categoria', d.categoria,
164:         'moneda', d.moneda,
165:         'capital_objetivo', 0,
166:         'capital_real', coalesce(pr.capital_real, 0),
167:         'capital_cumplimiento_pct', null,
168:         'contratos_objetivo', 0,
169:         'contratos_real', coalesce(pr.contratos_real, 0),
170:         'contratos_cumplimiento_pct', null,
171:         'capital_ajuste', 0,
172:         'contratos_ajuste', 0
173:       ) order by array_position(
174:         array['nuevo','renovacion','upgrade'], d.categoria
175:       ), d.moneda) as detalles
176:       from (values
177:         ('nuevo'::text, 'PEN'::text), ('nuevo', 'USD'),
178:         ('renovacion', 'PEN'), ('renovacion', 'USD'),
179:         ('upgrade', 'PEN'), ('upgrade', 'USD')
180:       ) d(categoria, moneda)
181:       left join prod pr on pr.vendedor_id = f.persona_id
182:         and pr.categoria = d.categoria and pr.moneda = d.moneda
183:     ) det on true;
184:   end if;
185: 
186:   with m as materialized (
187:     select x.*
188:     from private.metricas_cartera_por_vendedor(p_periodo) x
189:     where not v_cerrado
190:     union all
191:     select
192:       f.vendedor_id,
193:       (f.cartera->>'conversiones_clientes')::int,
194:       (f.cartera->>'conversiones_renovacion')::int,
195:       (f.cartera->>'conversiones_upgrade')::int,
196:       (f.cartera->>'operaciones_renovacion')::int,
197:       (f.cartera->>'operaciones_upgrade')::int,
198:       (f.cartera->>'capital_renovado_pen')::numeric,
199:       (f.cartera->>'capital_renovado_usd')::numeric,
200:       (f.cartera->>'capital_adicional_pen')::numeric,
201:       (f.cartera->>'capital_adicional_usd')::numeric,
202:       (f.cartera->>'renovaciones_sin_desglose')::int
203:     from private.cierre_mes_reportes_visible(p_periodo, v_uid) f
204:     where v_cerrado
205:   )
206:   select coalesce(jsonb_agg(
207:     jsonb_set(
208:       e.value,
209:       '{convertidos}',
210:       to_jsonb(coalesce((e.value->>'convertidos')::int, 0)
211:                + coalesce(m.conversiones_clientes, 0)),
212:       true
213:     ) order by e.ord
214:   ), '[]'::jsonb) into v_vendedores
215:   from jsonb_array_elements(coalesce(v_base->'vendedores','[]'::jsonb))
216:        with ordinality e(value, ord)
217:   left join m on m.vendedor_id = (e.value->>'vendedor_id')::uuid;
218: 
219:   v_base := jsonb_set(v_base, '{vendedores}', v_vendedores, true);
220:   return jsonb_set(v_base, '{fuera_ranking}', v_fuera_ranking, true);
221: end;
222: $function$;
223: 
224: commit;

FILE CRM-Avance-Corp/supabase/scripts/supervisores-metas/prueba.sql
1: create function pg_temp.leer(p_actor text,p_mes date) returns jsonb language plpgsql as $f$
2: begin
3:   perform pg_temp.sesion(p_actor);
4:   return crm.cumplimiento_metas_fn(p_mes);
5: exception when insufficient_privilege then return '{"denegado":true}'::jsonb;
6: end $f$;
7: create temporary table lecturas(actor text,mes date,fase text,valor jsonb);
8: grant all on lecturas to authenticated;
9: create function pg_temp.fotografiar(p_fase text) returns void language plpgsql as $f$
10: declare a record; m date; begin
11:   for a in select clase from actores where clase<>'cliente' loop
12:     foreach m in array array[date '2026-09-01',date '2026-10-01',date '2026-11-01'] loop
13:       insert into lecturas values(a.clase,m,p_fase,pg_temp.leer(a.clase,m));
14:     end loop;
15:   end loop;
16: end $f$;
17: 
18: -- La foto sintética conserva la producción de octubre bajo noviembre.
19: -- Noviembre no tiene operaciones vivas: recalcularlo perdería estas ventas.
20: set local role authenticated;
21: select pg_temp.sesion('gerencia');
22: create temporary table foto_cerrada as select crm.cumplimiento_metas_fn('2026-10-01')->'fuera_ranking' as filas;
23: reset role;
24: select set_config('crm.op_privilegiada','on',true);
25: insert into crm.periodos_cerrados(periodo,ponderacion_referido,meta_revision,cobertura)
26: select '2026-11-01',0.15,1,jsonb_build_object('fuera_ranking',filas) from foto_cerrada;
27: select set_config('crm.op_privilegiada','',true);
28: create temporary table contratos_antes as select id,analista_cierre_id,capital,moneda from public.contratos;
29: create temporary table cooperativas_antes as select * from crm.cierres_externos;
30: create temporary table acl_antes as select proacl,prosecdef,provolatile,proconfig
31:   from pg_proc where oid='crm.cumplimiento_metas_fn(date)'::regprocedure;
32: create temporary table sello_antes as select * from crm.periodos_cerrados;
33: set local role authenticated;
34: select pg_temp.fotografiar('antes');
35: reset role;
36: 
37: -- MIGRACION
38: 
39: set local role authenticated;
40: select pg_temp.fotografiar('despues');
41: do $prueba$ declare r record; esperado jsonb; id_propio text; begin
42:   perform pg_temp.exigir((select count(*) from lecturas)=54,'matriz completa: nueve actores, tres meses, antes y después');
43:   for r in select a.actor,a.mes,a.valor as antes,d.valor as despues
44:     from lecturas a join lecturas d using(actor,mes)
45:     where a.fase='antes' and d.fase='despues' loop
46:     if r.actor in ('gerencia','directorio','coordinador','vend1','vend2') or r.mes=date '2026-09-01' then
47:       perform pg_temp.exigir(r.antes=r.despues,'paridad JSON exacta: '||r.actor||' / '||r.mes);
48:     else
49:       select id::text into id_propio from actores where clase=r.actor;
50:       select coalesce(jsonb_agg(e.value order by e.ord),'[]'::jsonb) into esperado
51:       from lecturas l cross join lateral jsonb_array_elements(l.valor->'fuera_ranking')
52:         with ordinality e(value,ord)
53:       where l.actor='gerencia' and l.mes=r.mes and l.fase='antes'
54:         and e.value->>'persona_id'=id_propio and e.value->>'rol_crm'='supervisor';
55:       perform pg_temp.exigir(r.despues->'fuera_ranking'=esperado,'solo producción propia, sin equipo ajeno: '||r.actor||' / '||r.mes);
56:       perform pg_temp.exigir(r.antes-'fuera_ranking'=r.despues-'fuera_ranking','resto del contrato intacto: '||r.actor||' / '||r.mes);
57:       perform pg_temp.exigir(jsonb_array_length(r.despues->'fuera_ranking')=case when r.actor='sin_ventas' then 0 else 1 end,
58:         'atribución única o vacío sin ventas: '||r.actor||' / '||r.mes);
59:     end if;
60:   end loop;
61:   perform pg_temp.sesion('sup1');
62:   perform pg_temp.exigir((select sum((d->>'capital_real')::numeric)
63:     from jsonb_array_elements(crm.cumplimiento_metas_fn('2026-10-01')->'fuera_ranking') f
64:     cross join lateral jsonb_array_elements(f->'detalles') d where d->>'moneda'='PEN')=30000,
65:     'capital propio PEN conserva al autor comercial');
66:   perform pg_temp.exigir((select sum((d->>'capital_real')::numeric)
67:     from jsonb_array_elements(crm.cumplimiento_metas_fn('2026-11-01')->'fuera_ranking') f
68:     cross join lateral jsonb_array_elements(f->'detalles') d where d->>'moneda'='USD')=4000,
69:     'mes sellado conserva USD de la foto sin recalcular noviembre');
70:   perform pg_temp.exigir(pg_temp.leer('cliente','2026-10-01')='{"denegado":true}'::jsonb,'cliente sin rol CRM rechazado');
71:   perform pg_temp.exigir(pg_temp.leer('desconocido','2026-10-01')='{"denegado":true}'::jsonb,'sesión sin identidad rechazada');
72:   perform pg_temp.sesion('sup2');
73:   perform pg_temp.exigir((select sum((d->>'capital_real')::numeric)
74:     from jsonb_array_elements(crm.cumplimiento_metas_fn('2026-10-01')->'fuera_ranking') f
75:     cross join lateral jsonb_array_elements(f->'detalles') d where d->>'moneda'='PEN')=62000,
76:     'contrato y cooperativa propios suman una vez cada uno');
77: end $prueba$;
78: reset role;
79: savepoint perfil_activo;
80: select set_config('crm.op_privilegiada','on',true);
81: update public.perfiles set activo=false where id=(select id from actores where clase='sin_equipo');
82: set local role authenticated;
83: select pg_temp.exigir(pg_temp.leer('sin_equipo','2026-10-01')='{"denegado":true}'::jsonb,'perfil inactivo revoca la lectura propia');
84: rollback to savepoint perfil_activo;
85: savepoint cambio_rol;
86: -- Transición sintética como consola, con el par Portal/CRM coherente al final.
87: select pg_temp.sesion('desconocido');
88: select set_config('crm.op_privilegiada','on',true);
89: update public.perfiles set rol='analista' where id=(select id from actores where clase='sin_equipo');
90: update crm.equipo set rol_crm='vendedor',supervisor_id=(select id from actores where clase='sup1')
91:   where perfil_id=(select id from actores where clase='sin_equipo');
92: set local role authenticated;
93: select pg_temp.exigir(pg_temp.leer('sin_equipo','2026-10-01')->'fuera_ranking'='[]'::jsonb,
94:   'cambio a analista retira la capacidad de supervisión');
95: select pg_temp.exigir(pg_temp.leer('sin_equipo','2026-11-01')->'fuera_ranking'='[]'::jsonb,
96:   'cambio de rol tampoco hereda acceso a fotos de supervisión');
97: rollback to savepoint cambio_rol;
98: select set_config('crm.op_privilegiada','on',true);
99: update crm.equipo set activo=false where perfil_id=(select id from actores where clase='sin_ventas');
100: select set_config('crm.op_privilegiada','',true);
101: set local role authenticated;
102: select pg_temp.exigir(pg_temp.leer('sin_ventas','2026-10-01')='{"denegado":true}'::jsonb,'baja CRM revoca las ventas propias con el mismo actor');
103: reset role;
104: select pg_temp.exigir((select row(proacl,prosecdef,provolatile,proconfig) from acl_antes)=
105:   (select row(proacl,prosecdef,provolatile,proconfig) from pg_proc where oid='crm.cumplimiento_metas_fn(date)'::regprocedure),
106:   'ACL, security definer, estabilidad y search_path intactos');
107: select pg_temp.exigir(not exists((select * from sello_antes except select * from crm.periodos_cerrados)
108:   union all (select * from crm.periodos_cerrados except select * from sello_antes)),'ningún sello modificado');
109: select pg_temp.exigir(not exists((select * from contratos_antes except select id,analista_cierre_id,capital,moneda from public.contratos)
110:   union all (select id,analista_cierre_id,capital,moneda from public.contratos except select * from contratos_antes)),
111:   'ninguna venta duplicada, reasignada ni modificada');
112: select pg_temp.exigir(not exists((select * from cooperativas_antes except select * from crm.cierres_externos)
113:   union all (select * from crm.cierres_externos except select * from cooperativas_antes)),
114:   'cooperativas conservan atribución, monto e identidad');
115: 
116: -- REVERSA
117: 
118: set local role authenticated;
119: select pg_temp.exigir(pg_temp.leer('sup1','2026-10-01')=
120:   (select valor from lecturas where actor='sup1' and mes='2026-10-01' and fase='antes'),
121:   'reversa recupera exactamente el comportamiento anterior');
122: reset role;
123: 
124: -- REAPLICACION
125: 
126: set local role authenticated;
127: select pg_temp.exigir(pg_temp.leer('sup1','2026-10-01')=
128:   (select valor from lecturas where actor='sup1' and mes='2026-10-01' and fase='despues'),
129:   'reaplicación recupera exactamente las ventas propias');
130: reset role;

FILE CRM-Avance-Corp/supabase/scripts/supervisores-metas/semilla.sql
1: -- Solo banco local exclusivo y vacío. Datos ficticios; triggers y RLS encendidos.
2: do $guardia$ begin
3:   if current_database() <> 'supervisores_metas_20261016'
4:      or current_user <> 'postgres'
5:      or current_setting('session_replication_role') <> 'origin'
6:      or exists (select 1 from crm.equipo)
7:      or exists (select 1 from public.contratos) then
8:     raise exception 'La prueba requiere su banco sintético exclusivo y vacío';
9:   end if;
10: end $guardia$;
11: 
12: insert into crm.productos_inversion(codigo,es_legacy,permite_altas_legacy,estado,archivado_en)
13: values('HISTORICO-SIN-CATALOGO',true,true,'archivado',now());
14: insert into crm.sla_politicas(version,vigente_desde,zona_horaria,tipo_reloj,primera_gestion_minutos,primer_contacto_minutos)
15: values(1,'2000-01-01','America/Lima','corrido',60,120);
16: insert into crm.sla_politica_etapas(politica_id,etapa,maximo_minutos)
17: select id,'nuevo',120 from crm.sla_politicas;
18: insert into crm.conversion_pesos(vigente_desde,peso_referido,peso_renovacion,nota)
19: values('2000-01-01',0.15,0.15,'Prueba sintética de supervisores');
20: 
21: create temporary table actores(clase text primary key, id uuid not null default gen_random_uuid());
22: insert into actores(clase) values
23:   ('gerencia'),('directorio'),('coordinador'),('sup1'),('sup2'),('sin_equipo'),('sin_ventas'),('vend1'),('vend2'),('cliente');
24: grant select on actores to authenticated;
25: 
26: select set_config('crm.op_privilegiada','on',true);
27: insert into auth.users(id,email) select id,id::text||'@supervisores.test' from actores;
28: insert into public.perfiles(id,nombre_completo,correo,rol,activo,tipo_documento,
29:   debe_cambiar_password,titular_distinto,titular_distinto_usd)
30: select id,'PRUEBA '||clase,id::text||'@supervisores.test',
31:   case when clase='cliente' then 'cliente' when clase='directorio' then 'directorio'
32:     when clase in ('vend1','vend2') then 'analista' else 'comercial' end,
33:   true,'DNI',false,false,false from actores;
34: insert into crm.equipo(perfil_id,rol_crm,activo)
35: select id,case when clase in ('sup1','sup2','sin_equipo','sin_ventas') then 'supervisor' else clase end,true
36: from actores where clase in ('gerencia','directorio','coordinador','sup1','sup2','sin_equipo','sin_ventas');
37: insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
38: select a.id,'vendedor',s.id,true from actores a join actores s
39:   on s.clase=case a.clase when 'vend1' then 'sup1' when 'vend2' then 'sup2' end
40: where a.clase in ('vend1','vend2');
41: 
42: -- El autor de la carga es Gerencia; el dueño comercial de cada venta es distinto.
43: insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,tasa_anual,
44:   modalidad,tipo_interes,fecha_inicio,fecha_vencimiento,estado,categoria,creado_por,analista_cierre_id,es_demo)
45: select gen_random_uuid(),'SUP-TEST-'||gen_random_uuid(),c.id,v.monto,v.moneda,15,
46:   'mensual','simple',mes+4,(mes+4+interval '12 months')::date,'activo','nuevo',g.id,a.id,false
47: from (values ('vend1',10000::numeric,'PEN'),('vend2',20000,'PEN'),('sup1',30000,'PEN'),
48:   ('sup1',4000,'USD'),('sup2',50000,'PEN'),('sin_equipo',60000,'PEN')) v(clase,monto,moneda)
49: join actores a on a.clase=v.clase
50: cross join (values (date '2026-09-01'),(date '2026-10-01')) m(mes)
51: cross join actores c cross join actores g where c.clase='cliente' and g.clase='gerencia';
52: create temporary table leads_coop(mes date, id uuid default gen_random_uuid());
53: insert into leads_coop(mes) values('2026-09-01'),('2026-10-01');
54: insert into crm.leads(id,nombre_completo,telefono,origen,vendedor_id,creado_por,monto_estimado,categoria_interes)
55: select l.id,'PRUEBA COOPERATIVA','9000000'||lpad(extract(month from l.mes)::text,2,'0'),'referido',a.id,g.id,12000,'nuevo'
56: from leads_coop l cross join actores a cross join actores g
57: where a.clase='sup2' and g.clase='gerencia';
58: insert into crm.cierres_externos(lead_id,cooperativa,monto,moneda,documento_tipo,documento,
59:   nombre_completo,numero_transaccion,vendedor_id,creado_por,creado_en,
60:   fecha_comercial,fecha_imputacion)
61: select l.id,'qorilazo',12000,'PEN','DNI','00000001','CLIENTE SINTETICO',
62:   'SUP-TEST-'||gen_random_uuid(),a.id,g.id,
63:   (mes+5)::timestamp at time zone 'America/Lima',mes+5,mes+5
64: from actores a cross join actores g cross join leads_coop l
65: where a.clase='sup2' and g.clase='gerencia';
66: select set_config('crm.op_privilegiada','',true);
67: 
68: create function pg_temp.sesion(p_clase text) returns void language sql as $f$
69:   select set_config('request.jwt.claim.sub',coalesce((select id::text from actores where clase=p_clase),''),true);
70:   select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from actores where clase=p_clase),'role','authenticated')::text,true);
71: $f$;
72: create function pg_temp.exigir(p_ok boolean,p_mensaje text) returns void language plpgsql as $f$
73: begin
74:   if p_ok is not true then raise exception 'FAIL: %',p_mensaje; end if;
75:   raise notice 'PASS: %',p_mensaje;
76: end $f$;
77: 
78: set local role authenticated;
79: select pg_temp.sesion('gerencia');
80: do $metas$ declare mes date; payload jsonb; begin
81:   select jsonb_object_agg(a.id::text,jsonb_build_object('conversion_objetivo',15,'detalles',d.valor))
82:   into payload from actores a cross join lateral (
83:     select jsonb_agg(jsonb_build_object('categoria',categoria,'moneda',moneda,
84:       'capital_objetivo',case when categoria='nuevo' and moneda='PEN' then 1000 else 0 end,
85:       'contratos_objetivo',0)) as valor
86:     from (values('nuevo'),('renovacion'),('upgrade')) c(categoria)
87:       cross join (values('PEN'),('USD')) m(moneda)
88:   ) d where a.clase in ('vend1','vend2');
89:   foreach mes in array array[date '2026-09-01',date '2026-10-01'] loop
90:     perform crm.publicar_metas_vendedores(mes,0,payload);
91:   end loop;
92: end $metas$;
93: reset role;

FILE CRM-Avance-Corp/docs/plans/supervisores-metas/jev-contexto.json
1: {
2:   "consulta": "¿Qué extractos explican cómo incorporar ventas propias de supervisores a la meta del equipo, preservando atribución, visibilidad y meses cerrados, y ubicarlos al final del ranking?",
3:   "corte": 2,
4:   "extractos": [
5:     {
6:       "de": "app/src/lib/objetivos.ts:660-752",
7:       "puntos": 2.14,
8:       "confianza": 0.72
9:     },
10:     {
11:       "de": "supabase/scripts/supervisores-metas/vivo/crm.cumplimiento_metas_fn.sql:1-200",
12:       "puntos": 2,
13:       "confianza": 0.69
14:     },
15:     {
16:       "de": "app/src/screens/hoy/ranking-vendedores.tsx:574-650",
17:       "puntos": 1.82,
18:       "confianza": 0.61
19:     },
20:     {
21:       "de": "supabase/migrations/20261015000852_crm_plazo_carga_mes.sql:1250-1450",
22:       "puntos": 1.73,
23:       "confianza": 0.6
24:     },
25:     {
26:       "de": "app/src/lib/objetivos.ts:346-375",
27:       "puntos": 1.66,
28:       "confianza": 0.64
29:     },
30:     {
31:       "de": "supabase/migrations/20260807203757_crm_metas_sla_versionados.sql:35-50",
32:       "puntos": 1.55,
33:       "confianza": 0.54
34:     },
35:     {
36:       "de": "app/src/screens/hoy/ranking-vendedores.tsx:708-773",
37:       "puntos": 1.33,
38:       "confianza": 0.32
39:     },
40:     {
41:       "de": "app/src/screens/hoy/datos-supervisor.ts:164-183",
42:       "puntos": 0.84,
43:       "confianza": 0.17
44:     }
45:   ]
46: }

private.rol_crm(p_perfil_id uuid): stable SECURITY DEFINER, search_path ''. Joins crm.equipo e to public.perfiles p; requires BOTH activo is true. Allowed roles vendedor, supervisor, gerencia, coordinador, directorio. Directorio must match both systems; portal superadmin requires CRM gerencia. Existing authorization gate is unchanged.


FILE CRM-Avance-Corp/app/src/lib/objetivos.ts L294-375
294: })
295: 
296: // Produccion empresarial que existe y debe cuadrar en Gerencia, pero cuyo
297: // responsable no puede competir como analista (p. ej. un supervisor). Es una
298: // clave opcional para que este bundle pueda salir antes que la migracion.
299: const ConversionFueraRankingSchema = v.strictObject({
300:   divisor: EnteroNoNegativoRpcSchema,
301:   divisor_aproximado: EnteroNoNegativoRpcSchema,
302:   divisor_por_motivo: v.record(v.string(), EnteroNoNegativoRpcSchema),
303:   cierres_no_referidos: EnteroNoNegativoRpcSchema,
304:   cierres_referidos: EnteroNoNegativoRpcSchema,
305:   cierres_de_arrastre: EnteroNoNegativoRpcSchema,
306:   referidos_recibidos: EnteroNoNegativoRpcSchema,
307:   numerador: v.pipe(NumeroRpcSchema, v.minValue(0)),
308: })
309: 
310: const CarteraFueraRankingSchema = v.strictObject({
311:   conversiones_clientes: EnteroNoNegativoRpcSchema,
312:   conversiones_renovacion: EnteroNoNegativoRpcSchema,
313:   conversiones_upgrade: EnteroNoNegativoRpcSchema,
314:   operaciones_renovacion: EnteroNoNegativoRpcSchema,
315:   operaciones_upgrade: EnteroNoNegativoRpcSchema,
316:   capital_renovado_pen: v.pipe(NumeroRpcSchema, v.minValue(0)),
317:   capital_renovado_usd: v.pipe(NumeroRpcSchema, v.minValue(0)),
318:   capital_adicional_pen: v.pipe(NumeroRpcSchema, v.minValue(0)),
319:   capital_adicional_usd: v.pipe(NumeroRpcSchema, v.minValue(0)),
320:   renovaciones_sin_desglose: EnteroNoNegativoRpcSchema,
321: })
322: 
323: const ProduccionFueraRankingSchema = v.strictObject({
324:   persona_id: UuidSchema,
325:   nombre: TextoNoVacioSchema,
326:   rol_crm: v.picklist([
327:     'vendedor',
328:     'supervisor',
329:     'gerencia',
330:     'coordinador',
331:     'directorio',
332:     'fuera_equipo',
333:   ]),
334:   motivo: v.picklist([
335:     'analista_sin_meta',
336:     'analista_sin_supervisor',
337:     'supervisor',
338:     'gerencia',
339:     'fuera_estructura',
340:   ]),
341:   conversion: v.nullable(ConversionFueraRankingSchema),
342:   detalles: DetallesCumplimientoSchema,
343:   cartera: CarteraFueraRankingSchema,
344: })
345: 
346: export const CumplimientoMetasSchema = v.strictObject({
347:   // ── EL CONTRATO DE LA UNIFICACIÓN (Ola 1 de las doce puertas) ─────────────
348:   // Dicen DE DÓNDE salió la cifra. Opcionales a propósito: el front entra
349:   // PRIMERO (regla de la casa), y mientras el servidor no las emita,
350:   // `undefined` significa «servidor previo», no «no se sabe».
351:   es_mes_calendario: v.optional(v.boolean()),
352:   fuente: v.optional(v.picklist(['mensual', 'rango_vivo'])),
353:   sellado: v.optional(v.nullable(v.boolean())),
354:   ajuste_aplicado: v.optional(v.boolean()),
355:   mensual_comparada: v.optional(v.boolean()),
356:   paridad_mensual: v.optional(v.nullable(v.number())),
357:   version: v.literal(1),
358:   periodo: FechaSchema,
359:   revision: EnteroNoNegativoRpcSchema,
360:   publicada_en: v.nullable(FechaHoraSchema),
361:   fuentes_reales: v.strictObject({
362:     capital_y_contratos: v.literal('contratos_confirmados'),
363:     // Tolerar los DOS literales es lo que hace barata la reversión de la
364:     // migración B: el bundle acepta el servidor viejo (`leads_resueltos`) y el
365:     // nuevo (`leads_recibidos_ponderado`) sin redeploy.
366:     conversion: v.picklist(['leads_resueltos', 'leads_recibidos_ponderado']),
367:   }),
368:   // Llega con la migración B; optional por la misma ventana que arriba.
369:   ponderacion_referido: v.optional(v.pipe(NumeroRpcSchema, v.minValue(0), v.maxValue(1))),
370:   // Llega con el cierre de mes (20260815003742), en las dos ramas.
371:   cierre: v.optional(CierreDelMesSchema),
372:   vendedores: v.array(CumplimientoVendedorSchema),
373:   fuera_ranking: v.optional(v.array(ProduccionFueraRankingSchema)),
374: })
375: 

FILE CRM-Avance-Corp/app/src/lib/objetivos.ts L552-771
552: 
553: /**
554:  * Agregado de cumplimientos SIN aritmética de conversión (F3.3 de «Conversión
555:  * única»): la conversión del supervisor/gerencia la SIRVE el servidor
556:  * (conversion_mensual_fn y los motores F2) — el agregado del navegador quedó
557:  * sin pintor desde el 13/08 y recalcularla aquí era otra aritmética paralela.
558:  * Se conservan metas y `reales` de capital/contratos: alimentan las barras de
559:  * capital de cinco pantallas.
560:  */
561: export type CumplimientoAgregado = Omit<
562:   CumplimientoComercial,
563:   'conversionReal' | 'convertidos' | 'resueltos' | 'numerador'
564: >
565: 
566: export function agregarCumplimientos(
567:   items: Iterable<CumplimientoComercial>,
568: ): CumplimientoAgregado | null {
569:   const filas = Array.from(items)
570:   if (filas.length === 0) return null
571: 
572:   const metas = agregarObjetivos(filas)
573:   const reales = new Map(CLAVES_DIMENSION.map((clave) => [clave, {
574:     capitalReal: 0,
575:     contratosReal: 0,
576:     capitalAjuste: 0,
577:     contratosAjuste: 0,
578:   }]))
579:   const tieneAjuste = filas.some((fila) => fila.ajuste != null)
580:   const ajuste = filas.reduce<AjusteCumplimiento>((total, fila) => ({
581:     pendiente: total.pendiente + (fila.ajuste?.pendiente ?? 0),
582:     aplicado: total.aplicado + (fila.ajuste?.aplicado ?? 0),
583:     aplicadoPen: total.aplicadoPen + (fila.ajuste?.aplicadoPen ?? 0),
584:     aplicadoUsd: total.aplicadoUsd + (fila.ajuste?.aplicadoUsd ?? 0),
585:     contratosAplicados: total.contratosAplicados + (fila.ajuste?.contratosAplicados ?? 0),
586:   }), {
587:     pendiente: 0,
588:     aplicado: 0,
589:     aplicadoPen: 0,
590:     aplicadoUsd: 0,
591:     contratosAplicados: 0,
592:   })
593:   for (const fila of filas) {
594:     for (const detalle of fila.detalles) {
595:       const destino = reales.get(`${detalle.categoria}:${detalle.moneda}`)
596:       if (!destino) continue
597:       destino.capitalReal += detalle.capitalReal
598:       destino.contratosReal += detalle.contratosReal
599:       destino.capitalAjuste += detalle.capitalAjuste ?? 0
600:       destino.contratosAjuste += detalle.contratosAjuste ?? 0
601:     }
602:   }
603: 
604:   return {
605:     conversionObjetivo: metas.conversionObjetivo,
606:     ...(tieneAjuste ? { ajuste } : {}),
607:     detalles: metas.detalles.map((meta) => {
608:       const real = reales.get(`${meta.categoria}:${meta.moneda}`) ?? {
609:         capitalReal: 0,
610:         contratosReal: 0,
611:         capitalAjuste: 0,
612:         contratosAjuste: 0,
613:       }
614:       return {
615:         ...meta,
616:         ...real,
617:         capitalCumplimientoPct: meta.capitalObjetivo > 0
618:           ? Math.round((10_000 * real.capitalReal) / meta.capitalObjetivo) / 100
619:           : null,
620:         contratosCumplimientoPct: meta.contratosObjetivo > 0
621:           ? Math.round((10_000 * real.contratosReal) / meta.contratosObjetivo) / 100
622:           : null,
623:       }
624:     }),
625:   }
626: }
627: 
628: /**
629:  * La meta contra la que se mide el mes.
630:  *
631:  * `objetivos` describe el roster VIVO (lo que devuelve `configuracion_metas_fn`,
632:  * jerarquía de hoy) y sirve para EDITAR. El cumplimiento, en cambio, sale del
633:  * snapshot `crm.metas_vendedor` congelado al publicar. Mezclarlos descuadra el
634:  * porcentaje en cuanto alguien se mueve a mitad de mes:
635:  *
636:  *   · si un analista se da de baja, su meta desaparece del denominador pero su
637:  *     producción sigue en el numerador → el avance se INFLA;
638:  *   · si se reasigna de un supervisor a otro, el que lo recibe hereda la meta
639:  *     sin la producción → el avance se HUNDE.
640:  *
641:  * Decisión de negocio (Miguel, 2026-08-10): «si un analista se va, el progreso
642:  * hasta la fecha debe quedar ahí plasmado y contar para el supervisor al que
643:  * pertenecía». Eso es exactamente la FOTO: meta y cierres del mismo snapshot,
644:  * que además es lo que hace auditable un mes ya cerrado.
645:  *
646:  * Funciona porque `CumplimientoDetalle extends ObjetivoDetalle`: el cumplimiento
647:  * ya lleva dentro su propia meta, construida en `agregarCumplimientos` a partir
648:  * de las MISMAS filas que su producción.
649:  */
650: export function metaVigente(
651:   objetivo: ObjetivoComercial,
652:   cumplimiento: CumplimientoAgregado | null,
653: ): ObjetivoComercial {
654:   return cumplimiento ?? objetivo
655: }
656: 
657: /**
658:  * Producción de TODA persona con cierres en el mes: `porVendedor` (quien tiene
659:  * meta) más `fueraRanking` (supervisores o analistas sin meta). «Por empresa»
660:  * la necesita completa: sin la segunda parte decía «falta su foto de
661:  * cumplimiento» de quien sí la tiene. Si un id está en las dos, gana la fila
662:  * con meta.
663:  */
664: export function produccionPorPersona(
665:   cumplimiento: Pick<CumplimientoMetasJerarquico, 'porVendedor'> & { fueraRanking?: readonly ProduccionFueraRanking[]; supervisores?: readonly ProduccionFueraRanking[] } | null | undefined,
666: ): Record<string, Pick<CumplimientoVendedor, 'nombre' | 'detalles'>> | null {
667:   if (cumplimiento == null) return null
668:   const fuera = Object.fromEntries([...(cumplimiento.fueraRanking ?? []), ...(cumplimiento.supervisores ?? [])]
669:     .map((fila) => [fila.personaId, { nombre: fila.nombre, detalles: fila.detalles }]))
670:   return { ...fuera, ...cumplimiento.porVendedor }
671: }
672: 
673: const VENTAS_SUPERVISORES_DESDE = '2026-10-01'
674: 
675: export function cumplimientoDesdeRpc(
676:   respuesta: CumplimientoMetasRpc,
677:   actorId?: string | null,
678: ): CumplimientoMetasJerarquico {
679:   const porVendedor = Object.fromEntries(
680:     respuesta.vendedores.map((fila) => [fila.vendedor_id, cumplimientoDesdeVendedor(fila)]),
681:   )
682:   const filas = Object.values(porVendedor)
683:   const fueraRanking: ProduccionFueraRanking[] = (respuesta.fuera_ranking ?? []).map((fila) => ({
684:     personaId: fila.persona_id,
685:     nombre: fila.nombre,
686:     rolCrm: fila.rol_crm,
687:     motivo: fila.motivo,
688:     conversion: fila.conversion == null ? null : {
689:       divisor: fila.conversion.divisor,
690:       divisorAproximado: fila.conversion.divisor_aproximado,
691:       divisorPorMotivo: fila.conversion.divisor_por_motivo,
692:       cierresNoReferidos: fila.conversion.cierres_no_referidos,
693:       cierresReferidos: fila.conversion.cierres_referidos,
694:       cierresDeArrastre: fila.conversion.cierres_de_arrastre,
695:       referidosRecibidos: fila.conversion.referidos_recibidos,
696:       numerador: fila.conversion.numerador,
697:     },
698:     detalles: fila.detalles.map((detalle) => ({
699:       categoria: detalle.categoria,
700:       moneda: detalle.moneda,
701:       capitalObjetivo: detalle.capital_objetivo,
702:       capitalReal: detalle.capital_real,
703:       capitalCumplimientoPct: detalle.capital_cumplimiento_pct,
704:       contratosObjetivo: detalle.contratos_objetivo,
705:       contratosReal: detalle.contratos_real,
706:       contratosCumplimientoPct: detalle.contratos_cumplimiento_pct,
707:       capitalAjuste: detalle.capital_ajuste ?? 0,
708:       contratosAjuste: detalle.contratos_ajuste ?? 0,
709:     })),
710:     cartera: {
711:       conversionesClientes: fila.cartera.conversiones_clientes,
712:       conversionesRenovacion: fila.cartera.conversiones_renovacion,
713:       conversionesUpgrade: fila.cartera.conversiones_upgrade,
714:       operacionesRenovacion: fila.cartera.operaciones_renovacion,
715:       operacionesUpgrade: fila.cartera.operaciones_upgrade,
716:       capitalRenovadoPen: fila.cartera.capital_renovado_pen,
717:       capitalRenovadoUsd: fila.cartera.capital_renovado_usd,
718:       capitalAdicionalPen: fila.cartera.capital_adicional_pen,
719:       capitalAdicionalUsd: fila.cartera.capital_adicional_usd,
720:       renovacionesSinDesglose: fila.cartera.renovaciones_sin_desglose,
721:     },
722:   }))
723:   // Mismo corte comercial que la puerta SQL; el servidor mantiene fuera_ranking
724:   // compatible para todos los lectores y el adaptador separa su presentación.
725:   const supervisores = respuesta.periodo >= VENTAS_SUPERVISORES_DESDE
726:     ? fueraRanking.filter((fila) => fila.rolCrm === 'supervisor' && fila.motivo === 'supervisor')
727:     : []
728:   const comoCumplimiento = (fila: ProduccionFueraRanking): CumplimientoComercial => ({
729:     conversionObjetivo: 0,
730:     conversionReal: null,
731:     convertidos: (fila.conversion?.cierresNoReferidos ?? 0)
732:       + (fila.conversion?.cierresReferidos ?? 0)
733:       + fila.cartera.conversionesClientes,
734:     resueltos: fila.conversion?.divisor ?? 0,
735:     numerador: fila.conversion?.numerador ?? 0,
736:     detalles: fila.detalles,
737:   })
738:   const propias = Object.fromEntries(supervisores.map((fila) => [fila.personaId, comoCumplimiento(fila)]))
739:   const propia = actorId ? propias[actorId] : undefined
740:   const equipo = filas.filter((fila) => fila.supervisorId === actorId)
741:   const metaEquipo = agregarCumplimientos(equipo)
742:   const equipoConVentas = agregarCumplimientos([...equipo, ...(propia ? [propia] : [])])
743:   return {
744:     periodo: respuesta.periodo,
745:     revision: respuesta.revision,
746:     publicadaEn: respuesta.publicada_en,
747:     fuentesReales: {
748:       capitalYContratos: respuesta.fuentes_reales.capital_y_contratos,
749:       conversion: respuesta.fuentes_reales.conversion,
750:     },
751:     cierre: respuesta.cierre ?? null,
752:     vendedor: actorId ? (porVendedor[actorId] ?? null) : null,
753:     // Su producción aporta capital y contratos; no añade una meta individual
754:     // ni diluye el objetivo de conversión pactado con los analistas.
755:     supervisor: equipoConVentas == null ? null : {
756:       ...equipoConVentas,
757:       conversionObjetivo: metaEquipo?.conversionObjetivo ?? 0,
758:     },
759:     gerencia: agregarCumplimientos([...filas, ...fueraRanking.map(comoCumplimiento)]),
760:     porVendedor,
761:     fueraRanking: fueraRanking.filter((fila) => !supervisores.includes(fila)),
762:     supervisores,
763:   }
764: }
765: 
766: export function capitalReal(
767:   cumplimiento: CumplimientoAgregado,
768:   moneda: MonedaMeta,
769:   categoria?: CategoriaMeta,
770: ): number {
771:   return cumplimiento.detalles.reduce((total, detalle) => (

FILE CRM-Avance-Corp/app/src/screens/hoy/ranking-vendedores.tsx L707-752
707:     const siguiente = evento.key === 'ArrowRight' ? tipos[(indice + 1) % tipos.length]
708:       : evento.key === 'ArrowLeft' ? tipos[(indice + tipos.length - 1) % tipos.length]
709:       : evento.key === 'Home' ? tipos[0]
710:       : evento.key === 'End' ? tipos[tipos.length - 1] : undefined
711:     if (!siguiente) return
712:     evento.preventDefault()
713:     setTipo(siguiente)
714:     document.getElementById(IDS_TAB[siguiente].tab)?.focus()
715:   }
716:   // Una sola fuente define identidades para las TRES pestañas. En el mes
717:   // vigente manda el roster vivo; cumplimiento solo aporta meta/capital y no
718:   // puede reintroducir una baja. En un mes cerrado manda exclusivamente la
719:   // foto mensual, de modo que un alta posterior tampoco reescribe la historia.
720:   const equipoRanking = useMemo(() => {
721:     const porId = new Map<string, ConversionEquipoVendedor>()
722:     if (!usarIdentidadSnapshot) {
723:       for (const fila of equipo) {
724:         if (!fila.vendedorId) continue
725:         porId.set(fila.vendedorId, fila)
726:       }
727:       return [...porId.values()]
728:     }
729:     for (const fila of Object.values(cumplimientoVendedores)) {
730:       porId.set(fila.vendedorId, {
731:         vendedorId: fila.vendedorId,
732:         nombre: fila.nombre,
733:         supervisorId: fila.supervisorId,
734:         supervisorNombre: fila.supervisorNombre,
735:         leads: 0,
736:         contactados: 0,
737:         reunionesPactadas: 0,
738:         reunionesRealizadas: 0,
739:         clientes: 0,
740:         descartados: 0,
741:         conversionPct: null,
742:       })
743:     }
744:     return [...porId.values()]
745:   }, [cumplimientoVendedores, equipo, usarIdentidadSnapshot])
746:   const idsPoblacion = useMemo(
747:     () => new Set(equipoRanking.map((fila) => fila.vendedorId).filter((id): id is string => id != null)),
748:     [equipoRanking],
749:   )
750:   // Los núcleos son fuentes de MEDIDAS. Se proyectan al set autoritativo antes
751:   // de usar los adaptadores existentes, para que ni una respuesta obsoleta ni
752:   // fuera_de_roster materialicen una persona en pantalla.

FILE CRM-Avance-Corp/app/src/screens/equipo.tsx L528-543
528:   // Vive AQUÍ y no en «Hoy» porque en producción `FUNCIONES_LEADS_APROBADAS`
529:   // está en false: un supervisor real NO ve el mundo de leads, así que «Hoy» no
530:   // existe para él. «Gestión de equipo» sí la ve —no está en VISTAS_LEADS— y es
531:   // además donde ya mira a su gente.
532:   const equipoConversion = useMemo(
533:     () => identidadesEquipoConversion(ambito.vendedores, equipo),
534:     [ambito.vendedores, equipo],
535:   )
536:   const ahoraRanking = Date.parse(`${diaLima}T12:00:00Z`)
537:   const periodoRankingVigente = periodoInicialGerencia(ahoraRanking)
538:   const mesRankingVigente = periodoRankingVigente.desde.slice(0, 7)
539:   const [mesRanking, setMesRanking] = useState(mesRankingVigente)
540:   const mesRankingVigenteAnterior = useRef(mesRankingVigente)
541:   useEffect(() => {
542:     const anterior = mesRankingVigenteAnterior.current
543:     mesRankingVigenteAnterior.current = mesRankingVigente

FILE CRM-Avance-Corp/app/src/lib/objetivos.test.ts L220-290
220:       motivo: 'supervisor',
221:     })
222:     expect(capitalReal(cumplimiento.supervisor!, 'PEN')).toBeCloseTo(204_166.67, 1)
223:     expect(capitalReal(cumplimiento.gerencia!, 'PEN')).toBeCloseTo(274_166.67, 1)
224:     expect(capitalReal(cumplimiento.gerencia!, 'USD')).toBeCloseTo(21_416.67, 1)
225:   })
226: 
227:   it.each(['2026-10-01', '2026-11-01', '2027-01-01'])('desde octubre suma ventas propias al equipo una sola vez (%s)', (periodo) => {
228:     const respuesta = respuestaCumplimiento()
229:     respuesta.periodo = periodo
230:     const sinPropias = cumplimientoDesdeRpc(respuesta, S1)
231:     respuesta.fuera_ranking = [produccionSupervisor(S1), produccionSupervisor(S2)]
232:     // La API mantiene el contrato estricto existente, incluso con cliente viejo.
233:     const resultado = cumplimientoDesdeRpc(v.parse(CumplimientoMetasSchema, respuesta), S1)
234:     expect(capitalReal(resultado.supervisor!, 'PEN')).toBeCloseTo(274_166.67, 1)
235:     expect(capitalReal(resultado.supervisor!, 'USD')).toBeCloseTo(21_416.67, 1)
236:     expect(resultado.supervisor!.detalles.filter((fila) => fila.moneda === 'PEN').reduce((total, fila) => total + fila.contratosReal, 0)).toBe(7)
237:     expect(resultado.supervisor!.detalles.filter((fila) => fila.moneda === 'USD').reduce((total, fila) => total + fila.contratosReal, 0)).toBe(7)
238:     expect(capitalObjetivo(resultado.supervisor!, 'PEN')).toBe(capitalObjetivo(sinPropias.supervisor!, 'PEN'))
239:     expect(contratosObjetivo(resultado.supervisor!, 'PEN')).toBe(contratosObjetivo(sinPropias.supervisor!, 'PEN'))
240:     expect(resultado.supervisor!.conversionObjetivo).toBe(25)
241:     expect('conversionReal' in resultado.supervisor!).toBe(false)
242:     expect('numerador' in resultado.supervisor!).toBe(false)
243:     expect(resultado.porVendedor).toEqual(sinPropias.porVendedor)
244:     expect(resultado.vendedor).toBeNull()
245:     expect(resultado.supervisores?.map((fila) => fila.personaId)).toEqual([S1, S2])
246:     expect(resultado.fueraRanking).toEqual([])
247:     // Empresa incluye las dos ventas personales, una vez cada una, nunca suma equipos.
248:     expect(capitalReal(resultado.gerencia!, 'PEN')).toBeCloseTo(344_166.67, 1)
249:     expect(capitalReal(resultado.gerencia!, 'USD')).toBeCloseTo(22_416.67, 1)
250:     expect(produccionPorPersona(resultado)?.[S1]?.detalles[0]?.capitalReal).toBe(70_000)
251:   })
252: 
253:   it('septiembre conserva el aporte solo a empresa y octubre mantiene exactamente su total', () => {
254:     const respuesta = respuestaCumplimiento()
255:     respuesta.periodo = '2026-09-01'
256:     respuesta.fuera_ranking = [produccionSupervisor(S1)]
257:     const septiembre = cumplimientoDesdeRpc(respuesta, S1)
258:     const octubre = cumplimientoDesdeRpc({ ...respuesta, periodo: '2026-10-01' }, S1)
259:     expect(capitalReal(septiembre.supervisor!, 'PEN')).toBeCloseTo(204_166.67, 1)
260:     expect(septiembre.supervisores).toEqual([])
261:     expect(septiembre.fueraRanking).toHaveLength(1)
262:     expect(octubre.gerencia).toEqual(septiembre.gerencia)
263:   })
264: 
265:   it('un supervisor sin analistas ve su venta sin inventar metas; sin venta conserva el vacío', () => {
266:     const respuesta = { ...respuestaCumplimiento(), periodo: '2026-10-01', vendedores: [] }
267:     expect(cumplimientoDesdeRpc(respuesta, S1).supervisor).toBeNull()
268:     const resultado = cumplimientoDesdeRpc({ ...respuesta, fuera_ranking: [produccionSupervisor(S1)] }, S1)
269:     expect(capitalReal(resultado.supervisor!, 'PEN')).toBe(70_000)
270:     expect(capitalObjetivo(resultado.supervisor!, 'PEN')).toBe(0)
271:     expect(resultado.supervisor!.conversionObjetivo).toBe(0)
272:     expect(resultado.supervisor).toEqual(resultado.gerencia)
273:   })
274: 
275:   it('conserva otros responsables fuera del ranking y no atribuye sus ventas al supervisor', () => {
276:     const externa = { ...produccionSupervisor(S2), rol_crm: 'fuera_equipo' as const, motivo: 'fuera_estructura' as const }
277:     const respuesta = { ...respuestaCumplimiento(), periodo: '2026-10-01', fuera_ranking: [externa] }
278:     const resultado = cumplimientoDesdeRpc(v.parse(CumplimientoMetasSchema, respuesta), S1)
279:     expect(resultado.supervisores).toEqual([])
280:     expect(resultado.fueraRanking).toHaveLength(1)
281:     expect(capitalReal(resultado.supervisor!, 'PEN')).toBeCloseTo(204_166.67, 1)
282:   })
283: 
284:   it('conserva y agrega el descuento aplicado en una foto mensual cerrada', () => {
285:     const respuesta = respuestaCumplimiento()
286:     const fila = respuesta.vendedores[0]!
287:     fila.ajuste = {
288:       pendiente: 0,
289:       aplicado: 1,
290:       aplicado_pen: 40_000,

FILE CRM-Avance-Corp/supabase/migrations/20260901180000_crm_atr_4_sancion_de_anular_solo_conversion.sql L305-318
305:      and meta_autor.vendedor_id=base.creado_por
306:     left join crm.metas_vendedor meta_analista
307:       on meta_analista.meta_periodo_id=p_periodo_id
308:      and meta_analista.vendedor_id=base.analista_cierre_id
309:   ), contratos_confirmados as materialized (
310:     -- ATR-4 (Miguel 31/08): «solo la conversion, siempre». La anulacion ya NO
311:     -- neutraliza el capital del analista: su produccion queda como este. La
312:     -- sancion vive integra en la CONVERSION (conversion_episodios ya la
313:     -- aplica). La leccion del 2026-08-13 («solo se le puede quitar el merito
314:     -- a quien lo tiene») sigue viva donde corresponde: en la conversion.
315:     select a.id, a.vendedor_id, a.categoria, a.moneda, a.capital
316:     from atribuidos a
317:   ), externos_confirmados as materialized (
318:     -- Cierres en cooperativas (Qorilazo/Prodelco): suman a la cuota del mes

TRACKED DIFF
diff --git a/CRM-Avance-Corp/app/e2e/equipo.spec.ts b/CRM-Avance-Corp/app/e2e/equipo.spec.ts
index 3eea9d24..aec80638 100644
--- a/CRM-Avance-Corp/app/e2e/equipo.spec.ts
+++ b/CRM-Avance-Corp/app/e2e/equipo.spec.ts
@@ -13,8 +13,74 @@ import {
   loginReal,
   montarBackendReal,
   rankingAgostoReal,
+  UID,
 } from './_helpers'
 
+for (const rolCrm of ['supervisor', 'gerencia'] as const) {
+test(`${rolCrm}: ventas propias al final desde octubre y nunca como puesto de analista`, async ({ page }, testInfo) => {
+  await page.clock.setFixedTime(new Date('2026-10-16T15:00:00.000Z'))
+  const foto = rankingAgostoReal()
+  const ventasPropias = {
+    persona_id: UID,
+    nombre: 'SUPERVISOR VENTAS PROPIAS',
+    rol_crm: 'supervisor',
+    motivo: 'supervisor',
+    conversion: null,
+    detalles: (['nuevo', 'renovacion', 'upgrade'] as const).flatMap((categoria) =>
+      (['PEN', 'USD'] as const).map((moneda) => ({
+        categoria, moneda, capital_objetivo: 0,
+        capital_real: categoria === 'nuevo' && moneda === 'PEN' ? 900_000 : 0,
+        capital_cumplimiento_pct: null, contratos_objetivo: 0,
+        contratos_real: categoria === 'nuevo' && moneda === 'PEN' ? 1 : 0,
+        contratos_cumplimiento_pct: null,
+      }))),
+    cartera: {
+      conversiones_clientes: 0, conversiones_renovacion: 0, conversiones_upgrade: 0,
+      operaciones_renovacion: 0, operaciones_upgrade: 0, capital_renovado_pen: 0,
+      capital_renovado_usd: 0, capital_adicional_pen: 0, capital_adicional_usd: 0,
+      renovaciones_sin_desglose: 0,
+    },
+  }
+  await montarBackendReal(page, {
+    rolCrm, rolPortal: 'comercial',
+    configuracionMetas: { ...foto.configuracionMetas, periodo: '2026-10-01' },
+    cumplimientoMetas: { ...foto.cumplimientoMetas, periodo: '2026-10-01', fuera_ranking: [ventasPropias] },
+    metricas: { conversionMensual: foto.conversionMensual, cosecha: foto.cosecha },
+  })
+  // El mes vigente usa el equipo vivo: sus UUID deben coincidir con las metas.
+  const analistas = foto.configuracionMetas.vendedores as Array<{ vendedor_id: string; nombre: string }>
+  await page.route('**/rest/v1/rpc/equipo_visible_fn', (route) => route.fulfill({ json: [
+    { perfil_id: UID, nombre_completo: 'Usuario de prueba', rol_crm: rolCrm, supervisor_id: null, activo: true },
+    ...analistas.map((fila) => ({ perfil_id: fila.vendedor_id, nombre_completo: fila.nombre,
+      rol_crm: 'vendedor', supervisor_id: UID, activo: true })),
+  ] }))
+  await loginReal(page)
+  if (rolCrm === 'supervisor') await irAModulo(page, 'Gestión de equipo')
+  else await page.getByRole('button', { name: 'Ranking', exact: true }).click()
+  const selectorMes = page.getByLabel(rolCrm === 'supervisor' ? 'Mes del ranking' : 'Mes calendario')
+  await expect(selectorMes).toHaveValue('2026-10')
+  const ventas = page.getByRole('complementary', { name: 'Ventas propias de supervisores' })
+  await expect(ventas.getByText('SUPERVISOR VENTAS PROPIAS')).toBeVisible()
+  await expect(ventas.getByText('Aporta a su equipo')).toBeVisible()
+  await expect(ventas.getByText('S/ 900,000', { exact: true })).toBeVisible()
+  await page.getByRole('tab', { name: 'Capital total' }).click()
+  const tabla = page.getByRole('table', { name: 'Ranking de capital total en soles' })
+  await expect(tabla).toBeVisible()
+  await expect(tabla.getByRole('row', { name: /ANA AGOSTO/ })).toContainText('S/ 43,530')
+  await expect(tabla.getByRole('row', { name: /BRUNO AGOSTO/ })).toContainText('S/ 21,765')
+  await expect(tabla.getByText('SUPERVISOR VENTAS PROPIAS')).toHaveCount(0)
+  expect(await tabla.evaluate((el) => Boolean(el.compareDocumentPosition(
+    document.querySelector('[aria-label="Ventas propias de supervisores"]')!,
+  ) & Node.DOCUMENT_POSITION_FOLLOWING))).toBe(true)
+  await ventas.scrollIntoViewIfNeeded()
+  await page.screenshot({ path: testInfo.outputPath('supervisor-al-final.png') })
+  // Incluso si una respuesta anterior trae producción global, el corte del
+  // adaptador impide presentar septiembre con las reglas de octubre.
+  await selectorMes.fill('2026-09')
+  await expect(ventas).toHaveCount(0)
+})
+}
+
 test('demo supervisor: Gestión de equipo conserva seguimiento y separa el reparto', async ({ page }) => {
   // Fail-closed: en demo NINGÚN request debe salir al host de Supabase.
   const requestsSupabase = await bloquearSupabase(page)
diff --git a/CRM-Avance-Corp/app/src/lib/objetivos.test.ts b/CRM-Avance-Corp/app/src/lib/objetivos.test.ts
index 0a22f1eb..b0363e27 100644
--- a/CRM-Avance-Corp/app/src/lib/objetivos.test.ts
+++ b/CRM-Avance-Corp/app/src/lib/objetivos.test.ts
@@ -92,6 +92,48 @@ function respuestaCumplimiento(): CumplimientoMetasRpc {
   }
 }
 
+function produccionSupervisor(personaId = S2): NonNullable<CumplimientoMetasRpc['fuera_ranking']>[number] {
+  return {
+    persona_id: personaId,
+    nombre: 'Supervisor con inversión propia',
+    rol_crm: 'supervisor',
+    motivo: 'supervisor',
+    conversion: {
+      divisor: 4,
+      divisor_aproximado: 0,
+      divisor_por_motivo: { asignacion: 4 },
+      cierres_no_referidos: 1,
+      cierres_referidos: 0,
+      cierres_de_arrastre: 0,
+      referidos_recibidos: 0,
+      numerador: 1,
+    },
+    detalles: detalles(0, 0).map((detalle, indice) => ({
+      ...detalle,
+      capital_objetivo: 0,
+      capital_real: indice === 0 ? 70_000 : indice === 1 ? 1_000 : 0,
+      capital_cumplimiento_pct: null,
+      contratos_objetivo: 0,
+      contratos_real: indice < 2 ? 1 : 0,
+      contratos_cumplimiento_pct: null,
+      capital_ajuste: 0,
+      contratos_ajuste: 0,
+    })),
+    cartera: {
+      conversiones_clientes: 1,
+      conversiones_renovacion: 1,
+      conversiones_upgrade: 0,
+      operaciones_renovacion: 1,
+      operaciones_upgrade: 0,
+      capital_renovado_pen: 5_000,
+      capital_renovado_usd: 0,
+      capital_adicional_pen: 0,
+      capital_adicional_usd: 0,
+      renovaciones_sin_desglose: 0,
+    },
+  }
+}
+
 describe('metas versionadas y jerarquía', () => {
   it('no inventa una meta de conversión cuando no existe o falló la lectura', () => {
     expect(metaConversionAplicable(0)).toBeNull()
@@ -162,45 +204,7 @@ describe('metas versionadas y jerarquía', () => {
 
   it('suma la producción externa solo al total empresa y nunca crea un puesto', () => {
     const respuesta = respuestaCumplimiento()
-    respuesta.fuera_ranking = [{
-      persona_id: S2,
-      nombre: 'Supervisor con inversión propia',
-      rol_crm: 'supervisor',
-      motivo: 'supervisor',
-      conversion: {
-        divisor: 4,
-        divisor_aproximado: 0,
-        divisor_por_motivo: { asignacion: 4 },
-        cierres_no_referidos: 1,
-        cierres_referidos: 0,
-        cierres_de_arrastre: 0,
-        referidos_recibidos: 0,
-        numerador: 1,
-      },
-      detalles: detalles(0, 0).map((detalle, indice) => ({
-        ...detalle,
-        capital_objetivo: 0,
-        capital_real: indice === 0 ? 70_000 : indice === 1 ? 1_000 : 0,
-        capital_cumplimiento_pct: null,
-        contratos_objetivo: 0,
-        contratos_real: indice < 2 ? 1 : 0,
-        contratos_cumplimiento_pct: null,
-        capital_ajuste: 0,
-        contratos_ajuste: 0,
-      })),
-      cartera: {
-        conversiones_clientes: 1,
-        conversiones_renovacion: 1,
-        conversiones_upgrade: 0,
-        operaciones_renovacion: 1,
-        operaciones_upgrade: 0,
-        capital_renovado_pen: 5_000,
-        capital_renovado_usd: 0,
-        capital_adicional_pen: 0,
-        capital_adicional_usd: 0,
-        renovaciones_sin_desglose: 0,
-      },
-    }]
+    respuesta.fuera_ranking = [produccionSupervisor()]
 
     const cumplimiento = cumplimientoDesdeRpc(
       v.parse(CumplimientoMetasSchema, respuesta),
@@ -220,6 +224,63 @@ describe('metas versionadas y jerarquía', () => {
     expect(capitalReal(cumplimiento.gerencia!, 'USD')).toBeCloseTo(21_416.67, 1)
   })
 
+  it.each(['2026-10-01', '2026-11-01', '2027-01-01'])('desde octubre suma ventas propias al equipo una sola vez (%s)', (periodo) => {
+    const respuesta = respuestaCumplimiento()
+    respuesta.periodo = periodo
+    const sinPropias = cumplimientoDesdeRpc(respuesta, S1)
+    respuesta.fuera_ranking = [produccionSupervisor(S1), produccionSupervisor(S2)]
+    // La API mantiene el contrato estricto existente, incluso con cliente viejo.
+    const resultado = cumplimientoDesdeRpc(v.parse(CumplimientoMetasSchema, respuesta), S1)
+    expect(capitalReal(resultado.supervisor!, 'PEN')).toBeCloseTo(274_166.67, 1)
+    expect(capitalReal(resultado.supervisor!, 'USD')).toBeCloseTo(21_416.67, 1)
+    expect(resultado.supervisor!.detalles.filter((fila) => fila.moneda === 'PEN').reduce((total, fila) => total + fila.contratosReal, 0)).toBe(7)
+    expect(resultado.supervisor!.detalles.filter((fila) => fila.moneda === 'USD').reduce((total, fila) => total + fila.contratosReal, 0)).toBe(7)
+    expect(capitalObjetivo(resultado.supervisor!, 'PEN')).toBe(capitalObjetivo(sinPropias.supervisor!, 'PEN'))
+    expect(contratosObjetivo(resultado.supervisor!, 'PEN')).toBe(contratosObjetivo(sinPropias.supervisor!, 'PEN'))
+    expect(resultado.supervisor!.conversionObjetivo).toBe(25)
+    expect('conversionReal' in resultado.supervisor!).toBe(false)
+    expect('numerador' in resultado.supervisor!).toBe(false)
+    expect(resultado.porVendedor).toEqual(sinPropias.porVendedor)
+    expect(resultado.vendedor).toBeNull()
+    expect(resultado.supervisores?.map((fila) => fila.personaId)).toEqual([S1, S2])
+    expect(resultado.fueraRanking).toEqual([])
+    // Empresa incluye las dos ventas personales, una vez cada una, nunca suma equipos.
+    expect(capitalReal(resultado.gerencia!, 'PEN')).toBeCloseTo(344_166.67, 1)
+    expect(capitalReal(resultado.gerencia!, 'USD')).toBeCloseTo(22_416.67, 1)
+    expect(produccionPorPersona(resultado)?.[S1]?.detalles[0]?.capitalReal).toBe(70_000)
+  })
+
+  it('septiembre conserva el aporte solo a empresa y octubre mantiene exactamente su total', () => {
+    const respuesta = respuestaCumplimiento()
+    respuesta.periodo = '2026-09-01'
+    respuesta.fuera_ranking = [produccionSupervisor(S1)]
+    const septiembre = cumplimientoDesdeRpc(respuesta, S1)
+    const octubre = cumplimientoDesdeRpc({ ...respuesta, periodo: '2026-10-01' }, S1)
+    expect(capitalReal(septiembre.supervisor!, 'PEN')).toBeCloseTo(204_166.67, 1)
+    expect(septiembre.supervisores).toEqual([])
+    expect(septiembre.fueraRanking).toHaveLength(1)
+    expect(octubre.gerencia).toEqual(septiembre.gerencia)
+  })
+
+  it('un supervisor sin analistas ve su venta sin inventar metas; sin venta conserva el vacío', () => {
+    const respuesta = { ...respuestaCumplimiento(), periodo: '2026-10-01', vendedores: [] }
+    expect(cumplimientoDesdeRpc(respuesta, S1).supervisor).toBeNull()
+    const resultado = cumplimientoDesdeRpc({ ...respuesta, fuera_ranking: [produccionSupervisor(S1)] }, S1)
+    expect(capitalReal(resultado.supervisor!, 'PEN')).toBe(70_000)
+    expect(capitalObjetivo(resultado.supervisor!, 'PEN')).toBe(0)
+    expect(resultado.supervisor!.conversionObjetivo).toBe(0)
+    expect(resultado.supervisor).toEqual(resultado.gerencia)
+  })
+
+  it('conserva otros responsables fuera del ranking y no atribuye sus ventas al supervisor', () => {
+    const externa = { ...produccionSupervisor(S2), rol_crm: 'fuera_equipo' as const, motivo: 'fuera_estructura' as const }
+    const respuesta = { ...respuestaCumplimiento(), periodo: '2026-10-01', fuera_ranking: [externa] }
+    const resultado = cumplimientoDesdeRpc(v.parse(CumplimientoMetasSchema, respuesta), S1)
+    expect(resultado.supervisores).toEqual([])
+    expect(resultado.fueraRanking).toHaveLength(1)
+    expect(capitalReal(resultado.supervisor!, 'PEN')).toBeCloseTo(204_166.67, 1)
+  })
+
   it('conserva y agrega el descuento aplicado en una foto mensual cerrada', () => {
     const respuesta = respuestaCumplimiento()
     const fila = respuesta.vendedores[0]!
diff --git a/CRM-Avance-Corp/app/src/lib/objetivos.ts b/CRM-Avance-Corp/app/src/lib/objetivos.ts
index e755f783..5a34d11a 100644
--- a/CRM-Avance-Corp/app/src/lib/objetivos.ts
+++ b/CRM-Avance-Corp/app/src/lib/objetivos.ts
@@ -491,6 +491,8 @@ export interface CumplimientoMetasJerarquico {
   porVendedor: Record<string, CumplimientoVendedor>
   /** Produccion identificada que cuadra en empresa sin generar un puesto. */
   fueraRanking: ProduccionFueraRanking[]
+  /** Ventas propias, al final del ranking y con aporte al equipo. */
+  supervisores?: ProduccionFueraRanking[]
 }
 
 function cumplimientoDesdeVendedor(
@@ -660,14 +662,16 @@ export function metaVigente(
  * con meta.
  */
 export function produccionPorPersona(
-  cumplimiento: Pick<CumplimientoMetasJerarquico, 'porVendedor'> & { fueraRanking?: readonly ProduccionFueraRanking[] } | null | undefined,
+  cumplimiento: Pick<CumplimientoMetasJerarquico, 'porVendedor'> & { fueraRanking?: readonly ProduccionFueraRanking[]; supervisores?: readonly ProduccionFueraRanking[] } | null | undefined,
 ): Record<string, Pick<CumplimientoVendedor, 'nombre' | 'detalles'>> | null {
   if (cumplimiento == null) return null
-  const fuera = Object.fromEntries((cumplimiento.fueraRanking ?? [])
+  const fuera = Object.fromEntries([...(cumplimiento.fueraRanking ?? []), ...(cumplimiento.supervisores ?? [])]
     .map((fila) => [fila.personaId, { nombre: fila.nombre, detalles: fila.detalles }]))
   return { ...fuera, ...cumplimiento.porVendedor }
 }
 
+const VENTAS_SUPERVISORES_DESDE = '2026-10-01'
+
 export function cumplimientoDesdeRpc(
   respuesta: CumplimientoMetasRpc,
   actorId?: string | null,
@@ -716,7 +720,12 @@ export function cumplimientoDesdeRpc(
       renovacionesSinDesglose: fila.cartera.renovaciones_sin_desglose,
     },
   }))
-  const fueraComoCumplimiento: CumplimientoComercial[] = fueraRanking.map((fila) => ({
+  // Mismo corte comercial que la puerta SQL; el servidor mantiene fuera_ranking
+  // compatible para todos los lectores y el adaptador separa su presentación.
+  const supervisores = respuesta.periodo >= VENTAS_SUPERVISORES_DESDE
+    ? fueraRanking.filter((fila) => fila.rolCrm === 'supervisor' && fila.motivo === 'supervisor')
+    : []
+  const comoCumplimiento = (fila: ProduccionFueraRanking): CumplimientoComercial => ({
     conversionObjetivo: 0,
     conversionReal: null,
     convertidos: (fila.conversion?.cierresNoReferidos ?? 0)
@@ -725,7 +734,12 @@ export function cumplimientoDesdeRpc(
     resueltos: fila.conversion?.divisor ?? 0,
     numerador: fila.conversion?.numerador ?? 0,
     detalles: fila.detalles,
-  }))
+  })
+  const propias = Object.fromEntries(supervisores.map((fila) => [fila.personaId, comoCumplimiento(fila)]))
+  const propia = actorId ? propias[actorId] : undefined
+  const equipo = filas.filter((fila) => fila.supervisorId === actorId)
+  const metaEquipo = agregarCumplimientos(equipo)
+  const equipoConVentas = agregarCumplimientos([...equipo, ...(propia ? [propia] : [])])
   return {
     periodo: respuesta.periodo,
     revision: respuesta.revision,
@@ -736,10 +750,16 @@ export function cumplimientoDesdeRpc(
     },
     cierre: respuesta.cierre ?? null,
     vendedor: actorId ? (porVendedor[actorId] ?? null) : null,
-    supervisor: agregarCumplimientos(filas.filter((fila) => fila.supervisorId === actorId)),
-    gerencia: agregarCumplimientos([...filas, ...fueraComoCumplimiento]),
+    // Su producción aporta capital y contratos; no añade una meta individual
+    // ni diluye el objetivo de conversión pactado con los analistas.
+    supervisor: equipoConVentas == null ? null : {
+      ...equipoConVentas,
+      conversionObjetivo: metaEquipo?.conversionObjetivo ?? 0,
+    },
+    gerencia: agregarCumplimientos([...filas, ...fueraRanking.map(comoCumplimiento)]),
     porVendedor,
-    fueraRanking,
+    fueraRanking: fueraRanking.filter((fila) => !supervisores.includes(fila)),
+    supervisores,
   }
 }
 
diff --git a/CRM-Avance-Corp/app/src/screens/equipo.tsx b/CRM-Avance-Corp/app/src/screens/equipo.tsx
index 3339a037..0d516cbb 100644
--- a/CRM-Avance-Corp/app/src/screens/equipo.tsx
+++ b/CRM-Avance-Corp/app/src/screens/equipo.tsx
@@ -837,6 +837,7 @@ function EquipoSupervisor(): JSX.Element {
           equipo={equipoConversion}
           metasVendedores={metasVendedoresRanking}
           cumplimientoVendedores={cumplimientoRanking?.porVendedor ?? {}}
+          supervisores={cumplimientoRanking?.supervisores ?? []}
           metaMensual={metaMensual}
           // El vigente conserva altas/bajas del roster vivo; la identidad se
           // congela únicamente al consultar un mes histórico.
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/gerencia.tsx b/CRM-Avance-Corp/app/src/screens/hoy/gerencia.tsx
index 9c5553c7..64e41cf1 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/gerencia.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/gerencia.tsx
@@ -751,6 +751,7 @@ export function HoyGerencia({ seccion = 'completo' }: { seccion?: SeccionGerenci
           equipo={datosEquipoConversion}
           metasVendedores={metasVendedoresRanking}
           cumplimientoVendedores={cumplimientoRanking?.porVendedor ?? {}}
+          supervisores={cumplimientoRanking?.supervisores ?? []}
           fueraRanking={cumplimientoRanking?.fueraRanking ?? []}
           metaMensual={metaMensualRanking}
           // El mes vivo sigue el roster activo; solo un mes histórico congela
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/ranking-vendedores.test.tsx b/CRM-Avance-Corp/app/src/screens/hoy/ranking-vendedores.test.tsx
index 69600578..8c9410f1 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/ranking-vendedores.test.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/ranking-vendedores.test.tsx
@@ -383,7 +383,7 @@ describe('ranking general de analistas', () => {
     expect(mensual).toEqual(original)
   })
 
-  it('muestra la producción no analista aparte sin concederle puesto', () => {
+  it.each([false, true])('muestra ventas propias al final sin concederles puesto (desde octubre: %s)', (desdeOctubre) => {
     const cumplimiento = cumplimientoMetasConversionEquipoDemo()
     const base = cumplimiento.porVendedor['demo-v1']!
     const fueraRanking: ProduccionFueraRanking[] = [{
@@ -404,7 +404,7 @@ describe('ranking general de analistas', () => {
       detalles: base.detalles.map((detalle, indice) => ({
         ...detalle,
         capitalObjetivo: 0,
-        capitalReal: indice === 0 ? 70_000 : indice === 1 ? 1_000 : 0,
+        capitalReal: indice === 0 ? 7_000_000 : indice === 1 ? 1_000 : 0,
         capitalCumplimientoPct: null,
         contratosObjetivo: 0,
         contratosReal: indice < 2 ? 1 : 0,
@@ -431,20 +431,29 @@ describe('ranking general de analistas', () => {
         equipo={conversionEquipoDemo()}
         metasVendedores={metasConversionEquipoDemo()}
         cumplimientoVendedores={cumplimiento.porVendedor}
-        fueraRanking={fueraRanking}
-        metaMensual={{ etiqueta: 'agosto 2026', comparable: true }}
+        fueraRanking={desdeOctubre ? [] : fueraRanking}
+        supervisores={desdeOctubre ? fueraRanking : []}
+        metaMensual={{ etiqueta: desdeOctubre ? 'octubre 2026' : 'agosto 2026', comparable: true }}
         tc={{ promedio: 3.5, fuente: 'SBS · prom. 7d' }}
         {...fuentesRankingSinError()}
       />,
     )
 
     expect(screen.getByText('6 analistas')).toBeInTheDocument()
-    const bloque = screen.getByRole('complementary', { name: 'Producción fuera del ranking' })
+    const bloque = screen.getByRole('complementary', { name: desdeOctubre ? 'Ventas propias de supervisores' : 'Producción fuera del ranking' })
     expect(within(bloque).getByText('Supervisor con inversión propia')).toBeInTheDocument()
-    expect(within(bloque).getByText('Producción atribuida a supervisor')).toBeInTheDocument()
-    expect(within(bloque).getByText('No suma al ranking')).toBeInTheDocument()
+    expect(within(bloque).getByText(desdeOctubre ? 'Ventas propias · Supervisor' : 'Producción atribuida a supervisor')).toBeInTheDocument()
+    expect(within(bloque).getByText(desdeOctubre ? 'Aporta a su equipo' : 'No suma al ranking')).toBeInTheDocument()
     expect(within(bloque).queryByLabelText(/Puesto/)).not.toBeInTheDocument()
     expect(within(bloque).getByText('2 contratos')).toBeInTheDocument()
+    // Aunque supere el capital de todos los analistas, nunca toma sus puestos.
+    for (const tab of ['Capital total', 'Conversión general']) {
+      fireEvent.click(screen.getByRole('tab', { name: tab }))
+      const tabla = screen.getByRole('table', { name: tab === 'Capital total' ? 'Ranking de capital total en soles' : 'Ranking de conversión general' })
+      expect(within(tabla).queryByText('Supervisor con inversión propia')).not.toBeInTheDocument()
+      expect(tabla.compareDocumentPosition(bloque) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
+      expect(screen.getAllByRole('complementary').at(-1)).toBe(bloque)
+    }
   })
 
   it('no promete una foto sellada en Cosecha, que continúa madurando', () => {
diff --git a/CRM-Avance-Corp/app/src/screens/hoy/ranking-vendedores.tsx b/CRM-Avance-Corp/app/src/screens/hoy/ranking-vendedores.tsx
index ed2123f8..701bab7e 100644
--- a/CRM-Avance-Corp/app/src/screens/hoy/ranking-vendedores.tsx
+++ b/CRM-Avance-Corp/app/src/screens/hoy/ranking-vendedores.tsx
@@ -76,6 +76,8 @@ interface RankingVendedoresPanelProps {
   cumplimientoVendedores: Record<string, CumplimientoVendedor>
   /** Produccion empresarial identificada que no puede recibir un puesto. */
   fueraRanking?: ProduccionFueraRanking[]
+  /** Sus ventas propias se muestran siempre después de todos los analistas. */
+  supervisores?: ProduccionFueraRanking[]
   metaMensual: MetaMensualGerencia
   /** Nombre, supervisor y población salen de la foto mensual autoritativa. */
   usarIdentidadSnapshot?: boolean
@@ -575,26 +577,33 @@ function RankingCapitalTotal({ ranking, onAbrirDetalle }: { ranking: RankingCapi
 function ProduccionFueraRankingPanel({
   filas,
   tc,
+  sonSupervisores = false,
 }: {
   filas: ProduccionFueraRanking[]
   tc: TipoCambio | null | undefined
+  sonSupervisores?: boolean
 }): JSX.Element | null {
   if (filas.length === 0) return null
+  const titulo = sonSupervisores ? 'Ventas propias de supervisores' : 'Producción fuera del ranking'
 
   return (
     <aside
-      aria-label="Producción fuera del ranking"
+      aria-label={titulo}
       className="border-t border-[var(--gi-line)] bg-amber-50/45 px-4 py-4 sm:px-5"
     >
       <div className="flex flex-wrap items-start justify-between gap-2">
         <div>
-          <h3 className="text-sm font-bold text-[var(--gi-navy)]">Producción fuera del ranking</h3>
+          <h3 className="text-sm font-bold text-[var(--gi-navy)]">{titulo}</h3>
           <p className="mt-1 max-w-3xl text-[11px] font-medium leading-relaxed text-[var(--gi-muted)]">
-            Suma al resultado total de la empresa, pero no entrega puesto ni altera el orden de los analistas.
+            {sonSupervisores
+              ? 'Los supervisores aparecen al final. Sus ventas propias también suman al avance de su equipo.'
+              : 'Suma al resultado total de la empresa, pero no entrega puesto ni altera el orden de los analistas.'}
           </p>
         </div>
         <span className="rounded-full border border-amber-300 bg-amber-100 px-2.5 py-1 text-[10px] font-bold text-amber-900">
-          {numero(filas.length)} {filas.length === 1 ? 'responsable' : 'responsables'} sin puesto
+          {numero(filas.length)} {sonSupervisores
+            ? (filas.length === 1 ? 'supervisor' : 'supervisores')
+            : (filas.length === 1 ? 'responsable sin puesto' : 'responsables sin puesto')}
         </span>
       </div>
 
@@ -623,11 +632,11 @@ function ProduccionFueraRankingPanel({
                 <span className="min-w-0">
                   <strong className="block truncate text-xs text-[var(--gi-navy)]">{fila.nombre}</strong>
                   <span className="mt-0.5 block text-[10px] font-medium text-[var(--gi-muted)]">
-                    {MOTIVO_FUERA_RANKING[fila.motivo]}
+                    {sonSupervisores ? 'Ventas propias · Supervisor' : MOTIVO_FUERA_RANKING[fila.motivo]}
                   </span>
                 </span>
                 <span className="shrink-0 rounded-full bg-slate-100 px-2 py-1 text-[10px] font-bold text-slate-700">
-                  No suma al ranking
+                  {sonSupervisores ? 'Aporta a su equipo' : 'No suma al ranking'}
                 </span>
               </div>
               <div className="mt-2 flex flex-wrap items-end justify-between gap-x-4 gap-y-2">
@@ -667,6 +676,7 @@ export function RankingVendedoresPanel({
   metasVendedores,
   cumplimientoVendedores,
   fueraRanking = [],
+  supervisores = [],
   metaMensual,
   usarIdentidadSnapshot = false,
   estadoFotoMensual,
@@ -676,7 +686,7 @@ export function RankingVendedoresPanel({
   capitalError,
   onReintentarCapital,
   tc,
-  titulo = 'Ranking general de analistas',
+  titulo = 'Ranking comercial',
   etiquetaAlcance = 'Equipo completo',
   tabInicial = 'conversion',
   tipoSeleccionado,
@@ -941,7 +951,10 @@ export function RankingVendedoresPanel({
         </>
       )}
       {fuenteConversion == null && !fotoMensualCargando && !fotoMensualError && (
-        <ProduccionFueraRankingPanel filas={fueraRanking} tc={tc} />
+        <>
+          <ProduccionFueraRankingPanel filas={fueraRanking} tc={tc} />
+          <ProduccionFueraRankingPanel filas={supervisores} tc={tc} sonSupervisores />
+        </>
       )}
       <DetalleCapitalRanking
         abierto={detalleId !== null}


SQL OUTPUT
NOTICE:  PASS: matriz completa: nueve actores, tres meses, antes y después
NOTICE:  PASS: paridad JSON exacta: gerencia / 2026-09-01
NOTICE:  PASS: paridad JSON exacta: gerencia / 2026-10-01
NOTICE:  PASS: paridad JSON exacta: gerencia / 2026-11-01
NOTICE:  PASS: paridad JSON exacta: directorio / 2026-09-01
NOTICE:  PASS: paridad JSON exacta: coordinador / 2026-11-01
NOTICE:  PASS: paridad JSON exacta: directorio / 2026-10-01
NOTICE:  PASS: paridad JSON exacta: directorio / 2026-11-01
NOTICE:  PASS: paridad JSON exacta: coordinador / 2026-09-01
NOTICE:  PASS: paridad JSON exacta: coordinador / 2026-10-01
NOTICE:  PASS: paridad JSON exacta: sup1 / 2026-09-01
NOTICE:  PASS: solo producción propia, sin equipo ajeno: sup1 / 2026-10-01
NOTICE:  PASS: resto del contrato intacto: sup1 / 2026-10-01
NOTICE:  PASS: atribución única o vacío sin ventas: sup1 / 2026-10-01
NOTICE:  PASS: solo producción propia, sin equipo ajeno: sup1 / 2026-11-01
NOTICE:  PASS: resto del contrato intacto: sup1 / 2026-11-01
NOTICE:  PASS: atribución única o vacío sin ventas: sup1 / 2026-11-01
NOTICE:  PASS: paridad JSON exacta: sup2 / 2026-09-01
NOTICE:  PASS: solo producción propia, sin equipo ajeno: sup2 / 2026-10-01
NOTICE:  PASS: resto del contrato intacto: sup2 / 2026-10-01
NOTICE:  PASS: atribución única o vacío sin ventas: sup2 / 2026-10-01
NOTICE:  PASS: solo producción propia, sin equipo ajeno: sup2 / 2026-11-01
NOTICE:  PASS: resto del contrato intacto: sup2 / 2026-11-01
NOTICE:  PASS: atribución única o vacío sin ventas: sup2 / 2026-11-01
NOTICE:  PASS: paridad JSON exacta: sin_equipo / 2026-09-01
NOTICE:  PASS: solo producción propia, sin equipo ajeno: sin_equipo / 2026-10-01
NOTICE:  PASS: resto del contrato intacto: sin_equipo / 2026-10-01
NOTICE:  PASS: atribución única o vacío sin ventas: sin_equipo / 2026-10-01
NOTICE:  PASS: solo producción propia, sin equipo ajeno: sin_equipo / 2026-11-01
NOTICE:  PASS: resto del contrato intacto: sin_equipo / 2026-11-01
NOTICE:  PASS: atribución única o vacío sin ventas: sin_equipo / 2026-11-01
NOTICE:  PASS: paridad JSON exacta: sin_ventas / 2026-09-01
NOTICE:  PASS: solo producción propia, sin equipo ajeno: sin_ventas / 2026-10-01
NOTICE:  PASS: resto del contrato intacto: sin_ventas / 2026-10-01
NOTICE:  PASS: atribución única o vacío sin ventas: sin_ventas / 2026-10-01
NOTICE:  PASS: solo producción propia, sin equipo ajeno: sin_ventas / 2026-11-01
NOTICE:  PASS: resto del contrato intacto: sin_ventas / 2026-11-01
NOTICE:  PASS: atribución única o vacío sin ventas: sin_ventas / 2026-11-01
NOTICE:  PASS: paridad JSON exacta: vend1 / 2026-09-01
NOTICE:  PASS: paridad JSON exacta: vend1 / 2026-10-01
NOTICE:  PASS: paridad JSON exacta: vend1 / 2026-11-01
NOTICE:  PASS: paridad JSON exacta: vend2 / 2026-09-01
NOTICE:  PASS: paridad JSON exacta: vend2 / 2026-10-01
NOTICE:  PASS: paridad JSON exacta: vend2 / 2026-11-01
NOTICE:  PASS: capital propio PEN conserva al autor comercial
NOTICE:  PASS: mes sellado conserva USD de la foto sin recalcular noviembre
NOTICE:  PASS: cliente sin rol CRM rechazado
NOTICE:  PASS: sesión sin identidad rechazada
NOTICE:  PASS: contrato y cooperativa propios suman una vez cada uno
NOTICE:  PASS: perfil inactivo revoca la lectura propia
NOTICE:  PASS: cambio a analista retira la capacidad de supervisión
NOTICE:  PASS: cambio de rol tampoco hereda acceso a fotos de supervisión
NOTICE:  PASS: baja CRM revoca las ventas propias con el mismo actor
NOTICE:  PASS: ACL, security definer, estabilidad y search_path intactos
NOTICE:  PASS: ningún sello modificado
NOTICE:  PASS: ninguna venta duplicada, reasignada ni modificada
NOTICE:  PASS: cooperativas conservan atribución, monto e identidad
NOTICE:  PASS: reversa recupera exactamente el comportamiento anterior
NOTICE:  PASS: reaplicación recupera exactamente las ventas propias


E2E OUTPUT
npm notice run app@0.0.0 test:e2e:docker
npm notice run bash scripts/e2e-docker.sh e2e/equipo.spec.ts e2e/ranking-cartera.spec.ts e2e/gerencia-coherencia.spec.ts --reporter=list
E2E en Docker · imagen mcr.microsoft.com/playwright:v1.61.1-noble
Instalando dependencias (package-lock.json cambió o volumen nuevo)…
npm warn deprecated jpeg-exif@1.1.4: Package no longer supported. Contact Support at https://www.npmjs.com/support for more info.
npm warn deprecated crypto-js@4.2.0: Active development of CryptoJS has been discontinued. This library is no longer maintained.

added 366 packages in 22s

Running 9 tests using 2 workers

  ✓  1 [chromium] › e2e/equipo.spec.ts:20:1 › supervisor: ventas propias al final desde octubre y nunca como puesto de analista (17.9s)
  ✓  2 [chromium] › e2e/equipo.spec.ts:20:1 › gerencia: ventas propias al final desde octubre y nunca como puesto de analista (18.1s)
  ✓  3 [chromium] › e2e/equipo.spec.ts:75:1 › demo supervisor: Gestión de equipo conserva seguimiento y separa el reparto (3.7s)
  ✓  4 [chromium] › e2e/equipo.spec.ts:99:1 › supervisor real: el selector mensual recupera la foto completa de agosto (3.9s)
  ✓  5 [chromium] › e2e/equipo.spec.ts:195:1 › demo gerencia: un bloque por supervisor con la TABLA comparativa de analistas (3.6s)
  ✓  6 [chromium] › e2e/equipo.spec.ts:233:1 › demo gerencia: reparte desde la bandeja global (optgroup por equipo) con toast "(demo)" (4.1s)
  ✓  7 [chromium] › e2e/equipo.spec.ts:252:1 › demo directorio: la misma radiografía en tabla pero SIN botones de acción (3.9s)
  ✓  8 [chromium] › e2e/gerencia-coherencia.spec.ts:7:1 › siete hallazgos: conserva el corte mensual, combina fuentes y protege el mes cerrado (4.0s)
  ✓  9 [chromium] › e2e/ranking-cartera.spec.ts:4:1 › capital por origen muestra renovación y upgrade dentro de cartera en escritorio y móvil (4.2s)

  9 passed (37.0s)


CodeGraph attempted first: Explore failed: unable to open database file. No index rebuilt; sources attached above. Provide verdict on final code. Distinguish existing/explicit scope limits from regressions.
