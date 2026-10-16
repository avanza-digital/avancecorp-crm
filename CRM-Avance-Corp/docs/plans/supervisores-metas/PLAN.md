# Ventas propias de supervisores y meta de equipo

Decisiones de Miguel, 16/10/2026:

- Las ventas propias conservan su atribución personal y aportan a la meta del equipo.
- Vigencia desde el periodo comercial octubre de 2026; septiembre y anteriores conservan su comportamiento.
- Los supervisores aparecen después de todos los analistas en el ranking.
- Claude y JEV apoyan la revisión; Codex es el único escritor.
- Copia aislada autorizada: `/private/tmp/avancecorp-supervisores-20261016`, desde main `65764411`.

## Implementación

La migración modifica únicamente `crm.cumplimiento_metas_fn(date)`, cuya firma, ACL, modo de ejecución y claves JSON se conservan. Desde octubre, un supervisor activo recibe en `fuera_ranking` únicamente su propia fila. El filtro por UUID se aplica antes de unir nombres y membresías. Gerencia, Directorio y Coordinación conservan exactamente su respuesta anterior. Analistas no adquieren esta capacidad.

En meses cerrados se filtra la fotografía existente de `periodos_cerrados.cobertura.fuera_ranking` por identidad, rol y motivo. No se recalcula ni se escribe el sello. Sin actividad no se fabrica una fila, igual que en el contrato histórico. La identidad comercial sigue siendo la de la venta, no la del usuario que la cargó.

El adaptador del frontend separa para presentación las filas de supervisor desde octubre, sin añadir ninguna clave a la RPC ni modificar su esquema estricto. El cumplimiento del equipo añade capital y contratos propios por categoría y moneda. Conserva el objetivo de conversión de los analistas; la conversión real sigue viniendo de su RPC canónica. El agregado de empresa continúa sumando las mismas filas exactamente una vez.

Una sección final «Ventas propias de supervisores» muestra la atribución personal y el aporte al equipo, después del ranking de analistas y de los demás responsables externos. No cambia puestos ni desempates de analistas. No se crean metas individuales nuevas: Miguel no fijó una meta personal de supervisor.

## Compatibilidad y límites

- El servidor y el cliente anterior siguen compartiendo el mismo contrato. El comportamiento visual y la suma al equipo requieren publicar también el cliente actualizado.
- Se conserva la pertenencia mensual ya publicada. No se reatribuyen ventas ni se reescriben metas o cambios históricos de rol. En la consulta agregada productiva previa, ninguno de los cuatro supervisores activos tenía una meta de analista en octubre.
- Un supervisor sin analistas puede ver su venta con meta cero. Sin actividad se conserva el estado vacío.
- CodeGraph fue intentado primero y falló con `unable to open database file`; se usaron consultas y lecturas puntuales. No se reindexó.
- No se modifican tablas, triggers, policies, grants ni tipos de retorno. No requiere regenerar `database.types.ts`.

## Evidencia

- Función productiva leída sin mutaciones: `md5(prosrc)=be18b2feac623d18db695830d70e2a2e`.
- Migración y reversa protegidas por huellas; ambas rechazan una definición distinta a la revisada.
- Banco PostgreSQL exclusivo vacío, con fixtures sintéticos, triggers activos y llamadas como `authenticated`. Todas las escrituras y DDL se revierten al finalizar.
- Matriz de nueve actores en septiembre, octubre y noviembre sellado, antes/después: paridad JSON global y de analistas, aislamiento personal y histórico.
- Pruebas unitarias del corte, contratos/capital, meta de conversión, total empresa, ausencia de metas personales y orden final; E2E local en Docker de supervisión, gerencia y regresiones históricas.

Estado: implementado y verificado localmente; pendiente de promoción autorizada. Ver [LEEME del ensayo](../../../supabase/scripts/supervisores-metas/LEEME.md) y [verificación](VERIFICACION.md).
