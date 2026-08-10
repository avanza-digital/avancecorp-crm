---
tags: [crm, metas, conversion, regla-de-negocio]
actualizado: 2026-08-10
---

# Cómo se mide la conversión del asesor

**Regla de negocio (Miguel, 2026-08-10):** un lead **descartado le sigue
contando** al asesor ese mes. *«Con eso evitamos que descarten así por que sí.»*

## La fórmula que hay en producción

`crm.cumplimiento_metas_fn` (migración `20260808183527`, CTE `conversiones`):

```sql
convertidos = leads con etapa 'convertido' en el mes
resueltos   = convertidos + descartados en el mes
conversión  = 100 * convertidos / resueltos
```

Un lead descartado entra en **`resueltos`**, o sea en el **DIVISOR**. Por eso
descartar **baja** la conversión: el caso se le apunta igual, pero sin premio.

> ⚠️ Precisión que importa: si el descarte contara en el **numerador**,
> descartar *subiría* la conversión y premiaría justo lo que se quiere evitar.
> El efecto disuasorio se consigue porque va en el divisor. El sistema ya lo
> hacía así; la regla queda escrita para que nadie lo «arregle» al revés.

Un lead que sigue abierto no cuenta en ninguno de los dos lados: la conversión
mide lo **resuelto**, no lo que está en curso.

## Los leads NO se eliminan

Miguel, textual: *«nadie ha dicho que se puede eliminar leads, eso modificaría
los resultados»*.

Verificado en producción el 2026-08-10: **0 leads con `activo = false`** en toda
la base. Ninguna pantalla del CRM apaga un lead; haría falta SQL manual.

**Decisión asociada — NO se filtra `l.activo` en la CTE `conversiones`.** Una
auditoría propuso añadir ese filtro (un lead soft-borrado dejaría de contar).
**Se descarta a propósito**: si algún día alguien borrara un lead, su descarte
o su cierre deben seguir contando, precisamente para que borrar no sea una vía
de maquillar el resultado. Filtrar ahí convertiría el soft-delete en una goma
de borrar de la conversión.

⚠️ No confundir con `crm.cartera_pagina_fn`, que **sí** filtra `activo`: ahí se
trata de qué leads se VEN, no de qué resultados se CUENTAN. Ver
[[codigo-retomar-43]].

## La única marcha atrás: 24 horas

`crm.deshacer_descarte` permite revertir un descarte durante **24 horas**, solo
al propio asesor y si el lead no tiene dueño nuevo (`20260724203052`). Pasado
ese plazo el descarte es definitivo. Si se deshace dentro de plazo, el lead sale
del divisor y la conversión se recupera — coherente, porque deja de estar
resuelto.

## La meta de conversión

Se pacta **una sola para toda la empresa** en Configuración → Metas, y el
detalle por analista se consulta en la pantalla de **Conversiones**. Hasta el
2026-08-10 era imposible de fijar (el editor la guardaba siempre en cero): ver
[[Por que el CRM nunca tuvo metas publicadas]].

Relacionado: [[Metas del asesor van en soles]],
[[CRM filtro de leads que piden crédito|crm-filtro-credito-plan]].
