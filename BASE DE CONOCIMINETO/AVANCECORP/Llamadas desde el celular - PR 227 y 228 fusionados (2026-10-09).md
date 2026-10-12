# Llamadas desde el celular - PR 227 y 228 fusionados (2026-10-09)

Relacionado: [[Llamadas desde el celular - instalacion y publicacion (2026-10-07)]] · [[Telefonia CRM - plan por fases y Jev asistido (2026-09-29)]].

Miguel autorizó expresamente «ok mergea los dos» después de la revisión conjunta. Fusionados mediante squash y gates ordinarios, sin bypass administrativo:

- [PR #228](https://github.com/avanza-digital/avancecorp-crm/pull/228): `30eb8109f4e3031b3bece78eb71729b73ae824a9`, 09/10 10:05 Lima. Protege «Registrar el corregido» cuando ya existe una encuesta abierta.
- [PR #227](https://github.com/avanza-digital/avancecorp-crm/pull/227): `0f619b024be93f646742e299bfc7c273dbfdda43`, 09/10 10:15 Lima. Actualiza los resúmenes operativos y mantiene 33/102 tareas.

Verificado remotamente: main en `0f619b0`, padre `30eb810`; ambos PR con `merged=true`. Se actualizaron antes con main y se comprobó que sus 7 archivos de código/pruebas y 9 documentos, respectivamente, conservaran los mismos blobs que la revisión. Aprobaciones registradas y preflight/app-check/verify SUCCESS en las cabezas actualizadas.

Revisión previa: 156/156 pruebas dirigidas, 11/11 E2E en Docker local; JSON y regeneración documental PASS. [Único comentario de coordinación en #227](https://github.com/avanza-digital/avancecorp-crm/pull/227#issuecomment-6070626325).

## Pendientes

- Publicar el frontend con #228; esta tarea solo fusionó los PR.
- P9 físico en C1 después de publicar; conservar las pruebas físicas ya acreditadas.
- P14-L3 y consulta de base sin números; decisiones H-P5/H-P10 y desactivación de dos leads de prueba, según coordinación.
- El plan completo sigue en curso; no repetir P1–P15 completos por esta corrección.
- Jev permanece apagado.

El trabajo preexistente sin confirmar del checkout compartido se preservó; las fusiones y aprobaciones se realizaron por GitHub.
