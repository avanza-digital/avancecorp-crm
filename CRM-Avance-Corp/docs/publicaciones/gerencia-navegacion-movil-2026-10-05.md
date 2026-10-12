# Publicación: navegación móvil de Gerencia

**PUBLICADO Y VERIFICADO** en https://crm.miavance.com/. Fecha local: 5 de octubre de 2026 (Lima); build y evidencias fechados en UTC el 6 de octubre. Miguel autorizó el deploy y confirmó después la integración del PR.

Gerencia, por debajo de 768 px, dispone de **Resumen · Citas · Metas · Más**. Los 18 módulos autorizados siguen disponibles. A partir de 768 px se utiliza el lateral existente. Esta entrega no cambia consultas, permisos, datos ni backend.

## Fuente y artefacto

- PR: https://github.com/avanza-digital/avancecorp-crm/pull/201, integrado mediante squash.
- Commit publicado: `1d4134e6476f007ac14cbb38df42b84e22fe862f`.
- Build vivo: `build-20261006T031013454Z`.
- ZIP: `releases/crm-20261006T031014Z-1d4134e6476f.zip`, 2.475.735 bytes.
- Manifiesto: `releases/crm-20261006T031014Z-1d4134e6476f.manifest.json`.
- SHA-256 del ZIP: `054ad6350741d6b73055e3233ead75adb214581e246cdb9adc01a3c5c5b42961`.
- Fuente limpia en `/tmp/avancecorp-navegacion-movil-20261005/CRM-Avance-Corp`; demo deshabilitada y configuración productiva verificada.

Main local, `avancecorp/main`, el remoto consultado y el manifiesto coincidían al publicar y al cerrar la comprobación. La alineación posterior al squash comparó árboles idénticos y conservó el índice y los cambios locales. No se incluyeron trabajos sin confirmar. El código de la app es idéntico al de `7253de7e`, sobre el cual se completaron los gates locales; las diferencias de integración solo conservan documentación ya confirmada.

## Verificación

| Comprobación | Resultado |
| --- | --- |
| `npm run check` | PASS: 379 archivos / 6.120 pruebas; lint, tipos, cobertura, release-config, SW, build, bundle y duplicación |
| E2E Docker local completa | PASS: 351 aprobadas, 26 omitidas, 0 fallos; 2 workers y 0 reintentos |
| Revisión secundaria | PASS; sin bloqueantes y con espera de diálogo incorporada al helper |
| GitHub | PASS: `app-check`, `verify`, `preflight`, `cambios`; PR integrado |
| `npm run release:crm` y `release:crm:verify` | PASS; manifiesto identifica fuente limpia y destino correcto |
| Preflight de publicación | PASS: build anterior `b286b2bfce9a` contenido en candidato `1d4134e6476f` |
| Hostinger | PASS: subida aceptada y deploy aceptado; confirmación efectiva por archivos servidos |
| HTTP y huellas | PASS: 135 archivos con HTTP 200, SHA-256 y tamaño idénticos; incluidos portada, JS/CSS, SW y versión |
| PNG | PASS: 13 imágenes con HTTP 200 y tipo imagen; no se exige igualdad binaria porque el CDN transforma PNG |
| ZIP fuera del web root | PASS: HTTP 404 en CRM y portal |
| Smoke con Gerencia real en Chrome | PASS: Resumen, Citas por equipo con día/supervisor conservados, Metas, Más, Ranking, Atrás y móvil/escritorio |
| PWA instalada en iPhone/Android físicos | NOT RUN; pendientes teclado, giro, área segura y cierre de sesión en esos dispositivos |
| Gate con base real | NOT RUN; intento previo sin credenciales de servicio en shell. No se modifican datos, consultas ni backend en esta entrega |

El smoke utilizó 390 × 844 y 1024 × 768. La consulta de un equipo mantuvo las 9 citas mostradas en Resumen. No se crearon ni eliminaron datos reales. No se registraron errores JavaScript durante el recorrido; hubo avisos de GSAP por selectores de animación ausentes. Se restauró el tamaño del navegador tras la comprobación.

## Evidencia y recuperación

Evidencia: `output/navegacion-movil-local/deploy/estado.json`, `alineacion-main.json`, `github-merged.json`, `release-build.log`, `preflight.log`, `hostinger-recibo.json`, `postflight.json`, `version-imagenes.json`, `smoke-navegador.json`, `resumen-publicado.png` y `mas-publicado.png`. Los gates locales, su equivalencia y la revisión están en `output/navegacion-movil-local/`.

Paquete anterior conservado: `releases/crm-20261006T003149Z-b286b2bfce9a.zip` y su manifiesto. Fuente `b286b2bfce9a24004e887ee0cb127ecf5dab5a23`, build `build-20261006T003148355Z`, SHA-256 `90b29455d9e6b2fc8eded87f0cb5a02286e18ddf2dc42c8b07eccef5a63f429d` (verificado). No se ejecutó rollback; cualquier recuperación seguirá el preflight y la decisión de Miguel según el procedimiento vigente.

Estas actas son posteriores al despliegue y no cambian su fuente: el commit publicado es siempre el identificado en el manifiesto.
