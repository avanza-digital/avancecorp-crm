# Verificación en producción de los hallazgos del frente C (solo lectura, 2026-10-22, entre 20:40 y 21:03 Lima (hora real por `date`))

| Hallazgo | Comprobación | Resultado | Lectura |
|---|---|---|---|
| C-1 | `authenticated` tiene SELECT de TABLA en `crm.leads`; lee `dni`/`fecha_nacimiento`/`genero` | true; true/true/true. ACL propia de `dni` = solo `w` (UPDATE), lee por el permiso de tabla | CONFIRMADO. El recorte por columna no recorta nada. Si Coordinación debe o no ver el DNI lo decide Miguel. |
| C-2 | UPDATE de `consentimiento_en`/`consentimiento_fuente` a `authenticated`; triggers que lo protejan; leads con consentimiento | true/true; 0 triggers; 3 937 leads con consentimiento | CONFIRMADO. |
| C-3 | las 4 tablas con `log_audit_crm()` sin tapar; policies de `public.audit_log` | las 4 confirmadas; `audit_log`: RLS ON, lectura solo `es_admin()` o `superadmin` activo del portal (grants `anon=ar`, `authenticated=ar` filtrados por esas policies) | CONFIRMADO. Lo lee admin/superadmin del portal, como dicen los COMMENT; el DNI va sin tapar en ese rastro. |
| C-4 | permisos de escritura de tabla a `authenticated` | `actividades:I`, `tareas:I`, `agenda_ics:IU`, `enfriamiento_politica:IU`, `politica_abandono:U`, `recordatorios_disponibilidad:IUD`, `alertas_reconocimientos:I` (+ `leads` por columna) | CONFIRMADO (saltos ya medidos en el mapa de capas). |
| C-5 | bitácora I/U/D en permisos/config de `private` | `pares_autoridad` (9 filas, NO 0), `agenda_reparto_diaria`, `agenda_reparto_destinos`, 4 tablas de exenciones/topes: ninguna audita nada; `capital_valoracion_politica` audita I/U pero no D | CONFIRMADO. |
| C-6 | `private.respaldo_cierre_agosto_2026` | RLS false; **17 filas** (no 0); ACL solo del dueño; `postgres` tiene BYPASSRLS | CONFIRMADO. Tiene datos. |
| C-9 | `solicitudes_tasa` con grant SELECT y sin gate; tablas con policies sin grant | false/true; 19 tablas | CONFIRMADO (19, no 17). |
