---
fecha: 2026-09-27
estado: publicado-verificado
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
- Las migraciones `20260927172930_crm_vigilante_pre_citas.sql` y
  `20260927172931_crm_citas_supervisor_equipo.sql` están aplicadas y registradas
  en producción.

Publicado el 27/09/2026 en `crm.miavance.com`: artefacto
`crm-20260927T205509Z-8ec3dd1f67e1.zip`, commit `8ec3dd1f67e1`, build vivo
`build-20260927T205509063Z`. El preflight confirmó que el candidato contiene el
release vivo `01d5ddc4b653`; `version.json`, HTML y chunks de Gerencia/Hoy se
verificaron por HTTP tras el despliegue.

Verificación: `npm run check` PASS (4.598 pruebas), build y validación del bundle
PASS. La sonda con un supervisor real encontró 11 vendedores visibles y cero IDs
fuera de su ámbito en población, conversiones y capital; el testigo global no se
entregó y `anon` quedó bloqueado. El guard analítico quedó verde (37 candidatos,
tope 14 vigente). La corrida Docker exacta del artefacto final quedó invalidada
por otra suite completa concurrente que saturó Chromium; el candidato anterior
con el mismo cambio funcional había cerrado 277 PASS y 26 omitidas. La matriz
RLS completa con fixtures sigue pendiente de una base local/staging sembrada.

Relacionada con [[Citas Gerencia - Métricas, Query y Seguridad]] y [[Gestión Diaria - Permisos y Herramientas por Rol]].
