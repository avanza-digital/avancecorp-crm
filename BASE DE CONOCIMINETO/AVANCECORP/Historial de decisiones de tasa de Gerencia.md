# Historial de decisiones de tasa de Gerencia

Relacionado con [[Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06]] y [[Deploy a Hostinger]].

## Decisión de producto

El historial de tasas aprobadas vive dentro de **Configuración > Política de rentabilidad**. No es un módulo nuevo del menú.

La sección **Historial de rentabilidad** mantiene dos vistas separadas: **Cambios de política** y **Decisiones de tasa**. Las solicitudes pendientes continúan en **Hoy** para conservar la prioridad operativa.

## Trazabilidad mostrada

Cada decisión conserva cliente, analista solicitante, operación, capital, moneda, plazo, modalidad, tipo de interés, contrato origen, tasa base, tasa solicitada, tasa autorizada, versión de política, motivos, responsable, fecha y resultado posterior.

## Escala y permisos

`crm.historial_decisiones_tasa_gerencia_fn` exige rol CRM `gerencia` y devuelve únicamente decisiones cuyo `resuelta_por` es el usuario autenticado. La consulta usa paginación por cursor `resuelta_en + id`, diez filas por página en la interfaz y un máximo de veinticinco impuesto por el servidor. No existe scroll infinito ni acumulación ilimitada de filas en el DOM.

Estado: implementado en código local; migración y publicación pendientes.
