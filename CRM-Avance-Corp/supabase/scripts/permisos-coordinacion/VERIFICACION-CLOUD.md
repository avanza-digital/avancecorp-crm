# Coordinación — validación cloud y aplicación del backend

15/10/2026, 18:58 Lima. Miguel autorizó explícitamente validar y aplicar las tres
migraciones en PortalAvanceCorp, crear una rama temporal de pago y eliminarla al terminar.
El frontend se publicó por `$release-crm`; [artefacto y smoke verificados](../../../docs/COORDINACION-CARTERA-CATEGORIA-PUBLICADA.md).

## Rama y pruebas

Rama exclusiva `permisos-coordinacion-categoria-20261015`, proyecto `dcrnkkjtvnnkvvvxzueo`.
Se reprodujo la estructura vigente de producción sin copiar clientes ni datos de negocio.
El historial antiguo que Supabase reprodujo automáticamente estaba incompleto: se restauraron
los esquemas `public`, `private`, `crm`, roles internos y triggers de Auth, con los 481 registros
de migración productivos idénticos. La exportación omitió comentarios de dos funciones; sus
definiciones originales se restauraron antes de pasar los preflights. No se debilitaron sus huellas.
Las dos tareas cron de la rama quedaron desactivadas antes de crear usuarios de prueba.

- **PASS SQL:** 93 comprobaciones sobre el esquema productivo reproducido, datos sintéticos y ROLLBACK.
- **PASS Auth/PostgREST:** `node supabase/scripts/test-rls.mjs --permisos-coordinacion`,
  61 comprobaciones, 20 identidades sintéticas y 10 sesiones humanas reales, más anon.
  Consulta global, roles permitidos/denegados, seis transiciones, dinero y relojes intactos,
  conversión/ranking sin duplicación, idempotencia, auditoría protegida, mes sellado y baja
  efectiva sin renovar JWT. El administrador de Auth solo crea identidades: las aserciones
  de acceso y las correcciones usan anon key con el JWT de cada actor.
- **PASS advisors:** cero WARN/ERROR nuevos. Seguridad: 378 → 379 hallazgos; rendimiento:
  349 → 350. Los dos nuevos son INFO esperados: [RLS sin policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
  en la auditoría privada sin grants API, e [índice aún sin uso](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index)
  de esa tabla. No se abre la auditoría para silenciar el aviso. La deuda preexistente no se saneó.
- La matriz general `test-rls.mjs` con `seed-demo` permanece **NOT RUN**; la matriz focalizada
  anterior es la pertinente para este bloque. Su preflight offline y la sintaxis pasan.

## Promoción verificada

Se comprobó que la única diferencia del historial eran las tres migraciones aprobadas,
con el SQL íntegro idéntico a Git. Se promovieron mediante `supabase_merge_branch`;
el workflow productivo aplicó exclusivamente estas versiones a las **23:58:03 UTC**:

| Versión | SHA-256 del archivo probado |
|---|---|
| `20261015211217` | `6ba337d6d06ab666dad1852c4506015ec5d2b87e0efd161b8323236a6f84eebf` |
| `20261015212939` | `27a9b07cbc5b9d0606afd237dd01eabaa990c0a2d9226ad8f0425c5366975e4b` |
| `20261015224848` | `659b801cc1f3e3d6f645b53b6c07d99841dd40ff376d0cd05702b0b820441980` |

El registro productivo conserva 29/33/12 sentencias, respectivamente, porque el merge separa
las sentencias del archivo. Las **1.110 funciones** de los tres esquemas coinciden con la rama
validada en definición, propietario y ACL. El workflow indicó que las Edge Functions no cambiaron.

Verificación posterior: 818 contratos, 165 operaciones y un sello conservados; mismas huellas
de categorías e importes/condiciones antes y después. Cero correcciones fabricadas en producción;
auditoría con RLS y sin INSERT para authenticated. Consulta con el rol de Coordinación real:
Leads, cartera, conversión y metas PASS. Ese smoke terminó en ROLLBACK, incluida la auditoría
de lectura de cartera; no fue una prueba de escritura sobre inversiones reales.

La rama fue eliminada y se confirmó su ausencia en el inventario. Las otras ramas no se tocaron.
El módulo de prueba fija ese destino para impedir ejecutarlo por accidente en producción;
una repetición requiere preparar otra rama autorizada y revisar explícitamente su destino.

## Fuente de la pantalla

PR #298 integrada como `05c19efc`; se conservó después la corrección de cantidades de #299.
`npm run check` sobre `81480ebb`: **433 archivos, 6.966 tests PASS**, lint, tipos, cobertura,
build, bundle y duplicación. El árbol de app probado es `9adc5c59fa90c640437ac0054036bf07376ecd10`.
La suite Docker completa del árbol final pasó **427 casos / 26 omitidos / 0 fallidos**,
16,2 minutos, dos workers. Se ejecutó desde una copia exacta obtenida por `git archive`
para aislar las dependencias de Docker. Los cambios de este registro no alteran ese árbol.
