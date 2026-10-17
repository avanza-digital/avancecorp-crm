VERDICT:
CHANGES_REQUESTED

SUMMARY:
No encontré P0 ni P1. El criterio central está bien implementado y es coherente entre el frontend y el SQL:

- **Mes de venta:** sale de `fecha_comercial`, no de `mes_resultado`.
- **Auditoría:** `convertido_en` se conserva y solo actúa como tope de "conocido al corte".
- **Vínculo con entrevistas:** se compara por día de Lima y el mismo día es compatible.
- **Testigo raíz:** sigue intacto y el nuevo va en `comercial`.
- **Testigo en el frontend:** se evalúa sobre el cálculo mensual sin filtros, así que el bloqueo sobrevive a los filtros.

Los hallazgos son P2/P3. Hay un riesgo de orden de despliegue que debe quedar escrito, una asimetría en cómo se trata la ambigüedad según el rol, dos fuentes de `fecha_comercial` que pueden divergir y algunos huecos de test. Ninguno impide entregar esto como candidato.

FINDINGS:

[P2] El frontend nuevo falla por completo contra el servidor anterior: el orden de despliegue es obligatorio
File: `app/src/data/citas-gerencia.ts` (`ConsultaCitasSchema` v2, `criterio_depositos: v.literal('fecha_comercial')`, `fecha_comercial` sin `v.optional`); `app/src/lib/gestion-citas.ts` (`TestigoComercialCitasSchema` exige `comercial`)
Problem: Antes de que la migración se aplique, cualquier respuesta versión 2 se rechaza. Fallan tanto la falta de `criterio_depositos` como un `testigo` sin `comercial`.
Evidence: El test `rechaza el servidor anterior aunque la lista de conversiones esté vacía` confirma que el rechazo es intencionado (`'incompleta'`).
Impact: Si el frontend se publica antes que la migración (o la migración se revierte con el frontend nuevo ya publicado), la pantalla de Citas queda caída para gerencia y supervisores. La dirección contraria es segura: el frontend antiguo contra el servidor nuevo funciona porque el cambio es aditivo, valibot descarta claves desconocidas y la raíz del testigo es exacta.
Recommendation: Documentar en el plan de publicación el orden "migración TC → migración fecha comercial → frontend", y la reversa inversa ("frontend → migración"). La evidencia solo menciona el orden TC → nuestra migración, no el orden DB → frontend.

[P3] La ambigüedad se evalúa después de filtrar por visibilidad: supervisor y gerencia pueden discrepar
File: `supabase/migrations/20261017043000_crm_citas_fecha_comercial.sql`, líneas 65-73 (CTE `comerciales`)
Evidence: `where ... and (v_rol='gerencia' or c.analista_id=any(v_visibles)) group by c.lead_id having count(*)=1`. El testigo (líneas 207-209) excluye un lead con más de un `cierre` sin filtrar por rol.
Impact: Hoy no se materializa porque la acreditación tiene `lead_id` único. El residuo concreto aparece si un lead llega a tener dos cierres, uno de un equipo visible y otro ajeno. El supervisor recibiría una fecha comercial "única" mientras gerencia y el testigo la tratan como ambigua (null). Eso contradice la regla de "no elegir fecha arbitraria".
Recommendation: Calcular la unicidad antes del filtro de rol. Por ejemplo, `having count(*)=1 and bool_or(v_rol='gerencia' or c.analista_id=any(v_visibles))`. El coste es una línea y no cambia el hash del núcleo.

[P3] Hay dos fuentes de `fecha_comercial` por lead con reglas distintas
File: migración, ancla p1 (raíz `conversiones`: `tipo='cierre'`, no anulado, `count=1`) y ancla p2 (`gestion.conversiones`: `(c.fecha_numerador ...)::date` de la fila `c` que ya usaba el lector de gestión)
Evidence: La raíz alimenta `adaptarCitas` (cerrado/seguimiento) y `adaptarDepositos` (recuperación). `gestion.conversiones` alimenta `calcularAvanceCitas`. La evidencia no muestra que la fila `c` de p2 esté restringida a `tipo='cierre'` ni que aplique la exclusión por ambigüedad. En el fixture, el lead 206 tiene `analista_id: null` y `fecha_comercial: null`, lo que es coherente pero no lo demuestra.
Impact: Si la fila `c` de gestión puede ser una renovación, upgrade o cooperativa, el avance contaría una venta que el testigo comercial excluye. Ese caso se detectaría (testigo que no cuadra → bloqueo), pero la recuperación y el panel de avance quedarían con criterios distintos.
Recommendation: Confirmar con el cuerpo del lector de gestión que `c` es el cierre del núcleo. Añadir una aserción en `prueba.sql` dentro del savepoint `renovacion`: el lead 201 debe tener `fecha_comercial` null (o no aparecer) tanto en la raíz como en `gestion.conversiones`.

[P3] En la versión 2 se ignora `cierre_posterior` del servidor
File: `app/src/data/citas-gerencia.ts`, `adaptarCitas` (`cierreCompatible`)
Evidence: El fixture SQL tiene el lead 201 con `cierre_posterior: false`, asistencia el 01/09 a las 23:59 en Lima y `fecha_comercial` 2026-09-01. Con el cambio, el frontend lo marcará `cerrado: true`. Además, para citas no realizadas se usa `vence_en` como referencia, de modo que una inasistencia previa a la venta también queda `cerrado: true`.
Impact: Es un cambio deliberado, pero `cierre_posterior` deja de tener consumidor en v2 y su semántica (posible atribución o anulación) se reemplaza solo por la comparación de fechas. Esto es una hipótesis: no tengo el cuerpo SQL de `cierre_posterior` para confirmar que no aporta otra condición.
Recommendation: Confirmar que `cierre_posterior` solo codificaba orden temporal. Si es así, documentarlo junto a `cierreCompatible`. Si no, combinar ambas condiciones.

[P3] Postflight del censo: `EXCEPT` sin `ALL`
File: migración, líneas 366-367
Evidence: `except` sin `all` compara conjuntos, no multiconjuntos.
Impact: Si `contadores_crudos_leads_citas()` puede devolver filas duplicadas, aparecer o desaparecer un duplicado idéntico no se detectaría.
Recommendation: Usar `except all` en ambos sentidos.

[P3] El orden de depósitos por movimiento pasó de instante a día
File: `app/src/components/citas/depositos.ts` (`dia(...)` en `sort`)
Impact: Los depósitos con `fuente='movimiento'` del mismo día ahora se ordenan por `id`, no por hora. Es solo un cambio visual en la ficha: la fecha "desde" no cambia.
Recommendation: Usar el instante como desempate para `movimiento`, o aceptarlo de forma explícita.

TEST GAPS:
- El caso de renovación de `prueba.sql` solo comprueba `testigo.comercial.clientes_periodo=3`. No verifica `fecha_comercial` en la raíz ni en `gestion.conversiones`, ni que el frontend cuadre sobre ese payload.
- No hay test con un supervisor y un lead con fuente ambigua, que cubriría el P3 de visibilidad.
- No hay evidencia de que `FechaSchema` exija exactamente el formato `YYYY-MM-DD`. Las comparaciones léxicas de `ventaComercialDelMes`, `entrevistaCompatibleConVenta` y el `sort` dependen de ese formato.
- La aserción `expect(csv).toContain('"1","100"')` del E2E es débil. Conviene comprobar la fila completa del analista, incluida la columna nueva al final.
- No hay medición de latencia. `citas_testigo_mes` ahora ejecuta dos veces el CTE `identidad` y `conversion_cierres('-infinity', ...)`, y el lector añade otra llamada al núcleo.

ARCHITECTURE RISKS:
- La migración parchea con `replace()` sobre `pg_get_functiondef`. Está bien protegida (hash de preflight, cada ancla aparece exactamente una vez, comprobación de atributos), pero obliga a reconciliar si TC u otra tarea toca esos cuerpos antes de publicar.
- `citas_testigo_mes` duplica casi entero el bloque CTE para los dos testigos. Es aceptable para mantener la raíz exacta, pero conviene planificar cuándo retirar el testigo heredado.

SECURITY RISKS:
- No encontré regresiones. La puerta de rol del testigo se conserva y el supervisor no recibe testigo ni cierres de otro equipo (evidencia PASS). La matriz de vendedor, coordinación, inactivo y anónimo está denegada, y el postflight revisa `anon` y los atributos y ACL. El escape de inyección en el CSV se mantiene.
- Los checks remotos de RLS/advisors y `gate:realidad` no se ejecutaron. Así debe constar en la entrega.

REGRESSION RISKS:
- Cambio funcional esperado: las cifras de septiembre y octubre cambian frente a lo publicado (17 ventas pasan de octubre a septiembre). Los clientes antiguos seguirán mostrando el criterio anterior hasta que se actualicen.
- Con `mes_resultado='asignacion'`, los clientes del periodo dejan de seguir la cohorte. Es lo pedido; el test unitario y el savepoint SQL lo cubren.

RECOMMENDED NEXT ACTIONS:
1. Documentar el orden DB → frontend en la publicación y el orden inverso en la reversa.
2. Mover la comprobación de unicidad antes del filtro de visibilidad en `comerciales`, y cambiar a `except all` en el postflight.
3. Confirmar que la fila `c` de `gestion.conversiones` es el cierre del núcleo, y añadir las aserciones del caso de renovación en la raíz y en `gestion`.
4. Medir el tiempo de `citas_gerencia_consulta_fn` antes y después en el banco fiel.

CONFIDENCE:
MEDIUM. El diff y la evidencia SQL son suficientes para el criterio de fechas, el testigo y la compatibilidad. Faltan los cuerpos completos del lector de gestión, el origen de `cierre_posterior` y la definición de `FechaSchema`.

Nota: esta sesión estaba en modo plan, pero el protocolo de revisor secundario prohíbe crear archivos. Por eso entrego el review directamente aquí, sin plan ni herramientas.
