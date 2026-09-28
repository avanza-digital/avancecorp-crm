---
tags: [crm, ranking, cartera, publicacion]
fecha: 2026-09-28
estado: SQL y frontend publicados; un origen real pendiente
---

# Ranking — desglose completo y Nueva inversión de Cartera

Publicado en https://crm.miavance.com el 28/09/2026, con autorización expresa
de Miguel en la conversación. Sustituye el límite del primer arreglo del día,
que mostraba «Desglose de renovación y upgrade no disponible» cuando la
categoría financiera antigua no coincidía con la operación de cartera.

## Resultado comprobado

- La ficha reportada de 577.554 PEN + 40.000 USD corresponde íntegramente a
  **Upgrade** según sus operaciones registradas. Renovación es cero. Con el
  TC de la captura, 3,3776, son S/712.658.
- Las solicitudes confirmadas desde Mi cartera permiten acreditar su origen
  sin cambiar su categoría financiera. Decisión de Miguel: **Cartera → Nueva
  inversión, conservando lo registrado**. Se recuperaron cuatro fuentes por
  S/70.000. La regla sirve para cualquier fuente que cumpla esas condiciones;
  no contiene números de contrato, nombres ni importes específicos.
- En la primera ficha del día, Cartera queda en S/125.000: Renovación S/10.000,
  Upgrade S/80.000 y Nueva inversión S/35.000. Los demás canales y la conversión
  se conservan. Queda S/10.000 sin canal acreditado.
- Miguel confirmó que el contrato terminado en 666666 es su cuenta demo. Se
  marcó mediante `public.marcar_contrato_demo`, con motivo de mantenimiento
  autorizado en la auditoría. Los S/20.000 de prueba quedan fuera del capital
  real; contrato y cuotas no fueron eliminados.
- El contrato terminado en 000670 es real, según Miguel. No hay evidencia de
  lead, solicitud confirmada, operación de cartera ni acreditación del canal.
  Una coincidencia de correo pertenece a otra identidad y se descartó. Sigue
  pendiente confirmar su llegada; no se presenta como demo ni se inventa origen.

## Publicación SQL

Rama exclusiva `ranking-cartera-desglose-20260928`, referencia
`uttdpodejyqvyewavrlh`, id `ea64f26b-d782-41f0-8c1c-821cd71a493c`.
El replay histórico falló antes de los cambios actuales. Se reconstruyó con
estructura e historial productivos, controles técnicos y datos ficticios;
Cron permaneció apagado. No se copiaron clientes de producción.

Migraciones exactas ensayadas y fusionadas por **merge nativo**:

| Versión | SHA-256 |
|---|---|
| 20260928174554 | `05e915eaebf10e39b8ec442dedecd735d2cc3028b808038350b6caa9ddbcc654` |
| 20260928180237 | `575b6305cef1285ec8c1bdec083ac0b56e1a1bc23105a62983f23dc280fe4789` |

Historial 381 → 383. Snapshot inmediato antes/después: 144 filas, solo cuatro
cambios de origen; importes, monedas, categorías y vendedores idénticos.
Huellas de contratos, cuotas, operaciones, solicitudes y fotos idénticas.
Los dos núcleos monetarios, RPC v1 y las 22 Edge Functions quedaron intactos.
Control analítico: cero pendientes y sello válido. Lector final MD5
`53aecd29ef7efee10d4878b8e365b0d3`.

La exclusión demo ocurrió antes del snapshot del merge. Entre la primera
investigación y ese snapshot se registró otra inversión real de S/28.000 en
producción; por eso el número global de filas volvió a 144. No atribuir esa
actividad concurrente a la migración.

## Verificación

- PASS `npm run check`: 4.763 pruebas / 313 archivos, lint, tipos, build,
  cobertura, bundle y duplicación. Avisos de coverflow preexistentes.
- PASS Docker completo: 280 pruebas, 26 omitidas, cero fallos. Focal final de
  cartera desktop/mobile: 1/1 PASS; captura móvil inspeccionada.
- PASS SQL: captura legada con dos monedas, solicitud confirmada/pending,
  fuente exacta, COOPAC, conservación monetaria, conciliación y sello real de
  34 analistas / 2.048 leads. Nueva inversión queda en la foto; UPDATE rechazado;
  el histórico no depende de solicitudes vivas. Fotos antiguas siguen sin detalle.
- PASS Auth/PostgREST v1 y v2 en rama: gerencia y supervisor propio autorizados;
  equipo ajeno, inactivo, cliente y anónimo denegados. Lectura productiva v2
  bajo rol authenticated comprobó ambas fichas reportadas.
- Claude: CHANGES_REQUESTED, evaluado por PRIMARY; corrección de validación
  secundaria y pruebas de sello ampliadas. Hipótesis restantes descartadas con
  cuerpos vivos y ensayos. Ver `CRM-Avance-Corp/docs/auditorias/ranking-cartera-20260928/REVISION.md`.
- Advisors: advertencia SECURITY DEFINER intencional de la nueva RPC, con el
  mismo control autorizador de v1 y pruebas reales. Helpers privados sin acceso
  API. No se añadieron índices; avisos de no uso difieren por tráfico del banco.
- Recorrido autenticado visual en producción: NOT RUN. Pantalla en Docker y
  comparación HTTPS de archivos publicados: PASS.

## Frontend y Git

- Fuente limpia `43b3d6d0d7cad899a982bfef57b9124f306beea5`; copia independiente,
  sin worktree ni cambios ajenos sin confirmar. Commits de producto/revisión:
  `a764f140`, `a677381c`, `43b3d6d0`.
- Build `build-20260928T182709910Z`.
- ZIP `CRM-Avance-Corp/releases/crm-20260928T182710Z-43b3d6d0d7ca.zip`.
- SHA-256 `09314f3dbd0c83505c0b92b19ebf9947bedc575d2c0c216b053288964cf03dbe`.
- Artefacto verificado y preflight PASS conservando el vivo `5f3656c009c1`.
  Hostinger, operación oficial `hosting_deployStaticWebsite`. El primer intento
  recibió HTML al consultar version.json y terminó antes de subir; se comprobó
  la versión viva y se repitió con preflight intacto. Publicación aceptada.
- **Smoke PASS 13:31:21 Lima**: portada HTTP 200 y 81 archivos JS/CSS/index/version
  con bytes/SHA idénticos al manifiesto, sin cache-busting.
- Recuperación conservada: `crm-20260928T174317Z-5f3656c009c1.zip` y manifiesto.
  Ningún rollback ejecutado.
- Se usó [release-crm](../../.agents/skills/release-crm/SKILL.md), con la decisión
  previa de Miguel de mantener los cambios de Gloria/portal solo en local.
  Integración aislada sobre `avancecorp/main` (`2da2a103`), solo los commits de
  esta tarea; `CRM-Avance-Corp/app` idéntico al commit publicado.
- Rama Supabase exclusiva eliminada tras el smoke; las otras ramas no se tocaron.
  Evidencias privadas: `/private/tmp/ranking-desglose-20260928`.

Esta publicación recupera fuentes registradas y concilia el desglose. No cambia
la categoría de inversiones ni reconstruye fotos cerradas anteriores; tampoco
incorpora un nuevo campo obligatorio al alta manual antigua. No afirmar que
ya existen cero registros sin origen: el caso real indicado sigue pendiente.

Relacionado con [[Ranking - origen acreditado y desglose de cartera (2026-09-28)]].
