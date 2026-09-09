---
tags: [crm, servidor, arquitectura, figma, mapa, supabase]
actualizado: 2026-09-06
estado: mapa-documentado-con-lectura-de-produccion
---

# Mapa del servidor CRM en Figma - 2026-09-06

Miguel pidió analizar el servidor real del CRM y crear un diagrama en una carpeta separada de Figma llamada **SERVIDOR CRM**, con leyendas y explicación comercial de las funciones para una persona que no es experta en backend.

## Entrega

- [Carpeta SERVIDOR CRM en Figma](https://www.figma.com/files/team/1673045681873340799/folder/650628787).
- [Tablero completo](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df).
- [Portada y guía](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=10-347).
- [Vista general](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=1-2), [recorrido comercial](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=8-349), [calculadoras compartidas](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=8-352), [versiones y caminos](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=8-355).
- [Glosario de 24 capacidades](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=18-347) y [ocho puntos para revisar](https://www.figma.com/board/f5AcRzzIk3KS6CCOmKC0df?node-id=19-347).
- Guía y evidencias locales: `SERVIDOR-CRM/README.md`, en la raíz del repositorio. La carpeta contiene inventario, cuerpos y verificaciones del servidor, análisis Edge, relación con pantallas y contexto comercial.

## Hechos comprobados en esta revisión

Se leyó el proyecto Supabase `dctqcbznekcyxhjujuci` el 06/09/2026 Lima (07/09 UTC), sin ejecutar operaciones comerciales ni modificar servidor.

- Inventario del área revisada: **88 tablas, 3 vistas, 476 funciones de base de datos, 16 Edge Functions, 9 cron activos y 3 buckets**. Las funciones incluyen auxiliares, disparadores y firmas distintas; no son 476 capacidades comerciales.
- Las 16 Edge figuran `ACTIVE`, pero `diagnostico-push` devuelve siempre 410: desplegado no equivale a operando.
- `resolver_en_puertas`, `inversiones_escritura` y `ficha_360_neutral` están en **false**. La estructura de identidad unificada existe; sus caminos de activación permanecen apagados. No describir la identidad como inexistente ni como ruta universal encendida.
- Política de rentabilidad: **versión 1, observación**. El nuevo `private.sla_operacion_leads` propuesto no apareció en el catálogo vivo.
- Distribución usa en el código actual la puerta `crm.metricas_distribucion_leads_v3_fn`. Las puertas V1/V2 no tienen ejecución para `authenticated`/`anon`; los motores internos base/V2 todavía son utilizados por V3.
- Conversiones y Reuniones combinan las calculadoras de conversión, capital y citas. El control de acceso es transversal; no todas las rutas pasan por `private.capital_autorizada`.
- Conversión del lead, registro del contrato y estado del PDF son resultados separados. `crm-contrato-pdf-v2` prepara/verifica el documento y entrega enlaces temporales; PDF pendiente no significa contrato inexistente.
- Comunicados llama a `enviar-push`; pagos y vencimientos mantienen sus envíos push propios. Es un punto de mantenimiento visible, sin concluir por ello que exista un fallo.

## Criterio para mantener el mapa

Las bifurcaciones por empresa, pregunta comercial, permisos o estado pueden ser deliberadas. El mapa separa **vigente**, **instalado pero apagado** y **propuesto**. Las notas históricas explican decisiones; las afirmaciones sobre qué está activo deben volver a contrastarse con Supabase cuando cambie el servidor.

No se midió tráfico ni entrega final de correo/push. Los cuerpos muestran conexiones y decisiones posibles, no frecuencia de uso ni éxito de todas las ejecuciones. El alcance es arquitectura y explicación comercial, no auditoría completa de seguridad. No se guardaron fuentes Edge descargadas ni datos personales en el informe de Edge.

## Relacionadas

[[Arquitectura del portal]] · [[PLAN MAESTRO del servidor (P-055) - de la deuda a la capa semantica]] · [[Capa semantica del servidor - plan por nucleos (episodios)]] · [[Capacidad única de conversión de leads (2026-09-03)]] · [[Contrato arquitectonico consolidado - identidad unificada de inversionistas (F0 2026-08-31)]] · [[Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06]] · [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]] · [[Ciclo de vida de contratos]] · [[Notificaciones de pagos]]
