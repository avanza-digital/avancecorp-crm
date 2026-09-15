---
tags: [feature, negocio, contratos, backend]
actualizado: 2026-07-14
---

# Cuentas mancomunadas (co-titulares)

**Qué es (2026-07-14):** un contrato puede registrar **co-titulares** — personas
adicionales que figuran como titulares de la inversión, además del cliente
principal. Pedido por Miguel.

## La decisión de negocio (definida por Miguel)

Ante dos lecturas posibles de "mancomunada", Miguel eligió (vía pregunta directa):

1. **Co-titulares como DATO, aditivo, SIN segundo login.** El titular principal
   sigue siendo el mismo cliente que entra al portal (`contratos.cliente_id`); los
   co-titulares son información que figura en el contrato, no cuentas con acceso
   propio. *(La otra opción —que cada co-titular entre con su clave y ambos vean la
   MISMA inversión— quedó para una fase 2: exige reescribir la RLS de las tablas más
   sensibles. Ver la nota técnica en el changelog.)*
2. **Los agregan el admin Y el analista** al crear/editar un contrato.
3. **Solo nombre + documento** (DNI/CE/Pasaporte). Sin "relación/parentesco"
   (cónyuge/hijo/socio) — diferido; si hace falta se agrega, es aditivo.

## Quién ve qué

- **Admin / analista:** agregan/editan co-titulares en el modal de contrato; los ven
  en el detalle. El analista solo sobre su **cartera** (lo garantiza la RLS).
- **Cliente:** ve a sus co-titulares en **solo lectura** en "Mi inversión", debajo de
  la ficha del contrato. Nunca puede editarlos (el portal del cliente es solo lectura).
- Un cliente **jamás** ve co-titulares de un contrato ajeno (verificado: contrato
  ajeno → 0 filas, fail-closed).

## Reglas que hay que respetar al tocar esto

- El **titular principal NO se toca**: sigue siendo `contratos.cliente_id`. Los
  co-titulares son una tabla hija (`contrato_titulares`), aditiva.
- **Documento por tipo**: reusa las MISMAS reglas DNI/CE/Pasaporte del sistema
  ([[Tipo de documento]] si existe la nota; núcleo `documento-core.js`). No inventar
  regex nuevas.
- **Escritura solo por las RPC** de contrato (`crear_contrato`/`actualizar_contrato`):
  no hay forma de escribir la tabla por la API directa (RLS sin INSERT/UPDATE/DELETE).
- Al **editar**: si el formulario no manda co-titulares se **conservan**; si manda la
  lista (incluso vacía) se **reemplaza**. Por eso el editor **precarga los actuales
  ANTES** de abrir el modal (si no, un guardado ultrarrápido con el editor vacío los
  borraría).

## En el contrato PDF (cambio del 14/09/2026)

Hasta la plantilla v8 el PDF imprimía y hacía firmar **solo al titular principal**; los
co-titulares viajaban en el snapshot pero no salían («por decisión legal»). **Miguel lo cambia
el 14/09/2026**: desde la plantilla v9 el contrato nombra a los co-titulares en la comparecencia
(actúan de manera conjunta como EL ASOCIADO) y cada uno firma al final, rotulado EL ASOCIADO.
Solo nombre y documento; solo contratos nuevos (los PDF sellados no cambian). Detalle y estado en
[[Plantilla v9 del PDF - cotitulares en el contrato (2026-09-14)]].

## Estado

- **Completo en producción** (2026-07-14): BD (migración
  `contrato_titulares_cuentas_mancomunadas`, verificada con transacciones revertidas
  + advisors sin hallazgos nuevos) **y frontend DESPLEGADO** a Hostinger (admin,
  analista, cliente; verificado en prod, conciliación intacta).
- Falta solo la **prueba visual de Miguel**.
- Detalle técnico canónico → `public_html/CLAUDE.md`, changelog **2026-07-14 (d)**.

## Notas relacionadas
[[Ciclo de vida de contratos]] · [[Detalle de contratos para analistas]] · [[Arquitectura del portal]] · [[Inicio]]
