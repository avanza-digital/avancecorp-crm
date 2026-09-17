# Plan de cierre de saltos — se trabaja con el filtro «Foco» del mapa

Mapa: https://claude.ai/artifact/7rSe49eefhyVyuXgKZpg81 · Libreta: `decisiones.json` · Estado 17/09/2026: **137 pendientes** (A 56 · M 81), 33 aceptados.

## Cómo trabajamos cada paso

1. Miguel elige el paso y pone el **Foco** en el mapa (ve sus líneas rojas y sus objetos).
2. Claude entrega un **plan corto**: qué puerta nueva se crea o qué lógica pasa al núcleo, y qué cambia en el front.
3. Miguel aprueba.
4. Claude implementa (migración + front), corre las pruebas (`test:rls`, huellas, typecheck, build) y publica.
5. Se regenera el mapa: el Foco debe quedar sin rojo y **sin saltos nuevos**. Se anota la libreta. Vuelta a `main` el mismo día.

Un paso = un PR. Si un paso se complica, se parte en dos; no se mezclan pasos.

## Etapa 1 — Las pantallas dejan de leer tablas directo (35 saltos, 4 focos)

| # | Foco | Qué leen directo | Saltos | Qué se hace |
|---|---|---|---|---|
| 1 | Leads y cartera | `crm.leads`, `alertas_reconocimientos`, `recordatorios_disponibilidad` | 17 | 1–2 puertas de lectura/escritura; 16 pantallas y el store pasan por ellas |
| 2 | Agenda, tareas y reuniones | `crm.tareas`, `crm.actividades`, `crm.agenda_ics` | 12 | puertas de agenda; las pantallas dejan `from()` |
| 3 | Contratos y capital | `crm.operaciones_cartera` | 3 | una puerta |
| 4 | Clientes (perfiles) | `public.perfiles` | 3 | una puerta |

(El portal lee 10 tablas de `public`: es otro repo, va al final de todo.)

## Etapa 2 — Los 21 «al revés» (núcleo que llama a una puerta), 1 migración

| Foco | Conexiones | Qué se hace |
|---|---|---|
| Usuarios, equipo y permisos | 16 | `crm.bandera_activa` pasa a `private`; queda un wrapper |
| SLA y cola operativa | 11 | las puertas SLA que usan los `assert_*` pasan a `private` |
| Agenda / Tasa / Inversiones / resto | 1–8 c/u | igual, función por función |

## Etapa 3 — Las puertas dejan de hacer trabajo del núcleo (81 saltos), módulo por módulo

Orden por gravedad (A primero) y tamaño. Cada fila es un Foco y un PR.

| Orden | Foco | A | M | Conexiones |
|---|---|---|---|---|
| 1 | Leads y cartera | 2 | 5 | 50 |
| 2 | Clientes (perfiles) | 3 | 4 | 27 |
| 3 | Distribución y derivaciones | 3 | 4 | 32 |
| 4 | Conversión y cierres | 2 | 7 | 74 |
| 5 | Contratos y capital | 1 | 6 | 72 |
| 6 | Usuarios, equipo y permisos | 2 | 5 | 31 |
| 7 | Agenda, tareas y reuniones | 2 | 3 | 17 |
| 8 | Tasa y rentabilidad | 1 | 5 | 33 |
| 9 | Notificaciones del portal | 3 | 0 | 8 |
| 10 | Métricas y reportes | 0 | 6 | 12 |
| 11 | Postventa | 0 | 5 | 19 |
| 12 | SLA y cola operativa | 0 | 4 | 12 |
| 13 | Metas y productos · Citas | 0 | 3 | 5 |
| último | Inversiones e identidad | 0 | 6 | 118 — espera a que termine multiempresa F4–F8 |

## Avance

- [x] Paso 0 · B y D aceptados en la libreta (17/09)
- [ ] Etapa 1 · 1 Leads · 2 Agenda · 3 Contratos · 4 Clientes
- [ ] Etapa 2 · inversiones
- [ ] Etapa 3 · módulo por módulo
