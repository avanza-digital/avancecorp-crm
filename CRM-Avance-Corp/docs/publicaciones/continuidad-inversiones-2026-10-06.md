# Continuidad de inversiones publicada — 6 de octubre de 2026

Publicado y verificado en https://crm.miavance.com a las 16:35 Lima. Cuando un cliente tiene una inversión en cualquier empresa del grupo, la ficha multiempresa deshabilita «Registrar nueva inversión» y muestra una explicación accesible. Sin inversiones, conserva «Registrar primera inversión». Upgrade, renovación y reinversión mantienen sus condiciones.

## Fuente y autorización

Miguel autorizó «ok vmaos deploy» y confirmó la integración con «ya esta». [PR #206](https://github.com/avanza-digital/avancecorp-crm/pull/206) integrado a las 21:32:15 UTC, con cambios, preflight, app-check y verify PASS.

- Commit publicado: `4e6ee7ee296be83cd96366e3e79685343b3b706b`.
- Main del workspace, Main de la copia limpia y `avancecorp/main` coincidentes antes de publicar.
- Árbol completo idéntico al candidato probado `18e1e6c2c97caa4aa73c59acbdf3585cef0b5c5f`: `d10b8d35dc87ef780e1c7fe038c8f7144d41eca2`.
- El cambio propio contiene ocho archivos. Se conservó el trabajo local de otras tareas y se incorporó el Main remoto existente. El ledger conserva tanto B11 publicada como las entradas locales pendientes de postventa; no se aplicó ninguna migración.

## Artefacto publicado

- Build: `build-20261006T213354829Z`.
- ZIP: `releases/crm-20261006T213355Z-4e6ee7ee296b.zip` (2,512,687 bytes).
- SHA-256: `9b5be00b190443726f5520fc37a54ba27ff3785ace447200b7ce2d807430e33d`.
- Manifiesto: `releases/crm-20261006T213355Z-4e6ee7ee296b.manifest.json`.
- Fuente limpia; destino `crm.miavance.com`.
- Versión anterior conservada y revalidada: `crm-20261006T165240Z-afae7b59412a.zip`, SHA-256 `8921ca43f4f580c17d4175b92a922bc09f5ec837adab989aa7c0c971569a2c6f`. No se ejecutó rollback.

## Verificación

| Comprobación | Resultado |
| --- | --- |
| `npm run check` del código idéntico publicado | PASS: 385 archivos, 6.206 pruebas, lint, tipos, cobertura, build, bundle y duplicación 0,43 % |
| E2E locales en Docker | PASS: 25 pruebas; `f5-cartera`, `mi-cartera-detalle`, `contrato-crear` |
| `release:crm` y `release:crm:verify` definitivos | PASS, construidos desde Main limpio |
| Preflight obligatorio contra el vivo | PASS |
| Hostinger | PASS: una publicación aceptada a las 2026-10-06T21:35:32.805Z |
| HTTPS | PASS: 154 archivos; 140 coinciden en bytes/SHA, 13 imágenes disponibles y `.htaccess` protegido |
| Portada, JavaScript principal y versión | PASS: HTTP 200 y coincidencia con el manifiesto |
| ZIP en URL pública | PASS: HTTP 404 |
| Smoke real en el navegador | PASS: nueva inversión deshabilitada, upgrade habilitado y explicación visible |
| Gate de realidad | NOT RUN: sin `SUPABASE_URL` en su entorno; el smoke de UI no sustituye ese gate |

Check y E2E se ejecutaron sobre el candidato; se reutiliza su evidencia por equivalencia exacta del árbol tras el squash, sin presentarlos como nuevas ejecuciones. La ficha real se comprobó sin crear ni modificar operaciones. La captura solo incluye botones y texto del bloqueo, sin datos del cliente.

## Alcance y revisión

Cambio de interfaz; no agrega una validación de servidor ni modifica conversión de leads, venta cruzada, portal, tasas o datos. El contador global se aplica a la ficha multiempresa; la vista antigua de Avance solo conoce contratos Avance. La disponibilidad de continuidad conserva los requisitos actuales.

Revisión independiente de Claude mediante el wrapper del repositorio: CHANGES_REQUESTED. Se incorporaron los ajustes de accesibilidad y texto condicional; se documentaron los límites de alcance. No se solicitó otro dictamen para obtener aprobación.

Evidencia: `output/continuidad-inversion-20261006/deploy/`, incluidos `estado.json`, `equivalencia-main.json`, `check-limpio.log`, `e2e-limpio.log`, `release-definitivo.log`, `hostinger-recibo.json`, `postflight-https.json`, `smoke-produccion.json` y respaldos de alineación.

![Acciones verificadas en producción](../../output/continuidad-inversion-20261006/deploy/botones-publicados.jpg)
