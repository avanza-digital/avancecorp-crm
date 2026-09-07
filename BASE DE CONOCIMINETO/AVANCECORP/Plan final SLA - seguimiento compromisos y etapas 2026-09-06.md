# Plan final SLA — seguimiento, compromisos y etapas

Fecha: 2026-09-06. Estado: plan auditado y corregido; sin implementación ni mutaciones de la base del CRM.

Documento de desarrollo: `CRM-Avance-Corp/PROPUESTA DE SLA PARA ETAPAS/PLAN-FINAL-SLA-2026-09-06.md`, versión **SLA-R2**. Sustituye R1 y la propuesta original como guía de implementación. `auditoria-r2/` conserva R1, informe de trece hallazgos, contratos externo/arquitectónico y evidencia de las comprobaciones parciales.

Decisiones recomendadas del plan:

- Separar seguimiento pendiente, compromiso y etapa fuera de plazo; prórroga no apaga seguimiento.
- Seguimiento inicial 1/3/3/5 días para Nuevo/Contactado/Reunión/Propuesta; reloj corrido. Primera atención conserva 2h/24h según corte vivo.
- Inspeccionar inconsistencias antes de elegir primera tarea comercial pendiente del ciclo, incluyendo la atrasada. Una tarea ambigua no se salta para usar otra futura. Al vencer el margen termina cobertura, pero se conserva la frontera de la tarea pendiente en el límite operativo. Tercera reprogramación retira cobertura.
- Prórrogas solo por conversación humana autenticada durante las últimas 24h antes del límite, con mismo episodio antes/después del avance. Nunca créditos tempranos ni prórroga retroactiva.
- Seguimiento y cobertura prospectivos para la cartera actual desde activación; prórrogas solo para etapas con política ampliada. La política de adopción fija el techo de episodios históricos; las nuevas publicaciones no lo mueven. Sin reescribir snapshots ni cumplimiento histórico.
- Modelo de cinco tablas: anexo de reglas, ledger de ajustes, contexto causal de tareas, control de modos y solicitudes/recibos de gestión. No backfill sobre políticas inmutables.
- Instrucción expresa del usuario: reutilizar núcleos existentes; si hay un cálculo nuevo necesario, diseñarlo en backend bajo un núcleo rector, sin funciones o calculadoras independientes. SLA requiere un núcleo operativo nuevo que usa fuentes SLA actuales, una ventana común y consumidores sin fórmulas. Ver `auditoria-r2/ARQUITECTURA-NUCLEO-SLA.md`.
- Corregir locks existentes: modo fuerte del lead desde la primera adquisición y orden lead → tareas, con revalidación. Instalar captura en migración breve y reconstruir stock con commits por lote y helper privado transitorio.
- RPC v2 y recibos idempotentes de actividad/cierre/reprogramación; la UI espera confirmación persistida. Contratos de lectura v1 intactos; escritor común que preserva reglas nuevas ante un publicador v1. Agenda paginada y tarea dominante accesible por ID.
- Cancelar la última reunión puede cerrar/abrir episodios por el retroceso legítimo. El techo es por episodio, no global. Tercer ingreso a la misma etapa en el ciclo genera revisión de supervisión como regla inicial recomendada.
- Fases SLA-0–6; entorno reproducible, matriz de aceptación y observación antes de activar. Reversión por modo con barrera para writers en vuelo, más contingencia SQL ensayada para fallos estructurales que el modo no resuelve.

Corte productivo de solo lectura, 2026-09-06 17:34:44 Lima: v5 vigente/última; 827 etapas abiertas y 492 vencidas por límite base; duraciones 1/8/15/20 días. El branch de la propuesta original ya no figura en el inventario. Los conteos son fotografía de tablas, no número de alertas visibles. La consulta no modificó producción.

Los parámetros son las decisiones iniciales recomendadas del plan; no se registran como aprobaciones comerciales anteriores. La auditoría R2 leyó diez funciones de recorridos y tres definiciones adicionales de SLA/citas con inventario de núcleos; obtuvo 27 comprobaciones satisfactorias de modelos/patrones SQL reducidos en PostgreSQL local desechable. Esto no prueba una implementación del CRM: para ejecutar, seguir las fases y comprobar las definiciones vivas frente al repositorio antes de generar la migración final.

Relacionadas: [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]] · [[Auditoria del plan SLA - correcciones R2 2026-09-06]] · [[Analisis de propuesta SLA por etapas - 2026-09-06]] · [[Configuración operativa CRM 2026-08-07]] · [[Agenda comercial del CRM (plan v2)]] · [[Hoy del vendedor - Ahora y Después]] · [[Inventario de indicadores de Gerencia - Citas y operacion]] · [[Terminología comercial del CRM]] · [[Main unico - sincronizacion y publicacion 2026-09-04]].
