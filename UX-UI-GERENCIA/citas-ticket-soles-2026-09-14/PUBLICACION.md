# Ticket de Citas en soles — publicado el 14/09/2026

Estado: PUBLICADO y verificado en https://crm.miavance.com/.

## Artefacto

- Fuente: `32d57b5b3e155dd49a212afba40cd84056186581`, Main local/remoto y copia de construcción iguales durante la preparación previa a publicar.
- Build servido: `build-20260914T211412536Z`.
- ZIP: `crm-20260914T211416Z-32d57b5b3e15.zip`.
- SHA-256: `17fe0bf171b419a46e635b57a25f57acfba73c017c257b0d22240e91631c0545`.
- Construido con `npm run release:crm` desde la copia limpia; configuración productiva, bundle y manifiesto verificados. ZIP conservado en `CRM-Avance-Corp/releases/`.

## Lo publicado

Totales originales de capital PEN y USD en una línea compacta encima del avance mensual, detalle por analista y CSV. Ticket y proyección unificados en soles con el tipo de cambio existente; clientes deduplicados entre monedas. Carga, fallo, reintento, cambio de mes y motivos de exportación explícitos.

No se cambian las metas 1,25 internas ni 70/70, ni las reglas de mes/analista del evento. No se ejecutó SQL de escritura, migración, cambio de permisos ni deploy de Edge desde esta tarea.

## Concurrencia y reversa

La primera comprobación previa detuvo la publicación porque Tasas acababa de pasar a `tasas-faa1059-20260914` y su manifiesto estaba en una subcarpeta. Se localizó el ZIP real, se verificaron hash, limpieza y build y se copiaron ZIP/manifiesto al directorio canónico sin modificar los originales. El preflight pasó: `faa1059745aa` es ancestro del candidato `32d57b5b3e15`. No se omitió ni se forzó ese control.

Rollback inmediato correcto: `crm-20260914T210900Z-faa1059745aa.zip`, build `tasas-faa1059-20260914`, SHA-256 `80fbb3b5788177c357062689997144d21de65b1ffcc0084dc6d6b08e50904d41`. Se conserva también la publicación anterior de Citas del mismo día, pero no se usa como reversa inmediata porque omitiría la última entrega de Tasas.

F8 siguió trabajando en su documentación: commit `788dedc`, posterior a la publicación, integrado sin tocar sus archivos. Las otras sesiones y los archivos ajenos de recuperación/F7 se conservaron. Los commits documentales de cierre no requieren reconstruir el código servido.

## Verificación final

- Frontend: 3555 tests / 244 archivos PASS, lint, tipos, cobertura, build, bundle, release-config, worker y duplicación.
- E2E de Citas: 7 PASS finales; vista móvil con menú plegado y escritorio revisados.
- Cotización real: HTTP 200 para agosto y septiembre, fecha de corte exacta. La disponibilidad de fechas de la fuente consta en `tipo-cambio-http.json`; no se inventan cotizaciones.
- Hostinger: carga exitosa y deploy aceptado; confirmado posteriormente por versión y contenido HTTP.
- **67/67 recursos HTML, JavaScript, CSS, JSON y manifest coinciden byte a byte con el artefacto.**
- Un primer cliente HTTP con `--compressed` recibió desafío antibots 403. La misma URL sin solicitar compresión devolvió 200; la comparación completa final pasó sin cambiar reglas del hosting. Ese fallo de comprobación no se presentó como PASS.
- Imágenes y fuentes no se vuelven a verificar individualmente en este ajuste; no fueron modificadas.
- Inspección autenticada manual de producción: NOT RUN. Las pruebas UI usan datos ficticios; HTTP confirma el código publicado.
- Matriz RLS y CLI `gate:realidad`: NOT RUN en este ajuste; causas y comprobaciones específicas en README. No se atribuye PASS a la matriz histórica.

Evidencia: `http-publicado.json`, `hostinger-respuesta.json`, `tipo-cambio-http.json`, `citas-1440.png`, `citas-390.png` y resolución de la revisión en `README.md`.
