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

En producción desde el 2026-09-04. La migración
`20260904153431_reporte_diario_derivaciones_coordinacion` quedó aplicada y
registrada con su cuerpo completo. Una sonda transaccional usando identidades
reales permitió Coordinación y Gerencia, denegó Supervisión con `42501` y
confirmó que el JSON no contiene claves de PII. Los advisors de seguridad y
rendimiento terminaron sin errores.

Frontend publicado desde el commit `dc6c83e5aa37`: release
`crm-20260904T161303Z-dc6c83e5aa37`, build
`build-20260904T161302294Z`. Las 76 entradas del paquete quedaron verificadas
en vivo (61 al byte, 14 imágenes HTTP 200 y `.htaccess` 403); el ZIP devuelve
404 tanto en CRM como en el portal. El respaldo privado previo del esquema es
`releases/reporte-derivaciones-predeploy-20260904.sql` (SHA-256
`dd86370aa674f056bc33f046ea5e93a57aeb75939b148c05ce3711588b4d109c`).
No había un navegador conectado para el smoke visual autenticado; la interfaz
sí quedó cubierta por 2.644 pruebas y por la identidad del bundle publicado.

Relacionado con [[Acceso y roles del CRM]] y
[[Distribución de leads por capital y trazabilidad CRM]].
