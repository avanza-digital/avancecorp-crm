---
tags: [supabase, branching, multiempresa, f1, diagnostico, solo-lectura]
fecha: 2026-09-01
estado: aclarado-2026-09-03-causa-documentada-decision-de-via-pendiente
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

## Aclaración (2026-09-03, 09:35 Lima, con la documentación oficial de Supabase)

Fuente: guía «Troubleshooting MIGRATIONS_FAILED: missing tables or an incomplete
schema on your branch» (`supabase.com/docs/guides/troubleshooting/branch-in-migrations-failed-status`).

**Qué significa el estado.** Un branch se construye *replayando* la historia de
migraciones registrada en `main` sobre una base vacía. Si ese replay falla a
medias, el branch queda vacío o incompleto y marcado `MIGRATIONS_FAILED`. Según
Supabase, «casi siempre» significa que **la historia de migraciones de `main`
no coincide con su esquema vivo**: cambios aplicados a mano (SQL Editor,
`db query`) que nunca se registraron como migración, o migraciones registradas
que no se pueden volver a ejecutar desde cero.

**Por qué aplica aquí.** Es exactamente nuestra situación, y no es una avería:

- producción aplica con `db query --linked --file`, que **no registra** en
  `schema_migrations` (hoy: `20260902190000` y `20260902201000` aplicadas sin
  registro);
- el repo contiene `20260902200000`, que **nunca se aplicó ni puede aplicarse**;
- muchas migraciones llevan preflights «anclados al vivo» (md5 del cuerpo,
  censos de filas de producción) que **abortan por diseño** en una base vacía —
  por eso el banco se replay-a a mano con `replay.py`, siembras y
  `parches/DIVERGENCIAS.md` (ver [[El branch no se replay-a solo]]).

El `MIGRATIONS_FAILED` de `main` (fechado en su creación, 2026-07-11, nunca
actualizado) y el de `banco-f7` (01/09) son el mismo fenómeno: el estado del
control plane refleja el último intento de replay automático, no la salud de la
base (`ACTIVE_HEALTHY` en ambos). **No bloquea F1**; solo fija cómo se crea su
branch.

**Dos vías para el branch aislado de F1 (decisión de Miguel):**

1. **Vía probada — replay manual** con el arnés `supabase/scripts/banco/`
   (`volcar.py` → siembras → `replay.py` → `reregistrar.py` → `paridad-banco.sql`),
   como el 01/09 (196/196 al byte). Costo: horas de trabajo por branch; el
   estado seguirá diciendo `MIGRATIONS_FAILED` aunque el banco esté a paridad.
2. **Vía que propone Supabase — línea base**: una migración *baseline* que
   encapsule el esquema vivo actual (más `migration repair` para alinear el
   registro), de modo que los branches nuevos se construyan solos. Costo: es un
   cambio de régimen del repositorio (la historia anterior pasa a ser
   documental), exige que TODAS las sesiones lo adopten y choca con la regla
   del plan «no usar `migration repair` para ocultar la divergencia» — aquí no
   la ocultaría, la corregiría, pero hay que decidirlo expresamente.

Mientras no se decida, **F1 usa la vía 1**. En cualquier caso, antes de crear el
branch de F1 hay que registrar `190000` y `201000` (o incluirlas en el volcado)
y excluir `200000`.
