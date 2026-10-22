-- ORÁCULO de «el analista dado de baja o suspendido sigue en el desglose con su marca, y la fila «Otros» hace que el desglose de
-- reuniones sume el total» — se ejecuta en el LABORATORIO (banco Docker local), NUNCA contra producción, y no escribe nada.
--
-- Las reglas (decisiones de Miguel del 09/10/2026; plan del backend, bloque 2.12):
--   D-43  en el desglose por responsable de `crm.metricas_reuniones_fn`, quien FUE analista o supervisor (su ficha) y HOY está
--         dado de baja (ficha de `crm.equipo` inactiva) sigue, con SUS citas y `"de_baja": true`;
--   D-46  el «suspendido en el Portal» (ficha ACTIVA, perfil `activo is not true`) también, con `"suspendido": true`;
--   D-47  todo lo que el desglose deja fuera (citas sin responsable, de Gerencia o Coordinación —también de un ex Gerencia de
--         baja—, de un perfil sin rol efectivo…) va a una fila «Otros» al final, con las mismas columnas: el desglose suma
--         SIEMPRE el total;
--   D-48  `crm.metricas_agenda_fn` conserva al de baja («de baja») y al suspendido («suspendido») SOLO si tienen actividad en
--         el período, con la definición de la app (`app/src/lib/agenda-equipo-vista.ts:138-150`; respuesta del Director).
-- Sin cambiar a quién ve cada rol, ni el total, ni las otras tres métricas del filtro común. Sin bajas, suspendidos ni «Otros»,
-- la respuesta es IDÉNTICA byte a byte a la de antes.
--
-- Este archivo NO se ejecuta a mano: `armar-ensayo.mjs` pega `antes.sql` (montaje y mediciones de ANTES con las puertas
-- vigentes), la migración real (sin su `begin;`/`commit;`) y este oráculo dentro de UNA transacción que termina en
-- `rollback`. Con `--sin-migracion` TIENE que salir ROJO por el motivo correcto (faltan las marcas, falta «Otros», el desglose no
-- suma el total y las piezas no existen). Nunca un error de montaje.
--
-- El oráculo no se fía de la migración: clasifica él mismo cada elemento de la implementación (`pg_temp.clase`) y construye la
-- respuesta ESPERADA (`pg_temp.esperado_reuniones`, `pg_temp.esperado_agenda`); además exige cifras escritas a mano para los
-- actores del escenario y compara byte a byte con lo medido ANTES (`antes.sql`).
--
-- Casos (los actores y el escenario, en `antes.sql`). Estado «con» (A, S, X y Q1 de baja; P suspendido):
--   R1  D1: A y S marcados «de baja» con sus cifras; B tal cual; sin «Otros»; orden A, S, B.
--   R2  D2: P marcado «suspendido» con sus cifras; B tal cual; X, C, N, Z y M fuera por nombre y DENTRO de «Otros» (cifras a
--       mano); orden P, B, «Otros».
--   R3  En las seis ventanas (D1, D2, D3, hoy, el mes, el año), la respuesta es exactamente la esperada a partir de la
--       implementación.
--   R4  En las seis ventanas, quitando los marcados y «Otros», la respuesta es byte a byte la de antes.
--   R5  En las seis ventanas, el desglose suma el total en los diez contadores que comparten; el DIVISOR de realización no:
--       la suma de los divisores de las filas + las canceladas por otro asesor (que cada fila descuenta y el resumen no) = el
--       divisor del resumen (Codex r1: en D2, 9 frente a 8).
--   R6  Las marcas de cada ventana son exactamente las del escenario.
--   R7  El contrato de la pantalla (`metricas-reuniones.ts` + las marcas de `crm-api.ts`), con y sin.
--   R8  Lo que ve cada rol en reuniones (D1 y D2), con y sin: Gerencia y lector, lo de antes + lo nuevo; los demás, 42501.
--   R9  D3: «Otros» es la ÚNICA fila del desglose (una cita de Coordinación cancelada por el sistema) y su divisor es 0
--       (porcentaje nulo).
--   Todos los actores son obligatorios, también el lector global (Directorio, D-54): ningún caso se salta por falta de actor.
--   G1  Agenda (Gerencia, lector, supervisor, analista; cuatro ventanas): exactamente la esperada a partir de la implementación.
--   G2  Agenda: quitando los marcados, byte a byte la de antes.
--   G3  Agenda: las marcas de cada rol y ventana son exactamente las del escenario.
--   G4  Agenda: Q2 (de baja sin nada), R (suspendido con solo rezago) y M (desalineado) siguen fuera, aunque la implementación
--       los trae.
--   G5  Agenda: la marca casa con `activo` («de baja» ⇒ false; «suspendido» y sin marca ⇒ true) y respeta el contrato de la app.
--   G6  Agenda: Coordinación, el propio A, el propio P y anónimo reciben lo de antes (42501).
--   O1  Las otras tres métricas del filtro común: byte a byte las de antes.
--   K*  Catálogo: fichas de las dos puertas y las dos piezas, las claves de actividad de la agenda, lo que no se toca con su
--       huella, el registro analítico y la evidencia de las definiciones.
-- Estado «sin» (A, S, X y Q1 activos; P con el perfil activo):
--   S1  Reuniones: exactamente la esperada; sin «Otros» en la ventana, byte a byte la de antes; con «Otros», la de antes + «Otros».
--   S2  Agenda: byte a byte la de antes en cada rol y ventana.
--   S3  Visibilidad: byte a byte la de antes.
-- Y al final:
--   P1  P con el perfil `activo` NULO sigue siendo «suspendido» (es la definición del CRM: `is not true`).
--   P2  Un marcado con el nombre vacío (Q1) o en blanco (P) sale como «(sin nombre)», en la agenda y en reuniones: la agenda de
--       la app exige texto no vacío (`metricas-agenda.ts`, `TextoNoVacioSchema`) y `public.perfiles.nombre_completo` no lo impide
--       (auditor de permisos r1, P3-5).
--   P3  Ficha INACTIVA y perfil del Portal inactivo (A) o NULO (S), con actividad: en reuniones y en la agenda, SOLO
--       «de baja» (la ficha manda; Codex r1, P3-1). Sin este caso, un mutante que diera prioridad a la suspensión sobrevivía.
--   P4  Actividad por UNA sola clave: R (suspendido) con solo un toque y Q2 (de baja) con solo una reprogramación aparecen,
--       marcados; antes estaban fuera (solo rezago / nada).

set local statement_timeout = '300s';

-- Una respuesta de una puerta como jsonb, o null si fue un error.
create function pg_temp.j(p_txt text) returns jsonb language sql as $$
  select case when p_txt is null or p_txt like 'error %' then null else p_txt::jsonb end;
$$;

-- La clase de un sujeto según D-43/D-46, calculada AQUÍ (independiente de la migración): 'efectivo' si private.rol_crm lo
-- reconoce como analista o supervisor; 'de_baja' si su ficha de analista o supervisor está inactiva; 'suspendido' si esa ficha
-- está activa y su perfil no (`activo is not true`); null en cualquier otro caso (otro rol, desalineado, sin ficha, sin id).
create function pg_temp.clase(p_id text) returns text language sql as $$
  select case
    when p_id is null then null
    when private.rol_crm(p_id::uuid) in ('vendedor', 'supervisor') then 'efectivo'
    when exists (select 1 from crm.equipo e
                  where e.perfil_id = p_id::uuid and e.rol_crm in ('vendedor', 'supervisor') and e.activo is false) then 'de_baja'
    when exists (select 1 from crm.equipo e join public.perfiles p on p.id = e.perfil_id
                  where e.perfil_id = p_id::uuid and e.rol_crm in ('vendedor', 'supervisor') and e.activo is true
                    and p.activo is not true) then 'suspendido'
  end;
$$;

-- Un marcado con el nombre vacío o en blanco sale con un nombre de reserva legible: «(sin nombre)».
create function pg_temp.con_nombre_de_reserva(p_e jsonb) returns jsonb language sql as $$
  select case when p_e ? 'nombre' and coalesce(p_e ->> 'nombre', '') !~ '[^[:space:]]'
              then p_e || jsonb_build_object('nombre', '(sin nombre)') else p_e end;
$$;

-- «Tiene actividad» con la MISMA definición que la app (`agenda-equipo-vista.ts:138-150`, función `tieneActividad`).
create function pg_temp.tiene_actividad(p_e jsonb) returns boolean language sql as $$
  select pg_temp.n(p_e, 'toques') > 0 or pg_temp.n(p_e, 'reuniones_realizadas') > 0 or pg_temp.n(p_e, 'completadas') > 0
      or pg_temp.n(p_e, 'no_asistio') > 0 or pg_temp.n(p_e, 'canceladas') > 0 or pg_temp.n(p_e, 'tareas_creadas') > 0
      or pg_temp.n(p_e, 'reuniones_agendadas') > 0 or pg_temp.n(p_e, 'reprogramaciones') > 0 or pg_temp.n(p_e, 'pendientes') > 0;
$$;

-- Los contadores de una fila de responsable que se suman (los de la implementación, `metricas_reuniones_implementacion`).
create function pg_temp.contadores_responsable() returns text[] language sql as $$
  select array['pactadas','realizadas','debieron_ocurrir','divisor_realizacion','canceladas_sistema_vencidas',
               'canceladas_ajenas_vencidas','reprogramadas_vencidas','programadas_futuras','no_show','canceladas',
               'reprogramadas','pendientes_cierre'];
$$;

-- La fila «Otros» ESPERADA: la SUMA (directa, elemento a elemento) de los que el desglose deja fuera, con el porcentaje
-- recalculado como la implementación (`round(100.0*realizadas/divisor, 1)` si el divisor es positivo).
create function pg_temp.otros_esperado(p_fuera jsonb) returns jsonb language sql as $$
  select jsonb_build_object('responsable_id', null, 'nombre', 'Otros', 'rol', null, 'supervisor_id', null,
                            'supervisor_nombre', '—', 'otros', true)
         || (select jsonb_object_agg(c, (select coalesce(sum(pg_temp.n(x, c)), 0)::bigint
                                           from jsonb_array_elements(p_fuera) x))
               from unnest(pg_temp.contadores_responsable()) c)
         || jsonb_build_object('pct_realizacion',
              case when (select sum(pg_temp.n(x, 'divisor_realizacion')) from jsonb_array_elements(p_fuera) x) > 0
                   then round(100.0 * (select sum(pg_temp.n(x, 'realizadas')) from jsonb_array_elements(p_fuera) x)
                              / (select sum(pg_temp.n(x, 'divisor_realizacion')) from jsonb_array_elements(p_fuera) x), 1)
              end);
$$;

-- La respuesta ESPERADA de reuniones a partir de la implementación: el efectivo, tal cual; el de baja o suspendido, con su
-- marca y en su sitio; los demás, a «Otros» (al final), si hay alguno.
create function pg_temp.esperado_reuniones(p_impl jsonb) returns jsonb language plpgsql as $f$
declare
  v_lista jsonb := '[]'::jsonb;
  v_fuera jsonb := '[]'::jsonb;
  v_e jsonb;
  v_c text;
begin
  if p_impl is null then return null; end if;
  for v_e in select x from jsonb_array_elements(p_impl -> 'responsables') x loop
    v_c := pg_temp.clase(v_e ->> 'responsable_id');
    if v_c = 'efectivo' then
      v_lista := v_lista || jsonb_build_array(v_e);
    elsif v_c in ('de_baja', 'suspendido') then
      v_lista := v_lista || jsonb_build_array(pg_temp.con_nombre_de_reserva(v_e) || jsonb_build_object(v_c, true));
    else
      v_fuera := v_fuera || jsonb_build_array(v_e);
    end if;
  end loop;
  if jsonb_array_length(v_fuera) > 0 then
    v_lista := v_lista || jsonb_build_array(pg_temp.otros_esperado(v_fuera));
  end if;
  return jsonb_set(p_impl, '{responsables}', v_lista, false);
end;
$f$;

-- La respuesta ESPERADA de la agenda a partir de su implementación: el efectivo, tal cual; el de baja o suspendido, con su
-- marca y en su sitio, SOLO si tiene actividad; los demás, fuera (como hoy).
create function pg_temp.esperado_agenda(p_impl jsonb) returns jsonb language plpgsql as $f$
declare
  v_lista jsonb := '[]'::jsonb;
  v_e jsonb;
  v_c text;
begin
  if p_impl is null then return null; end if;
  for v_e in select x from jsonb_array_elements(p_impl -> 'vendedores') x loop
    v_c := pg_temp.clase(v_e ->> 'vendedor_id');
    if v_c = 'efectivo' then
      v_lista := v_lista || jsonb_build_array(v_e);
    elsif v_c in ('de_baja', 'suspendido') and pg_temp.tiene_actividad(v_e) then
      v_lista := v_lista || jsonb_build_array(pg_temp.con_nombre_de_reserva(v_e) || jsonb_build_object(v_c, true));
    end if;
  end loop;
  return jsonb_set(p_impl, '{vendedores}', v_lista, false);
end;
$f$;

-- La respuesta SIN lo nuevo (los elementos marcados y la fila «Otros»): tiene que ser la de antes, byte a byte.
create function pg_temp.sin_lo_nuevo(p_payload jsonb, p_grupo text) returns jsonb language sql as $$
  select jsonb_set(p_payload, array[p_grupo],
           coalesce((select jsonb_agg(x order by o) from jsonb_array_elements(p_payload -> p_grupo) with ordinality t(x, o)
                      where not (x ? 'de_baja' or x ? 'suspendido' or x ? 'otros')), '[]'::jsonb), false);
$$;

-- Las marcas de una respuesta, legibles y ordenadas: «<id>:<marca>» (con «otros» para la fila «Otros»).
create function pg_temp.marcas(p_payload jsonb, p_grupo text, p_clave_id text) returns text language sql as $$
  select coalesce(string_agg(coalesce(x ->> p_clave_id, '-') || ':'
                               || case when x ? 'de_baja' then 'de_baja' when x ? 'suspendido' then 'suspendido' else 'otros' end,
                             ',' order by coalesce(x ->> p_clave_id, '-')), '')
    from jsonb_array_elements(coalesce(p_payload -> p_grupo, '[]'::jsonb)) x
   where x ? 'de_baja' or x ? 'suspendido' or x ? 'otros';
$$;
-- Las marcas esperadas, en el mismo formato, a partir de pares (id, marca).
create function pg_temp.marcas_de(p_pares text[]) returns text language sql as $$
  select coalesce(string_agg(par, ',' order by par), '') from unnest(p_pares) par where par is not null;
$$;

-- La validación de la pantalla de reuniones (`metricas-reuniones.ts`: fila de responsable y check del payload) y la de las
-- marcas (`crm-api.ts`: cada marca es `true`, a lo sumo una por fila; «Otros» es la última, única, sin id; los marcados con id).
create function pg_temp.contrato_app(p_payload jsonb) returns text language sql as $$
  select case
    when p_payload is null then 'sin respuesta'
    when exists (select 1 from jsonb_array_elements(p_payload -> 'responsables') x
                  where pg_temp.n(x, 'divisor_realizacion') <> pg_temp.n(x, 'debieron_ocurrir') - pg_temp.n(x, 'canceladas_sistema_vencidas')
                                                               - pg_temp.n(x, 'canceladas_ajenas_vencidas') - pg_temp.n(x, 'reprogramadas_vencidas')
                     or pg_temp.n(x, 'realizadas') > pg_temp.n(x, 'divisor_realizacion')
                     or pg_temp.n(x, 'debieron_ocurrir') > pg_temp.n(x, 'pactadas')
                     or pg_temp.n(x, 'canceladas_ajenas_vencidas') > pg_temp.n(x, 'canceladas')
                     or pg_temp.n(x, 'reprogramadas_vencidas') > pg_temp.n(x, 'reprogramadas')
                     or jsonb_typeof(x -> 'nombre') is distinct from 'string'
                     or jsonb_typeof(x -> 'supervisor_nombre') is distinct from 'string') then 'una fila del desglose no pasa la validación de la app'
    when exists (select 1 from jsonb_array_elements(p_payload -> 'responsables') x
                  where (x ? 'de_baja' and (x -> 'de_baja') <> 'true'::jsonb)
                     or (x ? 'suspendido' and (x -> 'suspendido') <> 'true'::jsonb)
                     or (x ? 'otros' and (x -> 'otros') <> 'true'::jsonb)
                     or ((x ? 'de_baja')::int + (x ? 'suspendido')::int + (x ? 'otros')::int) > 1
                     or ((x ? 'de_baja' or x ? 'suspendido') and jsonb_typeof(x -> 'responsable_id') is distinct from 'string')
                     or (x ? 'otros' and (x -> 'responsable_id') <> 'null'::jsonb)) then 'una marca fuera de contrato'
    when (select count(*) from jsonb_array_elements(p_payload -> 'responsables') x where x ? 'otros') > 1
      or exists (select 1 from jsonb_array_elements(p_payload -> 'responsables') with ordinality t(x, o)
                  where x ? 'otros' and o <> jsonb_array_length(p_payload -> 'responsables')) then '«Otros» no es la última fila o no es única'
    when (select coalesce(sum(pg_temp.n(x, 'pactadas')), 0) from jsonb_array_elements(p_payload -> 'responsables') x) > pg_temp.n(p_payload -> 'resumen', 'pactadas')
      or (select coalesce(sum(pg_temp.n(x, 'realizadas')), 0) from jsonb_array_elements(p_payload -> 'responsables') x) > pg_temp.n(p_payload -> 'resumen', 'realizadas')
      or (select coalesce(sum(pg_temp.n(x, 'pendientes_cierre')), 0) from jsonb_array_elements(p_payload -> 'responsables') x) > pg_temp.n(p_payload -> 'resumen', 'pendientes_cierre')
      then 'el desglose supera al total'
    else '' end;
$$;

-- La validación de la agenda (`metricas-agenda.ts`: objeto ESTRICTO) más las marcas: ninguna clave fuera de la lista, la marca
-- es `true` y casa con `activo` («de baja» ⇒ false; «suspendido» y sin marca ⇒ true).
create function pg_temp.contrato_agenda(p_payload jsonb) returns text language sql as $$
  select case
    when p_payload is null then 'sin respuesta'
    when exists (select 1 from jsonb_array_elements(p_payload -> 'vendedores') x, jsonb_object_keys(x) k
                  where k not in ('vendedor_id','nombre','rol','activo','toques','toques_por_dia','reuniones_realizadas',
                                  'completadas','no_asistio','canceladas','canceladas_asesor','canceladas_sistema',
                                  'canceladas_ajenas','pct_completadas','tareas_creadas','reuniones_agendadas',
                                  'reprogramaciones','pendientes','vencidas','leads_sin_accion','de_baja','suspendido')) then 'una clave fuera del contrato'
    when exists (select 1 from jsonb_array_elements(p_payload -> 'vendedores') x
                  where jsonb_typeof(x -> 'nombre') is distinct from 'string' or length(x ->> 'nombre') = 0) then 'un nombre vacío (la app lo rechaza)'
    when exists (select 1 from jsonb_array_elements(p_payload -> 'vendedores') x
                  where (x ? 'de_baja' and ((x -> 'de_baja') <> 'true'::jsonb or (x -> 'activo') <> 'false'::jsonb))
                     or (x ? 'suspendido' and ((x -> 'suspendido') <> 'true'::jsonb or (x -> 'activo') <> 'true'::jsonb))
                     or (x ? 'de_baja' and x ? 'suspendido')
                     or (not (x ? 'de_baja') and (x -> 'activo') <> 'true'::jsonb)) then 'una marca no casa con activo'
    else '' end;
$$;

-- Diferencia «total − suma del desglose» por contador (texto), y si es cero en todos.
create function pg_temp.fuera(p_payload jsonb) returns text language sql as $$
  select string_agg(c || '=' || (pg_temp.n(p_payload -> 'resumen', c)
                                 - (select coalesce(sum(pg_temp.n(x, c)), 0) from jsonb_array_elements(p_payload -> 'responsables') x))::text,
                    ' ' order by c)
    from unnest(array['pactadas','debieron_ocurrir','realizadas','no_show','canceladas','reprogramadas','pendientes_cierre',
                      'programadas_futuras','canceladas_sistema_vencidas','reprogramadas_vencidas']) c;
$$;
create function pg_temp.cuadra(p_payload jsonb) returns boolean language sql as $$
  select p_payload is not null and pg_temp.fuera(p_payload) !~ '=-?[1-9]';
$$;

-- Nombres de un arreglo, en orden (para los mensajes).
create function pg_temp.nombres(p_payload jsonb, p_grupo text) returns text language sql as $$
  select coalesce(string_agg(coalesce(x ->> 'nombre', '?') || case when x ? 'de_baja' then ' (de baja)'
                                                                  when x ? 'suspendido' then ' (suspendido)' else '' end,
                             ' > ' order by o), '(vacío)')
    from jsonb_array_elements(coalesce(p_payload -> p_grupo, '[]'::jsonb)) with ordinality t(x, o);
$$;

do $ensayo$
declare
  v_g uuid := current_setting('ensayo.g')::uuid;
  v_x uuid := current_setting('ensayo.x')::uuid;
  v_dir uuid := current_setting('ensayo.dir')::uuid;
  v_coord uuid := current_setting('ensayo.coord')::uuid;
  v_a uuid := current_setting('ensayo.a')::uuid;
  v_b uuid := current_setting('ensayo.b')::uuid;
  v_m uuid := current_setting('ensayo.m')::uuid;
  v_s uuid := current_setting('ensayo.s')::uuid;
  v_supv uuid := current_setting('ensayo.supv')::uuid;
  v_p uuid := current_setting('ensayo.p')::uuid;
  v_r uuid := current_setting('ensayo.r')::uuid;
  v_q1 uuid := current_setting('ensayo.q1')::uuid;
  v_q2 uuid := current_setting('ensayo.q2')::uuid;
  v_z uuid := current_setting('ensayo.z')::uuid;
  v_d1 date := current_setting('ensayo.d1')::date;
  v_d2 date := current_setting('ensayo.d2')::date;
  v_d3 date := current_setting('ensayo.d3')::date;
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_mes date := date_trunc('month', (now() at time zone 'America/Lima')::date)::date;
  v_r1 jsonb; v_r2 jsonb; v_impl jsonb; v_esp jsonb;
  v_fa jsonb; v_fs jsonb; v_fb jsonb; v_fp jsonb; v_fo jsonb; v_ia jsonb; v_is jsonb; v_ib jsonb; v_ip jsonb;
  v_antes text; v_despues text; v_txt text; v_det text; v_ok boolean;
  v_marcas_esperadas text;
  v_actor uuid;
  r record;
  w record;
begin
  perform set_config('ensayo.fallos', '0', true);
  perform set_config('ensayo.informe', '', true);
  perform set_config('ensayo.oks', '', true);
  perform set_config('ensayo.medidas', '', true);

  -- ══════════════════ CON (A, S, X y Q1 dados de baja; P suspendido en el Portal, como los deja el montaje) ══════════════════

  -- ── R1. D1: A y S, marcados «de baja» y con sus citas; B tal cual; sin «Otros» ──────────────────────────────────────
  v_r1 := pg_temp.j(pg_temp.puerta(v_g, v_d1, v_d1));
  v_impl := pg_temp.implementacion(v_g, v_d1, v_d1);
  v_fa := pg_temp.fila(v_r1, 'responsables', 'responsable_id', v_a::text);
  v_fs := pg_temp.fila(v_r1, 'responsables', 'responsable_id', v_s::text);
  v_fb := pg_temp.fila(v_r1, 'responsables', 'responsable_id', v_b::text);
  v_ia := pg_temp.fila(v_impl, 'responsables', 'responsable_id', v_a::text);
  v_is := pg_temp.fila(v_impl, 'responsables', 'responsable_id', v_s::text);
  v_ib := pg_temp.fila(v_impl, 'responsables', 'responsable_id', v_b::text);
  perform pg_temp.exigir('R1-d1-baja-analista',
    v_fa is not null and (v_fa -> 'de_baja') = 'true'::jsonb and v_ia is not null and (v_fa - 'de_baja') = v_ia
      and not (v_fa ? 'suspendido') and not (v_fa ? 'otros')
      and pg_temp.n(v_fa, 'pactadas') = 6 and pg_temp.n(v_fa, 'debieron_ocurrir') = 6 and pg_temp.n(v_fa, 'realizadas') = 3
      and pg_temp.n(v_fa, 'no_show') = 1 and pg_temp.n(v_fa, 'canceladas') = 1 and pg_temp.n(v_fa, 'reprogramadas') = 1
      and pg_temp.n(v_fa, 'reprogramadas_vencidas') = 1 and pg_temp.n(v_fa, 'divisor_realizacion') = 5
      and pg_temp.n(v_fa, 'pct_realizacion') = 60.0 and (v_fa ->> 'rol') = 'vendedor',
    format('el analista dado de baja (A) no está en el desglose de D1 marcado «de baja» con SUS citas (6 pactadas, 3 realizadas, 1 no asistió, 1 cancelada, 1 reprogramada, divisor 5, 60,0 %%): servido [%s] · implementación [%s]',
      pg_temp.txt(v_fa), pg_temp.txt(v_ia)));
  perform pg_temp.exigir('R1-d1-baja-supervisor',
    v_fs is not null and (v_fs -> 'de_baja') = 'true'::jsonb and v_is is not null and (v_fs - 'de_baja') = v_is
      and pg_temp.n(v_fs, 'pactadas') = 3 and pg_temp.n(v_fs, 'realizadas') = 2
      and pg_temp.n(v_fs, 'canceladas_sistema_vencidas') = 1 and pg_temp.n(v_fs, 'divisor_realizacion') = 2
      and (v_fs ->> 'rol') = 'supervisor',
    format('el supervisor dado de baja (S) no está marcado «de baja» con sus citas (3 pactadas, 2 realizadas, 1 cancelada por el sistema, divisor 2): servido [%s] · implementación [%s]',
      pg_temp.txt(v_fs), pg_temp.txt(v_is)));
  perform pg_temp.exigir('R1-d1-activo-sin-marca',
    v_fb is not null and v_fb = v_ib and pg_temp.n(v_fb, 'pactadas') = 2 and pg_temp.n(v_fb, 'realizadas') = 1,
    format('el analista activo (B) no está tal cual, sin marca: [%s]', pg_temp.txt(v_fb)));
  perform pg_temp.exigir('R1-d1-sin-otros',
    v_r1 is not null and not exists (select 1 from jsonb_array_elements(v_r1 -> 'responsables') x where x ? 'otros'),
    format('D1 trae una fila «Otros» aunque la implementación no deja a nadie fuera: %s', pg_temp.nombres(v_r1, 'responsables')));
  perform pg_temp.exigir('R1-d1-orden',
    (select array_agg(x ->> 'responsable_id' order by o) from jsonb_array_elements(v_r1 -> 'responsables') with ordinality t(x, o))
      = array[v_a::text, v_s::text, v_b::text],
    format('el desglose de D1 no es A, S, B en el orden de la implementación: servido %s · implementación %s',
      pg_temp.nombres(v_r1, 'responsables'), pg_temp.nombres(v_impl, 'responsables')));
  perform pg_temp.medir(format('medida D1 con: A [%s] · S [%s] · B [%s] · total − desglose: %s',
    pg_temp.txt(v_fa), pg_temp.txt(v_fs), pg_temp.txt(v_fb), coalesce(pg_temp.fuera(v_r1), '-')));

  -- ── R2. D2: P marcado «suspendido»; B tal cual; X, C, N, Z y M dentro de «Otros» ────────────────────────────────────
  v_r2 := pg_temp.j(pg_temp.puerta(v_g, v_d2, v_d2));
  v_impl := pg_temp.implementacion(v_g, v_d2, v_d2);
  v_fp := pg_temp.fila(v_r2, 'responsables', 'responsable_id', v_p::text);
  v_ip := pg_temp.fila(v_impl, 'responsables', 'responsable_id', v_p::text);
  v_fb := pg_temp.fila(v_r2, 'responsables', 'responsable_id', v_b::text);
  v_ib := pg_temp.fila(v_impl, 'responsables', 'responsable_id', v_b::text);
  select x into v_fo from jsonb_array_elements(coalesce(v_r2 -> 'responsables', '[]'::jsonb)) x where x ? 'otros' limit 1;
  perform pg_temp.exigir('R2-d2-montaje',
    pg_temp.fila(v_impl, 'responsables', 'responsable_id', v_x::text) is not null
      and pg_temp.fila(v_impl, 'responsables', 'responsable_id', v_coord::text) is not null
      and pg_temp.fila(v_impl, 'responsables', 'responsable_id', v_z::text) is not null
      and pg_temp.fila(v_impl, 'responsables', 'responsable_id', v_m::text) is not null
      and v_ip is not null
      and exists (select 1 from jsonb_array_elements(v_impl -> 'responsables') x where x -> 'responsable_id' = 'null'::jsonb)
      and pg_temp.n(v_impl -> 'resumen', 'pactadas') = 10,
    format('el montaje de D2 no llegó entero a la implementación (P, X, C, N, Z, M y B; 10 pactadas): %s', pg_temp.nombres(v_impl, 'responsables')));
  perform pg_temp.exigir('R2-d2-suspendido',
    v_fp is not null and (v_fp -> 'suspendido') = 'true'::jsonb and not (v_fp ? 'de_baja') and (v_fp - 'suspendido') = v_ip
      and pg_temp.n(v_fp, 'pactadas') = 2 and pg_temp.n(v_fp, 'realizadas') = 1 and pg_temp.n(v_fp, 'no_show') = 1
      and pg_temp.n(v_fp, 'divisor_realizacion') = 2 and pg_temp.n(v_fp, 'pct_realizacion') = 50.0,
    format('el suspendido en el Portal (P) no está marcado «suspendido» con SUS citas (2 pactadas, 1 realizada, 1 no asistió, divisor 2, 50,0 %%): servido [%s] · implementación [%s]',
      pg_temp.txt(v_fp), pg_temp.txt(v_ip)));
  perform pg_temp.exigir('R2-d2-otros',
    v_fo is not null
      and (v_fo -> 'responsable_id') = 'null'::jsonb and (v_fo ->> 'nombre') = 'Otros' and (v_fo -> 'rol') = 'null'::jsonb
      and (v_fo -> 'supervisor_id') = 'null'::jsonb and (v_fo ->> 'supervisor_nombre') = '—' and (v_fo -> 'otros') = 'true'::jsonb
      and pg_temp.n(v_fo, 'pactadas') = 7 and pg_temp.n(v_fo, 'debieron_ocurrir') = 7 and pg_temp.n(v_fo, 'realizadas') = 4
      and pg_temp.n(v_fo, 'no_show') = 1 and pg_temp.n(v_fo, 'canceladas') = 1 and pg_temp.n(v_fo, 'reprogramadas') = 0
      and pg_temp.n(v_fo, 'canceladas_sistema_vencidas') = 1 and pg_temp.n(v_fo, 'canceladas_ajenas_vencidas') = 1
      and pg_temp.n(v_fo, 'reprogramadas_vencidas') = 0 and pg_temp.n(v_fo, 'programadas_futuras') = 0
      and pg_temp.n(v_fo, 'pendientes_cierre') = 0 and pg_temp.n(v_fo, 'divisor_realizacion') = 5
      and (v_fo -> 'pct_realizacion') = '80.0'::jsonb
      and (select count(*) from jsonb_object_keys(v_fo)) = 19,
    format('D2 no trae la fila «Otros» con X, C, N, Z y M (esperado: id nulo, nombre «Otros», supervisor «—», 7 pactadas, 7 que debieron ocurrir, 4 realizadas, 1 no asistió, 1 cancelada, 1 cancelada por el sistema, 1 por otro asesor, divisor 5, 80,0 %%, otros: true y las 19 claves): [%s]',
      pg_temp.txt(v_fo)));
  perform pg_temp.exigir('R2-d2-fuera-por-nombre',
    v_r2 is not null
      and pg_temp.fila(v_r2, 'responsables', 'responsable_id', v_x::text) is null
      and pg_temp.fila(v_r2, 'responsables', 'responsable_id', v_coord::text) is null
      and pg_temp.fila(v_r2, 'responsables', 'responsable_id', v_z::text) is null
      and pg_temp.fila(v_r2, 'responsables', 'responsable_id', v_m::text) is null
      and (select count(*) from jsonb_array_elements(v_r2 -> 'responsables') x where x -> 'responsable_id' = 'null'::jsonb
                                                                                 and not (x ? 'otros')) = 0,
    format('en D2 aparece por su nombre alguien que va a «Otros» (ex Gerencia de baja, Coordinación, sin ficha, desalineado o sin responsable): %s',
      pg_temp.nombres(v_r2, 'responsables')));
  perform pg_temp.exigir('R2-d2-orden',
    (select array_agg(coalesce(x ->> 'responsable_id', 'otros') order by o) from jsonb_array_elements(v_r2 -> 'responsables') with ordinality t(x, o))
      = array[v_p::text, v_b::text, 'otros'],
    format('el desglose de D2 no es P, B, «Otros»: %s', pg_temp.nombres(v_r2, 'responsables')));
  perform pg_temp.exigir('R2-d2-activo-sin-marca',
    v_fb is not null and v_fb = v_ib,
    format('B no está tal cual en D2: [%s]', pg_temp.txt(v_fb)));
  perform pg_temp.medir(format('medida D2 con: P [%s] · «Otros» [%s] · total − desglose: %s',
    pg_temp.txt(v_fp), pg_temp.txt(v_fo), coalesce(pg_temp.fuera(v_r2), '-')));

  -- ── R3–R7. Cada ventana: la esperada, «solo añade», cuadra, sus marcas y el contrato de la app ────────────────────────
  for w in select * from (values ('d1', v_d1, v_d1, array[v_a::text || ':de_baja', v_s::text || ':de_baja']),
                                 ('d2', v_d2, v_d2, array[v_p::text || ':suspendido', '-:otros']),
                                 ('d3', v_d3, v_d3, array['-:otros']),
                                 ('hoy', v_hoy, v_hoy, array[]::text[]),
                                 ('mes', v_mes, v_hoy, array[]::text[]),
                                 ('anio', v_hoy - 365, v_hoy, array[v_a::text || ':de_baja', v_s::text || ':de_baja',
                                                                    v_p::text || ':suspendido', '-:otros'])) x(k, desde, hasta, marcas)
  loop
    v_antes := current_setting('ensayo.con.' || w.k);
    v_despues := pg_temp.puerta(v_g, w.desde, w.hasta);
    v_r1 := pg_temp.j(v_despues);
    v_esp := pg_temp.esperado_reuniones(pg_temp.implementacion(v_g, w.desde, w.hasta));
    perform pg_temp.exigir('R3-esperado-' || w.k,
      v_r1 is not null and v_r1 = v_esp,
      format('la ventana %s no es la esperada a partir de la implementación: servido %s · esperado %s',
        w.k, pg_temp.nombres(v_r1, 'responsables'), pg_temp.nombres(v_esp, 'responsables')));
    perform pg_temp.exigir('R4-solo-anade-' || w.k,
      v_r1 is not null and pg_temp.sin_lo_nuevo(v_r1, 'responsables')::text = v_antes,
      format('en la ventana %s, quitando los marcados y «Otros», la respuesta NO es la de antes (antes %s bytes, después %s)',
        w.k, length(v_antes), length(v_despues)));
    perform pg_temp.exigir('R5-cuadra-' || w.k,
      pg_temp.cuadra(v_r1),
      format('el desglose de la ventana %s no suma el total (total − desglose: %s)', w.k, coalesce(pg_temp.fuera(v_r1), 'sin respuesta')));
    -- El divisor NO suma el total: cada fila descuenta las canceladas por otro asesor y el resumen no.
    perform pg_temp.exigir('R5-divisor-' || w.k,
      v_r1 is not null
        and (select coalesce(sum(pg_temp.n(x, 'divisor_realizacion') + pg_temp.n(x, 'canceladas_ajenas_vencidas')), 0)
               from jsonb_array_elements(v_r1 -> 'responsables') x)
            = pg_temp.n(v_r1 -> 'resumen', 'divisor_realizacion'),
      format('en la ventana %s, la suma de los divisores de las filas + sus canceladas por otro asesor (%s + %s) no es el divisor del resumen (%s)',
        w.k, (select coalesce(sum(pg_temp.n(x, 'divisor_realizacion')), 0) from jsonb_array_elements(v_r1 -> 'responsables') x),
        (select coalesce(sum(pg_temp.n(x, 'canceladas_ajenas_vencidas')), 0) from jsonb_array_elements(v_r1 -> 'responsables') x),
        pg_temp.n(v_r1 -> 'resumen', 'divisor_realizacion')));
    -- En hoy, el mes y el año pueden entrar citas reales del banco que van a «Otros»: la marca «otros» se espera si la
    -- implementación deja a alguien fuera (lo dice la esperada), y las demás marcas son exactamente las del escenario.
    v_marcas_esperadas := pg_temp.marcas_de(w.marcas || case when w.k in ('hoy', 'mes')
                                                                and pg_temp.marcas(v_esp, 'responsables', 'responsable_id') like '%-:otros%'
                                                              then array['-:otros'] else array[]::text[] end);
    perform pg_temp.exigir('R6-marcas-' || w.k,
      pg_temp.marcas(v_r1, 'responsables', 'responsable_id') = v_marcas_esperadas,
      format('las marcas de la ventana %s no son las del escenario: servidas [%s] · esperadas [%s]',
        w.k, pg_temp.marcas(v_r1, 'responsables', 'responsable_id'), v_marcas_esperadas));
    v_txt := pg_temp.contrato_app(v_r1);
    perform pg_temp.exigir('R7-contrato-app-' || w.k, v_txt = '',
      format('la pantalla rechazaría la respuesta de la ventana %s: %s', w.k, v_txt));
    perform pg_temp.medir(format('medida reuniones con %s: %s bytes antes, %s después · marcas [%s] · total − desglose: %s',
      w.k, length(v_antes), length(v_despues), pg_temp.marcas(v_r1, 'responsables', 'responsable_id'), coalesce(pg_temp.fuera(v_r1), '-')));
  end loop;

  -- ── R9. D3: «Otros» es la ÚNICA fila (una cita de Coordinación cancelada por el sistema) y su divisor es 0 ─────────────
  v_r1 := pg_temp.j(pg_temp.puerta(v_g, v_d3, v_d3));
  v_fo := v_r1 -> 'responsables' -> 0;
  perform pg_temp.exigir('R9-d3-solo-otros',
    v_r1 is not null and jsonb_array_length(v_r1 -> 'responsables') = 1 and (v_fo -> 'otros') = 'true'::jsonb
      and (v_fo -> 'responsable_id') = 'null'::jsonb and (v_fo ->> 'nombre') = 'Otros'
      and pg_temp.n(v_fo, 'pactadas') = 1 and pg_temp.n(v_fo, 'debieron_ocurrir') = 1
      and pg_temp.n(v_fo, 'canceladas_sistema_vencidas') = 1 and pg_temp.n(v_fo, 'realizadas') = 0
      and pg_temp.n(v_fo, 'divisor_realizacion') = 0 and (v_fo -> 'pct_realizacion') = 'null'::jsonb
      and pg_temp.n(v_r1 -> 'resumen', 'pactadas') = 1 and pg_temp.n(v_r1 -> 'resumen', 'divisor_realizacion') = 0
      and (v_r1 -> 'resumen' -> 'pct_realizacion') = 'null'::jsonb,
    format('D3 no es «solo la fila Otros, con 1 pactada, 1 cancelada por el sistema, divisor 0 y porcentaje nulo»: %s · Otros [%s]',
      pg_temp.nombres(v_r1, 'responsables'), pg_temp.txt(v_fo)));

  -- ── R8. Lo que ve cada rol en reuniones, CON: Gerencia y lector, lo de antes + lo nuevo; los demás, lo de antes (42501) ─
  for r in select * from (values ('gerencia', v_g), ('lector', v_dir), ('coordinacion', v_coord), ('supervisor', v_supv),
                                  ('analista', v_b), ('analista_a', v_a), ('suspendido', v_p), ('anonimo', null::uuid)) a(k, actor) loop
    for w in select * from (values ('vis', v_d1), ('vis2', v_d2)) x(k, dia) loop
      v_antes := current_setting('ensayo.' || w.k || '.con.' || r.k);
      v_despues := pg_temp.ve(r.actor, w.dia, w.dia);
      if r.k in ('gerencia', 'lector') then
        v_r1 := pg_temp.j(v_despues);
        perform pg_temp.exigir('R8-vis-con-' || r.k || '-' || w.k,
          v_r1 is not null and pg_temp.sin_lo_nuevo(v_r1, 'responsables')::text = v_antes
            and pg_temp.marcas(v_r1, 'responsables', 'responsable_id') <> '',
          format('%s, con, no ve «lo de antes + lo nuevo» en %s: antes «%s» · después «%s»', r.k, w.k, left(v_antes, 80), left(v_despues, 80)));
      else
        perform pg_temp.exigir('R8-vis-con-' || r.k || '-' || w.k,
          v_despues = v_antes and v_antes like 'error 42501 %',
          format('%s, con, no recibe lo mismo que antes (42501) en %s: antes «%s» · después «%s»', r.k, w.k, left(v_antes, 80), left(v_despues, 80)));
      end if;
    end loop;
  end loop;

  -- ── G1–G5. La agenda (Gerencia, lector, supervisor y analista; cuatro ventanas) ────────────────────────────────────
  for r in select * from (values
      ('gerencia', v_g, array[v_a::text || ':de_baja', v_s::text || ':de_baja', v_p::text || ':suspendido', v_q1::text || ':de_baja'],
                        array[v_q1::text || ':de_baja']),
      ('lector', v_dir, array[v_a::text || ':de_baja', v_s::text || ':de_baja', v_p::text || ':suspendido', v_q1::text || ':de_baja'],
                        array[v_q1::text || ':de_baja']),
      ('supervisor', v_supv, array[v_a::text || ':de_baja', v_p::text || ':suspendido'], array[]::text[]),
      ('analista', v_b, array[]::text[], array[]::text[])) a(k, actor, marcas_periodo, marcas_d1d2) loop
    for w in select * from (values ('hoy', v_hoy, v_hoy), ('semana', v_hoy - 6, v_hoy), ('mes', v_mes, v_hoy),
                                    ('d1d2', v_d1, v_d2)) x(k, desde, hasta) loop
      v_antes := current_setting('ensayo.ag.con.' || r.k || '.' || w.k);
      v_despues := pg_temp.agenda(r.actor, w.desde, w.hasta);
      v_r1 := pg_temp.j(v_despues);
      v_esp := pg_temp.esperado_agenda(pg_temp.agenda_impl(r.actor, w.desde, w.hasta));
      perform pg_temp.exigir('G1-' || r.k || '-' || w.k,
        v_r1 is not null and v_r1 = v_esp,
        format('la agenda de %s (%s) no es la esperada a partir de su implementación: servida %s · esperada %s',
          r.k, w.k, pg_temp.nombres(v_r1, 'vendedores'), pg_temp.nombres(v_esp, 'vendedores')));
      perform pg_temp.exigir('G2-' || r.k || '-' || w.k,
        v_r1 is not null and pg_temp.sin_lo_nuevo(v_r1, 'vendedores')::text = v_antes,
        format('la agenda de %s (%s), quitando los marcados, NO es la de antes (antes %s bytes, después %s)',
          r.k, w.k, length(v_antes), length(v_despues)));
      v_marcas_esperadas := pg_temp.marcas_de(case when w.k = 'd1d2' then r.marcas_d1d2 else r.marcas_periodo end);
      perform pg_temp.exigir('G3-' || r.k || '-' || w.k,
        pg_temp.marcas(v_r1, 'vendedores', 'vendedor_id') = v_marcas_esperadas,
        format('las marcas de la agenda de %s (%s) no son las del escenario: servidas [%s] · esperadas [%s]',
          r.k, w.k, pg_temp.marcas(v_r1, 'vendedores', 'vendedor_id'), v_marcas_esperadas));
      v_txt := pg_temp.contrato_agenda(v_r1);
      perform pg_temp.exigir('G5-' || r.k || '-' || w.k, v_txt = '',
        format('la agenda de %s (%s) rompe el contrato de la app o sus marcas: %s', r.k, w.k, v_txt));
      perform pg_temp.medir(format('medida agenda con %s %s: %s bytes antes, %s después · marcas [%s]',
        r.k, w.k, length(v_antes), length(v_despues), pg_temp.marcas(v_r1, 'vendedores', 'vendedor_id')));
    end loop;
  end loop;

  -- ── G4. Siguen FUERA de la agenda: Q2 (de baja sin nada), R (suspendido con solo rezago) y M (desalineado) ───────────
  v_impl := pg_temp.agenda_impl(v_g, v_hoy - 6, v_hoy);
  v_r1 := pg_temp.j(pg_temp.agenda(v_g, v_hoy - 6, v_hoy));
  perform pg_temp.exigir('G4-montaje',
    pg_temp.fila(v_impl, 'vendedores', 'vendedor_id', v_q2::text) is not null
      and not pg_temp.tiene_actividad(pg_temp.fila(v_impl, 'vendedores', 'vendedor_id', v_q2::text))
      and pg_temp.fila(v_impl, 'vendedores', 'vendedor_id', v_r::text) is not null
      and not pg_temp.tiene_actividad(pg_temp.fila(v_impl, 'vendedores', 'vendedor_id', v_r::text))
      and pg_temp.n(pg_temp.fila(v_impl, 'vendedores', 'vendedor_id', v_r::text), 'leads_sin_accion') > 0
      and pg_temp.tiene_actividad(pg_temp.fila(v_impl, 'vendedores', 'vendedor_id', v_m::text))
      and pg_temp.n(pg_temp.fila(v_impl, 'vendedores', 'vendedor_id', v_q1::text), 'pendientes') = 1
      and pg_temp.n(pg_temp.fila(v_impl, 'vendedores', 'vendedor_id', v_q1::text), 'tareas_creadas') = 0,
    format('el montaje de la agenda no es el del escenario: Q2 [%s] · R [%s] · M [%s] · Q1 [%s]',
      pg_temp.txt(pg_temp.fila(v_impl, 'vendedores', 'vendedor_id', v_q2::text)),
      pg_temp.txt(pg_temp.fila(v_impl, 'vendedores', 'vendedor_id', v_r::text)),
      pg_temp.txt(pg_temp.fila(v_impl, 'vendedores', 'vendedor_id', v_m::text)),
      pg_temp.txt(pg_temp.fila(v_impl, 'vendedores', 'vendedor_id', v_q1::text))));
  perform pg_temp.exigir('G4-sin-actividad-fuera',
    v_r1 is not null
      and pg_temp.fila(v_r1, 'vendedores', 'vendedor_id', v_q2::text) is null
      and pg_temp.fila(v_r1, 'vendedores', 'vendedor_id', v_r::text) is null,
    format('aparece en la agenda un de baja o suspendido SIN actividad (Q2 [%s] · R [%s])',
      pg_temp.txt(pg_temp.fila(v_r1, 'vendedores', 'vendedor_id', v_q2::text)),
      pg_temp.txt(pg_temp.fila(v_r1, 'vendedores', 'vendedor_id', v_r::text))));
  perform pg_temp.exigir('G4-desalineado-fuera',
    v_r1 is not null and pg_temp.fila(v_r1, 'vendedores', 'vendedor_id', v_m::text) is null,
    format('aparece en la agenda el analista desalineado M (ficha y perfil activos, sin rol efectivo): [%s]',
      pg_temp.txt(pg_temp.fila(v_r1, 'vendedores', 'vendedor_id', v_m::text))));
  perform pg_temp.medir(format('medida agenda (Gerencia, semana): A [%s] · P [%s] · Q1 [%s]',
    pg_temp.txt(pg_temp.fila(v_r1, 'vendedores', 'vendedor_id', v_a::text)),
    pg_temp.txt(pg_temp.fila(v_r1, 'vendedores', 'vendedor_id', v_p::text)),
    pg_temp.txt(pg_temp.fila(v_r1, 'vendedores', 'vendedor_id', v_q1::text))));

  -- ── G6. Agenda: quien no consulta (Coordinación) o ya no puede (A de baja, P suspendido, anónimo): lo de antes ──────
  for r in select * from (values ('coordinacion', v_coord), ('analista_a', v_a), ('suspendido', v_p), ('anonimo', null::uuid)) a(k, actor) loop
    for w in select * from (values ('hoy', v_hoy, v_hoy), ('semana', v_hoy - 6, v_hoy), ('mes', v_mes, v_hoy),
                                    ('d1d2', v_d1, v_d2)) x(k, desde, hasta) loop
      v_antes := current_setting('ensayo.ag.con.' || r.k || '.' || w.k);
      v_despues := pg_temp.agenda(r.actor, w.desde, w.hasta);
      perform pg_temp.exigir('G6-' || r.k || '-' || w.k,
        v_despues = v_antes and v_antes like 'error 42501 %',
        format('%s, con, no recibe lo de antes (42501) en la agenda %s: antes «%s» · después «%s»', r.k, w.k, left(v_antes, 80), left(v_despues, 80)));
    end loop;
  end loop;

  -- ── O1. Las otras tres métricas del filtro común: byte a byte las de antes ──────────────────────────────────────────
  for r in select * from (values ('conversiones'), ('conversiones_equipo'), ('conversion_mensual')) m(k) loop
    v_antes := current_setting('ensayo.otra.' || r.k);
    v_despues := pg_temp.otra(v_g, r.k, v_mes, v_hoy);
    perform pg_temp.exigir('O1-' || r.k,
      v_despues = v_antes and v_antes not like 'error %',
      format('la métrica %s cambió con el 2.12 o no respondió (antes %s bytes «%s», después %s bytes «%s»)',
        r.k, length(v_antes), left(v_antes, 60), length(v_despues), left(v_despues, 60)));
  end loop;

  -- ── K6–K8. Evidencia de las definiciones (con) ──────────────────────────────────────────────────────────────────────
  perform pg_temp.exigir('K6-fk-ficha',
    exists (select 1 from pg_constraint c
             where c.conname = 'tareas_vendedor_id_fkey' and c.conrelid = 'crm.tareas'::regclass and c.contype = 'f'
               and c.confrelid = 'crm.equipo'::regclass and c.convalidated and c.confdeltype = 'n'),
    'ya no está la FK crm.tareas.vendedor_id → crm.equipo (validada, on delete set null)');
  perform pg_temp.exigir('K7-regla-de-baja-de-produccion',
    private.analista_dado_de_baja(v_a) and private.analista_dado_de_baja(v_s) and private.analista_dado_de_baja(v_q1)
      and not private.analista_dado_de_baja(v_b) and not private.analista_dado_de_baja(v_p),
    format('la marca «de baja» no coincide con la regla de producción private.analista_dado_de_baja: A=%s S=%s Q1=%s B=%s P=%s (esperado t t t f f)',
      private.analista_dado_de_baja(v_a), private.analista_dado_de_baja(v_s), private.analista_dado_de_baja(v_q1),
      private.analista_dado_de_baja(v_b), private.analista_dado_de_baja(v_p)));
  perform pg_temp.exigir('K8-suspendido-definicion',
    (select e.activo from crm.equipo e where e.perfil_id = v_p) is true
      and (select p.activo from public.perfiles p where p.id = v_p) is not true
      and (select e.activo from crm.equipo e where e.perfil_id = v_r) is true
      and (select p.activo from public.perfiles p where p.id = v_r) is not true
      and private.rol_crm(v_p) is null and private.rol_crm(v_m) is null,
    'P y R no son «suspendidos en el Portal» (ficha activa, perfil activo is not true) o M tiene rol efectivo');

  -- ══════════════════ SIN (A, S, X y Q1 reactivados; P con el perfil activo) ══════════════════════════════════════════
  execute 'set local session_replication_role = replica';
  update crm.equipo e set activo = true where e.perfil_id in (v_a, v_s, v_x, v_q1);
  update public.perfiles p set activo = true where p.id = v_p;
  execute 'set local session_replication_role = origin';

  -- ── S1. Reuniones: la esperada; sin «Otros» en la ventana, byte a byte la de antes; con «Otros», la de antes + «Otros» ──
  for w in select * from (values ('d1', v_d1, v_d1), ('d2', v_d2, v_d2), ('d3', v_d3, v_d3), ('hoy', v_hoy, v_hoy),
                                  ('mes', v_mes, v_hoy), ('anio', v_hoy - 365, v_hoy)) x(k, desde, hasta) loop
    v_antes := current_setting('ensayo.sin.' || w.k);
    v_despues := pg_temp.puerta(v_g, w.desde, w.hasta);
    v_r1 := pg_temp.j(v_despues);
    v_esp := pg_temp.esperado_reuniones(pg_temp.implementacion(v_g, w.desde, w.hasta));
    v_ok := v_r1 is not null and v_r1 = v_esp
            and pg_temp.marcas(v_r1, 'responsables', 'responsable_id') in ('', '-:otros')
            and case when pg_temp.marcas(v_r1, 'responsables', 'responsable_id') = '' then v_despues = v_antes
                     else pg_temp.sin_lo_nuevo(v_r1, 'responsables')::text = v_antes end;
    perform pg_temp.exigir('S1-sin-' || w.k, v_ok,
      format('sin bajas ni suspendidos, la ventana %s no es «la de antes» (+ «Otros» si la implementación deja a alguien fuera): marcas [%s] · %s bytes antes, %s después',
        w.k, pg_temp.marcas(v_r1, 'responsables', 'responsable_id'), length(v_antes), length(v_despues)));
    perform pg_temp.exigir('S1-cuadra-' || w.k, pg_temp.cuadra(v_r1),
      format('sin bajas, el desglose de la ventana %s no suma el total (total − desglose: %s)', w.k, coalesce(pg_temp.fuera(v_r1), '-')));
    v_txt := pg_temp.contrato_app(v_r1);
    perform pg_temp.exigir('R7-contrato-app-sin-' || w.k, v_txt = '',
      format('la pantalla rechazaría la respuesta sin bajas de la ventana %s: %s', w.k, v_txt));
    perform pg_temp.medir(format('medida reuniones sin %s: %s bytes antes, %s después · marcas [%s]',
      w.k, length(v_antes), length(v_despues), pg_temp.marcas(v_r1, 'responsables', 'responsable_id')));
  end loop;

  -- ── S2. Agenda: byte a byte la de antes, en cada rol y ventana ─────────────────────────────────────────────────────
  for r in select * from (values ('gerencia', v_g), ('lector', v_dir), ('supervisor', v_supv), ('analista', v_b),
                                  ('coordinacion', v_coord), ('analista_a', v_a), ('suspendido', v_p), ('anonimo', null::uuid)) a(k, actor) loop
    for w in select * from (values ('hoy', v_hoy, v_hoy), ('semana', v_hoy - 6, v_hoy), ('mes', v_mes, v_hoy),
                                    ('d1d2', v_d1, v_d2)) x(k, desde, hasta) loop
      v_antes := current_setting('ensayo.ag.sin.' || r.k || '.' || w.k);
      v_despues := pg_temp.agenda(r.actor, w.desde, w.hasta);
      perform pg_temp.exigir('S2-sin-' || r.k || '-' || w.k,
        v_despues = v_antes,
        format('sin bajas ni suspendidos con actividad, la agenda de %s (%s) NO es byte a byte la de antes (%s bytes antes, %s después; marcas después [%s])',
          r.k, w.k, length(v_antes), length(v_despues), pg_temp.marcas(pg_temp.j(v_despues), 'vendedores', 'vendedor_id')));
    end loop;
  end loop;

  -- ── S3. Lo que ve cada rol en reuniones, SIN: byte a byte lo de antes (D1) y lo de antes + «Otros» (D2) ──────────────
  for r in select * from (values ('gerencia', v_g), ('lector', v_dir), ('coordinacion', v_coord), ('supervisor', v_supv),
                                  ('analista', v_b), ('analista_a', v_a), ('suspendido', v_p), ('anonimo', null::uuid)) a(k, actor) loop
    v_antes := current_setting('ensayo.vis.sin.' || r.k);
    v_despues := pg_temp.ve(r.actor, v_d1, v_d1);
    perform pg_temp.exigir('S3-vis-sin-' || r.k,
      v_despues = v_antes
        and case when r.k in ('gerencia', 'lector') then v_antes not like 'error %' else v_antes like 'error 42501 %' end,
      format('%s, sin, no recibe byte a byte lo de antes en D1: antes «%s» · después «%s»', r.k, left(v_antes, 80), left(v_despues, 80)));
    v_antes := current_setting('ensayo.vis2.sin.' || r.k);
    v_despues := pg_temp.ve(r.actor, v_d2, v_d2);
    perform pg_temp.exigir('S3-vis2-sin-' || r.k,
      case when r.k in ('gerencia', 'lector')
           then pg_temp.j(v_despues) is not null and pg_temp.sin_lo_nuevo(pg_temp.j(v_despues), 'responsables')::text = v_antes
                and pg_temp.marcas(pg_temp.j(v_despues), 'responsables', 'responsable_id') = '-:otros'
           else v_despues = v_antes and v_antes like 'error 42501 %' end,
      format('%s, sin, no recibe en D2 lo de antes (+ «Otros» si es Gerencia o lector): antes «%s» · después «%s»', r.k, left(v_antes, 80), left(v_despues, 80)));
  end loop;

  -- ══════════════════ P1. P suspendido con el perfil `activo` NULO (la definición del CRM es `is not true`) ══════════════
  execute 'set local session_replication_role = replica';
  update public.perfiles p set activo = null where p.id = v_p;
  execute 'set local session_replication_role = origin';
  v_r1 := pg_temp.j(pg_temp.puerta(v_g, v_d2, v_d2));
  v_r2 := pg_temp.j(pg_temp.agenda(v_g, v_hoy, v_hoy));
  perform pg_temp.exigir('P1-suspendido-perfil-nulo',
    (pg_temp.fila(v_r1, 'responsables', 'responsable_id', v_p::text) -> 'suspendido') = 'true'::jsonb
      and (pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_p::text) -> 'suspendido') = 'true'::jsonb,
    format('con el perfil activo NULO, P no sale «suspendido» (reuniones [%s] · agenda [%s])',
      pg_temp.txt(pg_temp.fila(v_r1, 'responsables', 'responsable_id', v_p::text)),
      pg_temp.txt(pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_p::text))));

  -- ══════════════════ P2. Un marcado con el nombre vacío o en blanco sale como «(sin nombre)» ═════════════════════════
  -- Q1 vuelve a estar de baja (con su pendiente) y con el nombre VACÍO; P sigue suspendido (perfil nulo) con el nombre EN BLANCO.
  execute 'set local session_replication_role = replica';
  update crm.equipo e set activo = false where e.perfil_id = v_q1;
  update public.perfiles p set nombre_completo = '' where p.id = v_q1;
  update public.perfiles p set nombre_completo = E' \t ' where p.id = v_p;
  execute 'set local session_replication_role = origin';
  v_r1 := pg_temp.j(pg_temp.agenda(v_g, v_hoy, v_hoy));
  v_esp := pg_temp.esperado_agenda(pg_temp.agenda_impl(v_g, v_hoy, v_hoy));
  v_r2 := pg_temp.j(pg_temp.puerta(v_g, v_d2, v_d2));
  v_impl := pg_temp.esperado_reuniones(pg_temp.implementacion(v_g, v_d2, v_d2));
  perform pg_temp.exigir('P2-marcado-sin-nombre',
    (pg_temp.fila(v_r1, 'vendedores', 'vendedor_id', v_q1::text) ->> 'nombre') = '(sin nombre)'
      and (pg_temp.fila(v_r1, 'vendedores', 'vendedor_id', v_q1::text) -> 'de_baja') = 'true'::jsonb
      and (pg_temp.fila(v_r1, 'vendedores', 'vendedor_id', v_p::text) ->> 'nombre') = '(sin nombre)'
      and (pg_temp.fila(v_r1, 'vendedores', 'vendedor_id', v_p::text) -> 'suspendido') = 'true'::jsonb
      and (pg_temp.fila(v_r2, 'responsables', 'responsable_id', v_p::text) ->> 'nombre') = '(sin nombre)'
      and (pg_temp.fila(v_r2, 'responsables', 'responsable_id', v_p::text) -> 'suspendido') = 'true'::jsonb
      and v_r1 = v_esp and v_r2 = v_impl and pg_temp.contrato_agenda(v_r1) = '',
    format('un marcado con el nombre vacío o en blanco no sale como «(sin nombre)» o la respuesta no es la esperada (agenda Q1 [%s] · agenda P [%s] · reuniones P [%s] · contrato de la agenda: %s)',
      pg_temp.txt(pg_temp.fila(v_r1, 'vendedores', 'vendedor_id', v_q1::text)),
      pg_temp.txt(pg_temp.fila(v_r1, 'vendedores', 'vendedor_id', v_p::text)),
      pg_temp.txt(pg_temp.fila(v_r2, 'responsables', 'responsable_id', v_p::text)),
      coalesce(nullif(pg_temp.contrato_agenda(v_r1), ''), 'bien')));

  -- ══════════════════ P3. Ficha inactiva y perfil inactivo (A) o NULO (S), con actividad: SOLO «de baja» ══════════════════
  execute 'set local session_replication_role = replica';
  update crm.equipo e set activo = false where e.perfil_id in (v_a, v_s);
  update public.perfiles p set activo = false where p.id = v_a;
  update public.perfiles p set activo = null where p.id = v_s;
  execute 'set local session_replication_role = origin';
  v_r1 := pg_temp.j(pg_temp.puerta(v_g, v_d1, v_d1));
  v_r2 := pg_temp.j(pg_temp.agenda(v_g, v_hoy, v_hoy));
  perform pg_temp.exigir('P3-baja-gana-a-suspension',
    (select bool_and((x -> 'de_baja') = 'true'::jsonb and not (x ? 'suspendido'))
       from jsonb_array_elements(v_r1 -> 'responsables') x where x ->> 'responsable_id' in (v_a::text, v_s::text))
      and (select count(*) from jsonb_array_elements(v_r1 -> 'responsables') x where x ->> 'responsable_id' in (v_a::text, v_s::text)) = 2
      and (select bool_and((x -> 'de_baja') = 'true'::jsonb and not (x ? 'suspendido') and (x -> 'activo') = 'false'::jsonb)
             from jsonb_array_elements(v_r2 -> 'vendedores') x where x ->> 'vendedor_id' in (v_a::text, v_s::text))
      and (select count(*) from jsonb_array_elements(v_r2 -> 'vendedores') x where x ->> 'vendedor_id' in (v_a::text, v_s::text)) = 2
      and v_r1 = pg_temp.esperado_reuniones(pg_temp.implementacion(v_g, v_d1, v_d1))
      and v_r2 = pg_temp.esperado_agenda(pg_temp.agenda_impl(v_g, v_hoy, v_hoy))
      and pg_temp.contrato_agenda(v_r2) = '' and pg_temp.contrato_app(v_r1) = '',
    format('con la ficha inactiva y el perfil inactivo (A) o nulo (S), no salen SOLO «de baja» (reuniones A [%s] · S [%s] · agenda A [%s] · S [%s])',
      pg_temp.txt(pg_temp.fila(v_r1, 'responsables', 'responsable_id', v_a::text)),
      pg_temp.txt(pg_temp.fila(v_r1, 'responsables', 'responsable_id', v_s::text)),
      pg_temp.txt(pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_a::text)),
      pg_temp.txt(pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_s::text))));

  -- ══════════════════ P4. Actividad por UNA sola clave: solo un toque (R) o solo una reprogramación (Q2) ════════════════
  execute 'set local session_replication_role = replica';
  insert into crm.actividades (lead_id, tipo, creado_por)
  select l.id, 'whatsapp_enviado', v_r from crm.leads l where l.vendedor_id = v_r and l.nombre_completo = 'ENSAYO 2.12 · R';
  insert into crm.tareas (lead_id, vendedor_id, tipo, titulo, vence_en, estado, reprogramaciones, activo, creado_por, creado_en)
  values (pg_temp.lead(v_q2, 'ENSAYO 2.12 · Q2', 'contactado'), v_q2, 'llamada', 'Q2 llamada movida',
          (v_d1::timestamp at time zone 'America/Lima') + interval '11 hours', 'reprogramada', 1, true, v_q2,
          (v_d1::timestamp at time zone 'America/Lima') + interval '11 hours');
  execute 'set local session_replication_role = origin';
  v_r2 := pg_temp.j(pg_temp.agenda(v_g, v_hoy, v_hoy));
  v_esp := pg_temp.esperado_agenda(pg_temp.agenda_impl(v_g, v_hoy, v_hoy));
  perform pg_temp.exigir('P4-actividad-de-una-sola-clave',
    (pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_r::text) -> 'suspendido') = 'true'::jsonb
      and pg_temp.n(pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_r::text), 'toques') = 1
      and pg_temp.n(pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_r::text), 'tareas_creadas')
          + pg_temp.n(pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_r::text), 'pendientes')
          + pg_temp.n(pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_r::text), 'completadas') = 0
      and (pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_q2::text) -> 'de_baja') = 'true'::jsonb
      and pg_temp.n(pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_q2::text), 'reprogramaciones') = 1
      and pg_temp.n(pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_q2::text), 'toques')
          + pg_temp.n(pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_q2::text), 'tareas_creadas')
          + pg_temp.n(pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_q2::text), 'pendientes') = 0
      and v_r2 = v_esp and pg_temp.contrato_agenda(v_r2) = '',
    format('con UNA sola clave de actividad no aparecen marcados (R, solo un toque [%s] · Q2, solo una reprogramación [%s])',
      pg_temp.txt(pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_r::text)),
      pg_temp.txt(pg_temp.fila(v_r2, 'vendedores', 'vendedor_id', v_q2::text))));

  -- ══════════════════ K. Catálogo ═══════════════════════════════════════════════════════════════════════════════════
  perform pg_temp.exigir('K1-ficha-puerta-reuniones',
    exists (select 1 from pg_proc p
             where p.oid = 'crm.metricas_reuniones_fn(date,date)'::regprocedure
               and p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.provolatile = 's'
               and p.proconfig = array['search_path=""'])
      and (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
             from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            where p.oid = 'crm.metricas_reuniones_fn(date,date)'::regprocedure)
          = array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false']
      and not has_function_privilege('anon', 'crm.metricas_reuniones_fn(date,date)', 'EXECUTE')
      and position('private.desglose_responsables_reuniones_crm(' in
                   (select p.prosrc from pg_proc p where p.oid = 'crm.metricas_reuniones_fn(date,date)'::regprocedure)) > 0,
    'la puerta crm.metricas_reuniones_fn no llama a la pieza de reuniones o cambió de dueño, atributos o permisos');
  perform pg_temp.exigir('K1-ficha-puerta-agenda',
    exists (select 1 from pg_proc p
             where p.oid = 'crm.metricas_agenda_fn(date,date)'::regprocedure
               and p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.provolatile = 's'
               and p.proconfig = array['search_path=""'])
      and (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
             from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            where p.oid = 'crm.metricas_agenda_fn(date,date)'::regprocedure)
          = array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false']
      and not has_function_privilege('anon', 'crm.metricas_agenda_fn(date,date)', 'EXECUTE')
      and position('private.filtrar_desglose_sujetos_con_bajas_crm(' in
                   (select p.prosrc from pg_proc p where p.oid = 'crm.metricas_agenda_fn(date,date)'::regprocedure)) > 0,
    'la puerta crm.metricas_agenda_fn no llama a la pieza con bajas o cambió de dueño, atributos o permisos');
  select string_agg(f, ', ') into v_det
    from unnest(array['private.filtrar_desglose_sujetos_con_bajas_crm(jsonb,text,text,text[],text[])',
                      'private.desglose_responsables_reuniones_crm(jsonb)']) f
   where not exists (select 1 from pg_proc p
                      where p.oid = to_regprocedure(f)
                        and p.proowner = 'postgres'::regrole::oid and not p.prosecdef and p.provolatile = 's'
                        and p.proconfig = array['search_path=""'])
      or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
            from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
           where p.oid = to_regprocedure(f)) is distinct from array['postgres:EXECUTE:false'];
  perform pg_temp.exigir('K2-ficha-piezas', v_det is null,
    'una pieza nueva no existe o no es de postgres, security invoker, STABLE, con search_path vacío y EXECUTE solo para el dueño: ' || coalesce(v_det, ''));
  perform pg_temp.exigir('K3-puerta-agenda-claves',
    position($c$array['toques','reuniones_realizadas','completadas','no_asistio','canceladas',
          'tareas_creadas','reuniones_agendadas','reprogramaciones','pendientes']$c$ in
             coalesce((select p.prosrc from pg_proc p where p.oid = 'crm.metricas_agenda_fn(date,date)'::regprocedure), '')) > 0,
    'la puerta de la agenda no pasa EXACTAMENTE las nueve claves de actividad de la app (agenda-equipo-vista.ts:138-150)');
  select string_agg(e.objeto, ', ' order by e.objeto) into v_det
    from (values
      ('private.metricas_reuniones_implementacion(date,date)', 'ca6fe61e76bcb8bf2d213acb1b7fc030'),
      ('private.metricas_agenda_implementacion(date,date)', '0fc09f917a816013e1af16ef183012de'),
      ('private.filtrar_desglose_sujetos_crm(jsonb,text,text,text[])', '1cce2929af369715a2c7e161d63fc7ce'),
      ('private.rol_crm(uuid)', 'd2878a210be96ac85973d51dfcfb27a5'),
      ('private.es_lector_global()', 'c7c5828be6d74121a1a0ef0de374f712'),
      ('private.vendedor_ids_visibles(uuid)', '33ece9bae4828f7ffdb837c6128ca9d6'),
      -- 22/10/2026 (C3 ronda 2): las tres de conversiones re-asentadas a producción del 22/10 (las cambió 20261012165115; antes f6e43674…, 09e538d7…, 9c69b704…).
      ('crm.metricas_conversiones_fn(date,date,text)', '81d7f76d87de7cfaa5fbfdcf55a7a815'),
      ('crm.metricas_conversiones_equipo_fn(date,date)', '7ed26cadf9b1403cdef6b8c3b7146c64'),
      ('crm.conversion_mensual_sin_cartera_fn(date)', 'e09d2f03966d556d0010aafd7f4b05b1'),
      ('private.analista_dado_de_baja(uuid)', 'ac4600cb6bb2d304847652d8015cb328')
    ) e(objeto, huella)
   where e.huella is distinct from (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(e.objeto));
  perform pg_temp.exigir('K4-intactas', v_det is null,
    'cambió algo que el 2.12 no toca (md5(prosrc) distinto del del laboratorio): ' || coalesce(v_det, ''));
  perform pg_temp.exigir('K5-registro-analitico',
    (select e.huella from private.analitica_leads_citas_exenciones e
      where e.objeto = 'private.metricas_reuniones_implementacion(date,date)') = 'd54d4f8773cf1106dadbcb0d793575e2'
      and exists (select 1 from private.contadores_crudos_leads_citas() c
                   where c.objeto = 'private.metricas_reuniones_implementacion(date,date)' and c.declarada and c.huella_ok)
      and exists (select 1 from private.contadores_crudos_leads_citas() c
                   where c.objeto = 'private.metricas_agenda_implementacion(date,date)' and c.declarada and c.huella_ok)
      and (select s.sello from private.analitica_lc_sello s where s.id) is not distinct from private.huella_exenciones_analitica_lc()
      and not exists (select 1 from private.contadores_crudos_leads_citas() c
                       where c.objeto in ('crm.metricas_reuniones_fn(date,date)', 'crm.metricas_agenda_fn(date,date)',
                                          'private.filtrar_desglose_sujetos_con_bajas_crm(jsonb,text,text,text[],text[])',
                                          'private.desglose_responsables_reuniones_crm(jsonb)'))
      and not exists (select 1 from private.puertas_analista_sin_vigencia() c
                       where c.objeto in ('crm.metricas_reuniones_fn(date,date)', 'crm.metricas_agenda_fn(date,date)',
                                          'private.filtrar_desglose_sujetos_con_bajas_crm(jsonb,text,text,text[],text[])',
                                          'private.desglose_responsables_reuniones_crm(jsonb)')),
    'el registro analítico de las implementaciones no es el del laboratorio (exención d54d4f87…, declaradas y al día, sello coherente) o una puerta o pieza del 2.12 entró en un censo');

  -- ── Medidas (no juzgan: documentan) ───────────────────────────────────────────────────────────────────────────────
  perform pg_temp.medir(format('medida reloj: ahora %s Lima · D1 %s · D2 %s · mes %s a %s · año %s a %s',
    to_char(now() at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI:SS'), v_d1, v_d2, v_mes, v_hoy, v_hoy - 365, v_hoy));
  perform pg_temp.medir(format('medida actores: gerencia=%s · otra gerencia (X, de baja)=%s · lector=%s · coordinación=%s · supervisor que consulta=%s · A=%s · B=%s · M (desalineado)=%s · S=%s · P (suspendido)=%s (sembrado: %s) · R (suspendido sin actividad)=%s · Q1=%s · Q2=%s · sin ficha=%s',
    (select nombre_completo from public.perfiles where id = v_g), (select nombre_completo from public.perfiles where id = v_x),
    coalesce((select nombre_completo from public.perfiles where id = v_dir), '-'), (select nombre_completo from public.perfiles where id = v_coord),
    (select nombre_completo from public.perfiles where id = v_supv), (select nombre_completo from public.perfiles where id = v_a),
    (select nombre_completo from public.perfiles where id = v_b), (select nombre_completo from public.perfiles where id = v_m),
    (select nombre_completo from public.perfiles where id = v_s), (select nombre_completo from public.perfiles where id = v_p),
    current_setting('ensayo.p_sembrado'), (select nombre_completo from public.perfiles where id = v_r),
    (select nombre_completo from public.perfiles where id = v_q1), (select nombre_completo from public.perfiles where id = v_q2),
    (select coalesce(nombre_completo, '?') || ' (rol del Portal ' || coalesce(rol, '?') || ')' from public.perfiles where id = v_z)));
  perform pg_temp.medir('medida neutralizadas en el montaje: ' || current_setting('ensayo.neutralizadas'));
  perform pg_temp.medir(format('medida huellas: puerta de reuniones %s · puerta de agenda %s · pieza con bajas %s · pieza de reuniones %s',
    (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.metricas_reuniones_fn(date,date)'::regprocedure),
    (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.metricas_agenda_fn(date,date)'::regprocedure),
    coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.filtrar_desglose_sujetos_con_bajas_crm(jsonb,text,text,text[],text[])')), 'no existe'),
    coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.desglose_responsables_reuniones_crm(jsonb)')), 'no existe')));

  -- ── Lo diferido se comprueba AHORA, no en un COMMIT que nunca llega ─────────────────────────────────────────────
  begin
    set constraints all immediate;
  exception when others then
    perform pg_temp.reg('K9', format(E'FALLO K9: algo de lo sembrado no sobreviviría al COMMIT (%s %s)\n', sqlstate, sqlerrm));
  end;

  -- ── Veredicto, y rollback SIEMPRE ───────────────────────────────────────────────────────────────────────────────
  raise exception E'ENSAYO %:\n%\n%\n%(rollback a propósito — nada queda escrito)',
    case when current_setting('ensayo.fallos')::integer = 0 then 'VERDE — 0 fallos'
         else format('ROJO — %s fallo(s)', current_setting('ensayo.fallos')) end,
    current_setting('ensayo.informe'),
    current_setting('ensayo.medidas'),
    current_setting('ensayo.oks');
end;
$ensayo$;
