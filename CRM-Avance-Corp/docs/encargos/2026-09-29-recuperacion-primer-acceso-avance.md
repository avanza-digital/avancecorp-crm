# Recuperación del primer acceso Avance rechazado

Estado: corrección local verificada; pendiente de publicación. Fecha: 2026-09-29.

## Evidencia y alcance

El intento real del analista a las 20:11:52 UTC devolvió HTTP 400 / SQLSTATE 22023 en `private.inversion_datos_portal`, desde `private.inversion_validar_datos` y `private.inversion_preparar_nucleo`. El error fue «Completa el nombre legal y un correo válido para el acceso Avance». La autorización se había superado. El validador de nombre/correo no depende del rol. En la consulta del caso no existían solicitud, perfil ni contrato nuevos.

No se capturó el cuerpo del envío original: no se puede atribuir con certeza el rechazo a un campo específico. El nombre del lead había tenido una tabulación, pero hubo otro rechazo después de corregirlo y renovar la sesión. La sesión abierta después en esta Mac no contenía el borrador fallido de Windows. Cerrar sesión o corregir únicamente el nombre del lead no resuelve el defecto de recuperación demostrado.

El defecto del frontend sí se reprodujo: `InversionNueva.preparar` guardaba el intento antes de enviar. Ante 22023 quedaba en «Recuperar solicitud»; si la consulta devolvía P0002, reenviaba los mismos datos rechazados sin permitir editarlos. `AltaAvance` solo recortaba los extremos de los nombres y no comprobaba controles ni el límite combinado del nombre legal.

## Corrección

- Normalizar espacios internos en nombres, apellidos y teléfono; comprobar caracteres de control, nombre legal de hasta 240 caracteres y correo antes de enviar. Mostrar el campo que necesita corrección.
- Ante rechazo 22023 del primer acceso, consultar la misma referencia: recuperar la versión del servidor si existe, o permitir corregir únicamente cuando P0002 confirma ausencia.
- Ante P0409, recuperar la misma referencia si existe. Si no existe, conservar el conflicto sin habilitar edición. Cuando el lead ya tiene otra solicitud conocida, ofrecer «Retomar solicitud registrada» también al reabrir un intento antiguo.
- Un intento antiguo sin solicitud en el servidor vuelve al formulario sin reenviarse automáticamente.
- Conservar UUID, token y metadatos del intento al corregirlo y al recuperar una escritura cuyo resultado no se recibió. Si un envío concurrente registra la misma referencia, el conflicto recupera lo registrado y sincroniza los datos locales con el servidor.
- Una consulta incierta mantiene la recuperación; 42501 conserva la revocación. No se cambian permisos, SQL, contratos ni la creación de accesos.

Archivos: `app/src/components/app/inversion-nueva.tsx`, `app/src/components/app/lead-drawer-convertir.test.tsx`, `app/e2e/acceso-avance-ux.spec.ts`.

Parche aislado de esos tres archivos: `/private/tmp/crm-recuperacion-acceso-20260929.patch`, SHA-256 `97c167f27f223281f76377fe6c3862c8812dcc2459aeed6d60ef152fae1df9c9`. No incluye el trabajo ajeno del árbol.

## Verificación

- PASS: test focalizado final, 47 pruebas, incluidas 15 regresiones nuevas (normalización, datos inválidos, rechazo, intento antiguo, consulta incierta, respuesta perdida, carreras, otra solicitud y permisos revocados).
- PASS: `npm run check` final, 317 archivos / 4.923 pruebas, lint, tipos, cobertura, configuración de release, push-tasa, compilación, bundle y duplicación.
- PASS: Docker `acceso-avance-ux.spec.ts`, 5 pruebas en escritorio/móvil.
- PASS: Docker `f5-cartera.spec.ts`, 9 pruebas del formulario compartido.
- PASS: banco completo final de navegador en Docker, **288 passed / 26 skipped / 0 failed**, 11,1 minutos. Comando: `npm run test:e2e:docker -- --workers=2 --output=test-results/acceso-final-20260929`. Junto con `npm run check` final, cubre el gate `check:all`.
- PASS: comprobación focalizada final de conversión + Cartera, 100 pruebas. La corrida integral intermedia detectó una regresión al sincronizar el contenido base de una corrección pendiente: se limitó la sincronización al intento explícito de preparación recuperado, conservando el contrato previo de recuperación de correcciones. El gate integral posterior pasó.
- La primera corrida completa E2E se interrumpió tras detectar un selector ambiguo de correo (aviso y resumen coexistían durante la consulta); se selecciona ahora el campo del resumen. El siguiente arranque falló antes de ejecutar pruebas con `ENOTEMPTY` en `.playwright-artifacts-2 2`. La corrida final usa su propia carpeta de resultados.
- PASS: revisión visual del formulario recuperado en móvil, con datos sintéticos. El parche final conserva la misma huella SHA-256 después de las verificaciones.
- PASS: `git diff --check` de los archivos de esta corrección.
- NOT RUN: `gate:realidad`, el script no pudo iniciar porque el entorno no proporciona `SUPABASE_URL` y credencial de servicio. Se inspeccionaron por separado el estado real del caso, el validador y los logs de rechazo; ese análisis no sustituye al gate integral.
- Revisión independiente: `scripts/claude-review` devolvió CHANGES_REQUESTED. Se aceptó y corrigió P2 (P0409 de otra clave no debe habilitar una edición inútil), P3 de token nuevo por cierre de render y P3 de datos locales divergentes. Los cuatro casos adicionales verifican conflicto de otra inversión, retomar otra solicitud en la misma apertura y al reabrir, y preservación del token tras escritura confirmada/lectura 22023. La observación opcional sobre foco durante el envío no afecta la recuperación ni la conservación de datos. No se atribuye PASS al reviewer después de las correcciones; el PRIMARY las verificó con pruebas.

Logs finales: `/private/tmp/crm-acceso-check-final2-20260929.log`, `/private/tmp/crm-acceso-e2e-final2-20260929.log`, `/private/tmp/crm-acceso-fix-review-result-20260929.txt`. Logs focalizados iniciales: `/private/tmp/crm-acceso-e2e-20260929.log`, `/private/tmp/crm-acceso-e2e-cartera-20260929.log`.

## Publicación pendiente

No se ha publicado ni registrado la inversión del cliente. `CLAUDE.md` exige invocación humana de `$release-crm` para publicar. La corrección debe aislarse de los cambios ajenos que ya estaban en el árbol y seguir el flujo de Main/avancecorp/main, artefacto y preflight del repositorio. No usar el `dist` del taller como artefacto de producción verificado.
