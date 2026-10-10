# Encargo 3 a Codex (IMPLEMENTADOR) — Facturación 3B: filtro de días sueltos (`p_dias`)

ROLE: IMPLEMENTER delegado por Claude (PRIMARY). Mismas reglas que los encargos 1 y 2:
- solo este worktree;
- sin commit, red, Docker, producción ni otros agentes;
- en español.

Trabajas SOBRE lo existente.

## Por qué

La hoja de Facturación permite marcar DÍAS SUELTOS. Regla de Miguel del 11/09/2026 (`app/src/screens/facturacion.tsx`,
alrededor de la línea 445): si hay días marcados, la malla son ESOS días y nada más. Cada total de esa vista (por ejemplo
los días 2, 5 y 7) tiene que abrir una lista que sume exactamente ese total. Con solo `p_desde`/`p_hasta` no se puede.
La maqueta de la fase 4 ya está APROBADA por Miguel y manda esos días.

## Cambio

1. **Parámetro `p_dias date[] default null`**, justo DESPUÉS de `p_hasta`, en la puerta y en el núcleo. La firma queda:
   `(p_desde date, p_hasta date, p_dias date[], p_analistas uuid[], p_sin_analista boolean, p_equipo uuid,
   p_sin_equipo boolean, p_tipos text[], p_moneda text, p_pagina integer, p_tamano integer)`.
2. **Semántica:**
   - con `p_dias` NULL, sin cambio;
   - si no es NULL, se filtra `dia = any(p_dias)`, después de la capa 1 y junto a los demás filtros;
   - da 22023 con un arreglo vacío, con un elemento NULL o con un día fuera de `[p_desde, p_hasta]`;
   - los repetidos no cambian el resultado.
3. **Actualizar TODAS las firmas:**
   - regprocedure del PREFLIGHT/POSTFLIGHT de la migración;
   - comparador y sus llamadas;
   - reversa, generadores, `registrar.sql` (regenerado), ensayos y `medir.sql`;
   - censo y bloques del gate (`test-rls.mjs`);
   - `test_generadores.py`, LEEME y `MIGRACIONES.md`.
4. **Oráculo de la migración:** en el mes con más operaciones, para cada identidad, un conjunto de 2 o 3 días sueltos
   con operaciones. Debe igualar a la cifra de esos mismos días, `dia = any(...)`, con el comparador por posición.
   - Añadir las negativas: vacío, elemento NULL y día fuera de rango.
5. **Ensayo sintético:**
   - un caso con días sueltos;
   - un MUTANTE «`p_dias` ignorado», cazado solo por su SQLSTATE propio;
   - las negativas.
6. **Gate (`testFacturacionLista`):**
   - Gerencia y sup1 con días sueltos: el `total` y los `totales` iguales a la suma de su cifra en esos días;
   - las tres negativas dan 22023.
7. **Huellas** de las dos funciones: `'PENDIENTE_MEDIR_EN_BANCO'`. Las mido yo.

## Verificación offline

Generadores con `--verificar`, `test_generadores.py`, `node --check supabase/scripts/test-rls.mjs` y `git diff --check`.
Informe breve.
