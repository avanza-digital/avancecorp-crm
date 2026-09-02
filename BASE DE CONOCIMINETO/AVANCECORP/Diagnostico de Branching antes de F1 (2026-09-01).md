---
tags: [supabase, branching, multiempresa, f1, diagnostico, solo-lectura]
fecha: 2026-09-01
estado: pendiente-aclaracion-control-plane
---

# Diagnóstico de Branching antes de F1

Relacionado con [[Manifiesto productivo G0 multiempresa (2026-09-01)]] y
[[El branch no se replay-a solo]].

## Evidencia de solo lectura

El 2026-09-01 se volvió a consultar Supabase sin mutaciones:

- producción `PortalAvanceCorp` está `ACTIVE_HEALTHY`;
- producción registra `198` migraciones, desde `20260708000000` hasta
  `20260902050000`;
- `banco-f7` también registra exactamente las mismas `198` migraciones y la
  misma última versión;
- Branching etiqueta tanto `main` como `banco-f7` con
  `MIGRATIONS_FAILED`, aunque ambos exponen `preview_project_status` =
  `ACTIVE_HEALTHY`;
- los logs `branch-action` disponibles para las últimas 24 horas están vacíos.

## Interpretación

`MIGRATIONS_FAILED` no demuestra una falla de la base ni un replay parcial: el
catálogo de migraciones está completo en ambos proyectos y las bases responden.
La hipótesis principal es metadata obsoleta del control plane de Branching o un
paso de orquestación posterior al SQL que falló y cuyo log ya no está disponible.
La causa exacta no puede afirmarse sin el historial del workflow o soporte de
Supabase.

## Gate para F1

- No usar `banco-f7` como branch de F1: además del estado ambiguo conserva el
  residuo declarado de la prueba de carga.
- No ejecutar `reset` sobre `banco-f7`: Supabase reconstruye el branch y la
  operación destruiría sus datos, incluido el ledger que debe conservarse.
- Antes de crear el branch de F1, obtener de Supabase la causa o limpieza del
  estado `MIGRATIONS_FAILED` de `main` y conservar evidencia del workflow.
- Solo después, crear un branch nuevo con autorización/costo explícitos y exigir
  como preflight: estado sano, `198` migraciones, trinquete `0` y oráculos G0.

## Reloj de Capital

El gate temporal no debe tratarse como una alternativa entre prueba y arreglo.
La secuencia segura es: fijar primero un oráculo reproducible con instantes de
borde UTC/Lima; si confirma el contrato comercial de Lima, autorizar aparte la
corrección coordinada de `crm.metricas_capital_mes_fn` y
`crm.metricas_vencimientos_fn`; después recapturar huellas, guardianes,
trinquete y oráculos antes de firmar G0.
