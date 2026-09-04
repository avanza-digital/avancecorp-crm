---
tags: [crm, ranking, mi-cartera, cooperativas, diagnostico]
actualizado: 2026-09-02
estado: diagnostico-verificado-fix-ux-pendiente
---

# Descuadre aparente entre Ranking y Mi cartera por cierres en cooperativas

Relacionado con [[Cierres en cooperativas Qorilazo y Prodelco - plan]],
[[Rankings por mes calendario (decision 2026-09-02)]],
[[Ranking de capital total unificado (TC BCRP)]] y [[Mi cartera por meses]].

## Caso real que destapó el problema

El 2026-09-02 Miguel observó que **FIORELLA RUIZ** tenía **S/ 20.000** en el
ranking de setiembre, mientras la lista principal de su cartera de setiembre no
mostraba contratos.

La lectura de producción confirmó que ambas cifras son correctas y hablan de
fuentes diferentes:

- `private.produccion_mes_por_vendedor` devuelve para Fiorella en setiembre
  `nuevo · PEN · 1 cierre · S/ 20.000`.
- La fila nace de `private.capital_episodios` con `tipo='cooperativa'`: cierre
  vigente en **COOPAC Qorilazo**, registrado el 01/09/2026, no de
  `public.contratos`.
- Los clientes cuya cartera pertenece a Fiorella tienen **0 contratos Avance**
  con `fecha_cierre_comercial` en setiembre; por eso el bloque contractual de
  Mi cartera está vacío.
- Ejecutada bajo la identidad real de Fiorella,
  `crm.cierres_externos_fn('2026-09-01')` sí devuelve exactamente ese cierre y
  el total S/ 20.000. No hay pérdida de datos ni fallo de ámbito/RLS.

El cambio reciente que hizo que Mi cartera agrupe contratos por
`fecha_cierre_comercial` **no causa estos S/ 20.000**: un cierre en cooperativa
no crea contrato Avance ni perfil de cliente en el portal.

## Causa de la confusión en la interfaz

`Mi cartera` contiene dos superficies separadas:

1. la tarjeta/lista principal, que representa clientes y contratos de Avance;
2. `SeccionEnCooperativas`, ubicada después de la paginación, para personas que
   no tienen cuenta ni contrato en el portal.

Cuando Avance está vacío, la pantalla anuncia primero «Sin cierres en
setiembre», aunque más abajo exista un cierre en cooperativa. Además,
`SeccionEnCooperativas` consulta `periodoLima(Date.now())`: no recibe el filtro
de mes ni el filtro de analista elegidos en la cartera. El backend está
comunicado; la reconciliación visual es insuficiente.

## Arreglo recomendado (pendiente de implementar)

- Mantener separados **capital administrado por Avance** y **cierres en
  cooperativas**; no sumar una cooperativa al AUM de Avance.
- En el resumen mensual, mostrar una conciliación «Producción reconocida en el
  ranking» con desglose por empresa: Avance, Qorilazo y Prodelco.
- Cambiar el vacío a «Sin contratos de Avance en setiembre» y, si hay cierres
  externos, anunciar allí mismo cuántos y por cuánto.
- Hacer que la sección de cooperativas siga el mismo mes y, para
  Supervisor/Gerencia, el mismo analista seleccionado.
- Colocar el bloque de cooperativas antes del vacío contractual o enlazarlo
  desde el resumen, para que el usuario no tenga que descubrirlo debajo de la
  paginación.

No hace falta cambiar la fórmula del ranking ni convertir el cierre externo en
un contrato Avance. La corrección es principalmente de composición y filtros
del frontend sobre la RPC existente.

## Estado de ramas al diagnosticar

`main` y `avancecorp/tronco` estaban alineadas (0 commits de diferencia) y el
build vivo era `build-20260902T170712941Z`, que ya incluye Mi cartera por fecha
de cierre. El taller compartido tenía cambios sin confirmar de otra sesión; no
son la causa del caso y no debe construirse ni desplegarse desde esa mezcla.
