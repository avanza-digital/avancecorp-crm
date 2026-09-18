---
tags: [crm, rentabilidad, diagnostico]
fecha: 2026-09-18
estado: causa-verificada-sin-correccion
---

# Modo observación mantiene la solicitud de tasa

Miguel informa que cambió la política a observación, pero el analista sigue
teniendo que solicitar tasa. Se verificó la causa con consultas de solo lectura
en producción y revisión del código. No se cambió la aplicación ni la base.

## Estado productivo comprobado

La política vigente es la versión 14: `modo = observacion`, tasa base para
nuevas inversiones 15 % y tope técnico 28 %. Entró en vigencia el 18/09/2026
a las 12:05:47 de Lima. La versión 13 estaba en `enforcement`.
El cambio de Miguel sí quedó guardado.

## Causa

- `TasaPolitica` (`app/src/components/app/tasa-politica.tsx`, líneas 189–214)
  calcula el máximo permitido como la base o el tope de una autorización.
  Aunque `resolverTasa` entrega `politica.modo`, el componente no lo usa para
  decidir el rango ni el bloqueo por solicitudes pendientes.
- La definición productiva de `private.validar_tasa_conversion_lead` exige
  aprobación cuando la tasa supera la base, sin consultar el modo de la
  política. También bloquea solicitudes pendientes. Por eso una corrección
  exclusivamente visual no resuelve el flujo de conversión.
- `private.trg_contratos_observar_rentabilidad` sí condiciona el control R4
  a `modo = enforcement`; sin embargo, llama a
  `private.rentabilidad_exigir_respuesta` fuera del manejador de observación.
  Esa función rechaza una solicitud pendiente sin consultar el modo.
- La descripción de observación promete «no se bloquea nada» en
  `app/src/lib/rentabilidad.ts:71`. Esa promesa no coincide con los otros
  controles vigentes. El diseño por fases explica la separación histórica.

## Verificación y alcance

PASS: lectura de la política vigente y definiciones productivas; 47 pruebas
existentes de `tasa-politica.test.tsx` y `condiciones-tasa-lead.test.tsx`.
La fixture del primer archivo usa `politica.modo = observacion` y sus pruebas
esperan el límite de la base y el rechazo de 16 % sin autorización. Confirman
el comportamiento actual; no acreditan una corrección.

NOT RUN: conversión real autenticada en producción, build y matriz completa.
No se necesitaba crear clientes ni contratos para este diagnóstico.
No se consultó un reviewer: diagnóstico de causa directa, sin cambio de
lógica financiera, permisos o esquema. Los cambios locales preexistentes
de conversión unificada se conservaron.

Para que observación permita operar sin solicitar aprobación, una futura
corrección debe coordinar el formulario, la conversión y el tratamiento de
solicitudes pendientes, conservando validaciones de identidad y datos.
No basta volver a guardar la misma política.

Relacionado: [[Inicio]],
[[Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06]],
[[Correccion solicitud de tasa - motivo y bloqueo de contrato 2026-09-08]],
[[Solicitud de tasa en el lead - publicada 2026-09-09]],
[[Rentabilidades menores a 15 - publicacion autorizada 2026-09-14]].
