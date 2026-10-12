# Segunda revisión del PR #231 — 09/10/2026

Cabeza revisada: `61444d6ab1edc638a712118e509945cea9c6bf29`. Base: `0f619b024be93f646742e299bfc7c273dbfdda43`. Revisados los commits nuevos `ea0cbbac` y `61444d6a`. Ocho archivos, todos de documentación; ningún cambio de producto ni migración.

## VERDICT: CHANGES_REQUESTED — una corrección operativa y una aclaración menor en la guía nueva

Los dos P2 de la revisión anterior quedan resueltos: retoma histórica inequívoca con estado vigente y consulta de cierre incorporada. El avance **44/102 tareas, 2/8 fases** está respaldado por las evidencias existentes. F4.3.2 (baja/atribución) y F4.4.1 (dos pestañas) siguen abiertas correctamente. No repetir P1–P15 ni la consulta productiva ya acreditada.

## FINDINGS

### P2 — La receta para una clave inválida intenta rotar una asignación cerrada

`CRM-Avance-Corp/docs/gestion-diaria/piloto-telefonia/SOPORTE.md:65` agrupa «se rotó» y «se cerró» y manda siempre a Gerencia rotar, conservar la cola y reenviarla con la clave nueva. Para una asignación cerrada ese procedimiento no existe: solo las vigentes tienen botón Rotar (`app/src/screens/config-celulares.tsx:163`); el historial no lo tiene (`:195–214`). `private.celular_rotar_credencial`, en `supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql:592–598`, exige asignación vigente y analista activo; devuelve 22023 si no existe o está de baja.

Impacto: soporte queda atascado siguiendo la guía en un cierre real. Si ya hay otra asignación con la misma etiqueta, conservar y reenviar la cola anterior puede atribuir llamadas al analista nuevo; la propia guía §3.4 explica ese riesgo.

Corrección concreta de esa fila:
- Si fue una rotación y sigue el mismo analista activo: instalar la clave vigente; si no se conservó, Gerencia puede rotar de nuevo. Mantener la cola y poner `ultimo_latido=0`.
- Si fue cierre, extravío, reemplazo o baja: remitir a §3.3–§3.5; no indicar rotación de la asignación cerrada ni reenvío de la cola anterior a otra persona.

Es una corrección de texto, sin ampliar permisos ni tocar SQL.

### P3 — La guía ofrece a Supervisión una pantalla que solo admite Gerencia

`SOPORTE.md:23` dice «gerencia ve todos; supervisión, los de su equipo». `app/src/lib/vistas.ts:96` permite `config-celulares` únicamente a Gerencia; el contrato de pruebas de `app/src/lib/vistas.test.ts:190–196` rechaza explícitamente Supervisión, incluso con rol portal superadmin. Cambiar el encabezado a «Configuración › Celulares (solo Gerencia)» y que Supervisión solicite esa comprobación a Gerencia. No abrir la pantalla a otros roles para adaptar el código al documento.

## Limpieza menor en el mismo commit

El título/cuerpo del PR todavía dicen 37/102 y piden la consulta ya hecha. `HANDOFF-2026-10-09.md:17–18` dice que llegó a main, pero el PR continúa abierto en borrador. En `SEGUIMIENTO.md`, algunas celdas antiguas «Falta» todavía piden repetir P1–P15/P15 y el alta de C1, aunque H4 y el resumen ya están corregidos. Alinear con el estado actual; para F4.3.2 conservar solo baja/atribución como pendientes. No convertir esta limpieza en nuevas pruebas.

## Verificación

- PASS: `git diff --check` sobre base...cabeza.
- PASS: JSON válido; 102 IDs únicos de tareas; las 44 casillas coinciden con `estado.json`.
- PASS: regeneración aislada de PLAN.md y AVANCE.md; ambos idénticos byte a byte, 44/102 y 2/8.
- PASS: rutas de la guía comprobadas, etiquetas contrastadas con UI, macro y runbook; diferencias anteriores sustentadas en código.
- PASS: evidencia documentada de P1–P3, P6/P7 y prueba 6 respalda las casillas nuevas; P9/consulta conservan la comprobación de la revisión anterior.
- P14 físico: se conserva el registro de Jhosep; no se inspeccionó de nuevo la captura ni se repitió la prueba.
- PASS CI de 61444d6a: preflight, app-check, cambios y verify SUCCESS. Supabase Preview omitido por ausencia de SQL.
- Tests/E2E nuevos: NOT RUN, solo documentos. Sin nueva lectura ni mutación productiva.
- LEVEL 1 documental: sin consulta secundaria. Checkout compartido preservado; extracción aislada, sin checkout de la rama.

## NEXT ACTIONS

Un único ajuste documental pequeño. H-WA sigue en PR separado, que Jhosep se ofreció a escribir; H-P5/H-P10 y el resto del piloto siguen abiertos. Los checks de esta cabeza ya terminaron correctamente. Después de corregir la guía y conservar los checks exitosos en la nueva cabeza, recomiendo fusionar #231. Esta revisión no fusiona ni publica. Jev sigue apagado.

CONFIDENCE: alta en los hallazgos y la consistencia documental; aceptación física apoyada en la evidencia ya registrada por Jhosep.

Relacionadas: [[Llamadas desde el celular - revision PR 231 y P9 corroborada (2026-10-09)]], [[Llamadas desde el celular - P9 publicado y consulta de C1 (2026-10-09)]], [[Inicio]].

Comunicación: segunda revisión incorporada al comentario único https://github.com/avanza-digital/avancecorp-crm/pull/231#issuecomment-6085271924 . La primera revisión queda conservada como historial.

## Petición final consolidada — 09/10 12:31 Lima

Miguel pidió analizar todos los cambios realmente necesarios antes de avisar a Jhosep. Revisados conjuntamente los ocho documentos y los contratos de UI, permisos, rotación, cierre y macro. Cabeza sin cambios 61444d6a; PR ya fuera de borrador. Único bloqueo: P2 de SOPORTE.md:65, con texto concreto para separar rotación vigente del mismo analista de cierre/baja. Permiso de pantalla y restos de seguimiento/título son P3 no bloqueantes por sí solos. 44/102 y 2/8 se aceptan; no repetir P1–P15 ni SQL; H-WA y piloto separados.

Comentario único actualizado y verificado: https://github.com/avanza-digital/avancecorp-crm/pull/231#issuecomment-6085271924 . Notificación formal CHANGES_REQUESTED: https://github.com/avanza-digital/avancecorp-crm/pull/231#pullrequestreview-5473323680 (revisión 5473323680, 17:31:38 UTC). Texto completo del pedido: /private/tmp/pr231-rereview-20261009/PEDIDO-FINAL.md.

Turno Jhosep: un commit documental y SHA. Miguel ya autorizó aprobar y fusionar si la nueva cabeza no tiene P0–P2; basta verificar el delta y los checks aplicables. Sin merge/publicación ni mutaciones productivas en esta ronda.

## Cierre — PR #231 fusionado, 09/10 12:44 Lima

## VERDICT: PASS — #231 aprobado y fusionado

Revisé **ba04edf302a75e0b728f13c401ae14ade9388cb1**: el P2 quedó resuelto y también las aclaraciones P3. La guía separa correctamente rotación vigente del mismo analista de cierre/baja, y no permite reenviar una cola anterior con la clave de otra persona. Sin nuevos P0–P2.

- **Aprobación:** https://github.com/avanza-digital/avancecorp-crm/pull/231#pullrequestreview-5473436564 (sustituye mi solicitud de cambios).
- **Fusión normal, sin bypass:** `918a97cb3b7d922ff7f7eadcaa13e23305c142ce`, 09/10/2026 **12:44:08 Lima**.
- **PASS:** preflight, app-check, cambios y verify en ba04edf3; diff sin errores. `estado.json`, PLAN.md y AVANCE.md no cambiaron desde su validación: **44/102 tareas, 2/8 fases**.
- **PASS:** GitHub confirma merged; main de la copia limpia coincide con `avancecorp/main` en 918a97cb y su árbol es idéntico al de ba04edf3 revisado. Checkout compartido preservado.
- PR solo documental: **sin publicación de frontend ni repetición de P1–P15 o de la consulta SQL**. Pruebas locales nuevas de aplicación/E2E: NOT RUN, no corresponden a este delta documental.

**TURNO PARA: Jhosep**, puedes abrir el PR de H-WA que indicaste tener preparado. El resto conserva su seguimiento: H-P5/H-P10, los dos leads de prueba, baja/atribución, dos pestañas, piloto y F4-e. El plan completo aún no está terminado. **Jev sigue apagado.**

CONFIDENCE: HIGH.
