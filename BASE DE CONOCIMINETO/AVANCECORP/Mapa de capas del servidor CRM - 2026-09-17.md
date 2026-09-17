---
tags: [servidor, arquitectura, mapa, capas, auditoria]
fecha: 2026-09-17
estado: publicado
---

# Mapa de capas del servidor CRM (2026-09-17)

**Artifact interactivo (privado):** https://claude.ai/artifact/7rSe49eefhyVyuXgKZpg81
**Evidencia y scripts:** `SERVIDOR-CRM/mapa-capas-2026-09-17/` (ver su `LEEME.md`).

Mide la regla nueva del `CLAUDE.md` («Arquitectura en 4 capas»): **Tablas → Núcleo → Puerta → Pantalla**, cada capa
solo habla con la inmediata. Sucede al [[Mapa del servidor CRM en Figma - 2026-09-06]] (que era un mapa de
bifurcaciones, no de capas) y se apoya en el catálogo VIVO del 17/09 (651 funciones, 118 relaciones, 20 Edge,
10 cron), no en memoria.

## Números

- 3 474 conexiones reales → **398 líneas sanas** y **171 saltos**: A 56 · M 81 · B 31 · D 3. Solo 1 en corrección.
- **39 saltos pantalla → tabla**: el front lee o escribe directo `crm.leads` (16 pantallas + el store al arrancar),
  `crm.tareas`, `crm.actividades`, `crm.recordatorios_disponibilidad`, `crm.alertas_reconocimientos`, `crm.agenda_ics`,
  `crm.operaciones_cartera`, `public.perfiles`; el portal, 10 tablas de `public`.
- **152 puertas mixtas** (usan núcleo pero además tocan tablas) y **24 puertas autónomas** (toda la lógica en la
  puerta, sin núcleo), entre ellas `editar_lead_fn`, `convertir_lead_con_domicilio`, `historial_derivaciones`,
  `reporte_derivaciones_equipo_fn`, `cronograma_contrato_fn`, `titulares_contrato_fn` y los predicados `public.es_*`.
- **21 inversiones** (núcleo que depende de una puerta): sobre todo `private.*` llamando `crm.bandera_activa` y las
  herramientas `assert_*` llamando puertas SLA.
- **Edge con `service_role` sobre tablas sin núcleo:** `crear-cliente`, `crm-convertir-lead`, `corregir-correo-cliente`,
  `eliminar-cliente`, `importar-clientes`, `enviar-*`, `notificar-pagos`, `resetear-password`, `crear-admin`.
- **52 objetos sin llamador** (38 puertas): confirma el enlace muerto de capital de Gerencia
  (`metricas_capital_mes_fn`, `metricas_pagos_mes_fn`, `metricas_vencimientos_fn`), `leads_recibidos_analista_fn`
  (componente nunca montado), `ingresos_reparto_mes_fn`, `series_comerciales_fn`, `resumen_tareas_fn`,
  `marcar/levantar_no_contactar`, la fusión de inversionistas (`fusionar_*`, `fusion_previsualizar_fn`) y
  `cartera_inversionistas_fn` (superada por la filtrada).
- 20 funciones de `private` tienen EXECUTE para `authenticated` (las usan las políticas RLS) y 4 triggers viven en `crm`.
- Referencias no resueltas: `crm.reclamar` (wrapper `rpc()` de `crear-cliente`) y `public.comunicados` (portal).

## Decisiones del mapa

- Nodos de Tablas/Núcleo/Puertas agrupados por módulo (17); las pantallas una a una. A nivel objeto el servidor tiene
  810 nodos y no cabe en una fila por banda; cada línea conserva sus conexiones reales para verlas al clic.
- Capa por esquema y no por permiso: una función de `crm` sin EXECUTE es una **puerta cerrada**, no núcleo (así lo
  nombra el propio proyecto). Las 15 piezas F7 `cerrada_permanente` sí cuentan como núcleo.
- Acceso/permisos y auditoría se dibujan como transversales (apagadas por defecto): alimentan a todo.
- Pendiente opcional: versión estática en FigJam (no se generó; con 569 líneas sería ilegible sin filtros).

Relacionado: [[PLAN MAESTRO del servidor (P-055) - de la deuda a la capa semantica]],
[[Capa semantica del servidor - plan por nucleos (episodios)]], [[Funciones sueltas del servidor CRM - 2026-09-06]].
