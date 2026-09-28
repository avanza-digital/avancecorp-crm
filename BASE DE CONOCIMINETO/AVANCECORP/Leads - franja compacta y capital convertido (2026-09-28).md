---
tags: [crm, leads, cartera, ux, capital]
fecha: 2026-09-28
estado: implementado y verificado (check, E2E, gate de realidad); PUBLICADO 28/09 (build-20260928T174316188Z, commit 5f3656c0 en main local); falta PR de integración a GitHub
---

# Leads — franja compacta y «Capital convertido»

Pedido de Miguel (28/09): la pantalla **Leads** (`#/cartera`, `screens/cartera.tsx`)
tenía mucho espacio vacío, y al filtrar sus convertidos quería ver cuánto suman.

## Decisiones

- **«Capital convertido», NO «Capital confirmado».** En el CRM «confirmado» es el
  capital de CONTRATOS del mes, neto de anulaciones (Hoy del analista, Gerencia).
  Esta cifra es el **monto estimado** de los leads convertidos
  (`resumen.capital.ganado` de `crm.cartera_pagina_fn`, ya existía). Si algún día se
  quiere el monto real del contrato, es una fase 2 con servidor (plan + migración).
- La tarjeta de capital cambia con el filtro de etapa:
  - «Convertido» → **Capital convertido** + «Monto estimado de N convertidos».
  - «Descartado» → «Los descartados no suman capital».
  - Resto → **Capital en juego** como siempre + línea «Convertido: …» (cada moneda aparte).
- PEN y USD jamás se suman (regla de siempre). Sin payload → «—».
- **Todo número se abre:** «Total leads» (limpia solo la etapa), «Convertidos», la
  línea «Convertido: …» y las pastillas de etapa filtran la tabla. «Activos» y el
  capital en juego NO se abren: no existe filtro «abiertos» en el servidor (pendiente).
- Espacio: sin tope `max-w-[1240px]`, indicadores + distribución en una sola franja,
  filtros y contador en una fila, columna Lead al 30 % desde `lg`. En escritorio la
  tabla sube de ~457–477 px a ~292–370 px; a 1920 px el contenido pasa de 1240 a 1632 px.
- `StatStrip`/`SegmentBar` NO se tocaron (los usan 9 pantallas más).

## Lecciones

- Cada mini-KPI sigue siendo una `Card` (`data-slot="card"`): los E2E la localizan así.
- Los E2E buscan la tarjeta «Convertidos» con `hasText` (sin distinguir mayúsculas):
  **cualquier texto con «convertidos» en la tarjeta de capital, aunque sea sr-only,
  rompe `gerencia-operativa.spec`.** Hay un test unitario espejo que lo caza.
- En sesión real, cambiar la etapa es una consulta nueva y el resumen llega tarde:
  los controles no pueden desmontarse ni pasar a `disabled` con el foco dentro
  (se usa `aria-disabled` y se conservan las últimas pastillas, sin cifra).

## Estado en producción (lectura 28/09)

133 convertidos dentro de la ventana de 45 días (114 PEN, 19 USD), todos con monto:
el caso de monedas mezcladas es el normal.

## Gate de realidad (corrido por Miguel, 28/09)

6/9 supuestos OK (entre ellos los de Leads: 2.509 leads activos, 17.062 actividades).
Diverge 1 ajeno a Leads: 288 clientes activos sin domicilio legal («+ Contrato», convertir,
PDF viejo). Sin medir 2, también ajenos: `permission denied for table periodos_cerrados`
(metas bajo el último mes sellado) y `statement timeout` en la conversión por los cuatro
caminos: el gate hoy NO vigila esos dos supuestos.

## Pendientes

- Filtro «Activos» (necesita servidor).
- Capital real de contrato como «Capital confirmado» (fase 2).
- Los convertidos con cierre anulado siguen sumando en `ganado` (así lo calcula el servidor).

Relacionadas: [[Leads - filtro de origen (2026-09-16)]] · [[Leads filtro integrado - vista local 2026-09-13]]
