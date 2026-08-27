# Propuesta C0.1: métricas por equipo desde el núcleo único

> **NO EJECUTAR.** Este directorio contiene un artefacto de revisión, no una
> migración. Requiere aprobación expresa de Miguel, captura live autorizada de
> todas las anclas y sustitución de cada placeholder fail-closed
> `__CAPTURAR_*__`. No aplicar el SQL ni copiarlo a `supabase/migrations/` antes
> de cumplir esos gates.

Artefactos revisables:

- `C0.1-metricas-vendedores-nucleo-unico.sql`
- `C0.1-banco-adversario.sql`
- `C0.1-banco-runner-plan.md`
- `README.md`

## Fórmula aprobable

Por cada equipo identificado por el `supervisor_id` canónico:

```text
D_equipo = Σ responsable.divisor
N_equipo = Σ responsable.numerador_neto
P_equipo = NULL                                  si D_equipo = 0
           round(100 × N_equipo / D_equipo, 2)  en otro caso

convertidos_equipo = Σ(cierres_no_referidos + cierres_referidos)
operaciones_cartera_equipo = Σ cartera.conversiones_clientes
```

El numerador de cada responsable ya incorpora su ajuste pendiente con suelo
cero. Por eso se suman numeradores netos por vendedor; no se resta el ajuste
después de agregar. No se promedian porcentajes ni se usa el propietario
actual; tampoco se aplica la ventana operativa de 45 días ni se limita el
resultado a 100 % para reconstruir la conversión: esas reglas vienen del núcleo
mensual.

La cadena que la propuesta exige es:

```text
crm.metricas_vendedores_fn
  → crm.conversion_mensual_fn
  → crm.conversion_mensual_sin_cartera_fn
  → private.conversion_mensual_por_vendedor
  → private.conversion_episodios
```

El coordinador conserva el contrato histórico de `vendedores=[]` y
`equipos=[]`; no llama a `conversion_mensual_fn`, que correctamente lo deniega.

Antes de convertir ausencias en cero, la propuesta compara el array mensual
contra `private.roster_metas_vendedores()` recortado al alcance del actor. Debe
existir exactamente una fila por vendedor canónico visible y su
`supervisor_id` debe ser idéntico al del roster. La función falla con 55000 ante
duplicados, vendedor esperado faltante, fila extra o supervisor inesperado.

La comparación no se hace contra todo `crm.equipo`: ese conjunto también
incluye supervisores, gerencia, inactivos visibles y vendedores sin supervisor
válido. El wrapper mensual representa únicamente vendedores activos con
supervisor activo; la producción fuera de roster permanece anónima en
`cobertura.fuera_de_roster`. Además, `metricas_vendedores_fn` siempre consulta
el mes en curso y `cerrar_periodo` prohíbe sellarlo. La propuesta comprueba
también que no exista un sello actual anómalo antes de llamar al wrapper, por lo
que no mezcla una foto histórica con un roster vivo aunque sus UUID coincidan.

## Orden de despliegue

1. Integrar main hasta `20260827193803` sin perder sus cambios de servidor ni
   frontend y volver a revisar el diff de C0.1.
2. Capturar en el servidor autorizado cuerpo, firma, owner, ACL, volatilidad,
   `SECURITY DEFINER`, `search_path` y dependencias de todas las funciones
   ancladas.
3. Comparar la captura con el estado esperado y resolver cualquier deriva.
4. Obtener aprobación expresa de Miguel sobre el SQL exacto y su banco.
5. Sustituir todos los placeholders live y fijar el hash del cuerpo final.
6. Crear una migración nueva posterior a la última vigente; no editar ninguna
   migración histórica.
7. Ejecutar el banco completo y los mutantes en una base local desechable.
8. Aplicar primero el servidor y verificar su readback.
9. Publicar después el frontend. El frontend nuevo exige los campos exactos de
   `equipos`, por lo que desplegarlo antes haría fallar el parseo del payload.

## Compatibilidad con F1.3 (`20260827193803`, main `abb8240`)

El artefacto F0 está deliberadamente sin rebase (`3fa7856`). La migración F1.3,
ya aplicada en producción, reemplaza solo
`private.metricas_conversiones_implementacion(date,date)` para que
`produccion.capital_pen/capital_usd` use los caminos vivos de cierres y añade
`produccion.sin_rastro`. No modifica `crm.metricas_vendedores_fn`, el wrapper
mensual, el roster ni las once funciones que C0.1 ancla; por eso no se agrega un
placeholder artificial para F1.3.

La frontera semántica es obligatoria:

- `metricas_vendedores_fn.capital_pen/capital_usd` sigue siendo capital
  estimado de leads abiertos, por vendedor/equipo;
- F1.3 `produccion.capital_pen/capital_usd` es capital ya producido por perfiles
  nacidos de leads más cierres externos, y `sin_rastro` declara sus huecos.

No deben fusionarse ni sustituirse entre sí. F1.3 declara además que sus
capitales por origen/responsable siguen pendientes de F1.3b; C0.1 no intenta
resolver esa deuda. Antes de materializar la migración C0.1 se debe integrar
main, preservar sus cambios de frontend, volver a ejecutar la captura live y
recalcular todos los hashes/checksums sobre el árbol rebasado.

El rebase no es mecánico: F0 y `3fa7856..abb8240` tocan a la vez
`hoy/gerencia.tsx`, `hoy/inteligencia-comercial.tsx` y su prueba, y
`hoy/resumen-gerencia.tsx` y su prueba. Esos conflictos deben conservar tanto
los rótulos/capital vivo ya publicados como el contrato exacto de conversión;
elegir un lado completo perdería una de las dos semánticas.

## Hashes estáticos del worktree — NO PRODUCCIÓN

Estos valores se calcularon desde los cuerpos presentes en el worktree
`/private/tmp/crm-conversion-stabilization-f0-20260827`. Son evidencia local y
no deben sustituir automáticamente las anclas live del SQL.

| Función | md5(prosrc) local |
|---|---|
| crm.metricas_vendedores_fn() | 87998c3b195d8f5e7197c579e71e5da9 |
| crm.conversion_mensual_fn(date) | d4a8294c2ce5c45cce8104143ce3508b |
| crm.conversion_mensual_sin_cartera_fn(date) | c7a7a103d6665acb9231976a3a2fcfa6 |
| private.conversion_mensual_por_vendedor(...) | 4816eeefabe34c3fc82a2ff2f18a1182 |
| private.conversion_episodios(...) | 34acbfa8f6838b5f0ca6d5aa17d85d2 |
| private.metricas_cartera_por_vendedor(date) | 8ac031c77f340328336df1c58cafa464 |
| private.roster_metas_vendedores() | 8e9e171919bc000b8ef38f61b8a7d66f |
| private.peso_referido_conversion(date) | db78c8acbb0b0ea0ac3b0d2f0d25e7de |
| private.ajuste_pendiente_por_vendedor() | 7b44de923a64305b00a64b114143a1dd |
| private.conversion_con_ajuste(...) | e08142ff2df5d9e78b7d7bde4998fc6f |
| private.filtrar_desglose_sujetos_crm(...) | 1cce2929af369715a2c7e161d63fc7ce |

## Banco de pruebas propuesto

Crear, únicamente después de la aprobación, un banco nuevo sobre el esquema
completo vigente:

- `C0.1-banco-adversario.sql` en este mismo directorio durante F0;
- `C0.1-banco-runner-plan.md` en este mismo directorio durante F0;
- solo después de aprobar C0.1 se portarán a
  `supabase/scripts/test-c0-1-metricas-equipos.sql` y su runner local.

No modificar el banco histórico F2.4: deliberadamente reconstruye un estado
anterior al wrapper mensual y no carga roster, cartera ni ajustes actuales.

El fixture nuevo debe cubrir como mínimo:

- suma ponderada por equipo frente a promedio de porcentajes;
- referido con peso 0,15;
- operación de cartera y deduplicación cliente/mes;
- reasignación: atribución del ledger, no propietario actual;
- ajuste pendiente y suelo cero por vendedor antes de agregar;
- divisor cero con porcentaje JSON `null` y legacy `0`;
- precisión decimal, por ejemplo 38,33 %;
- valores superiores a 100 %, por ejemplo 300 %;
- equipo activo sin responsables, con todas las claves exactas presentes;
- responsable duplicado (también el mismo UUID con otra capitalización), array
  parcial, vendedor canónico visible faltante, `supervisor_id` cambiado y fila
  extra de supervisor/fuera-de-roster;
- producción fuera de roster excluida de equipos, sin identidad inventada;
- paridad dinámica contra `conversion_mensual_fn()->responsables`;
- vendedor, supervisor, gerencia, Directorio, coordinador, actor inactivo y anon;
- owner postgres, ACL allowlist, stable, definer y `search_path=""`;
- conservación de activos/capital sobre leads abiertos y del marcador legacy
  de 45 días, sin reutilizarlo como ventana de la conversión mensual.

Los mutantes deben reintroducir y detectar: fórmula `convertidos/asignados`,
promedio de porcentajes, propietario actual, omisión de cartera, cartera sumada
a `convertidos`, ajuste ignorado o agregado incorrectamente, NULL convertido a
cero, redondeo entero, cap a 100 %, operación duplicada, fuera-de-roster dentro
de un equipo, ausencia de cualquiera de las cuatro claves exactas y eliminación
de cualquiera de las guardas de cobertura exacta.

## Contrato y consumidor

Cada fila real de `equipos` debe contener obligatoriamente:

- `operaciones_cartera`: número;
- `nucleo_divisor`: número;
- `nucleo_numerador`: número;
- `nucleo_conversion_pct`: número o NULL.

`conversion_pct` permanece como entero/0 solo para compatibilidad de wire.
`convertidos` cuenta cierres de lead; cartera viaja aparte.

Directorio debe leer “Cierres del mes” desde `resumen.totales.convertidos`, no
desde el objeto legado `resumen.conversion`, y no debe rotular el contador
mensual como parte de la ventana de capital ganado de 45 días.
