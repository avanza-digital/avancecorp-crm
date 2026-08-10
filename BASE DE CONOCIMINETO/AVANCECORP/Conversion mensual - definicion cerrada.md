---
tags: [crm, conversion, metas, regla-de-negocio, pendiente-implementar]
actualizado: 2026-08-10
estado: definicion-cerrada-sin-implementar
---

# Conversión mensual — definición cerrada

Acordada con Miguel el **2026-08-10** tras varias iteraciones. **Todavía NO está
implementada**: lo que hay en producción usa otra fórmula (ver el final).

## La fórmula

Para el asesor **V** en el mes **M**:

**DIVISOR** = los leads **no referidos** que V recibió en M.
- Se determina por la fecha en que el lead **pasó a ser suyo** (asignación), no
  por la fecha de alta del lead.
- Incluye los que siguen **abiertos** y los **descartados**. Nada se cae.
- ⚠️ **Los referidos NO entran** (cambio de Miguel, 2026-08-10 noche): *«el tema
  de referidos no afecta al vendedor, es decir no entra dentro de su divisor;
  solo si se cierra entra en el numerador»*. Recibir referidos no cuesta nada.

**NUMERADOR** = cierres que V hizo en M, así:
- leads **no referidos** cerrados en M → cuentan **al 100 %**;
- leads **referidos** cerrados en M → cuentan **al 15 %**.
- «Cierre hecho en M» = el lead se convirtió en cliente dentro de M, **sin
  importar en qué mes entró**. Uno de julio cerrado en agosto suma al numerador
  de **agosto** — y NO al divisor de agosto, porque su divisor fue el de julio.

**CONVERSIÓN = NUMERADOR ÷ DIVISOR**

## Ejemplo canónico

Ana recibe **90** leads de otros canales en agosto y **registra 20 referidos**.
Cierra **16** de otros canales (12 de agosto + 3 de julio + 1 de junio) y **12
referidos**.

| | |
|---|---|
| Divisor | **90** (los 20 referidos NO entran) |
| Numerador | 16 + (12 × 0,15 = 1,8) = **17,8** |
| **Conversión** | 17,8 ÷ 90 = **19,8 %** |

> Con la regla anterior (referidos enteros en el divisor) daba 16,2 %. El cambio
> del 2026-08-10 por la noche los sacó del divisor.

## Reglas de detalle

**Reasignaciones.** El lead suma al **divisor de cada** asesor que lo recibió en
el mes; el cierre suma al **numerador solo de quien lo convirtió**.
> A lo recibe en agosto y lo suelta; B lo recibe en agosto y lo cierra →
> **A: 0 de 1. B: 1 de 1.** Soltar un lead no limpia el expediente.

**Descartar no ayuda**: el lead sigue en el divisor. *«Con eso evitamos que
descarten así por que sí.»*

**Dejar abiertos tampoco**: también están en el divisor.

**Puede superar el 100 %** en un mes flojo, porque el numerador admite cierres de
meses anteriores y el divisor no. Miguel lo asume a sabiendas: reciben ~90 leads
al mes y arrastran ~4 cierres viejos, así que en la práctica no ocurre.

**No se pueden sumar los meses para sacar el año.** El año se calcula aparte, con
su propia ventana.

## Lo que ve gerencia en «Conversiones por asesor»

1. **De qué mes venía cada cierre**, con el mes nombrado:
   `Ana · agosto — 16,2 % · de agosto 12, de julio 3, de junio 1`.
   Distingue a quien cierra lo que le entra de quien vive de arrastrar cartera
   vieja.
2. **Bloque de referidos** por analista:
   `Referidos: 20 registrados · 12 cerrados · aporta 1,6 %`.
   Expresado en **%**, no en «puntos».

## El origen del lead se congela

Con el 15 % de los referidos, el origen deja de ser una etiqueta informativa y
pasa a tener **consecuencia económica**: mover un lead a «referido» o sacarlo de
ahí cambia la conversión de alguien.

**Decisión:** `crm.leads.origen` es **inmutable**, con una única excepción —
**gerencia puede corregirlo durante las primeras 24 horas** desde la creación del
lead, y la corrección queda registrada en `public.audit_log`. Pasado ese plazo
queda sellado para todos.

Misma ventana que `crm.deshacer_descarte`, que el equipo ya conoce. Y garantiza
que al cerrar el mes ningún origen se haya podido mover en las últimas semanas:
la conversión de agosto no puede cambiar en septiembre por una reclasificación.

## El referido es SOLO bonificación (corregido el 2026-08-10)

La primera versión ponía el referido **1 abajo y 0,15 arriba**, así que registrar
referidos **bajaba** la conversión. Se le advirtió a Miguel con números
—registrando 20 y cerrándolos todos, el resultado seguía siendo peor que no
registrarlos— y primero respondió *«sé lo que me dices y lo comparto, pero así lo
quieren por ahora»*. Esa misma noche lo cambió: **fuera del divisor**.

Con la regla nueva el referido **no cuesta nada y solo puede sumar**. El incentivo
queda alineado: registrarlos es gratis, cerrarlos premia.

⚠️ **Efecto de borde nuevo**: un asesor que en el mes solo recibió referidos tiene
**divisor 0**. No es «no recibió nada» ni es «0 %»: hay que rotularlo aparte
(estado propio en el payload) o se leerá como que no trabajó.

## Lo que hay HOY en producción (y no es esto)

Conviven **dos** fórmulas, y ninguna es la acordada:

1. `crm.cumplimiento_metas_fn` (`20260808183527`, CTE `conversiones`):
   convertidos ÷ (convertidos + descartados) **resueltos dentro del mes**. Los
   abiertos no cuentan — justo la inflación que Miguel quiere evitar. Alimenta la
   tarjeta «Conversión resuelta» contra la que se mide la meta.
2. `crm.metricas_conversiones_fn` y `crm.metricas_conversiones_equipo_fn`
   (`20260810024404`): cohorte por **fecha de alta**. Alimentan la pantalla
   «Conversiones» y el ranking.

Relacionado: [[Como se mide la conversion del asesor]],
[[Por que el CRM nunca tuvo metas publicadas]], [[Metas del asesor van en soles]].
