---
tags: [crm, cartera, multiempresa, f8, ux]
actualizado: 2026-09-15
estado: preparada-localmente
---

# F8 — ficha anterior recuperada para multiempresa

Miguel pidió recuperar la apariencia de la ficha anterior para la ficha multiempresa y continuar con el plan propuesto. La adaptación está preparada, con revisión visual pendiente antes de publicar.

## Resultado

Se recuperaron el panel de 620 px, la cabecera, la continuidad, el seguimiento, las tarjetas compactas, la información agrupada, el historial y las acciones al pie de la ficha anterior. Las inversiones amplían su detalle con **Ver inversión**. Los componentes visuales se comparten entre ambas fichas y permiten envolver textos largos en móvil.

Los importes, cantidades, vencimientos y capacidades siguen viniendo de los núcleos canónicos. Cada empresa/moneda conserva su grupo; capital activo y capital registrado tienen etiquetas distintas. PDF pendiente y anulación comercial se reconocen sin desplegar detalles. Las condiciones COOPAC y los escritores de F4/F6 existentes se conservan.

La ficha mantiene detalle y foco si falla o se desactiva Postventa. Al recuperarse exige una nueva lectura y no reabre sola una gestión que estaba abierta antes del corte.

## Evidencia y estado

- `npm run check`: **PASS**, 245 archivos / **3.596 pruebas**, más lint, tipos, build, bundle y duplicación.
- Pruebas focales de fichas: **54 PASS**.
- Recorridos relacionados de navegador: **23 PASS**, incluidos Analista/Gerencia en escritorio y móvil, Directorio, supervisor, revocación, recuperación y acciones F5/F6.
- Claude: dos revisiones por wrapper, ambas con observaciones; Codex corrigió los hallazgos y verificó después. No existe un tercer dictamen de aprobación.
- Gate de realidad: **NOT RUN**, entorno real sin `SUPABASE_URL`; el intento no consultó datos. Matriz E2E completa y recorrido manual de producción **NOT RUN**.
- Sin publicación, cambio SQL/banderas/datos productivos ni nuevo banco de pago en esta entrega.

Acta, dictámenes y comparación con datos sintéticos:
`CRM-Avance-Corp/supabase/scripts/multiempresa-f8/ficha-anterior-2026-09-15/`.
Abrir `COMPARACION.html` para revisar los dos diseños y las variantes móvil/escritorio.

## Siguiente paso

Miguel revisa el diseño preparado. Antes de publicar, integrar y verificar `avancecorp/main` y construir desde ese commit; no reutilizar el artefacto previo. G7 y F8 permanecen abiertos.

Relacionadas: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]], [[F8 - ensayo remoto y correccion de conflictos (2026-09-15)]], [[F8 - ajustes de cartera y condiciones COOPAC preparados (2026-09-14)]], [[F8 - piloto nominal activado (2026-09-14)]].
