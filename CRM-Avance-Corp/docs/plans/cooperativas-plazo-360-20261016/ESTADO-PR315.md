# PR #315 — cerrada y publicada

**Estado final:** fusionada el 17/10/2026 a las 04:18:24 UTC y publicada desde
Main limpio `f1e6f60269b300f300291b64ad0a007788d9a94b`.
Las tres migraciones están en producción; 84 históricos conservados;
frontend y acceso verificados; banco temporal eliminado.
Evidencia y salvedades: [PUBLICACION-20261017.md](PUBLICACION-20261017.md).
El punto de continuación de abajo queda únicamente como historial.

## Registro previo, ya superado

Estado observado: 17/10/2026, 04:16 UTC. Publicación pendiente de revisión GitHub.

- PR: https://github.com/avanza-digital/avancecorp-crm/pull/315
- Candidato: 5872a53287c192eae7a9bd0078637df1c5ef57ec.
- Rama de funcionalidad: crm/cooperativas-plazo-360-20261016.
- Árbol idéntico al probado: 51119623f2bf4872d7fcf131020d7c297b6c0904.
- Checks GitHub PASS: preflight, cambios, app-check y verify. Supabase Preview
  SKIPPED, sin crear otro banco. E2E únicamente local en Docker.
- ReviewDecision: REVIEW_REQUIRED; ninguna revisión registrada.
- La PR pertenece a miguejbs98. El otro administrador listado es jhosepv96.
  La regla exige una revisión aprobada; no hay CODEOWNERS en este árbol.
- El push directo a Main fue rechazado. Se linealizaron cuatro commits,
  preservando el árbol exacto. No se usó bypass ni push forzado.
- Auto-merge deshabilitado en el repositorio. El intento de prepararlo fue
  rechazado sin efectos; no se cambió configuración de GitHub.

Producción continúa intacta: sin merge SQL ni deploy frontend. No hay ZIP final,
SHA final ni smoke de nueva versión: NOT RUN hasta que se fusione y se construya
Main limpio idéntico a avancecorp/main. El ZIP anterior sigue preservado.
Hostinger sí funciona mediante la sesión OAuth MCP existente.

El banco qlsukwhdouhgzkjgsebe (ID 94cba615-4071-46ea-b69a-85c2092041ad)
sigue activo y conserva las tres candidatas ensayadas con historial base exacto.
Tarifa previamente autorizada: US$0,01344/h. Está pendiente de merge nativo;
la aceptación de la rama reconstruida por esa operación aún no está comprobada.
Eliminarlo y verificar ausencia al cerrar el release, o si Miguel vuelve a pausar.
No se han dejado credenciales en el repositorio ni en este expediente.

Continuación privada: /private/tmp/avancecorp-coop360-publicacion/ESTADO-RETOMA-4-20261017.json.
Clon completo: /private/tmp/avancecorp-coop360-release-20261016.
Antes de construir: fusionar PR por squash sin bypass cuando GitHub lo permita,
actualizar Main del clon y del checkout compartido sin tocar su rama sucia,
comprobar Main/remoto y equivalencia del árbol probado. No desplegar desde feature.
Después: ZIP/verify/preflight, guardas productivas y hashes por fila histórica,
merge nativo de solo tres migraciones, verificación SQL, deploy MCP Hostinger,
smoke HTTP/UI y eliminación del banco/credenciales. Mantener la fuente del
manifiesto como commit publicado aunque se añadan actas después.
