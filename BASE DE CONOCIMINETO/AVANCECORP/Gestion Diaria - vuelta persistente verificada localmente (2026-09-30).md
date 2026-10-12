# Gestion Diaria - vuelta persistente verificada localmente (2026-09-30)

Estado actualizado: **PUBLICADA Y VERIFICADA** en https://crm.miavance.com.

Al guardar una llamada, incluso «No contestó», el lead gestionado pasa al final
de la cola completa y «Ahora» propone el siguiente pendiente, también entre
páginas. Se muestra resultado y hora. El progreso se obtiene de la actividad
confirmada del día de Lima, por actor, tenencia y ciclo; persiste al recargar.
Deshacer recalcula el avance y un compromiso posterior reabre el turno a su hora.
Al completar la vuelta no empieza otra automáticamente.

Migración `20260930190028` promovida mediante merge_branch tras validar el banco
remoto: 530 leads, roles, diez denegaciones y gate RLS oficial de 287 aserciones.
Producción coincide con el catálogo probado y las 22 Edge Functions preservadas.
Banco temporal eliminado; no quedaron datos de prueba en producción.

Frontend: 4.945 pruebas y build PASS, E2E Docker 289 passed / 26 skipped. Dos
revisiones independientes atendidas con evidencia. Los dos oráculos pendientes
del gate de realidad HTTP se completaron mediante SQL de sólo lectura.

La PR #145 se integró en Main `adb12c053a0676ae015f0a6b86c54a1034bb56e9`.
El preflight rechazó la ascendencia del squash de GitHub; se siguió el rescate
previsto en CLAUDE.md desde la base publicada. El contenido completo del rescate
ya está en Main: los árboles son idénticos, no hay código pendiente de integrar.
Commit realmente publicado: `57e7b3b4a79634109041f5dcc7c5ccc72e75fa34`.
Build: `build-20260930T195218921Z`.
ZIP: `crm-20260930T195219Z-57e7b3b4a796.zip`.
SHA-256: `63bda8e5ab15a07075349e8260a9a71a10006620f0da2611645a360601dd94fd`.

Manifiesto, preflight y smoke HTTP PASS: portada 200 y 93 archivos con hashes
idénticos al ZIP. Smoke visual NOT RUN por servicio de navegador no disponible;
los E2E de Docker están aprobados. No se realizaron llamadas reales para probar.

Evidencia: `CRM-Avance-Corp/docs/encargos/gestion-diaria-cola/RELEASE.md` y
`PUBLICACION.json`. Artefacto y manifiesto guardados en `CRM-Avance-Corp/releases/`.
El artefacto anterior se conserva; no revertirlo sin el procedimiento autorizado.

Relacionadas: [[Gestion Diaria F2 - resultado tipificado de llamada (2026-09-20)]],
[[Gestion Diaria F3 - el dia del analista (2026-09-20)]],
[[Gestion Diaria - cola completa F6 preparada (2026-09-24)]],
[[Cola del dia con clientes - plan (2026-09-28)]].
