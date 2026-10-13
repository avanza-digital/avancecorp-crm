---
tags: [crm, conversion, regla-de-negocio, plan-mantenibilidad]
fecha: 2026-10-12
estado: verificado en laboratorio, NO publicado (grupo C de la fase 4)
---

# Conversión: el cliente antiguo usa su misma ficha, y su «No insistir» la detiene

Bloque 2.10 del plan de mantenibilidad del backend (decisiones D-38 y D-81…D-94 de Miguel). Vive fuera del repo, en
`~/dev/avancecorp-plan-backend/fase-2/bloque-2.10/` (`CIERRE.md`). Aún **no está en producción**: entra con el grupo C.

## La regla
Al convertir un lead con el DNI de un **cliente antiguo sin ficha de persona** (un convertido viejo, de antes de las fichas):
- Si el antiguo sigue **activo con otro asesor** ⇒ «ya es cliente de X» y no se convierte.
- Si está **retirado** o es **del mismo asesor** ⇒ se junta con la ficha nueva (misma persona, su dinero y su historia) y la conversión sigue; el cliente pasa al asesor que convierte.
- **D-94 (12/10/2026):** si ese antiguo tiene **«No insistir»**, la conversión se detiene SIEMPRE con el aviso del alta («Contacto no disponible»), también cuando el lead
  ya traía el DNI escrito o se usa CE/pasaporte. Antes de esta regla, en esos casos la marca no se miraba y la persona se convertía.

## Cómo se destraba
Si la persona volvió por su cuenta: Supervisión (si toda la persona es de su equipo) o Gerencia usan **«Quitar No contactar»** (ficha de «Base para gestión»;
`crm.levantar_no_contactar`, motivo obligatorio, queda en el historial). Quita la marca de la persona y de **todos** sus leads, incluida la ficha vieja. Luego se convierte.

## Cuánto pesa hoy (conteo D-82 en producción, 12/10)
4 candidatos, todos activos, ninguno comparte DNI con un lead vivo; 0 antiguos retirados ya unidos. La regla es preventiva.

## Pendiente conocido (bloque D-92, después del grupo C)
Ajustar el verificador de disponibilidad (para que los retirados ya unidos conviertan sin trámite), el teléfono de un antiguo absorbido que nombra al asesor viejo (H-3),
y el perfil activo del Portal cuando el DNI ya venía escrito (hoy convierte, como antes).

Relacionado: [[Como se mide la conversion del asesor]] · [[Conversion - conciliacion de responsable tras reasignar (2026-09-29)]] · [[Inicio]]
