---
tags: [crm, portal, contratos, numeracion, auditado, preparado]
actualizado: 2026-09-19
---

# Número de contrato: prefijos 2024, 2025 y 2026

**IMPLEMENTADO Y AUDITADO LOCALMENTE; SIN PUBLICAR.**

Miguel confirmó que los analistas pueden elegir `2024-01-`, `2025-01-` y
`2026-01-`. El último sigue como selección inicial del alta. El segmento `01`
no es el mes. Se transcriben seis dígitos del contrato físico, incluidos ceros
iniciales. La serie no determina las fechas ni el período comercial.

Alta, corrección y borradores del CRM conservan el número completo. La auditoría
ampliada pedida por Miguel y revisada con Claude detectó que los dos editores
antiguos del portal solo reconocían 2026: al corregir 2024/2025 perdían el prefijo.
También se corrigieron esos formularios, su búsqueda de duplicados y las
respuestas tardías de otra serie/contrato. Una nueva alta restaura 2026 y vacía
los dígitos. Los números legados AC mantienen el tratamiento anterior.

La base usa UNIQUE sobre el número completo; se admite repetir los seis dígitos
en series diferentes. Las relaciones con cuentas, cuotas, inversión, renovación
y PDF usan UUID. No se cambian permisos ni lógica financiera y no hace falta
una migración productiva para este selector.

## Evidencia

- PASS: gate CRM `npm run check`, 3.746 tests, lint, tipos, cobertura y build.
- PASS: 55 tests de componentes y 10 recorridos Playwright de alta CRM.
- PASS: 104 tests del portal; el defecto se reprodujo antes de corregirlo.
- PASS: DOM real del portal en Chromium, 390/1280 px, ambas pantallas.
- PASS: 48 tests del handler/renderer PDF, incluidos PDFs de las tres series.
- PASS: 14 comprobaciones SQL reales en copia sintética aislada con ROLLBACK,
  incluidos alta/corrección, snapshot, cuenta/cuotas, autorización, cinco horas,
  idempotencia y preparar/corregir/confirmar inversión.
- PASS: dos altas simultáneas del mismo número persisten una sola.
- PASS: 32 definiciones del recorrido reproducidas con huella idéntica a la
  lectura de producción. El resto del banco sigue siendo sintético local.
- Claude devolvió CHANGES_REQUESTED en la auditoría ampliada. El PRIMARY resolvió
  el fallo del portal y contrastó el resto con pruebas; no se pidió otro dictamen
  para conseguir aprobación.
- Se reparó una prueba anterior del portal que buscaba los roles en index.ts,
  aunque ahora están en autorizacion.mjs. Comprueba el resolver y la revocación;
  no se modificaron los permisos de producto.
- NOT RUN: `gate:realidad` no llegó a medir por faltar SUPABASE_URL en su entorno.
  El catálogo productivo se leyó mediante el conector. Sin escrituras productivas.

## Publicación coordinada pendiente

Publicar el portal antes o junto con el CRM. Módulos y núcleo primero, HTML
después, service worker al final y purga de CDN según las reglas del portal.
Pines preparados: analista v29, contratos v44, numero-contrato-core v1,
service worker avance-v119. No pedir URLs versionadas antes de subir sus archivos.

El portal recarga al actualizar su service worker. El CRM avisa de la nueva
versión y permite guardar antes de recargar. Una pestaña antigua conserva el
editor anterior: actualizarla antes de operar con 2024/2025 al publicar.
No se publicó, migró, renumeró ni deduplicó ningún contrato real.
Miguel autorizó la publicación invocando `$release-crm` el 19/09/2026.
La autorización ya está recibida. El release requiere comprobar Main integrado,
construir desde una copia limpia y publicar primero el ajuste del portal.
Esta sesión no expone la operación de despliegue de Hostinger; solo dispone de
sus herramientas de facturación. No se cambió la configuración del conector.

[Informe de auditoría con alcance y límites](../../CRM-Avance-Corp/docs/auditorias/prefijos-contrato-2026-09-19.md).

Relacionado: [[Número de contrato]] · [[Ciclo de vida de contratos]] ·
[[Periodo comercial de contratos]] · [[Inicio]].
