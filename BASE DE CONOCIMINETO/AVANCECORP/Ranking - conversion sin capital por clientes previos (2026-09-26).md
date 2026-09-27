---
tags: [crm, ranking, conversion, diagnostico, clientes-existentes]
fecha: 2026-09-26
estado: diagnóstico verificado en producción; corrección no autorizada ni ejecutada
---

# Ranking — conversión sin capital por clientes previos

Miguel reportó en la ficha de Betzabeth: Landing S/ 0 con 2,44 % y Formulario
S/ 0 con 3,03 %. Se verificó mediante consultas de solo lectura en producción.

## Evidencia

| Canal | Conversión contada en septiembre | Inversión existente |
|---|---|---|
| Landing | 1 cierre / 41 leads = 2,44 %; resultado del episodio: 21/09/2026 | S/ 2.000; fecha comercial 13/12/2025 |
| Formulario | 1 cierre / 33 leads = 3,03 %; resultado del episodio: 19/09/2026 | US$ 20.000; fecha comercial 26/01/2026 |

Ambos leads están en `etapa='convertido'`; sus únicos episodios tienen
`resultado='convertido'` en septiembre. Sus contratos son activos, categoría
`nuevo`, del mismo analista. No hay cierres externos para estos leads ni sus
inversionistas. El historial de `crm.inversiones` consultado solo contiene las
inversiones antiguas indicadas. Landing tiene enlace directo al contrato;
Formulario tiene enlace al perfil, pero `contrato_id` nulo.

Identificadores para reproducir la consulta (sin documentos ni contactos):
- Landing, lead `bd65cb35-a67c-4d3d-8fc6-c62825adb2cd`;
  contrato `d6ef277f-4c58-45fe-9436-0f8d98b27dd7`.
- Formulario, lead `d1297c01-1da8-48c8-a852-3c256ff516b0`;
  contrato `ccc2b458-850f-48da-99af-9d06d0de264f`.

## Dónde nace la discrepancia

Definiciones vigentes leídas mediante `pg_get_functiondef`:

1. `private.conversion_cierres` cuenta los episodios de
   `crm.lead_asignaciones` con resultado convertido usando
   `coalesce(resultado_en, finalizado_en)` como fecha del cierre. No exige que
   el contrato vinculado tenga fecha comercial en ese mes, ni valida allí
   primera inversión de la persona. Devuelve monto nulo: no es una suma monetaria.
2. `private.ranking_conversion_origen_mes` toma esos cierres y los divide por
   las llegadas del canal/analista; Landing y Formulario tienen peso 1.
3. `private.ranking_capital_origen_filas` lee el capital canónico por fecha
   comercial. Las dos inversiones antiguas no aportan al capital de septiembre.
4. `private.ranking_origen_live` junta ambos resultados; el frontend
   `ranking-detalle.tsx` presenta los valores recibidos sin recalcular la tasa.

El diagnóstico es una atribución temporal de conversiones de clientes previos,
no un importe perdido ni un error de formato. No se determinó en esta revisión
qué acción histórica exacta escribió los estados convertidos ni su autor.

## Límites y siguiente decisión

No se modificaron datos, SQL ni frontend. No ocultar el porcentaje porque el
capital sea cero, ni mover dinero histórico a septiembre para forzar coincidencia.
Una corrección requiere acordar el tratamiento de estos episodios de cliente
existente y comprobar el núcleo común de conversión y sus consumidores,
preservando los cierres mensuales sellados y la auditoría.

No confundir con [[Ranking cartera - publicacion verificada (2026-09-26)]]:
esa entrega solo reclasificó capital de upgrades legados, no cambió la conversión.
Relacionar con [[Plan por fases - inversion por empresa y ranking de cartera (2026-09-26)]]
y [[Ranking - enlaces excepcionales y propuesta por empresa (2026-09-26)]].
