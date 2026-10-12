# Revisión PR 231 — 09/10/2026

Repositorio avanza-digital/avancecorp-crm. Base 0f619b024be93f646742e299bfc7c273dbfdda43. Primera cabeza bcb9253a; durante la revisión se incorporó 72938df0a3b47ea4188bbe0e53e57b22152ca7b7 y se verificó su delta. Sigue draft. Solo 6 documentos; cero código/migraciones. Review local, sin comentario ni revisión formal enviados a GitHub, sin fusión.

## VERDICT: CHANGES_REQUESTED documental acotado

El avance técnico está acreditado; no repetir P1–P15. Un commit para actualizar la retoma y el cierre ya confirmado. No se necesita otra auditoría general de código para estos documentos. LEVEL 1 documental, sin secondary review.

### P2 — Retoma publicada con acciones ya terminadas

HANDOFF-2026-10-09.md:21–34 declara P9 parcial, L3 sin leer y #227/#228 abiertos. Líneas 57–80 ordenan esperar publicación y volver a ejecutar pruebas. El encabezado dice que sustituye al handoff anterior, y §5 lo recomienda como arranque. Aunque lleva la fecha de su redacción inicial, necesita una actualización vigente o un aviso inequívoco de archivo histórico y enlace al estado actual. SEGUIMIENTO.md:63 también sigue pendiente de P9/L3.

### P2 — Consulta de cierre acreditada sigue presentada como pendiente

estado.json:4/12/35 y REGISTRO.md:193 siguen solicitando la consulta. Ya fue publicada en el comentario consolidado del #227, https://github.com/avanza-digital/avancecorp-crm/pull/227#issuecomment-6070626325 . En esta revisión se repitió solo la lectura necesaria y se amplió con el nuevo P9:

| Intervalo Lima | Recepciones | Eventos | Enlaces |
|---|---:|---:|---:|
| 07/10 19:15–08/10 17:00 | 19 | 18 | 18 |
| 09/10 11:10–11:30 (P9) | 1 | 1 | 1 |

0 actividades enlazadas dos veces; 0 eventos enlazados dos veces. assert_gestion_diaria_resultado_v4: OK. P9: ocurrió 09/10 11:14:38 Lima; actividad corregida creada 11:21:08.827187, resultado volver_a_llamar, atención registrado, un enlace, via al_colgar. La diferencia 19/18 del primer intervalo corresponde a P13 sin identificar según la comprobación previa y política guardar_sin_identificar=false. Sin teléfonos ni credenciales en el resultado.

Recomendación: incorporar la evidencia y retirar el bloqueo documental de esa consulta; marcar solo las tareas cuyo alcance completo está acreditado. F4.3.2 todavía enumera baja y atribución histórica como pendientes; no cerrarla automáticamente por P9/P14. Mantener H-P5/H-P10/H-WA, cohortes y piloto como trabajo abierto.

## H-WA confirmado, preexistente y fuera del código modificado

app/src/screens/gestion-diaria/analista.tsx:342–363 toma la tarea de la fila local o por obtenerTareaParaRevision sin discriminar su tipo y la pasa al formulario. app/src/components/gestion-diaria/registrar-resultado.tsx:203/446 ofrece y envía el cierre. app/src/lib/store.tsx:3184 rechaza cualquier tipo distinto de llamada; también lo protege el SQL de registrar llamada. Concuerda con lo observado por Jhosep.

P2 funcional: corregir en un PR de código separado. Pasar únicamente la tarea de llamada pendiente de esa fila; si es WhatsApp/reunión, registrar llamada sin cerrarla ni sustituirla por otra tarea del lead. Cubrir ambos caminos de carga (local/remoto) y la llamada válida que debe seguir cerrándose. La validación del store/servidor se conserva. No bloquear la recepción del registro físico ni repetir el conjunto de pruebas anteriores para este fix.

La vía al_colgar retenida al corregir es consistente con supabase/migrations/20261005182227_crm_llamadas_celular_enlace_sin_ciclo.sql:113: mueve actividad_id y enlazado_por, no via. No se exige cambio de esquema para esa observación.

## Verificación

- PASS JSON y git diff --check.
- PASS regeneración PLAN/AVANCE en copia aislada, byte a byte iguales.
- 34/102 tareas; F3.3.3 cerrada con P1–P3 y respaldo manual ya documentados. No equivale al cierre de F3/F4.
- PASS comprobación SQL de P9 y sello; solo lectura.
- P14-L3: evidencia física documentada por Jhosep; no repetida por Codex ni captura original inspeccionada aquí.
- CI primera cabeza: preflight/app-check/verify SUCCESS. En 72938df0: preflight SUCCESS, app-check en curso al consultar; no se atribuye ese check como PASS.
- Tests de aplicación/E2E nuevos: NOT RUN; PR solo documental. Se conservan las verificaciones anteriores.
- Checkout compartido preservado; extracción de documentos en /private/tmp/pr231-review-20261009.

CONFIDENCE: alta en cierre de P9, consulta y H-WA; P14 físico depende del registro de Jhosep.

Relacionadas: [[Llamadas desde el celular - P9 publicado y consulta de C1 (2026-10-09)]], [[Llamadas desde el celular - PR 227 y 228 fusionados (2026-10-09)]], [[Inicio]].
