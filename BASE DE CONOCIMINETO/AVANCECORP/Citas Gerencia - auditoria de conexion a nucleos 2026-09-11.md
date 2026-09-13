---
fecha: 2026-09-11
estado: auditado-con-desconexiones
tags: [crm, citas, gerencia, auditoria, nucleos]
---

# Citas Gerencia — auditoría de conexión a núcleos

Miguel pidió comprobar si todas las métricas están conectadas a sus núcleos en backend y frontend. **Resultado: no.** Se auditó código local y catálogo/definiciones del servidor en modo lectura. No se aplicó SQL ni se cambió el runtime.

Informe y evidencias: `UX-UI-GERENCIA/auditoria-citas-nucleos-2026-09-11/README.md`.

## Hallazgos confirmados

- La ruta real de Gerencia llama a `crm.citas_gerencia_consulta_fn → private.citas_gerencia_consulta`. Este lector usa tareas, leads y asignaciones directamente; no llama a los núcleos de citas/conversión/capital. Comparte `private.cierre_anulado`.
- El servidor lo registra como contador crudo **sin declarar**. `private.assert_analitica_leads_citas()` falló y lo nombró. El agregador viejo `metricas_reuniones_implementacion` sí consume los tres núcleos: comprobar solo ese agregador no verifica la nueva ruta.
- `components/citas/metas.ts` conserva meta 3 y objetivo 125% (=3,75), calculados sobre leads con cita. La base total de asignados, excluyendo registro propio e incluyendo leads sin cita, no llega al tablero.
- `citas-detalle` no coincide con el prefijo `reuniones` invalidado al crear/cerrar/reprogramar. Reproducción con QueryClient real: 1 petición inicial, sigue 1 tras invalidación vieja, sube a 2 con el prefijo correcto. Puede quedar una foto anterior hasta refrescar.
- Tabla y RPC del Control de Superadmin están ausentes del servidor. La migración candidata solo guarda borradores; ningún lector aplica esa configuración. Instalarla por sí sola no conecta las metas.
- La propuesta integrada, sus objetivos 1,25/70%/70%, el ticket y el pronóstico siguen siendo datos ficticios en HTML independiente. No están integrados en la pantalla real.

## Lo que sí tiene evidencia real

El recorrido de inasistencias usa reprogramación vinculada, asistencia registrada y conversión posterior a cliente; deduplica por lead y excluye anulaciones. Mantiene conjuntos anidados. Su tasa usa **quienes faltaron**, no todos los entrevistados. No reutilizarla como el nuevo objetivo de conversión del 70%.

La conversión acredita conteo de depósito, pero la respuesta no aporta importe. `monto_estimado` no es ticket ni capital ingresado. El ticket necesita fuente de capital, período, atribución y moneda definidos.

La base del índice general `conversion_episodios` tampoco equivale automáticamente a los leads asignados de esta nueva meta: mide altas originales/primera asignación, canales específicos y aportes ponderados. Construir la lectura semántica que necesita Citas sin alterar ese otro contrato.

## Verificación y alcance

97 pruebas focalizadas pasadas y TypeScript limpio. Control de núcleos en servidor: **FAIL**. Matriz SQL/RLS con escrituras, E2E completo y build de producto: **NOT RUN** en esta auditoría. No se auditó el bundle desplegado.

Se intentó la revisión independiente con el wrapper Claude: el intento en sandbox no completó; el reintento autorizado terminó con respuesta incompleta o sin VERDICT válido. **No hubo dictamen utilizable.** No presentarlo como PASS.

El gate global también nombró cuatro funciones ajenas a Citas; están conservadas como seguimiento aparte en el informe, sin auditar sus reglas.

Siguiente trabajo recomendado: corregir invalidaciones y gobernanza; completar base/atribución del módulo; activar configuración versionada; conectar metas, ticket y proyección; verificar escritura→lectura antes de publicar. Esta auditoría no aprueba fórmulas pendientes ni autoriza una migración productiva.

Relacionado: [[Citas Gerencia - avance y proyeccion mensual por analista 2026-09-11]], [[Citas Gerencia - control de Superadmin en borrador 2026-09-11]], [[Citas Gerencia - deposito acreditado por conversion a cliente 2026-09-08]], [[Contrato de la capa semantica - Leads y Citas (F6, 2026-08-30)]], [[Contrato de la capa semantica - Capital (F4, 2026-08-29)]].
