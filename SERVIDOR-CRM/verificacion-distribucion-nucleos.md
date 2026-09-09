# Distribución y calculadoras: contraste vivo

Verificación Supabase de solo lectura, 06/09/2026 Lima. Proyecto `dctqcbznekcyxhjujuci`. Consultas al catálogo `pg_proc`/`pg_namespace`, cuerpos de funciones y `has_function_privilege`, dentro de transacciones `READ ONLY` terminadas en `ROLLBACK`. No se ejecutaron RPC comerciales ni se consultaron filas de clientes.

Evidencia completa: [evidencia-distribucion-dependencias.json](./evidencia-distribucion-dependencias.json). Los cuerpos `conversion_episodios`, `capital_episodios`, `citas_episodios`, `metricas_reuniones_fn`, `metricas_cartera_fn` y `conversion_mensual_fn` también están en [evidencia-sql.json](./evidencia-sql.json).

## Qué está cerrado y qué sigue funcionando

| Objeto | EXECUTE authenticated | EXECUTE anon | Conclusión |
|---|---|---|---|
| `crm.metricas_distribucion_leads_fn` (v1) | No | No | Puerta antigua conservada y cerrada al usuario |
| `crm.metricas_distribucion_leads_v2_fn` | No | No | Puerta antigua conservada y cerrada al usuario |
| `crm.metricas_distribucion_leads_v3_fn` | Sí | No | Puerta usada por el frontend actual; el cuerpo valida acceso |
| `private.metricas_distribucion_leads_autorizada` | No | No | Dispatcher interno; exige Gerencia o lector global y valida rango |
| `private.metricas_distribucion_leads_core` | No | No | Motor base interno todavía utilizado |
| `private.metricas_distribucion_leads_v2_core` | No | No | Motor interno todavía utilizado por v3 |
| `private.metricas_distribucion_leads_v3_core` | No | No | Motor interno de la versión actual |

**Hallazgo estructural confirmado:** cerrar la puerta de la versión antigua no elimina el uso de sus piezas internas. El recorrido actual es:

`Gerencia → crm.metricas_distribucion_leads_v3_fn → private.metricas_distribucion_leads_autorizada(versión 3) → private.metricas_distribucion_leads_v3_core → private.metricas_distribucion_leads_v2_core → private.metricas_distribucion_leads_core`.

El core v2 llama además a `private.metricas_sla_global_core`. Los tres niveles construyen/amplían un resultado; la v3 incorpora conversión canónica. El wrapper público v3 retira varios campos SLA antes de entregar la respuesta a pantalla. Esto documenta encadenamiento y posible trabajo prescindible que podría estudiarse; no demuestra un defecto comercial ni un problema de rendimiento sin medirlos.

El dispatcher conserva ramas 1/2/3, pero cada wrapper fija su versión. No se deben convertir automáticamente todas sus ramas en caminos de ejecución de todos los wrappers. La versión 3 no entra por la rama 1 del dispatcher: llega al motor base porque su propio motor reutiliza v2.

## Evidencia del consumidor de pantalla

Solo se encontró la llamada V3 en el código de aplicación examinado (`CRM-Avance-Corp/app/src`, `public_html/js`, `_supabase_functions/functions`; excluyendo tests, mapas y tipos generados):

- `CRM-Avance-Corp/app/src/screens/hoy/gerencia.tsx:294`: `useMetricasDistribucionLeadsV3(...)`.
- `CRM-Avance-Corp/app/src/data/crm-queries.ts:582`: hook; línea 585 llama `listarMetricasDistribucionLeadsV3`.
- `CRM-Avance-Corp/app/src/data/crm-api.ts:3938`: función; línea 3950 llama `crm.metricas_distribucion_leads_v3_fn`.
- `CRM-Avance-Corp/app/src/lib/metricas-distribucion.ts:4` contiene un comentario de contrato V2; es documentación/tipado, no otra llamada al servidor.

No se midió tráfico. La conclusión exacta es **ruta presente y utilizada por el código actual**, no «se ha observado N veces en producción».

## Conexiones que sí deben dibujarse

En la tabla, las flechas van de la pantalla hacia la función solicitada y las calculadoras que utiliza. En un diagrama de suministro de información pueden invertirse, siempre que la leyenda lo aclare.

| Pantalla / pregunta comercial | Recorrido confirmado en cuerpos vivos |
|---|---|
| Conversiones de Gerencia | `crm.metricas_conversiones_fn → private.metricas_conversiones_implementacion → conversion_episodios + citas_episodios + capital_episodios` |
| Citas / Reuniones | `crm.metricas_reuniones_fn → private.metricas_reuniones_implementacion → citas_episodios + conversion_episodios + capital_episodios` |
| Distribución V3 | `crm.metricas_distribucion_leads_v3_fn → dispatcher(3) → v3_core → conversion_episodios / conversion_mensual_por_vendedor`; además `v3_core → v2_core → base_core → conversion_episodios`, y `v2_core → metricas_sla_global_core` |
| Capital por mes | `crm.metricas_capital_mes_fn → private.capital_episodios` |
| Vencimientos | `crm.metricas_vencimientos_fn → private.capital_episodios` |
| Gestión de cartera | `crm.metricas_cartera_fn → private.metricas_cartera_por_vendedor → conversion_episodios + capital_episodios` |
| Conversión mensual | `crm.conversion_mensual_fn → crm.conversion_mensual_sin_cartera_fn → private.conversion_mensual_por_vendedor → conversion_episodios`; la composición de cartera llega también a `private.metricas_cartera_por_vendedor` |
| Ranking / rendimiento de vendedores | `crm.metricas_vendedores_fn → crm.conversion_mensual_fn`, con el recorrido anterior |
| Conversión por equipo | `crm.metricas_conversiones_equipo_fn → private.conversion_episodios` y `private.conversion_mensual_por_vendedor` |
| Resumen operativo de cartera | `crm.resumen_cartera_fn → private.conversion_episodios` |
| Series históricas | `crm.series_comerciales_fn → private.conversion_episodios`; porcentaje oficial por `private.conversion_mensual_pct_para_series → crm.conversion_mensual_fn` |

`private.conversion_mensual_por_vendedor` agrupa los aportes de `private.conversion_episodios`. Los componentes privados de la tabla no tienen EXECUTE para authenticated/anon según el catálogo medido.

**Para el dibujo:** Conversiones y Citas son pantallas que combinan varias preguntas, por eso reciben datos de tres calculadoras. Distribución presenta montos/segmentación operativa pero no se encontró una llamada suya al núcleo de capital; no debe conectarse a `capital_episodios` por asociación del nombre «capital» en la pantalla.

## El control de acceso no pasa siempre por una sola función

La arquitectura deseada del vault habla de una ventana por núcleo. El código vivo tiene varias formas de aplicar el ámbito permitido:

- Distribución sí usa `private.metricas_distribucion_leads_autorizada`.
- `crm.metricas_capital_mes_fn` llama al núcleo directamente y filtra el resultado con `private.rol_crm`, `private.es_lector_global` y `private.vendedor_ids_visibles` en su propio cuerpo.
- `crm.metricas_conversiones_fn` valida Gerencia/lector global y su implementación interna vuelve a comprobar acceso.
- Reuniones conserva autorización en su implementación interna.
- Existe `private.capital_autorizada`, pero no es un paso universal en los recorridos medidos de Gerencia.

Representar «control de acceso y ámbito» como capa transversal es correcto. Dibujar **todas** las flechas pasando por `capital_autorizada` sería incorrecto. La repetición de controles es una cuestión de estructura/mantenimiento; este análisis no la presenta como una vulnerabilidad.

## Límites del índice de dependencias

`paths_candidates` en el JSON se obtuvo buscando llamadas cualificadas en cuerpos sin comentarios y siguiendo hasta cinco saltos. Es una ayuda de navegación: también puede capturar nombres dentro de strings y combina ramas sin interpretar condiciones. Las conexiones recomendadas arriba fueron contrastadas con los cuerpos y las versiones fijas de wrappers; no usar automáticamente el resto de rutas candidatas como evidencia de ejecución.
