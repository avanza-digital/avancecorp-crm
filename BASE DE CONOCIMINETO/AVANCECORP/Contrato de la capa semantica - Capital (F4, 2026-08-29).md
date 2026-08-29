# Contrato de la capa semántica — CAPITAL (Fase 4 del P-055)

Escrito el 2026-08-29, en la semana quieta del cierre: **nada de esto se publica antes del 10/09**.
Molde: [[Capa semantica del servidor - plan por nucleos (episodios)]] (F0+F1) y el núcleo vivo
`private.conversion_episodios`. Las «preguntas duras» que F0 dejaba abiertas **ya están
respondidas** por las 21 decisiones del [[PLAN MAESTRO del servidor (P-055) - de la deuda a la capa semantica]].

## La fila-hecho de capital

`private.capital_episodios(p_ini timestamptz, p_fin timestamptz, p_global boolean, p_visibles uuid[])`
→ TABLE, `SECURITY DEFINER`, `search_path=''`, **sin grants a la API** (regla 1: el núcleo no autoriza).

| Columna | Tipo | Qué significa |
|---|---|---|
| `tipo` | text | `contrato_nuevo` · `renovado` · `adicional` · `upgrade` · `cooperativa` |
| `contrato_id` | uuid | el contrato (NULL para cooperativa) |
| `cierre_externo_id` | uuid | el cierre en coop (NULL para contratos) |
| `cliente_id` | uuid | de quién es la plata |
| `analista_id` | uuid | **de quién es la venta** — `analista_cierre_id` (decisiones 1 y 2; F3 lo cableó) |
| `registrado_por` | uuid | quién la tecleó (se conserva aparte, decisión de la F3) |
| `en_roster` | boolean | si el analista tenía meta publicada ese mes (decisión 15: **columna informativa, NO descuenta**) |
| `moneda` | text | PEN o USD — **jamás se suman** (regla vigente) |
| `monto` | numeric | el capital del episodio (para `renovado`/`adicional`, el desglose de la operación) |
| `mes_comercial` | date | primer día del mes de `fecha_cierre_comercial` (decisión 3) |
| `fecha` | timestamptz | el instante real del episodio |
| `estado` | text | `activo` · `vencido` · `renovado` · `retirado` (del contrato) / `vigente` · `anulado` (coop) |
| `anulado` | boolean | si gerencia lo anuló (los anulados **aportan 0 pero se listan**: historial, decisión 15) |
| `es_demo` | boolean | siempre false en la salida (los demos **no salen del núcleo**, decisión 6) — la columna existe para el mutante |

**Fuentes:** `public.contratos` (¬es_demo) · `crm.operaciones_cartera` (desglose renovado/adicional,
decisión 5) · `crm.cierres_externos` (decisión 4: las coops SON capital, solo vigentes) ·
`crm.ajustes_mes_cerrado` NO entra como fila-hecho: es deuda del analista, no capital de la empresa
(regla de Miguel del 29/08) — la leen solo las escritoras del sellado.

## Las dos preguntas de cada pantalla (decisión 17)

- **«¿Qué entró en el período?»** → filtra por `mes_comercial`/`fecha` — el capital del mes.
- **«¿Qué está vigente hoy?»** → filtra por `estado` — el **AUM**. Misma calculadora, cifra aparte.
- El **pipeline estimado** (decisión 16) NO vive aquí: otra métrica, otra ficha.

## La ventana (regla 2)

`private.capital_autorizada(p_desde date, p_hasta date, p_pregunta text)` → resuelve actor con
`private.rol_crm` / `es_lector_global`, visibilidad con `private.vendedor_ids_visibles`, y llama
al núcleo. Nada llega al núcleo sin pasar por aquí.

## Superficie de migración — los 16 consumidores, en 3 tandas + las escritoras

| Tanda | Funciones | Cuándo |
|---|---|---|
| **a** Gerencia | `metricas_capital_mes_fn` · `metricas_cartera_fn` · `metricas_vendedores_fn` · `metricas_vencimientos_fn` | tras el 10/09 |
| **b** Cartera/ficha | `resumen_cartera_clientes_fn` · `contratos_por_periodo_comercial_fn` · `metricas_cartera_por_vendedor` · `produccion_mes_por_vendedor` · `metricas_conversiones_implementacion` · `metricas_reuniones_implementacion` | tras la a |
| **c** Portal | `dashboard_admin_metricas` · `directorio_ranking_analistas` · `directorio_top_clientes` · `metricas_directorio` | tras la b |
| **escritoras** | `crm.cerrar_periodo` · `private.registrar_ajuste_si_mes_cerrado` — leen del núcleo, siguen escribiendo el ledger | **AL FINAL y nunca la semana de un cierre** |

Método de cada tanda: banco + **oráculo de paridad en la misma transacción** (md5 del payload
antes/después, byte a byte) + mutantes + grep del front por recalculos + auditor-rls + gate.
**Nada viejo se borra** (regla de Miguel): REVOKE → observar → DROP con su OK.

## El trinquete (F0.4 del diseño)

Prueba estructural sobre `pg_proc`: fuera de `private`, nadie agrega `contratos.capital`,
`operaciones_cartera.capital_renovado/adicional` ni `cierres_externos.monto`. Constante que
**solo baja** (hoy: 16), meta 0. Borrador en `supabase/scripts/trinquete-capital.sql`.

Relacionado: [[Auditoria servidor Supabase - duplicacion y deuda (2026-08-28)]] ·
[[Auditoria conversion CRM - inventario y diseno de unificacion (2026-08-26)]]
