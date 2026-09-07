# Seguimiento: avisos accionables por momento y rol

Estado: **PUBLICADO Y VERIFICADO EN PRODUCCIÓN EL 07/09/2026**.

Miguel aprobó reemplazar el panel explicativo de seguimiento por avisos concretos. La ficha muestra únicamente acciones requeridas por el núcleo, con botones a los flujos existentes, y conserva las fechas bajo «Ver plazos». Analista atiende actividades/contactos; Supervisor y Gerencia reciben también las revisiones y el reparto. La campana consulta el resumen completo autorizado, conserva el pendiente hasta resolución y abre la cola paginada en «Para atender ahora».

Se extiende el núcleo operativo vigente, sin cambiar plazos ni crear otro núcleo. Se agrega lectura puntual de tareas bajo RLS para abrir actividades fuera del lote inicial. Los reconocimientos históricos permanecen intactos; los nuevos avisos no se reconocen ni posponen como sustituto de resolver la condición.

[[Seguimiento - propuesta de avisos por momento y rol 2026-09-07]] · [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]] · [[Hoy Analista - seguimiento solo en su modulo 2026-09-07]].

[SQL, alcance, capturas y evidencia](../../CRM-Avance-Corp/PROPUESTA%20DE%20SLA%20PARA%20ETAPAS/avisos-contextuales-20260907/implementacion/REVISION-PARA-PUBLICAR.md).

Verificado: 56 pruebas PostgreSQL 16, integración y reversión PostgreSQL 17 con esquema completo y datos sintéticos, 2.952 pruebas de interfaz/datos, 10 recorridos de navegador, tipos y build. Capturas móvil/escritorio inspeccionadas. Refresco aproximadamente cada 60 segundos y al recuperar foco; no hay entrega con el CRM cerrado.

Miguel confirmó «ok publica» después de recibir el SQL concreto, conforme a [[Inicio]]. Se aplicó con huellas previas exactas y ocho controles correctos. Se verificaron lecturas autenticadas de Analista, Supervisor y Gerencia: el resumen coincide con la cola y el Analista recibe cero revisiones de supervisión. Sin identidad, la lectura devuelve 42501.

Producción sirve el release `crm-20260907T165158Z-8bb960672fb2`, build `build-20260907T165116731Z`, construido desde el commit limpio `8bb960672fb2a6d14e728e96b8ff611e30f3d9cb`, idéntico a Main y avancecorp/main antes de publicar. HTTP: 78 archivos, 65 hashes exactos, 12 imágenes transformadas por Hostinger, configuración protegida y cero fallos. El registro canónico de la migración es `20260907155813`; se conservó la cronología MCP `20260907165929` en la evidencia.

[Evidencia de producción](../../CRM-Avance-Corp/PROPUESTA%20DE%20SLA%20PARA%20ETAPAS/avisos-contextuales-20260907/implementacion/produccion-verificacion.json). El commit posterior de cierre documental no modifica el artefacto publicado.
