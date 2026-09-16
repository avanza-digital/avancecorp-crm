# Preparación de CI antes de publicar

La comprobación en GitHub de `28aa558` detectó defectos del banco de pruebas
que también existían en la corrida anterior `1e507bb`:

- `respuestas-tasa.test.ts:80`: el spy sobre la instancia de Storage no simulaba
  un rechazo en jsdom/Node 24. El guardado real devolvía `true`. Se sustituye el
  global dentro de un try/finally y se comprueba que el doble fue invocado.
- `citas-avance-mensual.spec.ts:57` y `citas-gerencia.spec.ts:20`: las capturas
  utilizaban `/private/tmp`, inexistente en el runner Linux. Se guardan mediante
  `TestInfo.outputPath`, en la carpeta propia del caso.
- `respuestas-tasa.spec.ts:114`: el contador de audio podía leerse antes de
  terminar la activación o la alerta. Se espera con `expect.poll`, manteniendo
  exactamente la exigencia de dos notas por lote.
- La suite ejecutaba 218 casos con un worker y agotaba los 20 minutos. El job
  E2E usa dos workers; conserva casos, aserciones, reintentos y límite de tiempo.

Evidencia anterior: [run 35039574191](https://github.com/avanza-digital/avancecorp-crm/actions/runs/35039574191).
La corrida `28aa558` reprodujo el fallo unitario y los paths de capturas.

Verificación focal local de la corrección: ocho unitarias y once E2E PASS.
No se cambió la lógica de producto ni las migraciones por estos ajustes.
El resultado del CI del commit de entrega se registra junto al artefacto en
`releases/PREPARADO-contratos-*.md`; el paquete anterior queda sustituido al
integrar esta corrección en Main.
