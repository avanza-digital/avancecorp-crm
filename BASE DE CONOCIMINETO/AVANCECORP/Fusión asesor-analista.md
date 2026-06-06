---
tags: [feature, roles, asesor, analista, fusion]
actualizado: 2026-06-05
---

# Fusión Asesor → Analista

**2026-06-05 (en progreso).** Decisión de Miguel: **"asesor" y "analista" son lo mismo**, así que se **elimina por completo el concepto de "Asesores"** del portal y el **analista** del equipo pasa a ser también el **asesor** que ve el cliente. Es la "unificación grande" que anticipaban [[Rol Analista]] y el ladrillo aditivo del 2026-06-04.

## Por qué
Había **dos representaciones de la misma persona**: una ficha en el catálogo `asesores` (sin login) y un `analista` (login que registra clientes y contratos). De 10 asesores, **7 ya eran el mismo analista** (mismo correo). Duplicación pura → se unifica en uno solo: el **analista**.

## Qué cambia
- El **asesor de un cliente = un analista del equipo**, vía `perfiles.asesor_perfil_id`. Se asigna desde *Clientes* eligiendo un analista.
- El **analista** ahora guarda **WhatsApp y cargo** (lo que el cliente ve como su asesor personal); se cargan al crear/editar el analista.
- Desaparecen: la **página Asesores**, su entrada de **menú**, el **registro** de asesores y (al final) la **tabla** `asesores`.
- En el admin se llama **"Analista"**; en el portal el cliente sigue viendo **"Tu asesor personal"** (con el nombre y WhatsApp del analista).

## Estado (2026-06-05)
- **Frontend y la edge del importador: hechos, sin desplegar.** El portal del cliente no cambió (ya resolvía el asesor con la función segura `obtener_mi_asesor`).
- **Base de datos: intacta todavía.** La tabla `asesores` y la columna `asesor_id` se borran en el **paso final** (`FUSION_asesor_analista_LIMPIEZA_FINAL.sql`, en la raíz del repo), recién cuando se migren los últimos 5 clientes legacy.

## Pendiente (Miguel)
1. Crear 3 analistas: **Miguel**, **Carmen**, **Lisseth** (con sus DNIs).
2. Reasignar los **5 clientes** que tenían de asesor a "Miguel Briceño" → al analista Miguel.
3. Subir el frontend a Hostinger (y **borrar del hosting** `admin/asesores.html` + `js/admin/asesores.js`).
4. Desplegar la edge `importar-clientes`.
5. Correr el SQL de limpieza final.

## Bug 2026-06-05: `crear-cliente` no auto-asignaba el asesor (arreglado)
**Síntoma:** al crear un cliente, el analista no quedaba como su asesor (`asesor_perfil_id` nulo) → el "Ranking por analista" del [[Rol Directorio]] salía incompleto.
**Causa raíz:** la edge **`crear-cliente` desplegada era la v11 (vieja)**, sin la línea `asesor_perfil_id: perfil.rol === "analista" ? userRes.user.id : null`. El arreglo existía en el repo (parte de esta fusión) pero **nunca se había desplegado** (ver "Estado: hechos, sin desplegar").
**Solución:** se desplegó la versión correcta (**v12**, verificada en prod) + se rellenaron los 2 clientes huérfanos de analista (`asesor_perfil_id = creado_por`). Quedan a propósito sin asesor 7 clientes creados por superadmin + 1 sin creador (decisión de Miguel: se asignan después).
**Lección:** editar el `index.ts` local de una edge **no la despliega**; hay que correr el deploy. Revisar siempre la versión viva con `get_edge_function` antes de dar por hecho un arreglo.

## Notas relacionadas
[[Rol Analista]] · [[Rol Directorio]] · [[Arquitectura del portal]] · [[Importador de clientes]] · [[Clave temporal = DNI]] · [[Inicio]]
