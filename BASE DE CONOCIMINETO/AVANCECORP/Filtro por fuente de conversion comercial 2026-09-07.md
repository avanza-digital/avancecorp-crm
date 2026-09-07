# Filtro por fuente de conversión comercial — 2026-09-07

## Decisión

Gerencia puede consultar el índice comercial completo o aislar el aporte de una fuente: **Landing, Formulario, Upgrade, Referido o Renovación**. La selección se conserva al pasar por Resumen, Conversiones, Ranking, Metas y Rendimiento. Citas no usa este filtro porque responde otra pregunta.

La interfaz muestra **“Aporte de [fuente] al índice”** cuando hay una fuente elegida. No presenta ese aporte como una segunda conversión ni lo compara por separado con la meta total.

## Regla comercial conservada

- Landing y Formulario: cada cierre aporta ×1.
- Upgrade: cada operación aporta ×1.
- Referido y Renovación: cada resultado aporta ×0.15.
- El divisor sigue siendo la base automática de prospectos de Landing/Formulario.
- Altas manuales, referidos y operaciones de cartera no aumentan el divisor.

El frontend no redefine elegibilidad ni ponderaciones. Para Landing, Formulario y Referido usa los aportes ya servidos en `cierres_por_semana`; para Upgrade y Renovación agrupa los aportes ya servidos en `conversion_operaciones`. Si el núcleo y sus sondas no están verificados, la cifra se oculta.

## Presentación

El selector se llama **“Conversión de”** y ofrece **“Todas las fuentes”** como lectura inicial. El total conserva el nombre de índice comercial. Una fuente muestra su cantidad de cierres u operaciones, su aporte ponderado y la misma base automática. Los porcentajes canónicos se presentan con dos decimales.

En Upgrade y Renovación se ocultan gráficos exclusivos del recorrido de prospectos. Ranking, Metas y Rendimiento reutilizan la selección y la misma lectura ponderada.

## Alcance técnico

El cambio es de frontend y consume contratos existentes; no agrega funciones independientes ni modifica núcleos de negocio o RPC.

## Relacionado

- [[Conversion comercial - una sola tasa visible 2026-09-06]]
- [[Gestión comercial de clientes - renovaciones y upgrades]]
- [[Canales de origen de leads CRM]]
