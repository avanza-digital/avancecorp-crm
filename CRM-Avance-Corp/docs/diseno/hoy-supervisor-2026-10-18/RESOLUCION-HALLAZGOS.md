# Resolución de la revisión independiente — fase 5

Codex PRIMARY. Primera revisión Claude: CHANGES_REQUESTED, sin P0/P1 demostrados.

| Hallazgo | Decisión y corrección | Evidencia |
| --- | --- | --- |
| P2 aviso de corte con caché en error | Aceptado. Valoración y aviso se retiran cuando falla Facturación. | `use-resultados-hoy.test.tsx`, caso aviso seguido de error. |
| P2 hipótesis refresco mensual | Confirmado parcialmente: store devuelve false sin marcar flags. La portada captura false/rechazo, comparte su solicitud manual/periódica/cambio de mes y protege su estado contra respuestas de otra sesión. | `datos-supervisor.test.tsx`: seis casos, incluidos reintento, cambio de mes y concurrentes. |
| Coste del refresco | Se mantiene el lector existente, cinco minutos visibles. `store.resincronizarReal` revalida la ficha abierta, equipo/tareas/metas y agrega invalidaciones; no descarga todo el historial. No se crea una fuente alternativa de cifras. El handler de foco ya evita iniciarse con resync en curso; mutaciones pueden exigir otra revalidación. | `store.tsx:1114–1251,1395–1426`; comportamiento previo conservado. |
| P3 TC en cada sondeo | Aceptado. Solo cambio de día o TC caído; no reconsultar TC sano por Actualizar. | `datos-supervisor.test.tsx`. |
| P3 región viva del aviso | Aceptado. Status persistente sin espacio visible; contenido solo con pendientes confirmados. | `supervisor-jornada.test.tsx`, secuencia 0→4→1→0. |
| P3 textos de tareas | Aceptado. Singular/plural y cierre «Cerrar tareas». | Componente y pruebas de interacciones. |
| Chevron del diálogo | Aceptado. Alto y ancho 13 px explícitos. | CSS, sin inspección visual. |
| Integración real de tareas | Se sustituyó el mock de PendientesSupervisor por su componente real; solo se simula el lector de datos. Cubre filtros, refresco y 42501→revalidar. | `supervisor-jornada.test.tsx`. |
| Hipótesis Citas sin intervalo | Descartada: `citas-gerencia.ts:193–205` ya define 60 s, primer plano, foco/reconexión. | Fuente Main vigente. |
| Caché de resumen sin actor | Búsqueda de `crmQueryKeys.resumenCartera` encuentra definición, hook y test de prefijo; no lectores/escritores exactos fuera del hook. | Búsqueda en `app/src` y prueba QueryClient de invalidación. |
| Nuevo hallazgo Codex: venta propia del supervisor omitida en desglose | Corregido al integrar Main: incluye capital/operaciones propios, conserva foto valorada, sin inventar meta/conversión individual. | `jornada-supervisor.test.ts`, variantes legado y valorado, conciliadas con el total oficial. |

Verificación de las correcciones: 37 tests en cuatro archivos PASS, typecheck
PASS. Hubo un fallo del nuevo test por mock incompleto de `usdAPen`: se sustituyó
por mock parcial y se repitieron los cuatro archivos con éxito.

Segunda consulta independiente justificada por evidencia nueva: contrato vigente
de Main para las ventas de supervisores, código del store/TC y correcciones del
refresco que no estaban en el primer expediente. Dictamen PASS (confianza MEDIUM), sin P0/P1/P2 demostrados; ver `REVISION-CLAUDE-INTEGRACION.txt`.

Restricciones: no inspección visual/lector de pantalla ni E2E; no conciliación
productiva. Pruebas DOM/fixtures no acreditan esos recorridos reales.

## Segunda revisión y cierre de Codex

- P3 recuperación externa: aceptado. El fallo queda ligado a las identidades de
  objetivos/cumplimiento consultadas; una nueva foto del store elimina ese fallo
  local, conservando los flags de error oficiales. Prueba fallo→foto nueva PASS.
- P3 descarte al abrir ficha: confirmado, `enlace-sujeto.tsx:19–27` abre el lead.
  Se permite un solo segundo intento ante false. Continúa sin confirmar si ambos
  fallan. Solicitud compartida, desmontaje/cambio de actor retiran su autoridad;
  probado también en StrictMode para evitar una carga indefinida al remontar.
- P3 carga mensual: aceptado. Se anuncia consulta de capital/metas aun cuando
  existan filas de conversión; no se interpreta la carga como ausencia de meta.
- Añadida prueba de render de la fila propia, nombre/rol y «Sin meta individual».
- Hipótesis de redondeo por persona: descartada. `usdAPen` multiplica sin
  redondear; la presentación formatea después y los agregados conservan precisión.
- Test del temporizador no incluido en el segundo expediente: ya había pasado
  en fase 2; repetido en fase 5 y se incluye en el gate integral.
- TC caído: se conserva la advertencia de fuente y el desglose por moneda, sin
  publicar una brecha/porcentaje mixto como completo. Contrato compartido previo.

**Cierre fase 5:** 44 tests / 5 archivos PASS (correcciones), 101 tests / 6
archivos PASS (regresiones Main), lint PASS (11 warnings previos en archivos
ajenos), typecheck PASS y build Main PASS. Se corrigieron errores del banco nuevo
(mock parcial, nombre del hook de prueba y anotación de Promise); ninguna supresión
de checks. Sin defectos aceptados pendientes. Dos consultas Claude completadas;
no se necesita otra para volver a confirmar lo resuelto.
