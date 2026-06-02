---
tags: [feature, seguridad, riesgo]
actualizado: 2026-06-01
---

# Clave temporal = DNI ⚠️

**Decisión (2026-05-25):** al crear un cliente ya no se escribe contraseña. La edge `crear-cliente` usa el **DNI como clave temporal** (`padStart(8,'0')` recupera el cero que borra Excel) y marca `perfiles.debe_cambiar_password = true`.

- En el **primer ingreso**, `auth.js` redirige al cliente a `reset-password.html?primer-ingreso=1` antes del dashboard; `reset-password.js` baja la marca tras guardar la nueva clave.
- El [[Importador de clientes]] aplica el mismo patrón en alta masiva (sin enviar correos).
- Edge retrocompatible: si llega `password`, se usa tal cual.

## ⚠️ Riesgo de seguridad ABIERTO
Que la clave inicial sea el DNI (dato semi-público) es un **riesgo crítico** detectado en la auditoría del 2026-05-28. El cambio obligatorio en el primer ingreso lo mitiga parcialmente, pero **sigue abierto** como pendiente. Ver [[Auditorías del portal]].

## Notas relacionadas
[[Importador de clientes]] · [[Arquitectura del portal]] · [[Inicio]]
