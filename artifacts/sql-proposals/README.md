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
`cobertura.fuera_de_roster`. Si esa persona todavía pertenece a la foto
operativa amplia, su fila conserva activos/capital pero las cinco claves del
bundle mensual quedan explícitamente en NULL; no se fabrican ceros. Además,
`metricas_vendedores_fn` siempre consulta
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
8. Publicar el frontend puente F0. Reconoce exactamente el contrato F2.4b
   vigente: sin las dos raíces, cuatro claves mensuales en `vendedores` (todavía
   sin `nucleo_convertidos`) y ninguna en `equipos`. Conserva la foto operativa
   y oculta ese bundle legacy completo; no reutiliza sus cifras. Otra combinación,
   una sola raíz o un bundle parcial falla cerrado.
9. Con aprobación separada, aplicar C0.1 en servidor y verificar readback. Al
   aparecer juntas `cobertura_conversion` y `nucleo_total`, el mismo frontend
   exige las cinco claves exactas completas en total, vendedores y equipos.
10. Ejecutar paridad por rol y snapshot a través de PostgREST/JWT antes de dar
    por cerrado C0.1. Solo después puede evaluarse retirar el puente legacy.

## Compatibilidad con F1.3 (`20260827193803`, main `abb8240`)

El artefacto F0 ya fue rebasado de forma controlada sobre `abb8240`; el SHA de
entrada a esta auditoría final fue `0ac9f34`. La migración F1.3, ya documentada
como aplicada en producción por su sesión propietaria, reemplaza solo
`private.metricas_conversiones_implementacion(date,date)` para que
`produccion.capital_pen/capital_usd` use los caminos vivos de cierres y añade
`produccion.sin_rastro`. No modifica `crm.metricas_vendedores_fn`, el wrapper
mensual, el roster ni las dieciséis funciones que C0.1 ancla; por eso no se agrega un
placeholder artificial para F1.3.

La frontera semántica es obligatoria:

- `metricas_vendedores_fn.capital_pen/capital_usd` sigue siendo capital
  estimado de leads abiertos, por vendedor/equipo;
- F1.3 `produccion.capital_pen/capital_usd` es capital ya producido por perfiles
  nacidos de leads más cierres externos, y `sin_rastro` declara sus huecos.

No deben fusionarse ni sustituirse entre sí. F1.3 declara además que sus
capitales por origen/responsable siguen pendientes de F1.3b; C0.1 no intenta
resolver esa deuda. El rebase conservó tanto los rótulos/capital vivo de F1.3
como el contrato exacto de conversión. Antes de materializar la migración C0.1
todavía se deben capturar las huellas live autorizadas y recalcular los hashes
del cuerpo candidato definitivo; ningún hash local sustituye ese readback.

## Hashes estáticos del worktree — NO PRODUCCIÓN

Estos valores se calcularon desde los cuerpos presentes en el worktree
`/private/tmp/crm-conversion-stabilization-f0-20260827`. Son evidencia local y
no deben sustituir automáticamente las anclas live del SQL.

Además de estos dieciséis hashes de cuerpo, el preflight exige un fingerprint
live único y ordenado de owner, `SECURITY DEFINER`, volatilidad, `proconfig` y
ACL directo normalizado de las dieciséis firmas. El RPC público comprueba además
privilegios efectivos de `authenticated`, `anon` y `service_role`, incluidas
membresías. No existe valor local sustitutivo para el fingerprint: debe
capturarse en el mismo servidor y momento que los cuerpos autorizados.

| Función | md5(prosrc) local |
|---|---|
| crm.metricas_vendedores_fn() — cuerpo candidato C0.1 | c8aa860ad9da6aebdf5b482845800a62 |
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
| private.rol_crm(uuid) | 2afc1b09b6cf71b10d791fbcae583d2d |
| private.es_lector_global() | d9e6238020882c2b2a7d0fb3b76305c1 |
| private.vendedor_ids_visibles(uuid) | 33ece9bae4828f7ffdb837c6128ca9d6 |
| private.cierre_externo_anulado(uuid) | 4f9d9c03e53497b8b84b80299e35b3cb |
| private.cierre_anulado(uuid) | dce6f9bf34feb57a2f1662ad401d1047 |

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
- producción fuera de roster excluida de equipos y fila operativa con bundle
  mensual íntegramente NULL, no cero disponible;
- `cobertura_conversion` literal y proyección exacta renombrada del total del
  wrapper: incluye la producción anónima fuera de roster y no se recompone
  sumando equipos;
- política de publicación única: `medible` y `mes_parcial` muestran; ausencia de
  ledger, motivo de roster o `cierres_sin_episodio > 0` dejan los bundles exactos
  íntegramente NULL sin borrar activos/capital;
- perfil público inactivo excluido del roster y supervisor no efectivo omitido;
- paridad dinámica contra `conversion_mensual_fn()->responsables`;
- vendedor, supervisor, gerencia, Directorio, coordinador, actor inactivo y anon;
- owner postgres, ACL allowlist, stable, definer y `search_path=""`;
- conservación de activos/capital sobre leads abiertos y del marcador legacy
  de 45 días, sin reutilizarlo como ventana de la conversión mensual.

Los mutantes deben reintroducir y detectar: fórmula `convertidos/asignados`,
promedio de porcentajes, propietario actual, omisión de cartera, cartera sumada
a `convertidos`, ajuste ignorado o agregado incorrectamente, NULL convertido a
cero, redondeo entero, cap a 100 %, operación duplicada, fuera-de-roster dentro
de un equipo, ausencia de cualquiera de las cinco claves exactas y eliminación
de cualquiera de las guardas de cobertura exacta.

## Contrato y consumidor

Para vendedor, supervisor, gerencia y Directorio, C0.1 emite las dos raíces juntas:
`cobertura_conversion`, copia literal de la cobertura del wrapper, y
`nucleo_total`, proyección exacta con nombres del contrato de Gestión. El servidor
F2.4b anterior no emite ninguna raíz, pero sí cuatro claves mensuales en cada
vendedor y cero en equipos; esa forma exacta es el único estado legacy aceptado
por el puente y se oculta por completo. Una sola raíz o cualquier otra mezcla es
contrato incompleto.

El coordinador es la única excepción explícita: también emite ambas raíces, pero
`cobertura_conversion` es JSON `null` y las cinco claves de `nucleo_total` son
JSON `null`, junto con `vendedores=[]` y `equipos=[]`; no invoca el wrapper que
ese rol no tiene autorizado.

`nucleo_total` y cada fila real de `vendedores` y `equipos` contienen como bundle:

- `nucleo_convertidos`: número o NULL;
- `operaciones_cartera`: número o NULL;
- `nucleo_divisor`: número o NULL;
- `nucleo_numerador`: número o NULL;
- `nucleo_conversion_pct`: número o NULL.

En una fila canónica, las primeras cuatro magnitudes son números —incluido
cero— y solo el porcentaje es NULL cuando el divisor vale cero. En una fila
operativa fuera del roster mensual, las cinco son NULL como un único bundle;
una mezcla parcial se rechaza. `conversion_pct` y `convertidos` permanecen
numéricos solo para compatibilidad transitoria de wire; la UI nueva usa
`nucleo_convertidos` y el resto del bundle exacto. Cartera viaja aparte.

Si la cobertura es publicable, las primeras cuatro magnitudes de `nucleo_total`
son necesariamente numéricas; el total jamás representa una fila fuera de
roster. Directorio lee “Cierres del mes” desde ese `nucleo_total`, no desde
`resumen.totales.convertidos`, el objeto legado `resumen.conversion` ni la suma
de equipos, y no rotula el contador mensual como parte de la ventana de capital
ganado de 45 días.
