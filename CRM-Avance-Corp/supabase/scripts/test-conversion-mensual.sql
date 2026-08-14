-- ============================================================================
-- Oráculo transaccional de la CONVERSIÓN MENSUAL PONDERADA
-- Migración A: 20260811154434_crm_conversion_mensual_ponderada.sql
-- Migración C: 20260811190310_crm_ledger_cierres_integros.sql      (CONV-19/20)
-- Migración D: 20260811190324_crm_origen_inmutable.sql             (CONV-22)
-- Migración F: 20260811210049_crm_alta_manual_origen_restringido.sql (CONV-23)
-- ============================================================================
-- Cómo se corre (sobre el branch de Supabase, DESPUÉS de aplicar las CUATRO
-- migraciones y de `npm run seed:demo` — el seed va ANTES que las migraciones
-- en el ciclo del branch; este oráculo va después de todo):
--
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/scripts/test-conversion-mensual.sql
--
-- ⚠️ LA CONEXIÓN TIENE QUE SER EL DUEÑO de `crm.equipo`, `crm.leads` y
-- `crm.lead_asignaciones` (en este proyecto, `postgres`: verificado por
-- `pg_class.relowner` el 2026-08-11). Este fichero apaga y reenciende triggers
-- con `alter table ... disable/enable trigger user` en cuatro sitios (secciones
-- 1, 3, 4 y 7): sin eso no hay forma de retro-fechar un episodio ni de escribir
-- en el ledger con el guard dormido, que es media suite.
-- NO se usa `session_replication_role`: es un GUC de contexto `superuser`, el
-- rol `postgres` de Supabase es `rolsuper = false` y NO puede ponerlo —
-- comprobado EN VIVO contra el canal real el 2026-08-11 (`permission denied to
-- set parameter`), no leyendo documentación. ⚠️ Eso implica que los oráculos
-- viejos de esta carpeta que sí lo usan (`test-metricas-agenda` y compañía)
-- están sujetos a la MISMA mina y deben migrar a este idioma cuando se retoquen.
-- `alter table` es ADEMÁS mejor aquí: es DDL transaccional (el `rollback` final
-- lo deshace incluso si el fichero muere a mitad, así que no puede quedar un
-- trigger apagado colgando), y deja vivas las FK, que `replica` apagaba.
-- `test-usuarios-jerarquia`), todos documentados en verde sobre branch en
-- MIGRACIONES.md. Para que la equivocación se cace en el primer segundo y con
-- nombre y apellidos, CONV-00a comprueba el privilegio ANTES de sembrar: sin
-- ese caso, el fichero moría a mitad de la sección 1 con un
-- «permission denied to set parameter» crudo, sin código CONV-xx, con la
-- transacción ya abortada y cero aserciones ejecutadas.
--
-- Éxito = una sola fila con el token CONVERSION_MENSUAL_OK. Cualquier aserción
-- fallida lanza `raise exception` con su código CONV-xx, el valor ESPERADO y el
-- OBTENIDO, y el token no llega a imprimirse. Todo revierte: el fichero termina
-- en `rollback` y no deja ni una fila.
--
-- POR QUÉ EXISTE (y qué NO cubre el postflight de la migración)
-- -------------------------------------------------------------
-- El postflight de la migración solo puede ejercitar el núcleo `language sql`.
-- El `with` de `crm.conversion_mensual_fn` es plpgsql: sus sentencias no se
-- analizan hasta que CORREN, así que un nombre de columna mal escrito ahí dentro
-- aplica limpio y se descubre en producción. Este fichero es la única red que
-- ejecuta la RPC de verdad, con sesión y con datos, y el único sitio donde la
-- ARITMÉTICA de la definición (Tabla 3 del plan) se contrasta contra números
-- calculados a mano. También es el único que ejercita el CONTRATO DE DENEGACIÓN
-- con sesión válida y rol denegado (CONV-17): el postflight solo puede probar el
-- caso sin sesión, y `test-rls.mjs` no tiene hoy ni un caso de esta RPC.
--
-- CÓMO SE SIEMBRA (y por qué así)
-- --------------------------------
-- 1. El ledger se escribe por su CAMINO REAL. `crm.lead_asignaciones` no se
--    inserta a mano en ningún sitio de este fichero: cada episodio nace y muere
--    por `private.trg_leads_asignaciones`, que es el único con
--    `crm.ledger_writer = on` y `pg_trigger_depth() >= 2`. Un fixture insertado
--    a pelo probaría una tabla, no la métrica.
-- 2. El RELOJ sí se mueve a mano. `asignado_en` lo sella el trigger con
--    `new.creado_en`, y `creado_en` lo pisa `trg_leads_guard_tenencia` con
--    `statement_timestamp()`: por diseño NO existe forma de fabricar un episodio
--    del mes pasado por la vía normal. Los episodios de arrastre se retro-fechan
--    con un UPDATE tras `alter table crm.lead_asignaciones disable trigger
--    user`, que duerme SOLO los triggers de usuario de esa tabla (incluido
--    `trg_lead_asignaciones_00_inmutables`) y deja vivos los CHECK, el UNIQUE,
--    el EXCLUDE **y las FOREIGN KEY** — la red completa sigue vigilando, y todo
--    referente (el `insert into crm.equipo` de la sección 1) tiene que existir
--    de verdad, no por confianza.
--    ⚠️ El `disable` dura hasta su `enable trigger user` EXPLÍCITO — los de las
--    secciones 1, 3, 4 y 7 no son cosméticos: borrarlos dejaría corriendo con
--    los triggers dormidos todo lo que viene después —sin ledger, sin sello de
--    descarte y sin proyección de tenencia—. La diferencia con el mundo del GUC:
--    ahora CONV-99 mira `tgenabled`, que es EXACTAMENTE el estado que estos
--    `alter` mueven, así que un `enable` olvidado SÍ hace saltar CONV-99. Y si
--    el fichero muere a mitad, el `rollback` de la transacción única deshace el
--    `disable` (es DDL transaccional): no puede quedar nada apagado. El de la
--    sección 7 es el único que duerme los triggers para PROBAR algo y no para
--    sembrar: ahí el guard se quita a propósito, porque lo que se mide es lo que
--    aguanta SIN él.
-- 3. Ninguna constante depende del reloj ni del estado de la base. El mes se
--    calcula (`pg_temp.conv_mes()`), el nombre del mes se compara contra un
--    array PROPIO del test —no contra `private.etiqueta_mes_es`, que es la
--    implementación— y el SUELO HISTÓRICO se lee de la base y de él se derivan
--    los meses de CONV-11 y CONV-11b. En producción hoy no hay una sola fila con
--    `aproximado = true`, así que aseverar `divisor_aproximado = 0` no probaría
--    nada: el fixture SIEMBRA una (CONV-16b) y exige que la cuente.
--    Tampoco es constante el RECUENTO de casos: cada aserción se registra a sí
--    misma en `pg_temp.conv_casos` y el token final imprime lo que de verdad
--    corrió. Un literal («19 casos») sigue diciendo 19 el día que alguien borra
--    un bloque `do $test$` entero, que es justo el día en que hay que enterarse.
--    ⚠️ Pero IMPRIMIR el recuento no es ASEVERARLO, y durante un ciclo entero
--    esa distinción se pasó por alto: la única comprobación era `v_casos = 0`,
--    así que borrar veinte de los veintiún bloques dejaba el token en verde
--    diciendo «casos: 1» — el mismo fallo mudo del literal, ahora con la cifra
--    correcta de lo poco que corrió. Por eso el inventario esperado está
--    DECLARADO en `pg_temp.conv_codigos_esperados()` (sección 0) y CONV-99 lo
--    compara elemento a elemento, nombrando los que FALTAN y los que SOBRAN.
--    Añadir un caso nuevo obliga a añadir su código ahí: es el punto.
-- 4. Los dos AGUJEROS del ledger se prueban contra el ALMACENAMIENTO, no contra
--    el trigger: la sección 7 escribe a pelo con los triggers de usuario del
--    ledger DORMIDOS (`disable trigger user`) y exige que la base rechace igual.
--    Un CHECK y un índice sobreviven a un `disable trigger`, a un backfill
--    privilegiado y a cualquier GUC; el código no. Y cada rechazo va con su
--    CONTROL POSITIVO: sin él, «fue rechazado» también puede significar «esa
--    fila no entra por cualquier otra razón».
-- 5. Todas las cifras se leen bajo la identidad del SUPERVISOR del fixture. Su
--    ámbito es su subárbol, así que el payload contiene EXACTAMENTE a las 17
--    personas de este fichero y ni una del seed de demo: por eso se pueden
--    aseverar totales absolutos sin volverse frágil. Los otros dos alcances
--    (CONV-18) se piden con la identidad de ANA y la de GERENCIA, y el global se
--    asevera con `>=` justamente porque ahí sí entra el seed.
--
-- EL REPARTO (uuid `40000000-0000-4000-8000-0000000000NN`)
-- ---------------------------------------------------------
--   01 SUP  supervisor de los 17                    · ámbito de casi todo el test
--   02 A    recibe 2: uno lo TRASPASA a B, otro lo suelta a la bandeja · CONV-01
--   03 B    recibe por TRASPASO el lead de A y lo cierra · CONV-01
--   04 IDA  recibe, cede y recupera el MISMO lead   · CONV-02
--   05 VUE  el intermedio del A→B→A                 · CONV-02
--   06 PRO  2 del mes + 1 arrastrado que cierra     · CONV-03 (y sus leads 1004
--                                                     y 1005 son los sujetos de
--                                                     CONV-22: los dos con
--                                                     episodio ABIERTO)
--   07 ANA  90 no referidos + 20 referidos, 16 y 12 · CONV-04 (canónico) y CONV-18a
--   08 REF  solo 8 referidos, cierra 2              · CONV-04b
--   09 DES  1 recibido y descartado CON dueño       · CONV-05 (y su lead 1301 es
--                                                     el sujeto de CONV-20c/20d)
--   10 BOR  1 recibido y soft-borrado               · CONV-07
--   11 ARR  0 recibidos, 4 cierres arrastrados      · CONV-08 (3 del mes pasado
--                                                     + 1 de hace 13 meses)
--   12 FLO  2 recibidos, 4 cierres → 200 %          · CONV-09
--   13 M1   cierra y DESPUÉS el lead se reasigna    · CONV-10 (y su lead 1331 es
--                                                     el sujeto de CONV-20a/20b/20e)
--   14 M2   recibe ese lead ya convertido           · CONV-10 (y presta su
--                                                     identidad al segundo cierre
--                                                     de CONV-20e)
--   15 FRA  10 recibidos, cierra 3 referidos        · CONV-12 (0,15 × 3)
--   16 SEP  su cierre cae fuera de la ventana       · CONV-14
--   17 APR  su episodio es `aproximado`             · CONV-16b
--   18 FUE  vendedor FUERA del roster, con trabajo  · CONV-13
--   19 CLI  perfil cliente (destino de perfil_id)   · CONV-17 (ajeno al CRM)
--   20 GER  gerencia: actor de las altas y los repartos · CONV-18b, y en
--                                                     CONV-22c el actor DENEGADO
--   21 COO  coordinador: descarta el lead sin dueño · CONV-06 y CONV-17
--   22 BORDE  8 leads clavados en las CUATRO fronteras del mes · CONV-21
--
-- Los leads usan el mismo prefijo desde el 1001 (`pg_temp.conv_lead`), y los
-- teléfonos la banda `+51940xxxxxx`, que no colisiona con el seed ni con prod.
--
-- CUADRO ESPERADO DEL MES EN CURSO, bajo el ámbito de SUP (17 del roster)
-- ----------------------------------------------------------------------
--   divisor 115 (113 por `ingreso` + 2 por `reasignado`) · cierres 29 + 17 ·
--   de ellos 9 de ARRASTRE · referidos recibidos 31 · numerador 31,55 ·
--   conversión 27,43 % (de los que 2,22 puntos los ponen los referidos) ·
--   fuera de roster: 1 analista, divisor 2, 1 cierre
--
--   De dónde salen esos 115 (ojo: este 112 es el DIVISOR de la versión anterior
--   del fixture, no tiene nada que ver con el 112 del desglose por motivo que se
--   corrige más abajo): 112 del cuadro anterior, +1 por el TRASPASO real de
--   CONV-01 (el lead 1001 le pesa a A —que lo recibió— y a B —que lo recibió por
--   traspaso—: dos filas del divisor para UN lead, que es exactamente lo que la
--   regla dice y lo que el fixture viejo nunca ejecutó) y +2 por las dos
--   fronteras INTERIORES de CONV-21. Los 29 cierres son 27 + los 2 de CONV-21
--   que caen dentro de la ventana.
--
--   ⚠️ El reparto 113/2 entre `ingreso` y `reasignado` NO es 112/3, que es lo
--   que decía este cuadro hasta el 2026-08-11 y lo que aseveraba CONV-02. El
--   desglose se queda con el motivo del PRIMER episodio del mes
--   (`(array_agg(la.motivo_apertura order by la.asignado_en ASC))[1]`,
--   20260811154434:622-623), no con el del último, y catorce líneas de
--   comentario de esa misma migración explican por qué `desc` era un bug: con
--   `desc`, cien leads que entran por `ingreso` el día 1 y se reactivan el día 2
--   salían como `{"reactivado": 100}` y el pico de la carga masiva —lo único que
--   este desglose existe para hacer visible— quedaba escondido. Quien se lleva
--   la diferencia es IDA (perfil 04): tiene DOS episodios del lead 1003 dentro
--   del mes (el `ingreso` del alta y el `reasignado` de la vuelta) y cuenta como
--   `ingreso`. Los `reasignado` reales son solo dos: el de B por el traspaso del
--   1001 y el de VUELTA por el 1003.
--
-- LOS CÓDIGOS NUEVOS DE ESTE CICLO
-- --------------------------------
--   CONV-19  el CIERRE SIN FECHA. `resultado = 'convertido'` con `resultado_en`
--            NULL entraba porque el CHECK trivaluado da NULL y un CHECK solo
--            rechaza en FALSE. Ese cierre era INVISIBLE para el numerador
--            (que filtra por `resultado_en`): 0 % donde había un 100 %.
--   CONV-20  el CIERRE CONTADO DOS VECES. Dos episodios `convertido` del mismo
--            lead pasan el EXCLUDE si son ADYACENTES o si uno dura cero, y el
--            numerador los cuenta con `count(*)`: 200 % con divisor 1. Incluye
--            el caso 20e, que es el único que fija la FORMA de la clave.
--   CONV-21  las CUATRO fronteras del mes en hora de Lima, por el divisor
--            (`asignado_en`) y por el numerador (`resultado_en`).
--   CONV-22  el sello del ORIGEN, tal y como lo despliega la migración D REAL
--            (`20260811190324_crm_origen_inmutable.sql`): mover el origen aborta
--            con `P0409` para CUALQUIERA —incluida Gerencia—, reenviar el mismo
--            valor pasa, y la ÚNICA vía de corrección es la válvula
--            `crm.op_privilegiada`, que mueve la FICHA y NO propaga al snapshot.
--            ⚠️ Estos cuatro casos estuvieron escritos contra la migración
--            DESCARTADA `20260811164017_crm_origen_inmutable_correccion_gerencia`
--            (ventana de 24 h para Gerencia + carve-out del ledger que propagaba
--            la corrección al snapshot). Miguel la aparcó el 2026-08-11 y los dos
--            diseños son MUTUAMENTE EXCLUYENTES: los preflights 0.2/0.3/0.4 de la
--            D abortan si la 164017 llegó a aplicarse, así que no existe estado
--            de la base en que la versión vieja de esta sección pudiera pasar.
--            El fichero 164017 hay que BORRARLO del árbol antes de crear el
--            branch (punto 1 de la nota de aplicación de la D).
-- ============================================================================

begin;

set local statement_timeout = '300s';
set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Utillería efímera (pg_temp: nace y muere con esta transacción)
-- ---------------------------------------------------------------------------
-- `conv_num` / `conv_txt` existen para que NINGUNA aserción pueda escribirse sin
-- decir el esperado y el obtenido. Un oráculo que solo dice «CONV-04 falló»
-- obliga a depurar a ciegas y es la razón por la que estos ciclos se alargan.
--
-- REGISTRO DE CASOS. Cada aserción se apunta a sí misma aquí, y el token final
-- imprime este recuento en vez de un literal. Un literal es una promesa que la
-- suite no sostiene: el día que alguien borre un bloque `do $test$`, el número
-- seguiría diciendo lo mismo. Los cuatro comparadores registran solos; los
-- bloques que solo hacen `raise exception` (CONV-07a, CONV-13a, CONV-14a,
-- CONV-15, CONV-17…) llaman a `conv_caso` a mano en su primera línea.
-- El `grant` no es adorno: la fase B corre bajo el rol `authenticated` y sin él
-- el registro moriría con «permiso denegado» en la primera aserción del payload.
create table pg_temp.conv_casos (
  codigo     text primary key,
  aserciones integer not null default 0
);
grant select, insert, update on table pg_temp.conv_casos to public;

create function pg_temp.conv_caso(p_codigo text) returns void
  language plpgsql volatile as
$$
begin
  insert into pg_temp.conv_casos as cc (codigo, aserciones)
  values (p_codigo, 1)
  on conflict (codigo) do update set aserciones = cc.aserciones + 1;
end;
$$;

-- EL INVENTARIO DECLARADO. Es la lista COMPLETA de códigos que una corrida sana
-- tiene que haber registrado, y CONV-99 la compara elemento a elemento contra lo
-- que de verdad corrió. Sin esto, el recuento del token era un contador que no
-- podía fallar: la única aserción sobre él era `v_casos = 0`, así que borrar
-- veinte de los veintiún bloques `do $test$` dejaba el token en verde diciendo
-- «casos: 1». Añadir un caso obliga a añadir su código aquí, y eso es el punto:
-- la lista es la parte del fichero que un diff enseña sin tener que leer 2.000
-- líneas.
create function pg_temp.conv_codigos_esperados() returns text[]
  language sql immutable as
$$ select array[
  'CONV-00',  'CONV-00a', 'CONV-00b',
  'CONV-01',  'CONV-01a',
  'CONV-02',  'CONV-03',  'CONV-04',  'CONV-04b', 'CONV-05',
  'CONV-06a', 'CONV-07',  'CONV-07a', 'CONV-08',  'CONV-09',
  'CONV-10a', 'CONV-10b', 'CONV-11',  'CONV-11b', 'CONV-12',
  'CONV-13a', 'CONV-13b', 'CONV-13c', 'CONV-14a', 'CONV-14b',
  'CONV-15',  'CONV-16',  'CONV-16b',
  'CONV-17a', 'CONV-17b', 'CONV-17c', 'CONV-18a', 'CONV-18b',
  'CONV-19a', 'CONV-19b', 'CONV-19c',
  'CONV-20',  'CONV-20a', 'CONV-20b', 'CONV-20c', 'CONV-20d', 'CONV-20e',
  'CONV-21a', 'CONV-21b',
  'CONV-22a', 'CONV-22b', 'CONV-22c', 'CONV-22d',
  'CONV-23a', 'CONV-23b', 'CONV-23c', 'CONV-23d',
  'CONV-24a', 'CONV-24b', 'CONV-24c',
  'CONV-99'
]::text[] $$;

create function pg_temp.conv_lead(p_n integer) returns uuid
  language sql immutable as
$$ select ('40000000-0000-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid $$;

create function pg_temp.conv_tel(p_n integer) returns text
  language sql immutable as
$$ select '9' || lpad((40000000 + p_n)::text, 8, '0') $$;

create function pg_temp.conv_mes() returns date
  language sql stable as
$$ select date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date $$;

create function pg_temp.conv_mes_anterior() returns date
  language sql stable as
$$ select (date_trunc('month', pg_catalog.now() at time zone 'America/Lima')
           - interval '1 month')::date $$;

-- Día 16 del mes anterior, 00:00 Lima. Instante sin ambigüedad de zona: la
-- métrica fecha por hora de Lima y un fixture a las 00:00 UTC del día 1 caería
-- en el mes anterior.
create function pg_temp.conv_instante_anterior() returns timestamptz
  language sql stable as
$$ select (date_trunc('month', pg_catalog.now() at time zone 'America/Lima')
           - interval '1 month' + interval '15 days') at time zone 'America/Lima' $$;

-- Día 16 de hace TRECE meses. Es el único instante del fixture que cae fuera de
-- la ventana de 11 meses de `procedencia` y por tanto el único que puede hacer
-- aparecer el cubo `anteriores` (CONV-08).
create function pg_temp.conv_instante_antiguo() returns timestamptz
  language sql stable as
$$ select (date_trunc('month', pg_catalog.now() at time zone 'America/Lima')
           - interval '13 months' + interval '15 days') at time zone 'America/Lima' $$;

-- LAS DOS FRONTERAS DEL MES, calculadas igual que las calcula la RPC
-- (20260811154434:644-645): `v_ini = p_periodo at time zone 'America/Lima'` y
-- `v_fin = (p_periodo + 1 mes) at time zone 'America/Lima'`, ventana SEMIABIERTA
-- [ini, fin). Todo el fixture de arriba vive cerca del mediodía del día 16, o
-- sea a quince días de cualquiera de los dos bordes: el sitio donde un `<=` por
-- un `<`, un `at time zone` olvidado o un `date_trunc` en UTC no se notan. Lima
-- no tiene horario de verano (UTC-5 fijo), así que estos cuatro instantes son
-- exactos y no dependen del mes en que se corra.
create function pg_temp.conv_ini() returns timestamptz
  language sql stable as
$$ select (pg_temp.conv_mes())::timestamp at time zone 'America/Lima' $$;

create function pg_temp.conv_fin() returns timestamptz
  language sql stable as
$$ select (pg_temp.conv_mes() + interval '1 month')::timestamp at time zone 'America/Lima' $$;

-- Intento de escritura DESHECHO. Devuelve 'ACEPTADO' o el SQLSTATE del rechazo,
-- y en los dos casos deja la base como estaba: el `raise` deshace la
-- subtransacción del bloque, así que hasta el caso que PASA se desanda solo.
-- Existe para que un caso negativo y su control positivo se escriban con la
-- misma frase — un rechazo sin control positivo al lado no distingue «la base
-- defiende la regla» de «esa fila no entraba ni bien formada».
create function pg_temp.conv_intento(p_sql text) returns text
  language plpgsql volatile as
$$
begin
  begin
    execute p_sql;
    raise exception 'CONV_DESHACER';
  exception
    when others then
      if sqlerrm = 'CONV_DESHACER' then
        return 'ACEPTADO';
      end if;
      return sqlstate;
  end;
end;
$$;

create function pg_temp.conv_fila(p_codigo text, p_payload jsonb, p_vendedor uuid)
returns jsonb language plpgsql volatile as
$$
declare
  v_fila jsonb;
begin
  perform pg_temp.conv_caso(p_codigo);

  select el.value into v_fila
  from jsonb_array_elements(p_payload -> 'responsables') el
  where (el.value ->> 'vendedor_id')::uuid = p_vendedor;

  if v_fila is null then
    raise exception '% · responsables: ESPERADO una fila para % · OBTENIDO ninguna (el array trae %)',
      p_codigo, p_vendedor, jsonb_array_length(p_payload -> 'responsables');
  end if;
  return v_fila;
end;
$$;

-- Comparación NUMÉRICA exacta (`numeric` es decimal exacto: 0,450 = 0,45 es
-- cierto, y 0,45000001 es falso). Nunca comparar estos campos como texto: el
-- numerador sale con la escala de la multiplicación (0,150 × 3 = 0,450) y un
-- `= '0.45'` fallaría por un cero que no significa nada.
create function pg_temp.conv_num(p_codigo text, p_campo text,
                                 p_esperado numeric, p_obtenido numeric)
returns void language plpgsql volatile as
$$
begin
  perform pg_temp.conv_caso(p_codigo);
  if p_esperado is distinct from p_obtenido then
    raise exception '% · %: ESPERADO % · OBTENIDO %',
      p_codigo, p_campo,
      coalesce(p_esperado::text, '<null>'), coalesce(p_obtenido::text, '<null>');
  end if;
end;
$$;

-- Variante para cotas. El alcance GLOBAL incluye al roster del seed de demo, así
-- que ahí un absoluto sería frágil y un `>=` sigue siendo falsable: si el ámbito
-- se recortara de más, el número caería por debajo de lo que el fixture aporta.
create function pg_temp.conv_min(p_codigo text, p_campo text,
                                 p_minimo numeric, p_obtenido numeric)
returns void language plpgsql volatile as
$$
begin
  perform pg_temp.conv_caso(p_codigo);
  if p_obtenido is null or p_obtenido < p_minimo then
    raise exception '% · %: ESPERADO >= % · OBTENIDO %',
      p_codigo, p_campo,
      p_minimo::text, coalesce(p_obtenido::text, '<null>');
  end if;
end;
$$;

create function pg_temp.conv_txt(p_codigo text, p_campo text,
                                 p_esperado text, p_obtenido text)
returns void language plpgsql volatile as
$$
begin
  perform pg_temp.conv_caso(p_codigo);
  if p_esperado is distinct from p_obtenido then
    raise exception '% · %: ESPERADO % · OBTENIDO %',
      p_codigo, p_campo,
      coalesce(p_esperado, '<null>'), coalesce(p_obtenido, '<null>');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- CONV-00a · PRECONDICIÓN: esta conexión puede dormir los triggers
-- ---------------------------------------------------------------------------
-- El fichero apaga triggers con `alter table ... disable trigger user` en cuatro
-- sitios, y eso exige ser DUEÑO de las tres tablas. En este proyecto el dueño es
-- `postgres` — el mismo rol del canal MCP y de `$SUPABASE_DB_URL` — así que la
-- conexión normal sirve y no hace falta ningún superusuario.
-- (La versión anterior de este caso exigía el privilegio SET sobre
-- `session_replication_role`, que `postgres` NO tiene en Supabase — comprobado
-- en vivo el 2026-08-11 con un `permission denied`. Ese camino queda prohibido
-- aquí: cualquier conexión de este proyecto moriría a mitad de la sección 1,
-- sin código CONV-xx y con cero aserciones ejecutadas.)
--
-- Sin este caso, una conexión equivocada naufraga a mitad de fichero con un
-- error crudo; con él, el fallo es una frase que dice exactamente qué falta.
do $test$
declare
  v_sin_dueno text;
begin
  perform pg_temp.conv_caso('CONV-00a');
  select string_agg(c.relname, ', ' order by c.relname)
    into v_sin_dueno
  from pg_catalog.pg_class c
  where c.oid in ('crm.equipo'::regclass, 'crm.leads'::regclass,
                  'crm.lead_asignaciones'::regclass)
    and not pg_catalog.pg_has_role(current_user, c.relowner, 'USAGE');
  if v_sin_dueno is not null then
    raise exception 'CONV-00a · duenno de las tablas del fixture: ESPERADO % duenno (o miembro del duenno) de equipo, leads y lead_asignaciones · OBTENIDO sin dominio sobre: %. Sin eso, los alter table disable trigger user de las secciones 1, 3, 4 y 7 fallan.',
      current_user, v_sin_dueno;
  end if;
end;
$test$;

-- ---------------------------------------------------------------------------
-- CONV-00b · PRECONDICIÓN: se empieza con los triggers en su sitio
-- ---------------------------------------------------------------------------
-- Sin esta foto de partida, la comprobación gemela del final (CONV-99) no
-- distingue «este fichero no apagó nada» de «ya venía apagado»: las dos cosas
-- salen en verde. Con las dos, el par es un DIFERENCIAL y sí puede fallar.
-- ⚠️ Deliberadamente NO se mira `crm.equipo`. El ciclo del gate suspende
-- `trg_equipo_validar_usuarios_jerarquia` durante seed+corrida (deuda anotada en
-- MIGRACIONES.md y reactivación explícita antes del merge en la nota de
-- aplicación de la migración): aseverarlo aquí haría fallar el oráculo justo en
-- el único entorno donde se corre.
do $test$
declare
  v_apagados text;
begin
  select string_agg(t.tgrelid::regclass::text || '.' || t.tgname, ', ' order by t.tgname)
    into v_apagados
  from pg_catalog.pg_trigger t
  where t.tgrelid in ('crm.leads'::regclass, 'crm.lead_asignaciones'::regclass)
    and not t.tgisinternal
    and t.tgenabled = 'D';
  if v_apagados is not null then
    raise exception 'CONV-00b · triggers deshabilitados ANTES de sembrar: ESPERADO ninguno · OBTENIDO %', v_apagados;
  end if;

  perform pg_temp.conv_txt('CONV-00b', 'session_replication_role al empezar',
    'origin', current_setting('session_replication_role'));
end;
$test$;

-- ---------------------------------------------------------------------------
-- 1. Personas
-- ---------------------------------------------------------------------------
insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
select
  pg_temp.conv_lead(n), 'authenticated', 'authenticated',
  'conv-' || n || '@test.invalid', now(), '{}', '{}', now(), now()
from generate_series(1, 22) n;

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  (pg_temp.conv_lead(1),  'ORACULO CONV SUPERVISOR',   'conv-1@test.invalid',  'comercial',  true),
  (pg_temp.conv_lead(2),  'ORACULO CONV A',            'conv-2@test.invalid',  'comercial',  true),
  (pg_temp.conv_lead(3),  'ORACULO CONV B',            'conv-3@test.invalid',  'comercial',  true),
  (pg_temp.conv_lead(4),  'ORACULO CONV IDA',          'conv-4@test.invalid',  'comercial',  true),
  (pg_temp.conv_lead(5),  'ORACULO CONV VUELTA',       'conv-5@test.invalid',  'comercial',  true),
  (pg_temp.conv_lead(6),  'ORACULO CONV PROCEDENCIA',  'conv-6@test.invalid',  'comercial',  true),
  (pg_temp.conv_lead(7),  'ORACULO CONV ANA',          'conv-7@test.invalid',  'comercial',  true),
  (pg_temp.conv_lead(8),  'ORACULO CONV SOLO REF',     'conv-8@test.invalid',  'comercial',  true),
  (pg_temp.conv_lead(9),  'ORACULO CONV DESCARTA',     'conv-9@test.invalid',  'comercial',  true),
  (pg_temp.conv_lead(10), 'ORACULO CONV BORRADO',      'conv-10@test.invalid', 'comercial',  true),
  (pg_temp.conv_lead(11), 'ORACULO CONV ARRASTRE',     'conv-11@test.invalid', 'comercial',  true),
  (pg_temp.conv_lead(12), 'ORACULO CONV MES FLOJO',    'conv-12@test.invalid', 'comercial',  true),
  (pg_temp.conv_lead(13), 'ORACULO CONV CIERRA',       'conv-13@test.invalid', 'comercial',  true),
  (pg_temp.conv_lead(14), 'ORACULO CONV RECIBE LUEGO', 'conv-14@test.invalid', 'comercial',  true),
  (pg_temp.conv_lead(15), 'ORACULO CONV FRACCION',     'conv-15@test.invalid', 'comercial',  true),
  (pg_temp.conv_lead(16), 'ORACULO CONV SIN EPISODIO', 'conv-16@test.invalid', 'comercial',  true),
  (pg_temp.conv_lead(17), 'ORACULO CONV APROXIMADO',   'conv-17@test.invalid', 'comercial',  true),
  (pg_temp.conv_lead(18), 'ORACULO CONV FUERA ROSTER', 'conv-18@test.invalid', 'comercial',  true),
  (pg_temp.conv_lead(19), 'ORACULO CONV CLIENTE',      'conv-19@test.invalid', 'cliente',    true),
  (pg_temp.conv_lead(20), 'ORACULO CONV GERENCIA',     'conv-20@test.invalid', 'directorio', true),
  (pg_temp.conv_lead(21), 'ORACULO CONV COORDINADOR',  'conv-21@test.invalid', 'comercial',  true),
  (pg_temp.conv_lead(22), 'ORACULO CONV BORDE MES',    'conv-22@test.invalid', 'comercial',  true);

-- `disable trigger user` SOLO para la jerarquía: FUE (18) cuelga de un VENDEDOR
-- a propósito, y `trg_equipo_validar_usuarios_jerarquia` lo rechazaría. Es
-- exactamente la forma en que hoy se sale del roster en producción (roster 16 ·
-- vendedores con rol efectivo 17), y el caso que la migración cubre con
-- `motivo_no_medible`.
-- ¿Por qué no `session_replication_role = replica`? Porque el rol `postgres` de
-- este proyecto NO puede ponerlo — contexto superuser, `pg_parameter_acl` vacía;
-- comprobado EN VIVO contra el canal real: `permission denied to set parameter`.
-- El recambio es ADEMÁS más estricto: `alter table ... disable trigger user` es
-- DDL transaccional (el `rollback` final lo deshace incluso si el fichero muere
-- a mitad), apaga solo los triggers de usuario de ESTA tabla, y deja vivas las
-- FK — los 22 perfiles de arriba ya están insertados, así que los referentes
-- existen y las FK pasan de verdad, no por omisión.
alter table crm.equipo disable trigger user;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  (pg_temp.conv_lead(1),  'supervisor',  null,                   true),
  (pg_temp.conv_lead(2),  'vendedor',    pg_temp.conv_lead(1),   true),
  (pg_temp.conv_lead(3),  'vendedor',    pg_temp.conv_lead(1),   true),
  (pg_temp.conv_lead(4),  'vendedor',    pg_temp.conv_lead(1),   true),
  (pg_temp.conv_lead(5),  'vendedor',    pg_temp.conv_lead(1),   true),
  (pg_temp.conv_lead(6),  'vendedor',    pg_temp.conv_lead(1),   true),
  (pg_temp.conv_lead(7),  'vendedor',    pg_temp.conv_lead(1),   true),
  (pg_temp.conv_lead(8),  'vendedor',    pg_temp.conv_lead(1),   true),
  (pg_temp.conv_lead(9),  'vendedor',    pg_temp.conv_lead(1),   true),
  (pg_temp.conv_lead(10), 'vendedor',    pg_temp.conv_lead(1),   true),
  (pg_temp.conv_lead(11), 'vendedor',    pg_temp.conv_lead(1),   true),
  (pg_temp.conv_lead(12), 'vendedor',    pg_temp.conv_lead(1),   true),
  (pg_temp.conv_lead(13), 'vendedor',    pg_temp.conv_lead(1),   true),
  (pg_temp.conv_lead(14), 'vendedor',    pg_temp.conv_lead(1),   true),
  (pg_temp.conv_lead(15), 'vendedor',    pg_temp.conv_lead(1),   true),
  (pg_temp.conv_lead(16), 'vendedor',    pg_temp.conv_lead(1),   true),
  (pg_temp.conv_lead(17), 'vendedor',    pg_temp.conv_lead(1),   true),
  -- BORDE: vendedor normal del roster. Toda su cartera está clavada en las
  -- cuatro fronteras del mes (CONV-21) y por eso su fila es la única que se
  -- movería si la ventana dejara de ser [ini, fin) en hora de Lima.
  (pg_temp.conv_lead(22), 'vendedor',    pg_temp.conv_lead(1),   true),
  -- FUE: rol efectivo de vendedor, pero su «supervisor» es un vendedor.
  (pg_temp.conv_lead(18), 'vendedor',    pg_temp.conv_lead(2),   true),
  (pg_temp.conv_lead(20), 'gerencia',    null,                   true),
  (pg_temp.conv_lead(21), 'coordinador', null,                   true);
alter table crm.equipo enable trigger user;

-- Gerencia reparte: es el único rol que puede dejar un lead en la cola global
-- (CONV-06) y el actor natural de un alta.
select set_config('request.jwt.claim.sub', pg_temp.conv_lead(20)::text, true);

-- ---------------------------------------------------------------------------
-- 2. Leads. Cada alta con `vendedor_id` abre su episodio por el trigger.
-- ---------------------------------------------------------------------------
insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  categoria_interes, vendedor_id, asignado_supervisor_id, creado_por
)
values
  -- CONV-01. Los DOS nacen en manos de A: el 1001 se TRASPASA a B (que lo
  -- cierra) y el 1002 se suelta a la bandeja del supervisor. Antes el 1002 nacía
  -- ya en manos de B y el traspaso que el caso anuncia no ocurría nunca: dos
  -- leads distintos, cada uno con su dueño de siempre, y el verde no significaba
  -- nada sobre la regla que el caso dice cubrir.
  (pg_temp.conv_lead(1001), 'ORACULO CONV 1001 A TRASPASA A B', pg_temp.conv_tel(1001), 'landing', 'nuevo', 1000, 'PEN', 'nuevo', pg_temp.conv_lead(2), null, pg_temp.conv_lead(20)),
  (pg_temp.conv_lead(1002), 'ORACULO CONV 1002 A SUELTA', pg_temp.conv_tel(1002), 'landing', 'nuevo', 1000, 'PEN', 'nuevo', pg_temp.conv_lead(2), null, pg_temp.conv_lead(20)),
  -- CONV-02: un solo lead que hará IDA → VUELTA → IDA
  (pg_temp.conv_lead(1003), 'ORACULO CONV 1003 IDA VUELTA', pg_temp.conv_tel(1003), 'landing', 'nuevo', 1000, 'PEN', 'nuevo', pg_temp.conv_lead(4), null, pg_temp.conv_lead(20)),
  -- CONV-03: dos del mes (divisor) y uno que se retro-fecha al mes anterior
  (pg_temp.conv_lead(1004), 'ORACULO CONV 1004 PRO MES', pg_temp.conv_tel(1004), 'landing', 'nuevo', 1000, 'PEN', 'nuevo', pg_temp.conv_lead(6), null, pg_temp.conv_lead(20)),
  (pg_temp.conv_lead(1005), 'ORACULO CONV 1005 PRO MES', pg_temp.conv_tel(1005), 'landing', 'nuevo', 1000, 'PEN', 'nuevo', pg_temp.conv_lead(6), null, pg_temp.conv_lead(20)),
  (pg_temp.conv_lead(1006), 'ORACULO CONV 1006 PRO ARRASTRE', pg_temp.conv_tel(1006), 'landing', 'nuevo', 1000, 'PEN', 'nuevo', pg_temp.conv_lead(6), null, pg_temp.conv_lead(20)),
  -- CONV-05 y CONV-07
  (pg_temp.conv_lead(1301), 'ORACULO CONV 1301 DESCARTE CON DUENO', pg_temp.conv_tel(1301), 'landing', 'nuevo', 1000, 'PEN', 'nuevo', pg_temp.conv_lead(9), null, pg_temp.conv_lead(20)),
  (pg_temp.conv_lead(1302), 'ORACULO CONV 1302 SOFT BORRADO', pg_temp.conv_tel(1302), 'landing', 'nuevo', 1000, 'PEN', 'nuevo', pg_temp.conv_lead(10), null, pg_temp.conv_lead(20)),
  -- CONV-10
  (pg_temp.conv_lead(1331), 'ORACULO CONV 1331 CIERRA Y SE MUEVE', pg_temp.conv_tel(1331), 'landing', 'nuevo', 1000, 'PEN', 'nuevo', pg_temp.conv_lead(13), null, pg_temp.conv_lead(20)),
  -- CONV-13: producción de un vendedor fuera del roster
  (pg_temp.conv_lead(1361), 'ORACULO CONV 1361 FUERA ROSTER', pg_temp.conv_tel(1361), 'landing', 'nuevo', 1000, 'PEN', 'nuevo', pg_temp.conv_lead(18), null, pg_temp.conv_lead(20)),
  (pg_temp.conv_lead(1362), 'ORACULO CONV 1362 FUERA ROSTER', pg_temp.conv_tel(1362), 'landing', 'nuevo', 1000, 'PEN', 'nuevo', pg_temp.conv_lead(18), null, pg_temp.conv_lead(20)),
  -- CONV-14: se convertirá y su episodio se empujará al mes anterior
  (pg_temp.conv_lead(1371), 'ORACULO CONV 1371 CIERRE SIN EPISODIO', pg_temp.conv_tel(1371), 'landing', 'nuevo', 1000, 'PEN', 'nuevo', pg_temp.conv_lead(16), null, pg_temp.conv_lead(20)),
  -- CONV-16b: su episodio se marcará `aproximado`
  (pg_temp.conv_lead(1381), 'ORACULO CONV 1381 APROXIMADO', pg_temp.conv_tel(1381), 'landing', 'nuevo', 1000, 'PEN', 'nuevo', pg_temp.conv_lead(17), null, pg_temp.conv_lead(20)),
  -- CONV-06: cola global, sin dueño y sin bandeja. Nunca tendrá episodio.
  (pg_temp.conv_lead(1391), 'ORACULO CONV 1391 COLA GLOBAL', pg_temp.conv_tel(1391), 'landing', 'nuevo', 1000, 'PEN', 'nuevo', null, null, pg_temp.conv_lead(20));

-- CONV-04, canónico: 90 NO referidos.
insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  categoria_interes, vendedor_id, creado_por
)
select
  pg_temp.conv_lead(n), 'ORACULO CONV ANA NR ' || n, pg_temp.conv_tel(n),
  'landing', 'nuevo', 1000, 'PEN', 'nuevo',
  pg_temp.conv_lead(7), pg_temp.conv_lead(20)
from generate_series(1101, 1190) n;

-- CONV-04: 20 REFERIDOS. `creado_por` = ANA para que además se ejercite
-- `referidos.dados_de_alta` (H4), que sale de `crm.leads.creado_por` y NO del
-- snapshot: es el único número del payload no reproducible hacia atrás.
insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  categoria_interes, vendedor_id, creado_por
)
select
  pg_temp.conv_lead(n), 'ORACULO CONV ANA REF ' || n, pg_temp.conv_tel(n),
  'referido', 'nuevo', 1000, 'PEN', 'nuevo',
  pg_temp.conv_lead(7), pg_temp.conv_lead(7)
from generate_series(1191, 1210) n;

-- CONV-04b: 8 referidos y NADA más. Su divisor legítimo es 0.
insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  categoria_interes, vendedor_id, creado_por
)
select
  pg_temp.conv_lead(n), 'ORACULO CONV SOLO REF ' || n, pg_temp.conv_tel(n),
  'referido', 'nuevo', 1000, 'PEN', 'nuevo',
  pg_temp.conv_lead(8), pg_temp.conv_lead(20)
from generate_series(1211, 1218) n;

-- CONV-08: 4 leads que se retro-fechan y se cierran este mes. Los 1311-1313 al
-- mes pasado; el 1314 a hace TRECE meses, que es el único que puede hacer
-- aparecer el cubo `anteriores` de `procedencia`.
insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  categoria_interes, vendedor_id, creado_por
)
select
  pg_temp.conv_lead(n), 'ORACULO CONV ARRASTRE ' || n, pg_temp.conv_tel(n),
  'landing', 'nuevo', 1000, 'PEN', 'nuevo',
  pg_temp.conv_lead(11), pg_temp.conv_lead(20)
from generate_series(1311, 1314) n;

-- CONV-09: 1321-1322 del mes; 1323-1324 se retro-fechan. Los cuatro se cierran.
insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  categoria_interes, vendedor_id, creado_por
)
select
  pg_temp.conv_lead(n), 'ORACULO CONV MES FLOJO ' || n, pg_temp.conv_tel(n),
  'landing', 'nuevo', 1000, 'PEN', 'nuevo',
  pg_temp.conv_lead(12), pg_temp.conv_lead(20)
from generate_series(1321, 1324) n;

-- CONV-12: 10 no referidos (divisor) y 3 referidos que SÍ se cierran.
insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  categoria_interes, vendedor_id, creado_por
)
select
  pg_temp.conv_lead(n), 'ORACULO CONV FRACCION NR ' || n, pg_temp.conv_tel(n),
  'landing', 'nuevo', 1000, 'PEN', 'nuevo',
  pg_temp.conv_lead(15), pg_temp.conv_lead(20)
from generate_series(1341, 1350) n;

insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  categoria_interes, vendedor_id, creado_por
)
select
  pg_temp.conv_lead(n), 'ORACULO CONV FRACCION REF ' || n, pg_temp.conv_tel(n),
  'referido', 'nuevo', 1000, 'PEN', 'nuevo',
  pg_temp.conv_lead(15), pg_temp.conv_lead(20)
from generate_series(1351, 1353) n;

-- CONV-21: los OCHO leads de BORDE. Nacen normales —con episodio abierto por el
-- trigger— y luego se les clava el reloj en las cuatro fronteras del mes: los
-- 1401-1404 por `asignado_en` (divisor) en la sección 3, los 1405-1408 por
-- `resultado_en` (numerador) en la sección 4, después de convertirse.
insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  categoria_interes, vendedor_id, creado_por
)
select
  pg_temp.conv_lead(n), 'ORACULO CONV BORDE ' || n, pg_temp.conv_tel(n),
  'landing', 'nuevo', 1000, 'PEN', 'nuevo',
  pg_temp.conv_lead(22), pg_temp.conv_lead(20)
from generate_series(1401, 1408) n;

-- ---------------------------------------------------------------------------
-- 3. El reloj a mano (I): ocho episodios fuera del mes y cuatro en la frontera
-- ---------------------------------------------------------------------------
-- Se mueven también `sla_global_iniciado_en` y los dos límites del SLA porque
-- tres CHECK vivos los amarran a `asignado_en` (`sla_global_iniciado_en <=
-- asignado_en`, `primera_gestion_limite_en >= asignado_en`, `primer_contacto >=
-- primera_gestion`). Que salten esos CHECK es la prueba de que `disable trigger
-- user` no toca los CHECK: apaga SOLO los triggers de usuario (aquí, el
-- inmutables que congela `asignado_en`); CHECK, UNIQUE, EXCLUDE y FK siguen
-- vivos y vigilando cada UPDATE de este bloque.
alter table crm.lead_asignaciones disable trigger user;
update crm.lead_asignaciones la
set asignado_en                = pg_temp.conv_instante_anterior(),
    sla_global_iniciado_en     = pg_temp.conv_instante_anterior(),
    primera_gestion_limite_en  = pg_temp.conv_instante_anterior() + interval '1 hour',
    primer_contacto_limite_en  = pg_temp.conv_instante_anterior() + interval '2 hours'
where la.lead_id in (
  pg_temp.conv_lead(1006),                                           -- CONV-03
  pg_temp.conv_lead(1311), pg_temp.conv_lead(1312), pg_temp.conv_lead(1313), -- CONV-08
  pg_temp.conv_lead(1323), pg_temp.conv_lead(1324),                  -- CONV-09
  pg_temp.conv_lead(1371)                                            -- CONV-14
);

-- El de hace 13 meses. Va aparte porque su instante es otro y porque es el que
-- pasa a ser el SUELO HISTÓRICO del ledger: CONV-11 y CONV-11b derivan sus dos
-- meses de ese suelo LEÍDO del payload, así que se recolocan solas.
update crm.lead_asignaciones la
set asignado_en                = pg_temp.conv_instante_antiguo(),
    sla_global_iniciado_en     = pg_temp.conv_instante_antiguo(),
    primera_gestion_limite_en  = pg_temp.conv_instante_antiguo() + interval '1 hour',
    primer_contacto_limite_en  = pg_temp.conv_instante_antiguo() + interval '2 hours'
where la.lead_id = pg_temp.conv_lead(1314);                          -- CONV-08

-- CONV-21 (divisor) · LAS DOS FRONTERAS, por los dos lados. El divisor sale de
-- `asignado_en >= v_ini and asignado_en < v_fin`: son cuatro instantes a un
-- segundo unos de otros y cada uno mata una mutación distinta.
--   1401 · v_ini - 1 s  → FUERA (es del mes pasado). Si el `>=` fuera `>`... no
--                         cambiaría nada aquí, pero si la ventana se abriera un
--                         punto antes, este lead entraría y el divisor mentiría.
--   1402 · v_ini exacto → DENTRO. Mata el `>` en vez de `>=`: el primer instante
--                         del mes es del mes.
--   1403 · v_fin - 1 s  → DENTRO. Mata cualquier cierre prematuro de la ventana
--                         (un `< v_fin - 1 day`, un mes de 30 clavado).
--   1404 · v_fin exacto → FUERA. Mata el `<=`: el primer instante del mes que
--                         viene NO es de este mes, y contarlo se lo robaría al
--                         mes siguiente.
-- Se mueven también las tres columnas del SLA porque sus CHECK las amarran a
-- `asignado_en` (ver más arriba). Que 1403 y 1404 caigan en el FUTURO no rompe
-- nada: el ledger no tiene ningún CHECK contra fechas futuras — se comprobó
-- contra el catálogo de producción antes de escribir esto.
update crm.lead_asignaciones la
set asignado_en                = b.instante,
    sla_global_iniciado_en     = b.instante,
    primera_gestion_limite_en  = b.instante + interval '1 hour',
    primer_contacto_limite_en  = b.instante + interval '2 hours'
from (values
  (pg_temp.conv_lead(1401), pg_temp.conv_ini() - interval '1 second'),
  (pg_temp.conv_lead(1402), pg_temp.conv_ini()),
  (pg_temp.conv_lead(1403), pg_temp.conv_fin() - interval '1 second'),
  (pg_temp.conv_lead(1404), pg_temp.conv_fin())
) as b(lead_id, instante)
where la.lead_id = b.lead_id;
alter table crm.lead_asignaciones enable trigger user;

-- ---------------------------------------------------------------------------
-- 4. Los movimientos del mes (todos por la vía real)
-- ---------------------------------------------------------------------------
-- CONV-01a: el TRASPASO de verdad. El MISMO lead pasa de A a B, y B lo cierra
-- más abajo. Un solo `update` del `vendedor_id` dispara las dos escrituras del
-- ledger: cierra el episodio de A como `transferido` (con `analista_destino_id`
-- = B) y abre el de B como `reasignado`. Ese lead pesa 1 en el divisor de A —lo
-- recibió— y 1 en el de B —también lo recibió—, y el cierre es de B: es el caso
-- que separa «contar leads por analista» de «contar leads», y el que el fixture
-- viejo anunciaba en su comentario sin sembrarlo nunca.
update crm.leads
set vendedor_id = pg_temp.conv_lead(3)
where id = pg_temp.conv_lead(1001);

-- CONV-01b: y el otro lead de A se suelta a la bandeja del supervisor. El
-- episodio se cierra como `parqueado`, pero su `asignado_en` sigue en el mes: A
-- lo RECIBIÓ, y soltarlo no lo borra del divisor.
update crm.leads
set vendedor_id = null,
    asignado_supervisor_id = pg_temp.conv_lead(1)
where id = pg_temp.conv_lead(1002);

-- CONV-02: el mismo lead va y vuelve. Dos episodios de IDA, UN solo lead.
update crm.leads set vendedor_id = pg_temp.conv_lead(5) where id = pg_temp.conv_lead(1003);
update crm.leads set vendedor_id = pg_temp.conv_lead(4) where id = pg_temp.conv_lead(1003);

-- CONV-05: descarte CON dueño → el lead sigue pesando en el divisor de DES.
update crm.leads
set etapa = 'descartado', motivo_descarte = 'sin_interes'
where id = pg_temp.conv_lead(1301);

-- CONV-07: soft-delete. La conversión no filtra `activo` (regla de Miguel del
-- 2026-08-10: los leads no se eliminan y le siguen contando al asesor).
update crm.leads set activo = false where id = pg_temp.conv_lead(1302);

-- Cierres del mes. `convertido_en` y el `resultado_en` del ledger comparten
-- statement: ambos caen dentro de la ventana y la sonda no debe verlos.
select set_config('crm.op_privilegiada', 'on', true);

update crm.leads
set etapa = 'convertido',
    perfil_id = pg_temp.conv_lead(19),
    convertido_en = statement_timestamp()
where id in (
  pg_temp.conv_lead(1001),   -- CONV-01  B cierra el lead que RECIBIÓ de A
  pg_temp.conv_lead(1006),   -- CONV-03  arrastre del mes anterior
  pg_temp.conv_lead(1331),   -- CONV-10  lo cierra M1
  pg_temp.conv_lead(1362),   -- CONV-13  producción fuera del roster
  pg_temp.conv_lead(1371)    -- CONV-14  su episodio se empujará al mes anterior
);

-- CONV-21 (numerador): los cuatro cierres de BORDE. Se convierten por la vía
-- real y justo después se les clava `resultado_en` en las cuatro fronteras.
update crm.leads
set etapa = 'convertido',
    perfil_id = pg_temp.conv_lead(19),
    convertido_en = statement_timestamp()
where id in (
  select pg_temp.conv_lead(n) from generate_series(1405, 1408) n
);

update crm.leads
set etapa = 'convertido',
    perfil_id = pg_temp.conv_lead(19),
    convertido_en = statement_timestamp()
where id in (
  select pg_temp.conv_lead(n) from generate_series(1101, 1116) n   -- ANA: 16 no referidos
  union all
  select pg_temp.conv_lead(n) from generate_series(1191, 1202) n   -- ANA: 12 referidos
  union all
  select pg_temp.conv_lead(n) from generate_series(1211, 1212) n   -- REF: 2 referidos
  union all
  select pg_temp.conv_lead(n) from generate_series(1311, 1314) n   -- ARR: 3 del mes pasado + 1 de hace 13 meses
  union all
  select pg_temp.conv_lead(n) from generate_series(1321, 1324) n   -- FLO: 2 + 2 arrastrados
  union all
  select pg_temp.conv_lead(n) from generate_series(1351, 1353) n   -- FRA: 3 referidos
);

select set_config('crm.op_privilegiada', 'off', true);

-- CONV-10: DESPUÉS de cerrar, el lead cambia de manos. El ledger ya está
-- sellado: ni A pierde su cierre ni B lo gana.
update crm.leads set vendedor_id = pg_temp.conv_lead(14) where id = pg_temp.conv_lead(1331);

-- CONV-06: el coordinador descarta el lead que nunca tuvo dueño.
select set_config('request.jwt.claim.sub', pg_temp.conv_lead(21)::text, true);
update crm.leads
set etapa = 'descartado', motivo_descarte = 'datos_invalidos'
where id = pg_temp.conv_lead(1391);
select set_config('request.jwt.claim.sub', pg_temp.conv_lead(20)::text, true);

-- CONV-14: el cierre de SEP cae en el mes ANTERIOR mientras su ficha dice que
-- convirtió este mes. Es el caso de borde de T3 (la ficha sella con `now()` de
-- transacción y el ledger con `statement_timestamp()`): el numerador pierde el
-- cierre y la sonda tiene que declararlo.
-- Se duermen los triggers de las DOS tablas que este bloque retoca: el ledger
-- (retro-fechar cierres, marcar `aproximado`) y la ficha (`convertido_en`, que
-- `leads_before_update` restaura en silencio si su trigger está despierto).
alter table crm.lead_asignaciones disable trigger user;
alter table crm.leads disable trigger user;
update crm.lead_asignaciones la
set finalizado_en = pg_temp.conv_instante_anterior() + interval '1 hour',
    resultado_en  = pg_temp.conv_instante_anterior() + interval '1 hour'
where la.lead_id = pg_temp.conv_lead(1371)
  and la.resultado = 'convertido';

-- CONV-16b: la única fila `aproximado` de la base. Sin sembrarla, aseverar
-- `divisor_aproximado` sería aseverar un 0 que hoy sale solo.
update crm.lead_asignaciones la
set aproximado = true
where la.lead_id = pg_temp.conv_lead(1381);

-- CONV-21 (numerador) · las mismas cuatro fronteras, ahora por `resultado_en`,
-- que es el reloj del NUMERADOR (`fuentes.numerador`). Los cuatro episodios se
-- retro-fechan al mes pasado por `asignado_en` para que NO toquen el divisor:
-- así la fila de BORDE dice una cosa sola —divisor 2 por las fronteras de
-- arriba, cierres 2 por las de aquí— y un fallo no se puede compensar con otro.
--   1405 · v_ini - 1 s  → FUERA del numerador (cerró el mes pasado)
--   1408 · v_ini exacto → DENTRO
--   1406 · v_fin - 1 s  → DENTRO
--   1407 · v_fin exacto → FUERA (ese cierre es del mes que viene)
-- `finalizado_en` viaja con `resultado_en` porque el CHECK de cierre los exige
-- IGUALES, y `primera_gestion_limite_en` / `primer_contacto_limite_en` se
-- recolocan sobre el cierre para no violar sus dos CHECK.
update crm.lead_asignaciones la
set asignado_en                = pg_temp.conv_ini() - interval '2 seconds',
    sla_global_iniciado_en     = pg_temp.conv_ini() - interval '2 seconds',
    primera_gestion_limite_en  = b.instante,
    primer_contacto_limite_en  = b.instante,
    finalizado_en              = b.instante,
    resultado_en               = b.instante
from (values
  (pg_temp.conv_lead(1405), pg_temp.conv_ini() - interval '1 second'),
  (pg_temp.conv_lead(1406), pg_temp.conv_fin() - interval '1 second'),
  (pg_temp.conv_lead(1407), pg_temp.conv_fin()),
  (pg_temp.conv_lead(1408), pg_temp.conv_ini())
) as b(lead_id, instante)
where la.lead_id = b.lead_id
  and la.resultado = 'convertido';

-- Y la FICHA se mueve con el ledger. Si `convertido_en` se quedara en `now()`,
-- los dos cierres que caen fuera de la ventana aparecerían en la sonda
-- `cierres_sin_episodio` y CONV-14b —que asevera exactamente 1— fallaría por un
-- motivo que no tiene nada que ver con lo que ese caso prueba. Aquí ficha y
-- ledger dicen lo mismo a propósito: el desacuerdo entre los dos ya tiene su
-- caso propio, y es el 1371.
update crm.leads l
set convertido_en = b.instante
from (values
  (pg_temp.conv_lead(1405), pg_temp.conv_ini() - interval '1 second'),
  (pg_temp.conv_lead(1406), pg_temp.conv_fin() - interval '1 second'),
  (pg_temp.conv_lead(1407), pg_temp.conv_fin()),
  (pg_temp.conv_lead(1408), pg_temp.conv_ini())
) as b(lead_id, instante)
where l.id = b.lead_id;
alter table crm.leads enable trigger user;
alter table crm.lead_asignaciones enable trigger user;

-- ---------------------------------------------------------------------------
-- 5. Fase A — lo que hay que mirar en el LEDGER (todavía como dueño)
-- ---------------------------------------------------------------------------
-- `crm.lead_asignaciones` no tiene grants para ningún rol de la API, así que
-- estas comprobaciones tienen que ir ANTES de asumir el rol `authenticated`.
select set_config('request.jwt.claim.sub', pg_temp.conv_lead(1)::text, true);

do $test$
declare
  v_mes date := pg_temp.conv_mes();
  v_ant date := pg_temp.conv_mes_anterior();
  v_n   bigint;
  v_suelo timestamptz;
begin
  -- El roster bajo el supervisor: 17 exactos (los 16 de siempre más BORDE, que
  -- entró con las fronteras del mes). Si esto se mueve, TODOS los totales de
  -- abajo dejan de significar lo que dicen.
  select count(*) into v_n
  from private.roster_metas_vendedores() r
  where r.supervisor_id = pg_temp.conv_lead(1);
  perform pg_temp.conv_num('CONV-00', 'vendedores del roster bajo el supervisor', 17, v_n);

  if exists (select 1 from private.roster_metas_vendedores() r
             where r.vendedor_id = pg_temp.conv_lead(18)) then
    raise exception 'CONV-00 · FUE en el roster: ESPERADO fuera · OBTENIDO dentro (el fixture de CONV-13 no vale)';
  end if;

  -- ...pero SÍ dentro del subárbol del supervisor, o `fuera_de_roster` no
  -- tendría nada que contar.
  if not exists (select 1 from private.vendedor_ids_visibles(pg_temp.conv_lead(1)) v
                 where v = pg_temp.conv_lead(18)) then
    raise exception 'CONV-00 · FUE en el subarbol del supervisor: ESPERADO visible · OBTENIDO fuera del ambito';
  end if;

  -- Los siete episodios retro-fechados al mes anterior.
  select count(*) into v_n
  from crm.lead_asignaciones la
  where la.lead_id in (
    pg_temp.conv_lead(1006), pg_temp.conv_lead(1311), pg_temp.conv_lead(1312),
    pg_temp.conv_lead(1313), pg_temp.conv_lead(1323), pg_temp.conv_lead(1324),
    pg_temp.conv_lead(1371))
    and date_trunc('month', la.asignado_en at time zone 'America/Lima')::date = v_ant;
  perform pg_temp.conv_num('CONV-00', 'episodios retro-fechados al mes anterior', 7, v_n);

  -- Y el octavo, el de hace 13 meses. Sin él no habría cubo `anteriores`.
  select count(*) into v_n
  from crm.lead_asignaciones la
  where la.lead_id = pg_temp.conv_lead(1314)
    and date_trunc('month', la.asignado_en at time zone 'America/Lima')::date
        = (v_mes - interval '13 months')::date;
  perform pg_temp.conv_num('CONV-00', 'episodios retro-fechados a hace 13 meses', 1, v_n);

  -- La fila aproximada existe y es solo una dentro del fixture.
  select count(*) into v_n
  from crm.lead_asignaciones la
  where la.aproximado and la.lead_id = pg_temp.conv_lead(1381);
  perform pg_temp.conv_num('CONV-00', 'episodios aproximados sembrados', 1, v_n);

  -- El SUELO se calcula, nunca se fija: el ledger existe desde el 2026-07-17
  -- pero sus filas de entonces se borraron en duro el 2026-08-05. Con el
  -- arrastre sembrado, el suelo tiene que quedar ANTES del mes en curso, o
  -- CONV-11/11b estarían preguntando por meses que no existen.
  select min(la.asignado_en) into v_suelo
  from crm.lead_asignaciones la
  where not la.aproximado;
  if v_suelo is null then
    raise exception 'CONV-00 · suelo historico: ESPERADO un instante · OBTENIDO null (el ledger esta vacio)';
  end if;
  if v_suelo >= (v_mes::timestamp at time zone 'America/Lima') then
    raise exception 'CONV-00 · suelo historico: ESPERADO anterior a % · OBTENIDO %',
      (v_mes::timestamp at time zone 'America/Lima'), v_suelo;
  end if;
end;
$test$;

do $test$
declare
  v_n bigint;
begin
  -- CONV-01a · EL TRASPASO, en el ledger. Es la mitad que la fase B no puede
  -- ver: el payload solo dice «divisor 1 y divisor 1», y ese mismo par saldría
  -- de dos leads distintos con dueño de siempre —que es justo lo que el fixture
  -- viejo sembraba—. Aquí se exige que sea UN lead con DOS episodios, que el de
  -- A esté cerrado como `transferido` apuntando a B, y que el cierre sea del
  -- episodio de B: si alguien vuelve a partir el caso en dos leads, esto revienta.
  select count(*) into v_n
  from crm.lead_asignaciones la where la.lead_id = pg_temp.conv_lead(1001);
  perform pg_temp.conv_num('CONV-01a', 'episodios del lead traspasado', 2, v_n);

  if not exists (
    select 1 from crm.lead_asignaciones la
    where la.lead_id = pg_temp.conv_lead(1001)
      and la.analista_id = pg_temp.conv_lead(2)
      and la.motivo_apertura = 'ingreso'
      and la.motivo_cierre = 'transferido'
      and la.analista_destino_id = pg_temp.conv_lead(3)
      and la.resultado is null
  ) then
    raise exception 'CONV-01a · episodio de A: ESPERADO ingreso cerrado como transferido con destino B y SIN resultado · OBTENIDO otra cosa';
  end if;

  if not exists (
    select 1 from crm.lead_asignaciones la
    where la.lead_id = pg_temp.conv_lead(1001)
      and la.analista_id = pg_temp.conv_lead(3)
      and la.motivo_apertura = 'reasignado'
      and la.resultado = 'convertido'
      and la.resultado_en = la.finalizado_en
      and date_trunc('month', la.asignado_en at time zone 'America/Lima')::date = pg_temp.conv_mes()
  ) then
    raise exception 'CONV-01a · episodio de B: ESPERADO reasignado del mes, convertido y con resultado_en = finalizado_en · OBTENIDO otra cosa';
  end if;

  -- Y el lead sigue siendo UNO: si el traspaso hubiera abierto ciclo nuevo, el
  -- divisor de B contaría por otra puerta y `procedencia` cambiaría de cubo.
  if not exists (
    select 1 from crm.leads l
    where l.id = pg_temp.conv_lead(1001)
      and l.etapa = 'convertido'
      and l.vendedor_id = pg_temp.conv_lead(3)
      and l.ciclo_actual = 1
  ) then
    raise exception 'CONV-01a · ficha del lead traspasado: ESPERADO convertido, en manos de B y en el ciclo 1 · OBTENIDO otra cosa';
  end if;
end;
$test$;

do $test$
declare
  v_mes date := pg_temp.conv_mes();
  v_n   bigint;
begin
  -- CONV-06a · el lead descartado en la cola global existe, está descartado
  -- DENTRO del mes y por el coordinador... y no tiene un solo episodio. Ese cero
  -- de episodios es la prueba entera del caso: el divisor sale del ledger y
  -- `analista_id` es `not null`, así que sin episodio no hay divisor de nadie que
  -- pueda contaminarse.
  if not exists (
    select 1 from crm.leads l
    where l.id = pg_temp.conv_lead(1391)
      and l.etapa = 'descartado'
      and l.vendedor_id is null
      and l.asignado_supervisor_id is null
      and l.descartado_por = pg_temp.conv_lead(21)
      and date_trunc('month', l.creado_en at time zone 'America/Lima')::date = v_mes
  ) then
    raise exception 'CONV-06a · fixture del lead sin dueno: ESPERADO descartado por el coordinador en el mes y sin tenencia · OBTENIDO otra cosa';
  end if;

  select count(*) into v_n
  from crm.lead_asignaciones la where la.lead_id = pg_temp.conv_lead(1391);
  perform pg_temp.conv_num('CONV-06a', 'episodios del lead sin dueno', 0, v_n);
end;
$test$;

do $test$
declare
  v_mes date := pg_temp.conv_mes();
begin
  perform pg_temp.conv_caso('CONV-07a');
  -- CONV-07a · el soft-borrado: el lead está inactivo y su episodio conserva el
  -- `asignado_en` del mes. El ledger no tiene columna `activo`, así que la ley
  -- se cumple por construcción; esto lo deja escrito.
  if not exists (
    select 1 from crm.leads l
    where l.id = pg_temp.conv_lead(1302) and l.activo = false
  ) then
    raise exception 'CONV-07a · lead 1302: ESPERADO activo=false · OBTENIDO activo=true';
  end if;
  if not exists (
    select 1 from crm.lead_asignaciones la
    where la.lead_id = pg_temp.conv_lead(1302)
      and la.motivo_cierre = 'desactivado'
      and date_trunc('month', la.asignado_en at time zone 'America/Lima')::date = v_mes
  ) then
    raise exception 'CONV-07a · episodio del lead soft-borrado: ESPERADO cierre desactivado con asignado_en en % · OBTENIDO otra cosa', v_mes;
  end if;
end;
$test$;

do $test$
declare
  v_mes date := pg_temp.conv_mes();
  v_n   bigint;
begin
  -- CONV-10a · el lead cerrado y luego movido conserva UN episodio, el de M1.
  select count(*) into v_n
  from crm.lead_asignaciones la where la.lead_id = pg_temp.conv_lead(1331);
  perform pg_temp.conv_num('CONV-10a', 'episodios del lead cerrado y reasignado', 1, v_n);

  if not exists (
    select 1 from crm.lead_asignaciones la
    where la.lead_id = pg_temp.conv_lead(1331)
      and la.analista_id = pg_temp.conv_lead(13)
      and la.resultado = 'convertido'
      and date_trunc('month', la.resultado_en at time zone 'America/Lima')::date = v_mes
  ) then
    raise exception 'CONV-10a · autoria del cierre: ESPERADO el episodio de M1 convertido en % · OBTENIDO otra cosa', v_mes;
  end if;

  if not exists (
    select 1 from crm.leads l
    where l.id = pg_temp.conv_lead(1331) and l.vendedor_id = pg_temp.conv_lead(14)
  ) then
    raise exception 'CONV-10a · tenencia posterior: ESPERADO el lead en manos de M2 · OBTENIDO otra';
  end if;
end;
$test$;

do $test$
declare
  v_mes date := pg_temp.conv_mes();
  v_ant date := pg_temp.conv_mes_anterior();
begin
  perform pg_temp.conv_caso('CONV-14a');
  -- CONV-14a · la ficha dice que convirtió este mes; el ledger, el mes pasado.
  if not exists (
    select 1 from crm.leads l
    where l.id = pg_temp.conv_lead(1371)
      and l.etapa = 'convertido'
      and date_trunc('month', l.convertido_en at time zone 'America/Lima')::date = v_mes
  ) then
    raise exception 'CONV-14a · ficha del lead: ESPERADO convertido_en en % · OBTENIDO otra cosa', v_mes;
  end if;
  if not exists (
    select 1 from crm.lead_asignaciones la
    where la.lead_id = pg_temp.conv_lead(1371)
      and la.resultado = 'convertido'
      and date_trunc('month', la.resultado_en at time zone 'America/Lima')::date = v_ant
  ) then
    raise exception 'CONV-14a · episodio del lead: ESPERADO resultado_en en % · OBTENIDO otra cosa', v_ant;
  end if;
end;
$test$;

do $test$
declare
  v_n bigint;
begin
  -- CONV-21a · PRECONDICIÓN de las fronteras. Los ocho instantes se comprueban
  -- UNO A UNO contra el segundo exacto. Sin esto, un `update` de la sección 3 o
  -- 4 que no case ni una fila dejaría a BORDE con toda su cartera dentro del mes
  -- y CONV-21b saldría en verde por el motivo contrario al que dice probar: no
  -- estaría midiendo la frontera, estaría midiendo el centro del mes otra vez.
  select count(*) into v_n
  from crm.lead_asignaciones la
  where (la.lead_id = pg_temp.conv_lead(1401)
         and la.asignado_en = pg_temp.conv_ini() - interval '1 second'
         and la.finalizado_en is null)
     or (la.lead_id = pg_temp.conv_lead(1402)
         and la.asignado_en = pg_temp.conv_ini()
         and la.finalizado_en is null)
     or (la.lead_id = pg_temp.conv_lead(1403)
         and la.asignado_en = pg_temp.conv_fin() - interval '1 second'
         and la.finalizado_en is null)
     or (la.lead_id = pg_temp.conv_lead(1404)
         and la.asignado_en = pg_temp.conv_fin()
         and la.finalizado_en is null)
     or (la.lead_id = pg_temp.conv_lead(1405)
         and la.resultado_en = pg_temp.conv_ini() - interval '1 second')
     or (la.lead_id = pg_temp.conv_lead(1408)
         and la.resultado_en = pg_temp.conv_ini())
     or (la.lead_id = pg_temp.conv_lead(1406)
         and la.resultado_en = pg_temp.conv_fin() - interval '1 second')
     or (la.lead_id = pg_temp.conv_lead(1407)
         and la.resultado_en = pg_temp.conv_fin());
  perform pg_temp.conv_num('CONV-21a', 'episodios de borde clavados en su instante exacto', 8, v_n);

  -- Los cuatro cierres de borde tienen `asignado_en` FUERA del mes: su fila solo
  -- puede mover el numerador, nunca el divisor. Es lo que permite leer el 2 y el
  -- 2 de CONV-21b como dos medidas independientes.
  select count(*) into v_n
  from crm.lead_asignaciones la
  where la.lead_id in (pg_temp.conv_lead(1405), pg_temp.conv_lead(1406),
                       pg_temp.conv_lead(1407), pg_temp.conv_lead(1408))
    and la.asignado_en < pg_temp.conv_ini();
  perform pg_temp.conv_num('CONV-21a', 'cierres de borde recibidos ANTES del mes', 4, v_n);

  -- Y ficha y ledger coinciden en los cuatro, para que la sonda de CONV-14b siga
  -- viendo UN solo cierre huérfano —el 1371— y no cinco.
  select count(*) into v_n
  from crm.leads l
  join crm.lead_asignaciones la on la.lead_id = l.id and la.resultado = 'convertido'
  where l.id in (pg_temp.conv_lead(1405), pg_temp.conv_lead(1406),
                 pg_temp.conv_lead(1407), pg_temp.conv_lead(1408))
    and l.convertido_en = la.resultado_en;
  perform pg_temp.conv_num('CONV-21a', 'cierres de borde con ficha y ledger en el mismo instante', 4, v_n);
end;
$test$;

-- ---------------------------------------------------------------------------
-- 6. Fase B — el payload, bajo el rol y la identidad reales
-- ---------------------------------------------------------------------------
-- `authenticated` es el rol con el que llega la Data API. La RPC es SECURITY
-- DEFINER, así que el rol no cambia lo que calcula, pero sí prueba el GRANT y
-- el camino completo: gate → ámbito → payload.
set local role authenticated;

-- ── CONV-01 ─────────────────────────────────────────────────────────────────
-- A recibe DOS: uno lo traspasa a B y otro lo suelta a la bandeja. B recibe por
-- TRASPASO ese mismo lead y lo cierra.
--
-- Las dos mitades de la regla, en un solo cuadro:
--   · soltar o traspasar un lead NO lo borra del divisor de quien lo recibió
--     (A cierra el mes con divisor 2 y 0 cierres, o sea 0 %),
--   · y el que lo recibe DESPUÉS también lo cuenta (B, divisor 1) y se lleva el
--     cierre entero (100 %).
-- El mismo lead pesa 1 en dos divisores distintos. Eso NO es doble conteo: el
-- divisor mide «cuántos leads pasaron por tus manos este mes», y por las de los
-- dos pasó. Lo que sí sería doble conteo es contarlo dos veces para el MISMO
-- analista, y de eso se ocupa CONV-02.
do $test$
declare
  v_pay jsonb;
  f jsonb;
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());

  f := pg_temp.conv_fila('CONV-01', v_pay, pg_temp.conv_lead(2));
  perform pg_temp.conv_num('CONV-01', 'divisor de A (traspasa uno y suelta otro)', 2, (f->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-01', 'cierres de A',                   0,
    (f->>'cierres_no_referidos')::numeric + (f->>'cierres_referidos')::numeric);
  perform pg_temp.conv_num('CONV-01', 'numerador de A',                 0, (f->>'numerador')::numeric);
  perform pg_temp.conv_num('CONV-01', 'conversion_pct de A',            0.00, (f->>'conversion_pct')::numeric);
  perform pg_temp.conv_txt('CONV-01', 'estado de A',                    'medible', f->>'estado');

  f := pg_temp.conv_fila('CONV-01', v_pay, pg_temp.conv_lead(3));
  perform pg_temp.conv_num('CONV-01', 'divisor de B (recibe por traspaso y cierra)', 1, (f->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-01', 'cierres no referidos de B',      1, (f->>'cierres_no_referidos')::numeric);
  perform pg_temp.conv_num('CONV-01', 'numerador de B',                 1, (f->>'numerador')::numeric);
  perform pg_temp.conv_num('CONV-01', 'conversion_pct de B',            100.00, (f->>'conversion_pct')::numeric);

  -- El cierre del lead traspasado es de B y de NADIE más: si el numerador se
  -- fechara o se atribuyera por la ficha del lead en vez de por la fila
  -- inmutable que cerró, A se llevaría un cierre que no hizo.
  perform pg_temp.conv_num('CONV-01', 'cierres del par A+B (un lead, un cierre)', 1,
    (pg_temp.conv_fila('CONV-01', v_pay, pg_temp.conv_lead(2))->>'cierres_no_referidos')::numeric
    + (f->>'cierres_no_referidos')::numeric);
end;
$test$;

-- ── CONV-02 ─────────────────────────────────────────────────────────────────
-- A→B→A dentro del mes. Se cuenta el LEAD, no el episodio: si contara episodios,
-- se podría hundir un porcentaje moviendo un lead de ida y vuelta.
--
-- El desglose por motivo se asevera en el AGREGADO DEL ÁMBITO y no en la fila,
-- porque el payload por responsable NO lleva `divisor_por_motivo` (la RPC solo
-- lo emite en `cobertura`). Además el agregado es la lectura que ejercita la
-- cadena entera —`motivos` → `motivos_json` → `motivos_totales` →
-- `cobertura.divisor_por_motivo`—, mientras que un campo por fila se habría
-- quedado en `motivos_json`.
do $test$
declare
  v_pay jsonb;
  f jsonb;
  v_claves text;
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());

  f := pg_temp.conv_fila('CONV-02', v_pay, pg_temp.conv_lead(4));
  perform pg_temp.conv_num('CONV-02', 'divisor de IDA (dos episodios, un lead)', 1, (f->>'divisor')::numeric);

  f := pg_temp.conv_fila('CONV-02', v_pay, pg_temp.conv_lead(5));
  perform pg_temp.conv_num('CONV-02', 'divisor de VUELTA', 1, (f->>'divisor')::numeric);

  -- El motivo que sobrevive al agrupado es el del PRIMER episodio del mes:
  -- `(array_agg(la.motivo_apertura order by la.asignado_en ASC))[1]`
  -- (20260811154434:622-623). La pregunta que contesta esta clave es «¿POR QUÉ
  -- entró este lead al divisor DE ESTE MES?», y eso lo responde la puerta por la
  -- que entró, no la última vez que cambió de manos dentro del mes.
  --
  -- A IDA le quedan DOS episodios en el mes (el `ingreso` del alta y el
  -- `reasignado` de la vuelta) y gana el primero: cuenta como `ingreso`. Los
  -- `reasignado` reales son por tanto solo dos — el de B, que recibió por
  -- TRASPASO el lead de A (CONV-01), y el de VUELTA por el 1003.
  --
  -- La mutación que estos dos números cazan es la INVERSIÓN a `desc`, que daría
  -- 112/3. No es hipotética: es lo que el borrador de la migración hacía, y su
  -- efecto real no es mover el divisor —sigue habiendo un valor por (analista,
  -- lead)— sino REETIQUETARLO. Con `desc`, cien leads que entran por `ingreso`
  -- el día 1, se parquean el 2 y se reactivan ese mismo día 2 salían en el
  -- desglose como `{"reactivado": 100}`: la clave `ingreso` desaparecía y el
  -- pico de una carga masiva —lo único que este desglose existe para hacer
  -- VISIBLE— quedaba escondido, y encima disfrazado de reciclaje de cartera
  -- vieja. Son los CONTEOS, y no el juego de claves, los que lo cazan.
  perform pg_temp.conv_num('CONV-02', 'cobertura.divisor_por_motivo{ingreso}', 113,
    (v_pay #>> '{cobertura,divisor_por_motivo,ingreso}')::numeric);
  perform pg_temp.conv_num('CONV-02', 'cobertura.divisor_por_motivo{reasignado}', 2,
    (v_pay #>> '{cobertura,divisor_por_motivo,reasignado}')::numeric);

  -- Vocabulario cerrado: solo los motivos que el fixture produce. Una clave de
  -- más significa que el desglose está contando algo que el divisor no cuenta.
  select string_agg(k, ',' order by k) into v_claves
  from jsonb_object_keys(v_pay #> '{cobertura,divisor_por_motivo}') k;
  perform pg_temp.conv_txt('CONV-02', 'claves de cobertura.divisor_por_motivo',
    'ingreso,reasignado', v_claves);

  -- Y el desglose CUADRA con el divisor: si no sumara, una de las dos cifras
  -- estaría contando episodios en vez de leads.
  perform pg_temp.conv_num('CONV-02', 'suma de divisor_por_motivo vs total.divisor',
    (v_pay #>> '{total,divisor}')::numeric,
    (v_pay #>> '{cobertura,divisor_por_motivo,ingreso}')::numeric
    + (v_pay #>> '{cobertura,divisor_por_motivo,reasignado}')::numeric);
end;
$test$;

-- ── CONV-03 ─────────────────────────────────────────────────────────────────
-- Un lead recibido el mes pasado y cerrado este suma al NUMERADOR de este mes y
-- no al divisor: su divisor fue el mes pasado. Por eso existe `procedencia`.
do $test$
declare
  v_pay jsonb;
  f jsonb;
  p jsonb;
  v_ant date := pg_temp.conv_mes_anterior();
  -- Array PROPIO del oráculo: comparar contra `private.etiqueta_mes_es` sería
  -- comparar la implementación consigo misma (y `authenticated` no puede
  -- ejecutarla, que es lo correcto).
  c_meses text[] := array['enero','febrero','marzo','abril','mayo','junio',
                          'julio','agosto','setiembre','octubre','noviembre','diciembre'];
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());
  f := pg_temp.conv_fila('CONV-03', v_pay, pg_temp.conv_lead(6));

  perform pg_temp.conv_num('CONV-03', 'divisor de PRO (el arrastre NO lo toca)', 2, (f->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-03', 'cierres no referidos de PRO',             1, (f->>'cierres_no_referidos')::numeric);
  perform pg_temp.conv_num('CONV-03', 'numerador de PRO',                        1, (f->>'numerador')::numeric);
  perform pg_temp.conv_num('CONV-03', 'conversion_pct de PRO',                   50.00, (f->>'conversion_pct')::numeric);

  -- El campo PLANO que explica el arrastre sin recorrer el array. Es derivable
  -- de `procedencia`, pero se publica aparte para que la tarjeta pueda justificar
  -- un ratio por encima de 100 de un vistazo — y hasta este ciclo no lo miraba
  -- NADIE en todo el oráculo: un `create or replace` que lo dejara en 0, o que
  -- cambiara su `count(distinct lead_id) filter (where mes_origen < mes_periodo)`
  -- por un `count(*)`, pasaba la suite entera en verde.
  perform pg_temp.conv_num('CONV-03', 'cierres_de_arrastre de PRO', 1, (f->>'cierres_de_arrastre')::numeric);

  p := f->'procedencia';
  perform pg_temp.conv_num('CONV-03', 'cubos de procedencia de PRO', 1, jsonb_array_length(p));
  perform pg_temp.conv_txt('CONV-03', 'procedencia[0].mes',
    to_char(v_ant, 'YYYY-MM'), p->0->>'mes');
  perform pg_temp.conv_txt('CONV-03', 'procedencia[0].mes_nombre',
    c_meses[extract(month from v_ant)::int], p->0->>'mes_nombre');
  perform pg_temp.conv_num('CONV-03', 'procedencia[0].anio',
    extract(year from v_ant)::numeric, (p->0->>'anio')::numeric);
  perform pg_temp.conv_num('CONV-03', 'procedencia[0].cierres', 1, (p->0->>'cierres')::numeric);
  perform pg_temp.conv_num('CONV-03', 'procedencia[0].cierres_referidos', 0,
    (p->0->>'cierres_referidos')::numeric);
end;
$test$;

-- ── CONV-04 · el caso canónico (Ana) ────────────────────────────────────────
-- 90 no referidos + 20 referidos, cierra 16 y 12. El divisor son 90, NO 110:
-- recibir un referido es gratis, cerrarlo premia al 15 %.
do $test$
declare
  v_pay jsonb;
  f jsonb;
  r jsonb;
  p jsonb;
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());
  f := pg_temp.conv_fila('CONV-04', v_pay, pg_temp.conv_lead(7));
  r := f->'referidos';

  perform pg_temp.conv_num('CONV-04', 'divisor de ANA (90, no 110)',   90, (f->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-04', 'cierres no referidos de ANA',   16, (f->>'cierres_no_referidos')::numeric);
  perform pg_temp.conv_num('CONV-04', 'cierres referidos de ANA',      12, (f->>'cierres_referidos')::numeric);
  perform pg_temp.conv_num('CONV-04', 'numerador de ANA (16 + 12x0,15)', 17.80, (f->>'numerador')::numeric);
  perform pg_temp.conv_num('CONV-04', 'conversion_pct de ANA',         19.78, (f->>'conversion_pct')::numeric);
  perform pg_temp.conv_txt('CONV-04', 'estado de ANA',                 'medible', f->>'estado');
  perform pg_temp.conv_num('CONV-04', 'referidos.recibidos de ANA',    20, (r->>'recibidos')::numeric);
  perform pg_temp.conv_num('CONV-04', 'referidos.cerrados de ANA',     12, (r->>'cerrados')::numeric);
  perform pg_temp.conv_num('CONV-04', 'referidos.aporta_pct de ANA',   2.00, (r->>'aporta_pct')::numeric);
  -- `dados_de_alta` sale de la columna VIVA `crm.leads.creado_por`, no del
  -- snapshot: es el único número del payload que no es reproducible hacia atrás.
  perform pg_temp.conv_num('CONV-04', 'referidos.dados_de_alta de ANA', 20, (r->>'dados_de_alta')::numeric);
  -- La ponderación viaja en el payload y tiene que ser la de la tabla, no una
  -- constante del código.
  perform pg_temp.conv_num('CONV-04', 'ponderacion.referido', 0.150,
    (v_pay #>> '{ponderacion,referido}')::numeric);

  -- Los 28 cierres de ANA son TODOS del propio mes: su arrastre es 0. Sin este
  -- cero, `cierres_de_arrastre` solo se comprobaría donde vale algo, y un campo
  -- que siempre devolviera un número positivo pasaría igual.
  perform pg_temp.conv_num('CONV-04', 'cierres_de_arrastre de ANA', 0,
    (f->>'cierres_de_arrastre')::numeric);

  -- `supervisor_id` en la fila del responsable: es lo que permite a la pantalla
  -- agrupar por equipo sin una segunda consulta, y nadie lo miraba.
  perform pg_temp.conv_txt('CONV-04', 'supervisor_id de ANA',
    pg_temp.conv_lead(1)::text, f->>'supervisor_id');

  -- Un solo cubo de procedencia —el mes en curso— con los 28 cierres, de los que
  -- 12 son referidos. `procedencia[].cierres_referidos` tampoco lo aseveraba
  -- nadie, y es la mitad del desglose que hace que la tarjeta pueda explicar de
  -- dónde salen los 2,00 puntos de `aporta_pct`.
  p := f->'procedencia';
  perform pg_temp.conv_num('CONV-04', 'cubos de procedencia de ANA', 1, jsonb_array_length(p));
  perform pg_temp.conv_txt('CONV-04', 'procedencia[0].mes de ANA',
    to_char(pg_temp.conv_mes(), 'YYYY-MM'), p->0->>'mes');
  perform pg_temp.conv_num('CONV-04', 'procedencia[0].cierres de ANA (16 + 12)', 28,
    (p->0->>'cierres')::numeric);
  perform pg_temp.conv_num('CONV-04', 'procedencia[0].cierres_referidos de ANA', 12,
    (p->0->>'cierres_referidos')::numeric);
end;
$test$;

-- ── CONV-04b · el efecto de borde nuevo ─────────────────────────────────────
-- Solo le llegaron referidos: su divisor legítimo es 0. Trabajó; simplemente no
-- tiene denominador. Confundirlo con `sin_actividad` es acusarle de no trabajar,
-- y con `solo_arrastre`, de vivir del mes pasado.
do $test$
declare
  v_pay jsonb;
  f jsonb;
  r jsonb;
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());
  f := pg_temp.conv_fila('CONV-04b', v_pay, pg_temp.conv_lead(8));
  r := f->'referidos';

  perform pg_temp.conv_num('CONV-04b', 'divisor de REF',              0, (f->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-04b', 'referidos.recibidos de REF',  8, (r->>'recibidos')::numeric);
  perform pg_temp.conv_num('CONV-04b', 'cierres referidos de REF',    2, (f->>'cierres_referidos')::numeric);
  perform pg_temp.conv_num('CONV-04b', 'numerador de REF (2x0,15)',   0.30, (f->>'numerador')::numeric);
  -- NULL EXPLÍCITO, no clave ausente y no 0: «sin datos» y «0 %» son dos frases
  -- muy distintas sobre el trabajo de una persona.
  perform pg_temp.conv_txt('CONV-04b', 'tipo json de conversion_pct de REF',
    'null', jsonb_typeof(f->'conversion_pct'));
  perform pg_temp.conv_txt('CONV-04b', 'tipo json de referidos.aporta_pct de REF',
    'null', jsonb_typeof(r->'aporta_pct'));
  perform pg_temp.conv_txt('CONV-04b', 'estado de REF', 'solo_referidos', f->>'estado');
end;
$test$;

-- ── CONV-05 ─────────────────────────────────────────────────────────────────
-- Un descartado CON dueño le sigue contando al asesor: va al DIVISOR, por eso
-- descartar BAJA la conversión (regla de Miguel, 2026-08-10).
do $test$
declare
  v_pay jsonb;
  f jsonb;
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());
  f := pg_temp.conv_fila('CONV-05', v_pay, pg_temp.conv_lead(9));

  perform pg_temp.conv_num('CONV-05', 'divisor de DES (descartado con dueno)', 1, (f->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-05', 'cierres de DES', 0,
    (f->>'cierres_no_referidos')::numeric + (f->>'cierres_referidos')::numeric);
  perform pg_temp.conv_num('CONV-05', 'conversion_pct de DES', 0.00, (f->>'conversion_pct')::numeric);
  perform pg_temp.conv_txt('CONV-05', 'estado de DES', 'medible', f->>'estado');
end;
$test$;

-- ── CONV-07 ─────────────────────────────────────────────────────────────────
-- Un lead soft-borrado sigue en el divisor. El ledger no tiene columna `activo`:
-- la ley se cumple por construcción y no hay predicado que nadie pueda
-- «arreglar». Ojo: `cartera_pagina_fn` sí filtra `activo` — una cosa es qué se
-- VE y otra qué se CUENTA.
do $test$
declare
  v_pay jsonb;
  f jsonb;
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());
  f := pg_temp.conv_fila('CONV-07', v_pay, pg_temp.conv_lead(10));

  perform pg_temp.conv_num('CONV-07', 'divisor de BOR (lead soft-borrado)', 1, (f->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-07', 'conversion_pct de BOR', 0.00, (f->>'conversion_pct')::numeric);
end;
$test$;

-- ── CONV-08 ─────────────────────────────────────────────────────────────────
-- No recibió nada, pero cerró cartera vieja. Con divisor 0 el porcentaje es
-- NULL, jamás 0, y el estado dice de dónde viene ese 0.
--
-- Sus cuatro cierres arrastrados caen en DOS cubos: tres del mes pasado y uno de
-- hace 13 meses, que es el único caso capaz de ejercitar el cubo `anteriores`.
-- Sin él, la comparación `<= 11` podría invertirse a `>= 11` y la `procedencia`
-- de un asesor con cartera de dos años crecería sin techo, que es exactamente lo
-- que ese cubo existe para impedir.
do $test$
declare
  v_pay jsonb;
  f jsonb;
  p jsonb;
  v_ant date := pg_temp.conv_mes_anterior();
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());
  f := pg_temp.conv_fila('CONV-08', v_pay, pg_temp.conv_lead(11));

  perform pg_temp.conv_num('CONV-08', 'divisor de ARR',               0, (f->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-08', 'cierres no referidos de ARR',  4, (f->>'cierres_no_referidos')::numeric);
  perform pg_temp.conv_num('CONV-08', 'numerador de ARR',             4, (f->>'numerador')::numeric);
  -- Los CUATRO cierres son de arrastre: es el caso puro del campo, y el que
  -- distingue «arrastre» de «cierres del mes».
  perform pg_temp.conv_num('CONV-08', 'cierres_de_arrastre de ARR', 4,
    (f->>'cierres_de_arrastre')::numeric);
  perform pg_temp.conv_txt('CONV-08', 'tipo json de conversion_pct de ARR',
    'null', jsonb_typeof(f->'conversion_pct'));
  perform pg_temp.conv_txt('CONV-08', 'estado de ARR', 'solo_arrastre', f->>'estado');

  p := f->'procedencia';
  perform pg_temp.conv_num('CONV-08', 'cubos de procedencia de ARR', 2, jsonb_array_length(p));
  -- `order by mes_cubo desc nulls last`: el cubo sin mes va SIEMPRE el último.
  perform pg_temp.conv_txt('CONV-08', 'procedencia[0].mes de ARR',
    to_char(v_ant, 'YYYY-MM'), p->0->>'mes');
  perform pg_temp.conv_num('CONV-08', 'procedencia[0].cierres de ARR', 3, (p->0->>'cierres')::numeric);
  perform pg_temp.conv_num('CONV-08', 'procedencia[0].cierres_referidos de ARR', 0,
    (p->0->>'cierres_referidos')::numeric);
  perform pg_temp.conv_txt('CONV-08', 'procedencia[1].mes_nombre de ARR',
    'anteriores', p->1->>'mes_nombre');
  perform pg_temp.conv_txt('CONV-08', 'tipo json de procedencia[1].mes de ARR',
    'null', jsonb_typeof(p->1->'mes'));
  perform pg_temp.conv_txt('CONV-08', 'tipo json de procedencia[1].anio de ARR',
    'null', jsonb_typeof(p->1->'anio'));
  perform pg_temp.conv_num('CONV-08', 'procedencia[1].cierres de ARR', 1, (p->1->>'cierres')::numeric);
  perform pg_temp.conv_num('CONV-08', 'procedencia[1].cierres_referidos de ARR', 0,
    (p->1->>'cierres_referidos')::numeric);
end;
$test$;

-- ── CONV-09 ─────────────────────────────────────────────────────────────────
-- Mes flojo en entradas: 2 recibidos y 4 cierres son 200 %. La definición supera
-- el 100 % POR DISEÑO. Recortarlo aquí (o en el `maxValue(100)` del front)
-- apagaría las tres pantallas de metas para los 17 compañeros.
do $test$
declare
  v_pay jsonb;
  f jsonb;
  p jsonb;
  v_mes date := pg_temp.conv_mes();
  v_ant date := pg_temp.conv_mes_anterior();
begin
  v_pay := crm.conversion_mensual_fn(v_mes);
  f := pg_temp.conv_fila('CONV-09', v_pay, pg_temp.conv_lead(12));

  perform pg_temp.conv_num('CONV-09', 'divisor de FLO',              2, (f->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-09', 'cierres no referidos de FLO', 4, (f->>'cierres_no_referidos')::numeric);
  perform pg_temp.conv_num('CONV-09', 'numerador de FLO',            4, (f->>'numerador')::numeric);
  perform pg_temp.conv_num('CONV-09', 'conversion_pct de FLO (SIN recorte a 100)',
    200.00, (f->>'conversion_pct')::numeric);

  -- Y AQUÍ está la razón del 200 %, en una sola clave: de los cuatro cierres,
  -- DOS traen su numerador de un mes cuyo divisor fue otro. `cierres_de_arrastre`
  -- existe exactamente para que ese ratio se pueda descomponer en pantalla sin
  -- parecer un error; aseverar el 200 sin aseverar el 2 era publicar el síntoma
  -- y no comprobar la explicación.
  perform pg_temp.conv_num('CONV-09', 'cierres_de_arrastre de FLO (los 2 que explican el 200 %)',
    2, (f->>'cierres_de_arrastre')::numeric);

  -- Dos cubos y el más reciente primero: la procedencia se ordena por mes desc.
  p := f->'procedencia';
  perform pg_temp.conv_num('CONV-09', 'cubos de procedencia de FLO', 2, jsonb_array_length(p));
  perform pg_temp.conv_txt('CONV-09', 'procedencia[0].mes de FLO', to_char(v_mes, 'YYYY-MM'), p->0->>'mes');
  perform pg_temp.conv_txt('CONV-09', 'procedencia[1].mes de FLO', to_char(v_ant, 'YYYY-MM'), p->1->>'mes');
  perform pg_temp.conv_num('CONV-09', 'procedencia[0].cierres de FLO', 2, (p->0->>'cierres')::numeric);
  perform pg_temp.conv_num('CONV-09', 'procedencia[1].cierres de FLO', 2, (p->1->>'cierres')::numeric);
end;
$test$;

-- ── CONV-10b ────────────────────────────────────────────────────────────────
-- El cierre se atribuye al `analista_id` de la fila INMUTABLE que cerró. Mover
-- el lead después no reescribe el pasado de nadie.
do $test$
declare
  v_pay jsonb;
  f jsonb;
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());

  f := pg_temp.conv_fila('CONV-10b', v_pay, pg_temp.conv_lead(13));
  perform pg_temp.conv_num('CONV-10b', 'divisor de M1 (el que cerro)',      1, (f->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-10b', 'cierres no referidos de M1',        1, (f->>'cierres_no_referidos')::numeric);
  perform pg_temp.conv_num('CONV-10b', 'conversion_pct de M1',              100.00, (f->>'conversion_pct')::numeric);

  f := pg_temp.conv_fila('CONV-10b', v_pay, pg_temp.conv_lead(14));
  perform pg_temp.conv_num('CONV-10b', 'divisor de M2 (recibio el lead ya cerrado)', 0, (f->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-10b', 'cierres de M2', 0,
    (f->>'cierres_no_referidos')::numeric + (f->>'cierres_referidos')::numeric);
  perform pg_temp.conv_txt('CONV-10b', 'estado de M2', 'sin_actividad', f->>'estado');
end;
$test$;

-- ── CONV-11 y CONV-11b · la cobertura del ledger ────────────────────────────
-- El suelo se LEE de la base y de él se derivan los dos meses. Fijar una fecha
-- aquí sería fijar una constante que ya nació mintiendo una vez (el plan
-- escribía 2026-07-17 y producción dice 2026-08-05).
--   · mes ENTERO anterior al suelo → `anterior_al_ledger`
--   · el mes que CONTIENE el suelo → `mes_parcial`
-- La distinción existe porque comparando contra el MES del suelo, el mes en el
-- que nace el ledger jamás podría salir no-medible: hoy mismo agosto se habría
-- declarado fiable con 4,5 días de datos.
do $test$
declare
  v_pay jsonb;
  v_suelo timestamptz;
  v_suelo_mes date;
  c jsonb;
begin
  -- El suelo no se puede leer desde `authenticated` (el ledger no tiene grants),
  -- así que se toma del propio payload: es metadato público del ledger y viaja
  -- sin recorte de ámbito a propósito.
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());
  v_suelo := (v_pay #>> '{cobertura,suelo_historico}')::timestamptz;
  if v_suelo is null then
    raise exception 'CONV-11 · cobertura.suelo_historico: ESPERADO un instante · OBTENIDO null';
  end if;
  v_suelo_mes := date_trunc('month', v_suelo at time zone 'America/Lima')::date;

  -- CONV-11 · un mes entero por debajo del suelo.
  c := crm.conversion_mensual_fn((v_suelo_mes - interval '1 month')::date) -> 'cobertura';
  perform pg_temp.conv_txt('CONV-11', 'cobertura.medible del mes anterior al suelo',
    'false', c->>'medible');
  perform pg_temp.conv_txt('CONV-11', 'cobertura.motivo_no_medible del mes anterior al suelo',
    'anterior_al_ledger', c->>'motivo_no_medible');

  -- CONV-11b · el mes que contiene el suelo. Si el suelo cayera exactamente en
  -- el primer instante del mes, el mes sería medible y el fixture no probaría
  -- nada: se dice en voz alta en vez de dar un verde falso.
  if v_suelo = (v_suelo_mes::timestamp at time zone 'America/Lima') then
    raise exception 'CONV-11b · PRECONDICION: el suelo (%) cae en el primer instante de su mes, asi que ese mes es medible y el caso no es expresable', v_suelo;
  end if;
  c := crm.conversion_mensual_fn(v_suelo_mes) -> 'cobertura';
  perform pg_temp.conv_txt('CONV-11b', 'cobertura.medible del mes del suelo',
    'false', c->>'medible');
  perform pg_temp.conv_txt('CONV-11b', 'cobertura.motivo_no_medible del mes del suelo',
    'mes_parcial', c->>'motivo_no_medible');
end;
$test$;

-- ── CONV-12 · el numerador es fraccionario y no se redondea ─────────────────
-- 0,15 × 3 = 0,45. Al entero más cercano son 0: se borrarían tres cierres
-- reales. La comparación es NUMÉRICA y exacta (`numeric` es decimal exacto), así
-- que ni 0 ni 0,45000001 pasan.
do $test$
declare
  v_pay jsonb;
  f jsonb;
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());
  f := pg_temp.conv_fila('CONV-12', v_pay, pg_temp.conv_lead(15));

  perform pg_temp.conv_num('CONV-12', 'cierres no referidos de FRA',  0, (f->>'cierres_no_referidos')::numeric);
  perform pg_temp.conv_num('CONV-12', 'cierres referidos de FRA',     3, (f->>'cierres_referidos')::numeric);
  perform pg_temp.conv_num('CONV-12', 'numerador de FRA (0,15 x 3)',  0.45, (f->>'numerador')::numeric);
  perform pg_temp.conv_num('CONV-12', 'divisor de FRA',               10, (f->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-12', 'conversion_pct de FRA',        4.50, (f->>'conversion_pct')::numeric);
  perform pg_temp.conv_num('CONV-12', 'referidos.aporta_pct de FRA',  4.50, (f #>> '{referidos,aporta_pct}')::numeric);
end;
$test$;

-- ── CONV-13 · producción fuera del roster ───────────────────────────────────
-- Ni se pierde ni se le atribuye a nadie: se declara como AGREGADO SIN IDENTIDAD.
-- Devolver su uuid sería filtrar la identidad de alguien sin rol efectivo.
do $test$
declare
  v_pay jsonb;
  fr jsonb;
  v_claves text[];
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());

  perform pg_temp.conv_caso('CONV-13a');
  -- CONV-13a · no está entre los responsables.
  if exists (
    select 1 from jsonb_array_elements(v_pay->'responsables') el
    where (el.value->>'vendedor_id')::uuid = pg_temp.conv_lead(18)
  ) then
    raise exception 'CONV-13a · responsables: ESPERADO sin la fila de FUE · OBTENIDO con su identidad publicada';
  end if;

  -- CONV-13b · pero sus cifras están, en agregado y sin uuid.
  fr := v_pay #> '{cobertura,fuera_de_roster}';
  perform pg_temp.conv_num('CONV-13b', 'fuera_de_roster.analistas', 1, (fr->>'analistas')::numeric);
  perform pg_temp.conv_num('CONV-13b', 'fuera_de_roster.divisor',   2, (fr->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-13b', 'fuera_de_roster.cierres',   1, (fr->>'cierres')::numeric);
  perform pg_temp.conv_num('CONV-13b', 'fuera_de_roster.numerador', 1, (fr->>'numerador')::numeric);

  select array_agg(k order by k) into v_claves from jsonb_object_keys(fr) k;
  perform pg_temp.conv_txt('CONV-13b', 'claves de fuera_de_roster (sin identidad)',
    'analistas,cierres,divisor,numerador', array_to_string(v_claves, ','));
end;
$test$;

-- CONV-13c · y cuando el propio excluido consulta, se le dice POR QUÉ. Silenciar
-- la exclusión sería cambiar un bug ruidoso por uno mudo: veía una pantalla en
-- blanco con `medible = true` calculado sobre el ledger de los demás.
select set_config('request.jwt.claim.sub', pg_temp.conv_lead(18)::text, true);
do $test$
declare
  v_pay jsonb;
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());

  perform pg_temp.conv_txt('CONV-13c', 'alcance del vendedor fuera del roster', 'propio', v_pay->>'alcance');
  perform pg_temp.conv_txt('CONV-13c', 'cobertura.medible',            'false', v_pay #>> '{cobertura,medible}');
  perform pg_temp.conv_txt('CONV-13c', 'cobertura.motivo_no_medible',
    'supervisor_no_es_supervisor', v_pay #>> '{cobertura,motivo_no_medible}');
  perform pg_temp.conv_num('CONV-13c', 'responsables', 0, jsonb_array_length(v_pay->'responsables'));
  -- Sus cifras siguen contadas, en su propio agregado.
  perform pg_temp.conv_num('CONV-13c', 'fuera_de_roster.divisor', 2,
    (v_pay #>> '{cobertura,fuera_de_roster,divisor}')::numeric);
  perform pg_temp.conv_num('CONV-13c', 'fuera_de_roster.cierres', 1,
    (v_pay #>> '{cobertura,fuera_de_roster,cierres}')::numeric);
end;
$test$;
select set_config('request.jwt.claim.sub', pg_temp.conv_lead(1)::text, true);

-- ── CONV-14b · la sonda ─────────────────────────────────────────────────────
-- El cierre existe en la ficha y no en la ventana del ledger. NO se corrige el
-- numerador con esto: se DECLARA, porque un informe que se auto-parchea es un
-- informe que no se puede auditar.
do $test$
declare
  v_pay jsonb;
  f jsonb;
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());

  perform pg_temp.conv_num('CONV-14b', 'cobertura.cierres_sin_episodio', 1,
    (v_pay #>> '{cobertura,cierres_sin_episodio}')::numeric);

  f := pg_temp.conv_fila('CONV-14b', v_pay, pg_temp.conv_lead(16));
  perform pg_temp.conv_num('CONV-14b', 'numerador de SEP', 0, (f->>'numerador')::numeric);
  perform pg_temp.conv_num('CONV-14b', 'cierres de SEP', 0,
    (f->>'cierres_no_referidos')::numeric + (f->>'cierres_referidos')::numeric);
  perform pg_temp.conv_txt('CONV-14b', 'estado de SEP', 'sin_actividad', f->>'estado');

  -- Y no se lo apuntó nadie más: el numerador del ámbito sigue siendo el mismo.
  perform pg_temp.conv_num('CONV-14b', 'total.numerador (el cierre huerfano no suma)',
    31.55, (v_pay #>> '{total,numerador}')::numeric);
end;
$test$;

-- ── CONV-15 · un mes futuro no es «todavía sin datos» ───────────────────────
-- Es una pregunta sin sentido. Sin este corte devolvería ceros para todos, que
-- es exactamente el payload que esta pantalla no puede emitir.
do $test$
declare
  v_futuro date := (pg_temp.conv_mes() + interval '1 month')::date;
begin
  perform pg_temp.conv_caso('CONV-15');
  begin
    perform crm.conversion_mensual_fn(v_futuro);
    raise exception 'CENTINELA CONV-15 el mes futuro no fue rechazado';
  exception
    when sqlstate '22023' then
      null; -- correcto
    when others then
      if sqlerrm like 'CENTINELA CONV-15%' then
        raise exception 'CONV-15 · mes futuro (%): ESPERADO error 22023 · OBTENIDO un payload', v_futuro;
      end if;
      raise exception 'CONV-15 · mes futuro (%): ESPERADO sqlstate 22023 · OBTENIDO % (%)',
        v_futuro, sqlstate, sqlerrm;
  end;
end;
$test$;

-- ── CONV-16 · el total cuadra con la suma, campo a campo ────────────────────
-- `total` se RECALCULA como sum(numerador)/sum(divisor); no es la media de los
-- porcentajes de las filas, que daría un número que no corresponde a ningún lead
-- real. Se comprueban las dos cosas: que CUADRE con el desglose y que valga lo
-- que el fixture dice — un cuadre entre dos ceros también «cuadra».
--
-- El orden de los bloques NO es cosmético: los absolutos van ANTES de la
-- comparación de porcentajes porque esa comparación divide por el divisor. Con
-- el divisor en 0 —que es justo el síntoma de que el escritor del ledger no
-- corrió, el fallo mudo que este fichero existe para cazar— la división mataría
-- el fichero con un `division by zero` crudo, sin código CONV-xx, sin ESPERADO y
-- sin OBTENIDO. La división lleva además su propio guard.
do $test$
declare
  v_pay jsonb;
  t jsonb;
  v_n         bigint;
  v_divisor   numeric;
  v_cie_nr    numeric;
  v_cie_ref   numeric;
  v_arrastre  numeric;
  v_recibidos numeric;
  v_numerador numeric;
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());
  t := v_pay->'total';

  -- (a) los valores absolutos del fixture, PRIMERO
  perform pg_temp.conv_num('CONV-16', 'total.analistas (fixture)',            17,     (t->>'analistas')::numeric);
  perform pg_temp.conv_num('CONV-16', 'total.divisor (fixture)',              115,    (t->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-16', 'total.cierres_no_referidos (fixture)', 29,     (t->>'cierres_no_referidos')::numeric);
  perform pg_temp.conv_num('CONV-16', 'total.cierres_referidos (fixture)',    17,     (t->>'cierres_referidos')::numeric);
  -- 4 de ARR + 2 de FLO + 2 de BORDE + 1 de PRO. Es, junto con
  -- `referidos_aporta_pct`, uno de los DOS sumandos que la migración A publica en
  -- `total` para que un porcentaje por encima de 100 se pueda reconstruir; hasta
  -- este ciclo ninguno de los dos tenía una sola aserción en todo el oráculo.
  perform pg_temp.conv_num('CONV-16', 'total.cierres_de_arrastre (fixture)',  9,      (t->>'cierres_de_arrastre')::numeric);
  perform pg_temp.conv_num('CONV-16', 'total.referidos_recibidos (fixture)',  31,     (t->>'referidos_recibidos')::numeric);
  perform pg_temp.conv_num('CONV-16', 'total.numerador (fixture)',            31.55,  (t->>'numerador')::numeric);
  perform pg_temp.conv_num('CONV-16', 'total.conversion_pct (fixture)',       27.43,  (t->>'conversion_pct')::numeric);
  -- 100 × 0,15 × 17 / 115 = 2,2173… → 2,22. Cuántos PUNTOS de los 27,43 los pone
  -- el 15 % de los referidos.
  perform pg_temp.conv_num('CONV-16', 'total.referidos_aporta_pct (fixture)',  2.22,  (t->>'referidos_aporta_pct')::numeric);

  -- (b) y el cuadre exacto contra el desglose
  select
    count(*),
    sum((el.value->>'divisor')::numeric),
    sum((el.value->>'cierres_no_referidos')::numeric),
    sum((el.value->>'cierres_referidos')::numeric),
    sum((el.value->>'cierres_de_arrastre')::numeric),
    sum((el.value #>> '{referidos,recibidos}')::numeric),
    sum((el.value->>'numerador')::numeric)
  into v_n, v_divisor, v_cie_nr, v_cie_ref, v_arrastre, v_recibidos, v_numerador
  from jsonb_array_elements(v_pay->'responsables') el;

  perform pg_temp.conv_num('CONV-16', 'total.analistas vs responsables',            v_n,         (t->>'analistas')::numeric);
  perform pg_temp.conv_num('CONV-16', 'total.divisor vs suma',                      v_divisor,   (t->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-16', 'total.cierres_no_referidos vs suma',         v_cie_nr,    (t->>'cierres_no_referidos')::numeric);
  perform pg_temp.conv_num('CONV-16', 'total.cierres_referidos vs suma',            v_cie_ref,   (t->>'cierres_referidos')::numeric);
  perform pg_temp.conv_num('CONV-16', 'total.cierres_de_arrastre vs suma',          v_arrastre,  (t->>'cierres_de_arrastre')::numeric);
  perform pg_temp.conv_num('CONV-16', 'total.referidos_recibidos vs suma',          v_recibidos, (t->>'referidos_recibidos')::numeric);
  perform pg_temp.conv_num('CONV-16', 'total.numerador vs suma',                    v_numerador, (t->>'numerador')::numeric);
  perform pg_temp.conv_num('CONV-16', 'total.conversion_pct vs sum(num)/sum(div)',
    case when coalesce(v_divisor, 0) > 0 then round(100.0 * v_numerador / v_divisor, 2) end,
    (t->>'conversion_pct')::numeric);
  perform pg_temp.conv_num('CONV-16', 'total.referidos_aporta_pct vs 0,15 x sum(cie_ref)/sum(div)',
    case when coalesce(v_divisor, 0) > 0
         then round(100.0 * (v_pay #>> '{ponderacion,referido}')::numeric * v_cie_ref / v_divisor, 2) end,
    (t->>'referidos_aporta_pct')::numeric);

  -- (c) el contrato fail-closed que el front verifica con `v.literal`
  perform pg_temp.conv_txt('CONV-16', 'alcance', 'equipo', v_pay->>'alcance');
  perform pg_temp.conv_txt('CONV-16', 'fuentes.divisor',   'crm.lead_asignaciones.asignado_en', v_pay #>> '{fuentes,divisor}');
  perform pg_temp.conv_txt('CONV-16', 'fuentes.numerador', 'crm.lead_asignaciones.resultado_en', v_pay #>> '{fuentes,numerador}');
  perform pg_temp.conv_txt('CONV-16', 'fuentes.referido',  'crm.lead_asignaciones.origen', v_pay #>> '{fuentes,referido}');
  perform pg_temp.conv_txt('CONV-16', 'periodo.mes', to_char(pg_temp.conv_mes(), 'YYYY-MM'), v_pay #>> '{periodo,mes}');
end;
$test$;

-- ── CONV-16b · el divisor aproximado cuenta lo que se sembró ────────────────
-- Hoy `aproximado = true` no existe en producción (0 filas). Un test que solo
-- comprobara `divisor_aproximado = 0` estaría en verde para siempre sin ejecutar
-- una línea del contador. Aquí hay una fila sembrada y el contador tiene que
-- verla — y verla SOLO una vez.
-- El desglose por persona NO se asevera: la RPC solo emite `divisor_aproximado`
-- en `cobertura`, no en la fila del responsable.
do $test$
declare
  v_pay jsonb;
  f jsonb;
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());

  perform pg_temp.conv_num('CONV-16b', 'cobertura.divisor_aproximado', 1,
    (v_pay #>> '{cobertura,divisor_aproximado}')::numeric);

  f := pg_temp.conv_fila('CONV-16b', v_pay, pg_temp.conv_lead(17));
  perform pg_temp.conv_num('CONV-16b', 'divisor de APR', 1, (f->>'divisor')::numeric);
  -- El episodio aproximado sigue pesando en el divisor normal: `aproximado`
  -- califica el dato, no lo excluye. Un 0,00 aquí (y no un NULL) es la prueba.
  perform pg_temp.conv_num('CONV-16b', 'conversion_pct de APR', 0.00, (f->>'conversion_pct')::numeric);
  perform pg_temp.conv_txt('CONV-16b', 'estado de APR', 'medible', f->>'estado');
end;
$test$;

-- ── CONV-21b · las CUATRO fronteras del mes, en hora de Lima ────────────────
-- El resto del fixture vive a quince días de cualquier borde: si la ventana se
-- corriera un segundo, un día o cinco horas —el desfase exacto entre UTC y
-- Lima—, TODOS los demás casos seguirían en verde. Esta es la única fila del
-- payload que se mueve, y por eso es la única que puede cazarlo.
--
-- Ocho leads, cuatro instantes, dos relojes:
--   divisor   (`asignado_en`)  1401 fuera · 1402 dentro · 1403 dentro · 1404 fuera
--   numerador (`resultado_en`) 1405 fuera · 1408 dentro · 1406 dentro · 1407 fuera
-- Los dos «fuera» de cada reloj están a UN SEGUNDO de la ventana y los dos
-- «dentro» también: 2 y 2 solo puede salir si los cuatro límites se evalúan como
-- [ini, fin) en América/Lima. Un `<=` arriba daría 3 cierres; un `>` abajo, 1.
do $test$
declare
  v_pay jsonb;
  f jsonb;
  p jsonb;
  v_ant date := pg_temp.conv_mes_anterior();
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());
  f := pg_temp.conv_fila('CONV-21b', v_pay, pg_temp.conv_lead(22));

  perform pg_temp.conv_num('CONV-21b', 'divisor de BORDE (v_ini y v_fin-1s, ni el de antes ni el de despues)',
    2, (f->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-21b', 'cierres no referidos de BORDE (resultado_en en v_ini y en v_fin-1s)',
    2, (f->>'cierres_no_referidos')::numeric);
  perform pg_temp.conv_num('CONV-21b', 'cierres referidos de BORDE', 0, (f->>'cierres_referidos')::numeric);
  perform pg_temp.conv_num('CONV-21b', 'numerador de BORDE', 2, (f->>'numerador')::numeric);
  perform pg_temp.conv_num('CONV-21b', 'conversion_pct de BORDE', 100.00, (f->>'conversion_pct')::numeric);
  perform pg_temp.conv_txt('CONV-21b', 'estado de BORDE', 'medible', f->>'estado');
  -- Los dos cierres que entran fueron recibidos DOS SEGUNDOS antes del mes, así
  -- que los dos son de arrastre. Si la frontera del divisor se hubiera corrido,
  -- este 2 se caería a 0 al mismo tiempo que el cubo de procedencia cambiaba de
  -- mes: son dos lecturas del mismo hecho por caminos distintos del payload.
  perform pg_temp.conv_num('CONV-21b', 'cierres_de_arrastre de BORDE', 2,
    (f->>'cierres_de_arrastre')::numeric);

  -- (El desglose por motivo no viaja en la fila del responsable —solo en
  -- `cobertura`—, así que las dos altas de BORDE se comprueban dentro del 113 de
  -- `ingreso` que asevera CONV-02, no aquí.)

  -- Y los dos cierres que SÍ entran vienen los dos del mes pasado (su
  -- `asignado_en` está dos segundos antes del inicio del mes): un solo cubo de
  -- procedencia con 2. Si la frontera del divisor se hubiera corrido, estos dos
  -- cierres se habrían fechado en el mes en curso y el cubo sería otro.
  p := f->'procedencia';
  perform pg_temp.conv_num('CONV-21b', 'cubos de procedencia de BORDE', 1, jsonb_array_length(p));
  perform pg_temp.conv_txt('CONV-21b', 'procedencia[0].mes de BORDE', to_char(v_ant, 'YYYY-MM'), p->0->>'mes');
  perform pg_temp.conv_num('CONV-21b', 'procedencia[0].cierres de BORDE', 2, (p->0->>'cierres')::numeric);
end;
$test$;

-- ── CONV-17 · el contrato de DENEGACIÓN, con sesión válida ──────────────────
-- Es lo único que la migración declara «fijado ANTES que los tests», y hasta
-- aquí no lo probaba nadie: el postflight solo cubre el caso SIN sesión y
-- `test-rls.mjs` no tiene ni un caso de esta RPC. El gate es una ALLOWLIST a
-- propósito y NO el `rol_crm is not null` de `cumplimiento_metas_fn`, que dejaría
-- pasar al COORDINADOR. Un `create or replace` que copiase el gate de la función
-- hermana devolvería a un coordinador el payload entero del ámbito, y sin este
-- caso nadie se enteraría.
select set_config('request.jwt.claim.sub', pg_temp.conv_lead(21)::text, true);
do $test$
declare
  v_mes date := pg_temp.conv_mes();
  -- Periodo inválido: mitad de mes. Se calcula, no se fija: una constante aquí
  -- envejecería igual que las que este fichero se prohíbe.
  v_basura date := (pg_temp.conv_mes() + interval '14 days')::date;
begin
  perform pg_temp.conv_caso('CONV-17a');
  perform pg_temp.conv_caso('CONV-17b');
  -- CONV-17a · coordinador → 42501 duro. Nunca un payload de ceros: un cero se
  -- leería como «0 % de conversión».
  begin
    perform crm.conversion_mensual_fn(v_mes);
    raise exception 'CENTINELA CONV-17a el coordinador no fue denegado';
  exception
    when sqlstate '42501' then
      null; -- correcto
    when others then
      if sqlerrm like 'CENTINELA CONV-17a%' then
        raise exception 'CONV-17a · coordinador: ESPERADO error 42501 · OBTENIDO un payload';
      end if;
      raise exception 'CONV-17a · coordinador: ESPERADO sqlstate 42501 · OBTENIDO % (%)', sqlstate, sqlerrm;
  end;

  -- CONV-17b · PRECEDENCIA: gate ANTES que periodo. Con un periodo basura el
  -- error tiene que seguir siendo 42501 y no 22023, para que el código de error
  -- no funcione como oráculo de pertenencia.
  begin
    perform crm.conversion_mensual_fn(v_basura);
    raise exception 'CENTINELA CONV-17b el coordinador no fue denegado con periodo basura';
  exception
    when sqlstate '42501' then
      null; -- correcto
    when sqlstate '22023' then
      raise exception 'CONV-17b · coordinador con periodo basura (%): ESPERADO sqlstate 42501 (gate primero) · OBTENIDO 22023 (el periodo se valido antes del gate)', v_basura;
    when others then
      if sqlerrm like 'CENTINELA CONV-17b%' then
        raise exception 'CONV-17b · coordinador con periodo basura (%): ESPERADO error 42501 · OBTENIDO un payload', v_basura;
      end if;
      raise exception 'CONV-17b · coordinador con periodo basura (%): ESPERADO sqlstate 42501 · OBTENIDO % (%)',
        v_basura, sqlstate, sqlerrm;
  end;
end;
$test$;

-- CONV-17c · ajeno al CRM: un perfil del portal sin membresía en `crm.equipo`.
-- Es el caso de [[crm-p04-revocado-vs-ajeno]]: `rol_crm` devuelve NULL y el gate
-- tiene que morir igual de duro que con el coordinador.
select set_config('request.jwt.claim.sub', pg_temp.conv_lead(19)::text, true);
do $test$
begin
  perform pg_temp.conv_caso('CONV-17c');
  begin
    perform crm.conversion_mensual_fn(pg_temp.conv_mes());
    raise exception 'CENTINELA CONV-17c el perfil ajeno al CRM no fue denegado';
  exception
    when sqlstate '42501' then
      null; -- correcto
    when others then
      if sqlerrm like 'CENTINELA CONV-17c%' then
        raise exception 'CONV-17c · perfil ajeno al CRM: ESPERADO error 42501 · OBTENIDO un payload';
      end if;
      raise exception 'CONV-17c · perfil ajeno al CRM: ESPERADO sqlstate 42501 · OBTENIDO % (%)', sqlstate, sqlerrm;
  end;
end;
$test$;
select set_config('request.jwt.claim.sub', pg_temp.conv_lead(1)::text, true);

-- ── CONV-18 · los otros dos alcances ────────────────────────────────────────
-- Hasta aquí, 'propio' solo se había probado en su forma DEGENERADA (CONV-13c,
-- el excluido del roster, cuyo payload correcto es el vacío) y 'global' no se
-- había pedido nunca. Son ramas distintas del mismo `case` (`v_global`,
-- `v_alcance`, `v_visibles`) y las viven 16 de las 17 personas reales.

-- CONV-18a · un vendedor NORMAL pide lo suyo: una sola fila, la suya, y un
-- `total` recalculado sobre el ámbito recortado — no sobre la empresa.
select set_config('request.jwt.claim.sub', pg_temp.conv_lead(7)::text, true);
do $test$
declare
  v_pay jsonb;
  v_sup jsonb;
  f jsonb;
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());

  perform pg_temp.conv_txt('CONV-18a', 'alcance de ANA', 'propio', v_pay->>'alcance');
  perform pg_temp.conv_num('CONV-18a', 'responsables de ANA (solo ella)', 1,
    jsonb_array_length(v_pay->'responsables'));

  f := pg_temp.conv_fila('CONV-18a', v_pay, pg_temp.conv_lead(7));
  perform pg_temp.conv_num('CONV-18a', 'divisor de ANA en su propio payload',   90, (f->>'divisor')::numeric);
  perform pg_temp.conv_num('CONV-18a', 'numerador de ANA en su propio payload', 17.80, (f->>'numerador')::numeric);

  -- Lo que de verdad prueba el recorte: el TOTAL es el suyo, no el del equipo.
  perform pg_temp.conv_num('CONV-18a', 'total.analistas de ANA', 1, (v_pay #>> '{total,analistas}')::numeric);
  perform pg_temp.conv_num('CONV-18a', 'total.divisor de ANA (90, no 115)', 90,
    (v_pay #>> '{total,divisor}')::numeric);
  perform pg_temp.conv_num('CONV-18a', 'fuera_de_roster.analistas de ANA', 0,
    (v_pay #>> '{cobertura,fuera_de_roster,analistas}')::numeric);

  -- Y como está EN el roster, la rama 5b no se dispara: su cobertura es la del
  -- ledger, no la de la exclusión. Es el contraste exacto con CONV-13c.
  perform pg_temp.conv_txt('CONV-18a', 'cobertura.medible de ANA', 'true',
    v_pay #>> '{cobertura,medible}');
  perform pg_temp.conv_txt('CONV-18a', 'tipo json de motivo_no_medible de ANA', 'null',
    jsonb_typeof(v_pay #> '{cobertura,motivo_no_medible}'));

  -- `suelo_historico` es la ÚNICA clave que no se recorta por ámbito, y tiene que
  -- decir lo mismo mire quien mire: si se recortara, el vendedor y el supervisor
  -- contarían meses distintos como medibles.
  perform set_config('request.jwt.claim.sub', pg_temp.conv_lead(1)::text, true);
  v_sup := crm.conversion_mensual_fn(pg_temp.conv_mes());
  perform pg_temp.conv_txt('CONV-18a', 'cobertura.suelo_historico (vendedor vs supervisor)',
    v_sup #>> '{cobertura,suelo_historico}', v_pay #>> '{cobertura,suelo_historico}');
end;
$test$;

-- CONV-18b · gerencia ve la EMPRESA. Aquí los absolutos serían frágiles (entra
-- también el roster del seed de demo), así que se asevera con cotas: lo que el
-- fixture aporta tiene que seguir estando dentro.
select set_config('request.jwt.claim.sub', pg_temp.conv_lead(20)::text, true);
do $test$
declare
  v_pay jsonb;
begin
  v_pay := crm.conversion_mensual_fn(pg_temp.conv_mes());

  perform pg_temp.conv_txt('CONV-18b', 'alcance de GERENCIA', 'global', v_pay->>'alcance');
  -- 17 del roster del fixture como MÍNIMO; el seed puede sumar más.
  perform pg_temp.conv_min('CONV-18b', 'total.analistas', 17, (v_pay #>> '{total,analistas}')::numeric);
  perform pg_temp.conv_min('CONV-18b', 'total.divisor', 115, (v_pay #>> '{total,divisor}')::numeric);
  perform pg_temp.conv_min('CONV-18b', 'total.numerador', 31.55, (v_pay #>> '{total,numerador}')::numeric);
  -- FUE sigue fuera del roster también para gerencia: el roster es uno solo.
  perform pg_temp.conv_min('CONV-18b', 'fuera_de_roster.divisor', 2,
    (v_pay #>> '{cobertura,fuera_de_roster,divisor}')::numeric);
  perform pg_temp.conv_min('CONV-18b', 'cobertura.cierres_sin_episodio', 1,
    (v_pay #>> '{cobertura,cierres_sin_episodio}')::numeric);
  if exists (
    select 1 from jsonb_array_elements(v_pay->'responsables') el
    where (el.value->>'vendedor_id')::uuid = pg_temp.conv_lead(18)
  ) then
    raise exception 'CONV-18b · responsables (global): ESPERADO sin la fila de FUE · OBTENIDO con su identidad publicada';
  end if;
end;
$test$;
select set_config('request.jwt.claim.sub', pg_temp.conv_lead(1)::text, true);

reset role;

-- ---------------------------------------------------------------------------
-- 7. Los dos agujeros del ledger, cerrados en el ALMACENAMIENTO
-- ---------------------------------------------------------------------------
-- Estos dos casos NO prueban la métrica: prueban que el estado que la rompía es
-- INEXPRESABLE. Y por eso se escriben con los triggers de usuario del ledger
-- DORMIDOS (`disable trigger user`), que es la única forma honesta de probarlo:
-- la garantía que hoy sostiene el guard —código— desaparece con un `alter table
-- ... disable trigger` o dentro de un backfill privilegiado, y ese patrón ya se
-- usó sobre esta misma tabla (20260807203757:747-748). Un CHECK y un índice
-- único sobreviven a los dos, porque viven en el ALMACENAMIENTO.
--
-- Cada rechazo va con su CONTROL POSITIVO. Un test que solo comprueba que algo
-- falla no distingue «la base defiende la regla» de «esa fila no entraba de
-- ninguna manera»: si el control positivo no fuera ACEPTADO, los rechazos de al
-- lado no probarían nada. `pg_temp.conv_intento` deshace las tres cosas.
alter table crm.lead_asignaciones disable trigger user;

-- ── CONV-19 · el CIERRE SIN FECHA ───────────────────────────────────────────
-- La rama `convertido` del CHECK exigía `resultado = 'convertido' and
-- resultado_en = finalizado_en`. Con `resultado_en` NULL esa igualdad da NULL,
-- la rama da NULL, el OR da NULL... y el CHECK PASA, porque un CHECK solo
-- rechaza en FALSE. La fila que entraba por ahí era un cierre INVISIBLE: el
-- numerador filtra por `resultado_en >= v_ini`, así que un lead convertido de
-- verdad salía como 0 % con divisor 1 — y nadie podía verlo en pantalla, porque
-- la ficha decía «convertido».
--
-- La VARIANTE 2 (19b) es la que un arreglo a medias deja viva: `motivo_cierre =
-- 'convertido'` con `resultado` NULL. Ese cierre es invisible incluso para un
-- índice que solo mirase `resultado`, y por eso el predicado del índice de
-- CONV-20 mira las DOS columnas.
do $test$
begin
  -- 19a · resultado sin fecha.
  perform pg_temp.conv_txt('CONV-19a',
    'sqlstate al insertar resultado=convertido con resultado_en NULL',
    '23514',
    pg_temp.conv_intento($i$
      insert into crm.lead_asignaciones (
        lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en,
        moneda, origen, sla_global_iniciado_en, sla_politica_asignacion_id,
        primera_gestion_limite_en, primer_contacto_limite_en,
        finalizado_en, motivo_cierre, resultado, resultado_en)
      select
        pg_temp.conv_lead(1391), 1, 1, m.analista_id, 'ingreso', m.asignado_en,
        m.moneda, m.origen, m.asignado_en, m.sla_politica_asignacion_id,
        m.asignado_en + interval '1 hour', m.asignado_en + interval '2 hours',
        m.finalizado_en, 'convertido', 'convertido', null
      from crm.lead_asignaciones m
      where m.lead_id = pg_temp.conv_lead(1331)
    $i$));

  -- 19b · motivo de cierre sin resultado (ni fecha).
  perform pg_temp.conv_txt('CONV-19b',
    'sqlstate al insertar motivo_cierre=convertido con resultado NULL',
    '23514',
    pg_temp.conv_intento($i$
      insert into crm.lead_asignaciones (
        lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en,
        moneda, origen, sla_global_iniciado_en, sla_politica_asignacion_id,
        primera_gestion_limite_en, primer_contacto_limite_en,
        finalizado_en, motivo_cierre, resultado, resultado_en)
      select
        pg_temp.conv_lead(1391), 1, 1, m.analista_id, 'ingreso', m.asignado_en,
        m.moneda, m.origen, m.asignado_en, m.sla_politica_asignacion_id,
        m.asignado_en + interval '1 hour', m.asignado_en + interval '2 hours',
        m.finalizado_en, 'convertido', null, null
      from crm.lead_asignaciones m
      where m.lead_id = pg_temp.conv_lead(1331)
    $i$));

  -- 19c · CONTROL POSITIVO: la MISMA fila, bien formada, entra. Sin este caso,
  -- los dos de arriba estarían en verde aunque la tabla rechazara cualquier
  -- inserción por un motivo que no tiene nada que ver con el agujero.
  perform pg_temp.conv_txt('CONV-19c',
    'la misma fila con resultado_en = finalizado_en',
    'ACEPTADO',
    pg_temp.conv_intento($i$
      insert into crm.lead_asignaciones (
        lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en,
        moneda, origen, sla_global_iniciado_en, sla_politica_asignacion_id,
        primera_gestion_limite_en, primer_contacto_limite_en,
        finalizado_en, motivo_cierre, resultado, resultado_en)
      select
        pg_temp.conv_lead(1391), 1, 1, m.analista_id, 'ingreso', m.asignado_en,
        m.moneda, m.origen, m.asignado_en, m.sla_politica_asignacion_id,
        m.asignado_en + interval '1 hour', m.asignado_en + interval '2 hours',
        m.finalizado_en, 'convertido', 'convertido', m.finalizado_en
      from crm.lead_asignaciones m
      where m.lead_id = pg_temp.conv_lead(1331)
    $i$));
end;
$test$;

-- ── CONV-20 · el CIERRE CONTADO DOS VECES ───────────────────────────────────
-- El EXCLUDE `lead_asignaciones_sin_solape` compara `tstzrange(asignado_en,
-- coalesce(finalizado_en,'infinity'), '[)')`. Dos episodios ADYACENTES —[10:00,
-- 11:00) y [11:00, 12:00)— no se solapan, y un episodio de duración CERO es un
-- rango VACÍO, que no se solapa con nada. Por las dos puertas cabían dos cierres
-- `convertido` del mismo lead, y `agg_cie` los cuenta con `count(*)`: 2 cierres
-- para 1 lead recibido son 200 % con divisor 1.
--
-- Lo que hay que escribir NO es «prohibir la duración cero» (esos episodios son
-- papeleo legítimo: `statement_timestamp()` es constante dentro de una función,
-- así que una RPC que mueve la tenencia dos veces abre y cierra en el mismo
-- instante) ni «cerrar el rango por la derecha» (haría chocar dos episodios
-- consecutivos legítimos en su instante de relevo). Lo que hay que escribir es
-- la regla de negocio que faltaba: UN LEAD SE CONVIERTE UNA SOLA VEZ.
do $test$
declare
  v_indice text;
  v_attnum smallint;
begin
  perform pg_temp.conv_caso('CONV-20');

  -- PRECONDICIÓN. Se busca por FORMA y no por nombre —un `create index` futuro
  -- puede rebautizarlo—, pero la forma que se exige es la EXACTA: índice único,
  -- parcial, con predicado que hable de «convertido» y con la clave en UNA sola
  -- columna, que además tiene que ser `lead_id`.
  --
  -- Lo de la clave no es puntillismo. Hasta este ciclo la precondición decía
  -- solo «un índice único parcial que mencione convertido», y con esa vara las
  -- DOS variantes que la migración C declara insuficientes —`(lead_id, ciclo_n)`
  -- y `(lead_id, analista_id)`— pasaban igual, mientras 20a-20d salían idénticos
  -- con las tres (copian `ciclo_n` y `analista_id` de la fila que ya existe, así
  -- que cualquiera de las tres claves las rechaza). La suite entera podía quedar
  -- en verde sobre el índice equivocado, y con él vivo seguía siendo expresable
  -- justo el escenario que la migración C existe para matar: un lead convertido
  -- en el ciclo 1 y otra vez en el ciclo 2, cerrado por analistas distintos, que
  -- suma 1 + 1 en `total` porque el `count(distinct lead_id)` de la migración A
  -- agrupa POR ANALISTA — lo dice su propio comentario: «eso NO se arregla
  -- aquí». 200 % con divisor 1, que es el agujero 2 tal cual.
  --
  -- Ojo con no colar `lead_asignaciones_un_abierto_por_lead_idx`, que también es
  -- único, parcial y sobre `(lead_id)`: su predicado es `finalizado_en is null`
  -- y por eso el filtro de «convertido» sigue haciendo falta además del resto.
  select a.attnum into v_attnum
  from pg_catalog.pg_attribute a
  where a.attrelid = 'crm.lead_asignaciones'::regclass and a.attname = 'lead_id';

  select string_agg(c.relname, ', ' order by c.relname) into v_indice
  from pg_catalog.pg_index i
  join pg_catalog.pg_class c on c.oid = i.indexrelid
  where i.indrelid = 'crm.lead_asignaciones'::regclass
    and i.indisunique
    and i.indpred is not null
    and pg_catalog.pg_get_expr(i.indpred, i.indrelid) like '%convertido%'
    and i.indnkeyatts = 1
    and i.indnatts = 1
    and i.indkey[0] = v_attnum;
  if v_indice is null then
    raise exception 'CONV-20 · PRECONDICION: ESPERADO un indice UNICO PARCIAL sobre crm.lead_asignaciones con la clave EXACTAMENTE en (lead_id) y predicado que hable de «convertido» (el que hace inexpresable la segunda conversion de un lead) · OBTENIDO ninguno. Indices unicos parciales presentes: %. Una clave (lead_id, ciclo_n) o (lead_id, analista_id) NO vale: deja pasar el mismo lead convertido dos veces en ciclos distintos o por analistas distintos, que es el agujero 2 entero.',
      coalesce((
        select string_agg(c2.relname || ' -> ' || pg_catalog.pg_get_indexdef(i2.indexrelid), ' | '
                          order by c2.relname)
        from pg_catalog.pg_index i2
        join pg_catalog.pg_class c2 on c2.oid = i2.indexrelid
        where i2.indrelid = 'crm.lead_asignaciones'::regclass
          and i2.indisunique and i2.indpred is not null
      ), '(ninguno)');
  end if;

  -- 20a · segunda conversión ADYACENTE a la primera. Esta es la forma que el
  -- EXCLUDE deja pasar y la razón por la que endurecer `intervalo_valido` a `>`
  -- no habría cerrado nada.
  perform pg_temp.conv_txt('CONV-20a',
    'sqlstate al insertar una segunda conversion ADYACENTE del mismo lead',
    '23505',
    pg_temp.conv_intento($i$
      insert into crm.lead_asignaciones (
        lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en,
        moneda, origen, sla_global_iniciado_en, sla_politica_asignacion_id,
        primera_gestion_limite_en, primer_contacto_limite_en,
        finalizado_en, motivo_cierre, resultado, resultado_en)
      select
        m.lead_id, m.ciclo_n, m.episodio_n + 1, m.analista_id, 'reasignado', m.finalizado_en,
        m.moneda, m.origen, m.finalizado_en, m.sla_politica_asignacion_id,
        m.finalizado_en + interval '1 hour', m.finalizado_en + interval '2 hours',
        m.finalizado_en + interval '1 minute', 'convertido', 'convertido',
        m.finalizado_en + interval '1 minute'
      from crm.lead_asignaciones m
      where m.lead_id = pg_temp.conv_lead(1331)
    $i$));

  -- 20b · y la de DURACIÓN CERO, que el EXCLUDE tampoco ve porque un rango
  -- vacío no se solapa con nada.
  perform pg_temp.conv_txt('CONV-20b',
    'sqlstate al insertar una segunda conversion de duracion CERO del mismo lead',
    '23505',
    pg_temp.conv_intento($i$
      insert into crm.lead_asignaciones (
        lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en,
        moneda, origen, sla_global_iniciado_en, sla_politica_asignacion_id,
        primera_gestion_limite_en, primer_contacto_limite_en,
        finalizado_en, motivo_cierre, resultado, resultado_en)
      select
        m.lead_id, m.ciclo_n, m.episodio_n + 2, m.analista_id, 'reasignado',
        m.finalizado_en + interval '5 minutes',
        m.moneda, m.origen, m.finalizado_en + interval '5 minutes', m.sla_politica_asignacion_id,
        m.finalizado_en + interval '5 minutes', m.finalizado_en + interval '5 minutes',
        m.finalizado_en + interval '5 minutes', 'convertido', 'convertido',
        m.finalizado_en + interval '5 minutes'
      from crm.lead_asignaciones m
      where m.lead_id = pg_temp.conv_lead(1331)
    $i$));

  -- 20c · CONTROL POSITIVO 1: un lead se DESCARTA tantas veces como ciclos
  -- tenga. Si el índice se hubiera puesto sobre `resultado` a secas, este
  -- insert fallaría y el CRM se quedaría sin poder descartar dos veces el mismo
  -- lead — el circuito de `deshacer_descarte` entero.
  perform pg_temp.conv_txt('CONV-20c',
    'un SEGUNDO descarte del mismo lead sigue entrando',
    'ACEPTADO',
    pg_temp.conv_intento($i$
      insert into crm.lead_asignaciones (
        lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en,
        moneda, origen, sla_global_iniciado_en, sla_politica_asignacion_id,
        primera_gestion_limite_en, primer_contacto_limite_en,
        finalizado_en, motivo_cierre, resultado, resultado_en, motivo_descarte_cierre)
      select
        m.lead_id, m.ciclo_n + 1, 1, m.analista_id, 'reabierto', m.finalizado_en,
        m.moneda, m.origen, m.finalizado_en, m.sla_politica_asignacion_id,
        m.finalizado_en + interval '1 hour', m.finalizado_en + interval '2 hours',
        m.finalizado_en + interval '1 minute', 'descartado', 'descartado',
        m.finalizado_en + interval '1 minute', 'sin_interes'
      from crm.lead_asignaciones m
      where m.lead_id = pg_temp.conv_lead(1301)
    $i$));

  -- 20d · CONTROL POSITIVO 2: descartado en el ciclo 1 y CONVERTIDO en el 2.
  -- Es una sola conversión en toda la vida del lead, y tiene que caber.
  -- ⚠️ Este caso NO descarta la variante «único por (lead_id, ciclo_n)», aunque
  -- durante un ciclo el comentario dijo que sí: el lead 1301 no tiene ninguna
  -- conversión previa —solo un descarte—, así que sale ACEPTADO con las tres
  -- claves candidatas y no distingue nada. Lo que descarta las variantes débiles
  -- es 20e, aquí abajo. Este sigue valiendo por lo suyo: que reabrir y convertir
  -- después de un descarte no lo bloquee el índice nuevo.
  perform pg_temp.conv_txt('CONV-20d',
    'un descarte y DESPUES una conversion del mismo lead entran',
    'ACEPTADO',
    pg_temp.conv_intento($i$
      insert into crm.lead_asignaciones (
        lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en,
        moneda, origen, sla_global_iniciado_en, sla_politica_asignacion_id,
        primera_gestion_limite_en, primer_contacto_limite_en,
        finalizado_en, motivo_cierre, resultado, resultado_en)
      select
        m.lead_id, m.ciclo_n + 2, 1, m.analista_id, 'reabierto',
        m.finalizado_en + interval '5 minutes',
        m.moneda, m.origen, m.finalizado_en + interval '5 minutes', m.sla_politica_asignacion_id,
        m.finalizado_en + interval '1 hour', m.finalizado_en + interval '2 hours',
        m.finalizado_en + interval '6 minutes', 'convertido', 'convertido',
        m.finalizado_en + interval '6 minutes'
      from crm.lead_asignaciones m
      where m.lead_id = pg_temp.conv_lead(1301)
    $i$));

  -- 20e · EL CASO DISCRIMINANTE. Es el único de la familia que fija la FORMA de
  -- la clave, y sin él la precondición y los cuatro casos de arriba salían
  -- exactamente igual con `(lead_id)`, con `(lead_id, ciclo_n)` y con
  -- `(lead_id, analista_id)` — 20a y 20b copian de la fila existente TANTO
  -- `ciclo_n` COMO `analista_id`, así que las tres claves las rechazan.
  --
  -- Aquí el lead 1331 ya tiene su conversión (la de M1, ciclo 1) y se intenta
  -- una SEGUNDA en OTRO ciclo y por OTRO analista, en un intervalo que no solapa
  -- con nada. Repasando lo que queda vivo, uno por uno: `episodio_unico`
  -- (lead, ciclo, episodio) no choca porque el ciclo es otro; el EXCLUDE no
  -- choca porque el rango va diez minutos después del cierre anterior;
  -- `un_abierto_por_lead` no aplica porque la fila nace cerrada; los dos CHECK
  -- del cierre se cumplen (`resultado_en = finalizado_en`, sin destino, sin
  -- motivo de descarte) y los tres del SLA también. O sea: lo ÚNICO que puede
  -- rechazar esta fila es un índice único cuya clave sea `(lead_id)` a secas.
  -- Con `(lead_id, ciclo_n)` entraría —ciclo 4 contra ciclo 1— y con
  -- `(lead_id, analista_id)` también —M2 contra M1—, y en los dos casos este
  -- ACEPTADO haría fallar la aserción, que es justo lo que tiene que pasar.
  --
  -- Y ese escenario no es de laboratorio: dos cierres del mismo lead atribuidos
  -- a analistas distintos son precisamente los que el `count(distinct lead_id)`
  -- de la migración A no puede deduplicar, porque agrupa POR ANALISTA. Suman
  -- 1 + 1 en el total del equipo: 200 % con divisor 1.
  perform pg_temp.conv_txt('CONV-20e',
    'sqlstate al insertar una SEGUNDA conversion del mismo lead en OTRO ciclo y por OTRO analista',
    '23505',
    pg_temp.conv_intento($i$
      insert into crm.lead_asignaciones (
        lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en,
        moneda, origen, sla_global_iniciado_en, sla_politica_asignacion_id,
        primera_gestion_limite_en, primer_contacto_limite_en,
        finalizado_en, motivo_cierre, resultado, resultado_en)
      select
        m.lead_id, m.ciclo_n + 3, 1, pg_temp.conv_lead(14), 'reabierto',
        m.finalizado_en + interval '10 minutes',
        m.moneda, m.origen, m.finalizado_en + interval '10 minutes', m.sla_politica_asignacion_id,
        m.finalizado_en + interval '10 minutes', m.finalizado_en + interval '10 minutes',
        m.finalizado_en + interval '11 minutes', 'convertido', 'convertido',
        m.finalizado_en + interval '11 minutes'
      from crm.lead_asignaciones m
      where m.lead_id = pg_temp.conv_lead(1331)
    $i$));
end;
$test$;
alter table crm.lead_asignaciones enable trigger user;

-- ---------------------------------------------------------------------------
-- 8. CONV-22 · el sello del ORIGEN (migración D: 20260811190324)
-- ---------------------------------------------------------------------------
-- Aquí los triggers están otra vez VIVOS: al revés que la sección 7, este sello
-- ES código —un bloque dentro de `private.leads_before_update()`— y solo se
-- puede probar ejecutándolo.
--
-- ⚠️ CONTRA QUÉ MIGRACIÓN ESTÁ ESCRITA ESTA SECCIÓN, porque hubo dos.
-- La versión anterior de estos cuatro casos probaba
-- `20260811164017_crm_origen_inmutable_correccion_gerencia.sql`: 42501, ventana
-- de 24 h para que Gerencia corrigiera el origen, y un carve-out del ledger que
-- PROPAGABA la corrección al snapshot del episodio abierto. Miguel descartó ese
-- diseño el 2026-08-11 —«quedarse con la mitad simple»— y lo que se despliega es
-- `20260811190324_crm_origen_inmutable.sql`, que aparca la ventana de gerencia
-- entera. Los dos son mutuamente excluyentes: los preflights 0.2/0.3/0.4 de la D
-- abortan si la 164017 llegó a aplicarse, y su nota de aplicación manda BORRAR
-- ese fichero del árbol antes de crear el branch. O sea que no existía ningún
-- estado de la base en el que la versión vieja de esta sección pudiera pasar;
-- habría fallado en 22a por el SQLSTATE y muerto en 22c en el primer UPDATE.
--
-- Lo que la D hace, y es todo lo que hay que probar:
--   · si un UPDATE mueve `crm.leads.origen`, aborta con `P0409` —no 42501—;
--   · el bloque vive DENTRO de `if not v_priv`, así que el gate es la válvula
--     `crm.op_privilegiada` y NO el rol: Gerencia queda tan denegada como
--     cualquiera;
--   · la condición es `is distinct from`, así que reenviar el mismo valor pasa;
--   · y NO toca el ledger. Su propio postflight (5) compara el `count(*)` de
--     `crm.lead_asignaciones` antes y después y aborta si cambió.
--
-- Que el snapshot NO se mueva no es una carencia que haya que disimular: es la
-- tesis de la migración. El divisor y el numerador salen de
-- `crm.lead_asignaciones.origen`, que ya era inmutable antes de todo esto
-- (`trg_lead_asignaciones_00_inmutables`), así que un mes ya contado nunca
-- estuvo en riesgo. Lo que el sello protege es el FUTURO: el origen que
-- `private.trg_leads_asignaciones` copiará al abrir el PRÓXIMO episodio de este
-- lead. Por eso 22d asevera las dos mitades a la vez —ficha 'web', snapshot
-- 'landing'—: la asimetría ES el contrato, y un `create or replace` que
-- reintrodujera la propagación la rompería en silencio.
--
-- No hay WARNING que esperar en la salida de psql: eso era de la 164017.
--
-- Los sujetos son los dos leads de PRO, 1004 y 1005, los dos con su episodio
-- ABIERTO —lo que permite leer el snapshot— y ninguno de los dos convertido.
do $test$
declare
  v_origen text;
  v_snap   text;
begin
  -- 22a · el supervisor no lo mueve: P0409 duro, no un 200 mudo. Se avisa con
  -- excepción y no restaurando en silencio porque el store del front es
  -- optimista: un éxito callado dejaría al usuario convencido de que corrigió.
  perform pg_temp.conv_txt('CONV-22a',
    'sqlstate al cambiar el origen sin la valvula privilegiada',
    'P0409',
    pg_temp.conv_intento($i$
      update crm.leads set origen = 'web' where id = pg_temp.conv_lead(1004)
    $i$));

  -- 22b · pero REENVIAR el mismo valor no falla. Es la mitad que hace usable el
  -- sello: el drawer y `actualizarLead` mandan parches donde la columna puede
  -- viajar con su valor de siempre, y `seed-demo.mjs` y `test-rls.mjs` hacen
  -- exactamente eso. Si esto reventara, editar cualquier campo de un lead sería
  -- imposible. El bloque solo se dispara cuando el valor CAMBIA (`is distinct
  -- from`, no `<>`).
  perform pg_temp.conv_txt('CONV-22b',
    'reenviar el MISMO origen no lanza',
    'ACEPTADO',
    pg_temp.conv_intento($i$
      update crm.leads set origen = 'landing' where id = pg_temp.conv_lead(1004)
    $i$));

  -- 22c · Y GERENCIA TAMPOCO. Este es el caso que la D introduce y que nadie
  -- probaba: el sello no mira el rol, mira la válvula. Si alguien reintrodujera
  -- la ventana de 24 h de la migración descartada —o cualquier carve-out por
  -- rol—, todo lo demás de esta sección seguiría en verde y solo esta línea se
  -- pondría roja. Sigue siendo el 1004, que nació en esta misma transacción: si
  -- hubiera ventana de gracia por antigüedad, estaría dentro de ella.
  perform set_config('request.jwt.claim.sub', pg_temp.conv_lead(20)::text, true);
  perform pg_temp.conv_txt('CONV-22c',
    'sqlstate cuando quien mueve el origen es GERENCIA (no hay ventana de gerencia)',
    'P0409',
    pg_temp.conv_intento($i$
      update crm.leads set origen = 'web' where id = pg_temp.conv_lead(1004)
    $i$));
  perform set_config('request.jwt.claim.sub', pg_temp.conv_lead(1)::text, true);

  -- Y la ficha del 1004 no se movió ni un milímetro en los tres intentos.
  select l.origen into v_origen from crm.leads l where l.id = pg_temp.conv_lead(1004);
  perform pg_temp.conv_txt('CONV-22c', 'origen de la ficha tras los intentos denegados',
    'landing', v_origen);

  -- 22d · la ÚNICA vía de corrección: la válvula `crm.op_privilegiada`. Sin ella
  -- el dato quedaría incorregible para siempre y el único remedio sería
  -- `disable trigger` en producción, que CLAUDE.md prohíbe. Es la misma válvula
  -- que ya tienen `perfil_id`, `contrato_id` y `convertido_en`. Se prueba con el
  -- SUPERVISOR a propósito: la válvula no es un rol, y con un actor gerencial no
  -- se distinguiría de un carve-out por rol. Sobre el 1005 para no pisar al 1004.
  perform set_config('crm.op_privilegiada', 'on', true);
  update crm.leads set origen = 'web' where id = pg_temp.conv_lead(1005);
  perform set_config('crm.op_privilegiada', 'off', true);

  select l.origen into v_origen from crm.leads l where l.id = pg_temp.conv_lead(1005);
  perform pg_temp.conv_txt('CONV-22d', 'origen de la FICHA bajo crm.op_privilegiada',
    'web', v_origen);

  -- Y el SNAPSHOT del episodio abierto NO se mueve. Esta línea es la que fija la
  -- diferencia entre la migración desplegada y la descartada, y la que hay que
  -- cambiar el día que alguien decida propagar: hoy la corrección alcanza a la
  -- ficha (y con ella a `referidos.dados_de_alta` y al origen que heredará el
  -- PRÓXIMO episodio), y deja intacta la foto del episodio en curso, que es lo
  -- que la conversión del mes ya contado lee.
  select la.origen into v_snap
  from crm.lead_asignaciones la
  where la.lead_id = pg_temp.conv_lead(1005) and la.finalizado_en is null;
  perform pg_temp.conv_txt('CONV-22d',
    'origen del SNAPSHOT del episodio abierto (la D NO propaga)',
    'landing', v_snap);

  -- Y la válvula se cierra sola: el resto del fichero (y CONV-99) corre sin ella.
  perform pg_temp.conv_txt('CONV-22d', 'crm.op_privilegiada al salir',
    'off', coalesce(current_setting('crm.op_privilegiada', true), 'off'));
end;
$test$;

-- ---------------------------------------------------------------------------
-- 8bis. CONV-23 · la regla del ALTA (migración F: 20260811210049)
-- ---------------------------------------------------------------------------
-- D8 de Miguel (2026-08-11, literal): «referido, Wallking y OTRO esto puede
-- registrar el vendedor; landing y formulario se carga solo» + «[los referidos]
-- solo los vendedores a su propio nombre».
--
-- La F cierra la mitad del camino que la D no toca: la ELECCIÓN del origen al
-- nacer. Cuatro casos, dos denegaciones y dos positivos — y los positivos van
-- DIRECTO (sin `conv_intento`, que deshace): necesitan que el lead exista para
-- poder aseverar a quién quedó asignado y qué fotografió el ledger.
-- Van DESPUÉS de todas las lecturas del payload (secciones 5-6): los dos leads
-- nuevos no tocan ninguna cifra ya aseverada, y el `rollback` final los borra.
do $test$
declare
  v_resultado jsonb;
  v_msg text;
  v_estado text;
  v_vendedor_id uuid;
  v_creado_por uuid;
  v_origen text;
  v_snap text;
  v_episodios int;
begin
  -- 23a · ANA (vendedor) intenta declarar un canal AUTOMÁTICO a mano.
  -- El monto va NULL a propósito: si la regla dejara pasar el origen por error,
  -- el 22023 de «Capital estimado invalido» delataría el hueco aquí mismo, sin
  -- riesgo de que la sonda inserte nada.
  perform set_config('request.jwt.claim.sub', pg_temp.conv_lead(7)::text, true);
  begin
    perform crm.crear_lead_si_disponible(
      'CONV23A CANAL AUTOMATICO', pg_temp.conv_tel(1501), 'landing', null, 'PEN');
    v_estado := 'ACEPTADO'; v_msg := '';
  exception when others then
    v_estado := sqlstate; v_msg := sqlerrm;
  end;
  perform pg_temp.conv_txt('CONV-23a',
    'sqlstate del alta manual de un vendedor con origen landing', '42501', v_estado);
  perform pg_temp.conv_txt('CONV-23a', 'el rechazo nombra al puente', 'si',
    case when position('puente' in v_msg) > 0 then 'si' else 'no: ' || v_msg end);

  -- 23b · el SUPERVISOR intenta declarar un referido. «Solo los vendedores a su
  -- propio nombre»: el rol se corta en la F; el nombre ya lo cortaba el bloque
  -- de destino («Solo puedes crear leads asignados a ti mismo», que CONV-18
  -- deja ejercitado por la vía del ámbito).
  perform set_config('request.jwt.claim.sub', pg_temp.conv_lead(1)::text, true);
  begin
    perform crm.crear_lead_si_disponible(
      'CONV23B REFERIDO DE MANDO', pg_temp.conv_tel(1501), 'referido', null, 'PEN');
    v_estado := 'ACEPTADO'; v_msg := '';
  exception when others then
    v_estado := sqlstate; v_msg := sqlerrm;
  end;
  perform pg_temp.conv_txt('CONV-23b',
    'sqlstate del referido declarado por un supervisor', '42501', v_estado);
  perform pg_temp.conv_txt('CONV-23b', 'el rechazo dice a su propio nombre', 'si',
    case when position('propio nombre' in v_msg) > 0 then 'si' else 'no: ' || v_msg end);

  -- 23c · POSITIVO: ANA declara SU referido y queda autoasignada. Es el flujo
  -- que D8 protege, y de paso prueba que el ledger fotografía 'referido' en el
  -- episodio que abre — el snapshot del que T10 excluye el divisor.
  perform set_config('request.jwt.claim.sub', pg_temp.conv_lead(7)::text, true);
  v_resultado := crm.crear_lead_si_disponible(
    'CONV23C REFERIDO DE ANA', pg_temp.conv_tel(1501), 'referido', 1000, 'PEN',
    p_id => pg_temp.conv_lead(1501));
  perform pg_temp.conv_txt('CONV-23c', 'estado del alta',
    'creado', v_resultado ->> 'estado');

  select l.vendedor_id, l.creado_por, l.origen
    into v_vendedor_id, v_creado_por, v_origen
  from crm.leads l where l.id = pg_temp.conv_lead(1501);
  perform pg_temp.conv_txt('CONV-23c', 'el referido queda asignado a ANA (a su propio nombre)',
    pg_temp.conv_lead(7)::text, v_vendedor_id::text);
  perform pg_temp.conv_txt('CONV-23c', 'creado_por es la propia ANA',
    pg_temp.conv_lead(7)::text, v_creado_por::text);
  perform pg_temp.conv_txt('CONV-23c', 'origen de la ficha', 'referido', v_origen);

  select la.origen into v_snap
  from crm.lead_asignaciones la
  where la.lead_id = pg_temp.conv_lead(1501) and la.finalizado_en is null;
  perform pg_temp.conv_txt('CONV-23c', 'el episodio abierto fotografio referido',
    'referido', v_snap);

  -- 23d · POSITIVO: GERENCIA sigue pudiendo registrar un Wallking (oficina),
  -- sin destino → cola global, sin episodio. El trío manual no es solo del
  -- vendedor; lo exclusivo del vendedor es el REFERIDO.
  perform set_config('request.jwt.claim.sub', pg_temp.conv_lead(20)::text, true);
  v_resultado := crm.crear_lead_si_disponible(
    'CONV23D WALLKING DE GERENCIA', pg_temp.conv_tel(1502), 'oficina', 1000, 'PEN',
    p_id => pg_temp.conv_lead(1502));
  perform pg_temp.conv_txt('CONV-23d', 'estado del alta',
    'creado', v_resultado ->> 'estado');

  select l.vendedor_id into v_vendedor_id
  from crm.leads l where l.id = pg_temp.conv_lead(1502);
  perform pg_temp.conv_txt('CONV-23d', 'un Wallking de gerencia sin destino va a la cola global',
    '<null>', coalesce(v_vendedor_id::text, '<null>'));

  select count(*)::int into v_episodios
  from crm.lead_asignaciones la where la.lead_id = pg_temp.conv_lead(1502);
  perform pg_temp.conv_txt('CONV-23d', 'sin dueno no se abre episodio (no toca ningun divisor)',
    '0', v_episodios::text);

  -- La identidad vuelve a donde la dejó la sección 8 (el SUPERVISOR).
  perform set_config('request.jwt.claim.sub', pg_temp.conv_lead(1)::text, true);
end;
$test$;

-- ---------------------------------------------------------------------------
-- 8bis. CONV-24 · gerencia anula un cierre de AVANCE y la CONVERSIÓN se entera
-- ---------------------------------------------------------------------------
-- La regla de Miguel (2026-08-13): «si gerencia anula un cierre tiene que
-- afectar en la conversión sí o sí, porque gerencia hará eso cuando haya
-- errores de gestión o malas prácticas».
--
-- Va el ÚLTIMO de los casos de negocio a propósito: anula un cierre que los
-- casos anteriores ya midieron, así que ejecutarlo antes movería sus números.
--
-- Lo que de verdad prueba: que la anulación llega a la conversión por el
-- DELEGADO. `private.conversion_mensual_por_vendedor` llama a
-- `private.cierre_externo_anulado`, que desde la migración de anulación de
-- Avance delega en `private.cierre_anulado` — la pregunta única que responde
-- por los dos canales. Si alguien deshiciera esa delegación, la cuota seguiría
-- bajando y la conversión NO, y volveríamos a tener dos números para lo mismo.
-- Sin este caso, ese mecanismo no lo probaba nada.
do $test$
declare
  v_pay        jsonb;
  v_fila       jsonb;
  v_divisor    integer;
  v_cierres    integer;
  v_numerador  numeric;
begin
  -- Foto ANTES, del vendedor B (analista 3), que cerró el lead 1001 en el mes.
  perform set_config('request.jwt.claim.sub', pg_temp.conv_lead(20)::text, true);
  v_pay  := crm.conversion_mensual_fn(pg_temp.conv_mes());
  v_fila := pg_temp.conv_fila('CONV-24a', v_pay, pg_temp.conv_lead(3));
  v_divisor   := (v_fila ->> 'divisor')::integer;
  v_cierres   := (v_fila ->> 'cierres_no_referidos')::integer;
  v_numerador := (v_fila ->> 'numerador')::numeric;

  if v_cierres < 1 then
    raise exception 'CONV-24a · el vendedor B no tiene ningun cierre que anular: el caso no probaria nada';
  end if;

  -- Gerencia anula.
  perform crm.anular_cierre_avance(
    pg_temp.conv_lead(1001),
    'CONV-24: el asesor registro un cierre que nunca se concreto');

  v_pay  := crm.conversion_mensual_fn(pg_temp.conv_mes());
  v_fila := pg_temp.conv_fila('CONV-24b', v_pay, pg_temp.conv_lead(3));

  -- El NUMERADOR baja: ese cierre deja de contar.
  perform pg_temp.conv_num('CONV-24b', 'cierres no referidos tras anular',
    v_cierres - 1, (v_fila ->> 'cierres_no_referidos')::numeric);
  perform pg_temp.conv_num('CONV-24b', 'numerador tras anular',
    v_numerador - 1, (v_fila ->> 'numerador')::numeric);

  -- Y el DIVISOR no se mueve: el lead se trabajó igual. Sin este aserto el caso
  -- no distingue «dejó de contar como ganado» de «desapareció del mes», que es
  -- justo la diferencia entre corregir el mérito y falsear la muestra.
  perform pg_temp.conv_num('CONV-24b', 'el divisor NO se mueve al anular',
    v_divisor, (v_fila ->> 'divisor')::numeric);

  -- Una sola dirección: no se des-anula.
  begin
    perform crm.anular_cierre_avance(pg_temp.conv_lead(1001), 'CONV-24 otra vez');
    raise exception 'CONV-24c · se pudo anular dos veces el mismo cierre';
  exception when sqlstate 'P0409' then
    perform pg_temp.conv_caso('CONV-24c');
  end;

  perform set_config('request.jwt.claim.sub', pg_temp.conv_lead(1)::text, true);
end;
$test$;

-- ---------------------------------------------------------------------------
-- 9. CONV-99 · higiene: la sesión y la tabla quedan como estaban
-- ---------------------------------------------------------------------------
-- Es la mitad final del diferencial que abre CONV-00b. Por separado, cada una es
-- casi imposible de romper; juntas dicen algo que sí puede fallar: que ESTE
-- fichero no dejó nada apagado. Los triggers se durmieron cuatro veces con
-- `alter table ... disable trigger user` y se despertaron a mano otras cuatro:
-- un `enable` olvidado deja `tgenabled = 'D'`, que es EXACTAMENTE lo que esta
-- comprobación mira — desde el recambio del 2026-08-11 este caso dejó de ser
-- decorativo y pasó a vigilar de verdad los cuatro pares. El GUC se comprueba
-- igual (gratis, y protege contra una sesión que llegara ya en `replica`).
do $test$
declare
  v_apagados  text;
  v_casos     bigint;
  v_corridos  text[];
  v_esperados text[] := pg_temp.conv_codigos_esperados();
  v_faltan    text;
  v_sobran    text;
begin
  perform pg_temp.conv_txt('CONV-99', 'session_replication_role',
    'origin', current_setting('session_replication_role'));

  -- Las DOS llaves que este fichero arma y desarma. `crm.op_privilegiada` la
  -- usan los cierres (sección 4) y CONV-22d; `crm.ledger_writer` la arma y la
  -- desarma el escritor del ledger en cada episodio. Dejar cualquiera de las dos
  -- armada sería dejar abierta, para todo lo que viniera después, una puerta que
  -- existe para abrirse un statement.
  -- ⚠️ Aquí había una tercera, `crm.correccion_origen`, y era una aserción que NO
  -- PODÍA FALLAR NUNCA: ese GUC solo existía en la migración descartada 164017,
  -- así que `current_setting(..., true)` devolvía NULL, el `coalesce` lo
  -- convertía en 'off' y la comparación salía verde pasara lo que pasara. Se
  -- retira con la sección 8 que la justificaba: una aserción que no puede fallar
  -- no es defensa, es ruido que abulta el recuento.
  perform pg_temp.conv_txt('CONV-99', 'crm.op_privilegiada',
    'off', coalesce(current_setting('crm.op_privilegiada', true), 'off'));
  perform pg_temp.conv_txt('CONV-99', 'crm.ledger_writer',
    'off', coalesce(current_setting('crm.ledger_writer', true), 'off'));

  -- EL INVENTARIO, comparado contra la lista declarada en la sección 0.
  -- (Ojo al escribir aquí dentro: este comentario vive DENTRO de un bloque
  -- dollar-quoted, y el lexer no distingue comentario de contenido — escribir la
  -- etiqueta de cierre en un `--` lo cerraría a mitad. Por eso abajo se dice
  -- «bloque DO» y no se teclea la etiqueta.)
  -- El `v_casos = 0` de antes no bastaba y es importante ver por qué: borrar
  -- veinte de los veintiún bloques DO dejaba UNA fila en el registro,
  -- `1 <> 0` pasaba, y el token se imprimía en verde diciendo «casos: 1». El
  -- número se publicaba, no se aseveraba — el mismo fallo mudo del literal «19»
  -- que este mecanismo venía a sustituir, solo que ahora con la cifra correcta
  -- de lo poco que había corrido. Se comparan los CÓDIGOS y no el total para que
  -- el diagnóstico nombre el bloque que desapareció; el `sobran` está para que
  -- añadir un caso sin declararlo también cante, que es la mitad que mantiene la
  -- lista viva.
  select array_agg(cc.codigo order by cc.codigo) into v_corridos
  from pg_temp.conv_casos cc;

  select string_agg(e, ', ' order by e) into v_faltan
  from unnest(v_esperados) e
  where e <> all(coalesce(v_corridos, '{}'::text[]));

  select string_agg(c, ', ' order by c) into v_sobran
  from unnest(coalesce(v_corridos, '{}'::text[])) c
  where c <> all(v_esperados);

  if v_faltan is not null or v_sobran is not null then
    raise exception 'CONV-99 · inventario de casos: ESPERADOS % codigos · OBTENIDOS %. FALTAN: [%]. SOBRAN: [%]. La lista canonica esta en pg_temp.conv_codigos_esperados() (seccion 0): si el caso nuevo es legitimo, declaralo ahi; si falta uno, es que su bloque DO no llego a correr.',
      array_length(v_esperados, 1),
      coalesce(array_length(v_corridos, 1), 0),
      coalesce(v_faltan, '-'),
      coalesce(v_sobran, '-');
  end if;

  -- Cinturón: el registro no puede estar vacío. Con el inventario de arriba esto
  -- es redundante, y se conserva a propósito — es la única comprobación que
  -- sigue siendo cierta aunque alguien vacíe la lista declarada.
  select count(*) into v_casos from pg_temp.conv_casos;
  if v_casos = 0 then
    raise exception 'CONV-99 · registro de casos: ESPERADO al menos uno · OBTENIDO vacio (ninguna asercion llego a registrarse: revisa el grant de pg_temp.conv_casos)';
  end if;

  select string_agg(t.tgrelid::regclass::text || '.' || t.tgname, ', ' order by t.tgname)
    into v_apagados
  from pg_catalog.pg_trigger t
  where t.tgrelid in ('crm.leads'::regclass, 'crm.lead_asignaciones'::regclass)
    and not t.tgisinternal
    and t.tgenabled = 'D';
  if v_apagados is not null then
    raise exception 'CONV-99 · triggers deshabilitados al terminar: ESPERADO ninguno · OBTENIDO %', v_apagados;
  end if;

  -- El escritor del ledger, vivo: sin él la métrica contaría de MENOS en
  -- silencio, que es la peor forma de fallar para un informe que decide sueldos.
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'crm.leads'::regclass
      and t.tgname = 'trg_leads_asignaciones'
      and not t.tgisinternal
      and t.tgenabled <> 'D'
  ) then
    raise exception 'CONV-99 · trg_leads_asignaciones: ESPERADO habilitado · OBTENIDO ausente o deshabilitado';
  end if;
end;
$test$;

-- ---------------------------------------------------------------------------
-- 10. Token. Solo se imprime si NINGUNA aserción lanzó.
-- ---------------------------------------------------------------------------
-- `casos`, `familias` y `aserciones` se CUENTAN de lo que de verdad corrió (cada
-- comparador se registró solo en `pg_temp.conv_casos`). Antes aquí había un
-- literal —«19»— y un literal es una promesa que la suite no sostiene: el día
-- que alguien borre un bloque `do $test$` entero, el número seguiría diciendo lo
-- mismo y el token seguiría saliendo verde. La lista `codigos` está para que un
-- diff cante el bloque que desapareció, no solo el total.
--
-- Pero IMPRIMIR no es ASEVERAR: quien de verdad sostiene el recuento es CONV-99,
-- que compara esta misma lista contra `pg_temp.conv_codigos_esperados()`. Si el
-- token llega a imprimirse, `casos` y `casos_esperados` son iguales por
-- construcción; se publican los dos porque el día que alguien lea esta salida a
-- mano querrá ver el par, no fiarse de que la comprobación existió.
select jsonb_build_object(
  'resultado', 'CONVERSION_MENSUAL_OK',
  'mes_medido', to_char(pg_temp.conv_mes(), 'YYYY-MM'),
  'mes_de_arrastre', to_char(pg_temp.conv_mes_anterior(), 'YYYY-MM'),
  'mes_anteriores', to_char((pg_temp.conv_mes() - interval '13 months')::date, 'YYYY-MM'),
  'ventana_lima', jsonb_build_object(
    'desde', pg_temp.conv_ini(),
    'hasta', pg_temp.conv_fin()),
  'leads_del_fixture', (
    select count(*) from crm.leads l
    where l.nombre_completo like 'ORACULO CONV %'),
  'episodios_del_fixture', (
    select count(*) from crm.lead_asignaciones la
    join crm.leads l on l.id = la.lead_id
    where l.nombre_completo like 'ORACULO CONV %'),
  'casos', (select count(*) from pg_temp.conv_casos),
  'casos_esperados', array_length(pg_temp.conv_codigos_esperados(), 1),
  'familias', (
    select count(distinct regexp_replace(cc.codigo, '[a-z]+$', ''))
    from pg_temp.conv_casos cc),
  'aserciones', (select coalesce(sum(cc.aserciones), 0) from pg_temp.conv_casos cc),
  'codigos', (select jsonb_agg(cc.codigo order by cc.codigo) from pg_temp.conv_casos cc)
) as validacion;

rollback;
