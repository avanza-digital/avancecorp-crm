# Verificación de la candidata local

Fecha de trabajo: 10 de septiembre de 2026, Lima. Base inicial: `774a04f`, desde
`avancecorp/main`. Checkout aislado: `/private/tmp/avancecorp-tasa-lead-real-20260908`.

| Comprobación | Resultado | Alcance real |
| --- | --- | --- |
| Migración completa en PostgreSQL local | PASS | Replay desde `tasa_lead_final_20260909` hacia `crm_push_tasa_release_20260910`. Auth, Vault y pg_net reales; `cron.schedule` inerte. |
| `test-push-tasa.sql` | PASS, 48 | ACL/RLS con SET ROLE, varias cuentas/dispositivos, solicitudes y resolución mediante RPC reales, sesiones/perfiles revocados, fallos/reintentos, recuperación, firmas, auditoría. Transacción revertida. |
| `concurrencia.mjs` | PASS, 3 | Transacciones simultáneas: reclamación sin duplicados; baja frente a 410; barridos de inválidos/agotados. Copia exclusiva `crm_push_tasa_concurrencia_final_20260910`. |
| Activación | PASS local | Bloque de activación ejecutado dos veces, idempotencia comprobada y todo revertido. Sin cron activo ni HTTP. No se ejecutó en producción. |
| Edge de notificaciones | PASS, 15 | Trece pruebas del handler y dos del transporte, con cifrado real y HTTP simulado. `deno check` incluido. |
| Worker del navegador | PASS, 8 | Reintentos silenciosos, fallos de cache, contenido tras baja, destino interno y conservación de otras pestañas. |
| Espejos y manifiesto | PASS, 4 | Las tres fuentes de Edge coinciden byte a byte; los iconos existen y tienen el tamaño declarado. |
| Frontend `npm run check` | PASS, 3.206 tests | Lint, tipos, cobertura, configuración de release, build, bundle y duplicación. Detalle del banco final en `evidencia/frontend-gate.txt`. |
| Playwright completo | PASS, 164; SKIP, 26 | Omisiones ya configuradas por el banco. Incluye los cuatro escenarios nuevos: activar/probar/desactivar, aviso antiguo, aviso sin sesión y móvil. |
| `npm run check:scripts` | PASS | Preflights y pruebas offline existentes del proyecto. |
| `npm run seed:preflight` | PASS | Destino local y variables ficticias, sin conexión ni alta de usuarios. |
| `npm run test:rls:preflight` | PASS | Matriz offline de trece roles/sesiones; no sustituye el gate remoto. |
| `npm run test:edge-preflight` | PASS | Gates previos y nueva suite de push integrada al comando de CI. |
| Tipos de base de datos | PASS | Generados con Supabase CLI desde el banco final. Se incorporaron dos tablas y ocho RPC, preservando los tipos de F6 y otros frentes. |
| Revisión visual | PASS local | Capturas desktop/móvil en `evidencia/`; controles visibles y sin desborde a 390 px. |
| Claude | Dos reviews evaluados | Dictámenes `CHANGES_REQUESTED`; correcciones y decisiones verificadas por PRIMARY. Véase `REVISION-CLAUDE.md`. |
| Banco Supabase gestionado, matriz global y advisors | NOT RUN | Requiere autorización del SQL y banco temporal propio. |
| Cron/Edge HTTP gestionados | NOT RUN | La prueba local sustituye el HTTP y el scheduler para no enviar mensajes. |
| Entrega APNs/FCM en un teléfono real | NOT RUN | Playwright simula permiso y proveedor; no acredita recepción con la PWA cerrada. |
| Publicación productiva | NOT RUN | No hay autorización de los SQL exactos. No hubo cambios remotos ni envío real. |

Se corrigieron durante la validación: fixture de navegador incompleto, intento de
foco antes de desaparecer el splash, selectores de tests que asumían una sola
región accesible y el formato de los tipos generados. El Chromium headless del
banco informa `Notification.permission=denied` pese a conceder `notifications` en
Permissions API; el test aísla expresamente permiso/proveedor y mantiene real la
instalación del service worker. No se relajó el permiso de la aplicación.

Lecturas productivas sin mutación confirmaron las dependencias: VAPID configurado
por nombre, secreto cron existente de longitud suficiente, HMAC disponible,
permiso de `postgres` para validar `auth.sessions` y auditoría con enmascarado.
La inspección de pg_net motivó usar HMAC temporal en lugar de escribir el secreto
compartido o intentar cambiar permisos de una tabla administrada por Supabase.

Los hashes de SQL y fuentes de despliegue están en `evidencia/SHA256SUMS`.
La evidencia registra PASS/NOT RUN por lo ejecutado; ningún review sustituye
las pruebas ni la validación pendiente del teléfono.

## Reanudación e integración del 11 de septiembre

Miguel reanudó la tarea con «sigamos». Se integró `avancecorp/main` (`4febe47`)
en la candidata `25c6fd5`, preservando Facturación, Reparto y los ajustes de F6.
El único conflicto fue el índice del vault; se conservaron ambas notas y el
estado más reciente de F6. El SQL y las fuentes push conservan las siete huellas
de `SHA256SUMS`, verificadas desde la raíz del repositorio.

- **PASS:** lint, tipos, cobertura (231 archivos, 3.266 pruebas), configuración
  de release, worker, build, bundle y duplicación sobre la integración.
- **FAIL:** el recorrido completo de navegador terminó con 163 PASS, 26 SKIP y
  un fallo en `f6-postventa.spec.ts:148`: tras Escape desapareció también la
  ficha y no se encontró el botón al que debía volver el foco. Los cuatro
  escenarios de notificaciones pasaron. Registro: `evidencia/integracion-20260911.txt`.
- **PASS:** el caso F6 aislado (1 prueba) y después F6 junto con notificaciones
  (11 pruebas) pasaron sin cambiar el código ni los tests. Registros:
  `evidencia/f6-foco-aislado-20260911.txt` y `evidencia/f6-push-conjunto-20260911.txt`.
  Es una intermitencia pendiente de aislar, no una corrección demostrada ni un
  PASS del primer recorrido completo. Se conserva la comprobación de foco.
- **PASS, solo lectura:** producción sigue sin las dos tablas push y conserva
  las dependencias de auditoría, solicitudes, cron y red. Referencia de advisors
  previa en `evidencia/advisors-produccion-antes-20260911.json`; sus avisos son
  anteriores a esta instalación y no se presentan como introducidos por push.
- **NOT RUN:** banco gestionado, SQL remoto, Edge/cron gestionados, publicación
  y recepción real en el teléfono. Se solicitó la organización para consultar
  el coste; falta autorizar los dos SQL exactos y el banco temporal.

No se hizo push ni se modificó producción en esta preparación. La aprobación
del SQL permite avanzar al banco; el cierre productivo aún requiere sus gates
y evaluar la intermitencia de navegador registrada arriba.
