---
tags: [crm, conversion, produccion, verificacion]
actualizado: 2026-10-19
---

# Conversión — primeras conversiones reales validadas

**19/10/2026, captura final 12:14:52 Lima: 8.2 PASS técnico.** Miguel pidió validar desde la base o Docker. Se hicieron ambas comprobaciones, sin escrituras productivas ni despliegue nuevo.

Producción sigue en `exigir`, revisión 2, desde las 09:44:22.886 de Lima. Desde la activación se observaron dos conversiones: **Qorilazo a las 09:54:03 y Avance a las 12:10:43**. Ambas tienen asistencia y entrevista con resultado `inicia_registro` de la misma cita/ciclo, anteriores a la confirmación; una solicitud, una inversión vigente y su fuente contable vinculadas; un evento de registro y una actividad total de conversión por lead. Sin duplicados en los casos auditados.

El control independiente por inversiones iniciales nuevas encontró 2, con 0 sin solicitud confirmada y 0 sin evidencia exigida/completa. Cero leads convertidos sin fecha y cero con fecha antigua pero actualizados desde la activación. Revisión y corte de ambos snapshots coinciden con el control. Las cantidades son una fotografía del momento indicado, no contadores en tiempo real.

Docker: **99 comprobaciones Auth/HTTP/RLS PASS**, tres suites SQL (`test`, `test-conversion`, `test-todos`) PASS. Misma implementación pertinente: 18 funciones (cuerpo, propietario, permisos, configuración) y 11 triggers habilitados idénticos entre Docker y producción. Se probaron rechazos por hechos incompletos o de otra cita/ciclo, leads antiguos, permisos y reintentos sin duplicados. Las copias temporales se eliminaron y el banco fuente quedó intacto, con 0 leads y 0 solicitudes.

Claude: primer intento incompleto, no considerado aprobación; único reintento operativo **PASS** sobre el primer caso. Codex aceptó su ampliación del control por inversiones, fechas, revisión y actividades, la ejecutó y validó también el segundo caso recién registrado. No se atribuye a Claude la revisión de ese caso posterior. La fecha `convertido_en` representa el inicio de sentencia; `verificado_en` se toma dentro del trigger unos milisegundos después. Esa diferencia no indica una confirmación sin verificar.

## Progreso y límites

- Estado de la auditoría de las 12:14: 47/48 subfases, 8.2 acreditada por registros productivos.
- **Cierre posterior, 19/10 15:30 Lima: 8.6 aceptada por Miguel; 48/48 (100 %), fase 8: 6/6.** Ver [[Conversion - cierre y limpieza de sesion (2026-10-19)]]. La aceptación no implica asistencia física observada por la auditoría.
- [Plan en Figma](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=72-190).
- Acta y evidencia duradera: `/Users/usuario/Downloads/CRM-validacion-conversion-20261019/ACTA-VALIDACION.md`. Consultas de solo lectura, respuestas originales saneadas, logs Docker, paridad y review incluidos en esa carpeta.
- Fuente ensayada: Main `6479402d63b22b5c254aef65abad2e2666ad0ab5`, copia aislada limpia al validar y retirada al cerrar la sesión. Sin cambios de código, migraciones o ZIP web nuevo por la validación/cierre. La versión de esta entrega es `ficha-compacta-6479402d-20261019`.
- Navegador manual y nuevos E2E visuales: NOT RUN en esta validación de servidor. La paridad no abarca todos los objetos de base ni certifica operaciones futuras.

Relacionadas: [[Conversion - exigencia activa en produccion (2026-10-19)]] · [[Conversion - ficha compacta publicada (2026-10-19)]] · [[Conversion - plan por fases y objetivo goal (2026-10-18)]].
