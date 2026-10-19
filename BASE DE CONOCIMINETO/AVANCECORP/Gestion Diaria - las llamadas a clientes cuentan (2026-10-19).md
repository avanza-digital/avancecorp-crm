---
tags: [crm, gestion-diaria, postventa, clientes, llamadas, servidor]
fecha: 2026-10-19
estado: ENSAYADA, REVISADA Y EN PR · SIN APLICAR · la aplica Miguel con «!» y luego /release-crm
---

# Gestión Diaria — las llamadas a clientes cuentan (2026-10-19)

## Qué pasaba
El marcador de [[Gestion Diaria - modulo nuevo y absorcion de Seguimiento 2026-09-19|Gestión Diaria]] (Mi día, Equipo,
«Llamadas de hoy» del supervisor, cortes de jornada, mínimo de útiles, Pulso y Hábitos) sale de UN lector que solo leía las
actividades de **leads**. Las llamadas a **clientes** se registran al cerrar una tarea de llamada de postventa y quedan en
otra tabla (gestiones de postventa), que el marcador nunca miraba. Medido el 19/10: Vladimir Jurado cerró 5 llamadas a
clientes (3 «agendó reunión», 2 «volver a llamar») y su marcador decía «1 llamada». Jhosep lo había dejado como objetivo
pendiente el 01/10 ([[Llamadas desde el celular - clientes como objetivo pendiente (2026-10-01)]]).

## Decisiones de Miguel (19/10/2026)
1. Las llamadas a clientes **suman al mismo número «Llamadas»** (no cifra aparte).
2. Entran en la **tasa de contacto**.
3. Cuentan hacia los **cortes de jornada y el mínimo de llamadas útiles**.

## Qué se construyó (migración `20261019170422`)
- Un ayudante DEFINER que lee las llamadas a clientes como **espejo de la visibilidad del actor** (su equipo visible, acceso al
  CRM, rol vendedor/supervisor/gerencia, banderas de postventa): filtra, nunca lanza. La métrica es **por quien registró**:
  una reasignación no borra histórico.
- El lector único pasa a leads ∪ clientes; el agregador no cambia salvo que «leads tocados» sigue contando solo leads.
- Misma regla que el Registro de clientes («Gestión de clientes» en Gestión Diaria): cierre de tarea de llamada completada,
  mismo catálogo de 7 resultados, el legado sin espejo. Un cierre antiguo sin resultado cuenta como llamada, no como contestada
  ni útil.
- Se re-sellan tres guardianes (analista, citas, pulso) desde su cuerpo vivo, con anclas; 12 mutantes nuevos. Las contestadas
  por hora usan la misma regla que el total (realizada y útil).

## Lo que el ensayo enseñó
- 🔴 La puerta de estado de postventa toma un candado de fila (`for share`) y PostgREST corre el marcador en transacción de
  **solo lectura**: habría roto Mi día. El ayudante lee las banderas sin candado, como ya hace la RLS de tareas. Regla nueva:
  **probar toda cadena de lectura con `begin read only`**.
- Los guardianes de Gestión Diaria ya estaban en rojo en producción por la consulta de Coordinación del 15/10
  ([[Guardianes en rojo - re-sellado (2026-10-16)]] los re-sella aparte); esta migración no toca lo ajeno y su postflight solo
  tolera esos rojos concretos.

## Revisiones
Codex r1 (diseño): 4 hallazgos aceptados, 1 rechazado con evidencia. auditor-rls y Codex r2 (código): sin fugas; aceptados la
paridad exacta del legado con el Registro, la sección del ayudante antes del roster, la huella fija del rojo ajeno, la reversa
con precondiciones, las contestadas por hora y mutantes específicos. Verificación: ensayo en verde, `npm run check` PASS, 19 E2E
en Docker PASS; `test:rls` hosted NOT RUN (sin entorno en la sesión).

## Lo que verá Vladimir
De «1 llamada» a **«6 llamadas · 6 contestadas»** (su llamada al lead + 5 a clientes contestadas).

## Límites declarados
«Leads distintos» y «llamadas por lead» siguen siendo solo de leads; `gestiones_hoy` de la vista de equipo sigue leyendo
solo actividades de leads. Si Miguel quiere, se abren en otra fase.

## Dónde vive
Kit y ensayo: `CRM-Avance-Corp/supabase/scripts/gestion-diaria-llamadas-clientes/` (LEEME, ensayar, oráculo, reversa,
`AVISO-GUARDIANES-1610.md`). Encargos de Codex: `CRM-Avance-Corp/docs/encargos/2026-10-19-codex-llamadas-clientes-*.md`.
Rama `crm/llamadas-clientes-gestion-diaria-20261019`.

Relacionadas: [[Gestion Diaria F2 - resultado tipificado de llamada (2026-09-20)]] · [[Gestion Diaria F3 - el dia del analista (2026-09-20)]] · [[Inicio]]
