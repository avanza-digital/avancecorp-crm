---
tags: [git, integracion, pendientes, gloria]
fecha: 2026-09-27
estado: main local integrado con GitHub; PR #114 abierta (sin lo de Gloria); limpieza parcial
---

# Integración del main local y pendientes (27/09/2026)

## Qué se hizo

- **Fusión** de `avancecorp/main` (#101–#113) con el `main` local, preparada en un worktree
  aparte → `4b324f7c`. `npm run check` PASS (4.468 tests, lint, typecheck, build, bundle, jscpd).
  Conflictos: P-0XX (5 archivos) con la versión de GitHub, posterior y ya aplicada;
  `MIGRACIONES.md` e `Inicio.md` por unión; `database.types.ts` igual al de GitHub.
- **Commits locales:** `46b0030a` (12 notas del vault del 25–27/09) y `dfec66df` (backfill de
  conversión de setiembre, recuperación del correo de acceso, `.codegraphignore`).
- **PR #114** a GitHub con 46 archivos (instrucciones, vault, scripts). Miguel la fusiona por squash.

## Decisión de Miguel: lo de Gloria NO va a GitHub

«Lo de Gloria no se sube a GitHub, solo CRM» / «déjalo fuera del CRM». Se tomó como todo el
trabajo del portal del 26/09: **cuentas de Gloria** (F1–F5 y arreglos) y **Pagos del portal**
(F1–F5, retiro de `admin_pagos_resumen`). Queda SOLO en el `main` local:

- migraciones `20260926182748`, `20260926193424`, `20260926200757`, `20260926204051`,
  `20260927012948`, `20260927020317`, `20260927024423` (todas aplicadas en producción);
- `supabase/scripts/cuentas-gloria/`, `registrar-`/`reversa-portal-admin-pagos-resumen.sql`;
- Edge `_supabase_functions/functions/notificar-cambio-cuenta/`;
- encargos `docs/encargos/2026-09-26-codex-*`; sus secciones de `MIGRACIONES.md`;
- notas [[Cuentas bancarias - Gloria ve y añade cuentas, fase 1 publicada (2026-09-26)]],
  [[Cuentas de Gloria - F3 cambiar la cuenta de pago, en producción (2026-09-26)]] y
  [[Portal Pagos - plan de mejora en Figma (2026-09-26)]];
- el puntero de `public_html` y el propio repo del portal (no se hace push).

**Consecuencia:** GitHub no tiene 7 migraciones aplicadas en producción. Un banco o una rama de
Supabase armada desde GitHub no las tendrá: armarla desde el `main` local. En cada PR de
integración futura, excluir esos archivos (receta: worktree desde `avancecorp/main` +
`git checkout main -- <archivos que sí van>`; `Inicio.md` sin las líneas de Gloria).

## Tras fusionar la #114

Traer `avancecorp/main` al `main` local en un worktree. `Inicio.md` puede chocar, porque GitHub
lo tiene sin las líneas de Gloria: gana la versión local. El árbol resultante debe ser idéntico
al del `main` local; luego se avanza con `--ff-only`.

## Limpieza

- **35 ramas locales borradas** (71 → 36), todas ya dentro de `main` o con PR fusionada en el
  mismo commit. Se recuperan con `git branch <rama> <commit>` mientras git no las recolecte:
  `ci/e2e-local-docker` `e0c07e5ada87` · `codex/f4-cierre` `fa33e375f7c2` · `codex/f5-cartera` `3a4cd223101b` · `codex/f5-instalacion` `5ec315696fa4` · `codex/f6-postventa` `a2a2c90293bd` · `codex/f7-metricas` `e9ead769aba4` · `codex/f8-piloto` `faa1059745aa` · `codex/gestion-diaria-f4-vista-equipo` `c237dc071f4f` · `conversion/doce-puertas-unificadas` `26b75814071c` · `docs/cierre-rechazos-tasa-20260916` `51512f0b9a8b` · `docs/cierre-rechazos-tasa-a-main-20260917` `fd68135d8907` · `docs/gestion-diaria-f3-acta` `cb6089707211` · `docs/rentabilidad-integral-publicada-20260918` `1bc710f30e39` · `feat/leads-filtro-origen` `718b01931fd3` · `feat/multiempresa-f1-expand` `b57bf35e58b2` · `feat/multiempresa-f2-backfill` `f9e053ca9267` · `feat/multiempresa-f2b-cola` `f0a262e63731` · `feat/multiempresa-f3-puertas` `f88e978c1af4` · `gestion-diaria/f2-resultado` `cece2489052b` · `gestion-diaria/f3-cache-parcial` `41df4e8428df` · `gestion-diaria/f3-pestana-vacia` `4b7307ae7e7a` · `gestion-diaria/nivel-bajo-ambar` `960a744c56b1` · `probe` `37a936c75673` · `release/alfin-banco-20260901` `a56fdac21a19` · `release/landing-formulario-20260901` `3cc480bd2ade` · `release/restaurar-ficha360-20260831` `3e6d69ee6ba9` · `ux/gerencia-f2` `96f20383948e` · `codex/corregir-acceso-clave-servicio-20260919` `f9ca932f0f16` · `codex/gestion-diaria-f4-detalle-analista` `d60eafb03080` · `codex/gestion-multiempresa` `24794825274e` · `fix/rechazos-tasa-jornada` `e01b4718a77a` · `fix/tipo-cambio-bcrp-set-20260918` `4d33785eddd6` · `foco-accesible-21-09` `4c408e471d38` · `venta-cruzada/publicacion-fases-1-6` `dd6f4ab2eb68` · `venta-cruzada/docs-release-frente` `790cee3ab69b`
- **Bloqueado por el clasificador de permisos (lo lanza Miguel):** borrar
  `wip/workspace-20260823-completo` (ya dentro de `main`), `git worktree prune` de 7 worktrees
  cuyas carpetas ya no existen y retirar `/private/tmp/avancecorp-ranking-origen-wt` con su rama
  `codex/ranking-origen-20260926` (limpio y contenido en `main`).
- **Se quedan:** 32 ramas viejas que se fusionaron por squash o se abandonaron, porque no hay
  forma automática de probar que no guarden trabajo. Entre ellas están las de la Ficha 360 de
  agosto. También se queda el worktree `supervisor-fecha-20260924`, que tiene 1 cambio sin
  commitear, y `releases/ranking-cartera-20260926/` en la raíz, que son evidencias de Codex.

## Pendientes al 27/09

**Antes del cierre de setiembre (30/09)**
1. Perfil vendedor de pruebas de Miguel (`d731f284…`): anular las ventas de prueba `06bed16f`
   (setiembre) y `3869c906` (agosto), republicar metas de agosto sin él y luego desactivarlo.
   Sin constancia de que se haya hecho.
2. Reexpresión de agosto: decidir C1/C2 antes de `02-resellar.sql`.

**Decisiones de Miguel**
3. Rotar el token de Hostinger (quedó escrito en un chat el 25/09).
4. Rentabilidad: plan de servidor (cuenta dos veces 18 contratos re-creados).
5. Cerrar `public.crear_contrato` (Fase 0 del plan por empresa).
6. Plan B, operaciones por empresa: implementación pendiente; caso «retiró todo y vuelve».
7. Número P definitivo de P-0XX · pasada visual de Pagos del portal · primer uso real de Gloria ·
   depreciar `actividades_del_ambito_fn`.

Relacionado: [[Plan por fases - inversion por empresa y ranking de cartera (2026-09-26)]] ·
[[Conversion - publicacion verificada (2026-09-27)]] · [[Ranking cartera - publicacion verificada (2026-09-26)]]
