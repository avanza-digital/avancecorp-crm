# Contraste SLA con cartera real

Corte de producción de solo lectura: 06/09/2026 21:22:34 Lima, `2026-09-07T02:22:34.784820Z`. El usuario pidió comparar primero con la cartera existente y manifestó preferencia por activar todo junto después si la evidencia es correcta. Se retira la exigencia de una jornada previa en observación; no se activó ni publicó SLA durante este contraste.

Se extrajeron hechos minimizados, sin nombres/contactos, en una única consulta. 1.157 leads activos: 827 abiertos y 330 terminales. Las 831 tareas pendientes con lead tienen contexto causal demostrable; reconstrucción aplicada solo en banco PostgreSQL 17 local. La tarea pendiente adicional sin lead queda fuera del dominio. Cero vetos en el corte mediante el helper canónico.

Con reglas aprobadas e historial conservado: 527 oportunidades con seguimiento pendiente; 229 cubiertas; 455 para revisión comercial; 342 primeras atenciones y 457 leads con tarea vencida. Las señales se solapan. Tres sin analista son pendientes de reparto, no incumplimientos atribuibles a un analista. 824 abiertos quedan completamente evaluables.

Reconstruir el contexto evita 102 avisos de seguimiento de más. 492 etapas exceden el límite original; 51 tienen ampliación válida por compromiso, quedan 441 vencidas operativamente y 14 revisiones adicionales por reingreso. Hay 262 etapas con política v4 y 565 con v5. Preservar historia implica que los topes heredados v4 son 3/11/8/14 días, frente a 3/16/18/27 en v5; no se reescriben como nuevas entradas. No hay prórrogas retrospectivas.

N1 corregido para no usar hitos de primera atención de asignaciones incoherentes. 44/44 pruebas y 18.698 comparaciones independientes por lead/campo sin discrepancias. V1 conserva sus 1.157 filas. SQL SHA-256 `33d904a80f5eea0a94c7b3abf355827b1eec48b57a46776d9901989236f08d8f`; foto SHA-256 `065e5496946dda8d5e50f06a4c9341327c545fce6c4f2844f7b0a6032ee0b5a2`. Bancos detenidos. Se usó esquema reducido y dobles de autoridad/ámbito; no certifica RLS completo, writers, concurrencia ni UI productiva.

Requisito nuevo comprobado para completar el mismo núcleo: filtros por señales y paginación en la consulta. 342 primeras atenciones superan el máximo 200 actual sin cursor; de 455 revisiones solo 18 tienen revisión como acción dominante. No filtrar revisiones por bucket ni derivar contadores de una página. Contrato descrito en `PROPUESTA DE SLA PARA ETAPAS/AJUSTE-LECTURA-COLA-TRAS-CONTRASTE.md`; implementación pendiente antes de activar.

No hace falta otro núcleo ni calculadora comercial suelta. Completar configuración versionada, contexto en writers/reconstrucción, concesión transaccional de prórrogas, recibos/locks, filtros/paginación y pantallas, con integración completa y pruebas. El contraste respalda mantener reglas y preparar activación conjunta, no declara terminado lo que falta.

Informe: `CRM-Avance-Corp/PROPUESTA DE SLA PARA ETAPAS/CONTRASTE-CARTERA-2026-09-06.md`. Agregados, paridad, consulta y oráculo de prueba en `supabase/tests/sla-nucleo/`; datos individuales en temporal privado. Los nulos de hitos propios en L-1024 y L-1119 son correctos: Gerencia/supervisor conversaron con el lead, no el analista. No corregirlos como errores de stock.

Relacionadas: [[Nucleo SLA N1 - implementacion local y ajustes guiados 2026-09-06]] · [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]] · [[Plan final SLA - seguimiento compromisos y etapas 2026-09-06]] · [[Auditoria del plan SLA - correcciones R2 2026-09-06]].
