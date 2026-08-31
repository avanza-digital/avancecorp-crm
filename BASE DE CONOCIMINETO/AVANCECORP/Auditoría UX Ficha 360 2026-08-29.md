---
tags: [crm, cartera, ficha-360, ux, accesibilidad, auditoria]
actualizado: 2026-08-29
estado: auditada-go-con-pulido
---

# Auditoría UX Ficha 360 — 2026-08-29

Relacionado: [[Ficha comercial 360 de clientes - plan]], [[Ficha 360 R2 - aceptacion UX comercial 2026-08-27]], [[Fundamentos UX del CRM]], [[Terminología comercial del CRM]] y [[Detalle de contratos para analistas]].

## Veredicto

La Ficha 360 está **bien estructurada y es utilizable por el Analista**. La jerarquía principal cumple el objetivo comercial: presenta primero capital vigente, próximo vencimiento y siguiente contacto; después inversiones, identidad, historial y cuentas autorizadas. No se encontró un defecto visual bloqueante.

No se considera todavía una UX completamente idónea. La pasada del 29/08 dejó seis mejoras, ordenadas por impacto:

1. Uniformar las acciones visibles de Mi cartera: «Upgrade» debe ser «Aumentar inversión» y «+ Contrato» debe ser «Registrar nueva inversión».
2. Evitar que correo, número de cuenta y CCI se corten entre líneas; añadir una acción clara para copiar identificadores financieros.
3. Reducir la repetición inmediata de «Siguiente contacto» entre el riel de continuidad y la sección operativa.
4. Contraer por defecto las cuentas bancarias con un resumen por moneda para acortar la ficha sin ocultar su existencia.
5. Subir a 11–12 px los textos auxiliares que hoy llegan a 9–10 px.
6. En el detalle de contrato, resumir arriba cuotas vencidas, próxima cuota y saldo antes del cronograma completo.

## Fortalezas confirmadas

- «Analista» aparece como denominación visible en la ficha.
- La acción principal «Agendar seguimiento» permanece fija y clara.
- En móvil, el panel ocupa la pantalla completa y no mostró desborde horizontal.
- Los controles visibles miden 40 px; el pie usa 44 px, en línea con el mínimo de [[Fundamentos UX del CRM]].
- Hay diálogo rotulado, regiones con nombre, encabezados y etiquetas accesibles.
- Los estados de carga, error, reintento, acceso revocado y cambio de asignación existen en el componente publicado.
- La pasada focal sobre el candidato desplegado aprobó 122 pruebas de `cliente-ficha` y `mi-cartera`.

## Evidencia y límite

Las capturas están en `artifacts/audits/ficha360-ux-20260829-current/`.

Producción estaba en la pantalla de acceso durante esta auditoría. La evidencia visual se capturó con datos demo en la preview local. El componente central de la Ficha 360 y sus piezas compartidas resultaron byte-idénticos al origen del release publicado. El envoltorio demo y el subdiálogo de contrato no son idénticos en todos sus detalles, por lo que quedan pendientes la comprobación autenticada de roles, teclado/lector de pantalla y el bloque nuevo «Analista de la venta».
