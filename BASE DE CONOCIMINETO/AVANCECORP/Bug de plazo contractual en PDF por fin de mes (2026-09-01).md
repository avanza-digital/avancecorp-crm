---
tags: [bug, contratos, pdf, fechas, produccion]
actualizado: 2026-09-01
estado: corregido-local-pendiente-produccion
---

# Bug de plazo contractual en PDF por fin de mes (2026-09-01)

## Síntoma

Un contrato creado con el selector **6 meses** puede mostrar en la cláusula
5.1 del PDF **CINCO (5) MESES**. El caso confirmado usa
`fecha_inicio = 2026-08-31` y `fecha_vencimiento = 2027-02-28`.

## Causa confirmada

El formulario del analista calcula bien el vencimiento. Al sumar seis meses a
un día 29, 30 o 31 que no existe en el mes de destino, aplica la regla de fin
de mes y guarda el último día disponible. Por ejemplo, 31 de agosto + 6 meses
= 28 de febrero.

La tabla `public.contratos` no conserva el plazo elegido como columna; solo
guarda `fecha_inicio` y `fecha_vencimiento`. La plantilla vuelve a inferir el
plazo mediante `plazoVisible` y resta un mes siempre que el día final sea menor
que el inicial:

```ts
(af - ai) * 12 + mf - mi - (df < di ? 1 : 0)
```

Así, agosto→febrero da 6 meses, pero `28 < 31` activa la resta y el PDF imprime
5. La fórmula no distingue entre una fecha realmente incompleta y el ajuste
válido al último día del mes.

El defecto existe tanto en
`CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/template-v2.ts` como en
la copia frontend `CRM-Avance-Corp/app/src/lib/contrato-pdf.ts`. La cláusula
5.1 consume directamente ese resultado.

## Alcance productivo comprobado

Consulta de solo lectura del 2026-09-01: hay **7 PDFs sellados** que representan
un plazo seleccionado de 6 meses como 5 meses. Todos coinciden exactamente con
la suma de meses ajustada al fin de febrero:

- `2026-01-001324`
- `2026-01-001332`
- `2026-01-001337`
- `2026-01-001342`
- `2026-01-001343`
- `2026-01-001344`
- `2026-01-001348`

No se encontró el número incompleto `2026-01-00134`; en producción existen
varias coincidencias con un dígito final. `2026-01-001347` es de 24 meses y no
presenta este defecto.

Los 7 documentos afectados estaban sellados con la plantilla
`contrato-aep-17-v5`, revisión 1. La plantilla local v6 conserva la misma
fórmula, por lo que el problema continúa en el código vigente.

## Brecha de pruebas

Las pruebas del renderer usan fechas con el mismo día del mes
(`2026-08-17`→`2027-08-17`). Las 27 pruebas actuales pasan, pero no existe un
caso de fin de mes como `2026-08-31`→`2027-02-28`. Una reproducción directa con
la plantilla v6 genera literalmente **CINCO (5) MESES**.

## Corrección preparada

La plantilla v7 reconoce como mes completo el aniversario ajustado al último
día del mes: `2026-08-31`→`2027-02-28` muestra **SEIS (6) MESES**, mientras
`2026-08-31`→`2027-02-27` conserva **CINCO (5) MESES**. La regla quedó aplicada
en la Edge y en la copia frontend, con pruebas de fin de mes y año bisiesto.

La migración
`20260901184132_crm_contrato_pdf_plantilla_v7_plazo_fin_mes.sql` preserva cada
PDF sellado y crea una revisión 2 pendiente para los 7 afectados, copiando el
snapshot v5 original. También actualiza a v7 las reservas v5/v6 que todavía no
tienen bytes ni lease. Fue ensayada en PostgreSQL temporal con siete fixtures y
pasó junto con 29 pruebas Deno, 44 pruebas Vitest y el typecheck del portal.

No se aplicó todavía ningún cambio a producción: falta la autorización expresa
del SQL y luego publicar en orden frontend → Edge → migración → generación de
las siete revisiones.

Relacionado: [[PDF de contrato (generador) — plan]] · [[Rol Analista]] ·
[[Ciclo de vida de contratos]] · [[Bug de fechas UTC]]
