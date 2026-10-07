---
tags: [crm, inversiones, continuidad, decisiones]
estado: correccion-preparada
---

# Nueva inversión por empresa y upgrade vigente

Miguel confirmó el 07/10/2026 la corrección de la regla de la ficha:

> Si tiene una inversión vigente en Qorilazo y nunca invirtió en Avance ni
> Prodelco, «Nueva inversión» permite únicamente Avance y Prodelco, y «Upgrade»
> únicamente la inversión vigente de Qorilazo. «Sí, esa es la regla».

Esta decisión **sustituye el bloqueo por todo el grupo de #206**. La primera
inversión se evalúa **por empresa**, sin confundirla con un aporte adicional a
una inversión existente.

- Sin historial en una empresa: puede registrar su primera inversión allí.
- Con historial en una empresa: debe usar la continuidad correspondiente a esa
  inversión. Un saldo activo de cero no convierte al cliente en nuevo.
- Upgrade: requiere origen activo/vigente y se registra separado de la
  reinversión. Un origen vencido no habilita upgrade.
- Historial en las tres empresas: «Nueva inversión» queda deshabilitado, con
  explicación. Los permisos operativos siguen siendo obligatorios.

La corrección usa `inversionista_ficha_fn.totales`, que abarca todas las páginas
y monedas, y `cantidad`, no el importe activo. Si las cantidades no concuerdan
con `inversiones_total`, solicita actualizar y no ofrece empresas como nuevas.
Conserva la semántica actual del servidor: `cartera_f5_fuentes_reales()` excluye
las fuentes demo, pero conserva las anuladas/vencidas. Las sesiones demo usan
la pantalla anterior de Avance.

El selector se actualiza al refrescar la ficha y vuelve a consultar antes de
preparar una solicitud nueva. Una solicitud ya enviada conserva su UUID, tipo y
recuperación, incluso si una confirmación llegó al servidor y su respuesta se
perdió.

## Alcance de esta corrección

Ficha multiempresa de la cartera propia y su formulario de nueva inversión.
No modifica SQL ni escritores financieros. No constituye un bloqueo atómico
del servidor ante dos altas simultáneas.

Los contextos de conversión de lead y venta cruzada todavía no devuelven el
historial por empresa. Mantienen su comportamiento anterior; extender la regla
a esas rutas requiere el trabajo de servidor descrito en
[[Plan por fases - inversion por empresa y ranking de cartera (2026-09-26)]].
La ficha antigua de Avance es otro componente y no alimenta este cálculo.

La evidencia y el estado de entrega se registran en
`CRM-Avance-Corp/docs/encargos/2026-10-07-inversion-por-empresa.md`.

Relacionadas: [[Upgrade cooperativo separado de reinversion (2026-10-06)]] ·
[[Upgrade es un contrato aparte, no una modificacion (2026-09-21)]].
