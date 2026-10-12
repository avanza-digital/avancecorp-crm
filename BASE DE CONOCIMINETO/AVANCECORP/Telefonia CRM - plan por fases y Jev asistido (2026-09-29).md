---
tags: [crm, gestion-diaria, telefonia, plan, typesafe]
actualizado: 2026-09-29
estado: plan-documentado-implementacion-pendiente
---

# Telefonía CRM: plan por fases y Jev asistido

Relacionado: [[Inicio]] · [[Gestion Diaria F2 - resultado tipificado de llamada (2026-09-20)]] · [[Gestion Diaria F4.1 - TypeSafe tecnico y piloto humano pendiente (2026-09-21)]] · [[Gestion Diaria - F4.1 apagada y F5 en desarrollo (2026-09-24)]].

El usuario pidió consolidar las mejoras de la revisión del plan de llamadas y llevarlo por fases a Figma. Precisó que quiere usar Jev para ayudar a relacionar el número marcado con los contactos del CRM. Esta nota documenta una propuesta, no una integración activada.

- [Plan principal, versión 3 con checklist](<../../CRM-Avance-Corp/GESTION DIARIA/AUTOMATIZACION DE LLAMADAS/Plan — Llamadas desde el celular al CRM.md>).
- [Tablero FigJam editable](https://www.figma.com/board/39XA8pQGdbXrg8r2UiPhpY?node-id=1-2), creado en El equipo de Avance Corp.
- El borrador previo se conservó en `historial/`, junto al plan. La revisión previa mantiene referencias a ese borrador.

## Secuencia propuesta

F0 piloto y línea base → F1 formulario único y match exacto / F2 núcleo confiable → F3 captura y sincronización → F4 pendientes y conciliación → F6 gerencia → F7 despliegue. F5 es Jev asistido, evaluable tras F4 y en paralelo con F6; puede quedar OFF sin bloquear el resto. Los IDs F0–F7 de esta nota pertenecen al plan de telefonía, no sustituyen las fases históricas del módulo Gestión Diaria.

## Criterios duraderos

- E.164 completo, canonización compatible cliente/servidor y candidatos completos dentro del ámbito. No usar últimos nueve dígitos como identidad internacional.
- Jev recibe candidatos ya recuperados y contexto pertinente; propone o se abstiene. Código compara dígitos; persona confirma la ambigüedad. No corregir números por parecido ni crear identidad por generación.
- Comparar reglas exactas, reglas con historial y Jev en banco reservado. El piloto F4.1 de contradicción nota/resultado no mide identificación telefónica.
- Evento técnico separado de actividad comercial; UUID de origen estable y cola durable. Enlace uno a uno con autor/lead válidos; una ventana temporal solo sugiere.
- Conservar núcleo sellado v4 y semántica de Deshacer. Preferir composición transaccional con enlace; alternativa de dos operaciones exige reconciliación durable.
- Entrante perdida implica devolver llamada, no declarar que el lead no contestó. Gerencia distingue cobertura, retrasos y pendientes; cero eventos no acredita cero trabajo.
- Revisar retención de todos los estados, baja de credenciales y reasignación histórica. Apagado operativo preserva evidencia.

## Estado de la entrega

MD versión 3 y tablero actualizados a pedido del usuario: ocho fases, 33 subfases y 102 tareas con IDs idénticos, casillas, responsable, evidencia y fecha por subfase. Todas pendientes. Marcas y contadores se editan manualmente, sin sincronización automática. Versión 2 conservada en historial. Paridad de textos/IDs y revisión visual PASS; sin desbordes ni solapamientos de texto. No se modificó código de producto, SQL ni configuración; no se desplegó ni se llamó a Jev con datos de leads. Android, nuevas pruebas SQL/E2E y evaluación de identificación corresponden a futuras fases. El plan se encuentra en una carpeta ignorada por Git: no asumir que su entrega local lo versiona.
