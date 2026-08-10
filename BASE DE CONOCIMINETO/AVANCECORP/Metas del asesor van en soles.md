---
tags: [crm, metas, comercial, regla-de-negocio]
actualizado: 2026-08-10
---

# Metas del asesor van en soles

**Regla de negocio (Miguel, 2026-08-10):** el asesor trabaja **su meta en soles
y su conversión**. Esas son las dos cifras con las que se le mide el mes.

El modelo de metas versionadas (`crm.metas_vendedor_detalle`) es por
**categoría × moneda**, así que soporta meta en PEN y en USD a la vez — y el
panel «Tu cumplimiento del mes» pintaba las **tres** columnas fijas (capital
PEN, capital USD, conversión) tuviera o no meta en cada una. Para un asesor
real eso significaba un tercio del panel diciendo «Sin meta fijada para este
mes» todos los días del mes.

## Lo que se hizo

La columna de **dólares** dejó de ser fija. Se pinta solo cuando tiene algo que
decir:

1. le fijaron meta en USD, **o**
2. **cerró capital en USD** aunque nadie se lo pidiera, **o**
3. **no se sabe**: si la lectura de metas o la de cumplimiento falló, no se
   puede afirmar que no hay nada en dólares.

Por defecto —metas en soles, sin cierres en dólares— el asesor ve **soles +
conversión**, que es lo pedido.

**Por qué no se borró la columna sin más:** ocultarla siempre habría escondido
capital cerrado. Si un asesor cierra un contrato en dólares, ese trabajo tiene
que verse en su panel; una pantalla que no enseña dinero que entró es peor que
una con una columna de sobra. El punto 3 es la misma disciplina de siempre: un
cero leído no es lo mismo que un dato que no se pudo leer.

## Dónde NO se tocó (y por qué)

- **Modo demo**: el vendedor demo tiene meta Y cierres en dólares
  (20.000 USD en `CUMPLIMIENTO_VENDEDORES_DEMO`), así que ahí la columna sigue
  saliendo — correctamente, por la regla 2. Si la demo debe enseñar el negocio
  real (asesores solo en soles), hay que quitar también esos cierres del
  fixture: es una decisión de guion de la demo, no un bug.
- **Paneles de supervisor y gerencia**: sus metas son la **suma** del equipo, así
  que si todo el equipo va en soles arrastran el mismo ruido. No se tocaron
  porque el reporte era del asesor; queda anotado como pendiente si se ve igual.
- **Formulario de metas de gerencia** (`config-metas`): sigue pidiendo capital en
  las dos monedas por asesor. Si los asesores nunca llevan meta en dólares, esos
  campos sobran ahí también.

## Dato de contexto

Al revisar producción para diagnosticarlo: **no hay ninguna revisión de metas
publicada** (`crm.meta_periodos` con 0 filas), así que hoy cualquier asesor real
ve su panel con las metas de capital en blanco. Las cifras que se ven en la
cuenta **demo** son fixtures, no producción.

Relacionado: [[Acceso y roles del CRM]],
[[Plan de escalabilidad del CRM a data gigante]].
