---
tags: [crm, gestion-diaria, analista, typesafe, orden, medicion]
estado: F0 medida y aprobada · F1 escrita, pendiente de branch · F2 y F3 sin empezar
fecha: 2026-09-20
---

# Temperatura del lead — la señal de TypeSafe para ordenar «Mi día»

## El problema

«Mi día» ordena la cartera del analista **solo por vencimiento**
(`20260920041500_crm_gestion_diaria_analista.sql`: `order by referencia, id`, tope 500).
Un lead que pidió el contrato y otro que nunca contestó compiten por la misma posición.
La meta es añadir una segunda señal que **desempate dentro de cada grupo de tiempo**, sin
cambiarle el flujo de trabajo al analista.

## Qué es la señal

Un número de 0 a 3 que responde «¿qué tan cerca está esta persona de invertir?», leído por
Jev (TypeSafe) de las **notas que el analista ya escribe** tras cada gestión. No genera
texto: elige entre cuatro niveles descritos y devuelve además la distribución completa.

Los cuatro niveles, tal como se midieron (cambiarlos invalida la medición): nunca se logró
hablar o dijo que no · se habló sin interés claro · interés con algo concreto pero sin fecha
ni monto · está por cerrar (dio fecha, monto o pidió el contrato).

## F0 — la medición (20/09, aprobada)

45 leads reales con historial, 15 por grupo, tomados de producción. Se excluyó la **última
actividad** de cada lead, que suele delatar el desenlace. Solo viajaron fecha, tipo y nota:
ni nombre, ni teléfono, ni documento.

| Grupo | Nivel medio | Mediana |
|---|---|---|
| Llegaron a cita o entrevista | 1.74 | 1.78 |
| Siguen en contactado | 1.06 | 0.98 |
| Terminaron descartados | 0.44 | 0.01 |

**AUC 0.84** separando avanzados de descartados. Coste total: US$0.001 (24 mil tokens).

Tres cosas que enseñó la medición y que mandan sobre el diseño:

1. **La confianza no sirve para ordenar.** Resultó casi una función del propio nivel: cuando
   Jev reparte entre dos niveles vecinos, la confianza es sencillamente la parte mayor
   (`1.78 → 0.43`, `2.41 → 0.41`, `0.02 → 0.98`). Se guarda para recalibrar, no se usa.
2. **Los peores «errores» son etapas rancias, no fallos del modelo.** Los tres leads del grupo
   avanzado que Jev puntuó 0.00 con confianza 1.00 tienen historiales que dicen que nadie
   contestó nunca: quedaron clavados en «cita agendada» tras un plantón y **la etapa no
   retrocede**. Con una etiqueta limpia el número sería mejor que 0.84. Es justamente el caso
   donde la señal ayuda, porque el orden por etapa no lo ve.
3. **El texto medido estaba recortado por el final** (`left(...,330)` sobre un agregado
   ascendente), o sea que el modelo vio las notas más **viejas**. En producción se recorta al
   revés (`right(...,3000)`), así que verá más texto y más reciente. El 0.84 es un piso, no
   una predicción exacta.

## Lo que NO se puede medir todavía

«¿Predice quién convierte?» no tiene respuesta con los datos de hoy: hay 73 leads convertidos
pero solo 28 con alguna nota, y 1.5 actividades de promedio. **Las conversiones casi no se
registran en el CRM.** Por eso la vara es «llegó a cita o entrevista vs. terminó descartado»,
que sí tiene 249 casos con historial de verdad.

## F1 — el servidor (escrita, pendiente de branch)

Migración `20260921034748_crm_temperatura_lead.sql` y Edge Function `crm-temperatura-lead`.

- Una sola tabla `crm.lead_temperatura` que es cola y resultado a la vez: la señal no tiene
  historia útil y recalcularla cuesta dos centésimas de centavo.
- **RLS encendida y sin ninguna policy, a propósito.** Nadie la lee directo; las puertas de la
  F2 serán `security definer`. Revocada también a `service_role`, que es `bypassrls`.
- La tabla **no guarda texto de notas**, solo una huella SHA-256 del historial usado.
- Molde copiado de los avisos de tasa (`20260910225540`): cola con reserva, cron que despierta
  la Edge con firma HMAC desde Vault, grants solo a `service_role` **más** gate de rol dentro
  de cada función.
- No cambia ningún orden: eso es la F2, con semanas de señal acumulada para comparar.

Coste estimado en régimen: unos **30 centavos de dólar al mes** con 500 leads recalculados a
diario.

## La revisión del auditor RLS cazó un P0 invisible

`pg_catalog.least` **no existe** (42883): `LEAST`, `GREATEST`, `COALESCE` y `NULLIF` son
construcciones del parser, no funciones. Como plpgsql compila perezosamente, la migración
habría aplicado **en verde** y el fallo habría salido en producción la primera vez que el
modelo devolviera un error. Es la misma trampa que el vault ya tenía escrita para `coalesce`,
en otra familia. Ver [[Trampas SQL del servidor CRM]].

Aprendizaje que vale más allá de esta migración: **un gate que no ejecuta una rama no la
compila**. Por eso `test-rls.mjs` ahora llama a `confirmar_temperatura_lead_fn` con
`p_error`, aunque no haya fila que confirmar.

El auditor levantó además tres P1 reales: la cola se envenenaba a la novena toma, el trigger
podía tumbar el registro de una gestión del analista, y faltaba el gate de rol dentro de las
puertas. Todos corregidos antes del branch. Detalle completo en `MIGRACIONES.md`.

## Decisiones tomadas

- **La señal desempata, no manda.** El orden por vencimiento sigue al mando; el peso lo fija
  Miguel y se puede cambiar sin volver a consultar al modelo.
- **Nada de esto toca `analista.tsx` hasta la F3**, porque esa pantalla está en obra con el
  rediseño horizontal «Opción D».
- **Fuera del alcance de Jev:** dinero, conversión, permisos, cierre de mes. La documentación
  del modelo avisa de que no tiene precisión numérica y lee las fechas como texto.
- El historial viaja en un campo **con nombre** (`historial_de_gestion`), no mezclado con las
  instrucciones: lo escribió un tercero y es dato, no órdenes.

## Pendiente

Vault `cron_temperatura_secret`, secreto `TYPESAFE_API_KEY` en la Edge, desplegarla con
`verify_jwt=false`, el ciclo branch → `test:rls` (con `CRM_RLS_EXIGE_TEMPERATURA=1`) →
advisors → merge. Y **rotar la key de TypeSafe**, que se pegó en un chat el 20/09.

Relacionadas: [[Gestion Diaria F4 - objetivos y piloto TypeSafe (2026-09-20)]] (otro uso de
TypeSafe, para el supervisor) · [[Gestion Diaria F3 - el dia del analista (2026-09-20)]] ·
[[Inicio]].
