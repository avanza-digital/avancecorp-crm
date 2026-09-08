# Inasistencias que terminaron en depósito

Ampliación local solicitada por Miguel el 8 de septiembre de 2026. Disponible en http://127.0.0.1:4180/prototypes/citas-crm.html, pestaña **Resultados**, apartado de inasistencias.

## Uso

La opción **Leads que depositaron** abre la lista de prospectos con depósito confirmado después de faltar. La franja inferior muestra cantidad, base, porcentaje y montos separados en PEN/USD. **Ver depósitos** abre fecha de depósito, confirmación, monto y código de cada movimiento ficticio. El acceso **Sin nueva cita** se conserva como filtro compacto.

Los filtros habituales eligen las inasistencias de origen. El mes y la semana no recortan los depósitos posteriores: se siguen hasta el corte del ejemplo. Los filtros de moneda y monto siguen refiriéndose al estimado de la cita; los depósitos de los leads seleccionados se muestran en su propia moneda.

## Definición del ejemplo

- Base: leads únicos con al menos una inasistencia en la consulta, ocurrida hasta el corte.
- Depositantes: leads de esa base con al menos un depósito desde la primera inasistencia filtrada, confirmado y no anulado al corte.
- Conversión: depositantes / base de leads con inasistencia. Sin base no se calcula porcentaje.
- Un mismo lead cuenta una sola vez aunque haya faltado varias veces o realizado varios depósitos. Cada movimiento se suma una vez por id.
- Se excluyen pendientes, anulaciones conocidas al corte, fechas inválidas, depósitos previos, depósitos o confirmaciones posteriores al corte, montos no positivos y movimientos de otros leads.
- Puede haber depósitos sin reprogramación o sin otra asistencia. La tarjeta dice **Con o sin nueva cita** y no lleva una flecha desde asistencia. Las tres tarjetas anteriores siguen contando episodios de inasistencia; la conversión financiera identifica explícitamente leads únicos.
- El vínculo por lead y orden temporal muestra un resultado posterior; no prueba causalidad de una cita concreta.
- Nunca se interpreta `cerrado` o el monto estimado de la cita como depósito.

Ejemplo fijo al 7 de septiembre de 2026, 13:00 Lima: 4 inasistencias, 3 reprogramaciones, 1 asistencia posterior y **2 de 4 leads con depósito (50%)**. Andrea Peralta: S/ 35.000, después de su nueva cita realizada. Esteban Duarte: US$ 5.000, sin nueva cita. El pendiente de Mónica y el depósito anulado de Pablo no incrementan el indicador.

Los depósitos son fixtures expresos de la propuesta. No se modificaron datos reales, APIs, contratos, lógica financiera productiva, migraciones ni componentes compartidos. La integración real requiere movimientos confirmados identificables, vínculo fiable al lead y validación del contrato de lectura; los cierres y el capital acumulado de Gerencia no se renombraron como depósitos.

## Verificación

- **PASS:** 20 tests del prototipo en 4 archivos, incluidos 7 nuevos sobre depósitos y su consulta. Cubren identidad, doble conteo, fechas, corte, confirmación, anulación, independencia de reprogramación, moneda, filtros, vacío y retorno de foco.
- **PASS:** `npm run test:run`, 3.091 tests en 216 archivos sobre el árbol local existente.
- **PASS:** `npm run lint`, sin errores; cuatro advertencias previas en `coverflow-carousel.tsx`.
- **PASS:** `npm run typecheck` y `npm run build`. Continúan avisos previos de chunks y `demo-config.ts`.
- **PASS:** Chrome, selección de depositantes, detalle, cierre y valores visibles. Sin desbordamiento a 390 px y 1.800 px CSS. Consola sin errores capturados durante la comprobación.
- Revisión independiente de Claude: **NOT RUN (revisión no completada)**. Se intentó con el wrapper del repositorio; el entorno restringido impidió iniciar el primer intento. El intento autorizado fuera del sandbox terminó sin resultado completo ni `VERDICT` válido (exit 1). No se considera review aprobado. Codex revisó directamente los cambios y ejecutó los checks anteriores.
- **NOT RUN:** `check:all`, matriz completa de dispositivos/lectores de pantalla y pruebas de datos reales. Es una ampliación del prototipo local; no hay integración de backend ni publicación.

Evidencia ficticia: [consulta de escritorio](consulta-escritorio.png), [detalle móvil](detalle-movil.png). El viewport temporal se restablece al concluir la revisión.

Implementación: `depositos.ts` contiene fixtures y lectura derivada; `inasistencias.tsx` agrupa seguimiento y detalle, extraídos de `resultados.tsx`. La guía **Cómo usar Citas** explica el indicador y su período.
