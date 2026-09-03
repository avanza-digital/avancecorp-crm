---
tags: [crm, multiempresa, f0, puertas, escritura, censo, solo-lectura]
fecha: 2026-09-03
estado: censo-inicial-solo-lectura-para-f0-y-f3
proyecto_supabase: dctqcbznekcyxhjujuci
capturado_en: 2026-09-03T14:35Z (09:35 Lima), transacción READ ONLY
---

# Catálogo de puertas de escritura — identidad e inversiones (F0)

Entregable de F0 del [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]]
(«inventariar todas las escrituras: lead, importación, conversión, perfil/Auth,
contrato, cierre externo, renovación, aumento y corrección»). Es el mapa que F3
(«una sola puerta para reconocer a la persona») tiene que cerrar: toda puerta
listada aquí deberá pasar por la primitiva canónica de identidad, y no puede
quedar ninguna fuera.

Método: censo en producción, solo lectura, sobre `pg_proc` de `crm`, `public` y
`private`: funciones cuyo cuerpo contiene `insert into | update | delete from`
seguido del nombre de la tabla. Exposición a la API medida con
`has_function_privilege` para `anon`, `authenticated` y `service_role`
(recordar: si PUBLIC tuviera EXECUTE, `has_function_privilege` lo enmascara —
ver [[Revocar a anon no basta]]; aquí todas las puertas son DEFINER con ACL
explícita). Complemento: edge functions del árbol `CRM-Avance-Corp/supabase/functions`.

## 1. `crm.leads` — 16 escritores

| Puerta | Expuesta a | Naturaleza |
|---|---|---|
| `crm.crear_lead_si_disponible(…)` | authenticated | **alta manual / importación** (la edge `crm-importar-leads` entra por aquí) |
| `crm.tomar_lead_libre(p_telefono, p_dni)` | authenticated | toma de lead libre |
| `crm.convertir_lead(p_lead_id, p_perfil_id)` | authenticated | **conversión Avance** (enlaza perfil) |
| `crm.convertir_lead_externo(…)` | authenticated | **conversión cooperativa** (escribe lead y cierre) |
| `crm.derivar_leads_equipo_fn(…)` / `crm.revertir_derivacion_equipo_fn(…)` | authenticated | reparto entre equipos |
| `crm.rescatar_descartes(…)` | authenticated | re-encolado |
| `crm.fijar_membresia_activa_fn(…)` | authenticated | offboarding (reasigna leads) |
| `private.descartar_lead_implementacion` / `deshacer_descarte_implementacion` / `repartir_lead_implementacion` / `retroceso_por_anular_reunion` | ninguna (internas) | implementación de descarte, reparto y retroceso |
| `private.trg_actividades_avance_etapa` / `trg_tareas_avance_etapa` / `trg_leads_sync_tareas` | triggers | avance de etapa y sincronización |

RLS: habilitado, 3 policies. La tabla además tiene **GRANT POR COLUMNA** a
`authenticated` (`rw`): existe escritura directa por PostgREST fuera de estas
funciones (el front edita campos del lead por columna). F3 debe decidir si esa
vía directa sigue o se canaliza.

## 2. `public.perfiles` — 8 escritores

| Puerta | Expuesta a | Naturaleza |
|---|---|---|
| `crm.convertir_lead_con_domicilio(…)` | authenticated | **conversión Avance con domicilio** (crea/enlaza perfil cliente) |
| `crm.completar_domicilio_cliente(…)` | authenticated | corrección |
| `crm.actualizar_cliente_gerencia(…)` (interna) / `…_con_domicilio(…)` (authenticated) | Gerencia | corrección de datos y bancos |
| `crm.registrar_candidato_usuario_fn(…)` / `crm.registrar_vendedor_usuario_fn(…)` / `crm.actualizar_usuario_administrable_fn(…)` | authenticated | **alta y edición de colaboradores** (multirrol) |
| `crm.fijar_membresia_activa_fn(…)` | authenticated | offboarding |

RLS: habilitado, 6 policies. La tabla es del Portal (`public`): el plan exige
que los puentes vivan en `crm` y no se alteren tablas `public` en silencio.
La creación de **Auth** (`auth.users`) no la hace ninguna función SQL: la hace
la edge **`crm-usuarios`** (service role) para colaboradores, y el flujo de
cliente Avance por el Portal. Es la única escritura de identidad fuera del
servidor SQL: F3 debe inventariarla como puerta service-role.

## 3. `public.contratos` — 9 escritores

| Puerta | Expuesta a | Naturaleza |
|---|---|---|
| `public.crear_contrato(p_contrato, p_cronograma)` | authenticated, service_role | **alta de contrato** (también escribe `crm.operaciones_cartera` en renovación/aumento) |
| `public.actualizar_contrato(…)` | authenticated | corrección |
| `public.actualizar_numero_contrato(…)` | ninguna (cerrada permanente por F7) | histórica |
| `crm.corregir_fecha_cierre_comercial(…)` | authenticated | corrección del periodo comercial |
| `public.reasignar_analista_contrato(…)` | authenticated, service_role | reasignación (ATR) |
| `public.marcar_contrato_demo(…)` | authenticated, service_role | clasificación demo |
| `public.marcar_contratos_vencidos()` | service_role | ciclo diario (cron 09:10 Lima) |
| `crm.contrato_eliminacion_finalizar(…)` | service_role | borrado con token |
| `private.trg_restaurar_operacion_antes_borrar_contrato()` | trigger | compensación |

RLS: habilitado, 5 policies; ACL de tabla concede `arwd` a `anon` y
`authenticated` (herencia del Portal) — las policies son las que mandan.

## 4. `crm.cierres_externos` — 3 escritores (todas authenticated, DEFINER)

`crm.convertir_lead_externo(…)` (**crea el cierre y convierte**),
`crm.corregir_cierre_externo(…)`, `crm.anular_cierre_externo(…)`.
RLS habilitado con **0 policies** (deny-by-default: solo las DEFINER entran).
Sigue vigente `UNIQUE (lead_id)`: la segunda inversión en cooperativa no tiene
puerta hoy — es exactamente lo que F4 crea.

## 5. `crm.operaciones_cartera` — 2 escritores

`public.crear_contrato(…)` (renovación y aumento) y el trigger de
compensación. RLS habilitado, 1 policy.

## 6. Fuera del SQL

- Edge `crm-usuarios` (Auth + perfil de colaboradores, service role).
- Edge `crm-importar-leads` (importación; entra por `crear_lead_si_disponible`).
- Puente Sheets→CRM de leads de landing (Apps Script → edge, cada 15 min; ver la
  sesión del puente): es un **escritor recurrente** de `crm.leads`.
- Portal: registro de cliente Avance (Auth + `perfiles`) por su propio flujo.
- Front CRM: edición por columna de `crm.leads` vía PostgREST (GRANT por columna).

Triggers activos sobre las cinco tablas: **43**. Ninguno crea identidad; varios
mueven etapa, tareas y auditoría.

## Lectura para F3

Hoy la «persona» se escribe por **cuatro caminos distintos** que no se
conocen entre sí: alta/toma de lead (`crm.leads`), conversión Avance (perfil +
Auth por Portal/edge), conversión cooperativa (`cierres_externos`) y alta de
colaborador (`perfiles` + edge). F3 debe hacer que las **puertas de creación**
(`crear_lead_si_disponible`, `tomar_lead_libre`, `convertir_lead*`,
`convertir_lead_externo`, `crear_contrato`, `registrar_*_usuario_fn`, la edge
`crm-usuarios` y el registro del Portal) pasen por la primitiva única de
identidad; las de corrección y ciclo (marcar vencidos, reasignar, anular,
corregir) no crean persona y solo necesitan respetar el enlace.

Relacionado: [[Manifiesto productivo G0 multiempresa (2026-09-01)]] ·
[[Contrato arquitectonico consolidado - identidad unificada de inversionistas (F0 2026-08-31)]] ·
[[Censo F0 de identidad unificada - resultado de solo lectura (2026-08-31)]]
