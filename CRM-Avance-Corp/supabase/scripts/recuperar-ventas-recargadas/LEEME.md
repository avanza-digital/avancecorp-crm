# Recuperar las cinco ventas recargadas — kit de 20261018032400

Migración: `supabase/migrations/20261018032400_crm_recuperar_ventas_recargadas.sql` (su encabezado explica qué hace y por qué).
Ledger: `supabase/migrations/MIGRACIONES.md`.

| Archivo | Para qué | Dónde corre |
|---|---|---|
| `probar.sh` | La batería: siembra los 5 casos con las puertas reales (+ control F), 34 rechazos del preflight, 2 aplicaciones, 12 inyecciones que el postflight detecta, D1–D9 (incluida la reversa). UNA transacción con ROLLBACK. Sale 0 = PASS. | banco Docker `reemplazo-inv-db` |
| `test-recuperar-ventas.sql` | El texto de la batería (lo ensambla `probar.sh`; no se corre solo). | banco |
| `mutantes.py` | Por cada defensa de la migración, un texto que la neutraliza; la batería tiene que tumbarlo. `python3 -I mutantes.py [filtro]`. Los de las funciones parchadas recalculan las huellas del postflight para que solo D6 pueda matarlos. | banco |
| `foto-casos.sql`, `foto-huellas.sql`, `foto-sellos-plazos.sql`, `foto-tope-referidos.sql` | Fotos de SOLO LECTURA de producción antes de aplicar: los cinco casos tal como los exige el preflight, las huellas de las funciones, sellos y plazos, y si el tope de referidos puede morder. | producción (`db query --linked --file`) |
| la migración | Aplicar en UN mensaje, como postgres, sin sesión de usuario, antes del 22/10/2026 00:00 Lima y con poca actividad. | producción |
| `registrar.sql` | DESPUÉS de aplicar: registra la versión en `supabase_migrations.schema_migrations` (generado por `generar-registrador.mjs`; regenerar tras cualquier edición de la migración). | producción |
| `comprobar-tras-aplicar.sql` | DESPUÉS de aplicar: veredicto `APTA` / `NO APTA` en una fila (huellas, tabla, cinco ventas contando, otras anulaciones siguen). Solo lectura. | producción |
| `reversa.sql` | Si hubiera que volver atrás: las cuatro funciones a su huella anterior (3 y 4 vuelven a contar como anuladas; 1, 2 y 5 siguen; las fechas no vuelven solas). Ensayada en D9. | producción |

Banco: `probar.sh` y `mutantes.py` leen la contraseña de `BANCO_PGPASSWORD` o de `~/dev/banco-reemplazar-inversion/conexion.env`
(fuera del repo). Estado el 18/10/2026 (v3): batería PASS (58 bloques) y 50/50 mutantes muertos; Codex revisó la v2 (CHANGES_REQUESTED: tope de referidos) y la v3 lo cierra.
