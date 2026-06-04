---
tags: [feature, seguridad, roles, analista]
actualizado: 2026-06-03
---

# Rol Analista (alta de clientes + contratos)

**Implementado 2026-06-03.** Cuarto rol del portal, pensado para que el **analista comercial** dé de alta a un cliente nuevo y su contrato, **sin acceso al resto del panel admin** y con una **ventana anti-fraude**. Idea original de Miguel.

## Qué puede hacer (y SOLO esto)
1. **Crear un cliente** (usuario del portal) → edge `crear-cliente` (clave temporal = DNI, igual que el admin). Ver [[Clave temporal = DNI]].
2. **Crear el contrato de ese cliente** + su cronograma → RPC `crear_contrato` (atómica).
3. **Corregir, solo dentro de las 5 h** desde que creó cada registro:
   - datos del cliente → `UPDATE` directo (la RLS valida dueño + ventana).
   - contrato → RPC `actualizar_contrato` (regenera el cronograma; bloquea si ya hay cuotas pagadas).

**No puede:** borrar nada, ver/editar clientes o contratos de otros, ver pagos/comunicados/documentos, crear admins, ni ascender un cliente a otro rol.

## La ventana de 5 h (decisión de Miguel)
- Corre **por registro**, desde su `creado_en`, y es **fija**: editar **no la reinicia**.
- **No se puede resetear**: el trigger `proteger_campos_inmutables` congela `id`, `creado_en` y `creado_por` en cualquier `UPDATE` de `perfiles`/`contratos`.
- Pasadas las 5 h, solo **admin/superadmin** pueden tocar el registro.

## Seguridad (todo en el servidor, no en el navegador)
- **RLS**: políticas `*_analista_*` en `perfiles`, `contratos`, `cronograma_pagos` — el analista solo ve/edita lo suyo (`creado_por = auth.uid()`) y dentro de la ventana. Helper `es_analista()`.
- **Escritura de contratos por RPC `SECURITY DEFINER`** (`crear_contrato`, `actualizar_contrato`): atómicas, validan dueño + ventana, y registran al analista en el historial (preservan `auth.uid()`). Así el analista nunca necesita permiso de `DELETE`/`INSERT` directo.
- Edges `crear-cliente` (ahora acepta `analista`) y `crear-admin` (ahora crea rol `admin` **o** `analista`, solo superadmin) en `service_role`.

## Cómo se crea un analista
El **superadmin**, en `/admin/clientes` → "**+ Nuevo miembro del equipo**" → elige tipo **Analista**. Aparece en la tabla "Equipo del sistema" con badge **ANALISTA**; ahí mismo se le puede **desactivar** (corta su acceso al instante).

## Bandeja de actividad (para admin/superadmin)
`/admin/bandeja.html` → lista **en tiempo real** (Realtime sobre `audit_log`) toda la actividad de los analistas (altas y correcciones, con el **antes → después** de cada campo). La alimenta la RPC `bandeja_actividad` (solo `es_admin()`); `audit_log` ahora tiene policy de lectura para admin y está en la publicación `supabase_realtime`.

## Pantallas
- **Analista:** `/admin/analista.html` (+ `js/admin/analista.js`) — acotada, sin navegación al resto del admin. El login enruta el rol `analista` aquí (`auth.js` → `verificarAnalista()`).
- **Bandeja:** `/admin/bandeja.html` (+ `js/admin/bandeja.js`), enlazada en el nav admin.

## Verificación (2026-06-03)
Probado contra la BD real con un analista de prueba (creado y **eliminado** después): ve solo lo suyo, corrige en ventana, queda bloqueado fuera de ventana, no puede resetear el reloj, no puede borrar, no puede escalar rol, no puede tocar lo ajeno, y la bandeja del superadmin refleja su actividad. Advisors de seguridad sin hallazgos nuevos.

## Notas relacionadas
[[Arquitectura del portal]] · [[Auditorías del portal]] · [[Clave temporal = DNI]] · [[Importador de clientes]] · [[Inicio]]
