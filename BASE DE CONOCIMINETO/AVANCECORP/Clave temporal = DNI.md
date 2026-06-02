---
tags: [feature, seguridad]
actualizado: 2026-06-01
---

# Clave temporal = DNI

**Decisión (2026-05-25):** al crear un cliente ya no se escribe contraseña. La edge `crear-cliente` usa el **DNI como clave temporal** (`padStart(8,'0')` recupera el cero que borra Excel) y marca `perfiles.debe_cambiar_password = true`.

- En el **primer ingreso**, `auth.js` redirige al cliente a `reset-password.html?primer-ingreso=1` antes del dashboard; `reset-password.js` baja la marca tras guardar la nueva clave.
- El [[Importador de clientes]] aplica el mismo patrón en alta masiva (sin enviar correos).
- Edge retrocompatible: si llega `password`, se usa tal cual.

## Seguridad — evaluado y aceptado
Una auditoría automática (2026-05-28) marcó esto como riesgo, pero **Miguel lo evaluó como NO un riesgo real** (decisión cerrada 2026-06-01): el **onboarding es controlado** (el asesor entrega la cuenta, no hay registro público) y el portal del cliente es de **bajo valor / solo lectura** (no se puede mover dinero ni hacer acciones sensibles). **No tratar como pendiente.**

## Notas relacionadas
[[Importador de clientes]] · [[Arquitectura del portal]] · [[Inicio]]
