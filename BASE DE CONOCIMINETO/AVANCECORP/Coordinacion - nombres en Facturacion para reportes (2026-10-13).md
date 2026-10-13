---
tags: [crm, coordinacion, permisos, facturacion]
fecha: 2026-10-13
estado: implementado y probado; validacion Auth y publicacion pendientes
---

# Coordinación — nombres en Facturación para reportes

Miguel confirmó «Mostrar nombres en Facturación, manteniendo solo lectura» para
que Rosa prepare reportes. Rosa es la cuenta activa del rol Coordinación. Se
amplía únicamente el nombre mostrado en el desglose de operaciones; no fichas,
IDs de clientes/contratos/leads/cierres, referencias, DNI, contactos ni escritura.
Complementa [[Coordinacion - Facturacion y Ranking en lectura (2026-10-12)]].

La RPC v2 mantiene `visible:false` y añade `nombre_visible:true`. La interfaz
muestra nombres sin enlaces ni acciones de ficha y usa «Cliente sin nombre» si
falta. La API v1 conserva su máscara para pestañas abiertas; los demás roles
delegan al helper v1 con idénticas cifras y filtros. La baja CRM o Portal corta
la consulta aun con el mismo JWT. Repartir sigue como inicio.

Matriz SQL local PASS (220 filas, tres meses/páginas, ambos tipos), reversa PASS,
gate frontend PASS (6.651 tests), 50 E2E Docker PASS y auditor RLS independiente
PASS. Validación Auth remota y publicación pendientes; este estado no implica
que Rosa ya vea los nombres en el sitio vivo.

La copia acotada de la consulta necesita revisión y matriz de paridad cada vez
que cambie `private.facturacion_lista`; la guarda de huella protege solo la
instalación. Fuente y procedimiento: `CRM-Avance-Corp/supabase/scripts/facturacion-nombres-coordinacion/LEEME.md`.

Relacionado: [[Facturacion - modulo del dueno en produccion (2026-09-13)]].
