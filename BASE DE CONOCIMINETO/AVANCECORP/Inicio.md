---
tags: [moc, inicio]
actualizado: 2026-07-22
---

# 🏠 Inicio — Portal Avance Corp

Bóveda de conocimiento del **Portal Digital de Inversiones de Avance Corp S.A.C.** (dominio `miavance.com`). Es la **memoria de negocio y decisiones** del proyecto. Léela al inicio de cada sesión.

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
- [[Rol Analista]]
- [[Rol Directorio]]
- [[Fusión asesor-analista]]
- [[Clave temporal = DNI]]
- [[Notificaciones de pagos]]
- [[Importador de clientes]]
- [[Gestión comercial de clientes - renovaciones y upgrades]]
- [[Identidad unificada de inversionistas - plan pendiente]]
- [[Handoff plan maestro multiempresa aprobado para firma F0 (2026-09-01)]]
- [[Incidente y restauracion Ficha 360 2026-08-31]]
- [[Nombres en mayúscula]]
- [[Interés compuesto]]
- [[Realtime de novedades]]
- [[Bug de fechas UTC]]
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
