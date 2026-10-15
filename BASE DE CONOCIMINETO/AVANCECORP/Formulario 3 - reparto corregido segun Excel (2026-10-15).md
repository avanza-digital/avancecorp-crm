---
tags: [crm, formulario-3, coordinacion, correccion-datos]
actualizado: 2026-10-15
---

# Formulario 3 — reparto corregido según Excel

## Resultado vigente

**Aplicado y verificado en producción el 15/10/2026, 11:18 Lima.** Se trasladaron **76 leads** al analista indicado en `Data Jorge.xlsx` y `Data Carmen.xlsx`: primer bloque de 72 y segundo bloque de 4 descartados. Un lead ya tenía el destino correcto: **77 coincidencias de Formulario 3 quedan alineadas con los Excel**.

- **39 leads de Formulario 3 ausentes de los Excel:** sin cambios, por decisión expresa de Miguel.
- **4 descartados:** responsable corregido sin reactivar; estado, motivo y fecha de descarte conservados. La restricción **No contactar** existente en uno permanece. Sus cuatro episodios cerrados no se modificaron ni se abrió ninguno nuevo.
- **Historial:** conservado, incluida cada actividad previa. Miguel priorizó el traslado y aceptó mantener el historial. Se añadió la reasignación normal del sistema y una nota de corrección por lead.
- **27 tareas pendientes:** trasladadas con su lead en el primer bloque, conservando contenido, fechas y estado. El segundo bloque no tenía tareas.
- **n8n:** sigue activo cada 5 minutos, por orden de Miguel; esta corrección no cambió la automatización.

## Alcance y emparejamiento

Los dos Excel contienen 108 contactos únicos en sus hojas DATA; las pestañas de analistas repiten esos contactos. Se compararon los dos teléfonos disponibles en Excel con el teléfono principal y alternativo del CRM, más el nombre completo normalizado, exigiendo coincidencia única. Miguel confirmó que «Mell» corresponde a Merlys García. El alias Betzabeh se corroboró con la pestaña BETZABETH y la analista activa del equipo de Carmen.

Se identificaron 77 leads de Formulario 3. Las otras 31 filas de Excel tienen candidatos telefónicos fuera de esa campaña (solo 8 también coinciden por nombre): no son 31 identidades confirmadas y no se modificaron. No se crearon ni se eliminaron leads.

## Ejecución y comprobaciones

Proyecto `PortalAvanceCorp` (`dctqcbznekcyxhjujuci`). Operaciones:

- `formulario3-reorden-20261015`: 72 cambios, postlectura 16:08:46 UTC. **72/72** responsables y episodios correctos; 27 tareas pendientes, **0 desalineadas**; 44 leads fuera del bloque sin cambios.
- `formulario3-reorden-descartados-20261015`: 4 cambios autorizados expresamente después de separar los descartados. Postlectura 16:18:44 UTC: **4/4** destinos correctos; 4 descartados, 1 No contactar, episodios y actividades anteriores intactos. El primer bloque sigue **72/72** correcto; ninguna asignación fuera del segundo bloque cambió.

Las escrituras se ejecutaron como `authenticated`, bajo RLS y la identidad administrativa activa de Gerencia, sin deshabilitar triggers ni cambiar permisos o esquema. Cada transacción verificó las 58 funciones revisadas, las policies, los triggers y las huellas del lead, tareas, actividades y episodios. Bloqueos inmediatos y precondiciones abortan ante cambios concurrentes; todos los campos de negocio se conservan salvo el responsable y las marcas temporales normales de la tenencia/actualización.

Ensayos sintéticos en copias locales Docker: **PASS** para traslado entre equipos, RLS, historial, tareas, episodios, veto, descarte, reintentos y edición concurrente. Pruebas de dos sesiones con lead o tarea bloqueada: **PASS**, sin escrituras. Las copias exclusivas de estos ensayos se retiraron. Build y E2E de interfaz no aplican a esta operación de datos; no se publicó interfaz.

## Revisión y evidencia

Codex fue el único escritor. Un agente Codex verificó el emparejamiento en solo lectura. Claude realizó dos revisiones con observaciones sobre identidad/RLS, concurrencia, manifiesto y paridad; se atendieron con guardas y pruebas reales. No se atribuye un PASS final a Claude. JEV se consultó sobre alias y ambigüedades con evidencia saneada; no decidió identidades ni autorizó SQL.

Respaldo privado, manifiestos, SQL exacto ya ejecutado y verificaciones: `/private/tmp/formulario3-reorden-20261015` (directorio restringido; contiene datos personales, **no versionar**). `ejecutar.sql` y `ejecutar-descartados.sql` **ya fueron ejecutados; no repetirlos**. La auditoría de corrección queda también en las actividades de producción. Una futura devolución de responsables requiere una nueva operación con lectura actual; no elimina la auditoría existente.

El plan en [FigJam](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34) se actualizó con la carga conciliada, automatización activa y esta corrección.

## Pendiente separado

La adaptación visual de Supervisores de Coordinación para identificar Formulario 3 sigue en preparación. No forma parte del traslado de datos ni está publicada. La migración `20261015145742_crm_coordinacion_campania_formulario3.sql` no se aplicó a producción.

Relacionado: [[Historial de derivaciones de Coordinacion]] · [[Leads - marca y filtro de reasignados (2026-09-28)]] · [[Formulario 3 - plan de integración en CRM y activación (2026-10-14)]].
