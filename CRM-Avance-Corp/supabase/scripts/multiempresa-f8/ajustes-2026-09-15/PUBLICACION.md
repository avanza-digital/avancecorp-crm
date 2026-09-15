# F8 — publicación verificada y punto de retoma

Las mejoras de Cartera, Ficha 360 y condiciones COOPAC están publicadas en https://crm.miavance.com/. Commit de producto `95804fc8d83dad8d7be7168a6cdea24e95b0f45d`, construido cuando Main local y `avancecorp/main` coincidían. Build `build-20260915T021656174Z`. El commit posterior del acta sólo guarda documentación y evidencia.

La comprobación de cierre corresponde al 15/09/2026 02:26 UTC (14/09, 21:26 Lima). La pausa solicitada no dejó ninguna publicación a medias.

## Resultado verificado

- Tres migraciones instaladas por merge: `20260915010349`, `20260915010350`, `20260915015315`, con 4/19/6 sentencias literales. Las 288 filas anteriores del historial siguen idénticas; total 291. Se conservan los mapeos de archivos fuente.
- 645 funciones coinciden con el banco en definición, firma, permisos, propietario y configuración. Las siete huellas de datos anteriores coinciden antes/después; piloto, banderas y miembros intactos.
- Se preservó la publicación concurrente del PDF v9: nueve archivos idénticos. El merge dejó la Edge PDF en versión 17 con el mismo bundle ensayado en la rama; las otras 18 Edge no cambiaron.
- Cartera y primera ficha respondieron en los cuatro contextos reales del piloto: 2.446, 1.374, 1.113 y 3.900 ms. Se usó SQL con rol authenticated, READ COMMITTED y ROLLBACK; no son sesiones JWT HTTP ni una prueba visual. Las RPC registran lecturas, por eso una transacción READ ONLY no sirve para este ensayo; el ROLLBACK conserva los datos.
- Verificación HTTP de 92 archivos: 80 hashes exactos, once PNG optimizados por CDN y `.htaccess` bloqueado. Seis PNG conservan exactamente sus píxeles; cinco se redimensionan con el mismo aspecto y error medio inferior a 2/255. Los JS, CSS, HTML y versión coinciden con el artefacto. ZIP público, `.env` y `package.json` bloqueados; portal HTTP 200.
- 3.582 pruebas frontend PASS en el gate de subida; lint, tipos y build PASS. El ensayo previo incluye 15 E2E afectados, SQL, Auth, Storage, revisiones antiguas, compatibilidad y confirmaciones simultáneas. Claude aprobó la corrección PT409.
- Advisors productivos: 211 antes y 211 después. Se sustituye la advertencia de la firma antigua de `convertir_lead_externo` por la firma ampliada; no se añadió un permiso.

## Banco y guardado

La rama propia `hqazubfaznppkfelctej` fue eliminada y su ausencia confirmada a las 02:26:51 UTC. El primer banco ya se había eliminado en la pausa anterior. Coste estimado total de ambos: **US$0,04**, dentro del máximo aprobado de US$1; no es una factura. Se borraron sus credenciales, sesiones y copias privadas temporales. No se tocó la rama ajena `banco-f7`.

Artefacto y manifiesto conservados en `CRM-Avance-Corp/releases/crm-20260915T021656Z-95804fc8d83d.*`. ZIP SHA256 `f65a2b044d21f6f6c68f84c328fdc5933b09005e35f66dfea4f010317359adad`. El release anterior `crm-20260914T211416Z-32d57b5b3e15.*` también se conserva como referencia de reversa; las columnas nuevas son compatibles y no se borran datos para revertir frontend.

## Retoma

1. Consultar esta acta y el estado vigente del piloto; la ventana nominal registrada termina el 21/09 a las 13:23 Lima.
2. Revisar con Miguel el cliente real del piloto en Cartera y su ficha, y recoger las observaciones visuales pendientes. Comprobar el apartado COOPAC: plazo, fecha calculada y porcentaje anual manual.
3. Registrar su conformidad para G7 y continuar el plan principal desde ese punto. G7-R01 tiene corrección técnica publicada y comprobación SQL; el recorrido visual real y la conformidad siguen pendientes.

No había navegador conectado para una nueva comprobación visual productiva. La matriz RLS general con otra semilla permanece NOT RUN; la matriz específica sí pasó. El [inventario de otros 40001](RIESGO-40001.md) requiere análisis por recorrido antes de ampliar cambios; no son 39 defectos HTTP demostrados.

Evidencia: [acta estructurada](PUBLICACION.json), [web](verificacion-web-final.json), [imágenes CDN](imagenes-cdn-verificadas.json), [roles](produccion-roles.json), [limpieza](LIMPIEZA.json) y [ensayos](README.md).
