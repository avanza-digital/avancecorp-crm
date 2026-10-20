# Gestión Diaria — pendientes de lo más reciente a lo más antiguo (2026-10-20)

**Decisión de Miguel (20/10/2026):** «el orden de los pendientes sale de lo más tiempo vencido hasta lo
que tiene menos tiempo vencido y quiero que sea al revés». Confirmó el plan completo: las dos listas.

## Qué cambia

- **Pendientes del supervisor / Gerencia** (ficha del analista, cuadros «Todas» y «Vencidas»): toda la
  lista va por `vence_en` **descendente**. En «Vencidas», lo que venció hace menos arriba y lo más viejo
  al final; en «Todas», lo de fecha más lejana arriba y lo vencido más viejo al final. «Ver más» sigue
  hacia atrás (más antiguo).
- **Cola del analista («Mi día»)**: dentro de **Vencidas**, **Sin primer intento** y **Sin conversación**
  va primero lo más reciente; **«Hoy»** sigue por hora (ahí nada está vencido). El orden ENTRE grupos no
  cambia (decisión #2 del 19/09/2026: Sin primer intento → Vencidas → Hoy → Sin conversación).

## Cómo quedó en el servidor (migración `20261020214445`)

- Núcleo nuevo `private.gestion_diaria_pendientes_core(…, p_recientes_primero boolean)`: el cuerpo de
  G4a con el sentido como parámetro (orden de la página y lado del cursor). El núcleo de 5 argumentos es
  un envoltorio con `false`.
- Puerta nueva `crm.gestion_diaria_pendientes_v3_fn` (= la v2 al revés, `version` 3). **La v2 sigue
  ascendente**: los bundles publicados antes del cambio validan orden ascendente con `v.strictObject` y
  no se tocan. El front nuevo llama a la v3.
- `crm.gestion_diaria_cola_trabajo_fn`: sólo cambia el `ORDER BY` de los pendientes.
- Gate H3 `private.assert_gestion_diaria_pendientes()` re-sellado. Ese gate ya estaba en rojo por una
  causa ajena (`crm.equipo_visible_fn`, tarea GUARDIANES-1610): la migración exige el MISMO veredicto
  antes y después, nunca lo usa como condición.

## Regla que deja

Cuando se invierte el orden de una lista paginada por cursor, se versiona la puerta (`v3`) y se deja
la anterior viva: el validador del front rechaza el payload entero si el orden no es el esperado, así
que front viejo + servidor nuevo (o al revés) rompería la pantalla.

Relacionado: [[Gestion Diaria - modulo nuevo y absorcion de Seguimiento 2026-09-19]] ·
[[Gestion Diaria - cola completa F6 preparada (2026-09-24)]] ·
[[Gestion Diaria - las llamadas a clientes cuentan (2026-10-19)]] · guardianes:
`AVISO-GUARDIANES-1610.md` en `supabase/scripts/pendientes-recientes-20261020/`.
