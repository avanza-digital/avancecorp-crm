VERDICT:
CHANGES_REQUESTED

SUMMARY:
La consulta v2 está bien construida en lo que más importaba del pedido: los filtros de empresa/mes/moneda/estado se aplican a **una misma fuente** (CTE `fuentes_filtradas`, líneas 43‑52) en vez de `EXISTS` independientes, el recorte ocurre antes de paginar, los totales se calculan sobre `filtradas` (no sobre la página), PEN/USD nunca se suman, no hay cálculo de comisiones, y el núcleo de visibilidad/flags (`cartera_f5_exigir`, `cartera_f5_personas_visibles`, `cartera_f5_fuentes_reales`) no se toca. El reuso del mismo núcleo para v1 es la decisión arquitectónica correcta.

Los hallazgos accionables no están en el álgebra de filtros sino en tres frentes: (a) el bloque de despliegue al final de la migración (líneas 138‑151) modifica la identidad de ejecución y los grants de una función **ya publicada**, y no contempla una firma previa de `private.cartera_f5_listar`; (b) para el lector global (Directorio) el predicado «sin inversiones» se evalúa contra el conjunto ya restringido a Avance, produciendo una etiqueta comercial falsa; (c) huecos de test y de UX/a11y concretos. Ninguno de estos exige rediseño; sí exigen comprobaciones previas a instalar el SQL.

No apruebo producción: por el propio reporte del PRIMARY, `http.mjs`, build/gates finales y la repetición de advisors tras fijar el owner siguen en curso, y el run completo solo pasó limitando a 4 workers tras una contaminación posterior a timeout.

FINDINGS:

[P1] Cambiar el owner de una SECURITY DEFINER ya publicada cambia su identidad de ejecución en producción

File:
CRM-Avance-Corp/supabase/migrations/20260916023055_crm_cartera_filtros_comerciales.sql

Lines:
140‑142 (en particular 142)

Problem:
`alter function crm.cartera_inversionistas_fn(...) owner to postgres` se aplica a una función `security definer` que **ya está en producción y en uso por el front publicado**. Cambiar el propietario cambia el rol bajo el cual se ejecuta todo su cuerpo, incluidos `public.perfiles`, `crm.*` y el núcleo `private.*`.

Evidence:
Línea 128: `returns jsonb language sql security definer set search_path=''`. Línea 142: `alter function crm.cartera_inversionistas_fn(integer,integer,text,text,uuid,boolean) owner to postgres;`. El comentario de las líneas 138‑139 justifica el cambio por el EXECUTE sobre el núcleo privado, pero el `alter owner` tiene el efecto colateral de reasignar la identidad de ejecución, no solo resolver el EXECUTE. El propio PRIMARY reporta que el owner fue «detectado por prueba v1», es decir, en local el owner previo **no** era el que asume la migración.

Impact:
Si en producción el owner actual es `supabase_admin` y pasa a `postgres`, cualquier tabla con RLS activa que hoy se recorre sin política pasa a evaluarla. El modo de fallo no es un error visible sino **menos filas** en v1 y v2: cartera parcialmente vacía o totales de capital subestimados, para todos los roles, sin excepción ni log. El riesgo inverso (elevar privilegios respecto del owner previo) también existe.

Recommendation:
Antes de instalar, capturar en la instancia real el estado previo y decidir explícitamente:
`select p.oid::regprocedure, pg_get_userbyid(p.proowner) owner, p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('crm','private') and p.proname in ('cartera_inversionistas_fn','cartera_inversionistas_filtrada_fn','cartera_f5_listar','cartera_f5_personas_visibles','cartera_f5_fuentes_reales','cartera_f5_exigir');`
Si el owner previo de `cartera_inversionistas_fn` no es `postgres`, no reasignarlo por arrastre: resolver el EXECUTE con `grant execute on function private.cartera_f5_listar(...) to <owner_previo>` y dejar el owner intacto. Si se decide cambiarlo, comparar filas y totales de v1 con el mismo JWT antes y después del `alter owner` (no solo antes y después del `create or replace`), y registrar el owner previo en `reversa.sql`.

[P1] La migración no contempla una firma previa de `private.cartera_f5_listar`; `revoke`/`alter owner` solo alcanzan la firma de 12 argumentos

File:
CRM-Avance-Corp/supabase/migrations/20260916023055_crm_cartera_filtros_comerciales.sql

Lines:
4‑11, 140, 143‑144

Problem:
`create or replace function` solo reemplaza una función con **la misma lista de parámetros**. Si ya existe `private.cartera_f5_listar` con otra aridad (la que hoy sirve a v1), esta migración no la reemplaza: crea una sobrecarga y deja la anterior instalada, con su owner y sus grants originales.

Evidence:
El README declara que `preparar.mjs` «restaura en la copia la definición anterior antes de comparar v1» (README líneas 36‑37), es decir, existe un lector v1 previo. Las líneas 140 y 143‑144 califican exclusivamente `private.cartera_f5_listar(integer,integer,text,text,uuid,boolean,text,text,text,text,boolean,boolean)`. No hay ningún `drop function` en el archivo.

Impact:
Queda una función privada huérfana con permisos antiguos y lógica divergente, que no recibe ninguno de los `revoke` de la línea 143. Si su grant previo incluía `authenticated`, es una superficie ejecutable que sobrevive a la migración y que la reversa tampoco contempla. Además convierte la migración en no reproducible: reinstalar deja dos definiciones.

Recommendation:
Antes de instalar, enumerar las firmas existentes:
`select p.oid::regprocedure, pg_get_userbyid(p.proowner) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='cartera_f5_listar';`
Si aparece más de una, añadir el `drop function` explícito de la firma antigua (con su lista de tipos completa) y verificar después que queda exactamente una fila. Marcar como hipótesis solo la existencia de la sobrecarga; la ausencia del `drop` defensivo es un hecho del archivo.

[P1] Para el lector global, «sin inversiones» significa «sin inversiones Avance», y el test lo deja pasar vacuamente

File:
CRM-Avance-Corp/supabase/migrations/20260916023055_crm_cartera_filtros_comerciales.sql

Lines:
42, 60‑63, 88‑89, 98‑99

Problem:
El CTE `fuentes` ya está recortado a Avance para el lector global (línea 42). Todos los predicados de «ausencia de inversiones» se evalúan sobre ese CTE recortado, no sobre el universo real de fuentes de la persona.

Evidence:
Línea 42: `where not v_lector or f.empresa='avance'`.
Línea 60: `not exists(select 1 from fuentes f where f.inversionista_id=p.inversionista_id)`.
Línea 88‑89: `'sin_inversiones_total', (select count(*) from filtradas p where not exists (select 1 from fuentes f ...))`.
Línea 99: `select distinct f.empresa from fuentes f where f.inversionista_id=p.inversionista_id`.
Una persona visible para Directorio (perfil Avance autorizado) cuyas fuentes sean todas Qorilazo/Prodelco satisface `not exists` sobre `fuentes` y entra por la rama de la línea 60.

Impact:
Directorio ve esa persona con `empresas: []`, `resumen: []`, la UI imprime literalmente «Sin inversiones» (`cartera-inversionistas.tsx:175`), el contador «N sin inversiones» (`cartera-inversionistas.tsx:156`) la incluye, y el filtro «Sin inversiones» la devuelve. Es una afirmación comercial falsa presentada a la audiencia de mayor nivel. No es una fuga —el recorte es hacia menos información—, pero sí un dato erróneo.

Evidence de que el banco no lo detecta:
`filtros.test.mjs:90`: `assert(d.filas.every(p=>p.empresas.every(e=>e==='avance') && p.resumen.every(r=>r.empresa==='avance')))`. Sobre `empresas: []` y `resumen: []`, ambos `.every()` son vacuamente verdaderos. El test 'Directorio conserva solo Avance…' (líneas 87‑94) no asserta `sin_inversiones_total` ni `filas.length` por persona.

Recommendation:
Evaluar la ausencia contra el conjunto no recortado por `v_lector` (un CTE `fuentes_persona` sin la condición de la línea 42, usado solo en las líneas 60 y 88‑89), o —si la decisión de producto es no revelar a Directorio ni siquiera la existencia de inversiones no‑Avance— excluir explícitamente esas personas de la rama de la línea 60 en modo lector y renombrar la etiqueta a «Sin inversiones Avance». Añadir un caso que cree una persona con perfil Avance autorizado y fuente exclusivamente Qorilazo, y asserte el comportamiento elegido para `total`, `sin_inversiones_total` y `filas`.

[P2] `revoke all … from service_role` puede eliminar un grant de producción existente

File:
CRM-Avance-Corp/supabase/migrations/20260916023055_crm_cartera_filtros_comerciales.sql

Lines:
147‑150

Problem:
Se revoca `crm.cartera_inversionistas_fn` de `service_role` y solo se vuelve a otorgar a `authenticated`. La función es preexistente y publicada.

Evidence:
Línea 147‑148 revoca de `public,anon,authenticated,service_role`; la línea 150 solo repone `authenticated`.

Impact:
Cualquier Edge Function, script o job que hoy llame la RPC con la service key pasa a recibir 42501 después de la migración, sin aviso y sin que el banco local lo cubra (`filtros.test.mjs:122‑130` prueba anon/coordinador/cliente/inactivo, no `service_role`).

Recommendation:
Capturar los grants actuales antes de instalar (`select grantee, privilege_type from information_schema.role_routine_grants where routine_schema='crm' and routine_name='cartera_inversionistas_fn';`) y reponer exactamente lo que existía, o confirmar por búsqueda que ningún consumidor server‑side la invoca.

[P2] El DTO se construye por denylist: cualquier columna futura de `personas_visibles` se publica al cliente

File:
CRM-Avance-Corp/supabase/migrations/20260916023055_crm_cartera_filtros_comerciales.sql

Lines:
97

Problem:
`to_jsonb(p)-'perfil_ids'-'lead_ids'-'perfil_id'` expone todo lo que devuelva `cartera_f5_personas_visibles()` menos tres claves conocidas.

Evidence:
Línea 97. El comentario de `inversionistas.ts:1` («Ningún UUID de perfil sustituye a la persona») indica que la exclusión es una decisión de seguridad deliberada, pero está expresada como resta de claves.

Impact:
Si el núcleo añade mañana `supervisor_id`, `dni_hash` o similar, viaja al navegador sin cambios en esta migración. El guardarraíl del cliente no lo detecta: `v.object` de valibot ignora claves desconocidas, así que `CarteraInversionistasSchema` (`inversionistas.ts:30‑39`) acepta el campo extra en silencio. Aplica igual a v1, que hereda la fila (líneas 130‑133).

Recommendation:
Proyectar explícitamente las columnas en `filtradas`/`pagina` (allowlist), o construir la fila con `jsonb_build_object` de los 12 campos de `Identidad` (`inversionistas.ts:20‑25`). Alternativa mínima: un test que compare `jsonb_object_keys` de una fila contra la lista exacta esperada.

[P2] `p_mes='sin_fecha'` no tiene ningún test, pese a tener dos ramas propias

File:
CRM-Avance-Corp/supabase/scripts/cartera-filtros/filtros.test.mjs

Lines:
25‑34, 131‑137 (ausencia)

Problem:
El valor `sin_fecha` atraviesa dos ramas exclusivas —línea 49 de la migración (`p_mes='sin_fecha' and f.fecha_comercial is null`) y línea 63 (`p_mes is distinct from 'sin_fecha'`, que **excluye** a los clientes sin inversiones)— y no aparece en ningún caso del banco.

Evidence:
Los casos de mes cubren `'2026-07'`, `'2026-09'` (líneas 26, 31, 63), y los inválidos `'2026-13'`, `'0000-01'`, `'2026-09-01'`, `''` (línea 132). `sin_fecha` no figura.

Impact:
La opción está expuesta en la UI (`cartera-inversionistas-filtros.tsx:29`) y decide si los clientes sin inversiones aparecen o desaparecen. Una inversión de semántica ahí pasaría el gate completo sin detección.

Recommendation:
Añadir un caso con una fuente de `fecha_comercial is null` que asserte: (1) la persona aparece con `p_mes='sin_fecha'`; (2) `ultima_fecha_comercial` es `null`; (3) un cliente sin inversiones **no** aparece con `p_mes='sin_fecha'` pero **sí** con `p_mes='2026-09'`; (4) `sin_fecha` combinado con `p_empresa` sigue correspondiendo a la misma fuente.

[P2] Riesgo de duplicación de capital si `personas_visibles()` puede emitir un `inversionista_id` repetido

File:
CRM-Avance-Corp/supabase/migrations/20260916023055_crm_cartera_filtros_comerciales.sql

Lines:
38, 41, 80

Problem:
`fuentes` hace `join personas p using(inversionista_id)` (línea 41) e `importes` hace `fuentes_filtradas f join filtradas p using(inversionista_id)` (línea 80). Ambos joins asumen cardinalidad 1 en el lado persona.

Evidence:
Línea 38: `personas as materialized (select * from private.cartera_f5_personas_visibles())`, sin `distinct` ni garantía documentada de unicidad. Un supervisor visible por dos rutas (relación actual + ámbito) sería suficiente.

Impact:
`cantidad` y `capital_registrado` se multiplican por el número de filas duplicadas, en filas y en `totales`, **silenciosamente**. El guardarraíl del cliente solo protege el conteo de personas: `validarPaginaInversionistas` (`inversionistas.ts:97‑100`) compara `filas.length` y el `Set` de ids, así que detectaría filas duplicadas pero **no** un capital inflado si el duplicado cae fuera de la página vigente. Marco esto como hipótesis: no tengo la definición de `cartera_f5_personas_visibles()`.

Recommendation:
Confirmar la unicidad con `select inversionista_id, count(*) from private.cartera_f5_personas_visibles() group by 1 having count(*)>1` ejecutado como gerencia y como supervisor con dos vendedores a cargo. Si no está garantizada por construcción, aplicar `distinct on (inversionista_id)` en el CTE `personas` y añadir el assert al banco.

[P2] Coste por petición amplificado por el polling de 15 s

File:
CRM-Avance-Corp/app/src/data/inversionistas-queries.ts, CRM-Avance-Corp/supabase/migrations/20260916023055_crm_cartera_filtros_comerciales.sql

Lines:
queries 14‑18, 23‑26; migración 22‑23, 74, 90‑95, 105

Problem:
Cada respuesta recalcula `opciones_meses` y `opciones_responsables` sobre **todo el ámbito visible** (no sobre la selección ni sobre la página), ejecuta `cartera_f5_registrar('lista')` (una escritura) y admite `offset` de hasta 50 000 000.

Evidence:
`lecturaVigente` fija `refetchInterval: 15_000`, `staleTime: 0`, `gcTime: 0`, `refetchOnWindowFocus:'always'`, `refetchOnReconnect:'always'` (queries 14‑18), y `useInversionistas` lo hereda (línea 24). En la migración: líneas 90‑95 barren `fuentes`/`personas` completas en cada llamada; línea 105 escribe auditoría en cada llamada; línea 22 admite `p_pagina` hasta 1000000 y la línea 74 calcula `offset (p_pagina-1)*p_tamano` sin acotar contra `total`.

Impact:
Para gerencia con cartera grande: barrido completo del ámbito 4 veces por minuto por usuario conectado, más 4 filas de auditoría por minuto por usuario. Y un usuario `authenticated` legítimo puede pedir `p_pagina=1000000, p_tamano=50` repetidamente y forzar un offset de 50M por petición; la validación de la línea 22 acota el número, no el coste.

Recommendation:
(1) Acotar la página contra `total` (devolver la última página válida o rechazar cuando `(p_pagina-1)*p_tamano` supere un techo razonable, p. ej. 10 000). (2) Separar `opciones_meses`/`opciones_responsables` a una RPC de catálogo con su propio `staleTime` en React Query, o devolverlas solo cuando `p_pagina=1`. (3) Confirmar que `cartera_f5_registrar` deduplica o agrega; si escribe una fila por llamada, evaluar subir `refetchInterval` para esta consulta concreta.

[P2] El `aria-label` de la fila oculta el capital, el último cierre y el responsable a lectores de pantalla

File:
CRM-Avance-Corp/app/src/screens/cartera-inversionistas.tsx

Lines:
165‑183 (en particular 169‑170)

Problem:
El `<button>` de fila lleva `aria-label={`Abrir ficha de ${p.nombre}`}`. Un `aria-label` en un botón **sustituye** todo su contenido accesible.

Evidence:
Línea 170: `aria-label={`Abrir ficha de ${p.nombre}`}`. El contenido sustituido incluye documento (172), badges de empresas (173), el resumen de capital por empresa/moneda (175‑179), el último cierre (181) y el responsable + marca «No contactar» (182). La cabecera de columnas de la línea 165 es `aria-hidden`, así que tampoco aporta contexto.

Impact:
Con lector de pantalla, la cartera se percibe como una lista de nombres sin ningún dato comercial: capital, cierre, responsable y la advertencia «No contactar» son inaccesibles. Es justamente la información que esta tarea añade a la fila.

Recommendation:
Eliminar el `aria-label` y dejar que el contenido del botón provea el nombre accesible (añadiendo texto visualmente oculto para los prefijos de columna, como ya se hace en la línea 181 con `@4xl/cartera:hidden`), o mantener el label y exponer el resto con `aria-describedby` apuntando a los spans de datos. Conviene pasarlo por `revisor-a11y` con el resto del cambio.

[P2] En móvil, los filtros superiores se deshabilitan sin ninguna explicación visible

File:
CRM-Avance-Corp/app/src/components/app/cartera-inversionistas-filtros.tsx

Lines:
16, 27, 31, 45, 55, 59

Problem:
Al elegir «Sin inversiones» se deshabilitan Mes, Empresa, Moneda y «Por vencer» (línea 16 + `disabled={sinInversiones}`), pero el texto que lo explica está oculto por debajo del breakpoint `@lg`.

Evidence:
Línea 59: `<p className="hidden @lg/cartera:block">{sinInversiones ? 'Clientes que aún no tienen inversiones registradas.' : …}</p>`. El `Select` de estado que causa el bloqueo vive dentro del panel plegable `f5-mas-filtros` (líneas 36‑43), cerrado por defecto (`useState(false)`, línea 15), mientras que Mes y Empresa están en la fila siempre visible (líneas 26‑32).

Impact:
En el ancho móvil de 390 px que el PRIMARY reporta como verificado, el usuario ve «Mes de cierre» y «Empresa» inertes, con el panel que contiene la causa colapsado y sin texto de ayuda. La única pista es el contador «Más filtros (1)» de la línea 34.

Recommendation:
Mostrar el mensaje de la línea 59 también en móvil cuando `sinInversiones` es verdadero (quitar `hidden` en esa rama), o asociarlo a los selects deshabilitados con `aria-describedby` para que exista también en el árbol de accesibilidad.

[P2] Desmarcar «Por vencer en 30 días» no restaura el mes y deja la vista en «Todos»

File:
CRM-Avance-Corp/app/src/components/app/cartera-inversionistas-filtros.tsx

Lines:
55‑56

Problem:
Marcar el checkbox aplica `{porVencer:true, mes:'', estado:'vigente'}`; desmarcarlo aplica solo `{porVencer:false}`.

Evidence:
Línea 56: `onChange={e => onCambio(e.target.checked ? {porVencer:true, mes:'', estado:'vigente'} : {porVencer:false})}`.

Impact:
La vista por defecto es el mes actual (`cartera-inversionistas.tsx:37`). Un ciclo marcar/desmarcar deja al usuario en «Todos» con `estado='vigente'` pegado, es decir, un conjunto distinto del que tenía antes de tocar el checkbox, sin ningún indicador de que el mes cambió. Sobre carteras grandes también cambia el coste de la consulta.

Recommendation:
Recordar `mes` y `estado` previos al activar y reponerlos al desactivar, o —más simple y predecible— no limpiar `mes` y dejar que el filtro de vencimiento conviva con el mes seleccionado, documentando la intersección. La segunda opción contradice el README línea 18, así que conviene decidirlo explícitamente.

[P2] `reversa.sql` no está adjunto: la ruta de retroceso de un cambio LEVEL 3 queda sin revisar

File:
CRM-Avance-Corp/supabase/scripts/cartera-filtros/README.md

Lines:
60‑62

Problem:
El README compromete `reversa.sql` como plan de retroceso, pero el archivo no forma parte de la evidencia.

Evidence:
README línea 60: «Reversa: primero volver al frontend anterior. `reversa.sql` restaura el lector v1 y elimina las dos funciones nuevas.» No aparece en el bloque de evidencia adjunta ni en el `git status` del arranque.

Impact:
No puedo verificar la propiedad más importante del retroceso: que restaure **el owner y los grants originales** de `crm.cartera_inversionistas_fn` (ver P1), y no simplemente su cuerpo. Una reversa que deje la función publicada con owner `postgres` no revierte el cambio de identidad de ejecución.

Recommendation:
Adjuntar `reversa.sql` y asegurar que registre y reponga el owner previo y los grants previos de `crm.cartera_inversionistas_fn`, además de `drop function` de ambas funciones nuevas con su firma completa. Probar la reversa en la copia local y comparar las mismas 7 respuestas v1 contra el estado pre‑migración.

[P3] `limpiar` no devuelve al estado inicial

File:
CRM-Avance-Corp/app/src/screens/cartera-inversionistas.tsx

Lines:
37, 70, 163

Problem:
El estado inicial fija el mes actual; «Limpiar filtros» y «Restablecer filtros» dejan `mes: ''` (Todos).

Evidence:
Línea 37: `useState(() => ({...FILTROS_INVERSIONISTAS_INICIALES, mes: fechaLima(Date.now()).slice(0,7)}))`. Línea 70: `setFiltros(FILTROS_INVERSIONISTAS_INICIALES)`, cuyo `mes` es `''` (`inversionistas.ts:93`).

Impact:
El usuario no puede volver a la vista por defecto desde la UI, y «Restablecer» sobre un mes vacío amplía la consulta a toda la cartera en lugar de reducirla. También es el estado más caro (ver P2 de rendimiento).

Recommendation:
Extraer un helper `filtrosIniciales()` que aplique el mes actual y usarlo tanto en la línea 37 como en `limpiar`, o dejarlo como está de forma deliberada y renombrar el botón a «Ver toda la cartera».

[P3] `cantidad` cuenta filas demo mientras el capital las excluye

File:
CRM-Avance-Corp/supabase/migrations/20260916023055_crm_cartera_filtros_comerciales.sql

Lines:
76‑79

Problem:
`count(*) cantidad` no lleva `filter(where not f.es_demo)`, pero `capital_registrado` y `capital_activo` sí.

Evidence:
Línea 76: `count(*) cantidad`; línea 77: `sum(f.capital) filter(where not f.es_demo)`.

Impact:
Hoy es inocuo porque `cartera_f5_fuentes_reales()` ya excluye `es_demo=true`; en ese caso los `filter` de las líneas 77‑78 son código muerto. Pero las dos afirmaciones no pueden ser ciertas a la vez: o la fuente filtra y los `filter` sobran, o la fuente no filtra y `cantidad` está mal. Es una incoherencia latente que una futura fuente con demos convertiría en «3 inversiones · S/ 0».

Recommendation:
Elegir una sola invariante: quitar los `filter` y confiar en la fuente, o aplicar `filter(where not f.es_demo)` también a `count(*)`. Dejar un assert en el banco sobre `cantidad` con una fuente demo presente.

[P3] `empresas` no respeta los filtros mientras `resumen` sí, en la misma fila

File:
CRM-Avance-Corp/supabase/migrations/20260916023055_crm_cartera_filtros_comerciales.sql, CRM-Avance-Corp/app/src/screens/cartera-inversionistas.tsx

Lines:
migración 98‑102; pantalla 166, 173

Problem:
`empresas` se calcula sobre `fuentes` (sin filtrar), `ultima_fecha_comercial` y `resumen` sobre `fuentes_filtradas`.

Evidence:
Línea 99: `from fuentes f where f.inversionista_id=p.inversionista_id`. Líneas 100 y 101‑102: `from fuentes_filtradas f` / `from importes i`. En pantalla, la cabecera dice «Cliente · empresas» sin sufijo, frente a «Capital registrado · filtros» y «Último cierre · filtros» (línea 166).

Impact:
Con `empresa=qorilazo` la fila muestra los badges «Avance» y «Qorilazo» pero un resumen solo de Qorilazo. La asimetría es entendible (preserva el payload v1), pero la cabecera no la comunica.

Recommendation:
Mantener el cálculo (v1 depende de él) y ajustar la etiqueta de la columna a «Cliente · todas sus empresas», o atenuar visualmente los badges fuera del filtro activo.

[P3] El esquema estricto del cliente convierte un `null` inesperado en cartera vacía

File:
CRM-Avance-Corp/app/src/lib/inversionistas.ts, CRM-Avance-Corp/app/src/data/inversionistas-api.ts

Lines:
inversionistas.ts 20‑25, 30‑39; api 24‑28, 53‑57

Problem:
`Identidad` exige `nombre: v.string()`, `estado: v.string()`, `documento_verificado: v.boolean()`, `no_contactar: v.boolean()`, `creado_en: v.string()` no nulables, y `to_jsonb(p)` los pasa tal cual desde el núcleo.

Evidence:
`inversionistas.ts:20‑25`. Un solo `null` en cualquiera de esos campos, en cualquiera de las hasta 50 filas, hace fallar `v.safeParse` y `respuestaInversionistas` lanza `RESPUESTA_INCOMPLETA` (`inversionistas-api.ts:25‑28`), que la pantalla muestra como «No pudimos cargar la cartera» sin identificar la fila.

Impact secundario, en SQL:
`p_contacto='sin_restriccion'` se evalúa como `false = p.no_contactar` (migración línea 57); si `no_contactar` fuese nulable, esas personas desaparecen de **ambos** valores del filtro, no solo de uno.

Recommendation:
Confirmar `NOT NULL` en origen para esos cinco campos (o `coalesce` en el núcleo), y en la línea 57 usar `coalesce(p.no_contactar,false)` para que el filtro sea una partición total. Añadir un test de API con una fila de `nombre: null` que verifique el mensaje de error.

[P3] `distinct` sobre (id, nombre) puede producir opciones de responsable duplicadas

File:
CRM-Avance-Corp/supabase/migrations/20260916023055_crm_cartera_filtros_comerciales.sql

Lines:
93‑95

Problem:
`select distinct responsable_id id, responsable_nombre nombre from personas` deduplica el par, no el id.

Evidence:
Línea 94. Si `responsable_nombre` llega con dos grafías para el mismo `responsable_id` (fusión de identidades, cambio de nombre, espacios), salen dos entradas con el mismo `id`.

Impact:
Dos opciones indistinguibles en el select y `key` duplicada en React (`cartera-inversionistas-filtros.tsx:50`, `key={r.id}`), con la advertencia y el riesgo de reconciliación habitual.

Recommendation:
`distinct on (responsable_id) responsable_id id, responsable_nombre nombre … order by responsable_id, responsable_nombre`, envuelto en el orden final por nombre.

[P3] Formato de fechas de calendario: pendiente de evidencia

File:
CRM-Avance-Corp/app/src/components/app/cartera-inversionistas-filtros.tsx, CRM-Avance-Corp/app/src/screens/cartera-inversionistas.tsx

Lines:
filtros 8, 28; pantalla 20, 181

Problem (hipótesis, confianza baja):
`etiquetaDeMes('2026-09')` y `fmtFecha('2026-09-01')` reciben fechas de calendario puras. Si alguno construye `new Date(iso)`, la cadena se interpreta como UTC y en Lima (UTC‑5) se renderiza el día/mes anterior.

Evidence:
No dispongo de `@/lib/cartera-meses` ni de `@/lib/format`. La existencia de `fechaLima` (`agenda-derivada`, usado en `cartera-inversionistas.tsx:37` y `cartera-inversionistas-filtros.tsx:17`) y la afirmación del README línea 8 («sin conversión UTC de fechas de calendario») sugieren que el repositorio ya trata esto correctamente. Los tests SQL (`filtros.test.mjs:29`) asertan el valor crudo `'2026-07-15'`, no el texto renderizado.

Impact si se confirma:
La etiqueta del mes seleccionado y la columna «Último cierre» mostrarían el mes/día anterior, que es precisamente la confusión que el cambio pretende eliminar.

Recommendation:
Aportar la implementación de ambas funciones o un test de render que asserte `fmtFecha('2026-09-01')` y `etiquetaDeMes('2026-09')` con `TZ=America/Lima` y con una TZ positiva (p. ej. `Asia/Tokyo`) para descartar la dependencia del reloj del navegador.

[P3] Observaciones menores agrupadas

- **Auditoría indistinguible entre v1 y v2** (migración línea 105): `cartera_f5_registrar('lista')` recibe la misma etiqueta por ambas rutas y no se ejecuta si el `select` lanza. Durante la convivencia v1/v2 no habrá forma de medir la adopción ni de detectar clientes antiguos rezagados. Sugerencia: pasar la versión como argumento.
- **Combinación muerta no prevenida en UI**: `p_por_vencer=true` exige `estado in ('activo','vigente')` (línea 52), pero el select de estado no se deshabilita al marcar el checkbox (`cartera-inversionistas-filtros.tsx:38`, sin `disabled`). Elegir «Por vencer» + «Vencidas» devuelve siempre 0 filas con el mensaje genérico «No hay personas que coincidan».
- **Caracteres de control → error duro**: la migración rechaza `v_texto ~ '[[:cntrl:]]'` con 22023 (líneas 24, 34); el input no los sanea (`cartera-inversionistas-filtros.tsx:24`). Un pegado con caracteres invisibles produce «Filtros de cartera inválidos» en lugar de cero resultados. Sugerencia: normalizar en `listarInversionistas` (`inversionistas-api.ts:43`) donde ya se hace `.trim()`.
- **Sello temporal de la migración en el futuro**: `20260916023055` frente a la fecha de hoy 2026‑09‑15, previsiblemente por UTC vs Lima. No es un error, pero si después se crea una migración con marca `2026-09-15…` quedará ordenada antes y `supabase db push` podría omitirla en instancias donde esta ya esté aplicada.
- **Posible bucle de refetch ante 42501 persistente** (hipótesis, `cartera-inversionistas.tsx:86‑97`): el efecto dispara `revocarRef.current()` en cada nuevo objeto `q.error`, y `revocar()` termina en `invalidateQueries({queryKey: inversionistasKeys.actor(actor)})` (línea 89), que vuelve a lanzar la consulta que falla. Con `retry:false` y `gcTime:0` el ciclo podría repetirse mientras el 42501 persista. No puedo distinguir si estas líneas son nuevas o preexistentes; verificarlo con un test que devuelva 42501 de forma sostenida y cuente las invocaciones de la RPC.

TEST GAPS:

- `p_mes='sin_fecha'`: sin ningún caso, pese a tener dos ramas dedicadas (migración líneas 49 y 63). Es el hueco más relevante.
- Directorio/lector: `filtros.test.mjs:90` pasa vacuamente sobre arrays vacíos; falta asertar `sin_inversiones_total` y la ausencia de personas cuyas fuentes sean todas no‑Avance (ver P1).
- Sin caso para `service_role` en la matriz de roles (`filtros.test.mjs:122‑130`), que es precisamente el grant que la migración revoca.
- Sin assert de unicidad de `inversionista_id` en `cartera_f5_personas_visibles()`, que es la premisa de los joins de las líneas 41 y 80.
- Sin comprobación de las claves exactas del DTO (`jsonb_object_keys`), que es lo único que detectaría la fuga por denylist de la línea 97.
- Comparación v1 limitada a 7 respuestas: no cubre personas sin inversiones, filas con fuente demo, ni el efecto del `alter owner` (la comparación debería repetirse **después** del cambio de propietario).
- Sin test de render para `etiquetaDeMes`/`fmtFecha` con TZ forzada.
- Sin test del ciclo marcar/desmarcar «Por vencer» ni de la equivalencia entre el estado inicial y el estado tras «Limpiar».
- La contaminación reportada tras el timeout en el run completo no quedó cubierta por ningún test ni por un cambio de aislamiento; queda como deuda conocida.

ARCHITECTURE RISKS:

- Compartir el núcleo entre v1 y v2 es la decisión correcta, pero convierte `cartera_f5_listar` en un punto único de fallo para las pestañas ya publicadas. El `p_compatibilidad` (líneas 68‑71) es una bifurcación de comportamiento dentro del núcleo: cada filtro futuro tendrá que decidir su semántica en modo compatibilidad. Conviene fijar por escrito, en el README, que `p_compatibilidad` es transitorio y con fecha de retirada.
- La adaptación v1 por resta de claves (líneas 130‑133) es frágil en la misma dirección que el P2 del DTO: cualquier clave nueva en v2 aparece automáticamente en v1 salvo que se añada a la resta.
- El cliente tolera que v1 quede instalado y v2 no (`PGRST202` se trata como estado compatible en `inversionistas-api.ts:36‑38`), pero solo para `cartera_inversionistas_estado_fn`; `listarInversionistas` no tiene esa tolerancia. Si el front v2 se publicara antes del SQL, la cartera quedaría en error duro. El orden documentado (README líneas 54‑59: SQL primero) lo evita; vale la pena que el orden esté también en `MIGRACIONES.md` y no solo en el README de scripts.

SECURITY RISKS:

- El cambio de propietario de una `security definer` publicada (P1) es el riesgo de seguridad principal: puede tanto elevar como reducir privilegios efectivos, y su modo de fallo es silencioso.
- La posible sobrecarga no eliminada de `private.cartera_f5_listar` (P1) dejaría una función ejecutable con permisos antiguos fuera del alcance de los `revoke` de la línea 143.
- Lo demás está sólido: `search_path=''` en las tres funciones, todo cualificado por esquema, `cartera_f5_exigir()` invocado **antes** de cualquier lectura (línea 21, verificado en `filtros.test.mjs:138‑139`), validación estricta de entradas con lista blanca y error 22023, búsqueda con `strpos` en lugar de `like` (sin metacaracteres, verificado en `filtros.test.mjs:98`), `p_responsable` aplicado sobre el conjunto ya recortado (línea 55) sin posibilidad de enumeración, y ningún identificador de perfil en el payload de lista (línea 97).
- Correcto también que el cliente no envíe a telemetría el payload ni los issues del validador (`inversionistas-api.ts:26`).

REGRESSION RISKS:

- **Alto**: grants y owner de `crm.cartera_inversionistas_fn`, que sirve al front ya publicado (P1 y P2 de `service_role`).
- **Medio**: `empresas`, `totales` y `total` de v1 dependen ahora de `filtradas`, que incorpora la rama nueva de «sin inversiones» (líneas 60‑63). Con `p_empresa` nulo, v1 empieza a incluir o excluir personas sin fuentes según esa rama; las 7 respuestas comparadas deberían incluir explícitamente al menos un caso con personas sin inversiones y uno con `p_empresa` fijado.
- **Medio**: la ficha aprobada y el radar F6 no se tocan en el SQL, pero `cartera-inversionistas.tsx` pasa `filtros.empresa` a `VencimientosPostventa` con `key` (línea 190); al cambiar el valor por defecto del mes no cambia `empresa`, así que ese contrato se conserva.
- **Bajo**: `inversionistas-queries.ts` no cambia claves de caché de ficha ni de cuentas; `inversionistasKeys.lista` incorpora los filtros nuevos por serialización del objeto, sin colisión con entradas antiguas.

RECOMMENDED NEXT ACTIONS:

1. Antes de instalar el SQL, ejecutar en la instancia real las tres consultas de inventario (owner+`prosecdef` de las funciones implicadas, firmas existentes de `private.cartera_f5_listar`, grants actuales de `crm.cartera_inversionistas_fn`) y ajustar el bloque 138‑151 de la migración a lo que devuelvan: no reasignar el owner por arrastre, añadir el `drop function` de la firma antigua si existe, y reponer `service_role` si estaba concedido.
2. Decidir y corregir la semántica de «sin inversiones» para el lector global (P1), y sustituir los `every()` vacuos de `filtros.test.mjs:90` por asserts que fallen: persona con perfil Avance autorizado y fuentes solo Qorilazo, verificando `total`, `sin_inversiones_total` y `filas`.
3. Añadir los casos de `p_mes='sin_fecha'` (cuatro asserts indicados en el P2 correspondiente) y el assert de unicidad de `cartera_f5_personas_visibles()`.
4. Adjuntar `reversa.sql` y verificar que repone owner y grants originales, no solo el cuerpo de v1; probar el ciclo ida y vuelta en la copia local comparando las respuestas v1.
5. Corregir los tres puntos de producto/accesibilidad de la UI: `aria-label` de la fila (P2), mensaje explicativo visible en móvil cuando `sinInversiones` (P2) y la asimetría del checkbox «Por vencer» (P2); alinear `limpiar` con el estado inicial (P3).
6. Cerrar el Verification Gate: terminar `http.mjs`, build y `npm run check:all`, repetir advisors **después** de fijar el owner, y repetir la comparación v1 también después del `alter owner`. Reportar el run completo indicando que requirió `--workers=4` y qué se hizo con la contaminación observada; no darlo por `PASS` sin esa nota.

CONFIDENCE:
MEDIUM

Alta para los hallazgos derivables del texto adjunto (bloque de permisos y propiedad, rama del lector global, huecos de test, DTO por denylist, UI/a11y). Media‑baja para los que dependen de artefactos no adjuntos: `cartera_f5_personas_visibles`, `cartera_f5_fuentes_reales`, `cartera_f5_registrar`, `reversa.sql`, `cartera-meses.ts`, `format.ts`, el diff de `cartera-inversionistas.tsx` y el estado real de owner/grants en producción. Esos están marcados como hipótesis con la comprobación exacta que los resolvería; no considero que su ausencia impida emitir dictamen, por lo que no devuelvo BLOCK.
