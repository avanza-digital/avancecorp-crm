---
tags: [moc, inicio]
actualizado: 2026-06-01
---

# 🏠 Inicio — Portal Avance Corp

Bóveda de conocimiento del **Portal Digital de Inversiones de Avance Corp S.A.C.** (dominio `miavance.com`). Es la **memoria de negocio y decisiones** del proyecto. Léela al inicio de cada sesión.

## 🧠 Cómo funciona la memoria de este proyecto

Hay **tres capas**, complementarias:

1. **Este vault de Obsidian** — conocimiento curado, decisiones y features (notas enlazadas).
2. **Grafo de código (Graphify)** — estructura del código en `graphify-out/`. Consúltalo con `graphify query "<pregunta>"` en vez de grepear.
3. **Documentos canónicos** (la *fuente de verdad* técnica):
   - **`public_html/CLAUDE.md`** → memoria técnica detallada del portal. **GANA sobre todo lo demás** si hay diferencia.
   - **`PORTAL_AVANCE_CORP_IMPLEMENTACION.md`** → guía de implementación.
   - *(`MEMORIA DE PROYECTOS.md` se eliminó el 2026-06-01 por estar desactualizado — era copia vieja del CLAUDE.md.)*

## 🗺️ Mapa de notas

- [[Arquitectura del portal]] — stack, base de datos, edge functions, seguridad (resumen).

**Features y decisiones:**
- [[Rol Analista]]
- [[Clave temporal = DNI]]
- [[Notificaciones de pagos]]
- [[Importador de clientes]]
- [[Nombres en mayúscula]]
- [[Interés compuesto]]
- [[Realtime de novedades]]
- [[Bug de fechas UTC]]
- [[Auditorías del portal]]

## 👤 Reglas de trabajo con Miguel

- Miguel **no es desarrollador** (analista comercial). Explicar en **lenguaje natural**, sin jerga.
- **Cambios de base de datos:** mostrar el **SQL primero** y esperar confirmación.
- Lo **visual** decláralo explícito para que Miguel lo pruebe; las **capturas** son el input principal de debugging.
- **Deploy manual** a Hostinger (copiar a la carpeta espejo) + subir `?v=N` del módulo editado.
- Máximo 3 intentos automáticos; si sigue fallando, escalar con explicación clara.
