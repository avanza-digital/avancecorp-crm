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
- Agrupa por fecha de Lima, analista, supervisor y origen histórico.
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

El JSON no expone PII de prospectos ni filas de leads: no contiene teléfonos,
correos, DNI, notas ni capital. Sí incluye nombres/identificadores de
colaboradores, fechas, orígenes y conteos, restringidos a
Coordinación/Gerencia. La interfaz valida
además que las fechas, el desglose por origen y los totales diarios reconcilien
con el período pedido antes de mostrar la información.

## Diseño operativo para la coordinadora

La pestaña muestra primero el parte **Entregas por fecha, analista y origen**.
Permite combinar filtros de supervisor, analista y origen; al elegir supervisor,
el selector de analistas enseña únicamente su equipo. Cuatro indicadores
resumen el resultado filtrado: leads entregados, analistas, orígenes y días con
entregas. **Restablecer** vuelve a Ayer y limpia todos los filtros.

La **Cartera activa actual** queda en un bloque separado debajo. Esa separación
es deliberada: el primer bloque responde «qué entregó Coordinación en una
fecha» usando el ledger; el segundo responde «dónde siguen los leads hoy» y
puede cambiar con reasignaciones posteriores.

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

### Extensión por origen — publicada el 2026-09-04

La migración
`20260904174534_crm_reporte_derivaciones_origen_coordinacion` está aplicada y
registrada en producción; conserva `dias[].analistas` por compatibilidad y
añade `dias[].entregas` por origen. El registro guarda el cuerpo literal con
MD5 `b2fa0249f50f64e4db72a08cd1b8968e`. Antes de aplicarla se ensayaron en
`banco-f7` la migración, el oráculo transaccional y la reversa exacta; todos
terminaron en verde. En producción se verificaron con una identidad autorizada
el contrato aditivo, la conciliación diaria y total, la ausencia de PII de
leads, las ACL y el índice. El único aviso relacionado de seguridad es el uso
intencional de `SECURITY DEFINER` por `authenticated`, protegido dentro de la
RPC por la puerta de Coordinación/Gerencia; el índice aparece como no usado
antes de recibir tráfico, como corresponde. El respaldo privado previo es
`releases/rollback-20260904174534-predeploy.sql` (SHA-256
`0424d4b7f73e5d462606d3e40df8611064157f44b52718426d5a02147afe4750`).

La interfaz está publicada desde el commit `d75be7b5d8d3`: release
`crm-20260904T194458Z-d75be7b5d8d3`, build
`build-20260904T194456335Z`, ZIP SHA-256
`91dd6ee84d4225f74c948192aed50d800c66d7eb57c68066cd18e6e37b40d79a`.
El gate final quedó en 2.648/2.648 pruebas y Repartir 29/29 en Playwright. En
vivo se verificaron 76/76 archivos (63 exactos, 12 imágenes disponibles y
`.htaccess` protegido), versión estable, ZIP 404 en CRM y portal, y login sin
errores de consola/página/red. Después de purgar la caché, el entry anterior
quedó en 404. Rollback frontend inmediato:
`releases/crm-20260904T194617Z-41a24d3bb98a.zip`.

Relacionado con [[Acceso y roles del CRM]] y
[[Distribución de leads por capital y trazabilidad CRM]].
