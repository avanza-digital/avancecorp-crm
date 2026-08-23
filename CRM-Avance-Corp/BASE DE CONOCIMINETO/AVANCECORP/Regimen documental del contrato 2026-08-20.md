# Régimen documental del contrato — 2026-08-20

Relacionado con [[PDF contractual privado e inmutable 2026-08-17]] y con el domicilio
legal (bloque 1, 19-ago).

## La regla de negocio

**El PDF que emite el sistema ES el contrato, pero solo para lo firmado del
2026-08-19 en adelante.** Un contrato firmado antes ya tiene el suyo en el formato
anterior: el sistema **no le emite ninguno**, aunque se cargue hoy. Decisión de Miguel
del 2026-08-20.

Corolario que ahorra trabajo: el domicilio legal **solo** se usa para ese documento
(verificado: ninguna otra función ni el portal lo leen). Por tanto **no hace falta la
campaña de llamadas** a los clientes sin domicilio — basta pedirlo cuando firman un
contrato nuevo, que es lo que ya hace la ventana del alta.

## Son DOS fechas, y la segunda no sobra

`contratos.fecha_inicio` es el inicio del **plazo**, no siempre el de la firma. Caso
real: `2026-01-000891` y `2026-01-000892` (REÁTEGUI PÉREZ PEDRO IVÁN, S/ 170.000 y
S/ 250.000) se cargaron el **1 de julio** con `fecha_inicio` = **2027-07-01**. Con la
fecha de plazo sola caerían en el régimen nuevo. El suelo `creado_en >= 2026-08-19`
(hora de Lima) lo impide sin contradecir la regla: lo registrado antes de la frontera
no pudo firmarse en ella o después.

Con las dos fechas, producción clasifica **5 contratos del régimen nuevo y 410 del
anterior** sobre 415.

## Lo que estaba pasando

El botón **«Ver contrato PDF»** del detalle no mostraba: **fabricaba**. Si el contrato
no tenía documento, lo creaba (front → edge `ensure` → `crm.contrato_pdf_reservar`).
Cualquiera que abriese un contrato antiguo acuñaba un contrato del formato nuevo,
fechado meses atrás y con el domicilio de hoy — el de notificaciones, cláusula 14.ª.
Así nacieron **21 documentos** para operaciones firmadas antes del 19-ago; la más
antigua, del 17 de febrero. **Decisión de Miguel: se quedan como están.**

Efecto colateral del mismo agujero: como el documento exige los nueve datos legales,
la **carga del histórico** —el grueso del trabajo real: 215 contratos en 30 días, solo
5 firmados del 19-ago en adelante— chocaba contra un muro que ese contrato no
necesita.

## Alcance decidido

- **El portal solo muestra.** Todos los contratos nuevos se hacen desde el CRM. No se
  toca `js/admin/*` aunque cree contratos sin documento.
- Los **21 ya emitidos**: intactos, sellados y descargables.
- Los **dos trabajos a medias** (`2026-01-000319` y `2026-01-000602`, RAMÍREZ CÁRDENAS
  TONNY, en espera desde el 19-ago con cero intentos) quedan **inertes e invisibles**
  sin borrar ni mutar la fila.

## Estado

Migración `20260820190500`, Edge y front **escritos y probados, SIN APLICAR** a
petición de Miguel (quiere revisarlo primero). Revisión publicada:
https://claude.ai/code/artifact/5a075e41-646e-4431-9253-fb46d24e92ff

Orden de despliegue obligatorio: **Edge → migración → front**. `parseEstado` de
`crm-contrato-pdf-v2` exigía `reintentable === true` para `sin_reserva`; con el orden
al revés, el detalle de todo contrato antiguo devolvería 502.
