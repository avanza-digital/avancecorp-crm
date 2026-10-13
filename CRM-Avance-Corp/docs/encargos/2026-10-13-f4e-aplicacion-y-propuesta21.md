# F4-e: aplicación, decisiones y entrega a Jhosep

Miguel reanudó y autorizó completar el trabajo el 13/10/2026. Continúa el PR #255,
ya fusionado. Este encargo cubre el paso 5 de la sección 9 de
[`F4E-CONTRATO.md`](../plans/llamadas-celular/F4E-CONTRATO.md).

## Aplicación y verificación

Estado: **APLICADAS Y REGISTRADAS ambas migraciones el 13/10/2026**,
verificación 15:39 UTC / 10:39 Lima; registradores con veredicto `true`.
Catálogo, propietario, ACL y accesos por rol comprobados en producción.
Proyecto de producción: `dctqcbznekcyxhjujuci` (PortalAvanceCorp).

El banco Supabase local tiene las mismas huellas de las ocho dependencias de
F4-e que producción, incluido el roster real del pulso. Se ejecutó
`CRM_RLS_EXIGE_LLAMADAS_F4E=1 CRM_RLS_EXIGE_LLAMADAS=1 CRM_RLS_EXIGE_LLAMADAS_F4B=1 npm run test:rls -- --llamadas`:
**347/347 PASS**. Este alcance incluye visibilidad, roles, aislamiento y llamadas;
no acredita la matriz global de otros módulos. El nuevo selector evita copias
temporales del gate. Se corrigió su lectura del roster: el pulso entrega
`equipos[].personas[]`, no `personas[]` en la raíz.

El banco reducido completo terminó en **482/482 PASS**, con reversa y registro,
O1–O17 y mutante de la deshecha antigua independiente. La revisión de Claude
dejó dos P2; ambos fueron corregidos y comprobados por Codex.

El EXPLAIN con **20.000 eventos, 18.000 enlaces y 100 días** mostró 2.882–2.976 ms
con la migración original. La causa era repetir `persona_vetada` por cada evento.
La migración adicional `20261013145935` evalúa la contactabilidad una vez por
lead, incluyendo las deshechas antiguas. Resultado: **21,729 / 16,039 / 15,014 ms**,
sin índices nuevos. La migración original `20261012192500` se conserva intacta.
Son mediciones locales con datos sintéticos; no una garantía para cualquier volumen.
El diferencial de siete combinaciones de gerencia, supervisores y equipos sobre
el historial devolvió JSON exactamente igual antes y después.

Evidencia: [`f4e-2026-10-13`](../../supabase/scripts/llamadas-celular/f4e-2026-10-13/).
Banco de rendimiento reproducible, **solo local con seed-demo**, terminado en
ROLLBACK: [`rendimiento-operacion-hoy.sql`](../../supabase/tests/llamadas-celular/rendimiento-operacion-hoy.sql).

Orden: aplicar `20261012192500` → `registrar-operacion-hoy.sql` → aplicar
`20261013145935` → `registrar-operacion-hoy-rendimiento.sql` → `npm run gen:types`.
Es necesario registrar la original antes de sustituir su núcleo: su registrador
verifica la huella original y debe rechazar la nueva.

Reversa: primero `reversa-operacion-hoy-rendimiento.sql`. Restaura el núcleo
original, conserva ACL/atributos y retira su entrada exacta del ledger en la misma
transacción; rechaza otra huella o contenido. Solo entonces podría revertirse la
decimotercera si hiciera falta. No ejecutar reversas para un despliegue normal.

`npm run gen:types`, typecheck, build y lint PASS (lint con 10 avisos previos). La generación
reflejó que `ajuste_anulacion_en_sello`, preparado por el PR #259, todavía no está
en producción: se conserva su declaración de main y se incorpora la firma F4-e
generada. No se modifica ni se despliega la migración de ese otro encargo.

Advisors consultados antes/después, respuestas frescas de 15:39 UTC. Rendimiento
sin avisos nuevos; seguridad añade únicamente la puerta F4-e como DEFINER
ejecutable por authenticated (278 → 279). Es deliberado: valida supervisor/gerencia
internamente, deniega anon/service_role y mantiene el núcleo privado. Los avisos
previos siguen fuera de este encargo. [Criterio y remediación de Supabase](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

## Dos decisiones confirmadas por Miguel

1. La retención procede de `crm.llamadas_celular_politica.dias_retencion_sin_resolver`
   (**30 días actualmente**). No es un 30 fijo. El texto visible también sigue la
   política. Las deshechas enlazadas siguen sin tope, por separado.
2. **Ningún porcentaje viaja en la respuesta.** La pantalla los calcula dentro
   de la misma cohorte: `llamadas_hoy.con_resultado / llamadas_hoy.total` y
   `resultados_hoy.al_colgar / resultados_hoy.total`. No mezclar los dos relojes;
   recalcular desde las sumas al agrupar y resolver explícitamente divisor cero.

No cambian las decisiones D1–D5 ni se necesita otra modificación funcional.

## Responsabilidad de las pantallas

**Jhosep y su agente hacen las pantallas de F4-e en un PR aparte**, una vez
consten aplicadas ambas migraciones y estén publicados los tipos generados:
tercera pestaña de «Toda la operación hoy» (gerencia) y bloque «Su celular» de
«Mi equipo hoy» (supervisión). Esta entrega no implementa esas pantallas.
Conservar los rótulos de los tres relojes, «—» para `sin_dato`, el ámbito y
las reglas de porcentajes del contrato. Jhosep actualiza su plan y sus avances.

## Propuesta #21: opinión técnica y decisiones a–e

**CON REPAROS** sobre construirla solo en pantalla sobre la v5 actual. No bloquea F4-e.
Referencia: [`análisis de la propuesta`](2026-10-12-codex-cierre-en-lote-propuesta-21.md).
Son recomendaciones para cerrar el contrato de #21, no autorización para implementarla.

| Decisión | Recomendación |
| --- | --- |
| a. Hora de la gestión | Hora de la confirmación, sin retrofechar. La hora real sigue en el evento. |
| b. Alcance | Solo `no_contesto` y estados `no_atendida`, `rechazada` o `cancelada`; excluir `conectada` y `desconocido`. No inferirlo de duración cero. |
| c. Parcial o todo/nada | Parcial, serial, con estado por fila y el mismo `p_operacion_id` al reintentar. Hace falta garantizar en servidor que registrar y consumir una pendiente concreta sea atómico e idempotente frente a otra pestaña. No exige necesariamente un lote entero atómico. |
| d. Descartar «No responde» | Excluirlo de la primera versión del lote. Las llamadas antiguas registradas hoy podrían cumplir artificialmente el orden de intentos posterior a una conversación. |
| e. Prioridad | Primero las pantallas F4-e; #21 queda separado, después de resolver captura técnica e idempotencia. #19/#20 conservan su prioridad acordada con Jhosep. |

Hechos que cambian el análisis:

- **Carrera real, no resuelta con releer.** `registrar_llamada_v5` guarda primero
  la actividad y después intenta enlazar; un enlace imposible devuelve
  `no_enlazado` sin deshacer la gestión. Una segunda pestaña puede guardar una
  gestión adicional para una llamada ya consumida. Releer antes de enviar no
  cierra ese intervalo. Evidencia: migración `20261005155914`, puerta v5 y
  `llamada_celular_enlazar_exacto`; fragmento A/F del análisis enlazado.
- **Dos relojes también afectan al descarte.** La v4 evalúa los intentos con
  `actividades.creado_en` después de la última conversación
  (`20260921153654`, líneas 283–299). Registrar ahora llamadas antiguas no prueba
  que se haya vuelto a intentar después de hablar con el lead.
- **Utilidad medida:** en la comprobación final de 13/10 15:39 UTC había 46 eventos salientes en producción, los
  46 con `estado_tecnico='desconocido'`: cero elegibles para este alcance en esa
  fotografía. Validar lo que captura MacroDroid antes de construir #21; no
  reclasificar esos registros por duración ni ampliar el alcance silenciosamente.
- **Una tarea y una confirmación pendientes:** enviar `p_tarea_id` solo una vez,
  y `p_siguiente` en la operación designada. Si falla antes de la última fila,
  la pantalla debe mostrar qué quedó pendiente, incluida la tarea; no anunciar
  cierre total. No iniciar otra operación con un id nuevo ante una respuesta
  desconocida. Mostrar por separado gestión guardada y enlace confirmado.

De nuestro lado siguen las pruebas de MacroDroid de C1 el **15/10**, y C2/C3
cuando estén disponibles. La aprobación y el trámite legal ya están resueltos,
según Miguel; no se crea otro trámite dentro del sistema.
