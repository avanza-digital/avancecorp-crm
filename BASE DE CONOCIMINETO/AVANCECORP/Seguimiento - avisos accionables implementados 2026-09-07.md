# Seguimiento: avisos accionables por momento y rol

Estado: **IMPLEMENTADO Y PROBADO LOCALMENTE; SQL Y PUBLICACIÓN PENDIENTES**.

Miguel aprobó reemplazar el panel explicativo de seguimiento por avisos concretos. La ficha muestra únicamente acciones requeridas por el núcleo, con botones a los flujos existentes, y conserva las fechas bajo «Ver plazos». Analista atiende actividades/contactos; Supervisor y Gerencia reciben también las revisiones y el reparto. La campana consulta el resumen completo autorizado, conserva el pendiente hasta resolución y abre la cola paginada en «Para atender ahora».

Se extiende el núcleo operativo vigente, sin cambiar plazos ni crear otro núcleo. Se agrega lectura puntual de tareas bajo RLS para abrir actividades fuera del lote inicial. Los reconocimientos históricos permanecen intactos; los nuevos avisos no se reconocen ni posponen como sustituto de resolver la condición.

[[Seguimiento - propuesta de avisos por momento y rol 2026-09-07]] · [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]] · [[Hoy Analista - seguimiento solo en su modulo 2026-09-07]].

[SQL, alcance, capturas y evidencia](../../CRM-Avance-Corp/PROPUESTA%20DE%20SLA%20PARA%20ETAPAS/avisos-contextuales-20260907/implementacion/REVISION-PARA-PUBLICAR.md).

Verificado: 56 pruebas PostgreSQL 16, integración y reversión PostgreSQL 17 con esquema completo y datos sintéticos, 2.952 pruebas de interfaz/datos, 10 recorridos de navegador, tipos y build. Capturas móvil/escritorio inspeccionadas. Refresco aproximadamente cada 60 segundos y al recuperar foco; no hay entrega con el CRM cerrado.

Falta confirmar el SQL concreto según [[Inicio]] antes de aplicarlo en producción. La autorización general de implementar el planteamiento no se presenta como una aplicación productiva ya realizada.
