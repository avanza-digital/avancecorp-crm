# Reemplazar inversión · Fase 4: cooperativas — kit de 20261018053228

Migración: `supabase/migrations/20261018053228_crm_reemplazar_inversion_cooperativa.sql` (su encabezado explica qué hace y por qué).
Ledger: `supabase/migrations/MIGRACIONES.md`. Plan: vault «Reemplazar inversion - plan por fases (2026-10-17)».

| Archivo | Para qué | Dónde corre |
|---|---|---|
| `probar.sh` | La batería: siembra propia (5 ventas de cooperativa, un aporte adicional, una anulada; comprobantes como filas de `storage.objects`), aplica la migración como postgres y prueba catálogo, vista previa, rechazos, reemplazos que pasan (fecha, cooperativa, comprobante, cotitulares, idempotencia, cadena) y la limpieza. UNA transacción con ROLLBACK. Sale 0 = PASS. | banco Docker `reemplazo-inv-db` |
| `test-reemplazar-cooperativa.sql` | El texto de la batería (lo ensambla `probar.sh`; no se corre solo). | banco |
| `mutantes.py` | Por cada defensa de la migración, un texto que la neutraliza; la batería tiene que tumbarlo. `python3 -I mutantes.py [filtro]`. Las defensas dobles (puerta/núcleo, núcleo/copia) se apagan juntas. | banco |
| `produccion/*.sql` | Cuerpos vivos (= producción, 18/10/2026) de los dos ayudantes del bucket que la migración parcha. Los usa la reversa (copiados dentro). | — |
| la migración | Aplicar en UN mensaje, como postgres (`db query --linked --file`). El preflight se niega si cambió alguna función que llama o parcha. | producción |
| `registrar.sql` | DESPUÉS de aplicar: registra la versión (generado por `generar-registrador.mjs`; regenerar tras cualquier edición). | producción |
| `comprobar-tras-aplicar.sql` | DESPUÉS de aplicar: `APTA` / `NO APTA` (huellas del bucket, funciones, permisos; cuenta los reemplazos hechos). Solo lectura. | producción |
| `reversa.sql` | Retira las cinco funciones nuevas y devuelve los dos ayudantes del bucket a su huella. Los reemplazos ya hechos quedan (copia «reemplazada por» + inversión nueva). Revertir primero el front. | producción |

Estado el 18/10/2026: batería PASS (11 bloques), 37/37 mutantes muertos, reversa ensayada en el banco. Pendiente: revisión de Codex (nivel 3: cambia dos funciones de las políticas del bucket) y auditor-rls.
