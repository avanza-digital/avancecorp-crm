ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión — RONDA 2 y ÚLTIMA (LEVEL 3) · Potencial del lead, FASE 3 entrega B (servidor)

Eres el revisor secundario. Sin base de datos ni red: todo está transcrito abajo. Esta ronda existe porque hay EVIDENCIA NUEVA: tu ronda 1 y la del auditor de RLS cambiaron el diseño del ámbito y las verificaciones. Tu trabajo es REFUTAR lo nuevo: ¿quedó cerrado lo que señalaste?, ¿el cambio de ámbito abre otra cosa?, ¿hay un falso verde nuevo? Responde con VERDICT (APPROVE / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 con evidencia (archivo/fragmento), riesgos y test gaps, NEXT ACTIONS y CONFIDENCE. Sin hallazgo sin evidencia; distingue hipótesis de hechos. No repitas lo ya resuelto.

## Qué es (resumen del contexto de la ronda 1)
«Potencial del lead»: los analistas marcan cada lead como Frío, Tibio o Estrella (tabla `crm.lead_potencial`, una fila por lead, RLS y SIN grants de API). Fases 1, 2 y 3A en producción, bandera `potencial_lead` ENCENDIDA. La entrega B añade en Leads una fila «Por potencial» con cuatro botones con conteo (Frío, Tibio, Estrella, Sin marcar) que filtran la lista. Servidor: `crm.cartera_filtrada_fn` (INVOKER, STABLE; hoy 13 argumentos, md5 `bf06666f…`) pasa a 14 con `p_potencial`, y el resumen gana `resumen.potencial` contado ANTES de aplicar ese filtro. `crm.resumen_cartera_fn()` (DEFINER) la envuelve sin RLS. `private` no está expuesto en PostgREST. El frente valida con valibot `v.object` (descarta claves desconocidas). Las migraciones las aplica Miguel con `supabase db query --linked --file`.

## Tus hallazgos de la ronda 1 y qué se hizo
1. **P2 — el postflight no verificaba la identidad del ayudante.** ACEPTADO. El postflight exige ahora `md5(pg_get_functiondef(ayudante)) = '73e993d6…'` (medido en el banco). La misma huella está en `verificar-filtro.sql` (con «debe ser» y el dueño), en la guarda de `reversa-filtro.sql` y en una aserción de catálogo del gate. Mutante de publicación nuevo `post-ayudante-ambito-abierto` (abre el ámbito conservando gate y bandera): rechazado. Paso 21 del ciclo: el verificador frente a un ayudante ensanchado enseña otra huella.
2. **P2 — el verificador de sumas aceptaba respuestas de error.** ACEPTADO. Ahora cuenta como mala toda respuesta nula, con `error` o sin el bloque (`18 respuestas, 0 malas`), hay un caso que prueba el propio verificador con una respuesta de error, y el mutante `m-fn-envoltorio-falla` (solo falla el envoltorio DEFINER) lo pone en «9 malas». En el gate, `idsDe` devuelve null ante un error y las aserciones de lista vacía ya no lo aceptan.
3. **Riesgo a/b — el coordinador recibía por el envoltorio conteos por nivel de una bandeja que su RLS no ve.** El auditor de RLS lo elevó a P2 (clase de dato nueva para un rol, sin decisión del dueño). RESUELTO sin ampliar visibilidad: el ayudante ya NO usa el predicado de la base (con reparto); es el **espejo exacto de la policy `leads_select`** (el mismo de `private.potencial_lectura`, 3A), y la cartera **no emite `resumen.potencial` ni llama al ayudante para quien no tiene ámbito de filas** (`v_potencial := bandera and (coalesce(v_global,false) or cardinality(v_visibles) > 0)`; `marcas … where v_potencial`). Coordinación: sin la clave por la API y por el envoltorio, y 55000 si pide el filtro. Un actor con ámbito de filas que además opere el reparto vería, dentro del envoltorio, las marcas que no puede leer contadas como «sin marca» (documentado en el COMMENT).
4. **Test gaps (h).** Añadidos: cerrados sin marca y convertido fuera de ventana; combinaciones no vacías con gestión efectiva (tenencia + contacto) y con reasignación; negativa cruzada (`p_vendedor_id` de otro equipo + nivel → ni filas ni conteos); cursor con empate de sello y con un id ajeno; el ayudante por dentro para DM y DH y «ayudante ⊆ RLS» para los 10 roles; el ayudante no se llama con la bandera apagada ni para coordinación (se sustituye por uno que explota). Preflight: índice único por `lead_id`, RLS de `crm.leads`, lista exacta de consumidores de servidor de la cartera y md5 del envoltorio.
5. **c — comprobar la API real tras recargar la caché.** Queda en el orden de producción: sonda HTTP con `p_potencial` antes de publicar la pantalla (401/42501 = conoce el parámetro; 404/PGRST202 = aún no).
No aceptado: nada. Pendiente declarado: la matriz `test-rls.mjs` sigue **NOT RUN** (exige credenciales de una rama de Supabase).

## Lo que añadió el auditor de RLS (aplicado)
- Postflight: el rechazo sin sesión debe ser por la guarda propia (`sqlerrm = 'No autorizado'`), no cualquier 42501.
- `verificar-filtro.sql`: `quote_all_identifiers` off y dueño del ayudante.
- Reversa: guarda con la huella del ayudante y contra un consumidor de servidor que ya pase `p_potencial =>`; `potencial-lead/reversa.sql` (fase 1) se niega si el filtro sigue aplicado.
- Gate: ruta sin RLS (`resumen_cartera_fn` por rol, con y sin bandera), `schema('private').rpc('cartera_potencial_fn')` inalcanzable, catálogo del ayudante, negativa cruzada.
- Mutantes: ya no sobrevive ninguno (antes sobrevivía `ayu-sin-gerencia`); mutantes propios para la clase de la declaración, guard 3, grant por columna a anon, USAGE de `private`, índice único, RLS de leads, policies, envoltorio y otro consumidor; el ciclo termina con un veredicto de máquina (sale con 1).
- Ledger y LEEME escritos; `gestion-diaria-cola/fixtures/acl.json` con la firma de 14 y el ayudante.

## Preguntas de esta ronda
a. ¿El espejo de `leads_select` en el ayudante es EXACTO (mira la policy transcrita al final) y falla cerrado con NULL (`v_rol` null, `v_lector` null, `vendedor_id` null, `v_visibles` vacío)?
b. `v_potencial` usa `coalesce(v_global, false) or cardinality(v_visibles) > 0`. ¿Hay algún rol con ámbito real de filas que quede SIN potencial (falso negativo) o alguno sin ámbito que lo reciba? Nota: `v_global` y `v_visibles` son los de la función de 13 (no se tocaron). ¿`cardinality` de un `uuid[]` vacío construido con `array(select …)` es 0 y nunca NULL?
c. `select … from private.cartera_potencial_fn() m where v_potencial` dentro de una CTE materializada: ¿hay algún plan en el que Postgres ejecute la función aunque `v_potencial` sea falso? (El banco prueba que no: con el ayudante sustituido por uno que explota, la cartera responde con la bandera apagada y para coordinación.) ¿Riesgo con planes genéricos de plpgsql?
d. ¿El postflight puede dar falso rojo en producción por las huellas nuevas (md5 de `pg_get_functiondef` del ayudante y del envoltorio `crm.resumen_cartera_fn`, policies por `pg_get_expr`)? Las de las policies y 5 ayudantes ya pasaron hoy en producción con la 3A; el md5 del envoltorio (`4a896597…`) y la lista de consumidores solo están medidos en el banco (volcado de producción de hoy 13:31).
e. Guard 7 del preflight: `prosrc ~* 'cartera_filtrada_fn'` debe dar exactamente `crm.resumen_cartera_fn()`. ¿Falso rojo razonable (una función que solo la nombre en un comentario)? ¿Lo dejarías?
f. ¿Queda algún falso verde en `prueba-filtro.sql` o en el bloque del gate tras los cambios?
g. ¿Algo en la reversa nueva (guarda por huella del ayudante, búsqueda de `p_potencial\s*=>`)?

## Evidencia (banco Docker: esquema de producción del 01/10 13:31 + migraciones posteriores del repo; trinquete analítico sembrado)
Ciclo `banco/ciclo-fase3b.sh` (salida real, con veredicto de máquina):
```
0 reversa del estado previo: NOTICE:  REVERSA filtro_potencial OK: firma unica de 13 (md5 bf06666f…), sin ayudante, declaracion analitica devuelta y sellada. Las marcas se conservan.
1 migración:        NOTICE:  cartera_filtro_potencial OK: firma unica de 14 argumentos, ayudante DEFINER con el cuerpo ensayado y solo para authenticated, contrato de seguridad intacto, declaraci
2 repetida:         ERROR:  PREFLIGHT: cartera_filtrada_fn no coincide con la version auditada, o esta migracion ya esta aplicada
3 reversa:          NOTICE:  REVERSA filtro_potencial OK: firma unica de 13 (md5 bf06666f…), sin ayudante, declaracion analitica devuelta y sellada. Las marcas se conservan.
4 reversa repetida: ERROR:  REVERSA filtro_potencial: la entrega B no esta aplicada tal como se publico
5 tras la reversa:  md5 de la cartera bf06666fb8ef533a39a50c7d70420153, ayudante=0
6 migración:        NOTICE:  cartera_filtro_potencial OK: firma unica de 14 argumentos, ayudante DEFINER con el cuerpo ensayado y solo para authenticated, contrato de seguridad intacto, declaraci
7 trinquetes:       idénticos sin y con la migración, salvo la fila de la cartera (27 pasan, 9 caen igual, CENSO (sin la cartera) 37 filas)
  la cartera en el censo, antes:   (funcion,"crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)",t,t)
  la cartera en el censo, después: (funcion,"crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)",t,t)
8 tras la reversa:  la foto entera es la de antes (censo incluido)
9  filtro:            ERROR:  FILTRO potencial_lead: 145 de 145 OK
10 fase 1 intacta:    ERROR:  SINTETICA potencial_lead: 75 de 75 OK
11 fase 2 intacta:    ERROR:  CADUCIDAD potencial_lead: 51 de 51 OK
12 fase 3A intacta:   ERROR:  LECTURA potencial_lead: 94 de 94 OK
13 regla de gestión:  CARTERA_GESTION_OK 128/128 (oráculo de scripts/cartera-gestion contra la firma de 14)
  el verificador de sumas ve el envoltorio roto: los cuatro conteos suman el total sin filtro (los 9 roles con ámbito, API y envoltorio) → esperado 18 respuestas, 0 malas, obtenido 18 respuestas, 9 malas
  tras los mutantes: ayudante=1, md5 de la cartera=23a63cc3965472b9db85aa81cadffbeb, SELECT de authenticated sobre la tabla de marcas=f, sello vigente=t
14 ERROR:  MEDIR filtro · gerencia (6000 leads, 2400 marcas): anterior 20.3 ms, nueva 21.0 ms, con estrella 17.9 ms, con sin_marca 21.3 ms · supervisor (1000 leads, 400 marcas): anterior 4.9 ms, nueva 6.3 ms, con estrella 5.4 ms, con sin_marca 6.3 ms · analista (100 leads, 100 marcas): anterior 2.9 ms, nueva 3.9 ms, con estrella 3.4 ms, con sin_marca 3.4 ms
15 el registrador lleva el md5 de la migración
16 registrar:          NOTICE:  REGISTRO: 20261001212341 / crm_cartera_filtro_potencial (1 sentencia: el archivo entero)
17 registrar otra vez: NOTICE:  REGISTRO: 20261001212341 / crm_cartera_filtro_potencial (1 sentencia: el archivo entero)
18 verificar:          VERIFICAR filtro_potencial: firmas [crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)] (debe ser una, la de 14), md5 de la cartera 23a63cc3965472b9db85aa81cadffbeb (debe ser 23a63cc3965472b9db85aa81cadffbeb), md5 del ayudante 73e993d618b203cdbe21e8127f7ea5b4 (debe ser 73e993d618b203cdbe21e8127f7ea5b4), ejecutan la cartera [authenticated] (debe ser authenticated), ejecutan el ayudante [authenticated] (debe ser authentica
19 verificar con la tabla abierta por columna: leen la tabla de marcas por la API [authenticated]
20 verificar con el ayudante abierto a PUBLIC:  ejecutan el ayudante [anon,authenticated,service_role]
21 verificar con el ayudante ensanchado:        md5 del ayudante f353a618b6d7bfe55f6d3ad41311325f
   estado final: ayudante=1, md5 de la cartera=23a63cc3965472b9db85aa81cadffbeb, SELECT de authenticated sobre la tabla de marcas=f, sello vigente=t
── VEREDICTO
CICLO FASE 3B: TODO COMO SE ESPERABA
```
Mutantes (salida real; lógica: «N FALLAS»; migración: `ERROR: PREFLIGHT/POSTFLIGHT` o el error de un trinquete ajeno; una línea «↑» marcaría un superviviente: no hay ninguna):
```
  m-ayu-con-reparto              → ERROR:  FILTRO potencial_lead: 2 FALLAS de 145: 132 ayudante, C: nada (operar el reparto no da a leer marcas) → esperado (ninguno), obtenido LP:f,LSM:t | 134 ayudante ⊆ R
  m-ayu-sin-bandeja              → ERROR:  FILTRO potencial_lead: 9 FALLAS de 145: 40 S1: conteos → esperado - E3 T3 F1 S2 v=9, obtenido - E3 T3 F0 S3 v=9 | 63 S1 sin filtro = oráculo (RLS real + tabla de 
  m-ayu-sin-bandera              → ERROR:  FILTRO potencial_lead: 1 FALLAS de 145: 13 apagada: el ayudante no devuelve nada (gerencia) → esperado (ninguno), obtenido L1:e,L1n:t,L2:e,LC:e,LCV:e,LD:t,LK:t,LP
  m-ayu-sin-gate                 → ERROR:  FILTRO potencial_lead: 4 FALLAS de 145: 133 ayudante, DM (pareja desalineada) → 42501 → esperado error 42501, obtenido (ninguno) | 136 ayudante, P (solo portal) →
  m-ayu-sin-gerencia             → ERROR:  FILTRO potencial_lead: 10 FALLAS de 145: 36 G: conteos (los cerrados sin marca cuentan en «sin marca») → esperado - E4 T4 F1 S5 v=14, obtenido - E4 T3 F1 S6 v=14 
  m-ayu-sin-lector               → ERROR:  FILTRO potencial_lead: 14 FALLAS de 145: 37 D (directorio) ve lo mismo que gerencia → esperado - E4 T4 F1 S5 v=14, obtenido - E0 T0 F0 S14 v=14 | 38 DH (directori
  m-ayu-sin-propios              → ERROR:  FILTRO potencial_lead: 64 FALLAS de 145: 40 S1: conteos → esperado - E3 T3 F1 S2 v=9, obtenido - E0 T0 F1 S8 v=9 | 41 S1n: solo el lead de su analista → esperado 
  m-ayu-sin-sesion-ni-gate       → ERROR:  FILTRO potencial_lead: 5 FALLAS de 145: 133 ayudante, DM (pareja desalineada) → 42501 → esperado error 42501, obtenido (ninguno) | 135 ayudante, sin sesión → 4250
  m-ayu-todo-global              → ERROR:  FILTRO potencial_lead: 5 FALLAS de 145: 129 ayudante, S1: su equipo y su bandeja → esperado L1:e,L1n:t,LC:e,LD:t,LK:t,LP:f,LZ:e, obtenido L1:e,L1n:t,L2:e,LC:e,LCV
  m-ayu-ve-inactivos             → ERROR:  FILTRO potencial_lead: 6 FALLAS de 145: 126 ayudante, G: todas las marcas de leads activos → esperado L1:e,L1n:t,L2:e,LC:e,LCV:e,LD:t,LK:t,LP:f,LSM:t,LZ:e, obteni
  m-fn-clave-siempre             → ERROR:  FILTRO potencial_lead: 6 FALLAS de 145: 8 apagada: el resumen NO trae la clave potencial → esperado (sin clave) v=7, obtenido - E0 T0 F0 S7 v=7 | 14 apagada: el e
  m-fn-columna-viaja             → ERROR:  FILTRO potencial_lead: 4 FALLAS de 145: 16 apagada: la respuesta es la de la firma de 13 (10 actores × 14 llamadas) → esperado 140 de 140, obtenido 43 de 140 · G 
  m-fn-conteos-tras-filtro       → ERROR:  FILTRO potencial_lead: 38 FALLAS de 145: 49 G con estrella = oráculo → esperado L1,L2,LC,LZ | E4 T4 F1 S5, obtenido L1,L2,LC,LZ | E4 T0 F0 S0 | 50 G con tibio = o
  m-fn-embudo-de-previa          → ERROR:  FILTRO potencial_lead: 1 FALLAS de 145: 102 V1 estrella: el embudo suma el total → esperado 3, obtenido 7
  m-fn-envoltorio-falla          → ERROR:  FILTRO potencial_lead: 5 FALLAS de 145: 14 apagada: el envoltorio responde y tampoco trae la clave → esperado (sin clave) v=7, obtenido error P0778 | 121 C en el 
  m-fn-estrella-cuenta-tibio     → ERROR:  FILTRO potencial_lead: 37 FALLAS de 145: 41 S1n: solo el lead de su analista → esperado - E0 T1 F0 S0 v=1, obtenido - E1 T1 F0 S0 v=1 | 42 V1: conteos → esperado 
  m-fn-frio-cuenta-sin-marca     → ERROR:  FILTRO potencial_lead: 49 FALLAS de 145: 36 G: conteos (los cerrados sin marca cuentan en «sin marca») → esperado - E4 T4 F1 S5 v=14, obtenido - E4 T4 F5 S5 v=14 
  m-fn-llama-siempre             → ERROR:  FILTRO potencial_lead: 1 FALLAS de 145: 145 ayudante que explota, bandera apagada: no se le llama y la cartera responde → esperado L1,L3,LC,LD,LK,LPV,LZ, obtenido
  m-fn-no-recorta                → ERROR:  FILTRO potencial_lead: 56 FALLAS de 145: 46 V2 con sin_marca: los dos cerrados sin marca → esperado LCS,LDS, obtenido L2,LCS,LDS | 47 V2 con estrella: el converti
  m-fn-pagina-de-previa          → ERROR:  FILTRO potencial_lead: 49 FALLAS de 145: 46 V2 con sin_marca: los dos cerrados sin marca → esperado LCS,LDS, obtenido L2,LCS,LDS | 47 V2 con estrella: el converti
  m-fn-potencial-sin-ambito      → ERROR:  FILTRO potencial_lead: 4 FALLAS de 145: 119 C (coordinación) por la API: su RLS no le deja ver leads y no recibe conteos por nivel → esperado (ninguno) / (sin cla
  m-fn-sin-bandera               → ERROR:  FILTRO potencial_lead: 3 FALLAS de 145: 9 apagada: pedir el filtro → 55000 → esperado error 55000, obtenido (ninguno) | 10 apagada: pedir «sin_marca» → 55000 → es
  m-fn-sin-eco                   → ERROR:  FILTRO potencial_lead: 6 FALLAS de 145: 94 V1 con estrella: eco, conteos intactos y total del nivel → esperado estrella E3 T2 F0 S2 v=3, obtenido - E3 T2 F0 S2 v=
  m-fn-sin-marca-rota            → ERROR:  FILTRO potencial_lead: 11 FALLAS de 145: 46 V2 con sin_marca: los dos cerrados sin marca → esperado LCS,LDS, obtenido (ninguno) | 52 G con sin_marca = oráculo → e
  m-fn-sin-marca-trae-todo       → ERROR:  FILTRO potencial_lead: 13 FALLAS de 145: 46 V2 con sin_marca: los dos cerrados sin marca → esperado LCS,LDS, obtenido L2,LCS,LDS | 52 G con sin_marca = oráculo → 
  m-fn-sin-union                 → ERROR:  FILTRO potencial_lead: 85 FALLAS de 145: 36 G: conteos (los cerrados sin marca cuentan en «sin marca») → esperado - E4 T4 F1 S5 v=14, obtenido - E0 T0 F0 S14 v=14
  m-fn-sin-validar               → ERROR:  FILTRO potencial_lead: 8 FALLAS de 145: 11 apagada: un valor inválido sigue siendo 22023 (se valida antes) → esperado error 22023, obtenido error 55000 | 22 valor
  m-fn-totales-de-previa         → ERROR:  FILTRO potencial_lead: 6 FALLAS de 145: 94 V1 con estrella: eco, conteos intactos y total del nivel → esperado estrella E3 T2 F0 S2 v=3, obtenido estrella E3 T2 F
  post-abre-la-tabla                 → ERROR:  POSTFLIGHT: crm.lead_potencial quedo con algun grant de lectura para la API
  post-ayudante-a-anon               → ERROR:  POSTFLIGHT: el ayudante no quedo con el cuerpo ensayado/DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-a-service-role       → ERROR:  POSTFLIGHT: el ayudante no quedo con el cuerpo ensayado/DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-ambito-abierto       → ERROR:  POSTFLIGHT: el ayudante no quedo con el cuerpo ensayado/DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-con-opcion           → ERROR:  POSTFLIGHT: el ayudante no quedo con el cuerpo ensayado/DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-cuenta               → ERROR:  POSTFLIGHT: el ayudante no quedo con el cuerpo ensayado/DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-invoker              → ERROR:  POSTFLIGHT: el ayudante no quedo con el cuerpo ensayado/DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-publico              → ERROR:  POSTFLIGHT: el ayudante no quedo con el cuerpo ensayado/DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-set-de-mas           → ERROR:  POSTFLIGHT: el ayudante no quedo con el cuerpo ensayado/DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-sin-grant            → ERROR:  POSTFLIGHT: el ayudante no quedo con el cuerpo ensayado/DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-sin-search-path      → ERROR:  POSTFLIGHT: el ayudante no quedo con el cuerpo ensayado/DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-sin-sesion           → ERROR:  POSTFLIGHT: el ayudante no quedo con el cuerpo ensayado/DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-volatil              → ERROR:  POSTFLIGHT: el ayudante no quedo con el cuerpo ensayado/DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-cambia-la-clase               → ERROR:  POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno
  post-cartera-a-anon                → ERROR:  POSTFLIGHT: firma, cuerpo, permisos o contrato invalido
  post-cartera-a-service-role        → ERROR:  POSTFLIGHT: firma, cuerpo, permisos o contrato invalido
  post-cartera-definer               → ERROR:  POSTFLIGHT: firma, cuerpo, permisos o contrato invalido
  post-cuerpo-cambiado               → ERROR:  POSTFLIGHT: firma, cuerpo, permisos o contrato invalido
  post-otro-consumidor               → ERROR:  POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno
  post-policy-cambia-durante         → ERROR:  leads_select cambio desde la auditoria (md5 aa5f67c1b4b372648c73cdece0e68d46): re-auditar
  post-sin-mover-la-declaracion      → ERROR:  POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno
  post-sin-resellar                  → ERROR:  POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno
  post-toca-el-envoltorio            → ERROR:  POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno
  post-toca-otra-declaracion         → ERROR:  POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno
  pre-actividades-abiertas           → ERROR:  crm.actividades tiene otras permisivas de lectura (actividades_select,mutante_all): la co-extensividad ya no esta garantizada
  pre-ayudante-de-ambito-cambiado    → ERROR:  PREFLIGHT: un ayudante de visibilidad no es el ensayado: crm.bandera_activa(text)=bb817f2b07b561356959f25dc3aae4dc private.es_lector
  pre-ayudante-ya-existe             → ERROR:  PREFLIGHT: cartera_filtrada_fn no coincide con la version auditada, o esta migracion ya esta aplicada
  pre-bandera-a-anon                 → ERROR:  PREFLIGHT: los permisos de crm.bandera_activa o del esquema private no son los ensayados
  pre-bandera-sin-execute            → ERROR:  PREFLIGHT: los permisos de crm.bandera_activa o del esquema private no son los ensayados
  pre-clase-cambiada                 → ERROR:  PREFLIGHT: la declaracion analitica no esta vigente y sellada
  pre-columna-nueva                  → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-envoltorio-cambiado            → ERROR:  PREFLIGHT: los consumidores de servidor de la cartera no son los ensayados
  pre-funcion-cambiada               → ERROR:  PREFLIGHT: cartera_filtrada_fn no coincide con la version auditada, o esta migracion ya esta aplicada
  pre-gate-cambiado                  → ERROR:  PREFLIGHT: las policies de lectura de crm.leads no son las ensayadas: crm_actor_activo_gate|*|false|{authenticated}|b326b5062b2f0e69
  pre-huella-vieja                   → ERROR:  PREFLIGHT: la declaracion analitica no esta vigente y sellada
  pre-leads-sin-rls                  → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-nivel-nuevo                    → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-otro-consumidor                → ERROR:  PREFLIGHT: los consumidores de servidor de la cartera no son los ensayados
  pre-policy-cambiada                → ERROR:  leads_select cambio desde la auditoria (md5 aa5f67c1b4b372648c73cdece0e68d46): re-auditar
  pre-policy-de-lectura-nueva        → ERROR:  PREFLIGHT: las policies de lectura de crm.leads no son las ensayadas: crm_actor_activo_gate|*|false|{authenticated}|c5e6c90632bc6162
  pre-select-a-anon                  → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-select-a-la-api                → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-select-de-columna-a-anon       → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-select-por-columna             → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-sello-roto                     → ERROR:  PREFLIGHT: la declaracion analitica no esta vigente y sellada
  pre-sin-bandera                    → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-sin-indice-unico               → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-sin-rls                        → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-sin-usage-de-private           → ERROR:  authenticated no tiene USAGE sobre private: la cadena invoker no funcionaria
  pre-sobrecarga                     → ERROR:  PREFLIGHT: cartera_filtrada_fn no coincide con la version auditada, o esta migracion ya esta aplicada
  pre-visibles-cambiado              → ERROR:  PREFLIGHT: un ayudante de visibilidad no es el ensayado: crm.bandera_activa(text)=bb817f2b07b561356959f25dc3aae4dc private.es_lector
```
- `test-rls.mjs`: **NOT RUN** (credenciales); `node --check` PASS. Advisors: se miden al publicar.
- Antes de publicar se repetirá el ciclo sobre un banco montado con un volcado NUEVO de producción (el de hoy 13:31 es anterior a la migración de gestión, que en este banco se aplicó desde el archivo del repo).

## Archivos

### supabase/migrations/20261001212341_crm_cartera_filtro_potencial.sql (versión de esta ronda, completa)
```sql
-- 20261001212341_crm_cartera_filtro_potencial.sql
--
-- Potencial del lead · FASE 3, entrega B (servidor): filtrar y contar Leads por potencial.
-- Plan aprobado por Miguel el 01/10/2026 («ok dale con el plan B, todo lo recomendado»: el filtro va
-- solo en Leads, «Sin marcar» es una opción y se elige un nivel a la vez). Nota del vault:
-- «Potencial del lead - Frio Tibio Estrella (2026-09-30)», «Fase 3 · entrega B».
--
-- QUÉ. `crm.cartera_filtrada_fn` gana UN argumento al final, `p_potencial text default null`:
--   · null                          → no recorta;
--   · 'estrella' | 'tibio' | 'frio' → leads cuya marca VIGENTE es ese nivel;
--   · 'sin_marca'                   → leads sin marca;
--   · cualquier otro valor          → 22023, por el mismo bloque de validación que los demás filtros;
--   · con la bandera `potencial_lead` apagada, pedirlo → 55000 (igual que la puerta de marcar);
--     lo mismo para quien no tiene ámbito de filas (ni global ni analistas visibles: coordinación).
--   Y el resumen gana UNA clave, `resumen.potencial` = {filtro, estrella, tibio, frio, sin_marca}:
--   cuántos leads hay de cada nivel con los DEMÁS filtros puestos. Se cuenta ANTES de aplicar
--   `p_potencial`: los cuatro números no cambian al elegir un nivel, suman el total sin ese filtro
--   y el del nivel elegido coincide con `totales.vivos`. `filtro` es el eco del pedido. La clave
--   solo viaja con la bandera encendida y para quien tiene ámbito de filas.
--
-- CÓMO LEE LA MARCA. La función es INVOKER y las tablas del potencial no tienen grants de API
--   (fase 1, auditor-rls r1): nace `private.cartera_potencial_fn()`, un ayudante con el molde de
--   `private.cartera_recepciones_fn` (el otro ayudante de esta misma función). Devuelve
--   (lead_id, nivel) de las marcas vigentes de los leads que el actor PUEDE VER.
-- SECURITY DEFINER, justificación: una función INVOKER no puede leer `crm.lead_potencial` (sin
--   grants para nadie de la API, y así se queda). El ayudante verifica de forma explícita la sesión,
--   el gate del CRM (`private.puede_acceder_crm`, invocado) y el ÁMBITO, que es el ESPEJO EXACTO de
--   la policy `leads_select` (el mismo de `private.potencial_lectura`, fase 3A): ve la marca solo
--   quien ve el lead, en cualquier contexto. El preflight fija por md5 esa policy, el gate
--   restrictivo de `crm.leads` y los ayudantes en que se apoyan: si alguno cambió desde el ensayo,
--   la migración se niega. `search_path` vacío, dueño postgres, EXECUTE solo `authenticated`; el
--   esquema `private` no está expuesto en la API.
--   Consecuencia buscada (Codex f3b r1 y auditor-rls f3b, P2-1): `crm.resumen_cartera_fn`
--   (DEFINER) llama a la cartera SIN RLS y su base incluye, para quien opera el reparto
--   (coordinación), una bandeja que su RLS no deja ver. El ayudante NO entrega esas marcas, y la
--   cartera ni siquiera emite `resumen.potencial` para quien no tiene ámbito de filas: ningún
--   conteo por nivel revela la marca de un lead que el actor no puede leer. Si un actor con ámbito
--   de filas opera además el reparto, dentro del envoltorio las marcas que no ve cuentan como
--   «sin marca». Por la API (INVOKER) no hay diferencia: la RLS ya recorta la base.
--
-- QUÉ NO CAMBIA. Con la bandera apagada la respuesta es byte a byte la de la firma de 13 (y el
--   ayudante ni se llama). Con la bandera encendida y sin el filtro, solo se AÑADE `resumen.potencial` (clave nueva dentro del
--   resumen: los frentes publicados leen el resumen con un esquema que ignora las claves de más).
--   Las filas tienen la forma de siempre (la columna de trabajo `potencial_nivel` se quita antes
--   de serializar), no hay claves nuevas arriba, y siguen igual INVOKER, `stable`, `search_path`
--   vacío, dueño y ACL. Los demás filtros y la regla de gestión (anclas de 20261001154153) no se
--   tocan: el cuerpo nuevo sale del vivo por sustituciones exactas, no se reteclea. Una sola firma:
--   se retira la de 13 (dos candidatas romperían PostgREST) y su exención analítica se MUEVE a la
--   de 14 (misma clase, tipo y fecha de declaración) y se resella. El orden de las listas no cambia.
--
-- ORDEN DE PUBLICACIÓN: servidor primero, pantalla después. El frente nuevo envía `p_potencial` y
--   sin esta migración recibiría PGRST202; los frentes publicados no lo envían y siguen igual.
--
-- REVERSA: `supabase/scripts/potencial-lead/reversa-filtro.sql`, tras retirar el frente que envía
--   `p_potencial`. Quita la firma de 14 y el ayudante, reinstala la de 13 byte a byte (md5
--   bf06666f…), devuelve la exención analítica a su firma y resella. No toca datos.
--
-- Las huellas se midieron con `search_path` vacío y sin comillas forzadas, que se fijan abajo para
-- la transacción: el texto de `pg_get_functiondef` cambia con el `search_path` de la sesión y con
-- `quote_all_identifiers`.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';
set local quote_all_identifiers = off;

lock table private.analitica_leads_citas_exenciones,
  private.analitica_lc_sello in share row exclusive mode;

do $preflight$
declare
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f14 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
  f13_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  v_huellas text;
  v_policies text;
begin
  -- 1. La función viva es la auditada: una sola firma (la de 13) y su cuerpo exacto.
  --    Guardas en positivo con `is not true`: un NULL también rechaza.
  if (
    to_regprocedure(f14) is null
    and to_regprocedure(f13) is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure(f13))) = 'bf06666fb8ef533a39a50c7d70420153'
    and to_regprocedure('private.cartera_potencial_fn()') is null
  ) is not true then
    raise exception 'PREFLIGHT: cartera_filtrada_fn no coincide con la version auditada, o esta migracion ya esta aplicada';
  end if;
  -- 2. Su declaración analítica está vigente (huella al día), es de inventario y la lista está
  --    sellada: esta migración la mueve y resella; no se resella a ciegas una lista alterada.
  if (
    exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto = f13_larga and c.declarada and c.huella_ok)
    and (select e.clase from private.analitica_leads_citas_exenciones e
          where e.objeto = f13_larga) = 'operativo'
    and (select s.sello from private.analitica_lc_sello s where s.id)
          = private.huella_exenciones_analitica_lc()
  ) is not true then
    raise exception 'PREFLIGHT: la declaracion analitica no esta vigente y sellada';
  end if;
  -- 3. La función sigue leyendo `crm.actividades` como INVOKER (reasignados, gestión, contacto).
  perform private.assert_actividades_de_lead_base();
  -- 4. El potencial está instalado como se ensayó: la tabla de la marca vigente con sus columnas,
  --    una fila por lead, RLS encendida, SIN grants para la API (por eso hace falta el ayudante),
  --    y su bandera.
  if (
    (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attnum)
       from pg_attribute a
      where a.attrelid = to_regclass('crm.lead_potencial') and a.attnum > 0 and not a.attisdropped)
      = 'id:uuid,lead_id:uuid,nivel:crm.nivel_potencial,origen:text,marcado_por:uuid,marcado_en:timestamp with time zone,creado_en:timestamp with time zone,actualizado_en:timestamp with time zone'
    and (select c.relrowsecurity from pg_class c where c.oid = to_regclass('crm.lead_potencial'))
    -- La premisa de la cartera INVOKER: la RLS de crm.leads está encendida.
    and (select c.relrowsecurity from pg_class c where c.oid = 'crm.leads'::regclass)
    -- Una fila por lead: la cartera une las marcas por `lead_id` y un duplicado repetiría el lead.
    and exists (select 1 from pg_index i
                 where i.indrelid = to_regclass('crm.lead_potencial') and i.indisunique and i.indisvalid
                   and i.indpred is null and i.indnkeyatts = 1
                   and i.indkey[0] = (select a.attnum from pg_attribute a
                                       where a.attrelid = i.indrelid and a.attname = 'lead_id'))
    and not has_table_privilege('authenticated', 'crm.lead_potencial', 'SELECT')
    and not has_any_column_privilege('authenticated', 'crm.lead_potencial', 'SELECT')
    and not has_table_privilege('anon', 'crm.lead_potencial', 'SELECT')
    and not has_any_column_privilege('anon', 'crm.lead_potencial', 'SELECT')
    and (select count(*) from crm.multiempresa_flags f where f.nombre = 'potencial_lead') = 1
    and (select array_agg(e.enumlabel::text order by e.enumsortorder)
           from pg_enum e where e.enumtypid = to_regtype('crm.nivel_potencial'))
        = array['frio', 'tibio', 'estrella']
  ) is not true then
    raise exception 'PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo';
  end if;
  -- 5. El ámbito del ayudante descansa en estos ayudantes, los mismos de `leads_select`:
  --    identidad por cuerpo + DEFINER + volatilidad + configuración + dueño.
  select string_agg(
           p.oid::regprocedure::text || '=' ||
           md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
               || coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.proowner::regrole::text),
           ' ' order by p.oid::regprocedure::text)
    into v_huellas
  from pg_proc p
  where p.oid in (to_regprocedure('private.rol_crm(uuid)'),
                  to_regprocedure('private.vendedor_ids_visibles(uuid)'),
                  to_regprocedure('private.es_lector_global()'),
                  to_regprocedure('private.puede_acceder_crm()'),
                  to_regprocedure('crm.bandera_activa(text)'));
  if v_huellas is distinct from
       'crm.bandera_activa(text)=bb817f2b07b561356959f25dc3aae4dc'
    || ' private.es_lector_global()=5b8ac0c37dcbf5b82057d7b98c65c303'
    || ' private.puede_acceder_crm()=4e2c1caf7ead51be450d5018be4c6092'
    || ' private.rol_crm(uuid)=16960a2a21cc5c372431c2dd67acafe4'
    || ' private.vendedor_ids_visibles(uuid)=45ae492c03234b80336c0b8f5c8ac09b' then
    raise exception 'PREFLIGHT: un ayudante de visibilidad no es el ensayado: %', coalesce(v_huellas, '(ninguno)');
  end if;
  -- Las policies que deciden qué leads se LEEN: exactamente la permisiva `leads_select` (la que el
  -- ayudante copia) y el gate restrictivo `crm_actor_activo_gate` (el que invoca). Una policy de
  -- lectura nueva o un cambio en estas dos dejaría al ayudante viendo de más o de menos.
  select string_agg(
           pol.polname::text || '|' || pol.polcmd::text || '|' || pol.polpermissive::text || '|'
           || pol.polroles::regrole[]::text || '|' || md5(pg_get_expr(pol.polqual, pol.polrelid)),
           ' ## ' order by pol.polname)
    into v_policies
  from pg_policy pol
  where pol.polrelid = 'crm.leads'::regclass and pol.polcmd in ('r', '*');
  if v_policies is distinct from
       'crm_actor_activo_gate|*|false|{authenticated}|c5e6c90632bc616212336e1d089a68b3'
    || ' ## leads_select|r|true|{authenticated}|073deaeb5700bac14209ec795b71567e' then
    raise exception 'PREFLIGHT: las policies de lectura de crm.leads no son las ensayadas: %', coalesce(v_policies, '(ninguna)');
  end if;
  -- 6. La función INVOKER debe poder llamar a la bandera, y la API no.
  if (
    has_function_privilege('authenticated', 'crm.bandera_activa(text)', 'EXECUTE')
    and not has_function_privilege('anon', 'crm.bandera_activa(text)', 'EXECUTE')
    and has_schema_privilege('authenticated', 'private', 'USAGE')
  ) is not true then
    raise exception 'PREFLIGHT: los permisos de crm.bandera_activa o del esquema private no son los ensayados';
  end if;
  -- 7. Quién llama a la cartera en el servidor: solo el envoltorio `crm.resumen_cartera_fn`, con el
  --    cuerpo ensayado (no pasa filtros del llamante). Otro consumidor, o un envoltorio distinto,
  --    recibiría `resumen.potencial` sin haberse revisado.
  if (
    (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
       from pg_proc p where p.prosrc ~* 'cartera_filtrada_fn') = 'crm.resumen_cartera_fn()'
    and md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) = '4a896597486e8b23788a2b2497f16309'
  ) is not true then
    raise exception 'PREFLIGHT: los consumidores de servidor de la cartera no son los ensayados';
  end if;
end;
$preflight$;

-- Foto de lo que NO debe cambiar: contrato de seguridad de la función, censo analítico,
-- declaraciones ajenas, la propia declaración (clase, tipo y fecha) y el consumidor.
create temporary table cartera_potencial_preflight on commit drop as
select
  (select to_jsonb(p) from (select proowner::regrole::text as duenio,
      prosecdef, provolatile, proconfig, proacl
    from pg_proc where oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)'::regprocedure) p) as contrato,
  (select count(*) from private.contadores_crudos_leads_citas()) as censo,
  (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
    from private.contadores_crudos_leads_citas() c
    where not (c.declarada and c.huella_ok)) as censo_rojo,
  (select jsonb_agg(to_jsonb(e) order by e.objeto)
    from private.analitica_leads_citas_exenciones e
    where e.objeto <> 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') as otras,
  (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
    from private.analitica_leads_citas_exenciones e
    where e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') as declaracion,
  md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) as resumen_md5;

-- ── 1 · Ayudante: la marca vigente de los leads del ámbito ─────────────────────
create function private.cartera_potencial_fn()
returns table(lead_id uuid, nivel text)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_visibles uuid[];
begin
  -- El gate RESTRICTIVO de crm.leads (crm_actor_activo_gate) se INVOCA en vez de copiarse.
  if v_uid is null or private.puede_acceder_crm() is not true then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  -- Con la bandera apagada no se lee nada (igual que crm.potencial_leads_fn).
  if crm.bandera_activa('potencial_lead') is not true then
    return;
  end if;
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  -- Se resuelve UNA vez (la policy lo evalúa como SubPlan en cada fila).
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  return query
    select p.lead_id, p.nivel::text
    from crm.lead_potencial p
    join crm.leads l on l.id = p.lead_id
    -- ── ESPEJO EXACTO de la policy leads_select (fijada por md5 en el preflight) ──
    --   activo = true and ( vendedor_id in (vendedor_ids_visibles(uid))
    --                       or (vendedor_id is null and asignado_supervisor_id in (...))
    --                       or rol_crm(uid) = 'gerencia' or es_lector_global() )
    where l.activo = true
      and (
        l.vendedor_id = any (v_visibles)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any (v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      );
end;
$$;
alter function private.cartera_potencial_fn() owner to postgres;
revoke all on function private.cartera_potencial_fn() from public, anon, authenticated, service_role;
grant execute on function private.cartera_potencial_fn() to authenticated;
comment on function private.cartera_potencial_fn() is
  'Ayudante de crm.cartera_filtrada_fn: (lead_id, nivel) de la marca de potencial vigente de los leads que el actor puede ver (espejo exacto de la policy leads_select: activos, de sus analistas visibles, parqueados en un supervisor visible, o todo para gerencia y lector global). SECURITY DEFINER porque crm.lead_potencial no tiene grants de API; exige sesion y el gate del CRM (42501). Con la bandera potencial_lead apagada no devuelve filas. No entrega la bandeja del reparto que la RLS no deja ver: dentro de crm.resumen_cartera_fn esas marcas cuentan como sin marca. No esta expuesto en la API (esquema private).';

-- ── 2 · La cartera: una sola firma, la de 14 ───────────────────────────────────
drop function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text);

create function crm.cartera_filtrada_fn(
  p_limite integer default 50,
  p_antes_de timestamptz default null,
  p_antes_id uuid default null,
  p_etapa text default null,
  p_vendedor_id uuid default null,
  p_sin_asignar boolean default false,
  p_texto text default null,
  p_desde date default null,
  p_hasta date default null,
  p_origen text default null,
  p_procedencia text default null,
  p_reasignados boolean default false,
  p_gestion text default null,
  p_potencial text default null
)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_global boolean;
  v_visibles uuid[];
  v_texto text := nullif(btrim(p_texto), '');
  v_reparto boolean;
  v_digitos text;
  v_salida jsonb;
  v_potencial boolean;
begin
  if v_uid is null or not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 200
     or (p_antes_de is null) <> (p_antes_id is null)
     or (p_sin_asignar and p_vendedor_id is not null)
     or (p_sin_asignar and p_desde is not null)
     or (p_desde is null) <> (p_hasta is null)
     or p_desde > p_hasta
     or p_hasta > (now() at time zone 'America/Lima')::date
     or (p_etapa is not null and p_etapa not in
       ('nuevo','contactado','reunion_agendada','propuesta_enviada','convertido','descartado'))
     -- Mismo dominio que el CHECK de crm.leads.origen: los 5 vigentes y los 3
     -- históricos (web, campania, whatsapp) siguen siendo consultables.
     or (p_origen is not null and p_origen not in
       ('referido','landing','formulario','oficina','otro','web','campania','whatsapp'))
     -- Procedencia: 'sistema' (puente automático) o 'manual' (una persona).
     -- Otro valor se rechaza: nunca un «cero resultados» silencioso.
     or (p_procedencia is not null and p_procedencia not in ('sistema','manual'))
     -- Gestión: 'con_gestion' (el titular actual ya intentó el contacto) o
     -- 'sin_gestion' (el resto). Otro valor se rechaza, igual que arriba.
     or (p_gestion is not null and p_gestion not in ('con_gestion','sin_gestion'))
     -- Potencial: uno de los tres niveles o 'sin_marca' (leads sin marca). Otro valor se
     -- rechaza, igual que arriba.
     or (p_potencial is not null and p_potencial not in ('estrella','tibio','frio','sin_marca'))
     or (v_texto is not null and length(v_texto) < 2) then
    raise exception 'Filtros de cartera inválidos' using errcode = '22023';
  end if;
  v_texto := left(v_texto, 80);
  v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_reparto := private.cartera_puede_operar_reparto_fn();
  -- El potencial solo existe con su bandera encendida y para quien tiene ámbito de FILAS (global
  -- o con analistas visibles). Sin eso la respuesta es la de siempre (sin `resumen.potencial`) y
  -- pedir el filtro se rechaza como en la puerta de marcar. Quien solo opera el reparto no lee
  -- leads por su RLS: tampoco recibe conteos por nivel (ni dentro de crm.resumen_cartera_fn).
  v_potencial := crm.bandera_activa('potencial_lead') is true
    and (coalesce(v_global, false) or cardinality(v_visibles) > 0);
  if p_potencial is not null and not v_potencial then
    raise exception 'El potencial del lead no está habilitado' using errcode = '55000';
  end if;

  with recepciones as materialized (
    select * from private.cartera_recepciones_fn(p_desde,p_hasta)
  ), marcas as materialized (
    -- Marca vigente de los leads que el actor puede ver. Ayudante DEFINER: las tablas del
    -- potencial no tienen grants de API. Sin potencial para este actor, ni se le llama.
    select m.lead_id, m.nivel from private.cartera_potencial_fn() m where v_potencial
  ), previa as materialized (
    select l.id, l.nombre_completo, l.telefono, l.telefono_alternativo,
      l.telefono_alternativo_crudo, l.correo, l.dni, l.genero,
      l.fecha_nacimiento, l.distrito, l.origen, l.etapa, l.motivo_descarte,
      l.monto_estimado, l.moneda, l.categoria_interes, l.vendedor_id,
      l.asignado_supervisor_id, l.creado_en, l.tenencia_desde, l.convertido_en,
      l.contrato_id, l.actualizado_en, l.activo, l.nota, l.no_contactar,
      -- Procedencia sellada por el servidor: `alta_manual` (columna del 01/09)
      -- o, para los leads anteriores a ella, tener autor. El puente inserta
      -- como service_role sin autor: nunca cae en 'manual'.
      case when l.alta_manual or l.creado_por is not null then 'manual' else 'sistema' end as procedencia,
      l.creado_por as cargado_por,
      coalesce(mov.reasignado, false) as reasignado,
      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada,
      mk.nivel as potencial_nivel
    from crm.leads l
    -- Una primera entrega desde la cola tiene vendedor_anterior NULL. Solo
    -- cuenta un analista ANTERIOR, incluso si volvió al mismo titular tras
    -- pasar por la bandeja. El evento lo emite el trigger del servidor.
    left join lateral (
      select true as reasignado
      from crm.actividades a
      where l.vendedor_id is not null
        and a.lead_id = l.id
        and a.tipo = 'reasignacion'
        and a.metadata ->> 'vendedor_anterior' is not null
      limit 1
    ) mov on true
    left join recepciones r on r.lead_id = l.id
    left join marcas mk on mk.lead_id = l.id
    where l.activo is true
      and (v_global or l.vendedor_id = any(v_visibles)
        or (l.vendedor_id is null and (l.asignado_supervisor_id = any(v_visibles)
          or v_reparto)))
      and (p_desde is null or r.lead_id is not null)
      -- La consulta por recepción puede recuperar convertidos antiguos que
      -- siguen siendo visibles por RLS; sin fechas se conserva la ventana operativa.
      and (p_desde is not null or l.etapa <> 'convertido' or l.convertido_en >= now() - interval '45 days')
      and (p_etapa is null or l.etapa = p_etapa)
      -- El origen acota la MISMA base: filas, totales, capital y embudo juntos.
      and (p_origen is null or l.origen = p_origen)
      -- La procedencia acota esa misma base, con la misma regla que la columna
      -- `procedencia` de arriba.
      and (p_procedencia is null or (l.alta_manual or l.creado_por is not null) = (p_procedencia = 'manual'))
      and (not coalesce(p_reasignados,false) or coalesce(mov.reasignado,false))
      -- Gestión vigente: el titular ACTUAL ya intentó el contacto desde que
      -- recibió el lead (`tenencia_desde`, que se renueva al reasignar y al
      -- reabrir). Lo que gestionó un titular anterior no cuenta, ni un resultado
      -- de llamada deshecho (`deshecho_en`: no ocurrió); sin titular o sin
      -- tenencia no hay gestión. Acota la MISMA base; el payload no cambia.
      and (p_gestion is null or (l.vendedor_id is not null
        and l.tenencia_desde is not null
        and exists (select 1 from crm.actividades g
          where g.lead_id = l.id
            and g.tipo in ('llamada_realizada','llamada_no_contestada',
              'whatsapp_enviado','whatsapp_recibido','reunion_realizada')
            and g.creado_en >= l.tenencia_desde
            and not (g.metadata ? 'deshecho_en'))) = (p_gestion = 'con_gestion'))
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
      and (not coalesce(p_sin_asignar,false) or l.vendedor_id is null)
      and (v_texto is null or strpos(lower(l.nombre_completo),lower(v_texto)) > 0
        or (length(v_digitos) >= 3 and (strpos(l.telefono,v_digitos) > 0
          or strpos(l.telefono_alternativo,v_digitos) > 0 or strpos(l.dni,v_digitos) > 0)))
  ), base as not materialized (
    -- El potencial recorta DESPUÉS de los demás filtros: `previa` alimenta los conteos por
    -- nivel (cuántos hay de cada uno con los demás filtros puestos, sin que cambien al elegir
    -- uno) y `base`, como siempre, las filas, los totales, el capital y el embudo.
    select pv.* from previa pv
    where p_potencial is null
      or (p_potencial = 'sin_marca' and pv.potencial_nivel is null)
      or pv.potencial_nivel = p_potencial
  ), pagina as (
    select b.* from base b
    where p_antes_de is null or b.actualizado_en < p_antes_de
      or (b.actualizado_en = p_antes_de and b.id > p_antes_id)
    order by b.actualizado_en desc,b.id asc limit p_limite
  ), filas as (
    select p.*, uc.creado_en as ultimo_contacto_en
    from pagina p left join lateral (
      select act.creado_en from crm.actividades act
      where act.lead_id = p.id and act.tipo in ('llamada_realizada',
        'llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
      order by act.creado_en desc limit 1
    ) uc on true
  ), metricas as (
    select count(*) as vivos,
      count(*) filter(where etapa not in ('convertido','descartado')) as abiertos,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null) as asignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is null) as parkeados,
      count(*) filter(where etapa = 'convertido') as convertidos,
      count(*) filter(where etapa = 'descartado') as descartados,
      count(*) filter(where reasignado) as reasignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='PEN') as asignados_pen,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='USD') as asignados_usd
    from base
  ), capital as (
    select jsonb_object_agg(tipo,valor) as valor from (
      select t.tipo, jsonb_build_object(
        'pen',coalesce(sum(b.monto_estimado) filter(where b.moneda='PEN'),0),
        'usd',coalesce(sum(b.monto_estimado) filter(where b.moneda='USD'),0)) as valor
      from (values('asignado'),('parkeado'),('ganado')) t(tipo)
      left join base b on (t.tipo='ganado' and b.etapa='convertido')
        or (b.etapa not in ('convertido','descartado') and
          ((t.tipo='asignado' and b.vendedor_id is not null) or (t.tipo='parkeado' and b.vendedor_id is null)))
      group by t.tipo
    ) montos
  )
  select jsonb_build_object('version',1,'generado_en',now(),
    'desde',p_desde,'hasta',p_hasta,'origen',p_origen,'procedencia',p_procedencia,
    'reasignados',coalesce(p_reasignados,false),
    -- La columna de trabajo `potencial_nivel` no viaja: las filas tienen la forma de siempre.
    'items',coalesce((select jsonb_agg(to_jsonb(f) - 'potencial_nivel' order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
    'resumen',jsonb_build_object('totales',(select to_jsonb(m) from metricas m),
      'capital',(select valor from capital),
      'conversion',jsonb_build_object(
        'convertidos',(select count(*) from base where etapa='convertido' and vendedor_id is not null),
        'base',(select count(*) from base where vendedor_id is not null),
        'pct',coalesce((select round(100.0 * count(*) filter(where etapa='convertido')
          / nullif(count(*),0))::int from base where vendedor_id is not null),0)),
      'descartes',jsonb_build_object(
        'total',(select count(*) from base where etapa='descartado'),
        'sin_motivo',(select count(*) from base where etapa='descartado' and motivo_descarte is null),
        'por_motivo',(select coalesce(jsonb_agg(to_jsonb(d) order by d.n desc,d.motivo),'[]'::jsonb)
          from (select motivo_descarte as motivo,count(*) as n from base
            where etapa='descartado' and motivo_descarte is not null group by motivo_descarte) d)),
      'sin_tocar',(select count(*) from base b where b.etapa not in('convertido','descartado')
        and b.vendedor_id is not null and not exists(select 1 from crm.actividades a
          where a.lead_id=b.id and a.tipo in ('llamada_realizada','llamada_no_contestada',
            'whatsapp_enviado','whatsapp_recibido','reunion_realizada'))),
      'embudo',(select jsonb_agg(jsonb_build_object('etapa',e.etapa,'n',
        (select count(*) from base b where b.etapa=e.etapa)) order by e.ord)
        from (values('nuevo',1),('contactado',2),('reunion_agendada',3),
          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord)))
      -- Conteos por nivel sobre `previa` (antes de `p_potencial`) y el eco del filtro. Solo con
      -- el potencial vigente para el actor: si no, el resumen es byte a byte el de antes.
      || case when v_potencial then jsonb_build_object('potencial',(select jsonb_build_object(
          'filtro',p_potencial,
          'estrella',count(*) filter(where pv.potencial_nivel='estrella'),
          'tibio',count(*) filter(where pv.potencial_nivel='tibio'),
          'frio',count(*) filter(where pv.potencial_nivel='frio'),
          'sin_marca',count(*) filter(where pv.potencial_nivel is null)) from previa pv))
        else '{}'::jsonb end)
  into v_salida;
  return v_salida;
end;
$$;

revoke all on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text) from public, anon, authenticated, service_role;
grant execute on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text) to authenticated;
comment on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text) is
  'Inventario de Leads con filtros comunes, incluidos reasignados (titular actual con una asignacion anterior a un analista), gestion (p_gestion: con_gestion = el titular actual ya intento el contacto desde tenencia_desde, sin contar resultados de llamada deshechos; sin_gestion = el resto) y potencial (p_potencial: estrella, tibio, frio o sin_marca; con la bandera potencial_lead apagada se rechaza con 55000). Listado y resumen salen de la misma base; resumen.potencial cuenta cada nivel con los demas filtros puestos, antes de aplicar p_potencial; solo viaja con la bandera encendida y para quien tiene ambito de filas (global o con analistas visibles), y cuenta solo las marcas que el actor puede ver por la RLS de crm.leads (una marca que no puede ver cuenta como sin_marca).';

-- La declaración analítica se MUEVE a la firma nueva (misma fila: conserva clase, tipo y
-- fecha), con la huella del cuerpo nuevo, y la lista se resella.
update private.analitica_leads_citas_exenciones e set
  objeto = p.oid::regprocedure::text,
  huella = md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  razon = 'Inventario operativo unico para listado y resumen: filtros de etapa, analista, busqueda, recepcion, origen, procedencia, reasignacion entre analistas, gestion del titular actual y potencial del lead. No calcula conversion mensual.'
from pg_proc p
where p.oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)'::regprocedure
  and e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
  where id;

do $postflight$
declare
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f14 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
  f14_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
  ayudante constant text := 'private.cartera_potencial_fn()';
  pre record;
begin
  select * into strict pre from pg_temp.cartera_potencial_preflight;
  -- 1. Una sola firma, la de 14, con el cuerpo ENSAYADO (md5 medido en el banco con
  --    search_path vacío) y el mismo contrato de seguridad que la que sustituye.
  if (
    to_regprocedure(f13) is null
    and to_regprocedure(f14) is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure(f14))) = '23a63cc3965472b9db85aa81cadffbeb'
    and not has_function_privilege('anon', f14, 'EXECUTE')
    and not has_function_privilege('service_role', f14, 'EXECUTE')
    and has_function_privilege('authenticated', f14, 'EXECUTE')
    and (select to_jsonb(p) from (select proowner::regrole::text as duenio,
            prosecdef, provolatile, proconfig, proacl
          from pg_proc where oid = to_regprocedure(f14)) p) = pre.contrato
  ) is not true then
    raise exception 'POSTFLIGHT: firma, cuerpo, permisos o contrato invalido';
  end if;
  -- 2. El ayudante: el cuerpo ENSAYADO (md5 medido en el banco: gate, bandera y espejo de la
  --    policy; Codex f3b r1), DEFINER, STABLE, dueño postgres, configuración EXACTA (solo
  --    search_path vacío), ACL explícita (postgres y authenticated; authenticated solo EXECUTE y
  --    sin opción de concederlo), permisos EFECTIVOS (authenticated sí; anon y service_role no) y
  --    sin conteos.
  if (
    md5(pg_get_functiondef(to_regprocedure(ayudante))) = '73e993d618b203cdbe21e8127f7ea5b4'
    and exists (select 1 from pg_proc p
             where p.oid = to_regprocedure(ayudante) and p.prosecdef
               and p.proowner = 'postgres'::regrole and p.provolatile = 's'
               and p.proconfig = array['search_path=""']::text[] and p.proacl is not null
               and p.prosrc !~* '(count|sum)\s*\(')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                     where p.oid = to_regprocedure(ayudante)
                       and (a.grantee not in ('postgres'::regrole, 'authenticated'::regrole)
                            or (a.grantee = 'authenticated'::regrole
                                and (a.is_grantable or a.privilege_type <> 'EXECUTE'))))
    and has_function_privilege('authenticated', ayudante, 'EXECUTE')
    and not has_function_privilege('anon', ayudante, 'EXECUTE')
    and not has_function_privilege('service_role', ayudante, 'EXECUTE')
  ) is not true then
    raise exception 'POSTFLIGHT: el ayudante no quedo con el cuerpo ensayado/DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated';
  end if;
  -- 3. La tabla de la marca sigue sin grants para la API: esta migración no abre ninguno.
  if (
    not has_table_privilege('authenticated', 'crm.lead_potencial', 'SELECT')
    and not has_any_column_privilege('authenticated', 'crm.lead_potencial', 'SELECT')
    and not has_table_privilege('anon', 'crm.lead_potencial', 'SELECT')
    and not has_any_column_privilege('anon', 'crm.lead_potencial', 'SELECT')
  ) is not true then
    raise exception 'POSTFLIGHT: crm.lead_potencial quedo con algun grant de lectura para la API';
  end if;
  -- 4. El sello quedó vigente, la firma nueva está declarada con su huella y nada ajeno se
  --    movió: mismo censo, mismo conjunto en rojo (si lo había), mismas declaraciones ajenas,
  --    la propia conserva clase, tipo y fecha, y el consumidor `resumen_cartera_fn` intacto.
  if (
    (select s.sello from private.analitica_lc_sello s where s.id)
      = private.huella_exenciones_analitica_lc()
    and (select count(*) from private.contadores_crudos_leads_citas()) = pre.censo
    and exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto = f14_larga and c.declarada and c.huella_ok)
    and (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
           from private.contadores_crudos_leads_citas() c
          where not (c.declarada and c.huella_ok)) = pre.censo_rojo
    and (select jsonb_agg(to_jsonb(e) order by e.objeto)
           from private.analitica_leads_citas_exenciones e
          where e.objeto <> f14_larga) is not distinct from pre.otras
    and (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
           from private.analitica_leads_citas_exenciones e
          where e.objeto = f14_larga) = pre.declaracion
    and md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) = pre.resumen_md5
    and (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
           from pg_proc p where p.prosrc ~* 'cartera_filtrada_fn') = 'crm.resumen_cartera_fn()'
  ) is not true then
    raise exception 'POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno';
  end if;
  perform private.assert_actividades_de_lead_base();
  -- 5. La policy que el ayudante copia sigue siendo la del preflight al terminar.
  if (
    (select string_agg(pol.polname::text || '|' || pol.polcmd::text || '|' || pol.polpermissive::text || '|'
              || pol.polroles::regrole[]::text || '|' || md5(pg_get_expr(pol.polqual, pol.polrelid)),
              ' ## ' order by pol.polname)
       from pg_policy pol
      where pol.polrelid = 'crm.leads'::regclass and pol.polcmd in ('r', '*'))
    = 'crm_actor_activo_gate|*|false|{authenticated}|c5e6c90632bc616212336e1d089a68b3'
      || ' ## leads_select|r|true|{authenticated}|073deaeb5700bac14209ec795b71567e'
  ) is not true then
    raise exception 'POSTFLIGHT: las policies de lectura de crm.leads cambiaron durante la instalacion';
  end if;
  -- 6. Sin sesión, el ayudante y la función se niegan (aquí no hay sesión de usuario).
  --    Y por SU guarda («No autorizado»), no por cualquier otro 42501.
  begin
    perform 1 from private.cartera_potencial_fn();
    raise exception 'POSTFLIGHT: el ayudante acepto una llamada sin sesion' using errcode = 'P0001';
  exception when insufficient_privilege then
    if sqlerrm is distinct from 'No autorizado' then
      raise exception 'POSTFLIGHT: el ayudante rechazo por otro motivo: %', sqlerrm using errcode = 'P0001';
    end if;
  end;
  begin
    perform crm.cartera_filtrada_fn(p_limite => 1, p_potencial => 'estrella');
    raise exception 'POSTFLIGHT: la cartera acepto una llamada sin sesion' using errcode = 'P0001';
  exception when insufficient_privilege then
    if sqlerrm is distinct from 'No autorizado' then
      raise exception 'POSTFLIGHT: la cartera rechazo por otro motivo: %', sqlerrm using errcode = 'P0001';
    end if;
  end;
  raise notice 'cartera_filtro_potencial OK: firma unica de 14 argumentos, ayudante DEFINER con el cuerpo ensayado y solo para authenticated, contrato de seguridad intacto, declaracion analitica movida y sellada.';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
```

### Diferencia EXACTA entre el cuerpo de la firma de 13 (vivo) y el de 14 (nuevo)
```diff
@@ -13,3 +13,4 @@
   p_reasignados boolean default false,
-  p_gestion text default null
+  p_gestion text default null,
+  p_potencial text default null
 )
@@ -24,2 +25,3 @@
   v_salida jsonb;
+  v_potencial boolean;
 begin
@@ -47,2 +49,5 @@
      or (p_gestion is not null and p_gestion not in ('con_gestion','sin_gestion'))
+     -- Potencial: uno de los tres niveles o 'sin_marca' (leads sin marca). Otro valor se
+     -- rechaza, igual que arriba.
+     or (p_potencial is not null and p_potencial not in ('estrella','tibio','frio','sin_marca'))
      or (v_texto is not null and length(v_texto) < 2) then
@@ -55,2 +60,11 @@
   v_reparto := private.cartera_puede_operar_reparto_fn();
+  -- El potencial solo existe con su bandera encendida y para quien tiene ámbito de FILAS (global
+  -- o con analistas visibles). Sin eso la respuesta es la de siempre (sin `resumen.potencial`) y
+  -- pedir el filtro se rechaza como en la puerta de marcar. Quien solo opera el reparto no lee
+  -- leads por su RLS: tampoco recibe conteos por nivel (ni dentro de crm.resumen_cartera_fn).
+  v_potencial := crm.bandera_activa('potencial_lead') is true
+    and (coalesce(v_global, false) or cardinality(v_visibles) > 0);
+  if p_potencial is not null and not v_potencial then
+    raise exception 'El potencial del lead no está habilitado' using errcode = '55000';
+  end if;
 
@@ -58,3 +72,7 @@
     select * from private.cartera_recepciones_fn(p_desde,p_hasta)
-  ), base as materialized (
+  ), marcas as materialized (
+    -- Marca vigente de los leads que el actor puede ver. Ayudante DEFINER: las tablas del
+    -- potencial no tienen grants de API. Sin potencial para este actor, ni se le llama.
+    select m.lead_id, m.nivel from private.cartera_potencial_fn() m where v_potencial
+  ), previa as materialized (
     select l.id, l.nombre_completo, l.telefono, l.telefono_alternativo,
@@ -71,3 +89,4 @@
       coalesce(mov.reasignado, false) as reasignado,
-      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada
+      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada,
+      mk.nivel as potencial_nivel
     from crm.leads l
@@ -86,2 +105,3 @@
     left join recepciones r on r.lead_id = l.id
+    left join marcas mk on mk.lead_id = l.id
     where l.activo is true
@@ -119,2 +139,10 @@
           or strpos(l.telefono_alternativo,v_digitos) > 0 or strpos(l.dni,v_digitos) > 0)))
+  ), base as not materialized (
+    -- El potencial recorta DESPUÉS de los demás filtros: `previa` alimenta los conteos por
+    -- nivel (cuántos hay de cada uno con los demás filtros puestos, sin que cambien al elegir
+    -- uno) y `base`, como siempre, las filas, los totales, el capital y el embudo.
+    select pv.* from previa pv
+    where p_potencial is null
+      or (p_potencial = 'sin_marca' and pv.potencial_nivel is null)
+      or pv.potencial_nivel = p_potencial
   ), pagina as (
@@ -158,3 +186,4 @@
     'reasignados',coalesce(p_reasignados,false),
-    'items',coalesce((select jsonb_agg(to_jsonb(f) order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
+    -- La columna de trabajo `potencial_nivel` no viaja: las filas tienen la forma de siempre.
+    'items',coalesce((select jsonb_agg(to_jsonb(f) - 'potencial_nivel' order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
     'resumen',jsonb_build_object('totales',(select to_jsonb(m) from metricas m),
@@ -179,3 +208,12 @@
         from (values('nuevo',1),('contactado',2),('reunion_agendada',3),
-          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord))))
+          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord)))
+      -- Conteos por nivel sobre `previa` (antes de `p_potencial`) y el eco del filtro. Solo con
+      -- el potencial vigente para el actor: si no, el resumen es byte a byte el de antes.
+      || case when v_potencial then jsonb_build_object('potencial',(select jsonb_build_object(
+          'filtro',p_potencial,
+          'estrella',count(*) filter(where pv.potencial_nivel='estrella'),
+          'tibio',count(*) filter(where pv.potencial_nivel='tibio'),
+          'frio',count(*) filter(where pv.potencial_nivel='frio'),
+          'sin_marca',count(*) filter(where pv.potencial_nivel is null)) from previa pv))
+        else '{}'::jsonb end)
   into v_salida;
```

### supabase/scripts/potencial-lead/reversa-filtro.sql (GENERADA; sin el cuerpo de la función de 13)
```sql
-- GENERADO por banco/generar-anterior-y-reversa.py. No editar a mano.
-- REVERSA de 20261001212341_crm_cartera_filtro_potencial (fase 3, entrega B).
-- ANTES: retirar el frente que envía `p_potencial` (con la firma de 13 recibiría PGRST202).
-- Quita la firma de 14 y el ayudante private.cartera_potencial_fn, reinstala la de 13 byte a byte
-- (md5 bf06666fb8ef533a39a50c7d70420153, el del postflight de 20261001154153), devuelve la exención analítica a su firma
-- con su razón y resella. No toca datos: las marcas y su historial se quedan. Conserva la fila de
-- schema_migrations: anotarlo en MIGRACIONES.md. Debe correr ANTES que la reversa de la migración
-- de gestión (`scripts/cartera-gestion/reversa.sql`), que exige la firma de 13.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';
set local quote_all_identifiers = off;

lock table private.analitica_leads_citas_exenciones,
  private.analitica_lc_sello in share row exclusive mode;

do $guarda$
begin
  if (
    to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') is null
    and to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)') is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)'))) = '23a63cc3965472b9db85aa81cadffbeb'
    and to_regprocedure('private.cartera_potencial_fn()') is not null
    and md5(pg_get_functiondef(to_regprocedure('private.cartera_potencial_fn()'))) = '73e993d618b203cdbe21e8127f7ea5b4'
  ) is not true then
    raise exception 'REVERSA filtro_potencial: la entrega B no esta aplicada tal como se publico';
  end if;
  if (
    exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)' and c.declarada and c.huella_ok)
    and (select s.sello from private.analitica_lc_sello s where s.id)
          = private.huella_exenciones_analitica_lc()
  ) is not true then
    raise exception 'REVERSA filtro_potencial: la declaracion analitica no esta vigente y sellada';
  end if;
  -- Nadie más depende del ayudante (solo lo nombra la cartera) ni pasa `p_potencial` desde el
  -- servidor: plpgsql enlaza tarde y ese consumidor fallaría al ejecutarse, no ahora.
  if exists (select 1 from pg_proc p
              where (p.prosrc ilike '%cartera_potencial_fn%' or p.prosrc ~* 'p_potencial\s*=>')
                and p.oid not in (to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)'), to_regprocedure('private.cartera_potencial_fn()'))) then
    raise exception 'REVERSA filtro_potencial: otra funcion usa private.cartera_potencial_fn o pasa p_potencial';
  end if;
end;
$guarda$;

create temporary table cartera_potencial_reversa on commit drop as
select
  (select to_jsonb(p) from (select proowner::regrole::text as duenio,
      prosecdef, provolatile, proconfig, proacl
    from pg_proc where oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)'::regprocedure) p) as contrato,
  (select count(*) from private.contadores_crudos_leads_citas()) as censo,
  (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
    from private.contadores_crudos_leads_citas() c
    where not (c.declarada and c.huella_ok)) as censo_rojo,
  (select jsonb_agg(to_jsonb(e) order by e.objeto)
    from private.analitica_leads_citas_exenciones e
    where e.objeto <> 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)') as otras,
  (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
    from private.analitica_leads_citas_exenciones e
    where e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)') as declaracion,
  md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) as resumen_md5;

drop function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text);

-- [aquí va, byte a byte, el `create function crm.cartera_filtrada_fn(… 13 argumentos …)` de 20261001154153: 183 líneas, generado desde ese archivo]

revoke all on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text) from public, anon, authenticated, service_role;
grant execute on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text) to authenticated;
comment on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text) is
  'Inventario de Leads con filtros comunes, incluidos reasignados (titular actual con una asignacion anterior a un analista) y gestion (p_gestion: con_gestion = el titular actual ya intento el contacto desde tenencia_desde, sin contar resultados de llamada deshechos; sin_gestion = el resto; no cambia la forma de la respuesta). Sistema/Manual conserva el alta. Filas, totales y embudo desde la misma base, bajo RLS.';

update private.analitica_leads_citas_exenciones e set
  objeto = p.oid::regprocedure::text,
  huella = md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  razon = 'Inventario operativo unico para listado y resumen: filtros de etapa, analista, busqueda, recepcion, origen, procedencia, reasignacion entre analistas y gestion del titular actual. No calcula conversion mensual.'
from pg_proc p
where p.oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)'::regprocedure
  and e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
  where id;

drop function private.cartera_potencial_fn();

do $post$
declare
  pre record;
begin
  select * into strict pre from pg_temp.cartera_potencial_reversa;
  if (
    to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)') is null
    and to_regprocedure('private.cartera_potencial_fn()') is null
    and to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)'))) = 'bf06666fb8ef533a39a50c7d70420153'
    and not has_function_privilege('anon', 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)', 'EXECUTE')
    and not has_function_privilege('service_role', 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)', 'EXECUTE')
    and has_function_privilege('authenticated', 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)', 'EXECUTE')
    and (select to_jsonb(p) from (select proowner::regrole::text as duenio,
            prosecdef, provolatile, proconfig, proacl
          from pg_proc where oid = to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)')) p) = pre.contrato
  ) is not true then
    raise exception 'REVERSA filtro_potencial: la firma de 13 no quedo como estaba';
  end if;
  if (
    (select s.sello from private.analitica_lc_sello s where s.id)
      = private.huella_exenciones_analitica_lc()
    and (select count(*) from private.contadores_crudos_leads_citas()) = pre.censo
    and exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)' and c.declarada and c.huella_ok)
    and (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
           from private.contadores_crudos_leads_citas() c
          where not (c.declarada and c.huella_ok)) = pre.censo_rojo
    and (select jsonb_agg(to_jsonb(e) order by e.objeto)
           from private.analitica_leads_citas_exenciones e
          where e.objeto <> 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') is not distinct from pre.otras
    and (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
           from private.analitica_leads_citas_exenciones e
          where e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') = pre.declaracion
    and md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) = pre.resumen_md5
  ) is not true then
    raise exception 'REVERSA filtro_potencial: cambio un contador, una declaracion o un consumidor ajeno';
  end if;
  raise notice 'REVERSA filtro_potencial OK: firma unica de 13 (md5 bf06666f…), sin ayudante, declaracion analitica devuelta y sellada. Las marcas se conservan.';
end;
$post$;
notify pgrst, 'reload schema';
commit;
```

### supabase/scripts/potencial-lead/verificar-filtro.sql
```sql
-- VERIFICACIÓN (solo lectura, termina SIEMPRE en raise) de 20261001212341_crm_cartera_filtro_potencial.
-- Se corre en producción después de aplicar y registrar. No escribe nada.
-- Permisos EFECTIVOS con has_function_privilege: una ACL nula significa «PUBLIC ejecuta».
do $v$
declare
  f14 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
  f14_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
  ayu constant text := 'private.cartera_potencial_fn()';
  v_firmas text; v_md5 text; v_md5_ayudante text; v_cartera text; v_ayudante text; v_forma text; v_acl_nula int; v_tabla text;
  v_declarada text; v_sello boolean; v_bandera boolean; v_marcas int; v_registro text;
begin
  -- Las huellas se miden como en la migración: sin search_path y sin comillas forzadas.
  perform set_config('search_path', '', true);
  perform set_config('quote_all_identifiers', 'off', true);
  select string_agg(p.oid::regprocedure::text, ' ## ' order by 1) into v_firmas
    from pg_proc p where p.proname = 'cartera_filtrada_fn' and p.pronamespace = 'crm'::regnamespace;
  if to_regprocedure(f14) is not null then
    v_md5 := md5(pg_get_functiondef(to_regprocedure(f14)));
    select string_agg(r.rol, ',' order by r.rol) into v_cartera
      from unnest(array['anon', 'authenticated', 'service_role']) r(rol) where has_function_privilege(r.rol, f14, 'EXECUTE');
  end if;
  if to_regprocedure(ayu) is not null then
    select string_agg(r.rol, ',' order by r.rol) into v_ayudante
      from unnest(array['anon', 'authenticated', 'service_role']) r(rol) where has_function_privilege(r.rol, ayu, 'EXECUTE');
    select (case when p.prosecdef then 'DEFINER' else 'INVOKER' end) || '/' || p.provolatile::text || '/' || coalesce(array_to_string(p.proconfig, ','), '')
           || '/' || p.proowner::regrole::text
      into v_forma from pg_proc p where p.oid = to_regprocedure(ayu);
    v_md5_ayudante := md5(pg_get_functiondef(to_regprocedure(ayu)));
  end if;
  select count(*) into v_acl_nula from pg_proc p where p.oid in (to_regprocedure(f14), to_regprocedure(ayu)) and p.proacl is null;
  select string_agg(r.rol, ',' order by r.rol) into v_tabla
    from unnest(array['anon', 'authenticated']) r(rol)
   where has_table_privilege(r.rol, 'crm.lead_potencial', 'SELECT') or has_any_column_privilege(r.rol, 'crm.lead_potencial', 'SELECT');
  select (c.declarada and c.huella_ok)::text into v_declarada from private.contadores_crudos_leads_citas() c where c.objeto = f14_larga;
  select (s.sello = private.huella_exenciones_analitica_lc()) into v_sello from private.analitica_lc_sello s where s.id;
  select f.activo into v_bandera from crm.multiempresa_flags f where f.nombre = 'potencial_lead';
  select count(*) into v_marcas from crm.lead_potencial;
  select coalesce(max(name), '(sin registrar)') into v_registro
    from supabase_migrations.schema_migrations where version = '20261001212341';
  raise exception 'VERIFICAR filtro_potencial: firmas [%] (debe ser una, la de 14), md5 de la cartera % (debe ser 23a63cc3965472b9db85aa81cadffbeb), md5 del ayudante % (debe ser 73e993d618b203cdbe21e8127f7ea5b4), ejecutan la cartera [%] (debe ser authenticated), ejecutan el ayudante [%] (debe ser authenticated), forma del ayudante [%] (debe ser DEFINER/s/search_path=""/postgres), funciones con ACL nula % (debe ser 0), leen la tabla de marcas por la API [%] (debe ser ninguno), declaración analítica vigente % (debe ser true), sello vigente % (debe ser true), bandera %, marcas vivas %, registro %',
    coalesce(v_firmas, '(ninguna)'), coalesce(v_md5, '(no existe)'), coalesce(v_md5_ayudante, '(no existe)'), coalesce(v_cartera, '(ninguno)'), coalesce(v_ayudante, '(ninguno)'),
    coalesce(v_forma, '(no existe)'), v_acl_nula, coalesce(v_tabla, 'ninguno'), coalesce(v_declarada, '(sin declarar)'), coalesce(v_sello::text, '(sin sello)'),
    coalesce(v_bandera::text, '(no existe)'), v_marcas, v_registro;
end $v$;
```

### supabase/scripts/potencial-lead/prueba-filtro.sql (completa; 145 casos)
```sql
-- Prueba sintética de 20261001212341_crm_cartera_filtro_potencial (fase 3, entrega B).
-- SOLO en un banco, como supabase_admin, en UNA transacción que termina en raise (no deja nada).
-- Necesita delante la función ANTERIOR (la firma de 13) como pg_temp.cartera_filtrada_anterior:
--   cat banco/anterior-13.sql prueba-filtro.sql | docker exec -i -e PGPASSWORD=postgres <banco> \
--     psql -U supabase_admin -h 127.0.0.1 -d postgres
-- (lo hace banco/ciclo-fase3b.sh). ⚠️ Nunca se llama a una función sin EXECUTE bajo `set role`
-- (tumba Postgres 17.6 con plan_filter): los permisos se leen del catálogo.
--
-- Mundo (el de prueba-lectura.sql más un lead): gerencia G · supervisor S1 con sub-supervisor S1n ·
-- analista V1 (de S1) y V1n (de S1n) · supervisor S2 con analista V2 · coordinador C (opera el
-- reparto) · directorio D · X con equipo inactivo · DH directorio HISTÓRICO · XP con el perfil
-- inactivo · P usuario solo del portal · DM pareja desalineada.
--   L1  V1  contactado  estrella                L1n V1n nuevo       tibio
--   L2  V2  contactado  estrella                LP  parqueado en S1 frío
--   LC  V1  convertido ayer, estrella           LD  V1  descartado  tibio
--   LI  V1  INACTIVO    estrella (nadie lo ve)  L3  V1  contactado  sin marca
--   LPV parqueado con «supervisor» V1, sin marca    LK  V1  contactado  tibio (bajó sola)
--   LZ  V1  contactado  estrella                LS  SIN ASIGNAR, sin marca
--   LSM SIN ASIGNAR (sin analista ni supervisor), tibio: solo lo ven gerencia y directorio. Dentro
--       de crm.resumen_cartera_fn (DEFINER) entra en la bandeja de quien opera el reparto, pero su
--       marca NO se le entrega: coordinación no recibe conteos por nivel.
--   LCS V2 convertido ayer, sin marca · LDS V2 descartado, sin marca (los cerrados también cuentan)
--   LCV V2 convertido hace 60 días, estrella: fuera de la ventana de 45 días, no aparece ni cuenta.
--   Además: L1 tiene tenencia y un contacto posterior (con gestión) y LK fue reasignado.
begin;
set local lock_timeout = '5s';

do $guarda$
begin
  if to_regprocedure('pg_temp.cartera_filtrada_anterior(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') is null then
    raise exception 'FILTRO: falta pg_temp.cartera_filtrada_anterior; corre: cat banco/anterior-13.sql prueba-filtro.sql | psql …';
  end if;
  -- La «anterior» es de verdad la anterior: el cuerpo de la firma de 13 de 20261001154153.
  if (select md5(p.prosrc) from pg_proc p
       where p.oid = to_regprocedure('pg_temp.cartera_filtrada_anterior(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)'))
     is distinct from 'cb7741fe73fe4da698943d78369bc4cc' then
    raise exception 'FILTRO: la función de comparación no es el cuerpo de la firma de 13';
  end if;
end;
$guarda$;

create temp table act (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into act (k) values ('G'), ('S1'), ('S1n'), ('V1'), ('V1n'), ('S2'), ('V2'), ('C'), ('D'), ('X'), ('DH'), ('XP'), ('P'), ('DM');
create temp table lds (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into lds (k) values ('L1'), ('L1n'), ('L2'), ('LP'), ('LC'), ('LD'), ('LI'), ('L3'), ('LPV'), ('LK'), ('LZ'), ('LS'), ('LSM'), ('LCS'), ('LDS'), ('LCV');
create temp table res (n serial, caso text, esperado text, obtenido text) on commit drop;

create function pg_temp.a(p_k text) returns uuid language sql as $$ select id from act where k = p_k $$;
create function pg_temp.l(p_k text) returns uuid language sql as $$ select id from lds where k = p_k $$;
create function pg_temp.esperar(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$
  insert into res (caso, esperado, obtenido) values (p_caso, p_esperado, coalesce(p_obtenido, '(null)'))
$$;

-- Fixtures sin disparadores (solo filas que cumplen los CHECK).
set local session_replication_role = replica;
insert into auth.users (id, email) select id, lower(k) || '@filtro.banco' from act;
insert into public.perfiles (id, nombre_completo, rol, activo)
  select id, 'FILTRO ' || k, case when k in ('D', 'DH', 'DM') then 'directorio' when k = 'G' then 'admin' else 'analista' end, k <> 'XP' from act;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  (pg_temp.a('G'), 'gerencia', null, true),
  (pg_temp.a('S1'), 'supervisor', null, true),
  (pg_temp.a('S1n'), 'supervisor', pg_temp.a('S1'), true),
  (pg_temp.a('V1'), 'vendedor', pg_temp.a('S1'), true),
  (pg_temp.a('V1n'), 'vendedor', pg_temp.a('S1n'), true),
  (pg_temp.a('S2'), 'supervisor', null, true),
  (pg_temp.a('V2'), 'vendedor', pg_temp.a('S2'), true),
  (pg_temp.a('C'), 'coordinador', null, true),
  (pg_temp.a('D'), 'directorio', null, true),
  (pg_temp.a('X'), 'vendedor', pg_temp.a('S1'), false),
  (pg_temp.a('XP'), 'vendedor', pg_temp.a('S1'), true),
  (pg_temp.a('DM'), 'vendedor', pg_temp.a('S1'), true);
-- actualizado_en escalonado: el orden de la lista (actualizado_en desc, id) queda determinado.
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, asignado_supervisor_id, activo, motivo_descarte, convertido_en, actualizado_en) values
  (pg_temp.l('LCS'), 'FILTRO LCS', '+51987650014', 'landing', 20000, 'PEN', 'convertido', pg_temp.a('V2'),  null, true, null, now() - interval '1 day', now() - interval '14 minutes'),
  (pg_temp.l('LDS'), 'FILTRO LDS', '+51987650015', 'landing', 20000, 'PEN', 'descartado', pg_temp.a('V2'),  null, true, 'sin_interes', null, now() - interval '15 minutes'),
  (pg_temp.l('LCV'), 'FILTRO LCV', '+51987650016', 'landing', 20000, 'PEN', 'convertido', pg_temp.a('V2'),  null, true, null, now() - interval '60 days', now() - interval '16 minutes'),
  (pg_temp.l('L1'),  'FILTRO L1',  '+51987650001', 'landing', 50000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null, null, now() - interval '1 minute'),
  (pg_temp.l('L1n'), 'FILTRO L1N', '+51987650002', 'landing', 15000, 'PEN', 'nuevo',      pg_temp.a('V1n'), null, true, null, null, now() - interval '2 minutes'),
  (pg_temp.l('L2'),  'FILTRO L2',  '+51987650003', 'landing', 30000, 'USD', 'contactado', pg_temp.a('V2'),  null, true, null, null, now() - interval '3 minutes'),
  (pg_temp.l('LP'),  'FILTRO LP',  '+51987650004', 'landing', 12000, 'PEN', 'nuevo',      null, pg_temp.a('S1'), true, null, null, now() - interval '4 minutes'),
  (pg_temp.l('LC'),  'FILTRO LC',  '+51987650005', 'landing', 20000, 'PEN', 'convertido', pg_temp.a('V1'),  null, true, null, now() - interval '1 day', now() - interval '5 minutes'),
  (pg_temp.l('LD'),  'FILTRO LD',  '+51987650006', 'landing', 20000, 'PEN', 'descartado', pg_temp.a('V1'),  null, true, 'sin_interes', null, now() - interval '6 minutes'),
  (pg_temp.l('LI'),  'FILTRO LI',  '+51987650007', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, false, null, null, now() - interval '7 minutes'),
  (pg_temp.l('L3'),  'FILTRO L3',  '+51987650008', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null, null, now() - interval '8 minutes'),
  (pg_temp.l('LPV'), 'FILTRO LPV', '+51987650009', 'landing', 20000, 'PEN', 'nuevo',      null, pg_temp.a('V1'), true, null, null, now() - interval '9 minutes'),
  (pg_temp.l('LK'),  'FILTRO LK',  '+51987650010', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null, null, now() - interval '10 minutes'),
  (pg_temp.l('LZ'),  'FILTRO LZ',  '+51987650011', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null, null, now() - interval '11 minutes'),
  (pg_temp.l('LS'),  'FILTRO LS',  '+51987650012', 'landing', 20000, 'PEN', 'nuevo',      null, null, true, null, null, now() - interval '12 minutes'),
  (pg_temp.l('LSM'), 'FILTRO LSM', '+51987650013', 'landing', 20000, 'PEN', 'nuevo',      null, null, true, null, null, now() - interval '13 minutes');
insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en) values
  (pg_temp.l('L1'),  'estrella', 'manual',    pg_temp.a('V1'),  now()),
  (pg_temp.l('L1n'), 'tibio',    'manual',    pg_temp.a('S1n'), now()),
  (pg_temp.l('L2'),  'estrella', 'manual',    pg_temp.a('V2'),  now()),
  (pg_temp.l('LP'),  'frio',     'manual',    pg_temp.a('S1'),  now()),
  (pg_temp.l('LC'),  'estrella', 'manual',    pg_temp.a('V1'),  now()),
  (pg_temp.l('LD'),  'tibio',    'manual',    pg_temp.a('V1'),  now()),
  (pg_temp.l('LI'),  'estrella', 'manual',    pg_temp.a('V1'),  now()),
  (pg_temp.l('LK'),  'tibio',    'caducidad', pg_temp.a('V1'),  now()),
  (pg_temp.l('LZ'),  'estrella', 'manual',    pg_temp.a('V1'),  now()),
  (pg_temp.l('LSM'), 'tibio',    'manual',    pg_temp.a('S1'),  now()),
  (pg_temp.l('LCV'), 'estrella', 'manual',    pg_temp.a('V2'),  now());
-- L1: su analista lo recibió hace dos días y lo llamó ayer (con gestión). LK: pasó por V2 antes.
update crm.leads set tenencia_desde = now() - interval '2 days' where id = pg_temp.l('L1');
insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en, metadata) values
  (pg_temp.l('L1'), 'llamada_realizada', 'prueba del filtro', pg_temp.a('V1'), now() - interval '1 day', '{}'::jsonb),
  (pg_temp.l('LK'), 'reasignacion', 'prueba del filtro', null, now() - interval '3 days',
   jsonb_build_object('vendedor_anterior', pg_temp.a('V2'), 'vendedor_nuevo', pg_temp.a('V1')));
-- crm.resumen_cartera_fn (el envoltorio) exige un peso del referido: un banco sin datos no lo tiene.
insert into crm.conversion_pesos (vigente_desde, peso_referido, nota)
  select date '2026-01-01', 0.5, 'FILTRO: fila sintética del banco' where not exists (select 1 from crm.conversion_pesos);
set local session_replication_role = origin;

-- Identidad de la sesión, en las DOS formas (producción lee request.jwt.claims; la imagen del banco
-- solo request.jwt.claim.sub).
create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

-- La cartera, como la llama la pantalla: authenticated. `p_args` es el texto de los argumentos.
-- Devuelve el sobre o {"error": SQLSTATE}. `p_fn` permite llamar a la ANTERIOR con lo mismo.
create function pg_temp.cartera(p_actor uuid, p_args text default '', p_fn text default 'crm.cartera_filtrada_fn') returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    execute 'select ' || p_fn || '(' || p_args || ')' into v;
    reset role;
    return v;
  exception when others then
    reset role;
    return jsonb_build_object('error', sqlstate);
  end;
end $f$;
-- El resumen por el envoltorio DEFINER (ahí la cartera corre sin RLS y entra la bandeja del reparto).
create function pg_temp.envoltorio(p_actor uuid) returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    v := crm.resumen_cartera_fn();
    reset role;
    return v;
  exception when others then
    reset role;
    return jsonb_build_object('error', sqlstate);
  end;
end $f$;
-- Las claves de los leads de una respuesta, en el ORDEN en que vienen.
create function pg_temp.claves(p_sobre jsonb) returns text language sql as $$
  select case when p_sobre ? 'error' then 'error ' || (p_sobre ->> 'error') else coalesce((
    select string_agg(d.k, ',' order by i.ord)
    from jsonb_array_elements(p_sobre -> 'items') with ordinality i(item, ord)
    join lds d on d.id = (i.item ->> 'id')::uuid), '(ninguno)') end
$$;
-- Las mismas claves en orden alfabético (para comparar conjuntos).
create function pg_temp.conjunto(p_sobre jsonb) returns text language sql as $$
  select case when p_sobre ? 'error' then 'error ' || (p_sobre ->> 'error') else coalesce((
    select string_agg(d.k, ',' order by d.k)
    from jsonb_array_elements(p_sobre -> 'items') i join lds d on d.id = (i ->> 'id')::uuid), '(ninguno)') end
$$;
-- El bloque de potencial de un resumen: filtro · E/T/F/S · vivos.
create function pg_temp.pot(p_resumen jsonb) returns text language sql as $$
  select case when p_resumen is null then '(sin resumen)'
    when p_resumen ? 'error' then 'error ' || (p_resumen ->> 'error')
    when not (p_resumen ? 'potencial') then '(sin clave) v=' || (p_resumen #>> '{totales,vivos}')
    else coalesce(p_resumen #>> '{potencial,filtro}', '-')
      || ' E' || (p_resumen #>> '{potencial,estrella}') || ' T' || (p_resumen #>> '{potencial,tibio}')
      || ' F' || (p_resumen #>> '{potencial,frio}') || ' S' || (p_resumen #>> '{potencial,sin_marca}')
      || ' v=' || (p_resumen #>> '{totales,vivos}') end
$$;
-- Lo que la RLS REAL de crm.leads deja ver a un actor (la vara independiente).
create function pg_temp.ve_rls(p_actor uuid) returns uuid[] language plpgsql as $f$
declare v_ids uuid[] := (select array_agg(id) from lds); v_vistos uuid[];
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    select array_agg(l.id) into v_vistos from crm.leads l where l.id = any (v_ids);
  exception when others then
    reset role;
    return null;
  end;
  reset role;
  return coalesce(v_vistos, '{}');
end $f$;
-- ORÁCULO independiente: con la RLS real y la tabla de marcas (leída como administrador), lo que
-- debería devolver la cartera para un actor y un nivel: «claves | E T F S» de lo que ve.
create function pg_temp.oraculo(p_actor uuid, p_nivel text default null) returns text language sql as $$
  with visibles as (
    select d.k, p.nivel::text as nivel
    from unnest(pg_temp.ve_rls(p_actor)) v(id)
    join lds d on d.id = v.id
    join crm.leads l on l.id = d.id
    left join crm.lead_potencial p on p.lead_id = d.id
    -- La ventana operativa de la cartera: sin fechas, un convertido de más de 45 días no entra.
    where l.etapa <> 'convertido' or l.convertido_en >= now() - interval '45 days'
  )
  select coalesce((select string_agg(k, ',' order by k) from visibles
                    where p_nivel is null or (p_nivel = 'sin_marca' and nivel is null) or nivel = p_nivel), '(ninguno)')
    || ' | E' || (select count(*) from visibles where nivel = 'estrella')
    || ' T' || (select count(*) from visibles where nivel = 'tibio')
    || ' F' || (select count(*) from visibles where nivel = 'frio')
    || ' S' || (select count(*) from visibles where nivel is null)
$$;
-- Lo mismo, tal como lo devuelve la cartera.
create function pg_temp.respuesta(p_actor uuid, p_nivel text default null) returns text language sql as $$
  with s as (select pg_temp.cartera(p_actor, 'p_limite => 200' || coalesce(', p_potencial => ' || quote_literal(p_nivel), '')) as v)
  select case when s.v ? 'error' then 'error ' || (s.v ->> 'error') else pg_temp.conjunto(s.v)
    || ' | E' || (s.v #>> '{resumen,potencial,estrella}') || ' T' || (s.v #>> '{resumen,potencial,tibio}')
    || ' F' || (s.v #>> '{resumen,potencial,frio}') || ' S' || (s.v #>> '{resumen,potencial,sin_marca}') end
  from s
$$;
-- El ayudante, llamado como administrador con la sesión del actor: las claves que devuelve.
create function pg_temp.ayudante(p_actor uuid) returns text language plpgsql as $f$
declare v text;
begin
  perform pg_temp.sesion(p_actor);
  begin
    select coalesce(string_agg(d.k || ':' || left(m.nivel, 1), ',' order by d.k), '(ninguno)') into v
    from private.cartera_potencial_fn() m join lds d on d.id = m.lead_id;
    return v;
  exception when others then
    return 'error ' || sqlstate;
  end;
end $f$;

do $prueba$
declare
  v jsonb;
  w jsonb;
  v_n integer;
  ak text;
  nv text;
  ca text;
  v_txt text;
  v_iguales integer := 0;
  v_total integer := 0;
  v_dist text := '';
  f14 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
  ayu constant text := 'private.cartera_potencial_fn()';
  llamadas constant text[] := array[
    $c$p_limite => 200$c$,
    $c$p_limite => 2$c$,
    $c$p_limite => 200, p_etapa => 'contactado'$c$,
    $c$p_limite => 200, p_etapa => 'descartado'$c$,
    $c$p_limite => 200, p_texto => 'filtro l'$c$,
    $c$p_limite => 200, p_origen => 'landing'$c$,
    $c$p_limite => 200, p_procedencia => 'sistema'$c$,
    $c$p_limite => 200, p_reasignados => true$c$,
    $c$p_limite => 200, p_sin_asignar => true$c$,
    $c$p_limite => 200, p_gestion => 'sin_gestion'$c$,
    $c$p_limite => 200, p_gestion => 'con_gestion'$c$,
    $c$p_limite => 200, p_desde => (now() at time zone 'America/Lima')::date - 30, p_hasta => (now() at time zone 'America/Lima')::date$c$,
    $c$p_limite => 3, p_antes_de => now() - interval '4 minutes', p_antes_id => '00000000-0000-4000-8000-000000000000'$c$,
    $c$200, null, null, 'nuevo', null, false, null, null, null, null, null, false, null$c$
  ];
begin
  -- ── Permisos (del catálogo: nunca se llama sin EXECUTE bajo set role) ──
  perform pg_temp.esperar('EXECUTE de la cartera: authenticated sí; anon y service_role no', 'true/false/false',
    has_function_privilege('authenticated', f14, 'EXECUTE')::text || '/' ||
    has_function_privilege('anon', f14, 'EXECUTE')::text || '/' || has_function_privilege('service_role', f14, 'EXECUTE')::text);
  perform pg_temp.esperar('EXECUTE del ayudante: authenticated sí; anon y service_role no', 'true/false/false',
    has_function_privilege('authenticated', ayu, 'EXECUTE')::text || '/' ||
    has_function_privilege('anon', ayu, 'EXECUTE')::text || '/' || has_function_privilege('service_role', ayu, 'EXECUTE')::text);
  perform pg_temp.esperar('el ayudante: DEFINER, STABLE, solo search_path vacío, dueño postgres', 'true/s/{"search_path=\"\""}/postgres',
    (select p.prosecdef::text || '/' || p.provolatile::text || '/' || p.proconfig::text || '/' || p.proowner::regrole::text
       from pg_proc p where p.oid = to_regprocedure(ayu)));
  perform pg_temp.esperar('la cartera sigue INVOKER, STABLE y con una sola firma', 'false/s/1',
    (select p.prosecdef::text || '/' || p.provolatile::text from pg_proc p where p.oid = to_regprocedure(f14)) || '/' ||
    (select count(*)::text from pg_proc p where p.proname = 'cartera_filtrada_fn' and p.pronamespace = 'crm'::regnamespace));
  perform pg_temp.esperar('la tabla de la marca sigue sin SELECT para la API (ni por columna)', 'false/false/false/false',
    has_table_privilege('authenticated', 'crm.lead_potencial', 'SELECT')::text || '/' ||
    has_any_column_privilege('authenticated', 'crm.lead_potencial', 'SELECT')::text || '/' ||
    has_table_privilege('anon', 'crm.lead_potencial', 'SELECT')::text || '/' ||
    has_any_column_privilege('anon', 'crm.lead_potencial', 'SELECT')::text);
  perform pg_temp.esperar('el rol de puente de métricas no ejecuta ni la cartera ni el ayudante', 'false/false',
    has_function_privilege('crm_metricas_bridge', f14, 'EXECUTE')::text || '/' || has_function_privilege('crm_metricas_bridge', ayu, 'EXECUTE')::text);

  -- ══ Bandera APAGADA: todo como antes ══
  update crm.multiempresa_flags set activo = false where nombre = 'potencial_lead';
  v := pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200');
  perform pg_temp.esperar('apagada: V1 ve sus 7 leads, en su orden', 'L1,LC,LD,L3,LPV,LK,LZ', pg_temp.claves(v));
  perform pg_temp.esperar('apagada: el resumen NO trae la clave potencial', '(sin clave) v=7', pg_temp.pot(v -> 'resumen'));
  perform pg_temp.esperar('apagada: pedir el filtro → 55000', 'error 55000', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), $c$p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('apagada: pedir «sin_marca» → 55000', 'error 55000', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), $c$p_potencial => 'sin_marca'$c$)));
  perform pg_temp.esperar('apagada: un valor inválido sigue siendo 22023 (se valida antes)', 'error 22023', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), $c$p_potencial => 'caliente'$c$)));
  perform pg_temp.esperar('apagada: p_potencial null explícito pasa', 'L1,L3,LC,LD,LK,LPV,LZ', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200, p_potencial => null')));
  perform pg_temp.esperar('apagada: el ayudante no devuelve nada (gerencia)', '(ninguno)', pg_temp.ayudante(pg_temp.a('G')));
  perform pg_temp.esperar('apagada: el envoltorio responde y tampoco trae la clave', '(sin clave) v=7', pg_temp.pot(pg_temp.envoltorio(pg_temp.a('V1'))));
  perform pg_temp.esperar('apagada: sin sesión → 42501', 'error 42501', pg_temp.conjunto(pg_temp.cartera(null, 'p_limite => 200')));
  -- Igualdad con la ANTERIOR, byte a byte salvo generado_en.
  foreach ak in array array['G', 'D', 'DH', 'C', 'S1', 'S1n', 'S2', 'V1', 'V1n', 'V2'] loop
    foreach ca in array llamadas loop
      v := pg_temp.cartera(pg_temp.a(ak), ca, 'pg_temp.cartera_filtrada_anterior');
      w := pg_temp.cartera(pg_temp.a(ak), ca);
      v_total := v_total + 1;
      if v is not null and not (v ? 'error') and (v - 'generado_en') = (w - 'generado_en') then v_iguales := v_iguales + 1;
      else v_dist := left(v_dist || ' · ' || ak || ' [' || ca || ']', 600); end if;
    end loop;
  end loop;
  perform pg_temp.esperar('apagada: la respuesta es la de la firma de 13 (10 actores × 14 llamadas)', '140 de 140', v_iguales || ' de ' || v_total || v_dist);

  -- ══ Bandera ENCENDIDA ══
  update crm.multiempresa_flags set activo = true where nombre = 'potencial_lead';

  -- Admisión y validación.
  perform pg_temp.esperar('sin sesión → 42501', 'error 42501', pg_temp.conjunto(pg_temp.cartera(null, $c$p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('X (equipo inactivo) → 42501', 'error 42501', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('X'), $c$p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('XP (perfil inactivo) → 42501', 'error 42501', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('XP'), $c$p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('P (solo portal) → 42501', 'error 42501', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('P'), $c$p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('DM (pareja desalineada) → 42501', 'error 42501', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('DM'), $c$p_potencial => 'estrella'$c$)));
  foreach nv in array array['caliente', 'ESTRELLA', 'Tibio', '', ' frio', 'sin marca', 'todos'] loop
    perform pg_temp.esperar('valor inválido «' || nv || '» → 22023', 'error 22023',
      pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), 'p_potencial => ' || quote_literal(nv))));
  end loop;

  -- Forma: una clave nueva en el resumen y ninguna más; las filas, como siempre.
  v := pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200');
  w := pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200', 'pg_temp.cartera_filtrada_anterior');
  perform pg_temp.esperar('encendida: las claves de arriba son las de la anterior', 'true',
    ((select array_agg(x order by x) from jsonb_object_keys(v) x) = (select array_agg(x order by x) from jsonb_object_keys(w) x))::text);
  perform pg_temp.esperar('encendida: el resumen gana SOLO la clave potencial', 'potencial',
    (select string_agg(x, ',' order by x) from jsonb_object_keys(v -> 'resumen') x where not (w -> 'resumen') ? x));
  perform pg_temp.esperar('encendida: las claves de potencial son cinco', 'estrella,filtro,frio,sin_marca,tibio',
    (select string_agg(x, ',' order by x) from jsonb_object_keys(v #> '{resumen,potencial}') x));
  perform pg_temp.esperar('encendida: las filas tienen las claves de siempre (sin potencial_nivel)', 'true/false',
    ((select array_agg(x order by x) from jsonb_object_keys(v #> '{items,0}') x) = (select array_agg(x order by x) from jsonb_object_keys(w #> '{items,0}') x))::text
    || '/' || ((v #> '{items,0}') ? 'potencial_nivel')::text);
  perform pg_temp.esperar('encendida y sin filtro: quitando resumen.potencial, es la respuesta anterior', 'true',
    ((v - 'generado_en') #- '{resumen,potencial}' = (w - 'generado_en'))::text);
  perform pg_temp.esperar('encendida: omitido y null explícito dan lo mismo', 'true',
    ((v - 'generado_en') = (pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200, p_potencial => null') - 'generado_en'))::text);

  -- Lo que ve cada rol, sin filtro: lista, conteos por nivel y total.
  perform pg_temp.esperar('G sin filtro (el convertido de hace 60 días no entra)', 'L1,L1n,L2,L3,LC,LCS,LD,LDS,LK,LP,LPV,LS,LSM,LZ', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('G'), 'p_limite => 200')));
  perform pg_temp.esperar('G: conteos (los cerrados sin marca cuentan en «sin marca»)', '- E4 T4 F1 S5 v=14', pg_temp.pot(pg_temp.cartera(pg_temp.a('G'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('D (directorio) ve lo mismo que gerencia', '- E4 T4 F1 S5 v=14', pg_temp.pot(pg_temp.cartera(pg_temp.a('D'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('DH (directorio histórico) igual', '- E4 T4 F1 S5 v=14', pg_temp.pot(pg_temp.cartera(pg_temp.a('DH'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('S1 sin filtro', 'L1,L1n,L3,LC,LD,LK,LP,LPV,LZ', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('S1'), 'p_limite => 200')));
  perform pg_temp.esperar('S1: conteos', '- E3 T3 F1 S2 v=9', pg_temp.pot(pg_temp.cartera(pg_temp.a('S1'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('S1n: solo el lead de su analista', '- E0 T1 F0 S0 v=1', pg_temp.pot(pg_temp.cartera(pg_temp.a('S1n'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('V1: conteos', '- E3 T2 F0 S2 v=7', pg_temp.pot(pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('V1n: conteos', '- E0 T1 F0 S0 v=1', pg_temp.pot(pg_temp.cartera(pg_temp.a('V1n'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('V2: su estrella, un convertido y un descartado sin marca; el convertido viejo no cuenta', '- E1 T0 F0 S2 v=3', pg_temp.pot(pg_temp.cartera(pg_temp.a('V2'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('S2: conteos', '- E1 T0 F0 S2 v=3', pg_temp.pot(pg_temp.cartera(pg_temp.a('S2'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('V2 con sin_marca: los dos cerrados sin marca', 'LCS,LDS', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V2'), $c$p_limite => 200, p_potencial => 'sin_marca'$c$)));
  perform pg_temp.esperar('V2 con estrella: el convertido de hace 60 días sigue fuera de la ventana', 'L2', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V2'), $c$p_limite => 200, p_potencial => 'estrella'$c$)));

  -- Cada nivel, rol por rol: la lista es la del nivel, el total es el del nivel, y los cuatro
  -- conteos NO cambian al elegir (se cuentan antes del filtro). Contra el oráculo de la RLS real.
  foreach ak in array array['G', 'D', 'DH', 'S1', 'S1n', 'S2', 'V1', 'V1n', 'V2'] loop
    perform pg_temp.esperar(ak || ' sin filtro = oráculo (RLS real + tabla de marcas)', pg_temp.oraculo(pg_temp.a(ak)), pg_temp.respuesta(pg_temp.a(ak)));
    foreach nv in array array['estrella', 'tibio', 'frio', 'sin_marca'] loop
      perform pg_temp.esperar(ak || ' con ' || nv || ' = oráculo', pg_temp.oraculo(pg_temp.a(ak), nv), pg_temp.respuesta(pg_temp.a(ak), nv));
    end loop;
  end loop;
  -- Y a mano, para que el oráculo no sea la única vara.
  perform pg_temp.esperar('V1 con estrella', 'L1,LC,LZ', pg_temp.claves(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('V1 con estrella: eco, conteos intactos y total del nivel', 'estrella E3 T2 F0 S2 v=3',
    pg_temp.pot(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_potencial => 'estrella'$c$) -> 'resumen'));
  perform pg_temp.esperar('V1 con tibio (uno manual y uno que bajó solo)', 'LD,LK', pg_temp.claves(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_potencial => 'tibio'$c$)));
  perform pg_temp.esperar('V1 con frio: ninguno, y el total es cero', 'frio E3 T2 F0 S2 v=0',
    pg_temp.pot(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_potencial => 'frio'$c$) -> 'resumen'));
  perform pg_temp.esperar('V1 con sin_marca', 'L3,LPV', pg_temp.claves(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_potencial => 'sin_marca'$c$)));
  perform pg_temp.esperar('S1 con frio: el parqueado en su bandeja', 'LP', pg_temp.claves(pg_temp.cartera(pg_temp.a('S1'), $c$p_limite => 200, p_potencial => 'frio'$c$)));
  perform pg_temp.esperar('G con tibio: incluye el sin asignar (lo ve por ser gerencia)', 'L1n,LD,LK,LSM', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('G'), $c$p_limite => 200, p_potencial => 'tibio'$c$)));
  perform pg_temp.esperar('el inactivo LI (estrella) no aparece ni cuenta para nadie', 'false',
    (pg_temp.conjunto(pg_temp.cartera(pg_temp.a('G'), $c$p_limite => 200, p_potencial => 'estrella'$c$)) ~ 'LI')::text);

  -- El resto del resumen sale de la base YA filtrada (totales, capital, embudo), como con los demás filtros.
  v := pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_potencial => 'estrella'$c$);
  perform pg_temp.esperar('V1 estrella: abiertos, convertidos y capital asignado en soles', '2/1/70000',
    (v #>> '{resumen,totales,abiertos}') || '/' || (v #>> '{resumen,totales,convertidos}') || '/' || (v #>> '{resumen,capital,asignado,pen}'));
  perform pg_temp.esperar('V1 estrella: el embudo suma el total', '3',
    (select sum((e ->> 'n')::int)::text from jsonb_array_elements(v #> '{resumen,embudo}') e));

  -- Se combina con los demás filtros: los conteos respetan la etapa pedida.
  perform pg_temp.esperar('V1, contactado + estrella', 'L1,LZ', pg_temp.claves(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_etapa => 'contactado', p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('V1, contactado: conteos de esa etapa', 'estrella E2 T1 F0 S1 v=2',
    pg_temp.pot(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_etapa => 'contactado', p_potencial => 'estrella'$c$) -> 'resumen'));
  perform pg_temp.esperar('S1, sin asignar + frio', 'LP', pg_temp.claves(pg_temp.cartera(pg_temp.a('S1'), $c$p_limite => 200, p_sin_asignar => true, p_potencial => 'frio'$c$)));
  perform pg_temp.esperar('G, texto + tibio', 'LSM', pg_temp.claves(pg_temp.cartera(pg_temp.a('G'), $c$p_limite => 200, p_texto => 'filtro lsm', p_potencial => 'tibio'$c$)));
  perform pg_temp.esperar('V1, sin gestión + sin_marca (un parqueado no tiene gestión)', 'L3,LPV', pg_temp.claves(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_gestion => 'sin_gestion', p_potencial => 'sin_marca'$c$)));
  perform pg_temp.esperar('V1, con gestión + estrella: el que su analista ya llamó', 'L1',
    pg_temp.claves(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_gestion => 'con_gestion', p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('V1, con gestión: los conteos son los de esa base', 'estrella E1 T0 F0 S0 v=1',
    pg_temp.pot(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_gestion => 'con_gestion', p_potencial => 'estrella'$c$) -> 'resumen'));
  perform pg_temp.esperar('V1, reasignados + tibio: el que vino de otro analista', 'LK',
    pg_temp.claves(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_reasignados => true, p_potencial => 'tibio'$c$)));
  perform pg_temp.esperar('V1, reasignados + estrella: ninguno, y los conteos dicen por qué', 'estrella E0 T1 F0 S0 v=0',
    pg_temp.pot(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_reasignados => true, p_potencial => 'estrella'$c$) -> 'resumen'));
  -- Negativa cruzada: pedir el analista de OTRO equipo con un nivel no enseña nada ni cuenta nada.
  perform pg_temp.esperar('V1 pidiendo a V2 + estrella: nada y cuatro ceros', '(ninguno) / estrella E0 T0 F0 S0 v=0',
    (select pg_temp.conjunto(x.v) || ' / ' || pg_temp.pot(x.v -> 'resumen')
       from (select pg_temp.cartera(pg_temp.a('V1'), format($c$p_limite => 200, p_vendedor_id => %L, p_potencial => 'estrella'$c$, pg_temp.a('V2'))) as v) x));

  -- El cursor recorre SOLO el nivel pedido, sin saltos ni repetidos.
  v := pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 2, p_potencial => 'estrella'$c$);
  perform pg_temp.esperar('cursor: primera página de estrella', 'L1,LC', pg_temp.claves(v));
  w := pg_temp.cartera(pg_temp.a('V1'), format($c$p_limite => 2, p_potencial => 'estrella', p_antes_de => %L, p_antes_id => %L$c$,
    v #>> '{items,1,actualizado_en}', v #>> '{items,1,id}'));
  perform pg_temp.esperar('cursor: segunda página de estrella', 'LZ', pg_temp.claves(w));
  perform pg_temp.esperar('cursor: el total no depende de la página', '3/3', (v #>> '{resumen,totales,vivos}') || '/' || (w #>> '{resumen,totales,vivos}'));
  -- Con EMPATE de sello (LC y LZ a la misma hora) desempata el id: de uno en uno, salen los tres una vez.
  perform set_config('session_replication_role', 'replica', true);
  update crm.leads set actualizado_en = (select x.actualizado_en from crm.leads x where x.id = pg_temp.l('LC')) where id = pg_temp.l('LZ');
  perform set_config('session_replication_role', 'origin', true);
  v_txt := '';
  w := null;
  for v_n in 1..4 loop
    v := pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 1, p_potencial => ''estrella''' || coalesce(format(', p_antes_de => %L, p_antes_id => %L',
      w #>> '{items,0,actualizado_en}', w #>> '{items,0,id}'), ''));
    exit when jsonb_array_length(v -> 'items') = 0;
    v_txt := v_txt || case when v_txt = '' then '' else ',' end || pg_temp.claves(v);
    w := v;
  end loop;
  perform pg_temp.esperar('cursor con empate de sello: los tres, una vez cada uno', 'L1,LC,LZ',
    (select string_agg(x, ',' order by x) from regexp_split_to_table(v_txt, ',') x));
  perform pg_temp.esperar('cursor con empate: sin repetidos', '3', (select count(distinct x)::text from regexp_split_to_table(v_txt, ',') x));
  -- Un cursor con un id AJENO solo es una posición: no enseña ese lead ni otro nivel.
  perform pg_temp.esperar('cursor con el id de un lead ajeno: sigue sin enseñar nada fuera del nivel y del ámbito', 'true',
    (select bool_and(d.k in ('L1', 'LC', 'LZ'))::text
       from jsonb_array_elements(pg_temp.cartera(pg_temp.a('V1'), format($c$p_limite => 200, p_potencial => 'estrella', p_antes_de => %L, p_antes_id => %L$c$,
              now()::text, pg_temp.l('L2'))) -> 'items') i join lds d on d.id = (i ->> 'id')::uuid));

  -- El coordinador: por la API ve lo que la RLS le deja; dentro del envoltorio DEFINER entra la
  -- bandeja del reparto (LP, LPV, LS y LSM) y sus marcas tienen que contar.
  perform pg_temp.esperar('C (coordinación) por la API: su RLS no le deja ver leads y no recibe conteos por nivel', '(ninguno) / (sin clave) v=0',
    (select pg_temp.conjunto(x.v) || ' / ' || pg_temp.pot(x.v -> 'resumen') from (select pg_temp.cartera(pg_temp.a('C'), 'p_limite => 200') as v) x));
  perform pg_temp.esperar('C pidiendo un nivel → 55000: para quien no tiene ámbito de filas el filtro no existe', 'error 55000',
    pg_temp.conjunto(pg_temp.cartera(pg_temp.a('C'), $c$p_limite => 200, p_potencial => 'tibio'$c$)));
  perform pg_temp.esperar('C en el envoltorio: cuenta su bandeja de reparto (4) pero SIN conteos por nivel', '(sin clave) v=4', pg_temp.pot(pg_temp.envoltorio(pg_temp.a('C'))));
  perform pg_temp.esperar('V1 en el envoltorio: los mismos conteos que por la API', '- E3 T2 F0 S2 v=7', pg_temp.pot(pg_temp.envoltorio(pg_temp.a('V1'))));
  perform pg_temp.esperar('G en el envoltorio', '- E4 T4 F1 S5 v=14', pg_temp.pot(pg_temp.envoltorio(pg_temp.a('G'))));
  -- Una respuesta de error o sin el bloque también cuenta como falla (Codex f3b r1: NULL no es «igual»).
  perform pg_temp.esperar('los cuatro conteos suman el total sin filtro (los 9 roles con ámbito, API y envoltorio)', '18 respuestas, 0 malas',
    (select count(*)::text || ' respuestas, ' || count(*) filter (where x.r is null or x.r ? 'error' or not (x.r ? 'potencial')
        or (x.r #>> '{potencial,estrella}')::int + (x.r #>> '{potencial,tibio}')::int + (x.r #>> '{potencial,frio}')::int
           + (x.r #>> '{potencial,sin_marca}')::int is distinct from (x.r #>> '{totales,vivos}')::int)::text || ' malas'
       from unnest(array['G', 'D', 'DH', 'S1', 'S1n', 'S2', 'V1', 'V1n', 'V2']) a(k),
       lateral (select pg_temp.cartera(pg_temp.a(a.k), 'p_limite => 1') -> 'resumen' as r union all select pg_temp.envoltorio(pg_temp.a(a.k))) x));
  perform pg_temp.esperar('el verificador de sumas ve un error: una respuesta rota cuenta como mala', '1',
    (select count(*) filter (where x.r is null or x.r ? 'error' or not (x.r ? 'potencial'))::text
       from (select pg_temp.envoltorio(pg_temp.a('P')) as r) x));

  -- El ayudante por dentro: solo las marcas del ámbito del actor.
  perform pg_temp.esperar('ayudante, G: todas las marcas de leads activos', 'L1:e,L1n:t,L2:e,LC:e,LCV:e,LD:t,LK:t,LP:f,LSM:t,LZ:e', pg_temp.ayudante(pg_temp.a('G')));
  perform pg_temp.esperar('ayudante, D: igual que gerencia', 'L1:e,L1n:t,L2:e,LC:e,LCV:e,LD:t,LK:t,LP:f,LSM:t,LZ:e', pg_temp.ayudante(pg_temp.a('D')));
  perform pg_temp.esperar('ayudante, DH (directorio histórico): igual que gerencia', 'L1:e,L1n:t,L2:e,LC:e,LCV:e,LD:t,LK:t,LP:f,LSM:t,LZ:e', pg_temp.ayudante(pg_temp.a('DH')));
  perform pg_temp.esperar('ayudante, S1: su equipo y su bandeja', 'L1:e,L1n:t,LC:e,LD:t,LK:t,LP:f,LZ:e', pg_temp.ayudante(pg_temp.a('S1')));
  perform pg_temp.esperar('ayudante, V1: solo lo suyo', 'L1:e,LC:e,LD:t,LK:t,LZ:e', pg_temp.ayudante(pg_temp.a('V1')));
  perform pg_temp.esperar('ayudante, V2: solo lo suyo', 'L2:e,LCV:e', pg_temp.ayudante(pg_temp.a('V2')));
  perform pg_temp.esperar('ayudante, C: nada (operar el reparto no da a leer marcas)', '(ninguno)', pg_temp.ayudante(pg_temp.a('C')));
  perform pg_temp.esperar('ayudante, DM (pareja desalineada) → 42501', 'error 42501', pg_temp.ayudante(pg_temp.a('DM')));
  -- El ayudante nunca entrega más que la RLS: lo que devuelve a cada rol está dentro de lo que ese rol lee.
  perform pg_temp.esperar('ayudante ⊆ RLS para los 10 roles admitidos', '0',
    (select count(*)::text from unnest(array['G', 'D', 'DH', 'C', 'S1', 'S1n', 'S2', 'V1', 'V1n', 'V2']) a(k)
      where exists (select 1 from regexp_split_to_table(nullif(pg_temp.ayudante(pg_temp.a(a.k)), '(ninguno)'), ',') m(par)
                     where not (pg_temp.l(split_part(m.par, ':', 1)) = any (pg_temp.ve_rls(pg_temp.a(a.k)))))));
  perform pg_temp.esperar('ayudante, sin sesión → 42501', 'error 42501', pg_temp.ayudante(null));
  perform pg_temp.esperar('ayudante, P (solo portal) → 42501', 'error 42501', pg_temp.ayudante(pg_temp.a('P')));
  perform pg_temp.esperar('ayudante, X (equipo inactivo) → 42501', 'error 42501', pg_temp.ayudante(pg_temp.a('X')));
  perform pg_temp.esperar('ayudante, XP (perfil inactivo) → 42501', 'error 42501', pg_temp.ayudante(pg_temp.a('XP')));

  -- Encendida, la igualdad sigue: quitando resumen.potencial, cada respuesta es la anterior.
  v_iguales := 0; v_total := 0; v_dist := '';
  foreach ak in array array['G', 'D', 'DH', 'C', 'S1', 'S1n', 'S2', 'V1', 'V1n', 'V2'] loop
    foreach ca in array llamadas loop
      v := pg_temp.cartera(pg_temp.a(ak), ca, 'pg_temp.cartera_filtrada_anterior');
      w := pg_temp.cartera(pg_temp.a(ak), ca);
      v_total := v_total + 1;
      if v is not null and not (v ? 'error') and (v - 'generado_en') = ((w - 'generado_en') #- '{resumen,potencial}')
         -- Todos reciben el bloque menos coordinación, que no tiene ámbito de filas.
         and ((w #> '{resumen,potencial}') is not null) = (ak <> 'C') then v_iguales := v_iguales + 1;
      else v_dist := left(v_dist || ' · ' || ak || ' [' || ca || ']', 600); end if;
    end loop;
  end loop;
  perform pg_temp.esperar('encendida: quitando resumen.potencial, la respuesta es la de la firma de 13 (10 × 14)', '140 de 140', v_iguales || ' de ' || v_total || v_dist);

  -- La marca cambia y el filtro lo ve en la siguiente llamada (no hay copia guardada).
  update crm.lead_potencial set nivel = 'frio' where lead_id = pg_temp.l('L1');
  perform pg_temp.esperar('tras bajar L1 a frío: V1', '- E2 T2 F1 S2 v=7', pg_temp.pot(pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200') -> 'resumen'));
  delete from crm.lead_potencial where lead_id = pg_temp.l('LK');
  perform pg_temp.esperar('tras quitar la marca de LK: V1 con sin_marca', 'L3,LK,LPV', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_potencial => 'sin_marca'$c$)));

  -- ── Solo lectura: la cartera no escribió nada en las tablas de la marca ──
  perform pg_temp.esperar('la cartera no escribió marcas ni eventos', '10/0',
    (select count(*)::text from crm.lead_potencial where lead_id in (select id from lds)) || '/' ||
    (select count(*)::text from crm.lead_potencial_eventos where lead_id in (select id from lds)));

  -- ── Con el potencial apagado (o sin ámbito de filas) el ayudante NI SE LLAMA ──
  -- Se sustituye por uno que explota: apagada, la cartera responde igual; encendida, explota.
  create or replace function private.cartera_potencial_fn() returns table(lead_id uuid, nivel text)
    language plpgsql stable security definer set search_path = '' as $x$
    begin raise exception 'el ayudante fue llamado' using errcode = 'P0777'; end $x$;
  perform pg_temp.esperar('ayudante que explota, bandera encendida: la cartera lo llama', 'error P0777',
    pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200')));
  perform pg_temp.esperar('ayudante que explota, bandera encendida, coordinación: no se le llama', '(ninguno)',
    pg_temp.conjunto(pg_temp.cartera(pg_temp.a('C'), 'p_limite => 200')));
  update crm.multiempresa_flags set activo = false where nombre = 'potencial_lead';
  perform pg_temp.esperar('ayudante que explota, bandera apagada: no se le llama y la cartera responde', 'L1,L3,LC,LD,LK,LPV,LZ',
    pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200')));

  -- ── Veredicto (el raise deshace todo) ──
  select count(*) into v_n from res where esperado is distinct from obtenido;
  if v_n = 0 then
    raise exception 'FILTRO potencial_lead: % de % OK', (select count(*) from res), (select count(*) from res) using errcode = 'P0001';
  else
    raise exception 'FILTRO potencial_lead: % FALLAS de %: %', v_n, (select count(*) from res),
      (select string_agg(n || ' ' || caso || ' → esperado ' || esperado || ', obtenido ' || obtenido, ' | ' order by n)
       from res where esperado is distinct from obtenido) using errcode = 'P0001';
  end if;
end;
$prueba$;
rollback;
```

### supabase/scripts/test-rls.mjs — catálogo de la firma viva (bloque de gestión, ahora 13 o 14)
```js
  // ACL y forma de la firma viva, leidas del CATALOGO (via fuera de banda del
  // banco). El 42501 de anon de arriba no distingue «sin EXECUTE» de la guarda
  // interna «No autorizado»; esto si: EXECUTE exactamente para authenticated,
  // INVOKER, stable, search_path vacio y una sola firma. La viva es la de 13
  // (20261001154153, p_gestion) o, desde la entrega B del potencial
  // (20261001212341), la de 14: p_gestion sigue 13.o y p_potencial es el 14.o.
  if (process.env.CRM_BANCO_PSQL_URL) {
    const F13 = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
    const F14 = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
    const cuenta = (etiqueta, sql) => contarFueraDeBanda(`cartera con gestion: ${etiqueta}`, sql);
    check(cuenta('una sola firma', `select count(*) from pg_proc where proname = 'cartera_filtrada_fn' and pronamespace = 'crm'::regnamespace`) === 1,
      'cartera_filtrada_fn: una sola firma (dos candidatas romperian PostgREST)');
    const con14 = cuenta('firma de 14', `select count(*) from pg_proc p where p.oid = to_regprocedure('${F14}')`) === 1;
    const VIVA = con14 ? F14 : F13;
    const N = con14 ? 14 : 13;
    const existe = cuenta('firma viva', `select count(*) from pg_proc p where p.oid = to_regprocedure('${VIVA}')`) === 1;
    check(existe, `cartera_filtrada_fn: la firma viva es la de ${N} argumentos (con p_gestion${con14 ? ' y p_potencial' : ''})`);
    if (existe) {
      check(cuenta('grants', `select count(*) from (select '${VIVA}'::text as firma) f
        where has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE')
           or not has_function_privilege('authenticated', f.firma, 'EXECUTE')
           or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f.firma::regprocedure and a.grantee = 0)`) === 0,
        `cartera_filtrada_fn(${N}): EXECUTE exactamente para authenticated (ni anon, ni service_role, ni PUBLIC)`);
      check(cuenta('forma', `select count(*) from pg_proc p where p.oid = '${VIVA}'::regprocedure and not p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""'] and p.pronargs = ${N} and p.proargnames[13] = 'p_gestion'${con14 ? " and p.proargnames[14] = 'p_potencial'" : ''}`) === 1,
        `cartera_filtrada_fn(${N}): INVOKER, stable, search_path vacio y p_gestion como 13.o argumento${con14 ? ' (p_potencial, 14.o)' : ''}`);
    }
```

### supabase/scripts/test-rls.mjs — bloque `testPotencialFiltro` (NOT RUN)
```js
// ── Potencial del lead (20261001212341): filtro y conteos en crm.cartera_filtrada_fn ─────────
// La cartera es INVOKER y lee la marca por un ayudante DEFINER (private.cartera_potencial_fn): este
// bloque comprueba, con sesiones reales, que nadie recibe la marca de un lead que su RLS no deja ver.
//   1 · Bandera APAGADA: el resumen no trae `potencial` y pedir el filtro da 55000.
//   2 · El bloque siembra CUATRO marcas fuera de banda (juan estrella, maría tibio, luis frío, ana
//       estrella; sin historial), ENCIENDE la bandera y, rol por rol: los cuatro conteos suman el
//       total, no cambian al elegir un nivel, cada nivel devuelve EXACTAMENTE los leads de ese nivel
//       que la RLS de crm.leads deja ver a ese actor, y «sin_marca» el resto. Después borra sus
//       cuatro marcas y repone la bandera (finally), y comprueba las dos cosas.
//   3 · La ruta SIN RLS (auditor-rls f3b): crm.resumen_cartera_fn es DEFINER y llama a la cartera
//       sin RLS. Para quien tiene ámbito de filas sus conteos son los mismos que por la API;
//       coordinación, que opera el reparto pero no lee leads, NO recibe conteos por nivel ni por la
//       API ni por el envoltorio. Y el ayudante no se alcanza por PostgREST (esquema private).
// Mismo AISLAMIENTO que el bloque de lectura: la suite se niega a correr contra producción y usa un
// banco desechable; si el proceso muere a mitad quedan la bandera encendida y hasta cuatro marcas
// sintéticas (apagar-bandera.sql y un delete de esas filas las reponen). Denegados: dado de baja,
// authenticated ajeno al CRM, anon, service_role, un nivel inventado y la tabla por PostgREST.
// Igualdad con la firma anterior, envoltorio DEFINER, cursor y mutantes: prueba-filtro.sql y
// banco/ciclo-fase3b.sh. Salto RUIDOSO si la migración no está; con CRM_RLS_EXIGE_POTENCIAL=1, FALLO.
async function testPotencialFiltro(sessions, seed) {
  console.log('\n— Potencial del lead: filtro y conteos en la cartera —');
  const saltar = (msg) => {
    if (process.env.CRM_RLS_EXIGE_POTENCIAL === '1') fail(msg);
    else console.log(`  ${msg}`);
  };
  const leerBandera = () => contarFueraDeBanda('potencial filtro: bandera',
    `select coalesce((select activo::int from crm.multiempresa_flags where nombre = 'potencial_lead'), 0)`);
  const contarMarcas = () => contarFueraDeBanda('potencial filtro: marcas', `select count(*)::int from crm.lead_potencial`);
  let aplicada;
  let encendida;
  let marcasAntes;
  try {
    aplicada = contarFueraDeBanda('potencial filtro: migración aplicada',
      `select (to_regprocedure('private.cartera_potencial_fn()') is not null)::int`);
    encendida = aplicada === 1 ? leerBandera() : 0;
    marcasAntes = aplicada === 1 ? contarMarcas() : 0;
  } catch (error) {
    saltar(`⚠ Filtro por potencial SALTADO: sin vía fuera de banda (${error?.message ?? String(error)})`);
    return;
  }
  if (aplicada !== 1) {
    saltar('⚠ private.cartera_potencial_fn NO desplegada en esta base: bloque del filtro por potencial SALTADO (no probado)');
    return;
  }
  if (encendida !== 0 || marcasAntes !== 0) {
    fail(`potencial filtro: el bloque espera la bandera APAGADA y la tabla de marcas VACÍA (bandera=${encendida}, marcas=${marcasAntes}). Si lo dejó así una corrida interrumpida: supabase/scripts/potencial-lead/apagar-bandera.sql y borrar las marcas sintéticas del banco`);
    return;
  }

  const FN = 'cartera_filtrada_fn';
  // Coordinación opera el reparto pero su RLS no le deja leer leads: no tiene ámbito de filas y
  // para ella el potencial no existe (ni conteos ni filtro). Va aparte.
  const CON_AMBITO = ['vend1', 'vend3', 'sup1', 'sup1Nested', 'sup2', 'gerencia', 'directorio'];
  const ROLES = [...CON_AMBITO, 'coordinador'];
  const NIVELES = ['estrella', 'tibio', 'frio'];
  const AYUDANTE = 'private.cartera_potencial_fn()';
  const resumenDe = (cliente) => cliente.schema('crm').rpc('resumen_cartera_fn');

  // Catálogo del ayudante DEFINER (fuera de banda): por PostgREST no se puede ver si devuelve de
  // más, así que se fija su identidad. La huella se mide como en la migración.
  check(contarFueraDeBanda('potencial filtro: forma del ayudante',
    `select count(*) from pg_proc p where p.oid = to_regprocedure('${AYUDANTE}') and p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']`) === 1,
  'cartera_potencial_fn: DEFINER, stable, dueño postgres y solo search_path vacío');
  check(contarFueraDeBanda('potencial filtro: grants del ayudante',
    `select count(*) from (select '${AYUDANTE}'::text as f) x
      where has_function_privilege('anon', x.f, 'EXECUTE') or has_function_privilege('service_role', x.f, 'EXECUTE')
         or not has_function_privilege('authenticated', x.f, 'EXECUTE')
         or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = x.f::regprocedure
                     and (a.grantee not in ('postgres'::regrole, 'authenticated'::regrole) or (a.grantee = 'authenticated'::regrole and a.is_grantable)))`) === 0,
  'cartera_potencial_fn: EXECUTE exactamente para authenticated (ni anon, ni service_role, ni PUBLIC, sin opción de concederlo)');
  check(contarFueraDeBanda('potencial filtro: huella del ayudante',
    `set search_path = ''; set quote_all_identifiers = off; select (md5(pg_get_functiondef(to_regprocedure('${AYUDANTE}'))) = '73e993d618b203cdbe21e8127f7ea5b4')::int`) === 1,
  'cartera_potencial_fn: el cuerpo es el ensayado (gate, bandera y espejo de leads_select)');
  check(contarFueraDeBanda('potencial filtro: tabla sin grants',
    `select (has_table_privilege('authenticated', 'crm.lead_potencial', 'SELECT') or has_any_column_privilege('authenticated', 'crm.lead_potencial', 'SELECT') or has_table_privilege('anon', 'crm.lead_potencial', 'SELECT') or has_any_column_privilege('anon', 'crm.lead_potencial', 'SELECT'))::int`) === 0,
  'crm.lead_potencial: sigue sin SELECT para la API (ni por columna)');
  const idDe = (clave) => seed.leadByName.get(LEAD_BY_KEY[clave].name)?.id;
  const MARCAS = [
    { lead: idDe('juan'), nivel: 'estrella', por: seed.profileIdByKey.vend1 },
    { lead: idDe('maria'), nivel: 'tibio', por: seed.profileIdByKey.vend1 },
    { lead: idDe('luis'), nivel: 'frio', por: seed.profileIdByKey.sup1 },
    { lead: idDe('ana'), nivel: 'estrella', por: seed.profileIdByKey.vend3 },
  ];
  if (MARCAS.some((m) => !m.lead || !m.por)) {
    fail('potencial filtro: la siembra no trae los leads juan, maria, luis y ana con sus dueños');
    return;
  }
  const nivelDe = new Map(MARCAS.map((m) => [m.lead, m.nivel]));
  const cartera = (cliente, extra = {}) => cliente.schema('crm').rpc(FN, { p_limite: 200, ...extra });
  const DENEGADO = /permission denied|denegado/i;
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-potencial-filtro'));
  const denegados = async (momento) => {
    await expectExpectedFailure(`potencial filtro vendInactive (${momento}) → 42501: la baja revoca la cartera`,
      cartera(sessions.vendInactive.client, { p_potencial: 'estrella' }), ['42501'], /no autorizado|acceso/i);
    await expectExpectedFailure(`potencial filtro clientBank, authenticated ajeno al CRM (${momento}) → 42501`,
      cartera(sessions.clientBank.client, { p_potencial: 'estrella' }), ['42501'], /no autorizado|acceso/i);
    await expectExpectedFailure(`potencial filtro anon (${momento}) → 42501 (sin EXECUTE)`,
      cartera(anon, { p_potencial: 'estrella' }), ['42501'], DENEGADO);
    await expectExpectedFailure(`potencial filtro service_role (${momento}) → 42501 (sin EXECUTE)`,
      cartera(admin, { p_potencial: 'estrella' }), ['42501'], DENEGADO);
    await expectExpectedFailure(`potencial filtro con un nivel inventado (${momento}) → 22023`,
      cartera(sessions.vend1.client, { p_potencial: 'caliente' }), ['22023'], /inv[aá]lid/i);
    // La tabla de la marca no se lee por PostgREST: sin grants para la API, con o sin bandera.
    await expectExpectedFailure(`potencial filtro: crm.lead_potencial por PostgREST (${momento}) → 42501`,
      sessions.vend1.client.schema('crm').from('lead_potencial').select('lead_id').limit(1), ['42501'], DENEGADO);
    // El ayudante DEFINER vive en private: PostgREST no lo expone, tenga o no EXECUTE quien llama.
    for (const [quien, cliente] of [['coordinador', sessions.coordinador.client], ['vend1', sessions.vend1.client], ['anon', anon]]) {
      const { data, error } = await cliente.schema('private').rpc('cartera_potencial_fn');
      check(Boolean(error) && data == null,
        `potencial filtro: ${quien} NO alcanza private.cartera_potencial_fn por la API (${momento}; ${error?.code ?? 'sin error'})`);
    }
  };

  // 1 · Bandera APAGADA: la cartera responde como siempre y el filtro no existe.
  for (const clave of ROLES) {
    const { data, error } = await cartera(sessions[clave].client);
    if (error) {
      fail(`potencial filtro ${clave} (apagada): error inesperado ${error.code ?? ''} ${error.message}`);
      continue;
    }
    check(data?.resumen && !('potencial' in data.resumen),
      `potencial filtro ${clave}: bandera apagada → el resumen no trae la clave potencial`,
      JSON.stringify(data?.resumen?.potencial ?? null));
  }
  await expectExpectedFailure('potencial filtro vend1 (apagada): pedir el filtro → 55000',
    cartera(sessions.vend1.client, { p_potencial: 'estrella' }), ['55000'], /no est[aá] habilitado/i);
  await expectExpectedFailure('potencial filtro gerencia (apagada): pedir «sin_marca» → 55000',
    cartera(sessions.gerencia.client, { p_potencial: 'sin_marca' }), ['55000'], /no est[aá] habilitado/i);
  // El envoltorio DEFINER, apagada: tampoco trae la clave.
  for (const clave of ['vend1', 'coordinador', 'gerencia']) {
    const { data, error } = await resumenDe(sessions[clave].client);
    check(!error && data && !('potencial' in data),
      `potencial filtro ${clave}: bandera apagada → resumen_cartera_fn no trae la clave potencial`,
      error ? `${error.code ?? ''} ${error.message}` : JSON.stringify(data?.potencial ?? null));
  }
  await denegados('bandera apagada');

  // 2 · Cuatro marcas sintéticas y la bandera ENCENDIDA, fuera de banda; todo se repone pase lo que pase.
  const lista = MARCAS.map((m) => `'${m.lead}'`).join(', ');
  const fijarBandera = (valor) => ejecutarFueraDeBanda('bandera potencial_lead (filtro)',
    `update crm.multiempresa_flags set activo = ${valor ? 'true' : 'false'}, actualizado_en = now() where nombre = 'potencial_lead';`);
  try {
    ejecutarFueraDeBanda('potencial filtro: marcas sintéticas',
      `insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en) values ${MARCAS.map((m) =>
        `('${m.lead}', '${m.nivel}', 'manual', '${m.por}', now())`).join(', ')};`);
    fijarBandera(true);
    // Coordinación: ni conteos ni filtro, por la API y por el envoltorio (que sí cuenta su bandeja).
    {
      const porApi = await cartera(sessions.coordinador.client);
      check(!porApi.error && porApi.data?.resumen && !('potencial' in porApi.data.resumen),
        'potencial filtro coordinador: encendida → por la API no recibe conteos por nivel',
        porApi.error ? `${porApi.error.code ?? ''} ${porApi.error.message}` : JSON.stringify(porApi.data?.resumen?.potencial ?? null));
      await expectExpectedFailure('potencial filtro coordinador: pedir un nivel → 55000 (sin ámbito de filas el filtro no existe)',
        cartera(sessions.coordinador.client, { p_potencial: 'frio' }), ['55000'], /no est[aá] habilitado/i);
      const porEnvoltorio = await resumenDe(sessions.coordinador.client);
      check(!porEnvoltorio.error && porEnvoltorio.data && !('potencial' in porEnvoltorio.data),
        'potencial filtro coordinador: encendida → resumen_cartera_fn (sin RLS) tampoco le da conteos por nivel',
        porEnvoltorio.error ? `${porEnvoltorio.error.code ?? ''} ${porEnvoltorio.error.message}` : JSON.stringify(porEnvoltorio.data?.potencial ?? null));
    }
    for (const clave of CON_AMBITO) {
      const cliente = sessions[clave].client;
      const todos = await cartera(cliente);
      if (todos.error) {
        fail(`potencial filtro ${clave} (encendida): error inesperado ${todos.error.code ?? ''} ${todos.error.message}`);
        continue;
      }
      const pot = todos.data?.resumen?.potencial;
      const vivos = todos.data?.resumen?.totales?.vivos;
      if (!check(pot && pot.filtro === null && ['estrella', 'tibio', 'frio', 'sin_marca'].every((k) => Number.isInteger(pot[k]) && pot[k] >= 0),
        `potencial filtro ${clave}: encendida y sin filtro → resumen.potencial con sus cuatro conteos y filtro null`,
        JSON.stringify(pot ?? null))) continue;
      check(pot.estrella + pot.tibio + pot.frio + pot.sin_marca === vivos,
        `potencial filtro ${clave}: los cuatro conteos suman el total`, `${JSON.stringify(pot)} vs ${vivos}`);
      if (!check(Number.isInteger(vivos) && vivos <= 200 && todos.data.items.length === vivos,
        `potencial filtro ${clave}: la siembra cabe en una página (para comparar listas enteras)`, `vivos=${vivos}`)) continue;
      const base = todos.data.items.map((l) => l.id);
      check(todos.data.items.every((l) => !('potencial_nivel' in l)),
        `potencial filtro ${clave}: las filas no traen la columna de trabajo`);
      // La vara independiente: lo que la RLS de crm.leads deja ver a este actor.
      const rls = await cliente.schema('crm').from('leads').select('id').in('id', MARCAS.map((m) => m.lead));
      if (rls.error) {
        fail(`potencial filtro ${clave}: no se pudo leer crm.leads para comparar (${rls.error.message})`);
        continue;
      }
      const visiblesMarcados = new Set(rls.data.map((fila) => fila.id));
      for (const nivel of [...NIVELES, 'sin_marca']) {
        const r = await cartera(cliente, { p_potencial: nivel });
        if (r.error) {
          fail(`potencial filtro ${clave} con ${nivel}: error inesperado ${r.error.code ?? ''} ${r.error.message}`);
          continue;
        }
        const ids = r.data.items.map((l) => l.id).sort();
        const esperados = (nivel === 'sin_marca'
          ? base.filter((id) => !nivelDe.has(id))
          : MARCAS.filter((m) => m.nivel === nivel && visiblesMarcados.has(m.lead)).map((m) => m.lead)).sort();
        check(ids.join(',') === esperados.join(','),
          `potencial filtro ${clave} con ${nivel}: EXACTAMENTE los leads de ese nivel que su RLS deja ver`,
          `cartera ${ids.length} vs esperado ${esperados.length}`);
        const p = r.data.resumen?.potencial;
        check(p && p.filtro === nivel && p.estrella === pot.estrella && p.tibio === pot.tibio && p.frio === pot.frio && p.sin_marca === pot.sin_marca,
          `potencial filtro ${clave} con ${nivel}: eco del filtro y conteos iguales a los de sin filtro`, JSON.stringify(p ?? null));
        check(r.data.resumen?.totales?.vivos === pot[nivel] && ids.length === pot[nivel],
          `potencial filtro ${clave} con ${nivel}: el total es el conteo de ese nivel`,
          `vivos=${r.data.resumen?.totales?.vivos} conteo=${pot[nivel]} filas=${ids.length}`);
      }
      check(MARCAS.filter((m) => visiblesMarcados.has(m.lead)).length === pot.estrella + pot.tibio + pot.frio,
        `potencial filtro ${clave}: cuenta tantas marcas como leads marcados ve por su RLS`,
        `RLS ${visiblesMarcados.size} vs conteos ${pot.estrella + pot.tibio + pot.frio}`);
      // La ruta sin RLS: el envoltorio DEFINER da a este rol los MISMOS conteos que la API.
      const envoltorio = await resumenDe(cliente);
      check(!envoltorio.error && JSON.stringify(envoltorio.data?.potencial ?? null) === JSON.stringify(pot),
        `potencial filtro ${clave}: resumen_cartera_fn trae los mismos conteos que la cartera por la API`,
        envoltorio.error ? `${envoltorio.error.code ?? ''} ${envoltorio.error.message}` : `${JSON.stringify(envoltorio.data?.potencial ?? null)} vs ${JSON.stringify(pot)}`);
    }
    // A mano, lo que el fixture garantiza. Un error NO es «lista vacía»: devuelve null y la aserción cae.
    const idsDe = async (clave, nivel, extra = {}) => {
      const { data, error } = await cartera(sessions[clave].client, { p_potencial: nivel, ...extra });
      return error || !Array.isArray(data?.items) ? null : data.items.map((l) => l.id);
    };
    const esLista = (ids, esperados) => Array.isArray(ids) && [...ids].sort().join(',') === [...esperados].sort().join(',');
    check(esLista(await idsDe('vend1', 'estrella'), [idDe('juan')]), 'potencial filtro vend1 con estrella: solo juan (ana es de otro equipo)');
    check(esLista(await idsDe('vend3', 'estrella'), [idDe('ana')]), 'potencial filtro vend3 con estrella: solo ana');
    check(esLista(await idsDe('vend1', 'frio'), []), 'potencial filtro vend1 con frío: el parqueado de la bandeja de su supervisor (luis) no viaja');
    check(esLista(await idsDe('sup1', 'frio'), [idDe('luis')]), 'potencial filtro sup1 con frío: el parqueado de su bandeja (luis)');
    check(esLista(await idsDe('sup2', 'tibio'), []), 'potencial filtro sup2 con tibio: maría es de otro equipo');
    check(esLista(await idsDe('gerencia', 'estrella'), [idDe('juan'), idDe('ana')]), 'potencial filtro gerencia con estrella: juan y ana');
    // Negativa cruzada: pedir el analista de OTRO equipo con un nivel no enseña nada ni cuenta nada.
    {
      const { data, error } = await cartera(sessions.vend1.client, { p_vendedor_id: seed.profileIdByKey.vend3, p_potencial: 'estrella' });
      const p = data?.resumen?.potencial;
      check(!error && Array.isArray(data?.items) && data.items.length === 0
        && p && p.filtro === 'estrella' && p.estrella === 0 && p.tibio === 0 && p.frio === 0 && p.sin_marca === 0,
      'potencial filtro vend1 pidiendo a vend3 con estrella: ni filas ni conteos (la estrella de ana no se revela)',
      error ? `${error.code ?? ''} ${error.message}` : JSON.stringify(p ?? null));
    }
    await denegados('bandera encendida');
  } finally {
    let repuesto = false;
    let ultimoError = null;
    for (let intento = 0; intento < 2 && !repuesto; intento += 1) {
      try {
        ejecutarFueraDeBanda('potencial filtro: reponer',
          `update crm.multiempresa_flags set activo = false, actualizado_en = now() where nombre = 'potencial_lead'; delete from crm.lead_potencial where lead_id in (${lista});`);
        repuesto = leerBandera() === 0 && contarMarcas() === marcasAntes;
      } catch (error) {
        ultimoError = error;
      }
    }
    if (!repuesto) {
      fail(`potencial filtro: el banco NO quedó repuesto (${ultimoError?.message ?? 'bandera encendida o marcas sintéticas'}). Corre supabase/scripts/potencial-lead/apagar-bandera.sql y borra las marcas sintéticas antes de volver a usar este banco`);
    }
  }
  check(leerBandera() === 0, 'potencial filtro: la bandera quedó APAGADA, como estaba');
  check(contarMarcas() === marcasAntes, 'potencial filtro: no quedó ninguna marca sintética');
}

```

## Objetos vivos que el cambio usa (leídos del banco con `search_path` vacío)
### private.cartera_recepciones_fn (el molde: el otro ayudante DEFINER de la misma función)
```sql
CREATE OR REPLACE FUNCTION private.cartera_recepciones_fn(p_desde date, p_hasta date)
 RETURNS TABLE(lead_id uuid, recibido_en timestamp with time zone, aproximado boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_global boolean;
  v_visibles uuid[];
begin
  if v_uid is null or not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_desde is null and p_hasta is null then return; end if;
  if p_desde is null or p_hasta is null or p_desde > p_hasta
     or p_hasta > (now() at time zone 'America/Lima')::date then
    raise exception 'Rango de fechas inválido' using errcode = '22023';
  end if;
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  return query
    select distinct on (l.id) l.id, a.asignado_en, a.aproximado
    from crm.lead_asignaciones a
    join crm.leads l on l.id = a.lead_id and l.vendedor_id = a.analista_id
    join crm.equipo e on e.perfil_id = a.analista_id and e.rol_crm = 'vendedor'
    where l.activo is true
      and (v_global or a.analista_id = any(v_visibles))
      and a.asignado_en >= (p_desde::timestamp at time zone 'America/Lima')
      and a.asignado_en < ((p_hasta + 1)::timestamp at time zone 'America/Lima')
      -- Una reversión al mismo supervisor no es una recepción comercial.
      and (a.motivo_cierre is distinct from 'parkeado'
        or a.supervisor_origen_id is null
        or a.supervisor_destino_id is distinct from a.supervisor_origen_id)
    order by l.id, a.asignado_en desc, a.id desc;
end;
$function$

```
### crm.resumen_cartera_fn (envoltorio DEFINER: llama a la cartera SIN RLS)
```sql
CREATE OR REPLACE FUNCTION crm.resumen_cartera_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=(select auth.uid());
  v_rol text:=private.rol_crm(v_uid);
  v_lector boolean:=private.es_lector_global();
  v_visibles uuid[]:=array(select private.vendedor_ids_visibles(v_uid));
  v_ahora timestamptz:=now();
  v_mes date:=date_trunc('month',v_ahora at time zone 'America/Lima')::date;
  v_payload jsonb;
  v_cierres bigint;
  v_operaciones bigint;
begin
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_payload:=crm.cartera_filtrada_fn(p_limite=>1)->'resumen';
  select coalesce(sum(n.cierres_no_referidos+n.cierres_referidos),0),coalesce(sum(n.operaciones),0)
  into v_cierres,v_operaciones from (
    select e.analista_id,
      count(distinct e.lead_id) filter(where e.tipo='cierre' and not e.anulado and not e.fue_referido) as cierres_no_referidos,
      count(distinct e.lead_id) filter(where e.tipo='cierre' and not e.anulado and e.fue_referido) as cierres_referidos,
      count(*) filter(where e.tipo='operacion') as operaciones
    from private.conversion_episodios(v_mes::timestamp at time zone 'America/Lima',
      (v_mes+interval '1 month')::timestamp at time zone 'America/Lima',v_mes,true,'{}'::uuid[],
      private.peso_referido_conversion(v_mes)) e
    where e.analista_id=any(v_visibles) or v_rol='gerencia' or v_lector
    group by e.analista_id
  ) n;
  return v_payload || jsonb_build_object(
    -- DECLARACION (Ola 2, 22/09/2026). Esta puerta es la excepcion del grupo:
    -- NO publica ninguna tasa de conversion. Lo que publica es un RECUENTO
    -- —`totales.convertidos`, cierres del mes sin ponderar, y
    -- `totales.operaciones_cartera`— que no pasa por ningun divisor. Por eso
    -- no delega: no hay cifra que delegar.
    --   es_mes_calendario: true. Siempre mide el mes en curso (`v_mes` = dia 1),
    --     y ya lo decia en `ventana_metrica`.
    --   fuente: 'rango_vivo'. Cuenta sobre `private.conversion_episodios`.
    --   sellado: null. No se delego, asi que no sabe si el mes esta sellado.
    --   ajuste_aplicado: false. Un recuento de cierres no resta la deuda de
    --     anulacion: esa resta vive en el NUMERADOR ponderado, que esta puerta
    --     no publica. Declararlo `true` seria afirmar algo que no hace.
    'es_mes_calendario', true,
    'fuente', 'rango_vivo',
    'sellado', null,
    'ajuste_aplicado', false,
    'version',1,'generado_en',v_ahora,
    'ventana_convertidos_dias',45,'ventana_metrica','mes_calendario','mes_metrica',v_mes,
    'totales',(v_payload->'totales') || jsonb_build_object('convertidos',v_cierres,'operaciones_cartera',v_operaciones));
end;
$function$

```
### private.puede_operar_reparto_crm
```sql
CREATE OR REPLACE FUNCTION private.puede_operar_reparto_crm()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    private.rol_crm((select auth.uid())) in ('coordinador','gerencia'),
    false
  );
$function$

```
### private.puede_acceder_crm
```sql
CREATE OR REPLACE FUNCTION private.puede_acceder_crm()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.rol_crm((select auth.uid())) is not null
      or private.es_lector_global();
$function$

```
### crm.bandera_activa
```sql
CREATE OR REPLACE FUNCTION crm.bandera_activa(p_nombre text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select activo from crm.multiempresa_flags where nombre = p_nombre), false)
$function$

```
ACL: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
### Policies de crm.leads (lectura)
```
crm_actor_activo_gate · cmd=* · permissive=false · roles={authenticated}
  USING ( SELECT private.puede_acceder_crm() AS puede_acceder_crm)
leads_select · cmd=r · permissive=true · roles={authenticated}
  USING ((activo = true) AND ((vendedor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles)) OR ((vendedor_id IS NULL) AND (asignado_supervisor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles))) OR (( SELECT private.rol_crm(( SELECT auth.uid() AS uid)) AS rol_crm) = 'gerencia'::text) OR ( SELECT private.es_lector_global() AS es_lector_global)))
```
### Policy y grants de crm.lead_potencial
```
lead_potencial_select · cmd=r · roles={authenticated} USING (EXISTS ( SELECT 1
   FROM crm.leads l
  WHERE (l.id = lead_potencial.lead_id)))
relacl: {postgres=arwdDxtm/postgres}
```

