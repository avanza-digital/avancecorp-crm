# Upgrade es un contrato aparte, no una modificación

**Fecha:** 2026-09-21 · **Origen:** confusión reportada por Miguel desde los analistas.

## El malentendido

Los analistas leían «Registrar nueva inversión» / «Aumentar inversión» sobre un cliente que
YA tiene contrato y entendían que iban a **modificar el contrato vigente**. No es eso.

## Lo que hace el upgrade de verdad

El upgrade **crea un contrato NUEVO**. Solo *declara* cuál contrato activo amplía, y de él
**hereda la tasa** (base de rentabilidad) y la cadena de atribución. El contrato declarado
**no se toca**: sigue activo, con su capital y su cronograma.

Evidencia en el núcleo: `supabase/migrations/20260918210543_crm_modo_rentabilidad_integral.sql`
— `v_origen_dec` (origen DECLARADO por la puerta, D2) en la línea 329; regla `heredada_upgrade`
en 570; y el candado de la línea 661: «El upgrade solo amplía un contrato **activo**».
Si el upgrade no declara origen, el núcleo lo rechaza (`upgrade_origen_inferido` /
`upgrade_origen_ambiguo`).

## Cómo quedó la pantalla (21/09)

- El rótulo «Aumentar inversión» se renombró a **«Registrar upgrade»**, y la frase única vive en
  `app/src/lib/contratos-catalogo.ts` (`ETIQUETA_UPGRADE`, `AYUDA_UPGRADE`):
  *«El upgrade abre un contrato NUEVO que hereda la tasa del contrato que amplía. El contrato
  actual no cambia.»*
- El botón va **al costado** de «Registrar nueva inversión», en horizontal, en las tres pantallas:
  fila y tarjeta de Mi cartera, ficha del cliente y **ficha del inversionista** (esta última era
  la que solo tenía «Registrar nueva inversión» arriba y escondía el upgrade dentro de cada
  tarjeta de inversión).
- En la ficha del inversionista, si hay varios contratos activos, el botón pregunta primero
  **cuál se amplía**; con uno solo entra directo.

Relacionado: [[Atribución por cadena de upgrade]], [[Fundamentos UX del CRM]].
