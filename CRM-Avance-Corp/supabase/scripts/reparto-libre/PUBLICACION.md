# Publicación: reparto libre de Coordinación · 07/10/2026

**Backend aplicado y frontend publicado en https://crm.miavance.com. Permiso inicialmente ACTIVADO para todo el rol Coordinadora.** Gerencia lo administra en **Administración → Configuración → Reparto libre de Coordinación**. Se verificó la pantalla real: estado Activado y botón «Desactivar reparto libre» habilitado.

## Fuente y artefacto

- PR [#216](https://github.com/avanza-digital/avancecorp-crm/pull/216), integrado tras `verify`, `app-check` y `preflight` correctos.
- Commit publicado: `e511d30504f24045aa28230a2d2eb03891bdf967`. Main local y `avancecorp/main` coincidían antes de construir y subir.
- El árbol completo es idéntico a `d2c4e44c5f52fe8ececa953991dbe6fec6fa37be`, sobre el que corrieron los checks y E2E. Construcción desde copia limpia; no se incluyó trabajo ajeno.
- Build: `build-20261007T152927260Z`.
- ZIP: `crm-20261007T152928Z-e511d30504f2.zip`.
- SHA-256: `44e46cc985a251a6d51d04bfd5b942e85443a2504fd7d9bab063f1df63846cf9`.
- Hostinger: preflight de ascendencia, huella y Ficha 360 PASS; conector oficial, despliegue aceptado y versión servida comprobada.
- Recuperación conservada: `crm-20261007T054815Z-8e7524ed2a3f.zip`, SHA-256 `a76511adb2ae07db608acb00f8078545ebaeec4ea484ec0b7e2355c64204ae90`. No ejecutar rollback sin el procedimiento del repositorio.

## Backend y autorización

Miguel invocó `$release-crm` y aprobó por separado «Sí, probar y aplicar el permiso», incluida una rama temporal de Supabase a US$0,01344/h. Se aplicó exclusivamente `20261007143121_crm_reparto_libre_coordinacion_configurable.sql` mediante `merge_branch`; no se usó `apply_migration` en producción.

La rama `reparto-libre-coordinacion-20261007` (`lxuwpkcgriemsdbioxne`) se reconstruyó desde el esquema productivo y datos ficticios porque el replay histórico requiere datos. El historial previo de 435 migraciones quedó intacto; única nueva versión `20261007143121`. El merge registró sus 29 sentencias por separado: se cotejaron literalmente contra el texto completo probado, admitiendo solo separadores y espacio entre sentencias.

Postflight **PASS**: siete definiciones idénticas a las probadas, ACL/RLS correctas, configuración ON/revisión 1 y las 22 Edge Functions sin cambios de código, JWT ni versión. Consulta de solo lectura con la identidad de Rosa: `reparto_libre = true`. No se derivaron leads reales para probar.

La rama temporal fue eliminada y su ausencia confirmada; se eliminaron las credenciales locales temporales. La rama preexistente `banco-f7` permanece intacta.

## Validación

- **PASS** `npm run check`: 6.333 pruebas/395 archivos, lint, tipos, build, bundle y configuración. Duplicación 0,44 %; el fallo previo del árbol sucio no aparece en la copia limpia.
- **PASS** 49 E2E Docker: reparto libre, reparto y cartera/Ficha 360. Dependencias instaladas mediante `npm ci` en la copia limpia.
- **PASS** `npm run check:scripts`, preflight RLS offline y verificación del artefacto.
- **PASS** SQL transaccional local y remoto, dos coordinadoras, ON/OFF, auditoría, destinos inactivos, No Insista y revocaciones. Concurrencia local de dos sesiones: un éxito y un PT409; carrera HTTP de reparto: una entrega.
- **HTTP general:** 2.850 aserciones, 2.845 correctas y cinco fallos iniciales del banco. Cuatro correspondían a la bandera `potencial_lead` inicialmente encendida; el quinto al ACL implícito del propietario tras el dump, frente al ACL explícito de producción en tres tablas B7. No había permisos API adicionales.
- **PASS de recuperación:** seed reconstruido según `LEEME-seed.md`, bandera de prueba apagada y ACL explícito de postgres igualado. Los cuatro bloques originales afectados se repitieron completos: **279 aserciones, cero fallos**. El adaptador cambió solo la selección de bloques; no modificó sus funciones ni omitió sus precondiciones o limpieza. No se presenta la primera corrida como íntegramente verde.
- Las negativas HTTP de las RPC nuevas para anon, service_role y roles no autorizados devolvieron 42501 sin caída del motor. La incidencia local previa del proveedor no se provocó en producción. La versión hospedada confirmada es PostgreSQL 17.6.1.105.
- **NOT RUN:** `gate:realidad` completo; se verificaron directamente los contratos vivos relevantes, tipos, autorización y comportamiento de esta entrega.

Advisors antes/después evaluados: sin errores nuevos. Los dos avisos de [RPC autenticadas SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) son intencionales y están protegidos por Gerencia activa en el núcleo; la [tabla sin políticas](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) carece de acceso directo; el [FK sin índice](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys) pertenece a una tabla limitada a una sola fila.

## Comprobación de la publicación

**PASS funcional:** portada y versión HTTP 200, bytes exactos; 116/116 JS y CSS con SHA-256 idéntico al manifiesto. Acceso real de Gerencia y control Activado verificados en navegador. **Límite del cotejo exhaustivo:** 142/154 archivos públicos tienen bytes exactos; los 12 PNG responden 200 pero conservan otra huella incluso tras solicitar el vaciado de caché de Hostinger/CDN. Siete tienen píxeles idénticos; cinco logotipos de aliados tienen dimensiones distintas. Esos 12 archivos son byte a byte iguales en el paquete publicado anterior y en este release: esta entrega no los modificó. No se presenta el cotejo de todos los PNG como PASS. El control de permisos, la pantalla y todos los JS/CSS sí están verificados. No se alteró la configuración del CDN ni se ejecutó rollback.

Evidencia saneada: `output/reparto-libre-20261007/` y `releases/crm-20261007T152928Z-e511d30504f2.smoke.json`. El informe de resolución RLS conserva los cinco mensajes iniciales y su cierre. [REVISION.md](REVISION.md) conserva el dictamen independiente y la decisión del PRIMARY; [README.md](README.md) describe el comportamiento y la recuperación operativa.
