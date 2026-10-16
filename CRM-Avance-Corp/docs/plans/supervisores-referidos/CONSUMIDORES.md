# Consumidores de Referido

Inventario de catálogo productivo del 16/10/2026, antes del cambio: 37 funciones de crm/private cuyo cuerpo contiene `referido`. La huella corresponde al DDL leído; no se modifican salvo el alta indicada.

| Firma | SHA-256 DDL previo |
|---|---|
| `crm.alarma_conversion_fn(date)` | `b14da73ebb8f926947e28c545eb0034899e79d93f8c14767a09c00652f8d9f5c` |
| `crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text,text)` | `6f36af82083752b5c0a1783a2ca4c94fe3d78077de224621ad59c6f175abdc99` |
| `crm.cerrar_periodo(date)` | `d27742370b9bb8f3a442509d4d1a347dc826547b505fe2bf70602adb8ce6c541` |
| `crm.conversion_divisor_coordinacion_fn(date,date,date)` | `519aff917cefc57a985094f4d307538a4ea6e22a25e09d5d35fe62f29941f83e` |
| `crm.conversion_mensual_sin_cartera_fn(date)` | `fc5b563596b1e2c14b62909f498c09cd3826bc8b86f93df339fd55774dcf68ce` |
| `crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)` | `c2c20bd62c75eda3c8bcf0611d0a28e5057676dfa62e4e4207129ac55e1e6871` |
| `crm.cumplimiento_metas_fn(date)` | `c14138125b5fa1c21db23cae72b1d0ffd7e635090b907073d522a0d3d0147cbb` |
| `crm.cumplimiento_metas_sin_cartera_fn(date)` | `f3f8c2266510753c844df4ab30a1aaeee1c5f38fb2fdc4e0121bd850fa0bd03e` |
| `crm.metricas_conversiones_equipo_fn(date,date)` | `cf6a429f9f98db5a348874f52fc9fa3c6c3ee99179ecebafea07d493c78e7400` |
| `crm.metricas_multiempresa_fn(date)` | `9f7be5707b6074b7d746fb1052e9e413021ea2d0d8aa07fa3de9d02a816dbcd2` |
| `crm.metricas_vendedores_fn()` | `b034fce01b27f00844521a6df5a241d940dd621883d6e14366cc2967f3da447f` |
| `crm.resumen_cartera_fn()` | `3b8aa270a845d5d56d93f18fabd387de9bd9a46bddc9f92cbf99d8d80fa9e757` |
| `crm.series_comerciales_fn(integer)` | `5b7203e969c168e0f898f616db5efa813062d9cd43bd4658e48bf4580308e524` |
| `private.conversion_cierres_coordinacion(uuid,date,date,integer)` | `3a01854fca5d03a16924101e11829ee156a4622ac02493f8fd60ea80ea353b10` |
| `private.conversion_cierres(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric,uuid[])` | `48b1d5ee22cbb0be3d3bfa5210f8ccfdf76d3dcb4bf2c374546aa7de696d600d` |
| `private.conversion_divisor_base(date,date)` | `27583fd0c50b000e7b0e1aace5130e7e6ee3f3d3ef7f55101af500da2e7a6da0` |
| `private.conversion_divisor_empresa_totales(date,date)` | `8742246e4130f954b09cc27577704b48093418ae8cc5890fe083ca09833edade` |
| `private.conversion_divisor_empresa(date,date)` | `40931ecc43317c9f717fac6750c43ee290c7702bb70aa0c325e6a7a850b4ba3d` |
| `private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)` | `4214561b86a20e311e0905df04cad2f3c0984ebee0d16ce6f858cffbc1fce0ee` |
| `private.conversion_fijar_sello_trg()` | `2ab50c110f8c5ca0e88a9d3abd3d43bced01cf4d7a68f09524a37a999edef9cc` |
| `private.conversion_mensual_por_vendedor(timestamp with time zone,timestamp with time zone,boolean,uuid[],numeric)` | `2e73c4253dbc80721d25eafa7ecd87e4fd504fb537f1da4f259743212a9f64f9` |
| `private.conversion_neta_por_vendedor(date,boolean,uuid[])` | `4426d862a95d6edd795172d9ee696935b1132bd723b8dbffbea8d6ca594c9c41` |
| `private.conversion_origen_con_cierre(text)` | `d48de0740e533d07f062abcdebf455ee17daee7a98649099ec59539d2c1d5e63` |
| `private.leads_before_insert()` | `a52bf84ef419c02b209ba69a3155f49bf6cfa05c1b846381490d6977c905d998` |
| `private.leads_before_update()` | `3136f2db54350d4c79ebd807c4ea46c797728c263b03b5c3645eadaad4b95268` |
| `private.metricas_conversiones_implementacion(date,date,text)` | `30f5e73bbff8128c07a9e66ff2143f6d0bd2259978c121376909e6d5ad6268ae` |
| `private.metricas_distribucion_leads_core(date,date,timestamp with time zone)` | `c7a9a19c4f469d4aaa6a32d3a68bb162213787e4505639bb957333fd789d01cd` |
| `private.metricas_distribucion_leads_v3_core(date,date,timestamp with time zone)` | `8cf767e8b8b46ea49a6f7f2b327b82951977043565451e8071571e409f0b3b0f` |
| `private.metricas_reuniones_implementacion(date,date)` | `420b067cbe63f4ca22519ae26c16f6c68498ebccf9fc3946d96066a97368f5e5` |
| `private.peso_referido_conversion(date)` | `29047189ab01cd41b94683f0f13584e468211e4368d247b2213e42d68c6f3794` |
| `private.peso_renovacion_conversion(date)` | `ca4eb25d1543ad281e9e07dd28ee45957b86daead53d33cf3fbcb3e26d2f00df` |
| `private.ranking_conversion_origen_mes(timestamp with time zone,timestamp with time zone,date,numeric)` | `74fc56a5f41f9b29eaa1adfded4755ee491569e20d851f9ae821dc3de60de965` |
| `private.ranking_llegadas_origen_filas(timestamp with time zone,timestamp with time zone)` | `b8ee00c0b8436c13c0dc8a00da06d8508ffd2a014d23fc87b677e55a5071b853` |
| `private.ranking_origen_live(date,uuid,jsonb)` | `ee4a2937a46ee7d1e1a4d312592e6678ac46437847f024edd84bdb9cd617e1d0` |
| `private.referidos_aporte_por_analista(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)` | `285e33e74a7fcb8f5ac95bb4407da8096a13843acf952c7e8dfd6389e7b00c4d` |
| `private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)` | `905c7f85c8f45e92a7d504dd423fefe738807e46b5722417f793cd77676dc3d5` |
| `private.tope_referidos_conversion(date)` | `ec5e793e30149993b6216755e348250a27f215c4fa19df5c47d5d6e9d6851db6` |

## Conclusiones verificadas

- `conversion_cierres` y `conversion_episodios` atribuyen el cierre al UUID del responsable. El ensayo exige un cierre propio del supervisor, divisor 0 y aporte referido 0,15 con la política vigente; el total empresarial lo incluye una sola vez.
- `roster_metas_vendedores` exige rol vendedor activo. `roster_conversion_mensual` lo usa en el periodo corriente. `conversion_mensual_fn.responsables` no incorpora al supervisor al ranking de analistas; `cumplimiento_metas_fn` mantiene su producción fuera de ese ranking y el frontend ya publicado lo presenta al final.
- `ranking_conversion_origen_mes` consume el núcleo de episodios, sin cambiar peso ni tope; los reportes conservan su población y filtros existentes. `metricas_conversiones_fn` cuenta el nuevo cierre al filtrar Referido.
- Los triggers de origen inmutable y los sellos permanecen iguales. No se recalculan periodos históricos ni se alteran fórmulas. Los otros consumidores mantienen exactamente su DDL y ACL.

Evidencia de comportamiento: `sql-local.log` y `sql-cloud.log`, casos de cierre compartido, Cartera, capital propio, núcleo de conversión, total empresarial, roster y filtro por origen. Este inventario no equivale a probar exhaustivamente cada combinación de filtros de las 37 funciones.
