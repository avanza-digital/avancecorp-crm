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

## Publicación en producción

Publicado en `https://crm.miavance.com` el 2026-09-04 mediante el flujo de [[Deploy a Hostinger]].

- Release: `crm-20260904T194617Z-41a24d3bb98a`.
- Build visible: `build-20260904T194616928Z`.
- Commit desplegado: `41a24d3bb98ac35f8b1e413426b9b3f41b92d392`.
- SHA-256 del ZIP: `0eb1c2ccc4928256f13802f57c32a25b441f9e2098e1653e055d1d86928ff332`.
- El preflight confirmó la sucesión desde `dc6c83e5aa37`; el artefacto anterior queda disponible como rollback.
- Los gates completos aprobaron: lint, tipos, 2.646 pruebas, configuración de release, build, bundle y duplicación.
- La comprobación posterior confirmó raíz y activos con HTTP 200, hashes idénticos al manifiesto, el nuevo `version.json`, salud de Supabase Auth y ausencia de exposición pública del ZIP.
- Una pestaña abierta antes de publicar puede conservar el índice anterior y debe recargarse una vez para tomar los chunks nuevos.

## Aclaración posterior sobre la base de conversión

El 2026-09-04 Miguel aclaró que la lectura gerencial buscada debe partir de los **leads que realmente ingresaron al sistema**, no de la cantidad de pares analista–lead generados por asignaciones y reasignaciones. También confirmó que los **upgrades elegibles suman conversión** y no crean otro lead en la base.

La comprobación agregada de producción para el 01–03 de setiembre encontró:

- 176 altas automáticas de los canales de entrada: 104 de Formulario y 72 de Landing;
- 8 altas manuales adicionales rotuladas como Formulario/Landing y 1 referido manual;
- 10 cierres no referidos ocurridos en el período: 6 Formulario, 1 Landing, 1 Oficina y 2 Otro;
- 3 upgrades registrados, de los cuales 2 son elegibles para conversión;
- ninguna renovación ni cierre referido en ese período.

La cifra visible de 345 para el 01–04 no representa leads únicos: son pares analista–lead no referidos. Corresponde a 300 leads únicos; 45 fueron asignados a dos analistas y sumaron dos veces. Para el 01–03 esa misma base por asignación era 289.

Quedaron detectadas dos brechas que deben corregirse en el núcleo existente, sin crear otra calculadora:

1. `metricas_conversiones_implementacion` cuenta filas no referidas y no suma `aporte_divisor`, por lo que incluye altas manuales que `conversion_episodios` ya marca con aporte cero.
2. La pierna de cartera solo se activa para mes completo o mes hasta hoy; al consultar 01–03 el 04/09 omite los 2 upgrades elegibles del período.

Antes de cambiar la definición debe cerrarse si los 3 cierres rotulados Oficina/Otro permanecen en el numerador de la lectura gerencial. Con todos los cierres reales del período, el numerador sería 10 + 2 upgrades = 12; restringiéndolo a Landing/Formulario sería 7 + 2 = 9. La regla vigente de referidos sigue siendo: no entra al divisor y un cierre aporta 0,15.

Relacionado con [[Conversion mensual - definicion cerrada]], [[Contrato de la capa semantica - Leads y Citas (F6, 2026-08-30)]] y [[Inicio]].
