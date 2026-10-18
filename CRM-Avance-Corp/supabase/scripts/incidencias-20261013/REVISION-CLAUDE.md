VERDICT:
CHANGES_REQUESTED

SUMMARY:
Revisé solo la evidencia adjunta. No usé herramientas ni modifiqué nada. Mi rol es auditor-rls, LEVEL 3.

Las dos migraciones son correctas en lo que pude ver:
- La de SLA es semánticamente equivalente a la versión anterior.
- No amplía la visibilidad entre roles.
- No toca `public`, grants, RLS ni la inmutabilidad.
- La de F7 no oculta una deriva F7 previa, porque el postflight exige que el vigilante quede completo en verde.

El transporte del frontend está bien diseñado. Sin embargo, **no se adjuntó el diff de `app/src/lib/supabase.ts`**, que es donde se conecta. Tampoco se adjuntó el de `MIGRACIONES.md`. Sin esos dos diffs no puedo validar la integración real ni el ledger.

Quedan además algunos puntos menores de endurecimiento y pruebas. Esta revisión **no** autoriza el despliegue: la matriz HTTP `test-rls.mjs` y los advisors siguen en NOT RUN.

FINDINGS:

[P1] Falta evidencia esencial de la integración del transporte
File:
`app/src/lib/supabase.ts` (aparece como modificado en git status; no se adjuntó)
Lines:
N/D
Problem:
No puedo verificar cuatro cosas:
- qué `proyecto` y qué `clavePublica` recibe `crearFetchCrm`;
- si son exactamente los mismos valores que recibe `createClient`;
- si se conserva un `global.fetch` previo (por ejemplo, timeouts o telemetría);
- si se usa `db.schema: 'crm'`.
Evidence:
La guarda de `transporte-crm.ts:18` depende de que se cumpla `token === clavePublica`. Si la clave pasada difiere de la que el SDK pone en `Authorization` la guarda deja de actuar sin avisar:
- por un `trim`;
- por otra variable de entorno;
- por una clave `sb_publishable_…` frente a la `anon` legacy.
Si `proyecto` difiere del origen real (por ejemplo, un dominio personalizado), `esCrm` en la línea 15 es siempre falso.
Impact:
La corrección de sesión podría no tener ningún efecto en producción mientras todos los tests unitarios pasan. Los tests construyen el cliente con los mismos literales.
Recommendation:
1. Adjuntar el diff de `supabase.ts`.
2. Garantizar que `createClient` y `crearFetchCrm` usen la misma constante para la URL y para la clave.
3. Si había un fetch previo, componerlo (`enviar = fetchPrevio`) en lugar de reemplazarlo.
4. Añadir un test que importe el cliente real de `supabase.ts` y verifique el bloqueo.

[P2] El ledger no es verificable
File:
`supabase/migrations/MIGRACIONES.md` (modificado; no se adjuntó)
Problem:
El punto 8 del checklist (fila nueva con estado honesto) no se puede comprobar. Solo tengo la afirmación «PREPARADA».
Recommendation:
Adjuntar el hunk. Debe mostrar:
- las dos filas con estado PREPARADA o no aplicada;
- el gate HTTP en NOT RUN;
- el bloqueo del replay de `banco-f7`;
- la nota de que la versión real del ledger se confirma tras el merge.

[P3] El preflight de F7 deja pasar `ola` NULL
File:
`20261014001044_crm_f7_redeclarar_huella_metricas_cartera.sql`
Lines:
42
Evidence:
`v_estado <> 'cerrada_permanente' or v_ola <> 'F7.1'`. Si `v_ola` es NULL, la expresión queda `false OR NULL = NULL` y el `if` no entra. Es el mismo patrón NULL que Codex ya corrigió en el postflight (línea 155).
Recommendation:
Usar `v_ola is distinct from 'F7.1'`.

[P3] La foto «solo se movieron dos campos» usa una lista fija de columnas
File:
Mismo archivo
Lines:
189–200
Problem:
Una columna que se añada después a `f7_piezas_en_observacion` no se compararía. La lista tampoco cubre columnas que puedan existir hoy y no aparecen en ella (por ejemplo, timestamps de alta).
Recommendation:
Comparar `to_jsonb(a) - 'huella_md5' - 'nota' = to_jsonb(b) - 'huella_md5' - 'nota'`.

[P3] El join del preflight omite las piezas cuya función ya no existe
File:
Mismo archivo
Lines:
73–80
Evidence:
El `join pg_proc ... on p.oid = to_regprocedure(o.firma)` es inner, así que una pieza cuya función se borró queda excluida.
Impact:
Es bajo: el postflight (a), en las líneas 154–157, exige `assert_f7_piezas_cerradas()` en OK, y cualquier otra causa de rojo aborta la transacción. Pero el mensaje del preflight, que promete detectar «otra deriva», es más estrecho de lo que dice.
Recommendation:
Usar `left join` y tratar `p.oid is null` como deriva. Otra opción es documentar que el postflight es la red real.

[P3] El postflight de SLA no fija la definición resultante
File:
`20261014001346_crm_sla_agrupar_tareas_por_lead.sql`, bloque `$post$`
Problem:
Compara owner, ACL, config, secdef, volatilidad y paralelismo, pero no comprueba `md5(pg_get_functiondef)` contra el valor ensayado (`0abdf…`). Tampoco `proleakproof` ni `procost`.
Recommendation:
Añadir la huella esperada de la nueva definición. Así la migración prueba que instaló exactamente lo que se ensayó, igual que hace el preflight.

TEST GAPS:
- **F7, rama «vigilante ya VERDE»** (líneas 95/98): no está ejercitada. El caso «rechaza repetición» falla antes, en la línea 46.
- **F7, rama «rojo por OTRA causa»** (líneas 99–100): no está ejercitada. Tampoco el caso «otra pieza con huella/ACL derivada» (líneas 81–83).
- **SLA:** el oráculo debería cubrir explícitamente cuatro casos, y no se muestra si los fixtures los incluyen:
  - leads sin tareas (left join a NULL);
  - tareas con `vence_en` infinito o NULL;
  - empates de `vence_en` resueltos por `tarea_id`;
  - tareas solo con `motivo_dato` no nulo.
- **Transporte:**
  - integración con el cliente real de `supabase.ts` (ver P1);
  - `Request` con cabeceras sobrescritas por `init`;
  - HEAD/`count`;
  - formato de clave `sb_publishable_…`;
  - cómo reacciona la UI ante `CRM_SESSION_UNAVAILABLE` (que haya mensaje, sin bucle de reintentos visibles).
- **Matriz HTTP `test-rls.mjs`:** NOT RUN. Es un gate obligatorio antes del merge, no opcional.

ARCHITECTURE RISKS:
- Las guardas con `md5(pg_get_functiondef)` fijo dependen del formato de la versión de Postgres y del camino de replay. El fallo de `banco-f7` (`F2.b b4 … no es el texto vivo esperado`) es precisamente esta clase de fragilidad. Ambas migraciones nuevas añaden dos anclas más del mismo tipo: `67cdc767…` y `12749d60…`. Hay que verificarlas en la rama Supabase real, no solo en el banco Docker.
- `tareas_agrupadas` construye un `jsonb_agg` completo por lead para luego tomar `->0`. Es un patrón heredado y aceptable con el volumen medido (6.860 tareas). Si la cartera global crece, `DISTINCT ON (lead_id) … ORDER BY vence_en, tarea_id` sería más barato.

SECURITY RISKS:
- **Sin hallazgos RLS en el SQL revisado.** Verifiqué:
  - no se crean tablas, policies ni DELETE;
  - no hay statements sobre `public`;
  - no cambian grants, y ambos pre/postflights fijan la ACL `{postgres=X/postgres}`;
  - el owner sigue siendo `postgres`;
  - la atribución de la línea 118 queda reactivada y probada con un rebote real (líneas 165–185);
  - `tareas_agrupadas` lee el mismo CTE `tareas`, ya acotado por `p_lead_ids/p_global/p_visibles`, así que no amplía el alcance entre roles;
  - los 44 pares de paridad, con 10 actores y sin identidad, respaldan esto, aunque no equivalen a HTTP.
- **Transporte:** solo reduce tráfico y no sustituye la autorización del servidor. Según la evidencia, `anon` no tiene USAGE sobre `crm`, así que bloquear las llamadas anónimas al perfil `crm` no rompe ningún flujo anónimo legítimo. Las rutas `/functions/v1/` y `/storage/v1/` quedan fuera de la guarda. Esto es coherente con el alcance, pero conviene documentarlo.

REGRESSION RISKS:
- Si `supabase.ts` reemplaza un fetch personalizado previo, se pierde su comportamiento (P1).
- Si el código de la app detecta la pérdida de sesión por códigos concretos (`PGRST301`, «JWT expired») para redirigir al login, el nuevo código `CRM_SESSION_UNAVAILABLE` no lo activará. Es una hipótesis: no vi ese código.
- La migración SLA ejecuta cuatro asserts en producción bajo `statement_timeout = 60s`. Si exceden ese tiempo, la migración se revierte entera, lo cual es seguro, pero bloquea el despliegue.
- No se detectó que F7 enmascare una deriva previa: el postflight exige el assert F7 completo en OK. La deriva del guardián analítico general queda fuera, y está declarada de forma honesta.

RECOMMENDED NEXT ACTIONS:
1. Adjuntar los diffs de `app/src/lib/supabase.ts` y `MIGRACIONES.md`. Confirmar que la URL y la clave son la misma constante en `createClient` y en `crearFetchCrm`, y que se compone el fetch previo si existía.
2. Aplicar los endurecimientos menores:
   - `is distinct from` en F7 línea 42;
   - comparación por `to_jsonb` en (b2);
   - huella de la definición nueva en el postflight de SLA.
3. Añadir los tests de las ramas F7 «VERDE» y «otra causa», y los casos límite del oráculo SLA.
4. Antes del merge, mantener la secuencia: resolver el replay de `banco-f7` → ensayar ambas migraciones en la rama → `test-rls.mjs` → advisors. El frontend solo se publica vía `$release-crm` humano.

CONFIDENCE:
MEDIUM. Es alta sobre la lógica SQL adjunta y baja sobre la integración del frontend y el ledger, por la evidencia que falta.
