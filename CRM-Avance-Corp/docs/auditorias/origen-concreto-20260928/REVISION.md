# Origen concreto — revisión y verificación del 28/09/2026

Codex PRIMARY; Claude SECONDARY_REVIEWER mediante wrapper, LEVEL 3.
Dictamen recibido: **CHANGES_REQUESTED**. No se interpreta como aprobación.

## Evaluación del PRIMARY

- P1 matriz ausente: incorporado `test-rls.mjs --origen-concreto`, banco exclusivo
  Supabase con estructura productiva y datos ficticios. Comprueba CRUD denegado
  por HTTP/Auth para anon, service y tres roles, fuente/auditoría/actor, mes
  sellado, duplicados, inmutabilidad y desactivación. Matriz final PASS, incluida Gerencia inactiva, categoría renovación y cierre anulado.
- P1 puente: RPC real `importar_lead_fn` como service_role, Landing/Formulario
  PASS. Alta sin origen rechazada. Se retira el default ambiguo deliberadamente.
- P2 desactivación: resuelta en 193048; usa fecha comercial guardada, no la
  elegibilidad actual. El sello mensual sigue protegiendo altas y bajas.
- P2 referido: hipótesis descartada mediante comparación íntegra de
  `conversion_mensual_fn` antes/después para los cuatro canales, además de capital,
  moneda y vendedor. La confirmación no fabrica un episodio ni un lead.
- P2 evidencia: base de rama restaurada del esquema productivo de 383 migraciones,
  sin clientes reales. Preflights de reemplazo exacto PASS. Firmas, ACL, definer y
  search_path de las tres funciones previas idénticos; dos helpers privados nuevos
  revocados a roles API. Tipos regenerados de la rama.
- P3 FKs: retiradas por 193048 antes de crear confirmaciones; integridad validada
  en INSERT con lock de fuente. No altera tablas ni triggers del portal.
- P3 mensaje/legados: la UI ofrece cuatro canales; web/campania/whatsapp conservan
  compatibilidad de integración. Otro/NULL nunca admitidos en nuevas altas.
- P3 D8: contexto histórico conservado en migraciones previas. Desde septiembre
  ya se permitían Landing/Formulario manuales; política T10 intacta.

## Evidencia ya ejecutada

- `npm run check`: PASS, 4.768 tests / 313 archivos, lint, tipos y build.
- E2E Docker: 277 PASS, 26 omitidas, 2 FAIL por expectativas antiguas de Otro,
  1 flaky de login. Se corrigieron esas dos expectativas; repetición de ambos
  archivos: **25/25 PASS**. No se presenta la primera corrida como verde.
- Matriz SQL local de altas/roles y conservación de Otro histórico: PASS.
- Matriz nueva en rama: primera corrida completa PASS (capital PEN/COOPAC USD,
  cuatro canales, conversión íntegra, autorizaciones, auditoría y desactivación).
- Advisors: sin nuevos WARN/ERROR respecto a producción. Tabla sin policies es
  INFO esperado por deny-by-default. Alertas preexistentes de funciones API y
  protección de contraseñas se mantienen fuera de este cambio.
- Las 22 Edge Functions de rama y producción coinciden en versión/hash/JWT.

## Límites y publicación

La rama se creó con autorización explícita del costo. El replay histórico falló
antes de este cambio; se reconstruyó exclusivamente su esquema desde producción
más metadata técnica, luego se sembraron datos ficticios. No se copiaron clientes.
Solo las cuatro migraciones nuevas se proponen para merge nativo.
Backend publicado por merge nativo, historial 383 → 387. Se verificó la aplicación
consultando producción después de completarse la operación asíncrona. Las 22 Edge
Functions permanecen idénticas. Control analítico 0 pendientes y sello válido.
Confirmación autorizada aplicada en transacción REPEATABLE READ con auditoría y
comparación íntegra de contratos/cuotas/externos/cartera/episodios/leads/fotos,
stock sin origen y conversión mensual. Todo preservado; septiembre sin ambiguos.
Rama eliminada y ausencia confirmada por list_branches.

Fuente frontend final de rescate `5ccb30ac54f5`, basada en la versión viva
`3c481f7f1a4f`; conserva la segunda publicación de Hoy. Check **4.768/313 PASS**,
E2E Docker final **34/34 PASS**. Avisos de rutas de fuentes del servidor Vite del
banco con dependencias enlazadas; build estático verificado incluye los assets.
Preflight de artefacto desde GitHub rechazó por historial divergente; reconstrucción
desde la fuente viva y preflight posterior PASS. No se forzó ni omitió el control.
Frontend publicado. Smoke HTTPS **99 archivos PASS** (HTML, versión, JS, CSS y
18 archivos de fuentes), SHA-256 por archivo idéntico al manifiesto. El primer
cliente Node HTTP/2 falló por NGHTTP2_INTERNAL_ERROR; verificación completa
repetida con curl HTTP/1.1 PASS, sin repetir el despliegue.

Referencias de advisors preexistentes: [extensión en public](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public),
[funciones anon](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable),
[funciones authenticated](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
[contraseñas filtradas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
La [tabla sin policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
es privada por diseño. No se introdujeron nuevos WARN/ERROR.
