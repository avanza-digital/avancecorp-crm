# Cierre de gestiones — evaluación de Claude por Codex

Codex PRIMARY; Claude SECONDARY_REVIEWER por el wrapper aislado. Riesgo LEVEL 3 por permisos, integridad y migraciones. Dos dictámenes válidos: arquitectura e implementación, ambos **CHANGES_REQUESTED**. El envío final tuvo un reintento técnico porque la primera respuesta no contenía VERDICT válido; no se pidió aprobación reiterada ni una tercera revisión. El dictamen final no se renombra a PASS: los ajustes y su verificación corresponden a Codex.

Respuesta íntegra: `app/artifacts/review-gestiones-clientes-final-respuesta.txt`. Evidencia enviada: `review-gestiones-clientes-final-acotado.txt`. [Estado de implementación](2026-10-06-cierre-gestiones-clientes.md).

## Hallazgos y decisiones

| Observación | Evaluación y acción |
| --- | --- |
| P2: metadata NULL puede quitar llamadas de leads | La columna `crm.actividades.metadata` es NOT NULL: hipótesis no reproducible en el esquema. Se aplicó además el predicado defensivo `IS NOT TRUE`. No se simula que una inserción NULL sea un caso válido. |
| P2: tipos de perfiles desconocidos rompen la página | El CHECK limita los siete tipos y todos pertenecen al catálogo del frontend. `test-revision.sql` compara el CHECK con el módulo real de UI. Se conserva el tipo histórico; no se cambia silenciosamente a nota. |
| P2: nombre vacío rompe el contrato v2 | Aceptado. Leads y perfiles autorizados con nombre vacío muestran «Sin nombre», preservando UUID y autorización. Un nombre ausente por falta de acceso sigue redactado, con IDs y detalle nulos. Caso SQL de lead histórico vacío PASS. |
| P2: detalle y F5 costosos antes de paginar/contar | Aceptado. Cada fuente se limita antes de presentar detalles. El resumen usa las mismas reglas de clasificación sin devolver identidad, detalle ni metadata, y agrupa antes de resolver nombres de autores. Retorno temprano para sujetos vacíos tras autorizar. Sonda que bloquea F5 demuestra que conteos y páginas solo de leads no lo consultan. Estrés de 90.000 eventos PASS. |
| P2: writer podría concatenar detalle NULL antes de asignarlo | Descartado con el cuerpo base guardado por MD5: asigna detalle antes del ancla y exige 3–2000 caracteres en todas las acciones salvo confirmar. Cierres heredados cancelada/no_show sin detalle se rechazan sin cierre parcial (prueba SQL). No se relaja el contrato para aceptar un caso inválido. La guarda inicial de huella y comparación final de prosrc permanecen. |
| P3: sujeto doble o cliente NULL abortaría página | Restricciones existentes: tarea tiene exactamente un sujeto mediante `num_nonnulls`; actividades_cliente.cliente_id es NOT NULL. Se conserva el fallo cerrado ante una referencia incoherente, sin adivinar su dueño. |
| P3: deduplicación con F6 apagada | Se conserva por privacidad: un espejo de un cierre F6 no debe convertirse en una vía heredada para mostrarlo al apagar F6. Prueba con espejo real y evento de perfil independiente: el primero desaparece, el segundo permanece. |
| P3: falta índice para deduplicar por tarea | Aceptado. Índice parcial `inversionista_gestiones_cierre_tarea_idx` sobre tarea_id para tipo=cierre. |
| P3: autores vacíos en Citas | Aceptado: mismo guardado `enabled` que el resumen. El caller actual solo usa un analista o ningún filtro. |
| P3: helper escalar de identidad | Se conserva como adaptador a la resolución por lotes, usado por las pruebas de autorización. Invoca la misma autorización; no abre un acceso alternativo a datos. No se expone el esquema private. |
| P3: resultado_origen declarado en acciones administrativas | No cambia conteos ni presencia: el lector operativo solo toma tipo=cierre y recalcula la clasificación. `declarado` en ese metadata existente describe el estado enviado; no acredita por sí solo contacto ni entrevista. No se utiliza como criterio de métricas. |
| P3: estado actual de tarea en historia de perfil | Se conserva el contrato legado: actividades_cliente no guarda estado ni resultado estructurado en metadata; el cierre atómico existente guarda resultado comercial en la tarea. Cambiar a completada toda actividad fabricaría gestión realizada para notas de no-show/cancelación. No se añade una reapertura retroactiva en esta tarea. |
| P3: revalidación retira páginas de clientes cada minuto | Decisión de privacidad conservada. Los IDs/detalles dependen del acceso actual tras reasignación; no se mantienen indefinidamente páginas acumuladas. CSV informa que exporta filas cargadas. Limitación UX documentada: vuelve a la primera página al revalidar clientes acumulados. |
| P3: toast de una recuperación usa acción actual | Corregido: recuperación muestra una confirmación neutra de envío y agenda actualizada; no afirma entrevista o confirmación basándose en estado local reiniciado. |

## Evidencia y ajustes propios adicionales

- La cola de citas sin responsable vuelve a gerencia sin filtro de analista, conservando la restricción para supervisor. SQL y contrato nullable frontend PASS.
- La clasificación de números errados y persona equivocada se alineó al catálogo de leads (`llamada_no_contestada`); contacto permanece falso. El banco obtiene las siete opciones reales de `resultado-llamada.ts` y los cinco resultados reales de `tipos.ts` y ejecuta cada cierre.
- Se completó el acceso a **Cerrar tarea** en la ficha heredada `ClienteFicha`, además de la neutral. Reutiliza `CerrarTareaDialog`; bloquea con permisos/datos desactualizados. Mantiene la tarea elegida durante el guardado optimista para conservar el formulario si la RPC rechaza. Unitarios y dos E2E Docker de llamada/cita PASS.
- El primer ensayo E2E de perfil encontró una incoherencia del fixture: sesión de analista pero UID como gerente en el roster. La pantalla bloqueó correctamente las acciones. Se corrigió el roster del escenario; la ejecución final pasó sin retry, incluido rechazo/reintento de RPC y un solo historial.
- Tipos de las cinco RPC verificados; las firmas públicas no cambiaron con la optimización. Los demás tipos modificados por otras tareas se conservaron.
- Cache `gestionesClientesKeys.raiz` está bajo `gestionDiariaKeys.raiz()`. Cierres de Agenda y postventa invalidan ambos; los E2E cubren salida de pendientes y actualización de historial/registro/resumen.
- Cursor conserva microsegundos y separa fuente+UUID; pruebas de empate y de paginación PASS. Los roles nuevos siguen los admitidos por las listas operativas existentes. El árbol incluye al actor supervisor/gerente.

## Rendimiento y límites

Con sesión gerencia, 90.000 eventos (30.000 por fuente) y 30.000 tareas adicionales: Registro 50 filas **332,031 ms**, resumen completo **142,642 ms**, Citas **4,036 ms**. Los incrementos exactos fueron 90.000 llamadas y 60.000 contactos; no se trunca el resumen al límite de una página. Se revirtió toda la carga.

Se limita antes del enriquecimiento porque PL/pgSQL materializa el resultado de `RETURN QUERY`; [documentación PostgreSQL 17](https://www.postgresql.org/docs/17/plpgsql-control-structures.html). El índice parcial corresponde al predicado exacto de cierres; [documentación de índices parciales](https://www.postgresql.org/docs/17/indexes-partial.html).

La prueba mide volumen de eventos con pocas personas sintéticas. La cardinalidad productiva de identidades, jerarquía y políticas debe comprobarse en la rama autorizada antes de instalar. Los índices de instalación pueden tomar bloqueos; se mantiene lock_timeout de 5 s y revisión del entorno destino.

## Verificación final y puertas abiertas

- PASS: cuatro grupos SQL, concurrencia previa sobre writer sin cambios posteriores, catálogos reales UI→SQL, 90.000 eventos de estrés y cinco tipos RPC.
- PASS: lint, typecheck, **387 archivos / 6.200 pruebas**, build/bundle, release-config, push-tasa y check:scripts.
- PASS: **13/13** E2E F6 y **2/2** ficha de perfil en Docker tras los ajustes. La suite más amplia de siete especificaciones había terminado 44 casos sin fallos finales antes de la pausa; tres necesitaron retry bajo carga.
- FAIL: `npm run check` global en duplicación, **1,1 %** frente a 0,8 %. Excluyendo únicamente las copias preexistentes ` 2.*`, **0,43 %**, sin cambiar el umbral ni borrar archivos.
- NOT RUN efectivo: seed/rls preflight se detuvieron por falta de SUPABASE_URL; gate:realidad y advisors/ensayo remoto sin destino autorizado. Esto no equivale a un PASS remoto.
- Validación visual: la realiza Miguel por instrucción expresa. Vista local disponible con datos sintéticos.
- Instalación/publicación: pendientes. SQL exacto requiere aprobación humana según AGENTS/CLAUDE y el release requiere invocación humana del flujo del proyecto. **Base y RPC primero; frontend después.** No se ha modificado producción, hecho commit ni publicado en esta tarea.
