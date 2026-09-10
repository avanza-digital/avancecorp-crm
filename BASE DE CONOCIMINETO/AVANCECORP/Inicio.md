---
tags: [moc, inicio]
actualizado: 2026-09-10
---

# 🏠 Inicio — Portal Avance Corp

Bóveda de conocimiento del **Portal Digital de Inversiones de Avance Corp S.A.C.** (dominio `miavance.com`). Es la **memoria de negocio y decisiones** del proyecto. Léela al inicio de cada sesión.

Estado vigente: [[F5 - instalada y apagada (2026-09-10)]].
Plan de trabajo F5: [[Plan de implementacion F5 - cartera y ficha multiempresa (2026-09-08)]].

## 🧠 Cómo funciona la memoria de este proyecto

Hay **tres capas**, complementarias:

1. **Este vault de Obsidian** — conocimiento curado, decisiones y features (notas enlazadas).
2. **Grafo de código (CODEgraph)** — estructura del código, vía el MCP `codegraph` (`mcp__codegraph__*`). Consúltalo (p. ej. `codegraph_symbol_search`, `codegraph_get_ai_context`) en vez de grepear.
3. **Documentos canónicos** (la *fuente de verdad* técnica):
   - **`public_html/CLAUDE.md`** → memoria técnica detallada del portal. **GANA sobre todo lo demás** si hay diferencia.
   - **`PORTAL_AVANCE_CORP_IMPLEMENTACION.md`** → guía de implementación.
   - **`CRM-Avance-Corp/PLAN-CRM-AVANCE-CORP.md`** → plan maestro vigente del CRM;
     su sección inicial «Estado maestro vigente» concentra avance, ruta crítica y
     definición de «CRM listo».
   - *(`MEMORIA DE PROYECTOS.md` se eliminó el 2026-06-01 por estar desactualizado — era copia vieja del CLAUDE.md.)*

## 🗺️ Mapa de notas

- [[Arquitectura del portal]] — stack, base de datos, edge functions, seguridad (resumen).

**Features y decisiones:**
- [[Citas Gerencia - cierre de sesion y punto de retoma 2026-09-09]] — publicado, avance guardado y respaldo privado; pendientes de revisión visual y mantenimiento del banco general.
- [[Solicitud de tasa en el lead - publicada 2026-09-09]] — aprobación antes de convertir publicada; banco temporal cerrado y verificaciones registradas.
- [[RETOMAR-64 - CARTERA F4 terminada y avance guardado (2026-09-08)]] — punto de retoma vigente, commits y respaldo privado; sigue F5.
- [[F4 cerrada - comisiones fuera del sistema (2026-09-08)]] — F4 técnica terminada; comisiones externas excluidas del sistema. Sigue F5.
- [[F4 multiempresa - reconstruccion, finanzas y lectura vigente (2026-09-08)]] — candidata técnica probada y guardada; G4 cerrado según la decisión de comisiones externas.
- [[UX1 y UX2 Gerencia - componentes y revision visual 2026-09-06]] — catálogo reutilizable y nueva revisión de Resumen/Conversiones; pendiente de revisión visual y validación humana de F0.
- [[Organizacion local y Figma - UI UX Gerencia 2026-09-06]] — carpeta `UX-UI-GERENCIA`, índice de Figma, estado de F0 y preparación de UX1.
- [[Rol Analista]]
- [[Rol Directorio]]
- [[Fusión asesor-analista]]
- [[Clave temporal = DNI]]
- [[Notificaciones de pagos]]
- [[Importador de clientes]]
- [[Gestión comercial de clientes - renovaciones y upgrades]]
- [[Nucleo de conversion - diagnostico de llegadas y asignaciones 2026-09-04]]
- [[Plan de correccion de metricas de Gerencia - requerimiento vigente]] — cinco puntos acordados, restricciones y punto de reanudación.
- [[Inventario de indicadores de Gerencia - Contrato de lectura]] — significado, fuente, período y límites de cada indicador; entregable documental del punto 1.
- [[Correccion de pantallas de Gerencia - punto 2 - 2026-09-04]] — correcciones implementadas, verificadas y publicadas; alcance y límites.
- [[Correccion de Cartera - punto 3 - conciliacion y SQL pendiente 2026-09-04]] — punto 3 completado: SQL aplicado y frontend publicado. Cifras conciliadas, pruebas y reversión.
- [[Main unico - sincronizacion y publicacion 2026-09-04]]
- [[Publicacion frontend metricas Gerencia 2026-09-04]] — todo guardado; frontend publicado desde `50f33a5`, archivos y acceso de Gerencia verificados. Los puntos 4–5 siguen pendientes.
- [[Datos faltantes de Gerencia - punto 4 - decision pendiente 2026-09-05]] — justificación histórica de las cuatro necesidades; alcance aprobado e implementación local completada después.
- [[Plan por fases - cuatro datos de Gerencia - aprobado 2026-09-05]] — N1–N4 implementados y auditados localmente; falta confirmar/aplicar SQL, versionar, sincronizar y publicar.
- [[Contrato tecnico de ampliaciones N1-N4 de Gerencia - 2026-09-05]] — contrato, huellas, migración, rollback y evidencia final. Título comercial acordado: «Resultados de los leads del mes».
- [[Auditoria final de Gerencia - punto 5 - avance 2026-09-05]] — ampliaciones y animación verificadas localmente con núcleos intactos; faltan las puertas productivas y el commit final.
- [[Cierre productivo de metricas de Gerencia - ejecucion 2026-09-05]] — ejecución autorizada de los seis pasos; preflight actual comprobado, SQL exacto pendiente de confirmación y publicación todavía no realizada.
- [[Identidad unificada de inversionistas - plan pendiente]]
- [[Handoff plan maestro multiempresa aprobado para firma F0 (2026-09-01)]]
- [[Incidente y restauracion Ficha 360 2026-08-31]]
- [[Nombres en mayúscula]]
- [[Interés compuesto]]
- [[Realtime de novedades]]
- [[Bug de fechas UTC]]
- [[Reporte diario de derivaciones para Coordinación]]
- [[Auditorías del portal]]

**Herramientas independientes:**
- [[SubLínea — subtítulos locales para X]]

## 👤 Reglas de trabajo con Miguel

- Miguel **no es desarrollador** (analista comercial). Explicar en **lenguaje natural**, sin jerga.
- **Versiones de desarrollo:** usar siempre la **última versión estable** disponible del lenguaje, framework y dependencias aplicables. Antes de implementar, verificar las versiones y la documentación vigente con Context7. Si una actualización rompe compatibilidad con el proyecto, explicar el impacto y acordar la migración antes de aplicarla.
- **Cambios de base de datos:** mostrar el **SQL primero** y esperar confirmación.
- Lo **visual** decláralo explícito para que Miguel lo pruebe; las **capturas** son el input principal de debugging.
- **Deploy manual** a Hostinger (copiar a la carpeta espejo) + subir `?v=N` del módulo editado.
- Máximo 3 intentos automáticos; si sigue fallando, escalar con explicación clara.
