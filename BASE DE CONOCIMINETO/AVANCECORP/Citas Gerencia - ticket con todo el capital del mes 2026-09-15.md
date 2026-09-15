---
fecha: 2026-09-15
estado: implementado-verificado-pendiente-publicar
tags: [crm, citas, gerencia, ticket, capital, adelayda]
---

# Citas Gerencia — el ticket del mes cuenta TODO el capital del analista

## El problema que vio Miguel

En Citas → Avance mensual, Adelayda tenía S/ 230 000 cerrados en septiembre y el
«Ticket del mes» decía «Sin base». Dos causas encadenadas, verificadas en producción:

1. El ticket sólo cruzaba **contratos nuevos con leads convertidos en el mes**. Sus dos
   contratos nuevos (S/ 140 000) eran de clientes creados con «Nuevo cliente» sin lead;
   sus upgrades y renovación (S/ 90 000) quedaban fuera por diseño.
2. Su única conversión del mes (Laupa Torres, cliente desde mayo con S/ 500 000) no
   firmó nada en septiembre, y una conversión sin contrato **anulaba la fila entera**.
   A Fiorella le pasaba lo mismo, y al total del equipo también.

## La decisión

Miguel (15/09): «**todo debe contar al ticket medio, nada debe quedar fuera**».

Regla nueva: ticket = todo el capital real que el analista cierra en el mes (contratos
nuevos, upgrades, renovaciones y cierres en cooperativas; medida «stock» del mismo
núcleo `private.capital_episodios` que Mi cartera y Ranking, atribuido al analista del
núcleo) ÷ personas únicas con capital. Una conversión sin capital ya no anula nada: se
informa aparte. Monedas como antes (nativas visibles, ticket en soles con el TC del CRM).

Con datos reales de septiembre: Adelayda 230 000 / 4 = 57 500; Betzabeth 44 490;
Fiorella 45 667; Guillermo Castro 96 667; Linda 31 600. El «Capital del mes» de la
cabecera pasa a coincidir con Mi cartera y Ranking (S/ 3 553 304 + US$ 90 500).

## Qué se cambió

**Servidor** (dos migraciones, ensayadas en producción dentro de un bloque `DO` que
termina en `raise` → deshecho; ver `MIGRACIONES.md`):
- `20260915170017` re-declara la exención analítica de `crm.cierres_externos_fn(date)`:
  F8 (`20260914213928`) la recreó sin renovar la huella y **el gate analítico de
  producción llevaba fallando desde el 14/09** («cuerpo CAMBIÓ desde que se
  declararon»), lo que bloqueaba cualquier migración de Citas. Sólo bendice el cuerpo
  vivo (md5 verificado = texto de F8).
- `20260915170018` sustituye en sitio el bloque de capital del lector
  `private.citas_gerencia_consulta` (patrón de `20260914044939`) y añade a la población
  los leads vinculados al capital del mes para que los filtros de persona lo acoten.

**Front** (`app/src`): `lib/gestion-citas.ts` (esquema: `tipo`, `cierre_externo_id`,
`identidad_persona`, analista/supervisor; ids anulables), `components/citas/avance.ts`
(ticket por analista del núcleo, identidad canónica, `sinContrato` informativo,
desglose por tipo, analistas sólo con capital tienen fila, proyección = capital cerrado
+ clientes que aún se esperan del flujo × ticket, mes cerrado = capital),
`avance-mensual.tsx` (textos, ayuda, CSV con seis columnas nuevas al final),
`data/citas-gerencia.ts` (frontera: contrato O cierre externo, único; perfil sólo si el
lead se convirtió), `contexto.ts` (selectores incluyen analistas con sólo capital).

## Revisión y verificación

Codex (CLI read-only; el MCP estaba caído) devolvió CHANGES_REQUESTED con 1 P1 y 5 P2.
Atendidos los cinco P2 (proyección, mes cerrado, filtros/`q` en blanco/leads del capital
en la población, selectores, «convertidos sin capital» estable al filtrar). El P1
(pestañas abiertas con el front anterior fallan tras aplicar el SQL hasta recargar) se
acepta con mitigación: front primero, SQL inmediatamente después, aviso de recarga.

- oxlint, tsc: PASS · vitest 65/65 en los módulos tocados · Playwright Citas 7/7 PASS
- `npm run check` completo: PASS (3 599 tests, build, bundle, dup) antes de los ajustes
  de la revisión; repetido tras ellos (ver nota de publicación).
- Ensayo en producción (deshecho): gate OK; 77 episodios, 72 identidades, 29/29 leads de
  capital en la población con la misma identidad; Adelayda 5 operaciones, 4 clientes,
  S/ 230 000.

## Cómo se publica

1. Front: `npm run release:crm` → preflight → deploy con el token de Miguel.
2. Servidor: `CRM-Avance-Corp/aplicar-ticket-capital-completo-prod.sh` (aplica, registra
   y comprueba leyendo como Gerencia). Nunca `db push` ni `merge_branch`.
3. Reversa: front = ZIP anterior; servidor = reponer los bloques `v_buscar*` de la migración.

Relacionado: [[Citas Gerencia - ticket unificado en soles 2026-09-14]],
[[Citas Gerencia - decisiones finales para publicar 2026-09-14]],
[[Alta directa de clientes cerrada al analista (2026-09-15)]],
[[Contrato de la capa semantica - Capital (F4, 2026-08-29)]].
