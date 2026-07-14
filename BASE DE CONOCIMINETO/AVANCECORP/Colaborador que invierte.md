---
tags: [feature, negocio, usuarios, backend]
actualizado: 2026-07-14
---

# Colaborador que invierte (staff + cliente)

**Qué es (2026-07-14):** un **colaborador** del equipo (analista, admin…) ya puede
tener **además** su propia cuenta de **cliente** para invertir. Antes no podía: el
sistema decía *"el DNI ya está en uso"*.

## Por qué pasaba

El DNI era **único en toda la tabla de usuarios**, sin importar el tipo. Como el
colaborador ya existía con su DNI (como parte del equipo), al crearle una cuenta de
cliente el DNI chocaba.

## La decisión (Miguel)

**Cuentas separadas** (dos accesos para la misma persona):
- Su cuenta de **trabajo** (rol del equipo) → entra al panel del equipo.
- Su cuenta de **cliente** (rol cliente) → entra al portal de inversión.

Se descartó "un solo login con las dos cosas": el portal manda a cada quien según su
rol, así que un login de colaborador no puede mostrar el portal del cliente sin un
cambio grande y riesgoso. Además, separar el acceso de trabajo de su dinero es lo sano.

## La regla nueva del DNI

El "no repetir DNI" ahora aplica **por población**, no entre todos:
- ❌ Dos **clientes** con el mismo DNI → sigue bloqueado (no se duplica un inversionista).
- ❌ Dos del **equipo** con el mismo DNI → bloqueado.
- ✅ Un **colaborador + un cliente** con el mismo DNI → **permitido** (misma persona).

## Lo único a tener presente al usarlo

La cuenta de cliente del colaborador va con un **correo distinto** al de trabajo (el
correo/login es único por persona). Ese correo personal recibe su acceso al portal;
la clave temporal inicial es su documento (como todo cliente — ver [[Clave temporal = DNI]]).

## Estado

- **BD y edge en producción** → crear un colaborador como cliente (uno por uno) YA
  funciona.
- El **Excel de importación masiva** también quedó corregido (dejó de rechazar a un
  colaborador por su DNI).
- Detalle técnico canónico → `public_html/CLAUDE.md`, changelog **2026-07-14 (e)**.

## Notas relacionadas
[[Importador de clientes]] · [[Clave temporal = DNI]] · [[Acceso y roles del CRM]] · [[Arquitectura del portal]] · [[Inicio]]
