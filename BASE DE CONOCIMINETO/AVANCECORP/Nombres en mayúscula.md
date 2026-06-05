---
tags: [feature, decision, datos]
actualizado: 2026-06-04
---

# Nombres de personas SIEMPRE en mayúscula

**Decisión de Miguel (2026-06-04):** todos los nombres de personas se guardan en
**MAYÚSCULA**, para evitar el desorden visual de tener unos clientes inscritos en
minúscula y otros en mayúscula. Es una **norma del sistema**, no algo que el
analista deba recordar hacer a mano.

## Cómo está garantizado

La norma vive en **dos capas** (la primera es la que de verdad la garantiza):

1. **Base de datos (a prueba de errores) — fuente de la verdad.**
   Un **trigger** (`trg_nombre_mayusculas`, función `normalizar_nombre_mayusculas()`)
   en las tablas **`perfiles`** y **`asesores`** normaliza el `nombre_completo` en
   **cada alta y cada edición**, sin importar por dónde entre (formulario del
   analista, del admin, el [[Importador de clientes]] o una carga manual por SQL):
   lo pone en **MAYÚSCULA**, le quita los espacios de los extremos **y junta los
   espacios dobles internos** en uno solo (`"JUAN  PÉREZ" → "JUAN PÉREZ"`). Aplicado
   en producción vía migraciones `nombres_personas_siempre_mayusculas` +
   `nombres_mayusculas_colapsa_espacios`. `upper()` respeta tildes y la ñ
   (`josé peña → JOSÉ PEÑA`).

2. **Formularios (refuerzo visual).** Los 5 inputs de nombre de persona se ven en
   mayúscula mientras se teclea (`text-transform:uppercase`) y el JS envía el valor
   ya normalizado (mayúscula + sin espacios dobles), para que el mensaje de éxito
   coincida con lo que guarda la BD.

## Excepción: el saludo del correo de bienvenida

El nombre se **guarda** en mayúscula, pero el **correo de bienvenida** al crear un
cliente saluda más cálido: usa solo el **primer nombre con mayúscula inicial**
(`"JOSÉ PÉREZ" → "Hola José"`), no el nombre completo en mayúsculas. Es solo
presentación del saludo (helper `nombreSaludo()` en la edge `crear-cliente`, v11).

## Alcance

- **SÍ aplica:** nombres de **clientes, analistas, admins, superadmins** (`perfiles`)
  y de **asesores** (`asesores`).
- **NO aplica:** correos, DNI, ni el **nombre de los documentos** (ej. "Estado de
  cuenta — Abril 2026"); esos conservan su escritura.

## Estado

- BD: **aplicada y verificada** (5 perfiles viejos corregidos, 0 asesores; 0 con
  espacios dobles; trigger probado contra la BD real). No requiere deploy.
- Correo de bienvenida (edge `crear-cliente` v11): **desplegado**. No requiere acción.
- Frontend (refuerzo visual): **pendiente de subir a Hostinger** (7 archivos) — ver
  el changelog del 2026-06-04 en `public_html/CLAUDE.md`.

## Notas relacionadas
[[Arquitectura del portal]] · [[Importador de clientes]] · [[Rol Analista]] · [[Inicio]]
