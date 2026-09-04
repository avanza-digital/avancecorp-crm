# Conversión de Gerencia respeta el rango visible

Fecha de decisión: 2026-09-04.

## Incidente

Con el filtro visible del 01 al 03 de setiembre de 2026, el Resumen y la pantalla de Conversiones mostraban la foto mensual calculada hasta el día 04: **317 asignaciones contabilizadas**, 10 cierres, 2 operaciones de cartera y 3,79 %. Para el rango realmente seleccionado, el núcleo canónico devolvía **289 asignaciones contabilizadas**, 10 cierres, 0 operaciones de cartera y 3,46 %.

317 y 289 cuentan episodios de asignación analista–lead del contrato canónico; no representan personas únicas ni deben rotularse simplemente como “recibidos”.

## Decisión de producto y datos

- La cifra principal de conversión en Resumen y Conversiones usa directamente `crm.metricas_conversiones_fn.nucleo` para las fechas visibles.
- `crm.conversion_mensual_fn` se conserva para metas, capital, ranking y detalle estrictamente mensual.
- El cliente no vuelve a dividir, ponderar ni reconstruir la conversión: pinta `divisor`, componentes del numerador y `conversion_pct` ya servidos por la capa semántica.
- No se creó ninguna función, RPC ni calculadora adicional.
- El filtro por origen recorta Cosecha y embudo. El núcleo canónico de conversión sigue siendo de todos los orígenes y la interfaz debe decirlo explícitamente.
- En rangos parciales, `incluye_cartera = false` implica que la cifra no incorpora operaciones de cartera; la interfaz debe advertirlo.
- La compatibilidad con servidores antiguos sin `nucleo` conserva la foto mensual, pero siempre rotulada como mensual para no mezclar períodos.

## Regla permanente

Toda cifra principal debe responder al período que el usuario ve en el filtro. Las lecturas mensuales que convivan en la misma pantalla deben estar identificadas como mensuales y no pueden sustituir silenciosamente al rango seleccionado.

Relacionado con [[Conversion mensual - definicion cerrada]], [[Contrato de la capa semantica - Leads y Citas (F6, 2026-08-30)]] y [[Inicio]].
