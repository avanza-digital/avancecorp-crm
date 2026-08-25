---
tags: [crm, cartera, postventa, renovacion, upgrade, conversion]
actualizado: 2026-08-24
estado: implementado-en-base-y-frontend
---

# Gestión comercial de clientes — renovaciones y upgrades

Decisión cerrada con Miguel el **2026-08-24**: **Mi cartera** deja de ser una
lista de consulta y pasa a ser el lugar desde el que el asesor continúa la
relación comercial con sus clientes.

## Acciones disponibles

Desde cada cliente se puede:

- agendar llamada, WhatsApp, reunión u otra tarea;
- registrar un upgrade;
- crear un contrato nuevo;
- abrir detalle, corregir dentro de las autorizaciones existentes y consultar
  el historial comercial;
- renovar desde el contrato que llegó a su fecha fin.

Las gestiones de cliente viven en la misma agenda operativa que las de leads y
aparecen en **Hoy** y **Agenda**. Su resultado se guarda en un historial de
postventa propio. No modifica etapa, SLA ni timeline de leads.

## Renovación

Una renovación:

1. solo se habilita cuando el contrato llega a su fecha fin;
2. crea **otro contrato**;
3. enlaza y cierra el anterior dentro de la misma transacción;
4. traslada sus cuotas pendientes;
5. registra el puente económico:
   **capital anterior → capital renovado + capital adicional = contrato nuevo**.

El **capital adicional** es dinero nuevo y se conserva separado porque se paga
de otra manera. No crea una conversión adicional. El desglose se muestra en la
misma cartera para asesor, supervisor y Gerencia, siempre separado por PEN/USD.

## Conversión

- Renovación: suma **1 conversión** y **0 al divisor**.
- Upgrade: suma 1 conversión solo si ocurre en un mes posterior al mes del
  primer contrato del cliente.
- Un cliente suma como máximo **una conversión por mes**, aunque renueve dos
  contratos o combine renovación + upgrade.
- La conversión se acredita al asesor dueño de la cartera en el instante de la
  operación.
- El divisor conserva como única fuente los leads no referidos recibidos; ni el
  capital renovado ni el adicional lo alteran.

## Histórico de agosto de 2026

Se reconstruyeron 48 operaciones: 9 renovaciones y 39 upgrades, correspondientes
a 29 clientes elegibles. Los nueve desgloses históricos de renovación no podían
deducirse con certeza: se muestran como **desglose pendiente** y no se inventa
capital adicional.

## Implementación y prueba

- Migraciones: `20260824231133` y compatibilidad `20260824233619`.
- Ledger inmutable: `crm.operaciones_cartera`.
- Historial postventa: `crm.actividades_cliente`.
- Gate SQL transaccional: `GESTION_CLIENTES_RENOVACIONES_OK`.
- La tarea de cliente mantiene `perfil_id` al crear la siguiente acción y al
  reasignarse la cartera viaja al nuevo asesor.

## Relacionado

- [[Mi cartera por meses]]
- [[Categorización de inversiones - Nuevo Renovación Upgrade]]
- [[Conversion mensual - definicion cerrada]]
- [[Periodo comercial de contratos]]
- [[Agenda comercial del CRM (plan v2)]]
- [[Ciclo de vida de contratos]]
