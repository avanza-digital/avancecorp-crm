ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión — RONDA 1 (LEVEL 3: cambio de firma de una puerta viva + ayudante DEFINER) · Potencial del lead, FASE 3 entrega B (servidor)

Eres el revisor secundario. Sin base de datos ni red: todo está transcrito abajo. Tu trabajo es REFUTAR: busca la fuga, el falso verde y el caso que falta. Responde con VERDICT (APPROVE / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 con evidencia (archivo/fragmento), riesgos y test gaps, NEXT ACTIONS y CONFIDENCE. Sin hallazgo sin evidencia; distingue hipótesis de hechos.

## Negocio (decisiones de Miguel, 30/09 y 01/10)
Los analistas marcan cada lead como Frío, Tibio o Estrella («potencial del lead»). Marcan el analista dueño y su supervisor; gerencia y directorio solo ven y filtran. Fases 1 (marcar), 2 (la marca baja sola) y 3A (leer la marca por lote, `crm.potencial_leads_fn(uuid[])`) están EN PRODUCCIÓN y la bandera `potencial_lead` está ENCENDIDA desde hoy. Esta entrega B añade en la pantalla de Leads una fila «Por potencial» con cuatro botones con conteo (Estrella, Tibio, Frío, Sin marcar): al tocar uno, la lista, los totales y el capital se quedan con ese nivel. Decidido: solo en Leads (no en Pipeline), «Sin marcar» es una opción, un nivel a la vez. El orden de las listas no cambia.

## Contexto técnico
- La tabla de Leads y las 5 columnas del Pipeline leen de `crm.cartera_filtrada_fn` (plpgsql, STABLE, **INVOKER**, `search_path` vacío, EXECUTE solo `authenticated`). Hoy tiene 13 argumentos (el 13.º, `p_gestion`, lo añadió HOY otra sesión con `20261001154153`, ya en producción). `crm.resumen_cartera_fn()` (DEFINER, transcrita abajo) la envuelve: `crm.cartera_filtrada_fn(p_limite=>1)->'resumen'`.
- Las tablas del potencial (`crm.lead_potencial`, una fila por lead con `nivel`) tienen RLS y NINGÚN grant para la API (decisión de la fase 1 con el auditor: la pantalla no lee tablas). Existe una policy `lead_potencial_select` «por si algún día se concede SELECT» (exists sobre `crm.leads`), sin grant.
- El esquema `private` no está expuesto en PostgREST (expuestos: `public`, `crm`). `authenticated` tiene USAGE sobre `private` porque las funciones INVOKER de `crm` llaman a ayudantes de ahí.
- El frente valida la respuesta con valibot `v.object(...)` tanto en `CarteraFiltradaSchema` como en `ResumenCarteraSchema` (no `strictObject`): las claves desconocidas se descartan sin error. Los frentes publicados NO envían `p_potencial`.
- Un censo diario (`private.contadores_crudos_leads_citas`) vigila toda función que nombre `crm.leads` y cuente; `cartera_filtrada_fn` está declarada con una exención sellada que hay que MOVER a la firma nueva (mismo procedimiento que usó `20261001154153`).
- Producción: las migraciones las aplica Miguel con `supabase db query --linked --file`; el reviewer no ve la base. Banco de pruebas: Docker propio con el esquema de producción de hoy.

## Decisiones a refutar
1. El filtro va DENTRO de `crm.cartera_filtrada_fn` (argumento 14, `p_potencial text default null`: 'estrella' | 'tibio' | 'frio' | 'sin_marca') y no en una puerta aparte: tiene que recortar la misma base que los demás filtros, con el mismo cursor.
2. Los conteos por nivel (`resumen.potencial = {filtro, estrella, tibio, frio, sin_marca}`) se calculan ANTES de aplicar `p_potencial` (CTE `previa`) para que no cambien al elegir un nivel; todo lo demás (filas, totales, capital, embudo) sale de `base` = `previa` recortada. `filtro` es el eco.
3. Para leer la marca desde una función INVOKER sin abrir la tabla: ayudante `private.cartera_potencial_fn()` **SECURITY DEFINER** (molde `private.cartera_recepciones_fn`), con sesión + gate `private.puede_acceder_crm()` + bandera + el MISMO predicado de ámbito que la base de la cartera (global, analistas visibles, bandeja del supervisor visible o de quien opera el reparto). NO es el espejo de la policy `leads_select`: dentro de `crm.resumen_cartera_fn` (DEFINER) la cartera corre sin RLS y su base incluye la bandeja del reparto (coordinador); con el espejo de la policy esas marcas contarían como «sin marca». Por la API (INVOKER) la RLS de `crm.leads` recorta `previa` antes de unirla con las marcas.
   Alternativa descartada: `GRANT SELECT (lead_id, nivel)` a `authenticated` apoyándose en la policy que ya existe. Se descartó por no abrir la tabla a PostgREST (contradice la fase 1) y porque la lectura directa se saltaría la bandera.
4. Con la bandera APAGADA: la respuesta es byte a byte la de la firma de 13 (sin la clave `potencial`) y pedir el filtro da 55000 (igual que la puerta de marcar). La validación del valor (22023) va antes.
5. Las filas NO cambian de forma: la columna de trabajo `potencial_nivel` se quita con `to_jsonb(f) - 'potencial_nivel'`. No hay claves nuevas arriba; la única clave nueva está dentro de `resumen`.
6. `base as not materialized` sobre `previa as materialized`: cada referencia a `base` es un CTE scan de `previa` con el filtro; no se copia la base.
7. Una sola firma: `drop` de la de 13 y `create` de la de 14 en la misma transacción (dos candidatas romperían PostgREST). El cuerpo nuevo se generó desde el texto de la migración anterior con sustituciones exactas y contadas (la diferencia completa está abajo).
8. Preflight por identidad: md5 de `pg_get_functiondef` de la firma de 13 (el mismo valor que fijó el postflight de `20261001154153`), declaración analítica vigente y sellada, forma de `crm.lead_potencial` (columnas, RLS, sin SELECT para la API), niveles del enum, huellas de 7 ayudantes de visibilidad (5 de ellas ya pasaron en producción hoy en el preflight de la 3A), permisos de `crm.bandera_activa`. `search_path` vacío y `quote_all_identifiers` off para la transacción.
9. Las anclas de la regla de GESTIÓN (trigger de `tenencia_desde`, integridad de `crm.actividades`) NO se repiten: son de `20261001154153` y esta migración no cambia esa regla; sí se repite `private.assert_actividades_de_lead_base()`.
10. La reversa (generada, no tecleada) reinstala la firma de 13 byte a byte y exige md5 `bf06666f…` en su postflight.

## Preguntas
a. FUGA: ¿algún actor obtiene, por la cartera (INVOKER) o por `crm.resumen_cartera_fn` (DEFINER), la marca o un conteo que revele marcas de leads fuera de su ámbito? Mira los NULL (`v_global` null cuando `rol_crm` es null), el coordinador (opera el reparto pero su RLS no ve la bandeja ajena), el canal lateral del cursor con `p_potencial`, y si los conteos por nivel revelan algo que `totales` no revelara ya.
b. ¿Es aceptable un ayudante DEFINER con EXECUTE para `authenticated` en `private` cuyo ámbito es el predicado de la cartera y no el espejo de la RLS? ¿Ves una vía por la que `authenticated` lo llame directamente (PostgREST, otra función expuesta que ejecute SQL del usuario)? ¿Preferirías el espejo de `leads_select` aun con la inconsistencia del envoltorio, u otra salida?
c. COMPATIBILIDAD: con la bandera encendida en producción, TODA respuesta gana `resumen.potencial` y `crm.resumen_cartera_fn` la deja pasar en su payload (`v_payload || jsonb_build_object(...)`). ¿Algo que un frente publicado pueda romper? ¿Algo en el orden «servidor primero, pantalla después»?
d. PREFLIGHT/POSTFLIGHT: ¿falsos rojos en producción (formato de `format_type`, `pg_get_functiondef`, ACL) o falsos verdes? ¿El postflight del ayudante deja pasar algo (ACL, `proconfig`, dueño)?
e. SEMÁNTICA: `sin_marca` incluye convertidos (ventana de 45 días) y descartados sin marca, y los niveles incluyen leads cerrados con marca; el botón «Sin marcar» mostraría también esos. ¿Incoherencia con algo de arriba? ¿Conteos y `totales.vivos` pueden discrepar en algún caso (carrera entre `marcas` y `previa` dentro de la misma sentencia STABLE)?
f. RENDIMIENTO: +2 ms medidos por llamada (el Pipeline hace 5 llamadas y Leads 1). ¿Algún caso patológico (miles de marcas, plan del `left join` contra un CTE materializado sin índice)?
g. REVERSA: ¿deja algo? ¿El orden con la reversa de `20261001154153` es correcto?
h. ¿Qué caso falta en `prueba-filtro.sql` o en el bloque del gate?

## Evidencia (banco Docker: esquema de producción del 01/10 13:31 + las migraciones posteriores del repo; trinquete analítico sembrado)
Resultado del ciclo `banco/ciclo-fase3b.sh` (salida real):
```
0 reversa del estado previo: NOTICE:  REVERSA filtro_potencial OK: firma unica de 13 (md5 bf06666f…), sin ayudante, declaracion analitica devuelta y sellada. Las marcas se conservan.
1 migración:        NOTICE:  cartera_filtro_potencial OK: firma unica de 14 argumentos, ayudante DEFINER solo authenticated, contrato de seguridad intacto, declaracion analitica movida y sellada.
2 repetida:         ERROR:  PREFLIGHT: cartera_filtrada_fn no coincide con la version auditada, o esta migracion ya esta aplicada
3 reversa:          NOTICE:  REVERSA filtro_potencial OK: firma unica de 13 (md5 bf06666f…), sin ayudante, declaracion analitica devuelta y sellada. Las marcas se conservan.
4 reversa repetida: ERROR:  REVERSA filtro_potencial: la entrega B no esta aplicada tal como se publico
5 tras la reversa:  md5 de la cartera bf06666fb8ef533a39a50c7d70420153 (debe ser bf06666fb8ef533a39a50c7d70420153), ayudante=0
6 migración:        NOTICE:  cartera_filtro_potencial OK: firma unica de 14 argumentos, ayudante DEFINER solo authenticated, contrato de seguridad intacto, declaracion analitica movida y sellada.
7 trinquetes:       idénticos sin y con la migración, salvo la fila de la cartera (27 pasan, 9 caen igual, CENSO (sin la cartera) 37 filas)
  la cartera en el censo, antes:   (funcion,"crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)",t,t)
  la cartera en el censo, después: (funcion,"crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)",t,t)
8 tras la reversa:  la foto entera es la de antes (censo incluido)
9  filtro:            ERROR:  FILTRO potencial_lead: 132 de 132 OK
10 fase 1 intacta:    ERROR:  SINTETICA potencial_lead: 75 de 75 OK
11 fase 2 intacta:    ERROR:  CADUCIDAD potencial_lead: 51 de 51 OK
12 fase 3A intacta:   ERROR:  LECTURA potencial_lead: 94 de 94 OK
13 regla de gestión:  CARTERA_GESTION_OK 128/128 (oráculo de scripts/cartera-gestion contra la firma de 14)
  tras los mutantes: ayudante=1, md5 de la cartera=42a452bd5318ecdd7e319d144bd0c44f, SELECT de authenticated sobre la tabla de marcas=f, sello vigente=t
14 ERROR:  MEDIR filtro · gerencia (6000 leads, 2400 marcas): anterior 19.2 ms, nueva 20.5 ms, con estrella 17.1 ms, con sin_marca 20.2 ms · supervisor (1000 leads, 400 marcas): anterior 4.8 ms, nueva 6.5 ms, con estrella 5.8 ms, con sin_marca 6.8 ms · analista (100 leads, 100 marcas): anterior 2.9 ms, nueva 4.2 ms, con estrella 3.9 ms, con sin_marca 3.8 ms
15 el registrador lleva el md5 de la migración
16 registrar:          NOTICE:  REGISTRO: 20261001212341 / crm_cartera_filtro_potencial (1 sentencia: el archivo entero)
17 registrar otra vez: NOTICE:  REGISTRO: 20261001212341 / crm_cartera_filtro_potencial (1 sentencia: el archivo entero)
18 verificar:          VERIFICAR filtro_potencial: firmas [crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)] (debe ser una, la de 14), md5 42a452bd5318ecdd7e319d144bd0c44f (debe ser 42a452bd5318ecdd7e319d144bd0c44f), ejecutan la cartera [authenticated] (debe ser authenticated), ejecutan el ayudante [authenticated] (debe ser
19 verificar con la tabla abierta por columna: leen la tabla de marcas por la API [authenticated]
20 verificar con el ayudante abierto a PUBLIC:  ejecutan el ayudante [anon,authenticated,service_role]
   estado final: ayudante=1, md5 de la cartera=42a452bd5318ecdd7e319d144bd0c44f, SELECT de authenticated sobre la tabla de marcas=f, sello vigente=t
```
Mutantes (salida real; en los de lógica lo correcto es «N FALLAS», en los de migración un `ERROR: PREFLIGHT/POSTFLIGHT`):
```
  m-ayu-sin-bandeja              → ERROR:  FILTRO potencial_lead: 9 FALLAS de 132: 40 S1: conteos → esperado - E3 T3 F1 S2 v=9, obtenido - E3 T3 F0 S3 v=9 | 66 S1 sin filtro = oráculo (
  m-ayu-sin-bandera              → ERROR:  FILTRO potencial_lead: 1 FALLAS de 132: 13 apagada: el ayudante no devuelve nada (gerencia) → esperado (ninguno), obtenido L1:e,L1n:t,L2:e,LC:
  m-ayu-sin-gate                 → ERROR:  FILTRO potencial_lead: 3 FALLAS de 132: 126 ayudante, P (solo portal) → 42501 → esperado error 42501, obtenido (ninguno) | 127 ayudante, X (eq
  m-ayu-sin-gerencia-ni-reparto  → ERROR:  FILTRO potencial_lead: 12 FALLAS de 132: 36 G: conteos → esperado - E4 T4 F1 S3 v=12, obtenido - E4 T3 F1 S4 v=12 | 46 G sin filtro = oráculo 
  m-ayu-sin-gerencia             → ERROR:  FILTRO potencial_lead: 132 de 132 OK
  m-ayu-sin-lector               → ERROR:  FILTRO potencial_lead: 13 FALLAS de 132: 37 D (directorio) ve lo mismo que gerencia → esperado - E4 T4 F1 S3 v=12, obtenido - E0 T0 F0 S12 v=1
  m-ayu-sin-propios              → ERROR:  FILTRO potencial_lead: 55 FALLAS de 132: 40 S1: conteos → esperado - E3 T3 F1 S2 v=9, obtenido - E0 T0 F1 S8 v=9 | 41 S1n: solo el lead de su 
  m-ayu-sin-reparto              → ERROR:  FILTRO potencial_lead: 2 FALLAS de 132: 115 C en el envoltorio: la bandeja del reparto con sus marcas → esperado - E0 T1 F1 S2 v=4, obtenido -
  m-ayu-sin-sesion-ni-gate       → ERROR:  FILTRO potencial_lead: 4 FALLAS de 132: 125 ayudante, sin sesión → 42501 → esperado error 42501, obtenido (ninguno) | 126 ayudante, P (solo po
  m-ayu-todo-global              → ERROR:  FILTRO potencial_lead: 4 FALLAS de 132: 121 ayudante, S1: su equipo y su bandeja → esperado L1:e,L1n:t,LC:e,LD:t,LK:t,LP:f,LZ:e, obtenido L1:e
  m-ayu-ve-inactivos             → ERROR:  FILTRO potencial_lead: 4 FALLAS de 132: 119 ayudante, G: todas las marcas de leads activos → esperado L1:e,L1n:t,L2:e,LC:e,LD:t,LK:t,LP:f,LSM:
  m-fn-clave-siempre             → ERROR:  FILTRO potencial_lead: 3 FALLAS de 132: 8 apagada: el resumen NO trae la clave potencial → esperado (sin clave) v=7, obtenido - E0 T0 F0 S7 v=
  m-fn-columna-viaja             → ERROR:  FILTRO potencial_lead: 4 FALLAS de 132: 16 apagada: la respuesta es la de la firma de 13 (10 actores × 14 llamadas) → esperado 140 de 140, obt
  m-fn-conteos-tras-filtro       → ERROR:  FILTRO potencial_lead: 35 FALLAS de 132: 47 G con estrella = oráculo → esperado L1,L2,LC,LZ | E4 T4 F1 S3, obtenido L1,L2,LC,LZ | E4 T0 F0 S0 
  m-fn-embudo-de-previa          → ERROR:  FILTRO potencial_lead: 1 FALLAS de 132: 105 V1 estrella: el embudo suma el total → esperado 3, obtenido 7
  m-fn-estrella-cuenta-tibio     → ERROR:  FILTRO potencial_lead: 36 FALLAS de 132: 41 S1n: solo el lead de su analista → esperado - E0 T1 F0 S0 v=1, obtenido - E1 T1 F0 S0 v=1 | 42 V1:
  m-fn-frio-cuenta-sin-marca     → ERROR:  FILTRO potencial_lead: 38 FALLAS de 132: 36 G: conteos → esperado - E4 T4 F1 S3 v=12, obtenido - E4 T4 F3 S3 v=12 | 37 D (directorio) ve lo mi
  m-fn-no-recorta                → ERROR:  FILTRO potencial_lead: 48 FALLAS de 132: 47 G con estrella = oráculo → esperado L1,L2,LC,LZ | E4 T4 F1 S3, obtenido L1,L1n,L2,L3,LC,LD,LK,LP,L
  m-fn-pagina-de-previa          → ERROR:  FILTRO potencial_lead: 42 FALLAS de 132: 47 G con estrella = oráculo → esperado L1,L2,LC,LZ | E4 T4 F1 S3, obtenido L1,L1n,L2,L3,LC,LD,LK,LP,L
  m-fn-sin-bandera               → ERROR:  FILTRO potencial_lead: 2 FALLAS de 132: 9 apagada: pedir el filtro → 55000 → esperado error 55000, obtenido (ninguno) | 10 apagada: pedir «sin
  m-fn-sin-eco                   → ERROR:  FILTRO potencial_lead: 3 FALLAS de 132: 97 V1 con estrella: eco, conteos intactos y total del nivel → esperado estrella E3 T2 F0 S2 v=3, obten
  m-fn-sin-marca-rota            → ERROR:  FILTRO potencial_lead: 8 FALLAS de 132: 50 G con sin_marca = oráculo → esperado L3,LPV,LS | E4 T4 F1 S3, obtenido (ninguno) | E4 T4 F1 S3 | 55
  m-fn-sin-marca-trae-todo       → ERROR:  FILTRO potencial_lead: 12 FALLAS de 132: 50 G con sin_marca = oráculo → esperado L3,LPV,LS | E4 T4 F1 S3, obtenido L1,L1n,L2,L3,LC,LD,LK,LP,LP
  m-fn-sin-union                 → ERROR:  FILTRO potencial_lead: 76 FALLAS de 132: 36 G: conteos → esperado - E4 T4 F1 S3 v=12, obtenido - E0 T0 F0 S12 v=12 | 37 D (directorio) ve lo m
  m-fn-sin-validar               → ERROR:  FILTRO potencial_lead: 8 FALLAS de 132: 11 apagada: un valor inválido sigue siendo 22023 (se valida antes) → esperado error 22023, obtenido er
  m-fn-totales-de-previa         → ERROR:  FILTRO potencial_lead: 5 FALLAS de 132: 97 V1 con estrella: eco, conteos intactos y total del nivel → esperado estrella E3 T2 F0 S2 v=3, obten
  (m-ayu-sin-gerencia debe dar «de N OK»: gerencia ve a todos los analistas y opera el reparto, así que su rama propia no añade nada; su doble sin gerencia ni reparto debe caer)
  post-abre-la-tabla                 → ERROR:  POSTFLIGHT: crm.lead_potencial quedo con algun grant de lectura para la API
  post-ayudante-a-anon               → ERROR:  POSTFLIGHT: el ayudante no quedo DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-a-service-role       → ERROR:  POSTFLIGHT: el ayudante no quedo DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-con-opcion           → ERROR:  POSTFLIGHT: el ayudante no quedo DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-cuenta               → ERROR:  POSTFLIGHT: el ayudante no quedo DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-invoker              → ERROR:  POSTFLIGHT: el ayudante no quedo DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-publico              → ERROR:  POSTFLIGHT: el ayudante no quedo DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-set-de-mas           → ERROR:  POSTFLIGHT: el ayudante no quedo DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-sin-grant            → ERROR:  POSTFLIGHT: el ayudante no quedo DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-sin-search-path      → ERROR:  POSTFLIGHT: el ayudante no quedo DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-ayudante-sin-sesion           → ERROR:  POSTFLIGHT: el ayudante acepto una llamada sin sesion
  post-ayudante-volatil              → ERROR:  POSTFLIGHT: el ayudante no quedo DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated
  post-cartera-a-anon                → ERROR:  POSTFLIGHT: firma, cuerpo, permisos o contrato invalido
  post-cartera-a-service-role        → ERROR:  POSTFLIGHT: firma, cuerpo, permisos o contrato invalido
  post-cartera-definer               → ERROR:  POSTFLIGHT: firma, cuerpo, permisos o contrato invalido
  post-cuerpo-cambiado               → ERROR:  POSTFLIGHT: firma, cuerpo, permisos o contrato invalido
  post-sin-mover-la-declaracion      → ERROR:  POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno
  post-sin-resellar                  → ERROR:  POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno
  post-toca-otra-declaracion         → ERROR:  POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno
  pre-ayudante-de-ambito-cambiado    → ERROR:  PREFLIGHT: un ayudante de visibilidad no es el ensayado: crm.bandera_activa(text)=bb817f2b07b561356959f25dc3aae4dc private.cartera_p
  pre-ayudante-ya-existe             → ERROR:  PREFLIGHT: cartera_filtrada_fn no coincide con la version auditada, o esta migracion ya esta aplicada
  pre-bandera-a-anon                 → ERROR:  PREFLIGHT: los permisos de crm.bandera_activa o del esquema private no son los ensayados
  pre-bandera-sin-execute            → ERROR:  PREFLIGHT: los permisos de crm.bandera_activa o del esquema private no son los ensayados
  pre-columna-nueva                  → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-funcion-cambiada               → ERROR:  PREFLIGHT: cartera_filtrada_fn no coincide con la version auditada, o esta migracion ya esta aplicada
  pre-huella-vieja                   → ERROR:  PREFLIGHT: la declaracion analitica no esta vigente y sellada
  pre-nivel-nuevo                    → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-reparto-cambiado               → ERROR:  PREFLIGHT: un ayudante de visibilidad no es el ensayado: crm.bandera_activa(text)=bb817f2b07b561356959f25dc3aae4dc private.cartera_p
  pre-select-a-anon                  → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-select-a-la-api                → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-select-por-columna             → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-sello-roto                     → ERROR:  PREFLIGHT: la declaracion analitica no esta vigente y sellada
  pre-sin-bandera                    → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-sin-rls                        → ERROR:  PREFLIGHT: el potencial del lead (20260930213647) no esta como se ensayo
  pre-sobrecarga                     → ERROR:  PREFLIGHT: cartera_filtrada_fn no coincide con la version auditada, o esta migracion ya esta aplicada
  pre-visibles-cambiado              → ERROR:  PREFLIGHT: un ayudante de visibilidad no es el ensayado: crm.bandera_activa(text)=bb817f2b07b561356959f25dc3aae4dc private.cartera_p
```
- Igualdad con la función anterior: 10 actores × 14 llamadas con la bandera apagada (byte a byte salvo `generado_en`) y otras 140 con la bandera encendida (quitando `resumen.potencial`). Están dentro de `prueba-filtro.sql`.
- El oráculo de la regla de gestión de la otra sesión (128 aserciones) pasa contra la firma de 14 (paso 13).
- `test-rls.mjs` (gate con sesiones reales por PostgREST): **NOT RUN** (exige credenciales de una rama de Supabase); `node --check`: PASS. Se actualizó su comprobación de catálogo (acepta la firma de 13 o la de 14) y se añadió el bloque `testPotencialFiltro` (abajo).
- Advisors de Supabase: se medirán al publicar (los lanza Miguel).

## Archivos

### supabase/migrations/20261001212341_crm_cartera_filtro_potencial.sql (NUEVA, completa)
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
--   · con la bandera `potencial_lead` apagada, pedirlo → 55000 (igual que la puerta de marcar).
--   Y el resumen gana UNA clave, `resumen.potencial` = {filtro, estrella, tibio, frio, sin_marca}:
--   cuántos leads hay de cada nivel con los DEMÁS filtros puestos. Se cuenta ANTES de aplicar
--   `p_potencial`: los cuatro números no cambian al elegir un nivel, suman el total sin ese filtro
--   y el del nivel elegido coincide con `totales.vivos`. `filtro` es el eco del pedido.
--
-- CÓMO LEE LA MARCA. La función es INVOKER y las tablas del potencial no tienen grants de API
--   (fase 1, auditor-rls r1): nace `private.cartera_potencial_fn()`, un ayudante con el molde de
--   `private.cartera_recepciones_fn` (el otro ayudante de esta misma función). Devuelve
--   (lead_id, nivel) de las marcas vigentes de los leads activos del ámbito del actor.
-- SECURITY DEFINER, justificación: una función INVOKER no puede leer `crm.lead_potencial` (sin
--   grants para nadie de la API, y así se queda). El ayudante verifica de forma explícita la sesión,
--   el gate del CRM (`private.puede_acceder_crm`, invocado) y el ÁMBITO, que es el MISMO predicado
--   de la base de la cartera (global, analistas visibles, bandeja del supervisor visible o de quien
--   opera el reparto), con los mismos ayudantes. Es el ámbito de la base y no el espejo de
--   `leads_select` a propósito: `crm.resumen_cartera_fn` (DEFINER) llama a la cartera sin RLS y ahí
--   la base incluye la bandeja del reparto; con otro ámbito esas marcas saldrían «sin marca». Por
--   la API (INVOKER) la RLS de `crm.leads` recorta la base antes de unirla con las marcas, así que
--   nadie recibe la marca de un lead que no ve. `search_path` vacío, dueño postgres, EXECUTE solo
--   `authenticated`; el esquema `private` no está expuesto en la API.
--
-- QUÉ NO CAMBIA. Con la bandera apagada la respuesta es byte a byte la de la firma de 13. Con la
--   bandera encendida y sin el filtro, solo se AÑADE `resumen.potencial` (clave nueva dentro del
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
  --    RLS encendida, SIN grants para la API (por eso hace falta el ayudante), y su bandera.
  if (
    (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attnum)
       from pg_attribute a
      where a.attrelid = to_regclass('crm.lead_potencial') and a.attnum > 0 and not a.attisdropped)
      = 'id:uuid,lead_id:uuid,nivel:crm.nivel_potencial,origen:text,marcado_por:uuid,marcado_en:timestamp with time zone,creado_en:timestamp with time zone,actualizado_en:timestamp with time zone'
    and (select c.relrowsecurity from pg_class c where c.oid = to_regclass('crm.lead_potencial'))
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
  -- 5. El ámbito del ayudante descansa en estos ayudantes, los mismos de la base de la cartera:
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
                  to_regprocedure('private.cartera_puede_operar_reparto_fn()'),
                  to_regprocedure('private.puede_operar_reparto_crm()'),
                  to_regprocedure('crm.bandera_activa(text)'));
  if v_huellas is distinct from
       'crm.bandera_activa(text)=bb817f2b07b561356959f25dc3aae4dc'
    || ' private.cartera_puede_operar_reparto_fn()=418bce371aa02fb572bbbea38f5ebe29'
    || ' private.es_lector_global()=5b8ac0c37dcbf5b82057d7b98c65c303'
    || ' private.puede_acceder_crm()=4e2c1caf7ead51be450d5018be4c6092'
    || ' private.puede_operar_reparto_crm()=c7d4261e635f1df16a525e39e509c70e'
    || ' private.rol_crm(uuid)=16960a2a21cc5c372431c2dd67acafe4'
    || ' private.vendedor_ids_visibles(uuid)=45ae492c03234b80336c0b8f5c8ac09b' then
    raise exception 'PREFLIGHT: un ayudante de visibilidad no es el ensayado: %', coalesce(v_huellas, '(ninguno)');
  end if;
  -- 6. La función INVOKER debe poder llamar a la bandera, y la API no.
  if (
    has_function_privilege('authenticated', 'crm.bandera_activa(text)', 'EXECUTE')
    and not has_function_privilege('anon', 'crm.bandera_activa(text)', 'EXECUTE')
    and has_schema_privilege('authenticated', 'private', 'USAGE')
  ) is not true then
    raise exception 'PREFLIGHT: los permisos de crm.bandera_activa o del esquema private no son los ensayados';
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
  v_global boolean;
  v_visibles uuid[];
  v_reparto boolean;
begin
  if v_uid is null or private.puede_acceder_crm() is not true then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  -- Con la bandera apagada no se lee nada (igual que crm.potencial_leads_fn).
  if crm.bandera_activa('potencial_lead') is not true then
    return;
  end if;
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_reparto := private.cartera_puede_operar_reparto_fn();
  return query
    select p.lead_id, p.nivel::text
    from crm.lead_potencial p
    join crm.leads l on l.id = p.lead_id
    -- MISMO ámbito que la base de crm.cartera_filtrada_fn (el predicado de abajo es el suyo).
    where l.activo is true
      and (v_global or l.vendedor_id = any(v_visibles)
        or (l.vendedor_id is null and (l.asignado_supervisor_id = any(v_visibles)
          or v_reparto)));
end;
$$;
alter function private.cartera_potencial_fn() owner to postgres;
revoke all on function private.cartera_potencial_fn() from public, anon, authenticated, service_role;
grant execute on function private.cartera_potencial_fn() to authenticated;
comment on function private.cartera_potencial_fn() is
  'Ayudante de crm.cartera_filtrada_fn: (lead_id, nivel) de la marca de potencial vigente de los leads activos del ambito del actor (el mismo predicado de la base de la cartera: global, analistas visibles, bandeja del supervisor visible o de quien opera el reparto). SECURITY DEFINER porque crm.lead_potencial no tiene grants de API; exige sesion y el gate del CRM (42501). Con la bandera potencial_lead apagada no devuelve filas. No esta expuesto en la API (esquema private).';

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
  -- El potencial solo existe con su bandera encendida. Apagada, la respuesta es la de siempre
  -- (sin la clave `resumen.potencial`) y pedir el filtro se rechaza como en la puerta de marcar.
  v_potencial := crm.bandera_activa('potencial_lead') is true;
  if p_potencial is not null and not v_potencial then
    raise exception 'El potencial del lead no está habilitado' using errcode = '55000';
  end if;

  with recepciones as materialized (
    select * from private.cartera_recepciones_fn(p_desde,p_hasta)
  ), marcas as materialized (
    -- Marca vigente de los leads del ámbito. Ayudante DEFINER: las tablas del potencial no
    -- tienen grants de API. Con la bandera apagada no devuelve filas.
    select m.lead_id, m.nivel from private.cartera_potencial_fn() m
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
      -- la bandera encendida: apagada, el resumen es byte a byte el de antes.
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
  'Inventario de Leads con filtros comunes, incluidos reasignados (titular actual con una asignacion anterior a un analista), gestion (p_gestion: con_gestion = el titular actual ya intento el contacto desde tenencia_desde, sin contar resultados de llamada deshechos; sin_gestion = el resto) y potencial (p_potencial: estrella, tibio, frio o sin_marca; con la bandera potencial_lead apagada se rechaza con 55000). Listado y resumen salen de la misma base; resumen.potencial cuenta cada nivel con los demas filtros puestos, antes de aplicar p_potencial, y solo viaja con la bandera encendida.';

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
    and md5(pg_get_functiondef(to_regprocedure(f14))) = '42a452bd5318ecdd7e319d144bd0c44f'
    and not has_function_privilege('anon', f14, 'EXECUTE')
    and not has_function_privilege('service_role', f14, 'EXECUTE')
    and has_function_privilege('authenticated', f14, 'EXECUTE')
    and (select to_jsonb(p) from (select proowner::regrole::text as duenio,
            prosecdef, provolatile, proconfig, proacl
          from pg_proc where oid = to_regprocedure(f14)) p) = pre.contrato
  ) is not true then
    raise exception 'POSTFLIGHT: firma, cuerpo, permisos o contrato invalido';
  end if;
  -- 2. El ayudante: DEFINER, STABLE, dueño postgres, configuración EXACTA (solo search_path vacío),
  --    ACL explícita (postgres y authenticated; authenticated solo EXECUTE y sin opción de
  --    concederlo), permisos EFECTIVOS (authenticated sí; anon y service_role no) y sin conteos.
  if (
    exists (select 1 from pg_proc p
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
    raise exception 'POSTFLIGHT: el ayudante no quedo DEFINER/STABLE/postgres/solo search_path vacio/EXECUTE solo authenticated';
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
  ) is not true then
    raise exception 'POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno';
  end if;
  perform private.assert_actividades_de_lead_base();
  -- 5. Sin sesión, el ayudante y la función se niegan (aquí no hay sesión de usuario).
  begin
    perform 1 from private.cartera_potencial_fn();
    raise exception 'POSTFLIGHT: el ayudante acepto una llamada sin sesion' using errcode = 'P0001';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform crm.cartera_filtrada_fn(p_limite => 1, p_potencial => 'estrella');
    raise exception 'POSTFLIGHT: la cartera acepto una llamada sin sesion' using errcode = 'P0001';
  exception when insufficient_privilege then
    null;
  end;
  raise notice 'cartera_filtro_potencial OK: firma unica de 14 argumentos, ayudante DEFINER solo authenticated, contrato de seguridad intacto, declaracion analitica movida y sellada.';
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
@@ -55,2 +60,8 @@
   v_reparto := private.cartera_puede_operar_reparto_fn();
+  -- El potencial solo existe con su bandera encendida. Apagada, la respuesta es la de siempre
+  -- (sin la clave `resumen.potencial`) y pedir el filtro se rechaza como en la puerta de marcar.
+  v_potencial := crm.bandera_activa('potencial_lead') is true;
+  if p_potencial is not null and not v_potencial then
+    raise exception 'El potencial del lead no está habilitado' using errcode = '55000';
+  end if;
 
@@ -58,3 +69,7 @@
     select * from private.cartera_recepciones_fn(p_desde,p_hasta)
-  ), base as materialized (
+  ), marcas as materialized (
+    -- Marca vigente de los leads del ámbito. Ayudante DEFINER: las tablas del potencial no
+    -- tienen grants de API. Con la bandera apagada no devuelve filas.
+    select m.lead_id, m.nivel from private.cartera_potencial_fn() m
+  ), previa as materialized (
     select l.id, l.nombre_completo, l.telefono, l.telefono_alternativo,
@@ -71,3 +86,4 @@
       coalesce(mov.reasignado, false) as reasignado,
-      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada
+      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada,
+      mk.nivel as potencial_nivel
     from crm.leads l
@@ -86,2 +102,3 @@
     left join recepciones r on r.lead_id = l.id
+    left join marcas mk on mk.lead_id = l.id
     where l.activo is true
@@ -119,2 +136,10 @@
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
@@ -158,3 +183,4 @@
     'reasignados',coalesce(p_reasignados,false),
-    'items',coalesce((select jsonb_agg(to_jsonb(f) order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
+    -- La columna de trabajo `potencial_nivel` no viaja: las filas tienen la forma de siempre.
+    'items',coalesce((select jsonb_agg(to_jsonb(f) - 'potencial_nivel' order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
     'resumen',jsonb_build_object('totales',(select to_jsonb(m) from metricas m),
@@ -179,3 +205,12 @@
         from (values('nuevo',1),('contactado',2),('reunion_agendada',3),
-          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord))))
+          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord)))
+      -- Conteos por nivel sobre `previa` (antes de `p_potencial`) y el eco del filtro. Solo con
+      -- la bandera encendida: apagada, el resumen es byte a byte el de antes.
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
    and md5(pg_get_functiondef(to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)'))) = '42a452bd5318ecdd7e319d144bd0c44f'
    and to_regprocedure('private.cartera_potencial_fn()') is not null
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
  -- Nadie más depende del ayudante: solo lo nombra la cartera.
  if exists (select 1 from pg_proc p
              where p.prosrc ilike '%cartera_potencial_fn%'
                and p.oid not in (to_regprocedure('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)'), to_regprocedure('private.cartera_potencial_fn()'))) then
    raise exception 'REVERSA filtro_potencial: otra funcion usa private.cartera_potencial_fn';
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

### supabase/scripts/potencial-lead/prueba-filtro.sql (completa; 132 casos)
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
--   LSM SIN ASIGNAR (sin analista ni supervisor), tibio: por la API solo lo ven gerencia y
--       directorio; dentro de crm.resumen_cartera_fn (DEFINER) entra en la bandeja de quien opera
--       el reparto, y su marca tiene que contar ahí.
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
insert into lds (k) values ('L1'), ('L1n'), ('L2'), ('LP'), ('LC'), ('LD'), ('LI'), ('L3'), ('LPV'), ('LK'), ('LZ'), ('LS'), ('LSM');
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
  (pg_temp.l('LSM'), 'tibio',    'manual',    pg_temp.a('S1'),  now());
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
    left join crm.lead_potencial p on p.lead_id = d.id
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
  perform pg_temp.esperar('G sin filtro', 'L1,L1n,L2,L3,LC,LD,LK,LP,LPV,LS,LSM,LZ', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('G'), 'p_limite => 200')));
  perform pg_temp.esperar('G: conteos', '- E4 T4 F1 S3 v=12', pg_temp.pot(pg_temp.cartera(pg_temp.a('G'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('D (directorio) ve lo mismo que gerencia', '- E4 T4 F1 S3 v=12', pg_temp.pot(pg_temp.cartera(pg_temp.a('D'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('DH (directorio histórico) igual', '- E4 T4 F1 S3 v=12', pg_temp.pot(pg_temp.cartera(pg_temp.a('DH'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('S1 sin filtro', 'L1,L1n,L3,LC,LD,LK,LP,LPV,LZ', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('S1'), 'p_limite => 200')));
  perform pg_temp.esperar('S1: conteos', '- E3 T3 F1 S2 v=9', pg_temp.pot(pg_temp.cartera(pg_temp.a('S1'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('S1n: solo el lead de su analista', '- E0 T1 F0 S0 v=1', pg_temp.pot(pg_temp.cartera(pg_temp.a('S1n'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('V1: conteos', '- E3 T2 F0 S2 v=7', pg_temp.pot(pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('V1n: conteos', '- E0 T1 F0 S0 v=1', pg_temp.pot(pg_temp.cartera(pg_temp.a('V1n'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('V2: conteos', '- E1 T0 F0 S0 v=1', pg_temp.pot(pg_temp.cartera(pg_temp.a('V2'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('S2: conteos', '- E1 T0 F0 S0 v=1', pg_temp.pot(pg_temp.cartera(pg_temp.a('S2'), 'p_limite => 200') -> 'resumen'));

  -- Cada nivel, rol por rol: la lista es la del nivel, el total es el del nivel, y los cuatro
  -- conteos NO cambian al elegir (se cuentan antes del filtro). Contra el oráculo de la RLS real.
  foreach ak in array array['G', 'D', 'DH', 'C', 'S1', 'S1n', 'S2', 'V1', 'V1n', 'V2'] loop
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
  perform pg_temp.esperar('G con tibio: incluye el sin asignar', 'L1n,LD,LK,LSM', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('G'), $c$p_limite => 200, p_potencial => 'tibio'$c$)));
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

  -- El cursor recorre SOLO el nivel pedido, sin saltos ni repetidos.
  v := pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 2, p_potencial => 'estrella'$c$);
  perform pg_temp.esperar('cursor: primera página de estrella', 'L1,LC', pg_temp.claves(v));
  w := pg_temp.cartera(pg_temp.a('V1'), format($c$p_limite => 2, p_potencial => 'estrella', p_antes_de => %L, p_antes_id => %L$c$,
    v #>> '{items,1,actualizado_en}', v #>> '{items,1,id}'));
  perform pg_temp.esperar('cursor: segunda página de estrella', 'LZ', pg_temp.claves(w));
  perform pg_temp.esperar('cursor: el total no depende de la página', '3/3', (v #>> '{resumen,totales,vivos}') || '/' || (w #>> '{resumen,totales,vivos}'));

  -- El coordinador: por la API ve lo que la RLS le deja; dentro del envoltorio DEFINER entra la
  -- bandeja del reparto (LP, LPV, LS y LSM) y sus marcas tienen que contar.
  perform pg_temp.esperar('C por la API = oráculo de la RLS', pg_temp.oraculo(pg_temp.a('C')), pg_temp.respuesta(pg_temp.a('C')));
  perform pg_temp.esperar('C en el envoltorio: la bandeja del reparto con sus marcas', '- E0 T1 F1 S2 v=4', pg_temp.pot(pg_temp.envoltorio(pg_temp.a('C'))));
  perform pg_temp.esperar('V1 en el envoltorio: los mismos conteos que por la API', '- E3 T2 F0 S2 v=7', pg_temp.pot(pg_temp.envoltorio(pg_temp.a('V1'))));
  perform pg_temp.esperar('G en el envoltorio', '- E4 T4 F1 S3 v=12', pg_temp.pot(pg_temp.envoltorio(pg_temp.a('G'))));
  perform pg_temp.esperar('los cuatro conteos suman el total sin filtro (todos los roles, API y envoltorio)', '0',
    (select count(*)::text from unnest(array['G', 'D', 'DH', 'C', 'S1', 'S1n', 'S2', 'V1', 'V1n', 'V2']) a(k),
       lateral (select pg_temp.cartera(pg_temp.a(a.k), 'p_limite => 1') -> 'resumen' as r union all select pg_temp.envoltorio(pg_temp.a(a.k))) x
      where (x.r #>> '{potencial,estrella}')::int + (x.r #>> '{potencial,tibio}')::int + (x.r #>> '{potencial,frio}')::int
            + (x.r #>> '{potencial,sin_marca}')::int is distinct from (x.r #>> '{totales,vivos}')::int));

  -- El ayudante por dentro: solo las marcas del ámbito del actor.
  perform pg_temp.esperar('ayudante, G: todas las marcas de leads activos', 'L1:e,L1n:t,L2:e,LC:e,LD:t,LK:t,LP:f,LSM:t,LZ:e', pg_temp.ayudante(pg_temp.a('G')));
  perform pg_temp.esperar('ayudante, D: igual que gerencia', 'L1:e,L1n:t,L2:e,LC:e,LD:t,LK:t,LP:f,LSM:t,LZ:e', pg_temp.ayudante(pg_temp.a('D')));
  perform pg_temp.esperar('ayudante, S1: su equipo y su bandeja', 'L1:e,L1n:t,LC:e,LD:t,LK:t,LP:f,LZ:e', pg_temp.ayudante(pg_temp.a('S1')));
  perform pg_temp.esperar('ayudante, V1: solo lo suyo', 'L1:e,LC:e,LD:t,LK:t,LZ:e', pg_temp.ayudante(pg_temp.a('V1')));
  perform pg_temp.esperar('ayudante, V2: solo lo suyo', 'L2:e', pg_temp.ayudante(pg_temp.a('V2')));
  perform pg_temp.esperar('ayudante, C: la bandeja del reparto', 'LP:f,LSM:t', pg_temp.ayudante(pg_temp.a('C')));
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
         and (w #> '{resumen,potencial}') is not null then v_iguales := v_iguales + 1;
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
  perform pg_temp.esperar('la cartera no escribió marcas ni eventos', '9/0',
    (select count(*)::text from crm.lead_potencial where lead_id in (select id from lds)) || '/' ||
    (select count(*)::text from crm.lead_potencial_eventos where lead_id in (select id from lds)));

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

### supabase/scripts/test-rls.mjs — bloque nuevo `testPotencialFiltro` (NOT RUN)
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
  const ROLES = ['vend1', 'vend3', 'sup1', 'sup1Nested', 'sup2', 'gerencia', 'coordinador', 'directorio'];
  const NIVELES = ['estrella', 'tibio', 'frio'];
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
    for (const clave of ROLES) {
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
    }
    // A mano, lo que el fixture garantiza.
    const idsDe = async (clave, nivel) => ((await cartera(sessions[clave].client, { p_potencial: nivel })).data?.items ?? []).map((l) => l.id);
    check((await idsDe('vend1', 'estrella')).join(',') === idDe('juan'), 'potencial filtro vend1 con estrella: solo juan (ana es de otro equipo)');
    check((await idsDe('vend3', 'estrella')).join(',') === idDe('ana'), 'potencial filtro vend3 con estrella: solo ana');
    check((await idsDe('vend1', 'frio')).length === 0, 'potencial filtro vend1 con frío: el parqueado de la bandeja de su supervisor (luis) no viaja');
    check((await idsDe('sup1', 'frio')).join(',') === idDe('luis'), 'potencial filtro sup1 con frío: el parqueado de su bandeja (luis)');
    check((await idsDe('sup2', 'tibio')).length === 0, 'potencial filtro sup2 con tibio: maría es de otro equipo');
    check((await idsDe('gerencia', 'estrella')).sort().join(',') === [idDe('juan'), idDe('ana')].sort().join(','),
      'potencial filtro gerencia con estrella: juan y ana');
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
