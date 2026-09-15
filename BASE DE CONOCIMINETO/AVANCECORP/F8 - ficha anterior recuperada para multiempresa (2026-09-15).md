---
tags: [crm, cartera, multiempresa, f8, ux]
actualizado: 2026-09-15
estado: publicada-g7-abierto
---

# F8 — ficha anterior recuperada para multiempresa

Miguel pidió recuperar la apariencia de la ficha anterior para la ficha multiempresa y continuar con el plan propuesto. Aprobó la comparación y la secuencia de verificación real y publicación. **La adaptación está publicada**, commit de producto `d93d805`, build `build-20260915T160348830Z`.

## Resultado

Se recuperaron el panel de 620 px, la cabecera, la continuidad, el seguimiento, las tarjetas compactas, la información agrupada, el historial y las acciones al pie de la ficha anterior. Las inversiones amplían su detalle con **Ver inversión**. Los componentes visuales se comparten entre ambas fichas y permiten envolver textos largos en móvil.

Los importes, cantidades, vencimientos y capacidades siguen viniendo de los núcleos canónicos. Cada empresa/moneda conserva su grupo; capital activo y capital registrado tienen etiquetas distintas. PDF pendiente y anulación comercial se reconocen sin desplegar detalles. Las condiciones COOPAC y los escritores de F4/F6 existentes se conservan.

La ficha mantiene detalle y foco si falla o se desactiva Postventa. Al recuperarse exige una nueva lectura y no reabre sola una gestión que estaba abierta antes del corte.

## Evidencia y estado

- `npm run check`: **PASS**, 245 archivos / **3.596 pruebas**, más lint, tipos, build, bundle y duplicación.
- Pruebas focales de fichas: **54 PASS**.
- Recorridos relacionados de navegador: **23 PASS**, incluidos Analista/Gerencia en escritorio y móvil, Directorio, supervisor, revocación, recuperación y acciones F5/F6.
- Claude: dos revisiones por wrapper, ambas con observaciones; Codex corrigió los hallazgos y verificó después. No existe un tercer dictamen de aprobación.
- La medición real posterior por SQL cubrió los ocho supuestos del gate: siete conformes, 296 clientes históricos sin domicilio. Se usó `public.perfiles`; el CLI conserva una referencia inexistente a `crm.perfiles`, por lo que no se declara PASS del CLI.
- Cartera y primera ficha de los cuatro participantes: **PASS** con rol SQL `authenticated`, límite de ocho segundos por sentencia y `ROLLBACK`. No equivale a login JWT/HTTP.
- Publicación: **80 archivos de código/configuración con hash exacto**, once PNG preexistentes optimizados por CDN y `.htaccess` bloqueado. CRM/portal HTTP 200; ZIP y rutas internas protegidos. Paquete y reversa verificados.
- Matriz E2E completa y recorrido manual de producción **NOT RUN**, sin navegador conectado. Sin cambio SQL/banderas/datos económicos ni nuevo banco de pago.

Acta, dictámenes y comparación con datos sintéticos:
`CRM-Avance-Corp/supabase/scripts/multiempresa-f8/ficha-anterior-2026-09-15/`.
Abrir `COMPARACION.html` para consultar el diseño aprobado y `PUBLICACION.md` para la evidencia productiva. El paquete se construyó cuando Main local y `avancecorp/main` coincidían; incorpora el ajuste previo de permisos de «Nuevo cliente».

## Siguiente paso

Retomar los recorridos y conformidades reales en `multiempresa-f8/ACTA-G7.md`. G7-R01 está resuelto técnicamente y los cuatro contextos vuelven a responder. La aceptación visual no cierra el muestreo, los casos especiales ni la conformidad financiera. G7 y F8 permanecen abiertos; F9 aún no corresponde.

Relacionadas: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]], [[F8 - ensayo remoto y correccion de conflictos (2026-09-15)]], [[F8 - ajustes de cartera y condiciones COOPAC preparados (2026-09-14)]], [[F8 - piloto nominal activado (2026-09-14)]].
