---
tags: [crm, rentabilidad, propuesta]
fecha: 2026-09-13
estado: propuesta-aprobada-implementacion-pausada
---

# Rentabilidades menores a 15 %

Miguel pidió que el analista pueda tipear rentabilidades menores al 15 % y
preguntó cómo hacerlo. Es una nueva necesidad respecto de D4 del
[[Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06]],
que bloquea tasas inferiores a la base.

## Diagnóstico local

CodeGraph se consultó primero; no localizó los componentes recientes y se
complementó con lectura puntual. `TasaPolitica` fija el mínimo y máximo en
la base, mantiene el campo en solo lectura y restablece la base cuando el
valor cambia sin autorización. `ContratoNuevo` y `CondicionesEditables`
también rechazan tasas inferiores al mínimo del rango.

## Propuesta presentada

Para una inversión cuya base es 15 %, permitir escribir una tasa positiva de
hasta 15 %, con hasta dos decimales, sin solicitar una excepción. Mantener el
15 % precargado. Para superarlo, conservar el flujo de aprobación de Gerencia
antes de convertir. Una solicitud ya pendiente sigue bloqueando la conversión;
bajar el valor escrito no debe eludir esa decisión pendiente.

La tasa elegida debe conservarse desde la ficha del lead hasta el contrato.
La implementación deberá ajustar y verificar también las validaciones del
servidor y la trazabilidad. Renovaciones y upgrades tienen una base heredada:
no confundir el 15 % de una inversión nueva con un límite universal ni
reinterpretar automáticamente las condiciones de contratos existentes.

El diagnóstico inicial fue solo una propuesta. Después Miguel autorizó:
«deja todo listo para hacer deploy. pero no lo hagas». Esto autoriza implementar
y verificar la propuesta, conservando la publicación pendiente. La D4 anterior
se revisa únicamente para el alta de categoría `nuevo`, no para rebajar términos
de un contrato existente ni el piso heredado de renovaciones y upgrades.

Implementación, pruebas, artefacto y punto de retoma:
[[Rentabilidades menores a 15 - pausa segura 2026-09-14]].

Relacionadas: [[Solicitud de tasa en el lead - publicada 2026-09-09]],
[[Alertas de respuestas de tasa para analistas - 2026-09-11]], [[Inicio]].
