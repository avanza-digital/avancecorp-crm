---
tags: [crm, coordinacion, permisos, facturacion]
fecha: 2026-10-13
estado: publicado y verificado; rama temporal eliminada
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

Publicado y verificado en `crm.miavance.com`: build `build-20261013T182849030Z`,
fuente limpia `4e31dbbf13efc8b462c7ceb217d18eb408c58203`, preservando la versión
viva anterior `767e04447c94`. Rosa ya recibe 71 operaciones con nombres en la
lectura de producción, sin campos privados y con totales/estructura intactos.
Portada, versión y JS/CSS verificados: 123 archivos iguales al manifiesto.

Matriz SQL local PASS (220 filas, tres meses/páginas, ambos tipos), reversa PASS,
gate frontend PASS (6.671 tests), 54 E2E Docker PASS y auditor RLS independiente
PASS. Auth remoto: 3.932 aserciones de matriz general y 392 de Facturación sobre
el backend vigente, cero fallos. Advisors de producción sin avisos nuevos.
La migración se fusionó desde la rama autorizada y quedó registrada como
`20261013171002`; SQL versionado `20261013154615`. Rama temporal eliminada y
credenciales retiradas. Acta: `supabase/scripts/facturacion-nombres-coordinacion/publicacion.json`.

La copia acotada de la consulta necesita revisión y matriz de paridad cada vez
que cambie `private.facturacion_lista`; la guarda de huella protege solo la
instalación. Fuente y procedimiento: `CRM-Avance-Corp/supabase/scripts/facturacion-nombres-coordinacion/LEEME.md`.

Relacionado: [[Facturacion - modulo del dueno en produccion (2026-09-13)]].
