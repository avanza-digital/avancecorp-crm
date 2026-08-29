# Propuesta C0.1: métricas por equipo desde el núcleo único

> **NO EJECUTAR EL ARTEFACTO CON PLACEHOLDERS.** La propuesta de este directorio
> sigue siendo revisable y fail-closed. R5 ya materializó una migración exacta
> con las anclas capturadas del servidor, pero no la aplicó a producción. Tanto
> esa migración como el frontend requieren aprobación expresa de Miguel antes
> de publicarse.

Artefactos revisables:

- `C0.1-metricas-vendedores-nucleo-unico.sql`
- `C0.1-metricas-vendedores-nucleo-unico.rollback.sql`
- `C0.1-banco-adversario.sql`
- `C0.1-banco-runner-plan.md`
- `README.md`

## Estado R5 verificado — 2026-08-28

- R5 parte del release F6 vivo y conserva su historia como ancestro.
- La captura autorizada comparó 18/18 cuerpos live contra las migraciones
  canónicas y fijó el fingerprint de catálogo
  `91029038fb842066de0c29443d599715`.
- La migración nueva es
  `20260828173154_crm_c0_1_metricas_vendedores_nucleo_unico.sql`, SHA-256
  `f232306bb088ec6e71bd3fcefd953fb4609f3f8d3e30e2ea916599f2ddd8bf14`.
- Un historial remoto aislado confirmó por dry-run que `db push` propondría
  exclusivamente esa migración.
- El SQL completo se ejecutó contra la base viva dentro de una transacción con
  `ROLLBACK`; las 18 huellas quedaron idénticas al terminar.
- El rollback exacto, SHA-256
  `d258702ebd704a2a182fa4eaafb46b7dbf22a22a0b18819958456125d5358f94`,
  aprobó en PostgreSQL 17 el roundtrip `forward → rollback → forward`; una
  segunda reversa fue rechazada por la guarda de estado candidato.
- El banco volvió a quedar verde con 17/17 mutantes cazados. El frontend aprobó
  182/182 archivos, 2.430/2.430 pruebas unitarias y la suite E2E completa:
  107 pasaron y 26 quedaron omitidas por diseño, sin fallos.

Nada de lo anterior equivale a producción aplicada. Falta la aprobación final,
publicar el frontend puente, aplicar la única migración y ejecutar readback
PostgREST/JWT, rendimiento y logs en vivo.

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

Las dos rutas que la propuesta exige terminan en el mismo núcleo:

```text
crm.metricas_vendedores_fn
  ├─→ crm.conversion_mensual_fn
  │     → crm.conversion_mensual_sin_cartera_fn
  │     → private.conversion_mensual_por_vendedor
  │     → private.conversion_episodios
  └─→ private.metricas_cartera_por_vendedor
        → private.conversion_episodios
```

La segunda ruta reemplaza la deduplicación local de cartera: sus tres conteos
se obtienen de la pierna `tipo='operacion'` de episodios. El ledger
`crm.operaciones_cartera` permanece como fuente económica de importes y
desgloses, no como una segunda autoridad de conversión.

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

1. Integrar main hasta `20260827220132` (F1.3b) y el `HEAD` canónico
   `7c94d77`, sin perder sus cambios de servidor ni frontend, y volver a
   revisar el diff de C0.1. Este rebase ya se ejecutó en el candidato local.
2. Capturar en el servidor autorizado cuerpo, firma, owner, ACL, volatilidad,
   `SECURITY DEFINER`, `search_path` y dependencias de todas las funciones
   ancladas.
3. Comparar la captura con el estado esperado y resolver cualquier deriva.
4. Obtener aprobación expresa de Miguel sobre el SQL exacto y su banco.
5. Sustituir los 21 placeholders —18 cuerpos live, un fingerprint de catálogo
   y los dos cuerpos candidatos— en una copia exacta, nunca en este artefacto.
6. Crear una migración nueva posterior a la última vigente; no editar ninguna
   migración histórica.
7. Reproducir todas las migraciones vigentes en una base compatible y ejecutar
   allí el banco completo y los mutantes. El runner PG17 focal ya da evidencia
   rápida, pero no sustituye esta reproducción integral.
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

## Compatibilidad con F1.3b (`20260827220132`, base canónica `7c94d77`)

El artefacto F0 fue rebasado de forma controlada sobre F1.3b. F1.3 corrigió
`produccion.capital_pen/capital_usd` y añadió `produccion.sin_rastro`; F1.3b
mantiene byte a byte ese núcleo de conversiones y amplía la misma función
`private.metricas_conversiones_implementacion(date,date)` con capital vivo por
origen y vendedor, además de la sonda opcional
`perfiles_con_leads_de_varios_vendedores`. Ninguna de las dos migraciones
modifica `crm.metricas_vendedores_fn`, el wrapper mensual, el roster ni las
dieciocho funciones que C0.1 ancla; por eso no se agrega un placeholder
artificial para F1.3/F1.3b.

La frontera semántica es obligatoria:

- `metricas_vendedores_fn.capital_pen/capital_usd` sigue siendo capital
  estimado de leads abiertos, por vendedor/equipo;
- F1.3/F1.3b `produccion.capital_pen/capital_usd` y los desgloses por
  origen/vendedor son capital ya producido por perfiles nacidos de leads más
  cierres externos; `sin_rastro` declara sus huecos.

No deben fusionarse ni sustituirse entre sí. El rebase conservó el capital vivo
de F1.3b independientemente del gate fail-closed de conversión: una sonda
inválida oculta porcentajes, no contratos ya atribuidos. Antes de materializar
la migración C0.1 todavía se deben capturar las huellas live autorizadas y
recalcular los hashes del cuerpo candidato definitivo; ningún hash local
sustituye ese readback.

## Hashes estáticos del worktree — NO PRODUCCIÓN

Estos valores se calcularon desde los cuerpos presentes en el worktree
`/private/tmp/crm-c01-nucleo-unico-20260827`. Son evidencia local y
no deben sustituir automáticamente las anclas live del SQL.

Además de estos dieciocho hashes live de cuerpo, el preflight exige un fingerprint
live único y ordenado de firma/resultado, owner, lenguaje, clase de función,
`SECURITY DEFINER`, leakproof/strict/set-returning, volatilidad, paralelismo,
`proconfig` y ACL directo normalizado de las dieciocho firmas. El RPC público
comprueba además privilegios efectivos de `authenticated`, `anon` y
`service_role`, incluidas membresías. No existe valor local sustitutivo para el
fingerprint: debe capturarse en el mismo servidor y momento que los cuerpos
autorizados.

| Función | md5(prosrc) local |
|---|---|
| crm.metricas_vendedores_fn() — baseline extraída | 87998c3b195d8f5e7197c579e71e5da9 |
| crm.metricas_vendedores_fn() — candidato C0.1 | d8226991aba1783b042eaf087568ba49 |
| crm.conversion_mensual_fn(date) | d4a8294c2ce5c45cce8104143ce3508b |
| crm.conversion_mensual_sin_cartera_fn(date) | c7a7a103d6665acb9231976a3a2fcfa6 |
| private.conversion_mensual_por_vendedor(...) | 4816eeefabe34c3fc82a2ff2f18a1182 |
| private.conversion_episodios(...) | 34acbfa8f6838b5f0ca6d5aa17d85d2 |
| private.metricas_cartera_por_vendedor(date) — baseline extraída | 8ac031c77f340328336df1c58cafa464 |
| private.metricas_cartera_por_vendedor(date) — candidato C0.1 | a5ec29bd68511a286a3d2ea4d316a9be |
| crm.metricas_cartera_fn(date) | 0b4ede547cf7079be1e56073311453b3 |
| private.roster_metas_vendedores() | 8e9e171919bc000b8ef38f61b8a7d66f |
| private.vendedores_sin_supervisor() | 41bc7077a9be1e23f63637b98db82cd2 |
| private.peso_referido_conversion(date) | db78c8acbb0b0ea0ac3b0d2f0d25e7de |
| private.ajuste_pendiente_por_vendedor() | 7b44de923a64305b00a64b114143a1dd |
| private.conversion_con_ajuste(...) | e08142ff2df5d9e78b7d7bde4998fc6f |
| private.filtrar_desglose_sujetos_crm(...) | 1cce2929af369715a2c7e161d63fc7ce |
| private.rol_crm(uuid) | 2afc1b09b6cf71b10d791fbcae583d2d |
| private.es_lector_global() | d9e6238020882c2b2a7d0fb3b76305c1 |
| private.vendedor_ids_visibles(uuid) | 33ece9bae4828f7ffdb837c6128ca9d6 |
| private.cierre_externo_anulado(uuid) | 4f9d9c03e53497b8b84b80299e35b3cb |
| private.cierre_anulado(uuid) | dce6f9bf34feb57a2f1662ad401d1047 |

Las anclas añadidas cierran llamadas transitivas reales. En cambio,
`private.etiqueta_mes_es(date)` no se ancla porque es invoker/immutable y su
rótulo no forma parte de la salida de esta RPC. `private.cierre_mes_visible` no
se ancla mientras C0.1 consulte exclusivamente el mes vigente y aborte ante un
sello vigente anómalo; si la firma acepta períodos históricos, debe incorporarse
al preflight antes de materializar el cambio.

La propuesta bloquea las dieciocho funciones concretas durante todo el intervalo
preflight→DDL→postflight mediante un `ALTER FUNCTION ... COST` que conserva el
valor vivo pero fuerza `CatalogTupleUpdate` sobre cada fila de `pg_proc`. Verifica
el `xmin` del XID actual al tomar cada exclusión y justo antes de `COMMIT`; un
advisory lock transaccional complementario serializa despliegues C0.1
cooperativos. Supabase administrado no permite bloquear directamente
`pg_namespace`, `pg_authid` ni `pg_auth_members`: sus ACL, atributos y membresías
se revalidan completos antes y después del DDL, y producción requiere una ventana
operativa sin cambios de identidad/esquema y readback inmediato. Cualquier
diferencia en cuerpos, metadatos/ACL, privilegios efectivos o cadena transitiva
aborta.

## Banco de pruebas local

El banco y el runner focal ya están materializados:

- `C0.1-banco-adversario.sql` contiene fixture y oráculos transaccionales;
- `C0.1-banco-runner-plan.md` documenta alcance, mutantes y gates;
- `CRM-Avance-Corp/supabase/scripts/run-test-c0-1-local.sh` crea su propio
  PostgreSQL 17 sin TCP, captura los 21 placeholders en copias temporales,
  aplica los dos cuerpos y ejecuta el banco en otra sesión;
- el bootstrap es mínimo y los cuerpos de negocio se extraen de migraciones
  canónicas. No es una reproducción de todas las migraciones ni de Supabase,
  PostgREST o RLS reales.

Resultado certificado local del 2026-08-28: PostgreSQL 17.10, socket Unix
privado sin TCP, 21 placeholders materializados, caso real y mutantes internos
verdes, un único `C0.1_BANCO_ADVERSARIO_OK`, matriz de cuerpos 17/17 y roundtrip
del rollback exacto. El cleanup no dejó directorios, bases ni clústeres C0.1.
El check integral del frontend aprobó 182/182 archivos y 2.430/2.430 pruebas,
además de tipos, lint, build, bundle y duplicación. La suite E2E aprobó 107
casos, omitió 26 por diseño y no tuvo fallos. Es evidencia focal local; no
autoriza una migración ni una publicación productiva.

No modificar el banco histórico F2.4: deliberadamente reconstruye un estado
anterior al wrapper mensual y no carga roster, cartera ni ajustes actuales.

El fixture cubre como mínimo:

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
- conjuntos exactos para vendedor, supervisor, gerencia, Directorio CRM y
  Directorio Portal sin fila CRM; coordinador, actor inactivo, Admin/Superadmin
  solo Portal, `anon` y `service_role` como casos fail-closed;
- owner postgres, ACL allowlist directa/efectiva, ACL de esquemas, stable,
  definer y `search_path=""`; además, `crm` expuesto y `private` excluido en la
  configuración PostgREST local;
- conservación de activos/capital sobre leads abiertos y del marcador legacy
  de 45 días, sin reutilizarlo como ventana de la conversión mensual.
- cuenta operativa de cinco directos en S1, incluido un coordinador no vendedor,
  tres abiertos y S/ 3.000; la cobertura mensual sigue limitada al roster de
  vendedores;
- identidad del total global para divisor, cierres, numerador y cartera:
  responsables más producción fuera de roster, sin atribuir esa producción a
  un equipo.

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
