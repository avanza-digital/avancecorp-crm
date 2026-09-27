---
tags: [crm, ranking, origenes, correccion-datos, propuesta]
fecha: 2026-09-26
estado: tres enlaces publicados; regla de nueva inversión solo propuesta
---

# Ranking — enlaces excepcionales y propuesta por empresa

## Corrección puntual ejecutada

Miguel autorizó enlazar el origen de los tres leads atípicos creados por el
[[Backfill de conversion - contratos nuevos sin lead (2026-09-22)]] del 23/09.
No autorizó ampliar globalmente el criterio temporal de atribución.

Ejecución técnica de Codex, con autorización humana de Miguel:
`2026-09-26T22:13:41.429174Z` (17:13 Lima).
Solo se enlazó `crm.leads.contrato_id` en tres leads ya convertidos:
contratos `001385` (Walking, S/ 32.450), `001412` (Referido, S/ 50.000)
y `001420` (Referido, S/ 10.000). No se cambió el canal, la fecha de creación,
la fecha de conversión, la categoría, el vendedor ni el capital. El trigger
normal actualizó `actualizado_en` y dejó tres auditorías.

Se usó la válvula transaccional de mantenimiento existente
`crm.op_privilegiada`; ningún trigger fue apagado. No hubo suplantación de
sesión: el actor de auditoría queda nulo como intervención técnica y la
autorización humana se documenta aquí. No hubo migración ni nuevo despliegue web.

Resultado para Betzabeth, septiembre, en monedas originales:

| Canal | PEN | USD |
|---|---:|---:|
| Walking | 72.450 | 30.000 |
| Referido | 283.000 | 0 |
| Sin origen identificado | 150.000 | 0 |

**Pendiente independiente:** esos S/ 150.000 corresponden a tres operaciones
que `crm.operaciones_cartera.tipo` identifica como `upgrade`, pero sus contratos
conservan `categoria='nuevo'`. El desglose publicado mira esta última categoría.
Deben tratarse como Cartera; esta intervención NO corrigió esa lectura ni
recategorizó contratos. No generar leads para esos upgrades.

## Evidencia y límites

Paquete local ignorado: `CRM-Avance-Corp/releases/ranking-enlaces-20260926/`.
Incluye SQL exacto, ensayos, review y `verificacion.json`.
SQL SHA-256: `f6cdadffb4f198cc1323826a8dadb14802219afe5ff509b3bb1567f8f524d796`.

- Banco Docker exclusivo `ranking_enlaces_20260926`, copia de fixtures sintéticos:
  3 enlaces PASS; repetición 0 enlaces PASS; ROLLBACK PASS.
- Origen o importe inesperados: rechazo sin escrituras PASS.
- Triggers relevantes iguales a producción. No se copiaron personas reales al banco.
- Antes de COMMIT: todos los campos del lead salvo enlace/reloj iguales; contratos
  idénticos; núcleo de capital y conversión y tasas por canal idénticos;
  historial, asignaciones, SLA y tareas idénticos.
- Desglose completo idéntico salvo los tres canales autorizados; sin duplicar
  contratos, mover vendedores ni alterar importes.
- Auditoría limitada a esas tres escrituras por ID de transacción (`xmin`),
  sin confundir escrituras concurrentes por una ventana de tiempo.
- Revisión Claude LEVEL 3: CHANGES_REQUESTED por dos comprobaciones P2 adicionales.
  PRIMARY incorporó ambas y volvió a pasar ensayos positivos, negativos y repetición.
  No se solicitó otra opinión para obtener un PASS.
- Postflight productivo PASS: tres enlaces y tres auditorías; lectura separada
  confirmó los importes de la tabla.
- Frontend/build/E2E: NOT RUN en esta corrección de datos; no se modificó código
  desplegado. Banco local conservado para reproducibilidad, sin rama remota nueva.

Auditorías:
`06b1690c-007e-4c60-a7e9-ad4f4b109f22`,
`4867e52e-2832-4868-9f85-1fd4c66dbead`,
`7fd68054-2f88-4cc8-9478-406dcbe20568`.
La reversa, si se autoriza, debe limitarse a estos enlaces y conservar la
auditoría histórica; no restaurar fechas ni borrar registros de auditoría.

## Propuesta de Miguel — NO implementada

Conservar «Nueva inversión» y mostrar únicamente empresas en las que la persona
nunca tuvo una inversión confirmada: Avance, Qorilazo y Prodelco por separado.
Si invirtió en todas, no mostrar el botón. Consultar historial completo
(incluidos contratos y cierres legados), no solo inversiones activas ni la
presencia en `crm.inversiones`. Un borrador o una solicitud cancelada no acredita
una primera inversión.

En una empresa donde ya invirtió, orientar a upgrade o renovación según el
contrato. La restricción deberá existir en servidor y en todas las puertas,
además del selector visible, conservando roles y atribución de venta cruzada.

**Caso pendiente de decisión:** si retiró todo y vuelve, no tiene un contrato
activo que permita el upgrade actual. Recomendación: una ruta de
«Reinversión / volver a invertir» para cliente existente, sin tratarlo como
primera captación. Las cooperativas ya tienen una operación llamada reinversión;
no asumir que sus reglas son idénticas a las de Avance.

Relacionado con [[Ranking - publicacion verificada (2026-09-26)]],
[[Upgrade es un contrato aparte, no una modificacion (2026-09-21)]],
[[Gestión comercial de clientes - renovaciones y upgrades]] y
[[Venta cruzada - servidor probado en banco y P1 del PDF (2026-09-24)]].

