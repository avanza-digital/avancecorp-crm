# Auditoría del plan SLA — correcciones R2

Fecha: 2026-09-06. El usuario pidió auditar el plan, buscar fallos y corregirlos. Se corrigió la documentación; no se implementó ni publicó el módulo.

Informe: `CRM-Avance-Corp/PROPUESTA DE SLA PARA ETAPAS/auditoria-r2/AUDITORIA.md`. Plan vigente: `PLAN-FINAL-SLA-2026-09-06.md`, versión SLA-R2. El anexo `auditoria-r2/CONTRATO-V2.md` fija firmas, JSON, nulls, recibos y paginación; la copia de R1 permite revisar qué se corrigió.

Trece grupos de hallazgos: techo histórico móvil; límite que retrocedía al vencer margen; tareas ambiguas ocultadas por selección; locks incompatibles; confirmación/idempotencia insuficientes; carrera al apagar; constraints contradictorias; efectos reales de cancelación/reprogramación; tareas ausentes del conjunto descargado; lotes sin commits independientes; reversión estructural incompleta; contratos y garantías temporales ambiguos; vinculación insuficiente del cálculo con el patrón de núcleo/ventana/consumidores y la gobernanza vigente.

La auditoría leyó diez definiciones de recorridos y tres definiciones adicionales de SLA/citas con inventario de núcleos; guardó fuente/huellas, sin mutaciones. PostgreSQL 16.14 local desechable reprodujo dos patrones de deadlock y una carrera al cambiar modo; los patrones corregidos pasaron. Hay 27 comprobaciones parciales satisfactorias: 18 de modelos/entradas y 9 de preparación/concurrencia SQL. No son 27 pruebas funcionales del CRM ni evidencia de incidentes productivos. El clúster de pruebas quedó detenido.

Decisiones duraderas:

- Primera activación y política de adopción se fijan juntas una vez. Una publicación posterior no cambia techos históricos.
- Estado desconocido no equivale a false ni a «al día». Solo cobertura comprobada suspende seguimiento; falta de dato de compromiso no fabrica un límite operativo conocido.
- La idempotencia debe cubrir la gestión completa y su recibo, no solo el asiento de prórroga. Mantener la misma intención/UUID mientras la respuesta sea incierta.
- Corregir orden/modo de locks en los writers compartidos, incluyendo puertas antiguas. El apagado debe esperar writers admitidos, y el modo no desinstala triggers.
- El techo sigue siendo por episodio; cancelaciones pueden causar transiciones legítimas. Revisión por tercer ingreso a una etapa en el ciclo es una regla inicial recomendada, no una prohibición de transición.
- SLA-0–4 y la matriz integral siguen pendientes. No confundir revisión documental con certificación de SQL o UI todavía inexistentes.
- El usuario pidió expresamente reutilizar núcleos y organizar cualquier cálculo nuevo necesario en backend bajo su núcleo rector. Se justificó y esquematizó el núcleo operativo de SLA, su ventana y sus consumidores; núcleo agregado histórico y núcleos de capital/conversión/citas conservan su pregunta original.

Relacionadas: [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]] · [[Plan final SLA - seguimiento compromisos y etapas 2026-09-06]] · [[Analisis de propuesta SLA por etapas - 2026-09-06]] · [[Agenda comercial del CRM (plan v2)]] · [[Configuración operativa CRM 2026-08-07]] · [[Main unico - sincronizacion y publicacion 2026-09-04]].
