---
fecha: 2026-09-27
estado: preparado-local-no-publicado
tags:
  - citas
  - supervision
  - rls
---

# Citas Gerencia — supervisión por equipo

Se preparó la extensión de la vista **Citas Gerencia** para el rol de supervisión.

- Supervisión ve únicamente los datos vinculados a su equipo asignado y a la jerarquía descendente ya resuelta por `private.vendedor_ids_visibles`.
- El alcance se aplica en servidor a citas, tareas, asignaciones, población, conversiones y capital; no depende solo del filtro de interfaz.
- El agregado global `testigo` sigue reservado para Gerencia.
- La migración es `20260927172931_crm_citas_supervisor_equipo.sql`. No se ha aplicado en producción ni publicado.

La validación local de aplicación pasó. La ejecución completa de RLS con usuarios de prueba sigue pendiente de una base local con cuentas y equipos sembrados.

Relacionada con [[Citas Gerencia - Métricas, Query y Seguridad]] y [[Gestión Diaria - Permisos y Herramientas por Rol]].
