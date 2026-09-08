# Plan de avisos por acción y rol — 2026-09-07

Miguel aprobó implementar el plan con «dale hazlo», confirmó el SQL exacto con «sii haz deploy» y retomó con «sigue» después de una pausa. **Publicado y verificado en el alcance SLA.** Interfaz desde fuente limpia `1e580d77f95efb014199ad3e7acbd45e0b514a76`, coincidente con Main y remoto antes del build; release `crm-20260907T231539Z-1e580d77f95e`, build `build-20260907T231539249Z`. SQL aplicado el 07/09 a las 19:26:39 Lima, cuerpo y versión canónica comprobados. El cierre documental no requiere otro build.

Decisión comercial: una gestión reconocida cuenta aunque el cliente no responda. Primera gestión pertenece a la asignación actual. Agenda organiza el siguiente intento; la cobertura de política no invalida una tarea futura. Actividad vencida es la acción principal; revisión por etapa, reprogramaciones o reingreso corresponde a supervisión. Cancelar no crea gestión ni vuelve a primera atención; reasignar/reabrir usa el contexto nuevo.

Se amplía el núcleo existente, sin funciones nuevas ni calculadoras comerciales en la interfaz. `version=2`, `modelo_avisos=3`, próxima acción y avisos mostrados definidos en servidor. Se mantienen plazos/historia/permisos y el arreglo de respuestas antiguas en vuelo. La UI reconsulta en la frontera del servidor y al recuperar foco/conexión; los cursores viejos se reinician.

Entrega y SQL: `CRM-Avance-Corp/PROPUESTA DE SLA PARA ETAPAS/avisos-accion-rol-20260907/README.md`. Migración `20260907212612_crm_sla_avisos_por_accion_y_rol.sql`, reversión exacta y guardas de fuentes incluidas. 66 pruebas del núcleo y 29 de esquema integral. Contraste de 1.272 oportunidades: primera atención 319→121; tareas vencidas 459→459; revisiones 438→438. No se perdió historia, tareas vencidas ni revisiones.

Plan completo: `CRM-Avance-Corp/PROPUESTA DE SLA PARA ETAPAS/PLAN-AVISOS-POR-ACCION-Y-ROL-2026-09-07.md`.

Producción: 78 archivos, dos ZIP 404 y tres versiones estables, sin fallos. Ficha/cola/campana concilian para dos analistas, supervisión y Gerencia; acceso ajeno denegado, paginación sin duplicados, ambas próximas tareas preservadas. La etapa agotada mantiene revisión de Gerencia sin pedir otra llamada inmediata al analista. En la entrega inicial pasaron seis controles y el cierre SLA; advisors 210→210 sin novedades. El pendiente previo de Citas se corrigió posteriormente a las 21:03:47 de Lima: ahora pasan los siete controles y el cierre de reconstrucción, con reglas y permisos intactos. Cierre y evidencia en [[Control de Citas pendiente - huella de excepcion 2026-09-07]]. Esto acredita los controles concretos ejecutados, no una auditoría de todo el sistema.

Evidencia productiva: `avisos-accion-rol-20260907/produccion-verificacion.json` y `produccion-http.json`. Reversión: SQL `rollback-sla-accion-rol.sql` primero, release anterior `crm-20260907T195955Z-431e926e6d8d.zip` después.

Relacionadas: [[Seguimiento - propuesta de avisos por momento y rol 2026-09-07]], [[Main unico - sincronizacion y publicacion 2026-09-04]], [[Deploy a Hostinger]], [[Inicio]].
