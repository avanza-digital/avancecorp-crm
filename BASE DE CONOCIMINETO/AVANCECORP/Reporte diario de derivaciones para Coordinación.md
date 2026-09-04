---
tags: [crm, coordinacion, derivaciones, reportes]
actualizado: 2026-09-04
---

# Reporte diario de derivaciones para Coordinación

## Decisión de negocio

Coordinación necesita rendir cuántos leads entregó Supervisión a cada analista,
día por día. El reporte vive en la pestaña **Distribución** de `#/repartir`, que
es la pantalla habitual de la coordinadora.

El período se elige con los mismos atajos del reporte de Supervisión:
**Ayer**, **Últimos 7 días** o un **Rango** manual inclusivo. El rango máximo es
de 366 días, no admite fechas futuras y se interpreta siempre en
`America/Lima`; esto conserva la decisión de [[Bug de fechas UTC]].

## Qué cuenta

- Cuenta aperturas del ledger `crm.lead_asignaciones` con motivo `asignado` o
  `reasignado`, hechas por el mismo supervisor que entregó el lead.
- Agrupa por fecha de Lima, analista y supervisor.
- Una devolución previa a la gestión, que regresa el lead a la misma bandeja
  del supervisor, deja de sumar. Es la misma regla de
  [[Derivar leads del supervisor - paginacion compacta]].
- La salida conserva los días sin movimiento con total cero.
- El historial no desaparece si después el analista o supervisor sale del
  roster: la cantidad sale del ledger, no de la tenencia actual.

## Seguridad y contrato

La RPC `crm.reporte_derivaciones_coordinacion_fn(date,date)` reutiliza la puerta
canónica del reparto: permite a Coordinación o Gerencia activas. Usa
`SECURITY DEFINER` con `search_path` vacío, `EXECUTE` solo para `authenticated`
y una validación interna del rol. Un supervisor o analista autenticado recibe
`42501`.

El JSON no expone filas de leads, teléfonos, correos, DNI, notas ni capital:
solo fechas, nombres/identificadores de responsables y conteos. La interfaz
valida además que las fechas y los totales diarios reconcilien con el período
pedido antes de mostrar la información.

## Estado

Implementado y probado localmente el 2026-09-04. La migración y el frontend
quedan pendientes de publicación; no se aplicó ningún cambio a producción.

Relacionado con [[Acceso y roles del CRM]] y
[[Distribución de leads por capital y trazabilidad CRM]].
