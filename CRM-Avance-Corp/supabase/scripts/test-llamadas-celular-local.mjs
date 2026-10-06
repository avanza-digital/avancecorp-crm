#!/usr/bin/env node
// Prueba las migraciones REALES de Llamadas desde el celular (F2-b datos 20261001145242, F2-c
// núcleo 20261001160219, F3-a ingesta 20261001212258 y la corrección de elegibilidad 20261001222431)
// en un PostgreSQL 16/17 desechable: initdb en una carpeta temporal,
// escucha solo en 127.0.0.1, contraseña de usar y tirar generada aquí (nunca se imprime ni sale de
// la carpeta temporal) y se borra al terminar. Nunca acepta una URL ni variables PG* del entorno.
//
// Banco reducido: supabase/tests/llamadas-celular/base.sql (auditoría, regla de rastro, ámbito,
// canonización, idempotencia y forma del resultado reales; auth.uid como doble declarado).
// Molde: supabase/scripts/test-sla-nucleo-local.py. No sustituye el gate test-rls.mjs.
//
// Dieciocho pasadas:
//   1. Las migraciones tal cual: se aplican, se niegan a sobrescribirse, pasan sus oráculos, sus
//      reversas funcionan en orden (y se niegan fuera de orden o con filas) y se vuelven a aplicar.
//   2–5. Mutantes de F2-b, F2-c, F3-a y la corrección de elegibilidad: por cada defensa, una copia de
//      la migración que la neutraliza. Un mutante «de oráculo» tiene que APLICARSE y hacer fallar su
//      oráculo; uno «de postflight» tiene que ser rechazado por el postflight con su mensaje. Si
//      sobrevive, esa defensa no está probada.
//   6. Concurrencia con dos sesiones REALES: la primera abre su transacción y la retiene; la
//      segunda llega mientras tanto, tiene que ESPERAR (se mide) y responder bien al soltarse.
//   7. La QUINTA (20261005143843, corrección de F2 + F3) sobre las cuatro: se aplica, se niega a
//      repetirse y con filas, pasa su oráculo, su reversa vuelve a la huella exacta del catálogo de las
//      cuatro (y se niega tras el primer aviso), y las reversas viejas se niegan mientras siga puesta.
//   8. Mutantes de la quinta (oráculo o postflight, como en 2–5).
//   9. Concurrencia de la quinta con dos sesiones reales (cierre durante un latido, reasignación durante
//      descartar, asociar y enlazar, Deshacer durante enlazar en los dos órdenes, mismo id a la vez, la
//      llamada que cambia mientras se asocia) y mutantes de candados: cada uno quita un candado y su
//      carrera tiene que dejar de comportarse bien.
//  10. F4-a (20261005155914, enlace exacto) sobre las cinco, con la v4 como doble declarado (base.sql): se
//      aplica, se niega a repetirse, pasa su oráculo y el de la quinta, la reversa de la quinta se niega
//      con F4-a puesta y la suya vuelve a la huella exacta de las cinco (y se niega con enlaces).
//  11. Mutantes de F4-a.
//  12. Carreras de F4-a: el aviso llega mientras se guarda la encuesta y al revés, dos encuestas con el
//      mismo id y Deshacer mientras la ingesta cumple la intención.
//  13. La SÉPTIMA (20261005182227, enlace sin ciclo con Deshacer) sobre las seis: se aplica, se niega a
//      repetirse, pasan los oráculos de F4-a y de la quinta, la reversa de F4-a se niega con ella puesta y la
//      suya vuelve a la huella exacta de las seis (también con datos: solo cambia cuerpos).
//  14. Carreras de la séptima: Deshacer PAUSADO entre sus dos candados (resultado → lead) con el aviso o un
//      reintento de la v5 en medio, en los dos órdenes y con Deshacer revertido; las de F4-a otra vez; un
//      control sin la séptima que reproduce el interbloqueo de la revisión de Miguel (#190); y mutantes que
//      la carrera tiene que cazar.
//  15. La OCTAVA (20261005201010, lecturas de F4-b) sobre las siete: se aplica, se niega a repetirse, pasan su
//      oráculo y los de F4-a y la quinta, las reversas de la séptima y F4-a se niegan con ella puesta, la suya
//      vuelve a la huella exacta de las siete; y sus mutantes.
//  16. La NOVENA (20261005224330, «Qué pasó hoy» paginada y por la hora de resolución) sobre las ocho: se niega sin la
//      octava, se aplica, se niega a repetirse, pasan su oráculo y los de F4-a y la quinta, la reversa de la octava se
//      niega con ella puesta, la suya vuelve a la huella exacta de las ocho; y sus mutantes.
//  17. La DÉCIMA (20261006150154, id de origen en la bandeja y el detalle) sobre las nueve, con el mismo recorrido.
//  18. La UNDÉCIMA (20261006150254, salud de los celulares sin la hora exacta del latido) sobre las diez, igual.
//
// Uso:  node supabase/scripts/test-llamadas-celular-local.mjs     (npm run test:llamadas:local)
// Binarios: LLAMADAS_PG_BIN, o ~/.local/pg/pgsql/bin (zip oficial de EDB en Windows), o Homebrew.
import { spawn, spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = fileURLToPath(new URL('../..', import.meta.url));
const MIG_DATOS = join(RAIZ, 'supabase/migrations/20261001145242_crm_llamadas_celular_datos.sql');
const MIG_NUCLEO = join(RAIZ, 'supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql');
const MIG_INGESTA = join(RAIZ, 'supabase/migrations/20261001212258_crm_llamadas_celular_ingesta.sql');
const MIG_ELEGIBILIDAD = join(RAIZ, 'supabase/migrations/20261001222431_crm_llamadas_celular_elegibilidad_dueno.sql');
const ORACULO_ELEGIBILIDAD = join(RAIZ, 'supabase/tests/llamadas-celular/oraculo-elegibilidad.sql');
const REVERSA_ELEGIBILIDAD = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-elegibilidad.sql');
const BASE = join(RAIZ, 'supabase/tests/llamadas-celular/base.sql');
const ORACULO_DATOS = join(RAIZ, 'supabase/scripts/llamadas-celular/verificar-datos.sql');
const ORACULO_NUCLEO = join(RAIZ, 'supabase/tests/llamadas-celular/oraculo-nucleo.sql');
const ORACULO_INGESTA = join(RAIZ, 'supabase/tests/llamadas-celular/oraculo-ingesta.sql');
const REVERSA_DATOS = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-datos.sql');
const REVERSA_TOTAL = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-datos-total.sql');
const REVERSA_NUCLEO = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-nucleo.sql');
const REVERSA_INGESTA = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-ingesta.sql');
const MIG_CORRECCION = join(RAIZ, 'supabase/migrations/20261005143843_crm_llamadas_celular_correccion.sql');
const ORACULO_CORRECCION = join(RAIZ, 'supabase/tests/llamadas-celular/oraculo-correccion.sql');
const REVERSA_CORRECCION = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-correccion.sql');
const HUELLA = join(RAIZ, 'supabase/tests/llamadas-celular/huella-catalogo.sql');
const MIG_ENLACE = join(RAIZ, 'supabase/migrations/20261005155914_crm_llamadas_celular_enlace_exacto.sql');
const ORACULO_ENLACE = join(RAIZ, 'supabase/tests/llamadas-celular/oraculo-enlace-exacto.sql');
const REVERSA_ENLACE = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-enlace-exacto.sql');
const MIG_SIN_CICLO = join(RAIZ, 'supabase/migrations/20261005182227_crm_llamadas_celular_enlace_sin_ciclo.sql');
const REVERSA_SIN_CICLO = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-enlace-sin-ciclo.sql');
const MIG_LECTURAS = join(RAIZ, 'supabase/migrations/20261005201010_crm_llamadas_celular_lecturas_analista.sql');
const ORACULO_LECTURAS = join(RAIZ, 'supabase/tests/llamadas-celular/oraculo-lecturas-analista.sql');
const REVERSA_LECTURAS = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-lecturas-analista.sql');
const MIG_PAGINADAS = join(RAIZ, 'supabase/migrations/20261005224330_crm_llamadas_celular_resueltas_paginadas.sql');
const ORACULO_PAGINADAS = join(RAIZ, 'supabase/tests/llamadas-celular/oraculo-resueltas-paginadas.sql');
const REVERSA_PAGINADAS = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-resueltas-paginadas.sql');
const MIG_ORIGEN = join(RAIZ, 'supabase/migrations/20261006150154_crm_llamadas_celular_bandeja_con_origen.sql');
const ORACULO_ORIGEN = join(RAIZ, 'supabase/tests/llamadas-celular/oraculo-bandeja-con-origen.sql');
const REVERSA_ORIGEN = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-bandeja-con-origen.sql');
const MIG_SALUD = join(RAIZ, 'supabase/migrations/20261006150254_crm_llamadas_celular_salud_sin_hora.sql');
const ORACULO_SALUD = join(RAIZ, 'supabase/tests/llamadas-celular/oraculo-salud-sin-hora.sql');
const REVERSA_SALUD = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-salud-sin-hora.sql');
const PUERTO = '55485';
const USUARIO = 'llamadas_test_owner';
const EXE = process.platform === 'win32' ? '.exe' : '';

// Cada defensa y la copia de la migración que la neutraliza. `aviso` convierte su
// `raise exception` en `raise notice` (la regla sigue escrita, pero ya no frena nada);
// `ocurrencia`/`total` eligen cuál de varias iguales; `cambios` aplica varias a la vez.
const MUTANTES_DATOS = [
  { nombre: 'auditoría con el número a la vista', buscar: "log_audit_sin_secretos('numero_canonico', 'hash_payload')", poner: "log_audit_sin_secretos('hash_payload')" },
  { nombre: 'auditoría con el hash del payload a la vista', buscar: "log_audit_sin_secretos('numero_canonico', 'hash_payload')", poner: "log_audit_sin_secretos('numero_canonico')" },
  { nombre: 'auditoría con la credencial a la vista', buscar: "private.log_audit_sin_secretos('credencial_hash');", poner: 'private.log_audit_crm();' },
  { nombre: 'credencial que no es un sha256', buscar: "check (credencial_hash ~ '^[0-9a-f]{64}$')", poner: 'check (true)' },
  { nombre: 'DELETE de llamadas sin el GUC de la purga', buscar: "if coalesce(pg_catalog.current_setting('crm.op_purga_llamadas', true), 'off') = 'on'", poner: 'if true' },
  { nombre: 'payload editable', aviso: 'El contenido de una llamada del celular es inmutable' },
  { nombre: 'identificación que retrocede', aviso: 'La identificación de una llamada solo avanza' },
  { nombre: 'lead de una llamada registrada editable', aviso: 'Una llamada registrada o descartada no cambia de lead' },
  { nombre: 'transiciones de atención libres', aviso: 'Transición no permitida de la llamada' },
  { nombre: 'motivo de descarte reescribible', aviso: 'El motivo de un descarte no se reescribe' },
  { nombre: 'devolución pedida para una saliente', buscar: "and identificacion = 'identificado' and direccion = 'entrante')", poner: "and identificacion = 'identificado')" },
  { nombre: 'asociación manual sin autor', buscar: "or metodo_asociacion = 'exacto' or asociado_por is not null)", poner: 'or true)' },
  { nombre: 'descarte «otro» sin detalle', buscar: '>= 3))', poner: '>= 0))' },
  { nombre: 'enlace movible sin deshacer el resultado', buscar: 'if not coalesce(v_deshecha, false) then', poner: 'if false then' },
  { nombre: 'enlace desenlazable', aviso: 'Un enlace no se desenlaza' },
  { nombre: 'enlace a una actividad de otro lead', aviso: 'La actividad enlazada es de otro lead' },
  { nombre: 'enlace con lead distinto al de la llamada', aviso: 'El enlace debe apuntar al lead de la llamada' },
  { nombre: 'enlace a algo que no es un resultado de llamada', aviso: 'Solo se enlaza un resultado de llamada' },
  { nombre: 'enlace sin actividad', aviso: 'Un enlace nace con la actividad registrada' },
  { nombre: 'enlace borrable', aviso: 'El enlace de una llamada no se borra' },
  { nombre: 'asignación borrable', aviso: 'Una asignación de celular no se borra' },
  { nombre: 'asignación cerrada editable', aviso: 'Una asignación de celular cerrada es inmutable' },
  { nombre: 'asignación con analista editable', aviso: 'De una asignación de celular solo se cierra la vigencia' },
  { nombre: 'política borrable', aviso: 'La política de llamadas no se borra' },
  { nombre: 'tablas vaciables', aviso: '%s no se vacía: es evidencia de llamadas' },
  { nombre: 'purga sin plazo para descartadas', buscar: '\n     and e.descartado_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_descartados);', poner: ';' },
  { nombre: 'purga que deja el GUC encendido', buscar: "  perform pg_catalog.set_config('crm.op_purga_llamadas', 'off', true);\n", poner: '' },
  { nombre: 'sin exclusión de vigencias', por: 'postflight', espera: 'falta la exclusión',
    buscar: "exclude using gist (\n      etiqueta with =,\n      tstzrange(vigente_desde, coalesce(vigente_hasta, 'infinity'::timestamptz), '[)') with &&\n    )", poner: 'check (true)' },
  { nombre: 'RLS apagada en eventos', por: 'postflight', espera: 'quedó sin RLS',
    buscar: 'alter table crm.llamadas_celular_eventos enable row level security;\n', poner: '' },
  { nombre: 'enlaces abiertos a la API', por: 'postflight', espera: 'accesible desde la API',
    buscar: 'revoke all on crm.llamadas_celular_enlaces from public, anon, authenticated, service_role;', poner: 'grant select on crm.llamadas_celular_enlaces to authenticated;' },
  { nombre: 'autoría que se desatribuye (SET NULL)', por: 'postflight', espera: 'no es RESTRICT',
    buscar: 'descartado_por          uuid references public.perfiles(id) on delete restrict,', poner: 'descartado_por          uuid references public.perfiles(id) on delete set null,' },
  { nombre: 'FK sin índice', por: 'postflight', espera: 'sin índice que la cubra',
    buscar: 'create index llamadas_celular_eventos_descartado_por_idx\n  on crm.llamadas_celular_eventos (descartado_por);\n', poner: '' },
];

const AMBITO = 'Llamada no encontrada o fuera de tu ámbito';
const MUTANTES_NUCLEO = [
  { nombre: 'asociar sin exigir el número de la llamada', aviso: 'Ese lead no tiene el número de la llamada' },
  { nombre: 'asociar a un lead fuera de ámbito', aviso: 'Ese lead no es de tu ámbito' },
  { nombre: 'asociar una llamada que no se ve', aviso: AMBITO, ocurrencia: 1, total: 4 },
  { nombre: 'enlazar sin ámbito (decisión 7)', aviso: AMBITO, ocurrencia: 2, total: 4 },
  { nombre: 'descartar sin ámbito', aviso: AMBITO, ocurrencia: 3, total: 4 },
  { nombre: 'detalle sin ámbito', aviso: AMBITO, ocurrencia: 4, total: 4 },
  { nombre: 'reenvío con otro contenido aceptado', aviso: 'Esta llamada ya llegó con otro contenido' },
  { nombre: 'celular cerrado o analista de baja ingiere', aviso: 'Celular sin asignación vigente o analista inactivo' },
  { nombre: 'entrante guardada con la perilla apagada', buscar: "if v_dir = 'entrante' and not coalesce(v_pol.entrantes_activas, false) then", poner: 'if false then' },
  { nombre: 'número sin lead guardado con la perilla apagada', buscar: 'elsif coalesce(v_pol.guardar_sin_identificar, false) then', poner: 'elsif true then' },
  { nombre: 'hora sin normalizar en el hash', buscar: `'ocurrio_en', pg_catalog.to_char(v_ocurrio at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`, poner: "'ocurrio_en', v_ocurrio" },
  { nombre: 'enlace con un resultado anterior a la llamada', aviso: 'El resultado se registró antes de la llamada' },
  { nombre: 'resultado vigente reemplazado', buscar: 'if v_enl.actividad_id is not null and not coalesce(v_deshecha, false) then', poner: 'if false then' },
  { nombre: 'enlace a una llamada descartada', aviso: 'La llamada fue descartada' },
  { nombre: 'enlace a una llamada sin lead', aviso: 'Primero asocia la llamada a un lead' },
  { nombre: 'descarte reescrito con otro motivo', aviso: 'La llamada ya fue descartada con otro motivo' },
  { nombre: 'bandeja sin filtro de ámbito', buscar: '\n      and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)\n    order by e.recibido_en desc', poner: '\n    order by e.recibido_en desc' },
  { nombre: 'atención efectiva sin re-evaluar la elegibilidad', buscar: "when p_atencion = 'requiere_resultado' and private.llamada_celular_elegible(p_actor, p_lead)", poner: "when p_atencion = 'requiere_resultado'" },
  { nombre: 'credencial guardada en claro', buscar: 'values (p_etiqueta, p_analista_id, private.celular_credencial_hash(v_credencial), pg_catalog.clock_timestamp(), p_actor)', poner: 'values (p_etiqueta, p_analista_id, v_credencial, pg_catalog.clock_timestamp(), p_actor)' },
  { nombre: 'un analista asigna celulares (puerta y núcleo)', cambios: [
    { buscar: "  v_actor uuid := private.llamadas_celular_actor(array['gerencia']);\nbegin\n  return private.celular_asignar(", poner: "  v_actor uuid := private.llamadas_celular_actor(array['vendedor', 'supervisor', 'gerencia']);\nbegin\n  return private.celular_asignar(" },
    { aviso: 'Solo gerencia asigna celulares' }] },
  { nombre: 'supervisión ve celulares de otro equipo', buscar: '         and a.analista_id in (select private.vendedor_ids_visibles(p_actor)))', poner: '         and true)' },
  { nombre: 'rotar el celular de un analista de baja', aviso: 'El analista del celular ya no está activo' },
  { nombre: 'puerta abierta a anon', por: 'postflight', espera: 'EXECUTE inesperado',
    buscar: "    execute pg_catalog.format('grant execute on function %s to authenticated', v_f);", poner: "    execute pg_catalog.format('grant execute on function %s to authenticated, anon', v_f);" },
  { nombre: 'núcleo con EXECUTE para authenticated', por: 'postflight', espera: 'EXECUTE inesperado',
    buscar: "    'private.celulares_asignaciones_listar(uuid)'] loop\n    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);",
    poner: "    'private.celulares_asignaciones_listar(uuid)'] loop\n    execute pg_catalog.format('grant execute on function %s to authenticated', v_f);" },
  { nombre: 'puerta INVOKER', por: 'postflight', espera: 'debería ser SECURITY DEFINER',
    buscar: 'create function crm.asociar_llamada_celular(p_evento_id uuid, p_lead_id uuid)\nreturns jsonb\nlanguage plpgsql\nvolatile\nsecurity definer',
    poner: 'create function crm.asociar_llamada_celular(p_evento_id uuid, p_lead_id uuid)\nreturns jsonb\nlanguage plpgsql\nvolatile\nsecurity invoker' },
];

const CLAVE_VIGENTE_ACTIVA = "    and a.vigente_hasta is null\n    and coalesce(private.rol_crm(a.analista_id), '') in ('vendedor', 'supervisor')\n$function$;";
const MUTANTES_INGESTA = [
  { nombre: 'clave de un celular cerrado entra (el latido no re-chequea)', buscar: CLAVE_VIGENTE_ACTIVA,
    poner: "    and coalesce(private.rol_crm(a.analista_id), '') in ('vendedor', 'supervisor')\n$function$;" },
  { nombre: 'clave de un analista de baja entra (el latido no re-chequea)', buscar: CLAVE_VIGENTE_ACTIVA,
    poner: '    and a.vigente_hasta is null\n$function$;' },
  { nombre: 'clave desconocida sin frenar en la ingesta', aviso: 'No autorizado', ocurrencia: 1, total: 3 },
  { nombre: 'clave desconocida sin frenar en el latido', aviso: 'No autorizado', ocurrencia: 3, total: 3 },
  { nombre: 'sin chequeo propio de la clave ni respuesta uniforme: el núcleo da pistas', cambios: [
    { buscar: CLAVE_VIGENTE_ACTIVA, poner: "    and coalesce(private.rol_crm(a.analista_id), '') in ('vendedor', 'supervisor')\n$function$;" },
    { buscar: "  exception when insufficient_privilege then\n    -- Cerrada o dada de baja mientras esperaba el candado: la misma respuesta, sin pistas.\n    raise exception using errcode = '42501', message = 'No autorizado';\n  end;",
      poner: '  exception when division_by_zero then\n    raise;\n  end;' }] },
  { nombre: 'la ingesta no cuenta el envío', buscar: '  perform private.celular_consumir_envio(v_asig);\n  begin\n    v_r := private.llamada_celular_ingerir(v_asig, p_evento);',
    poner: '  begin\n    v_r := private.llamada_celular_ingerir(v_asig, p_evento);' },
  { nombre: 'el latido no cuenta el envío (límite no compartido)', buscar: '  perform private.celular_consumir_envio(v_asig);\n  return private.celular_registrar_salud(v_asig, p_latido);',
    poner: '  return private.celular_registrar_salud(v_asig, p_latido);' },
  { nombre: 'la respuesta al celular lleva el lead y su atención',
    buscar: "  return pg_catalog.jsonb_build_object('evento_id', v_r -> 'evento_id', 'repetido', v_r -> 'repetido',\n    'ignorado', v_r -> 'ignorado', 'motivo', v_r -> 'motivo');",
    poner: '  return v_r;' },
  { nombre: 'último envío sin sellar', buscar: '  update private.celulares_estado set ultimo_envio_en = pg_catalog.now() where asignacion_id = v_asig;\n', poner: '' },
  { nombre: 'límite por minuto apagado', buscar: 'if v_min >= v_pol.limite_envios_minuto then', poner: 'if false then' },
  { nombre: 'límite diario apagado', buscar: 'if v_dia_n >= v_pol.limite_envios_dia then', poner: 'if false then' },
  { nombre: 'el minuto no vuelve a cero', buscar: 'v_min := case when v_est.minuto_desde = v_minuto then v_est.envios_minuto else 0 end;', poner: 'v_min := v_est.envios_minuto;' },
  { nombre: 'el día no vuelve a cero', buscar: 'v_dia_n := case when v_est.dia = v_dia then v_est.envios_dia else 0 end;', poner: 'v_dia_n := v_est.envios_dia;' },
  { nombre: 'freno por minuto sin la espera', buscar: "      detail = pg_catalog.format('reintentar_en_seg=%s', greatest(1, pg_catalog.ceil(\n        extract(epoch from (v_minuto + interval '1 minute' - v_ahora)))::integer));",
    poner: "      detail = 'reintentar_en_seg=0';" },
  { nombre: 'freno diario sin la espera', buscar: "      detail = pg_catalog.format('reintentar_en_seg=%s', greatest(1, pg_catalog.ceil(\n        extract(epoch from (((v_dia + 1)::timestamp at time zone 'America/Lima') - v_ahora)))::integer));",
    poner: "      detail = 'reintentar_en_seg=0';" },
  { nombre: 'latido con claves no previstas', aviso: 'El latido trae claves no previstas' },
  { nombre: 'latido de otra versión', aviso: 'Versión de latido no soportada' },
  { nombre: 'latido sin versión de la macro', aviso: 'version_macro inválida' },
  { nombre: 'latido sin cola', aviso: 'en_cola es obligatorio' },
  { nombre: 'latido con hora ilegible', aviso: 'en_cola u ocurrio_en con formato inválido' },
  { nombre: 'latido sin estado dado por bueno', aviso: 'El celular no tiene estado' },
  { nombre: 'bandeja sin ámbito', buscar: '\n      and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)\n    order by e.recibido_en desc, e.id desc',
    poner: '\n    order by e.recibido_en desc, e.id desc' },
  { nombre: 'bandeja que ignora el cursor', buscar: '      and (p_antes_recibido_en is null or (e.recibido_en, e.id) < (p_antes_recibido_en, p_antes_id))\n', poner: '' },
  { nombre: 'cursor a medias aceptado', aviso: 'El cursor lleva recibido_en y evento_id juntos' },
  { nombre: 'supervisión ve la salud de otro equipo', buscar: '             and a.analista_id in (select private.vendedor_ids_visibles(p_actor))))\n$function$;',
    poner: '             and true))\n$function$;' },
  { nombre: 'salud con celulares cerrados', buscar: "  where a.vigente_hasta is null\n    and (private.rol_crm(p_actor) = 'gerencia'",
    poner: "  where (private.rol_crm(p_actor) = 'gerencia'" },
  { nombre: 'estado del celular borrable (reinicia el límite)', aviso: 'El estado de un celular no se borra' },
  { nombre: 'estado del celular que cambia de asignación', aviso: 'El estado de un celular no cambia de asignación' },
  { nombre: 'límite por minuto mayor que el diario', buscar: ',\n  add constraint llamadas_celular_politica_limites_coherentes check (limite_envios_minuto <= limite_envios_dia);', poner: ';' },
  { nombre: 'límite de cero envíos', buscar: 'check (limite_envios_minuto between 1 and 600)', poner: 'check (limite_envios_minuto between 0 and 600)' },
  { nombre: 'puerta de servicio abierta a authenticated', por: 'postflight', espera: 'EXECUTE inesperado',
    buscar: "    execute pg_catalog.format('grant execute on function %s to service_role', v_f);",
    poner: "    execute pg_catalog.format('grant execute on function %s to service_role, authenticated', v_f);" },
  { nombre: 'tabla técnica sin RLS', por: 'postflight', espera: 'quedó sin RLS',
    buscar: 'alter table private.celulares_estado enable row level security;\n', poner: '' },
  { nombre: 'tabla técnica abierta a la API', por: 'postflight', espera: 'accesible desde la API',
    buscar: 'revoke all on private.celulares_estado from public, anon, authenticated, service_role;', poner: 'grant select on private.celulares_estado to authenticated;' },
  { nombre: 'tabla técnica sin candado', por: 'postflight', espera: 'quedó sin su candado',
    buscar: 'create trigger trg_celulares_estado_00_candado\n  before update or delete on private.celulares_estado\n  for each row execute function private.trg_celulares_estado_candado();\n', poner: '' },
  { nombre: 'puerta de servicio INVOKER', por: 'postflight', espera: 'debería ser SECURITY DEFINER',
    buscar: 'create function crm.ingerir_llamada_celular_servicio(p_credencial text, p_evento jsonb)\nreturns jsonb\nlanguage plpgsql\nvolatile\nsecurity definer',
    poner: 'create function crm.ingerir_llamada_celular_servicio(p_credencial text, p_evento jsonb)\nreturns jsonb\nlanguage plpgsql\nvolatile\nsecurity invoker' },
  { nombre: 'límites que no son los decididos', por: 'postflight', espera: 'no quedaron en 30 por minuto y 600 al día',
    buscar: 'add column limite_envios_dia integer not null default 600', poner: 'add column limite_envios_dia integer not null default 601' },
];

const MUTANTES_ELEGIBILIDAD = [
  { nombre: 'el ayudante no asume la identidad del dueño', buscar: "  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_dueno::text, ''), true);\n", poner: '' },
  { nombre: 'la identidad del dueño no se devuelve', buscar: "  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_previo, ''), true);\n", poner: '' },
  { nombre: 'la identidad anterior se pierde (se devuelve vacía)', buscar: "coalesce(v_previo, '')", poner: "''" },
  { nombre: 'elegible sin mirar el ámbito', buscar: 'v_elegible := coalesce(private.llamada_celular_elegible(p_dueno, p_lead), false);', poner: 'v_elegible := true;' },
  { nombre: 'la ingesta llama a la regla sin el dueño', por: 'postflight', espera: 'no evalúa la elegibilidad como el dueño',
    buscar: '    v_aten := case when private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)',
    poner: '    v_aten := case when private.llamada_celular_elegible(v_asig.analista_id, v_lead)' },
  { nombre: 'ayudante con EXECUTE para authenticated', por: 'postflight', espera: 'EXECUTE inesperado',
    buscar: 'revoke all on function private.llamada_celular_elegible_dueno(uuid,uuid) from public, anon, authenticated, service_role;',
    poner: 'grant execute on function private.llamada_celular_elegible_dueno(uuid,uuid) to authenticated;' },
  { nombre: 'ayudante DEFINER', por: 'postflight', espera: 'debería ser SECURITY INVOKER',
    buscar: "returns boolean\nlanguage plpgsql\nvolatile\nset search_path = ''",
    poner: "returns boolean\nlanguage plpgsql\nvolatile\nsecurity definer\nset search_path = ''" },
];

// Mutantes de la quinta (20261005143843). Los candados no se ven en un solo hilo: van en MUTANTES_CANDADOS.
const VALIDACION_INGESTA = "  exception when sqlstate '22023' then\n    return pg_catalog.jsonb_build_object('resultado', 'invalido', 'mensaje', sqlerrm);\n  end;\n\n  -- Recepción";
const VALIDACION_LATIDO = "  exception when sqlstate '22023' then\n    return pg_catalog.jsonb_build_object('resultado', 'invalido', 'mensaje', sqlerrm);\n  end;\n  update private.celulares_estado";
const SIN_RESOLVER = "     and e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')\n     and not exists (select 1 from crm.llamadas_celular_enlaces l where l.evento_id = e.id)\n     and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_resolver);";
const MUTANTES_CORRECCION = [
  { nombre: 'un reenvío vuelve a buscar el lead (la recepción no corta)', buscar: '  if v_recepcion is null then\n    return v_aceptado;\n  end if;\n', poner: '' },
  { nombre: 'id sin forma fija', aviso: 'evento_origen_id inválido: se espera' },
  { nombre: 'id con la etiqueta de otro celular', aviso: 'evento_origen_id con la etiqueta de otro celular' },
  { nombre: 'id fuera de la ventana', aviso: 'evento_origen_id fuera de la ventana' },
  { nombre: 'un inválido revierte el cupo (sin respuesta normal)', buscar: VALIDACION_INGESTA, poner: VALIDACION_INGESTA.replace("    return pg_catalog.jsonb_build_object('resultado', 'invalido', 'mensaje', sqlerrm);", '    raise;') },
  { nombre: 'la dirección desconocida se guarda', buscar: "  if v_dir <> 'saliente' then\n    return v_aceptado;", poner: "  if v_dir = 'entrante' then\n    return v_aceptado;" },
  { nombre: 'un lead ajeno con dueño es candidato', buscar: '    and (coalesce(private.sla_gestion_permitida(p_dueno, l.id), false)\n', poner: '    and (true\n' },
  { nombre: 'los candidatos no se evalúan como el dueño', buscar: "  perform pg_catalog.set_config('request.jwt.claim.sub', p_dueno::text, true);\n", poner: '' },
  { nombre: 'la identidad no vuelve tras los candidatos', buscar: "  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_previo, ''), true);\n  return v_cand;", poner: '  return v_cand;' },
  { nombre: 'la bolsa no es candidata', buscar: "         or (l.vendedor_id is null and l.asignado_supervisor_id is null\n             and l.etapa not in ('convertido', 'descartado'))\n", poner: '' },
  { nombre: 'un descartado es reutilizable sin esperar su enfriamiento', buscar: "else interval '24 hours' end <= p_ahora));", poner: "else interval '24 hours' end <= p_ahora + interval '365 days'));" },
  { nombre: 'sin la carencia de 24 h', buscar: "else interval '24 hours' end <= p_ahora));", poner: "else interval '0 hours' end <= p_ahora));" },
  { nombre: 'la ambigua guarda cuántos candidatos', buscar: "    v_ident := 'ambiguo';\n    v_aten := 'por_revisar';\n  elsif",
    poner: "    v_ident := 'ambiguo';\n    v_aten := 'por_revisar';\n    v_calidad := v_calidad || pg_catalog.jsonb_build_object('candidatos', pg_catalog.cardinality(v_cand));\n  elsif" },
  { nombre: 'gerencia ve llamadas de leads dados de baja', buscar: '      exists (select 1 from crm.leads l where l.id = p_lead and l.activo)\n      and (coalesce', poner: '      (coalesce' },
  { nombre: 'enlazar acepta un resultado deshecho', aviso: 'Ese resultado se deshizo' },
  { nombre: 'enlace manual sin la regla de los 10 minutos', aviso: 'El resultado se registró antes de la llamada' },
  { nombre: 'la purga borra registradas', buscar: SIN_RESOLVER, poner: '     and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_resolver);' },
  { nombre: 'las identificadas sin enlace no caducan', buscar: "   where e.identificacion in ('identificado', 'ambiguo')", poner: "   where e.identificacion in ('ambiguo')" },
  { nombre: 'las recepciones no caducan', buscar: "  delete from private.llamadas_celular_recepciones r\n   where r.recibido_en < pg_catalog.now() - interval '32 days';",
    poner: '  delete from private.llamadas_celular_recepciones r\n   where false;' },
  { nombre: 'las recepciones caducan dentro de la ventana (liberan ids)', buscar: "interval '32 days';", poner: "interval '30 days';" },
  { nombre: 'la ventana del minuto retrocede', buscar: 'v_est.minuto_desde >= v_minuto', poner: 'v_est.minuto_desde = v_minuto' },
  { nombre: 'la ventana del día retrocede', buscar: 'v_est.dia >= v_dia', poner: 'v_est.dia = v_dia' },
  { nombre: 'sin política, sin error', aviso: 'Falta la política de llamadas del celular' },
  { nombre: 'las entrantes se encienden por la puerta', aviso: 'Las llamadas entrantes siguen bloqueadas' },
  { nombre: 'entrantes sin CHECK en la tabla', buscar: 'check (not entrantes_activas);', poner: 'check (true);' },
  { nombre: 'un latido inválido revierte el cupo', buscar: VALIDACION_LATIDO, poner: VALIDACION_LATIDO.replace("    return pg_catalog.jsonb_build_object('resultado', 'invalido', 'mensaje', sqlerrm);", '    raise;') },
  { nombre: 'el latido usa now() y no la hora de la puerta', buscar: '     set ultimo_latido_en = p_ahora,', poner: '     set ultimo_latido_en = pg_catalog.now(),' },
  // (Sin «$'» en `poner`: String.replace lo leería como «lo que sigue a la coincidencia».)
  { nombre: 'una fecha sin zona se acepta', buscar: '(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})', poner: '(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})?' },
  { nombre: 'la puerta devuelve más que el resultado',
    buscar: "  return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(\n    'resultado', v_r ->> 'resultado', 'mensaje', v_r ->> 'mensaje'));\nend;\n$function$;\n\ncreate or replace function crm.registrar_salud_celular_servicio",
    poner: "  return v_r || pg_catalog.jsonb_build_object('asignacion_id', v_asig);\nend;\n$function$;\n\ncreate or replace function crm.registrar_salud_celular_servicio" },
  { nombre: 'la salud muestra los envíos', buscar: "'eventos_en_cola', s.eventos_en_cola)", poner: "'eventos_en_cola', s.eventos_en_cola, 'envios_hoy', s.envios_dia)" },
  { nombre: 'una recepción se borra a mano', aviso: 'Una recepción de llamada no se borra a mano' },
  { nombre: 'una recepción se edita', aviso: 'Una recepción de llamada es inmutable' },
  { nombre: 'recepción sin RLS', por: 'postflight', espera: 'quedó sin RLS',
    buscar: 'alter table private.llamadas_celular_recepciones enable row level security;\n', poner: '' },
  { nombre: 'recepción abierta a la API', por: 'postflight', espera: 'accesible desde la API',
    buscar: 'revoke all on private.llamadas_celular_recepciones from public, anon, authenticated, service_role;', poner: 'grant select on private.llamadas_celular_recepciones to authenticated;' },
  { nombre: 'recepción sin candado', por: 'postflight', espera: 'quedó sin sus candados',
    buscar: 'create trigger trg_llamadas_celular_recepciones_00_candado\n  before update or delete on private.llamadas_celular_recepciones\n  for each row execute function private.trg_llamadas_celular_recepciones_candado();\n', poner: '' },
  { nombre: 'la llamada sigue única por asignación + id (rotar duplicaría)', por: 'postflight', espera: 'no quedó única por id',
    buscar: '  add constraint llamadas_celular_eventos_origen_uq unique (evento_origen_id);', poner: '  add constraint llamadas_celular_eventos_origen_uq unique (asignacion_id, evento_origen_id);' },
  { nombre: 'la bitácora muestra el número', por: 'postflight', espera: 'número enmascarado',
    buscar: "for each row execute function private.log_audit_sin_secretos('numero_canonico');", poner: 'for each row execute function private.log_audit_crm();' },
  { nombre: 'núcleo nuevo con EXECUTE para authenticated', por: 'postflight', espera: 'EXECUTE inesperado',
    buscar: "    'private.llamada_celular_ingerir(uuid,jsonb,timestamptz)'] loop\n    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);",
    poner: "    'private.llamada_celular_ingerir(uuid,jsonb,timestamptz)'] loop\n    execute pg_catalog.format('grant execute on function %s to authenticated', v_f);" },
  { nombre: 'el 409 sigue en la ingesta', por: 'postflight', espera: 'todavía lanza P0409',
    buscar: '  if v_recepcion is null then\n    return v_aceptado;\n  end if;\n', poner: "  if v_recepcion is null then\n    raise exception using errcode = 'P0409', message = 'conflicto';\n  end if;\n" },
  { nombre: 'la validación atrapa cualquier error', por: 'postflight', espera: 'atrapa cualquier error',
    buscar: VALIDACION_INGESTA, poner: VALIDACION_INGESTA.replace("exception when sqlstate '22023' then", 'exception when others then') },
  { nombre: 'puerta de servicio INVOKER', por: 'postflight', espera: 'debería ser SECURITY DEFINER',
    buscar: 'create or replace function crm.ingerir_llamada_celular_servicio(p_credencial text, p_evento jsonb)\nreturns jsonb\nlanguage plpgsql\nvolatile\nsecurity definer',
    poner: 'create or replace function crm.ingerir_llamada_celular_servicio(p_credencial text, p_evento jsonb)\nreturns jsonb\nlanguage plpgsql\nvolatile\nsecurity invoker' },
];

// Mutantes de candados: cada uno quita una defensa de concurrencia y su carrera (pasada 9) tiene que fallar.
const MUTANTES_CANDADOS = [
  { nombre: 'descartar no bloquea el lead', escenario: 'reasignarDuranteDescartar',
    buscar: "    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';\n  end if;\n  perform 1 from crm.leads l where l.id = v_ev.lead_id for share;\n",
    poner: "    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';\n  end if;\n" },
  { nombre: 'enlazar no bloquea el resultado', escenario: 'deshacerDuranteEnlazar',
    buscar: '  select * into v_act from crm.actividades a where a.id = p_actividad_id for share;', poner: '  select * into v_act from crm.actividades a where a.id = p_actividad_id;' },
  { nombre: 'la clave no bloquea la asignación', escenario: 'cierreDuranteLatido',
    buscar: '    and a.vigente_hasta is null\n  for share;', poner: '    and a.vigente_hasta is null;' },
  { nombre: 'asociar no revisa si la llamada cambió', escenario: 'llamadaCambiaAlAsociar',
    buscar: "  if not found or v_ev.lead_id is distinct from v_lead_leido then\n    raise exception using errcode = '40001', message = 'La llamada cambió mientras la asociabas",
    poner: "  if not found then\n    raise exception using errcode = '40001', message = 'La llamada cambió mientras la asociabas" },
];

// Mutantes de F4-a (20261005155914). El candado explícito del lead en la ingesta no tiene mutante: coincide con el
// que ya toma la llave foránea al guardar la llamada (FOR KEY SHARE choca con el FOR UPDATE de la v4), así que
// ninguna carrera puede distinguirlo; está por claridad del orden.
const NO_ENLAZADO = (motivo) => `      return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', '${motivo}');`;
const MUTANTES_ENLACE = [
  { nombre: 'la ingesta no cumple la intención', por: 'postflight', espera: 'no cumple las intenciones',
    buscar: '  perform private.llamada_celular_cumplir_intencion(v_evento);\n', poner: '' },
  { nombre: 'con el aviso ya llegado no se une', buscar: '  select * into v_ev from crm.llamadas_celular_eventos e where e.evento_origen_id = p_origen for update;\n  if found then',
    poner: '  select * into v_ev from crm.llamadas_celular_eventos e where e.evento_origen_id = p_origen for update;\n  if false then' },
  { nombre: 'el id de un celular ajeno se acepta',
    buscar: "  if not exists (select 1 from crm.celulares_asignaciones a\n                 where a.etiqueta = pg_catalog.split_part(p_origen, '-', 1) and a.analista_id = p_actor\n                   and (a.vigente_hasta is null or a.vigente_hasta >= v_hora)) then",
    poner: '  if false then' },
  { nombre: 'la v5 sin ventana del id', buscar: "  if v_hora < p_ahora - interval '30 days' or v_hora > p_ahora + interval '1 day' then", poner: '  if false then' },
  { nombre: 'se une la llamada de otro lead', buscar: "    if v_ev.identificacion <> 'identificado' or v_ev.lead_id is distinct from p_lead_id then",
    poner: "    if v_ev.identificacion <> 'identificado' then" },
  { nombre: 'se une una llamada descartada', buscar: `    if v_ev.atencion = 'descartado_con_motivo' then\n${NO_ENLAZADO('descartada')}\n    end if;\n`, poner: '' },
  { nombre: 'un resultado vigente se reemplaza en el enlace',
    buscar: "      if v_enl.actividad_id is not null and not coalesce(v_deshecha, false) then", poner: '      if false then' },
  { nombre: 'una intención vigente se reemplaza', buscar: `    if not coalesce(v_deshecha, false) then\n${NO_ENLAZADO('ya_tiene_resultado')}`,
    poner: `    if false then\n${NO_ENLAZADO('ya_tiene_resultado')}` },
  { nombre: 'con el aviso ignorado se guarda intención',
    buscar: '  if exists (select 1 from private.llamadas_celular_recepciones r where r.evento_origen_id = p_origen) then', poner: '  if false then' },
  { nombre: 'un resultado ya unido se guarda como intención',
    buscar: '  if exists (select 1 from crm.llamadas_celular_enlaces l where l.actividad_id = p_actividad_id) then', poner: '  if false then' },
  { nombre: 'el reintento de un resultado deshecho se une', buscar: "  if v_act.metadata ? 'deshecho_en' then\n    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_deshecho');",
    poner: "  if false then\n    return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_deshecho');" },
  { nombre: 'la intención de otro lead se cumple', buscar: '     or v_ev.lead_id is distinct from v_int.lead_id then', poner: ' then' },
  { nombre: 'la intención con el resultado deshecho se cumple', buscar: "  if not found or v_act.metadata ? 'deshecho_en' then\n    return;", poner: '  if not found then\n    return;' },
  { nombre: 'la intención no se retira al cumplirse', buscar: '  delete from private.llamadas_celular_intenciones where id = v_int.id;\n', poner: '' },
  { nombre: 'la vía de un enlace se cambia', aviso: 'El enlace de una llamada no cambia de evento, de lead ni de vía' },
  { nombre: 'una intención se borra a mano', aviso: 'Una intención de enlace no se borra a mano' },
  { nombre: 'una intención cambia de lead', aviso: 'De una intención de enlace solo cambia el resultado' },
  { nombre: 'una intención pasa a otro resultado sin deshacer', aviso: 'La intención solo pasa a otro resultado si el anterior se deshizo' },
  { nombre: 'las intenciones no caducan', buscar: "   where i.creado_en < pg_catalog.now() - interval '32 days';", poner: '   where false;' },
  { nombre: 'la v5 acepta la vía «manual»', buscar: "(p_via is null or p_via not in ('al_colgar', 'pestana'))", poner: "(p_via is null or p_via not in ('al_colgar', 'pestana', 'manual'))" },
  { nombre: 'intenciones sin RLS', por: 'postflight', espera: 'quedó sin RLS',
    buscar: 'alter table private.llamadas_celular_intenciones enable row level security;\n', poner: '' },
  { nombre: 'intenciones abiertas a la API', por: 'postflight', espera: 'accesible desde la API',
    buscar: 'revoke all on private.llamadas_celular_intenciones from public, anon, authenticated, service_role;', poner: 'grant select on private.llamadas_celular_intenciones to authenticated;' },
  { nombre: 'intenciones sin candado', por: 'postflight', espera: 'quedó sin sus candados',
    buscar: 'create trigger trg_llamadas_celular_intenciones_00_candado\n  before update or delete on private.llamadas_celular_intenciones\n  for each row execute function private.trg_llamadas_celular_intenciones_candado();\n', poner: '' },
  { nombre: 'la v5 abierta a anon', por: 'postflight', espera: 'EXECUTE inesperado',
    buscar: '  grant execute on function crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)\n    to authenticated;',
    poner: '  grant execute on function crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)\n    to authenticated, anon;' },
  { nombre: 'la v5 INVOKER', por: 'postflight', espera: 'debería ser SECURITY DEFINER',
    buscar: '  p_no_insista boolean default false, p_evento_origen_id text default null, p_via text default null)\nreturns jsonb\nlanguage plpgsql\nvolatile\nsecurity definer',
    poner: '  p_no_insista boolean default false, p_evento_origen_id text default null, p_via text default null)\nreturns jsonb\nlanguage plpgsql\nvolatile\nsecurity invoker' },
  { nombre: 'cumplir la intención atrapa cualquier error', por: 'postflight', espera: 'atrapa cualquier error',
    buscar: '  exception when unique_violation then\n    return;  -- ese resultado', poner: '  exception when others then\n    return;  -- ese resultado' },
];

// Mutantes de la séptima (20261005182227). Los caza la carrera con Deshacer pausado entre sus dos candados (pasada 14):
// sin el NOWAIT, la ingesta o la v5 esperan el resultado con el lead ya tomado y vuelve el interbloqueo del #190.
const MUTANTES_SIN_CICLO = [
  { nombre: 'la ingesta lee el resultado sin candado (el cuerpo de F4-a)', escenario: 'deshacerEntreCandados',
    buscar: 'where a.id = v_int.actividad_id for key share nowait;', poner: 'where a.id = v_int.actividad_id;' },
  { nombre: 'la ingesta espera el resultado (sin NOWAIT)', escenario: 'deshacerEntreCandados',
    buscar: 'where a.id = v_int.actividad_id for key share nowait;', poner: 'where a.id = v_int.actividad_id for key share;' },
  { nombre: 'la v5 lee el resultado sin candado (el cuerpo de F4-a)', escenario: 'reintentoV5DuranteDeshacer',
    buscar: 'where a.id = p_actividad_id for key share nowait;', poner: 'where a.id = p_actividad_id;' },
  { nombre: 'la v5 espera el resultado (sin NOWAIT)', escenario: 'reintentoV5DuranteDeshacer',
    buscar: 'where a.id = p_actividad_id for key share nowait;', poner: 'where a.id = p_actividad_id for key share;' },
  { nombre: 'cumplir sin NOWAIT atrapa cualquier error', por: 'postflight', espera: 'atrapa cualquier error',
    buscar: '  exception when lock_not_available then\n    return;\n  end;', poner: '  exception when others then\n    return;\n  end;' },
];

// Mutantes de la octava (20261005201010, lecturas de F4-b): los caza su oráculo o el postflight.
const MUTANTES_LECTURAS = [
  { nombre: '«Qué pasó hoy» sin el filtro del día', buscar: "      and e.recibido_en >= dia.desde and e.recibido_en < dia.desde + interval '1 day'\n", poner: '' },
  { nombre: '«Qué pasó hoy» con las pendientes', buscar: "    where e.atencion in ('registrado', 'descartado_con_motivo')",
    poner: "    where e.atencion in ('registrado', 'descartado_con_motivo', 'requiere_resultado')" },
  { nombre: '«Qué pasó hoy» sin ámbito', buscar: "      and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)\n    order by", poner: '    order by' },
  { nombre: 'la marca sin ámbito', buscar: "    and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)\n$function$;", poner: '$function$;' },
  { nombre: 'la marca sin tope de 500', buscar: 'pg_catalog.cardinality(p_actividad_ids) > 500', poner: 'pg_catalog.cardinality(p_actividad_ids) > 100000' },
  { nombre: 'el límite sin validar', buscar: '  if p_limite is null or p_limite not between 1 and 200 then', poner: '  if false then' },
  { nombre: 'el deshecho no se marca', buscar: "'deshecho', coalesce(r.deshecho, false)", poner: "'deshecho', false" },
  { nombre: '«Qué pasó hoy» abierta a anon', por: 'postflight', espera: 'EXECUTE inesperado',
    buscar: "    'crm.llamadas_celular_resueltas_hoy_fn(integer)',\n    'crm.actividades_con_llamada_celular_fn(uuid[])'] loop\n    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);\n    execute pg_catalog.format('grant execute on function %s to authenticated', v_f);",
    poner: "    'crm.llamadas_celular_resueltas_hoy_fn(integer)',\n    'crm.actividades_con_llamada_celular_fn(uuid[])'] loop\n    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);\n    execute pg_catalog.format('grant execute on function %s to authenticated, anon', v_f);" },
  { nombre: 'el núcleo con EXECUTE para authenticated', por: 'postflight', espera: 'EXECUTE inesperado',
    buscar: "    'private.actividades_con_llamada_celular(uuid,uuid[])'] loop\n    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);\n  end loop;",
    poner: "    'private.actividades_con_llamada_celular(uuid,uuid[])'] loop\n    execute pg_catalog.format('grant execute on function %s to authenticated', v_f);\n  end loop;" },
  { nombre: 'la puerta INVOKER', por: 'postflight', espera: 'debería ser SECURITY DEFINER',
    buscar: "create function crm.actividades_con_llamada_celular_fn(p_actividad_ids uuid[])\nreturns jsonb\nlanguage plpgsql\nstable\nsecurity definer",
    poner: "create function crm.actividades_con_llamada_celular_fn(p_actividad_ids uuid[])\nreturns jsonb\nlanguage plpgsql\nstable\nsecurity invoker" },
];

// Mutantes de la novena (20261005224330, «Qué pasó hoy» paginada y por la hora de resolución): los caza su oráculo o
// el postflight.
const MUTANTES_PAGINADAS = [
  { nombre: 'sin cursor en la rama de registradas',
    buscar: '      and (p_antes_resuelto_en is null or (en.actualizado_en, en.evento_id) < (p_antes_resuelto_en, p_antes_id))\n', poner: '' },
  { nombre: 'sin cursor en la rama de descartadas',
    buscar: '      and (p_antes_resuelto_en is null or (e.descartado_en, e.id) < (p_antes_resuelto_en, p_antes_id))\n', poner: '' },
  { nombre: 'sin la rama de descartadas', buscar: "    where e.atencion = 'descartado_con_motivo'\n",
    poner: "    where false and e.atencion = 'descartado_con_motivo'\n" },
  { nombre: 'la registrada cuenta cuando nació el enlace (creado_en), no cuando pasó al corregido',
    buscar: "      and en.actualizado_en >= dia.desde and en.actualizado_en < dia.desde + interval '1 day'\n",
    poner: "      and en.creado_en >= dia.desde and en.creado_en < dia.desde + interval '1 day'\n" },
  { nombre: 'la descartada cuenta el día en que se recibió, no el del descarte',
    buscar: "      and e.descartado_en >= dia.desde and e.descartado_en < dia.desde + interval '1 day'\n",
    poner: "      and e.recibido_en >= dia.desde and e.recibido_en < dia.desde + interval '1 day'\n" },
  { nombre: 'el día en UTC, no en Lima', buscar: "'America/Lima') at time zone 'America/Lima') as desde",
    poner: "'UTC') at time zone 'UTC') as desde" },
  { nombre: 'sin la fila de más (limit sin +1)', buscar: '    limit p_limite + 1\n', poner: '    limit p_limite\n' },
  { nombre: 'la página se corta por la hora de recepción', buscar: '    order by r.resuelto_en desc, e.id desc\n',
    poner: '    order by e.recibido_en desc, e.id desc\n' },
  { nombre: '«Qué pasó hoy» sin ámbito',
    buscar: '    where private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)\n    order by', poner: '    order by' },
  { nombre: 'el cursor a medias se acepta', buscar: '  if (p_antes_resuelto_en is null) <> (p_antes_id is null) then', poner: '  if false then' },
  { nombre: 'el límite sin validar', buscar: '  if p_limite is null or p_limite not between 1 and 200 then', poner: '  if false then' },
  { nombre: 'el deshecho no se marca', buscar: "'deshecho', coalesce(p.deshecho, false)", poner: "'deshecho', false" },
  { nombre: 'la lectura de la octava sigue (dos firmas)', por: 'postflight', espera: 'sigue la lectura de la octava',
    buscar: 'drop function crm.llamadas_celular_resueltas_hoy_fn(integer);\n', poner: '' },
  { nombre: 'el índice de descartadas sin filtrar', por: 'postflight', espera: 'faltan los índices',
    buscar: "  on crm.llamadas_celular_eventos (descartado_en, id) where atencion = 'descartado_con_motivo';",
    poner: '  on crm.llamadas_celular_eventos (descartado_en, id);' },
  { nombre: '«Qué pasó hoy» abierta a anon', por: 'postflight', espera: 'EXECUTE inesperado',
    buscar: 'grant execute on function crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid) to authenticated;',
    poner: 'grant execute on function crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid) to authenticated, anon;' },
  { nombre: 'el núcleo con EXECUTE para authenticated', por: 'postflight', espera: 'EXECUTE inesperado',
    buscar: 'revoke all on function private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid)\n  from public, anon, authenticated, service_role;',
    poner: 'grant execute on function private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid)\n  to authenticated;' },
  { nombre: 'la puerta INVOKER', por: 'postflight', espera: 'debería ser SECURITY DEFINER',
    buscar: 'stable\nsecurity definer', poner: 'stable\nsecurity invoker' },
];

// Mutantes de la décima (20261006150154, id de origen en la bandeja y el detalle): los caza su oráculo o el postflight.
const MUTANTES_ORIGEN = [
  { nombre: 'la bandeja pone otro id en lugar del de origen', buscar: "'evento_origen_id', p.evento_origen_id,", poner: "'evento_origen_id', p.id::text," },
  { nombre: 'el detalle sin el id de origen', por: 'postflight', espera: 'siguen sin evento_origen_id',
    buscar: "'evento_origen_id', v_ev.evento_origen_id, ", poner: '' },
  { nombre: 'la bandeja sin ámbito', buscar: '      and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)\n', poner: '' },
  { nombre: 'el detalle sin ámbito',
    buscar: 'if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then', poner: 'if not found then' },
  { nombre: 'la bandeja DEFINER', por: 'postflight', espera: 'debería ser SECURITY INVOKER',
    buscar: "language sql\nstable\nset search_path = ''", poner: "language sql\nstable\nsecurity definer\nset search_path = ''" },
  { nombre: 'el detalle VOLATILE', por: 'postflight', espera: 'debería ser STABLE',
    buscar: 'language plpgsql\nstable', poner: 'language plpgsql\nvolatile' },
];

// Mutantes de la undécima (20261006150254, salud sin la hora exacta del latido): los caza su oráculo o el postflight.
const MUTANTES_SALUD = [
  { nombre: 'vuelve la hora exacta del latido', por: 'postflight', espera: 'sigue devolviendo la hora exacta',
    buscar: "           'version_macro', s.version_macro,", poner: "           'ultimo_latido_en', s.ultimo_latido_en, 'version_macro', s.version_macro," },
  { nombre: 'el umbral de «sin latido» en 9 h', buscar: "interval '7 hours'", poner: "interval '9 hours'" },
  { nombre: 'las horas sin redondear', buscar: "pg_catalog.floor(extract(epoch from pg_catalog.now() - s.ultimo_latido_en) / 3600)::integer",
    poner: 'extract(epoch from pg_catalog.now() - s.ultimo_latido_en)' },
  { nombre: 'las horas sin piso de 0', buscar: 'greatest(0, pg_catalog.floor(extract(epoch from pg_catalog.now() - s.ultimo_latido_en) / 3600)::integer)',
    poner: 'pg_catalog.floor(extract(epoch from pg_catalog.now() - s.ultimo_latido_en) / 3600)::integer' },
  { nombre: '«nunca» da 0 horas en vez de nulo', buscar: "'horas_sin_latido', case when s.ultimo_latido_en is null then null\n", poner: "'horas_sin_latido', case when false then null\n" },
  { nombre: 'el reloj nunca se marca desfasado', buscar: '> 300, false)', poner: '> 300000, false)' },
  { nombre: '«nunca» se confunde con «sin latido»', buscar: "when s.ultimo_latido_en is null then 'nunca'", poner: "when s.ultimo_latido_en is null then 'sin_latido'" },
  { nombre: 'la supervisión ve celulares de otro equipo',
    buscar: 'and a.analista_id in (select private.vendedor_ids_visibles(p_actor))', poner: 'and true' },
  { nombre: 'la salud DEFINER', por: 'postflight', espera: 'debería ser SECURITY INVOKER',
    buscar: "language sql\nstable\nset search_path = ''", poner: "language sql\nstable\nsecurity definer\nset search_path = ''" },
];

function carpetaBinarios() {
  const candidatos = [
    process.env.LLAMADAS_PG_BIN,
    join(homedir(), '.local/pg/pgsql/bin'),
    '/opt/homebrew/opt/postgresql@17/bin',
    '/opt/homebrew/opt/postgresql@16/bin',
    '/usr/lib/postgresql/17/bin',
    '/usr/lib/postgresql/16/bin',
  ].filter(Boolean);
  for (const dir of candidatos) if (existsSync(join(dir, `initdb${EXE}`))) return dir;
  throw new Error('No encuentro PostgreSQL 16/17: define LLAMADAS_PG_BIN con la carpeta de initdb');
}

const PG = carpetaBinarios();
const temporal = mkdtempSync(join(tmpdir(), 'llamadas-celular-'));
const datos = join(temporal, 'data');
const bitacora = join(temporal, 'postgres.log');
const clave = randomBytes(18).toString('hex');
const archivoClave = join(temporal, 'clave');
writeFileSync(archivoClave, `${clave}\n`, { mode: 0o600 });

// Fuera toda variable PG* heredada: el destino lo fija este guion y nada más.
const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith('PG')));
Object.assign(env, {
  PGHOST: '127.0.0.1', PGPORT: PUERTO, PGUSER: USUARIO,
  PGPASSWORD: clave, PGCONNECT_TIMEOUT: '5', PGTZ: 'UTC',
});

// `sinTuberias`: el servidor que lanza pg_ctl heredaría las tuberías de salida y, en Windows,
// spawnSync esperaría hasta su timeout. Su salida ya va a la bitácora (-l).
function correr(binario, args, { sinTuberias = false } = {}) {
  const r = spawnSync(join(PG, binario + EXE), args, {
    env, encoding: 'utf8', timeout: 180_000, ...(sinTuberias ? { stdio: 'ignore' } : {}),
  });
  const salida = `${r.stdout ?? ''}${r.stderr ?? ''}`.split(clave).join('<clave>');
  return { ok: r.status === 0 && !r.error, salida: salida || (r.error ? String(r.error.message) : '') };
}
const psqlArchivo = (archivo, db) => correr('psql', ['-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', db, '-f', archivo]);
const psqlSql = (sql, db) => correr('psql', ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-d', db, '-c', sql]);
const cola = (texto, n = 700) => texto.trim().slice(-n);
const lineasOraculo = (texto) => (texto.match(/ORACULO[^\n]*/g) ?? [cola(texto)]).join('\n');
function lineaError(texto) {
  const linea = texto.split('\n').find((l) => /ERROR:/.test(l)) ?? cola(texto, 200);
  return linea.replace(/^.*ERROR:\s*/, '').slice(0, 170);
}

const pasos = [];
function paso(nombre, ok, detalle = '') {
  pasos.push({ nombre, ok: Boolean(ok) });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${nombre}${detalle ? `\n      ${detalle.replace(/\n/g, '\n      ')}` : ''}`);
  return Boolean(ok);
}

function escaparRegex(texto) {
  return texto.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
function aplicarCambio(texto, cambio) {
  if (cambio.aviso) {
    const patron = new RegExp(
      `raise exception using errcode = '[0-9A-Z]{5}',(\\s*message = (?:pg_catalog\\.format\\()?'${escaparRegex(cambio.aviso)})`, 'g');
    const total = (texto.match(patron) ?? []).length;
    const esperado = cambio.total ?? 1;
    if (total !== esperado) return { error: `el aviso «${cambio.aviso}» aparece ${total} veces (se esperaban ${esperado})` };
    const objetivo = cambio.ocurrencia ?? 1;
    let n = 0;
    return { texto: texto.replace(patron, (todo, resto) => (++n === objetivo ? `raise notice using${resto}` : todo)) };
  }
  const veces = texto.split(cambio.buscar).length - 1;
  if (veces !== 1) return { error: `el fragmento aparece ${veces} veces` };
  return { texto: texto.replace(cambio.buscar, cambio.poner) };
}
function aplicarMutante(original, mutante) {
  let texto = original;
  for (const cambio of mutante.cambios ?? [mutante]) {
    const r = aplicarCambio(texto, cambio);
    if (r.error) return r;
    texto = r.texto;
  }
  return { texto };
}

function pasadaMutantes(titulo, migracion, mutantes, plantilla, oraculo, marca) {
  console.log(`\n— ${titulo} —`);
  const original = readFileSync(migracion, 'utf8').replace(/\r\n/g, '\n');
  mutantes.forEach((mutante, i) => {
    const etiqueta = `${marca} ${String(i + 1).padStart(2, '0')}: ${mutante.nombre}`;
    const m = aplicarMutante(original, mutante);
    if (m.error) { paso(etiqueta, false, `mutante obsoleto: ${m.error}`); return; }
    const archivo = join(temporal, `${marca}-${i + 1}.sql`);
    writeFileSync(archivo, m.texto);
    const db = `${marca}_${i + 1}`;
    psqlSql(`create database ${db} template ${plantilla}`, 'postgres');
    const aplicado = psqlArchivo(archivo, db);
    if (mutante.por === 'postflight') {
      paso(etiqueta, !aplicado.ok && aplicado.salida.includes(mutante.espera),
        aplicado.ok ? 'SOBREVIVE: la migración mutada se aplicó' : `cazado por el postflight: ${lineaError(aplicado.salida)}`);
    } else if (!aplicado.ok) {
      paso(etiqueta, false, `la migración mutada no se aplica (mutante inválido): ${lineaError(aplicado.salida)}`);
    } else {
      const r = psqlArchivo(oraculo, db);
      paso(etiqueta, !r.ok, r.ok ? 'SOBREVIVE: el oráculo no lo nota' : `cazado por el oráculo: ${lineaError(r.salida)}`);
    }
    psqlSql(`drop database ${db}`, 'postgres');
  });
}

// Una sesión psql en paralelo (para la concurrencia): devuelve su salida y cuánto tardó.
function psqlParalelo(sql, db) {
  return new Promise((resolve) => {
    const archivo = join(temporal, `sesion-${randomBytes(4).toString('hex')}.sql`);
    writeFileSync(archivo, sql);
    const inicio = Date.now();
    const p = spawn(join(PG, `psql${EXE}`), ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-d', db, '-f', archivo], { env });
    let salida = '';
    p.stdout.on('data', (d) => { salida += d; });
    p.stderr.on('data', (d) => { salida += d; });
    p.on('close', (code) => resolve({ ok: code === 0, salida: salida.split(clave).join('<clave>'), ms: Date.now() - inicio }));
  });
}
const pausa = (ms) => new Promise((r) => { setTimeout(r, ms); });
const RETIENE_MS = 2000;

async function pasadaConcurrencia() {
  console.log('\n— Pasada 6: concurrencia con dos sesiones reales —');
  const db = 'concurrencia';
  psqlSql(`create database ${db} template plantilla_nucleo`, 'postgres');
  let r = psqlArchivo(MIG_INGESTA, db);
  if (!paso('banco de concurrencia listo (datos + núcleo + ingesta)', r.ok, r.ok ? '' : cola(r.salida))) return;
  const a1 = '00000000-0000-0000-0000-0000000000a1';
  const c1 = '00000000-0000-0000-0000-0000000000c1';
  r = psqlSql(`insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash) values ('C1', '${a1}', repeat('a', 64)) returning id`, db);
  const asig = r.salida.trim();
  const evento = (origen, extra = '') =>
    `'{"v": 1, "evento_origen_id": "${origen}", "numero": "900000001", "direccion": "saliente"${extra}}'::jsonb`;
  const ingerir = (origen, extra) => `select private.llamada_celular_ingerir('${asig}', ${evento(origen, extra)})::text;`;
  const retener = (sql) => `begin;\n${sql}\nselect pg_sleep(${RETIENE_MS / 1000});\ncommit;\n`;

  // Dos envíos del mismo origen con el MISMO contenido: la segunda espera y responde «repetido».
  let [s1, s2] = await Promise.all([
    psqlParalelo(retener(ingerir('conc-1')), db),
    pausa(400).then(() => psqlParalelo(ingerir('conc-1'), db)),
  ]);
  const id1 = /"evento_id": "([0-9a-f-]{36})"/.exec(s1.salida)?.[1];
  paso('mismo origen a la vez, mismo contenido → la segunda espera y devuelve el mismo evento',
    s1.ok && s2.ok && id1 && s2.salida.includes(`"evento_id": "${id1}"`) && s2.salida.includes('"repetido": true') && s2.ms >= RETIENE_MS - 600,
    `segunda sesión: ${s2.ms} ms · ${(s2.salida.trim().split('\n').pop() ?? '').slice(0, 140)}`);

  // Mismo origen con OTRO contenido a la vez: la segunda espera y recibe el conflicto.
  [s1, s2] = await Promise.all([
    psqlParalelo(retener(ingerir('conc-2', ', "duracion_seg": 10')), db),
    pausa(400).then(() => psqlParalelo(ingerir('conc-2', ', "duracion_seg": 20'), db)),
  ]);
  paso('mismo origen a la vez, otro contenido → la segunda espera y recibe el conflicto',
    s1.ok && !s2.ok && s2.salida.includes('llegó a la vez con otro contenido') && s2.ms >= RETIENE_MS - 600,
    `segunda sesión: ${s2.ms} ms · ${lineaError(s2.salida)}`);

  // Dos consumidores enlazan la MISMA llamada con dos resultados distintos: uno gana.
  r = psqlSql(`${ingerir('conc-3')}`, db);
  const ev = /"evento_id": "([0-9a-f-]{36})"/.exec(r.salida)?.[1];
  r = psqlSql(`select set_config('crm.op_resultado_llamada', 'on', false);
    insert into crm.actividades (lead_id, tipo, metadata, creado_por) values
      ('${c1}', 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', '${a1}'),
      ('${c1}', 'llamada_no_contestada', '{"evento": "resultado_llamada", "resultado": "no_contesto"}', '${a1}')
    returning id;`, db);
  // En Windows psql termina las líneas con \r\n.
  const [actX, actY] = r.salida.trim().split(/\r?\n/).filter((l) => /^[0-9a-f-]{36}$/.test(l));
  const como = `set local role authenticated;\nselect set_config('request.jwt.claim.sub', '${a1}', true);\n`;
  const enlazar = (act) => `select crm.enlazar_llamada_celular('${ev}', '${act}')::text;`;
  [s1, s2] = await Promise.all([
    psqlParalelo(retener(`${como}${enlazar(actX)}`), db),
    pausa(400).then(() => psqlParalelo(`begin;\n${como}${enlazar(actY)}\ncommit;\n`, db)),
  ]);
  paso('dos consumidores enlazan la misma llamada → el segundo espera y es rechazado',
    Boolean(ev && actX && actY) && s1.ok && !s2.ok && s2.salida.includes('ya tiene su resultado registrado') && s2.ms >= RETIENE_MS - 600,
    `segunda sesión: ${s2.ms} ms · ${lineaError(s2.salida)}`);
  r = psqlSql(`select count(*) from crm.llamadas_celular_enlaces where evento_id = '${ev}'`, db);
  paso('queda exactamente un enlace', r.ok && r.salida.trim() === '1', r.salida.trim());

  // F3-a: gerencia rota la clave de C7 mientras una ingesta con la clave vieja espera el candado
  // de la asignación. La ingesta vio la asignación vigente al empezar; tras esperar, el núcleo la
  // encuentra cerrada y la puerta responde el MISMO «No autorizado», sin el mensaje del núcleo.
  const g1 = '00000000-0000-0000-0000-0000000000f1';
  const claveC7 = randomBytes(32).toString('hex'); // sintética: no protege nada fuera de este banco
  r = psqlSql(`insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash)
    values ('C7', '${a1}', encode(sha256(convert_to('${claveC7}', 'utf8')), 'hex')) returning id`, db);
  const comoGerencia = `set local role authenticated;\nselect set_config('request.jwt.claim.sub', '${g1}', true);\n`;
  const comoServicio = `set local role service_role;\nselect set_config('request.jwt.claim.sub', '', true);\n`;
  [s1, s2] = await Promise.all([
    psqlParalelo(retener(`${comoGerencia}select crm.rotar_credencial_celular('C7') is not null;`), db),
    pausa(400).then(() => psqlParalelo(`begin;\n${comoServicio}select crm.ingerir_llamada_celular_servicio('${claveC7}', ${evento('conc-4')})::text;\ncommit;\n`, db)),
  ]);
  paso('rotación mientras una ingesta espera → la ingesta espera y recibe el mismo «No autorizado»',
    r.ok && s1.ok && !s2.ok && s2.salida.includes('No autorizado') && !s2.salida.includes('Celular sin asignación')
      && s2.ms >= RETIENE_MS - 600,
    `segunda sesión: ${s2.ms} ms · ${lineaError(s2.salida)}`);
  r = psqlSql(`select count(*) from crm.llamadas_celular_eventos where evento_origen_id = 'conc-4'`, db);
  paso('la ingesta rechazada no dejó la llamada guardada', r.ok && r.salida.trim() === '0', r.salida.trim());
}

// ── Quinta: siembra y carreras (pasada 9) ──────────────────────────────────────────────────────
const ACT = {
  a1: '00000000-0000-0000-0000-0000000000a1', a2: '00000000-0000-0000-0000-0000000000a2',
  a3: '00000000-0000-0000-0000-0000000000a3', b1: '00000000-0000-0000-0000-0000000000b1',
  g1: '00000000-0000-0000-0000-0000000000f1', c1: '00000000-0000-0000-0000-0000000000c1',
  c6: '00000000-0000-0000-0000-0000000000c6', c7: '00000000-0000-0000-0000-0000000000c7',
};
const SERVICIO = "set local role service_role;\nselect set_config('request.jwt.claim.sub', '', true);\n";
const comoSql = (u) => `set local role authenticated;\nselect set_config('request.jwt.claim.sub', '${u}', true);\n`;
const enTx = (sql) => `begin;\n${sql}\ncommit;\n`;
const retenerTx = (sql) => `begin;\n${sql}\nselect pg_sleep(${RETIENE_MS / 1000});\ncommit;\n`;
const esperoYo = (s) => s.ms >= RETIENE_MS - 600;
const ultima = (s) => (s.salida.trim().split('\n').pop() ?? '').slice(0, 140);

// Asignaciones con claves sintéticas (no protegen nada fuera del banco) y cupo alto para las carreras.
function sembrarCorreccion(db) {
  const k = { C1: randomBytes(32).toString('hex'), C2: randomBytes(32).toString('hex'),
              C4: randomBytes(32).toString('hex'), C5: randomBytes(32).toString('hex') };
  const hash = (x) => `encode(sha256(convert_to('${x}', 'utf8')), 'hex')`;
  const r = psqlSql(`update crm.llamadas_celular_politica set limite_envios_minuto = 600, limite_envios_dia = 20000;
    insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash) values
      ('C1', '${ACT.a1}', ${hash(k.C1)}), ('C2', '${ACT.a3}', ${hash(k.C2)}),
      ('C4', '${ACT.b1}', ${hash(k.C4)}), ('C5', '${ACT.a2}', ${hash(k.C5)})
    returning etiqueta || '=' || id;`, db);
  const asig = Object.fromEntries(r.salida.trim().split(/\r?\n/).filter((l) => l.includes('=')).map((l) => l.split('=')));
  let segundo = Math.floor(Date.now() / 1000) - 20000;
  return { db, k, asig, ok: r.ok, nuevoId: (et) => `${et}-${segundo++}` };
}
const ingerirSql = (clave, id, numero) => `select crm.ingerir_llamada_celular_servicio('${clave}', '{"v": 1, "evento_origen_id": "${id}", "numero": "${numero}", "direccion": "saliente"}'::jsonb)::text;`;
const latidoSql = (clave) => `select crm.registrar_salud_celular_servicio('${clave}', '{"v": 1, "version_macro": "banco", "en_cola": 0}'::jsonb)::text;`;
function llamada(ctx, et, numero) {
  const id = ctx.nuevoId(et);
  psqlSql(enTx(SERVICIO + ingerirSql(ctx.k[et], id, numero)), ctx.db);
  return psqlSql(`select id from crm.llamadas_celular_eventos where evento_origen_id = '${id}'`, ctx.db).salida.trim();
}
function resultado(ctx, lead, autor) {
  const r = psqlSql(`insert into crm.actividades (lead_id, tipo, metadata, creado_por)
    values ('${lead}', 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', '${autor}') returning id;`, ctx.db);
  return r.salida.trim().split(/\r?\n/).find((l) => /^[0-9a-f-]{36}$/.test(l));
}
// Deshacer real (crm.deshacer_resultado_llamada, 20260920005000:649 y 682): resultado FOR UPDATE → lead FOR UPDATE → sello.
const deshacerSql = (act, lead) => `select 1 from crm.actividades where id = '${act}' for update;
select 1 from crm.leads where id = '${lead}' for update;
update crm.actividades set metadata = metadata || jsonb_build_object('deshecho_en', now()) where id = '${act}';`;
const reasignarSql = (lead, a) => `update crm.leads set vendedor_id = '${a}' where id = '${lead}';`;

const CARRERAS = {
  async mismoIdALaVez(ctx) {
    const id = ctx.nuevoId('C1');
    const [s1, s2] = await Promise.all([
      psqlParalelo(retenerTx(SERVICIO + ingerirSql(ctx.k.C1, id, '900000001')), ctx.db),
      pausa(400).then(() => psqlParalelo(enTx(SERVICIO + ingerirSql(ctx.k.C1, id, '900000001')), ctx.db)),
    ]);
    const n = psqlSql(`select count(*) from crm.llamadas_celular_eventos where evento_origen_id = '${id}'`, ctx.db).salida.trim();
    return { ok: s1.ok && s2.ok && s2.salida.includes('"resultado": "aceptado"') && esperoYo(s2) && n === '1',
             detalle: `segunda: ${s2.ms} ms · ${ultima(s2)} · llamadas con ese id: ${n}` };
  },
  async cierreDuranteLatido(ctx) {
    const [s1, s2] = await Promise.all([
      psqlParalelo(retenerTx(`${comoSql(ACT.g1)}select crm.cerrar_asignacion_celular('${ctx.asig.C2}', 'extravio') is not null;`), ctx.db),
      pausa(400).then(() => psqlParalelo(enTx(SERVICIO + latidoSql(ctx.k.C2)), ctx.db)),
    ]);
    const n = psqlSql(`select count(*) from private.celulares_estado where asignacion_id = '${ctx.asig.C2}'`, ctx.db).salida.trim();
    return { ok: s1.ok && !s2.ok && s2.salida.includes('No autorizado') && esperoYo(s2) && n === '0',
             detalle: `latido: ${s2.ms} ms · ${lineaError(s2.salida)} · filas de estado: ${n}` };
  },
  async latidoDuranteCierre(ctx) {
    const [s1, s2] = await Promise.all([
      psqlParalelo(retenerTx(SERVICIO + latidoSql(ctx.k.C5)), ctx.db),
      pausa(400).then(() => psqlParalelo(enTx(`${comoSql(ACT.g1)}select crm.cerrar_asignacion_celular('${ctx.asig.C5}', 'extravio') is not null;`), ctx.db)),
    ]);
    return { ok: s1.ok && s2.ok && esperoYo(s2) && s1.salida.includes('"resultado": "aceptado"'),
             detalle: `cierre: ${s2.ms} ms · latido: ${ultima(s1)}` };
  },
  async reasignarDuranteDescartar(ctx) {
    const ev = llamada(ctx, 'C1', '900000001');
    const [s1, s2] = await Promise.all([
      psqlParalelo(retenerTx(reasignarSql(ACT.c1, ACT.a2)), ctx.db),
      pausa(400).then(() => psqlParalelo(enTx(`${comoSql(ACT.a1)}select crm.descartar_llamada_celular('${ev}', 'personal')::text;`), ctx.db)),
    ]);
    psqlSql(reasignarSql(ACT.c1, ACT.a1), ctx.db);
    return { ok: Boolean(ev) && s1.ok && !s2.ok && s2.salida.includes('fuera de tu ámbito') && esperoYo(s2),
             detalle: `descartar: ${s2.ms} ms · ${s2.ok ? ultima(s2) : lineaError(s2.salida)}` };
  },
  async reasignarDuranteAsociar(ctx) {
    const ev = llamada(ctx, 'C4', '900000006');
    const [s1, s2] = await Promise.all([
      psqlParalelo(retenerTx(reasignarSql(ACT.c7, ACT.a3)), ctx.db),
      pausa(400).then(() => psqlParalelo(enTx(`${comoSql(ACT.b1)}select crm.asociar_llamada_celular('${ev}', '${ACT.c7}')::text;`), ctx.db)),
    ]);
    psqlSql(reasignarSql(ACT.c7, ACT.a2), ctx.db);
    return { ok: Boolean(ev) && s1.ok && !s2.ok && s2.salida.includes('no es de tu ámbito') && esperoYo(s2),
             detalle: `asociar: ${s2.ms} ms · ${s2.ok ? ultima(s2) : lineaError(s2.salida)}` };
  },
  async llamadaCambiaAlAsociar(ctx) {
    const ev = llamada(ctx, 'C4', '900000006');
    const [s1, s2] = await Promise.all([
      psqlParalelo(retenerTx(`${comoSql(ACT.b1)}select crm.asociar_llamada_celular('${ev}', '${ACT.c6}')::text;`), ctx.db),
      pausa(400).then(() => psqlParalelo(enTx(`${comoSql(ACT.b1)}select crm.asociar_llamada_celular('${ev}', '${ACT.c7}')::text;`), ctx.db)),
    ]);
    return { ok: Boolean(ev) && s1.ok && !s2.ok && s2.salida.includes('cambió mientras la asociabas') && esperoYo(s2),
             detalle: `segunda: ${s2.ms} ms · ${s2.ok ? ultima(s2) : lineaError(s2.salida)}` };
  },
  async reasignarDuranteEnlazar(ctx) {
    const ev = llamada(ctx, 'C1', '900000001');
    const act = resultado(ctx, ACT.c1, ACT.a1);
    const [s1, s2] = await Promise.all([
      psqlParalelo(retenerTx(reasignarSql(ACT.c1, ACT.a2)), ctx.db),
      pausa(400).then(() => psqlParalelo(enTx(`${comoSql(ACT.a1)}select crm.enlazar_llamada_celular('${ev}', '${act}')::text;`), ctx.db)),
    ]);
    psqlSql(reasignarSql(ACT.c1, ACT.a1), ctx.db);
    return { ok: Boolean(ev && act) && s1.ok && !s2.ok && s2.salida.includes('fuera de tu ámbito') && esperoYo(s2),
             detalle: `enlazar: ${s2.ms} ms · ${s2.ok ? ultima(s2) : lineaError(s2.salida)}` };
  },
  async deshacerDuranteEnlazar(ctx) {
    const ev = llamada(ctx, 'C1', '900000001');
    const act = resultado(ctx, ACT.c1, ACT.a1);
    const [s1, s2] = await Promise.all([
      psqlParalelo(retenerTx(deshacerSql(act, ACT.c1)), ctx.db),
      pausa(400).then(() => psqlParalelo(enTx(`${comoSql(ACT.a1)}select crm.enlazar_llamada_celular('${ev}', '${act}')::text;`), ctx.db)),
    ]);
    return { ok: Boolean(ev && act) && s1.ok && !s2.ok && s2.salida.includes('se deshizo') && !s2.salida.includes('deadlock') && esperoYo(s2),
             detalle: `enlazar: ${s2.ms} ms · ${s2.ok ? ultima(s2) : lineaError(s2.salida)}` };
  },
  async enlazarDuranteDeshacer(ctx) {
    const ev = llamada(ctx, 'C1', '900000001');
    const act = resultado(ctx, ACT.c1, ACT.a1);
    const [s1, s2] = await Promise.all([
      psqlParalelo(retenerTx(`${comoSql(ACT.a1)}select crm.enlazar_llamada_celular('${ev}', '${act}')::text;`), ctx.db),
      pausa(400).then(() => psqlParalelo(enTx(deshacerSql(act, ACT.c1)), ctx.db)),
    ]);
    return { ok: Boolean(ev && act) && s1.ok && s2.ok && esperoYo(s2) && !`${s1.salida}${s2.salida}`.includes('deadlock'),
             detalle: `deshacer: ${s2.ms} ms · enlazar: ${s1.ok ? 'ok' : lineaError(s1.salida)}` };
  },
};
const CARRERAS_TITULOS = [
  ['mismoIdALaVez', 'mismo id a la vez → la segunda espera, responde «aceptado» y queda una llamada'],
  ['cierreDuranteLatido', 'cierre durante un latido → el latido espera y recibe «No autorizado», sin gastar cupo'],
  ['latidoDuranteCierre', 'latido durante un cierre → el cierre espera al latido'],
  ['reasignarDuranteDescartar', 'reasignación durante descartar → descartar espera y revalida el ámbito (42501)'],
  ['reasignarDuranteAsociar', 'reasignación del destino durante asociar → asociar espera y revalida (42501)'],
  ['llamadaCambiaAlAsociar', 'la llamada cambia de lead mientras se asocia → 40001 «vuelve a intentarlo»'],
  ['reasignarDuranteEnlazar', 'reasignación durante enlazar → enlazar espera y revalida el ámbito (42501)'],
  ['deshacerDuranteEnlazar', 'Deshacer durante enlazar → enlazar espera y rechaza el resultado deshecho, sin interbloqueo'],
  ['enlazarDuranteDeshacer', 'enlazar durante Deshacer → Deshacer espera, sin interbloqueo'],
];

async function pasadaConcurrenciaCorreccion() {
  console.log('\n— Pasada 9: concurrencia de la quinta con dos sesiones reales —');
  psqlSql('create database conc_quinta template plantilla_cuatro', 'postgres');
  let r = psqlArchivo(MIG_CORRECCION, 'conc_quinta');
  if (!paso('banco de concurrencia listo (las cuatro + la quinta)', r.ok, r.ok ? '' : cola(r.salida))) return;
  const ctx = sembrarCorreccion('conc_quinta');
  if (!paso('celulares sembrados (C1, C2, C4, C5)', ctx.ok && Object.keys(ctx.asig).length === 4, JSON.stringify(ctx.asig))) return;
  for (const [clave, titulo] of CARRERAS_TITULOS) {
    const c = await CARRERAS[clave](ctx);
    paso(titulo, c.ok, c.detalle);
  }
  const original = readFileSync(MIG_CORRECCION, 'utf8').replace(/\r\n/g, '\n');
  for (const [i, mutante] of MUTANTES_CANDADOS.entries()) {
    const etiqueta = `mut_candado ${String(i + 1).padStart(2, '0')}: ${mutante.nombre}`;
    const m = aplicarMutante(original, mutante);
    if (m.error) { paso(etiqueta, false, `mutante obsoleto: ${m.error}`); continue; }
    const archivo = join(temporal, `mut-candado-${i + 1}.sql`);
    writeFileSync(archivo, m.texto);
    const db = `mut_candado_${i + 1}`;
    psqlSql(`create database ${db} template plantilla_cuatro`, 'postgres');
    r = psqlArchivo(archivo, db);
    if (!r.ok) { paso(etiqueta, false, `la migración mutada no se aplica: ${lineaError(r.salida)}`); continue; }
    const c = await CARRERAS[mutante.escenario](sembrarCorreccion(db));
    paso(etiqueta, !c.ok, c.ok ? 'SOBREVIVE: la carrera no lo nota' : `cazado por la carrera: ${c.detalle}`);
    psqlSql(`drop database ${db}`, 'postgres');
  }
}

// ── F4-a: carreras entre el aviso y la encuesta (pasada 12) ────────────────────────────────────
const v5Sql = (op, lead, id, via) => `select crm.registrar_llamada_v5('${op}', '${lead}', 'volver_a_llamar', null, null, null, null, false, false, '${id}', '${via}')::text;`;
const uuid = () => [4, 2, 2, 2, 6].map((n) => randomBytes(n).toString('hex')).join('-');
const cuenta = (db, sql) => psqlSql(sql, db).salida.trim();
const CARRERAS_ENLACE = {
  async avisoDuranteEncuesta(ctx) {
    const id = ctx.nuevoId('C1'); const op = uuid();
    const [s1, s2] = await Promise.all([
      psqlParalelo(retenerTx(comoSql(ACT.a1) + v5Sql(op, ACT.c1, id, 'al_colgar')), ctx.db),
      pausa(400).then(() => psqlParalelo(enTx(SERVICIO + ingerirSql(ctx.k.C1, id, '900000001')), ctx.db)),
    ]);
    const enl = cuenta(ctx.db, `select count(*) from crm.llamadas_celular_enlaces l join crm.llamadas_celular_eventos e on e.id = l.evento_id
      where e.evento_origen_id = '${id}' and l.actividad_id = '${op}' and l.via = 'al_colgar'`);
    const int = cuenta(ctx.db, `select count(*) from private.llamadas_celular_intenciones where evento_origen_id = '${id}'`);
    return { ok: s1.ok && s1.salida.includes('"estado": "pendiente"') && s2.ok && esperoYo(s2) && enl === '1' && int === '0',
             detalle: `aviso: ${s2.ms} ms · enlaces: ${enl} · intenciones: ${int}` };
  },
  async encuestaDuranteAviso(ctx) {
    const id = ctx.nuevoId('C1'); const op = uuid();
    const [s1, s2] = await Promise.all([
      psqlParalelo(retenerTx(SERVICIO + ingerirSql(ctx.k.C1, id, '900000001')), ctx.db),
      pausa(400).then(() => psqlParalelo(enTx(comoSql(ACT.a1) + v5Sql(op, ACT.c1, id, 'al_colgar')), ctx.db)),
    ]);
    const enl = cuenta(ctx.db, `select count(*) from crm.llamadas_celular_enlaces l join crm.llamadas_celular_eventos e on e.id = l.evento_id
      where e.evento_origen_id = '${id}' and l.actividad_id = '${op}'`);
    return { ok: s1.ok && s2.ok && s2.salida.includes('"estado": "enlazado"') && esperoYo(s2) && enl === '1',
             detalle: `encuesta: ${s2.ms} ms · ${(/"enlace": \{[^}]*\}/.exec(s2.salida) ?? [ultima(s2)])[0]} · enlaces: ${enl}` };
  },
  async dosEncuestasMismoId(ctx) {
    const id = ctx.nuevoId('C1'); const op1 = uuid(); const op2 = uuid();
    const [s1, s2] = await Promise.all([
      psqlParalelo(retenerTx(comoSql(ACT.a1) + v5Sql(op1, ACT.c1, id, 'al_colgar')), ctx.db),
      pausa(400).then(() => psqlParalelo(enTx(comoSql(ACT.a1) + v5Sql(op2, ACT.c1, id, 'pestana')), ctx.db)),
    ]);
    const guardados = cuenta(ctx.db, `select count(*) from crm.actividades where id in ('${op1}', '${op2}')`);
    return { ok: s1.ok && s2.ok && s2.salida.includes('ya_tiene_resultado') && esperoYo(s2) && guardados === '2',
             detalle: `segunda: ${s2.ms} ms · resultados guardados: ${guardados} · ${(/"motivo": "[a-z_]+"/.exec(s2.salida) ?? [ultima(s2)])[0]}` };
  },
  async deshacerDuranteCumplir(ctx) {
    const id = ctx.nuevoId('C1'); const op = uuid();
    psqlSql(enTx(comoSql(ACT.a1) + v5Sql(op, ACT.c1, id, 'al_colgar')), ctx.db);
    const [s1, s2] = await Promise.all([
      psqlParalelo(retenerTx(deshacerSql(op, ACT.c1)), ctx.db),
      pausa(400).then(() => psqlParalelo(enTx(SERVICIO + ingerirSql(ctx.k.C1, id, '900000001')), ctx.db)),
    ]);
    const enl = cuenta(ctx.db, `select count(*) from crm.llamadas_celular_enlaces where actividad_id = '${op}'`);
    const aten = cuenta(ctx.db, `select atencion from crm.llamadas_celular_eventos where evento_origen_id = '${id}'`);
    return { ok: s1.ok && s2.ok && esperoYo(s2) && enl === '0' && aten === 'requiere_resultado' && !`${s1.salida}${s2.salida}`.includes('deadlock'),
             detalle: `aviso: ${s2.ms} ms · enlaces al deshecho: ${enl} · la llamada queda: ${aten}` };
  },
};
const CARRERAS_ENLACE_TITULOS = [
  ['avisoDuranteEncuesta', 'el aviso llega mientras se guarda la encuesta → espera y cumple la intención (un enlace, sin intención)'],
  ['encuestaDuranteAviso', 'la encuesta llega mientras se guarda el aviso → espera y une directo'],
  ['dosEncuestasMismoId', 'dos encuestas con el mismo id → la segunda espera, se guarda y no reemplaza a la primera'],
  ['deshacerDuranteCumplir', 'Deshacer mientras la ingesta cumple la intención → la ingesta espera y no une el resultado deshecho, sin interbloqueo'],
];

// ── Séptima: Deshacer PAUSADO entre sus dos candados (pasada 14) ───────────────────────────────
// El orden real de Deshacer (20260920005000:649 y 682) con una pausa en medio: fuerza la intercalación que reprodujo la
// revisión de Miguel en el #190 (Deshacer tiene el resultado y espera el lead; el otro tiene el lead y pide el resultado).
const deshacerPausadoSql = (act, lead, fin = 'commit') => `begin;
select 1 from crm.actividades where id = '${act}' for update;
select pg_sleep(1.2);
select 1 from crm.leads where id = '${lead}' for update;
update crm.actividades set metadata = metadata || jsonb_build_object('deshecho_en', now()) where id = '${act}';
${fin};
`;
const sinInterbloqueo = (...ss) => !ss.some((s) => /deadlock|40P01/.test(s.salida));
const v5SinIdSql = (op, lead) => `select crm.registrar_llamada_v5('${op}', '${lead}', 'volver_a_llamar', null, null, null, null, false, false, null, null)::text;`;
// enlaces del resultado / intenciones del id / recepciones del id / atención de la llamada / ¿resultado deshecho?
const estadoEnlace = (db, id, op) => cuenta(db, `select (select count(*) from crm.llamadas_celular_enlaces where actividad_id = '${op}') || '/'
  || (select count(*) from private.llamadas_celular_intenciones where evento_origen_id = '${id}') || '/'
  || (select count(*) from private.llamadas_celular_recepciones where evento_origen_id = '${id}') || '/'
  || coalesce((select atencion from crm.llamadas_celular_eventos where evento_origen_id = '${id}'), '-') || '/'
  || (select (metadata ? 'deshecho_en')::text from crm.actividades where id = '${op}')`);
const ambas = (s1, s2) => `deshacer: ${s1.ok ? 'ok' : lineaError(s1.salida)} · otra: ${s2.ms} ms, ${s2.ok ? ultima(s2) : lineaError(s2.salida)}`;
const CARRERAS_SIN_CICLO = {
  async deshacerEntreCandados(ctx, fin = 'commit') {
    const id = ctx.nuevoId('C1'); const op = uuid();
    psqlSql(enTx(comoSql(ACT.a1) + v5Sql(op, ACT.c1, id, 'al_colgar')), ctx.db);
    const [s1, s2] = await Promise.all([
      psqlParalelo(deshacerPausadoSql(op, ACT.c1, fin), ctx.db),
      pausa(250).then(() => psqlParalelo(enTx(SERVICIO + ingerirSql(ctx.k.C1, id, '900000001')), ctx.db)),
    ]);
    const estado = estadoEnlace(ctx.db, id, op);
    const esperado = `0/0/1/requiere_resultado/${fin === 'commit' ? 'true' : 'false'}`;
    return { ok: s1.ok && s2.ok && s2.salida.includes('"resultado": "aceptado"') && sinInterbloqueo(s1, s2) && estado === esperado,
             detalle: `enlaces/intenciones/recepciones/atención/deshecho: ${estado} · ${ambas(s1, s2)}` };
  },
  async cumplirAntesDeDeshacer(ctx) {
    const id = ctx.nuevoId('C1'); const op = uuid();
    psqlSql(enTx(comoSql(ACT.a1) + v5Sql(op, ACT.c1, id, 'al_colgar')), ctx.db);
    const [s1, s2] = await Promise.all([
      psqlParalelo(retenerTx(SERVICIO + ingerirSql(ctx.k.C1, id, '900000001')), ctx.db),
      pausa(400).then(() => psqlParalelo(enTx(deshacerSql(op, ACT.c1)), ctx.db)),
    ]);
    const estado = estadoEnlace(ctx.db, id, op);
    return { ok: s1.ok && s1.salida.includes('"resultado": "aceptado"') && s2.ok && esperoYo(s2) && sinInterbloqueo(s1, s2)
               && estado === '1/0/1/registrado/true',
             detalle: `enlaces/intenciones/recepciones/atención/deshecho: ${estado} · deshacer: ${s2.ms} ms, ${s2.ok ? 'ok' : lineaError(s2.salida)}` };
  },
  async deshacerRevertido(ctx) {
    return CARRERAS_SIN_CICLO.deshacerEntreCandados(ctx, 'rollback');
  },
  async reintentoV5DuranteDeshacer(ctx) {
    const id = ctx.nuevoId('C1'); const op = uuid();
    psqlSql(enTx(SERVICIO + ingerirSql(ctx.k.C1, id, '900000001')), ctx.db); // la llamada ya llegó
    psqlSql(enTx(comoSql(ACT.a1) + v5SinIdSql(op, ACT.c1)), ctx.db); // la encuesta se guardó sin el id
    const [s1, s2] = await Promise.all([
      psqlParalelo(deshacerPausadoSql(op, ACT.c1), ctx.db),
      pausa(250).then(() => psqlParalelo(enTx(comoSql(ACT.a1) + v5Sql(op, ACT.c1, id, 'al_colgar')), ctx.db)),
    ]);
    const estado = estadoEnlace(ctx.db, id, op);
    return { ok: s1.ok && s2.ok && s2.salida.includes('"motivo": "resultado_en_uso"') && sinInterbloqueo(s1, s2)
               && estado === '0/0/1/requiere_resultado/true',
             detalle: `enlaces/intenciones/recepciones/atención/deshecho: ${estado} · ${ambas(s1, s2)}` };
  },
};
const CARRERAS_SIN_CICLO_TITULOS = [
  ['deshacerEntreCandados', 'Deshacer pausado entre resultado y lead, con el aviso en medio → sin interbloqueo: el aviso se guarda y no se une; la intención se retira'],
  ['cumplirAntesDeDeshacer', 'el aviso cumple la intención y Deshacer llega después → Deshacer espera, sin interbloqueo; el enlace queda'],
  ['deshacerRevertido', 'Deshacer pausado que se revierte → sin interbloqueo; la llamada queda para unirla a mano (lo aceptado al no esperar)'],
  ['reintentoV5DuranteDeshacer', 'reintento de la v5 con Deshacer entre sus candados → no_enlazado «resultado_en_uso», sin interbloqueo'],
];

let arrancado = false;
try {
  const init = correr('initdb', ['-D', datos, '-U', USUARIO, '-A', 'scram-sha-256', '--pwfile', archivoClave,
    '--no-locale', '-E', 'UTF8']);
  if (!init.ok) throw new Error(`initdb falló:\n${cola(init.salida)}`);
  const inicio = correr('pg_ctl', ['-D', datos, '-l', bitacora, '-w', '-t', '60',
    '-o', `-c listen_addresses=127.0.0.1 -p ${PUERTO} -c fsync=off -c timezone=UTC`, 'start'], { sinTuberias: true });
  if (!inicio.ok) {
    const log = existsSync(bitacora) ? readFileSync(bitacora, 'utf8') : '';
    throw new Error(`pg_ctl start falló:\n${cola(inicio.salida)}\n${cola(log)}`);
  }
  arrancado = true;
  const version = psqlSql('show server_version', 'postgres');
  console.log(`Banco desechable: PostgreSQL ${version.salida.trim()} en 127.0.0.1:${PUERTO} (se borra al terminar)\n`);

  // Plantillas: el banco reducido solo, y con los datos (F2-b) para los mutantes del núcleo.
  let r = psqlSql('create database plantilla', 'postgres');
  if (!r.ok) throw new Error(`no se pudo crear la plantilla:\n${cola(r.salida)}`);
  r = psqlArchivo(BASE, 'plantilla');
  paso('banco reducido sembrado', r.ok, r.ok ? '' : cola(r.salida));
  if (!r.ok) throw new Error('sin banco reducido no hay pruebas');
  psqlSql('create database plantilla_datos template plantilla', 'postgres');
  r = psqlArchivo(MIG_DATOS, 'plantilla_datos');
  if (!r.ok) throw new Error(`la plantilla con datos no se pudo preparar:\n${cola(r.salida)}`);
  psqlSql('create database plantilla_nucleo template plantilla_datos', 'postgres');
  r = psqlArchivo(MIG_NUCLEO, 'plantilla_nucleo');
  if (!r.ok) throw new Error(`la plantilla con el núcleo no se pudo preparar:\n${cola(r.salida)}`);
  // Las cuatro, en el orden de publicación: el punto de partida de la quinta (pasadas 7–9).
  psqlSql('create database plantilla_cuatro template plantilla_nucleo', 'postgres');
  r = psqlArchivo(MIG_INGESTA, 'plantilla_cuatro');
  if (r.ok) r = psqlArchivo(MIG_ELEGIBILIDAD, 'plantilla_cuatro');
  if (!r.ok) throw new Error(`la plantilla con las cuatro no se pudo preparar:\n${cola(r.salida)}`);
  // Y con la quinta: el punto de partida de F4-a (pasadas 10–12).
  psqlSql('create database plantilla_cinco template plantilla_cuatro', 'postgres');
  r = psqlArchivo(MIG_CORRECCION, 'plantilla_cinco');
  if (!r.ok) throw new Error(`la plantilla con las cinco no se pudo preparar:\n${cola(r.salida)}`);
  // Y con F4-a: el punto de partida de la séptima (pasadas 13–14).
  psqlSql('create database plantilla_seis template plantilla_cinco', 'postgres');
  r = psqlArchivo(MIG_ENLACE, 'plantilla_seis');
  if (!r.ok) throw new Error(`la plantilla con las seis no se pudo preparar:\n${cola(r.salida)}`);
  // Y con la séptima: el punto de partida de la octava (pasada 15).
  psqlSql('create database plantilla_siete template plantilla_seis', 'postgres');
  r = psqlArchivo(MIG_SIN_CICLO, 'plantilla_siete');
  if (!r.ok) throw new Error(`la plantilla con las siete no se pudo preparar:\n${cola(r.salida)}`);
  // Y con la octava: el punto de partida de la novena (pasada 16).
  psqlSql('create database plantilla_ocho template plantilla_siete', 'postgres');
  r = psqlArchivo(MIG_LECTURAS, 'plantilla_ocho');
  if (!r.ok) throw new Error(`la plantilla con las ocho no se pudo preparar:\n${cola(r.salida)}`);
  // Y con la novena: el punto de partida de la décima (pasada 17); con la décima, el de la undécima (pasada 18).
  psqlSql('create database plantilla_nueve template plantilla_ocho', 'postgres');
  r = psqlArchivo(MIG_PAGINADAS, 'plantilla_nueve');
  if (!r.ok) throw new Error(`la plantilla con las nueve no se pudo preparar:\n${cola(r.salida)}`);
  psqlSql('create database plantilla_diez template plantilla_nueve', 'postgres');
  r = psqlArchivo(MIG_ORIGEN, 'plantilla_diez');
  if (!r.ok) throw new Error(`la plantilla con las diez no se pudo preparar:\n${cola(r.salida)}`);
  psqlSql('create database principal template plantilla', 'postgres');

  console.log('\n— Pasada 1: las migraciones tal cual —');
  const db = 'principal';
  const oraculoDatos = (nombre) => {
    const o = psqlArchivo(ORACULO_DATOS, db);
    return paso(nombre, o.ok && o.salida.includes('ORACULO F2-b OK'), lineasOraculo(o.salida));
  };
  const oraculoNucleo = (nombre) => {
    const o = psqlArchivo(ORACULO_NUCLEO, db);
    return paso(nombre, o.ok && o.salida.includes('ORACULO F2-c OK'), lineasOraculo(o.salida));
  };
  const oraculoIngesta = (nombre) => {
    const o = psqlArchivo(ORACULO_INGESTA, db);
    return paso(nombre, o.ok && o.salida.includes('ORACULO F3-a OK'), lineasOraculo(o.salida));
  };
  r = psqlArchivo(MIG_DATOS, db);
  paso('F2-b aplicada (precondición, tablas, candados, purga, postflight)', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_DATOS, db);
  paso('F2-b se niega a sobrescribirse', !r.ok && r.salida.includes('los objetos ya existen'), r.ok ? 'se aplicó dos veces' : '');
  oraculoDatos('oráculo de F2-b');
  r = psqlArchivo(MIG_NUCLEO, db);
  paso('F2-c aplicada (núcleo, puertas, permisos, postflight)', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_NUCLEO, db);
  paso('F2-c se niega a sobrescribirse', !r.ok && r.salida.includes('los objetos ya existen'), r.ok ? 'se aplicó dos veces' : '');
  oraculoNucleo('oráculo de F2-c');
  oraculoDatos('oráculo de F2-b con F2-c instalado');
  r = psqlSql('select count(*) from crm.llamadas_celular_eventos', db);
  paso('los oráculos no dejaron filas (terminan en ROLLBACK)', r.ok && r.salida.trim() === '0', r.salida.trim());

  // F3-a encima de F2: se aplica, se niega a repetirse, pasa su oráculo sin romper los de F2, la
  // reversa del núcleo se niega mientras F3-a siga, y su propia reversa la retira y la deja reaplicar.
  r = psqlArchivo(MIG_INGESTA, db);
  paso('F3-a aplicada (límite, tabla técnica, puertas de servicio y de lectura, postflight)', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_INGESTA, db);
  paso('F3-a se niega a sobrescribirse', !r.ok && r.salida.includes('los objetos ya existen'), r.ok ? 'se aplicó dos veces' : '');
  oraculoIngesta('oráculo de F3-a');
  oraculoNucleo('oráculo de F2-c con F3-a instalada');
  oraculoDatos('oráculo de F2-b con F3-a instalada');
  r = psqlSql('select (select count(*) from crm.llamadas_celular_eventos) + (select count(*) from private.celulares_estado)', db);
  paso('el oráculo de F3-a no dejó filas', r.ok && r.salida.trim() === '0', r.salida.trim());
  r = psqlArchivo(REVERSA_NUCLEO, db);
  paso('la reversa del núcleo se niega con F3-a instalada', !r.ok && r.salida.includes('la ingesta F3-a sigue instalada'), r.ok ? 'se aplicó fuera de orden' : '');
  r = psqlArchivo(REVERSA_INGESTA, db);
  paso('reversa de F3-a (puertas, núcleo, tabla técnica y límites)', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_INGESTA, db);
  paso('F3-a se vuelve a aplicar tras su reversa', r.ok, r.ok ? '' : cola(r.salida));
  oraculoIngesta('oráculo de F3-a tras reaplicar');
  r = psqlArchivo(REVERSA_INGESTA, db);
  paso('reversa de F3-a (otra vez, antes del núcleo)', r.ok, r.ok ? '' : cola(r.salida));

  // Corrección de F2-c (20261001222431): la ingesta evalúa la elegibilidad como el dueño del celular.
  const oraculoElegibilidad = (nombre) => {
    const o = psqlArchivo(ORACULO_ELEGIBILIDAD, db);
    return paso(nombre, o.ok && o.salida.includes('ORACULO ELEGIBILIDAD OK'), lineasOraculo(o.salida));
  };
  r = psqlArchivo(MIG_ELEGIBILIDAD, db);
  paso('corrección de elegibilidad aplicada (ayudante, ingesta con una línea cambiada, postflight)', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_ELEGIBILIDAD, db);
  paso('la corrección se niega a sobrescribirse', !r.ok && r.salida.includes('los objetos ya existen'), r.ok ? 'se aplicó dos veces' : '');
  oraculoElegibilidad('oráculo de la corrección de elegibilidad');
  oraculoNucleo('oráculo de F2-c con la corrección instalada');
  oraculoDatos('oráculo de F2-b con la corrección instalada');
  r = psqlArchivo(REVERSA_NUCLEO, db);
  paso('la reversa del núcleo se niega con la corrección instalada', !r.ok && r.salida.includes('la corrección de elegibilidad sigue instalada'), r.ok ? 'se aplicó fuera de orden' : '');
  r = psqlArchivo(REVERSA_ELEGIBILIDAD, db);
  paso('reversa de la corrección (la ingesta vuelve al cuerpo de F2-c)', r.ok, r.ok ? '' : cola(r.salida));
  oraculoNucleo('oráculo de F2-c tras revertir la corrección');
  r = psqlArchivo(MIG_ELEGIBILIDAD, db);
  paso('la corrección se vuelve a aplicar tras su reversa', r.ok, r.ok ? '' : cola(r.salida));
  oraculoElegibilidad('oráculo de la corrección tras reaplicar');
  r = psqlArchivo(REVERSA_ELEGIBILIDAD, db);
  paso('reversa de la corrección (otra vez, antes del núcleo)', r.ok, r.ok ? '' : cola(r.salida));

  r = psqlArchivo(REVERSA_DATOS, db);
  paso('la reversa de datos se niega con el núcleo instalado', !r.ok && r.salida.includes('el núcleo F2-c sigue instalado'), r.ok ? 'se aplicó fuera de orden' : '');
  r = psqlArchivo(REVERSA_NUCLEO, db);
  paso('reversa del núcleo', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlSql('select count(*) from crm.llamadas_celular_politica', db);
  paso('tras esa reversa las tablas siguen', r.ok && r.salida.trim() === '1', r.salida.trim());
  r = psqlArchivo(MIG_NUCLEO, db);
  paso('F2-c se vuelve a aplicar tras su reversa', r.ok, r.ok ? '' : cola(r.salida));
  oraculoNucleo('oráculo de F2-c tras reaplicar');
  r = psqlArchivo(REVERSA_NUCLEO, db);
  paso('reversa del núcleo (otra vez, antes de los datos)', r.ok, r.ok ? '' : cola(r.salida));

  r = psqlArchivo(REVERSA_DATOS, db);
  paso('reversa de datos que conserva los hechos', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlSql('select count(*) from crm.llamadas_celular_politica', db);
  paso('tras esa reversa las tablas siguen (política con 1 fila)', r.ok && r.salida.trim() === '1', r.salida.trim());
  r = psqlSql("insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash) "
    + "select 'C9', e.perfil_id, repeat('e', 64) from crm.equipo e where e.rol_crm = 'vendedor' and e.activo order by e.perfil_id limit 1", db);
  paso('fila de prueba para la reversa total', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(REVERSA_TOTAL, db);
  paso('reversa total se niega si hay filas', !r.ok && r.salida.includes('la evidencia no se borra'), r.ok ? 'borró con filas' : '');
  r = psqlSql("delete from crm.celulares_asignaciones where etiqueta = 'C9'", db);
  paso('fila de prueba retirada', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(REVERSA_TOTAL, db);
  paso('reversa total sin filas', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_DATOS, db);
  paso('F2-b se vuelve a aplicar tras la reversa total', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_NUCLEO, db);
  paso('F2-c se vuelve a aplicar encima', r.ok, r.ok ? '' : cola(r.salida));
  oraculoDatos('oráculo de F2-b tras reaplicar todo');
  oraculoNucleo('oráculo de F2-c tras reaplicar todo');
  r = psqlArchivo(MIG_INGESTA, db);
  paso('F3-a se vuelve a aplicar encima de todo', r.ok, r.ok ? '' : cola(r.salida));
  oraculoIngesta('oráculo de F3-a tras reaplicar todo');
  r = psqlArchivo(MIG_ELEGIBILIDAD, db);
  paso('la corrección de elegibilidad se aplica encima de todo', r.ok, r.ok ? '' : cola(r.salida));
  oraculoElegibilidad('oráculo de la corrección con todo instalado');
  oraculoIngesta('oráculo de F3-a con la corrección instalada');
  oraculoNucleo('oráculo de F2-c con todo instalado');

  pasadaMutantes('Pasada 2: mutantes de F2-b (datos)', MIG_DATOS, MUTANTES_DATOS, 'plantilla', ORACULO_DATOS, 'mut_datos');
  pasadaMutantes('Pasada 3: mutantes de F2-c (núcleo y puertas)', MIG_NUCLEO, MUTANTES_NUCLEO, 'plantilla_datos', ORACULO_NUCLEO, 'mut_nucleo');
  pasadaMutantes('Pasada 4: mutantes de F3-a (servicio, límite, salud y bandeja)', MIG_INGESTA, MUTANTES_INGESTA, 'plantilla_nucleo', ORACULO_INGESTA, 'mut_ingesta');
  pasadaMutantes('Pasada 5: mutantes de la corrección de elegibilidad', MIG_ELEGIBILIDAD, MUTANTES_ELEGIBILIDAD, 'plantilla_nucleo', ORACULO_ELEGIBILIDAD, 'mut_elegib');
  await pasadaConcurrencia();

  // ── Pasada 7: la quinta sobre las cuatro ──
  console.log('\n— Pasada 7: la quinta (corrección de F2 + F3) —');
  const dq = 'quinta';
  const oraculoEn = (nombre, archivo, marca, base) => {
    const o = psqlArchivo(archivo, base);
    return paso(nombre, o.ok && o.salida.includes(marca), lineasOraculo(o.salida));
  };
  const huella = (base) => correr('psql', ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-d', base, '-f', HUELLA]);
  psqlSql(`create database ${dq} template plantilla_cuatro`, 'postgres');
  const h0 = huella(dq);
  const lineasH0 = h0.salida.trim().split(/\r?\n/);
  paso('huella del catálogo de las cuatro', h0.ok && lineasH0.length > 100, h0.ok ? `${lineasH0.length} líneas` : cola(h0.salida));
  r = psqlArchivo(MIG_CORRECCION, dq);
  paso('quinta aplicada (recepción, id fijo, candidatos, candados, entrantes, retención, salud, postflight)', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_CORRECCION, dq);
  paso('la quinta se niega a sobrescribirse', !r.ok && r.salida.includes('los objetos ya existen'), r.ok ? 'se aplicó dos veces' : '');
  oraculoEn('oráculo de la quinta', ORACULO_CORRECCION, 'ORACULO CORRECCION OK', dq);
  r = psqlSql(`select (select count(*) from crm.llamadas_celular_eventos) + (select count(*) from private.llamadas_celular_recepciones)
    + (select count(*) from private.celulares_estado) + (select count(*) from crm.celulares_asignaciones)`, dq);
  paso('el oráculo de la quinta no dejó filas', r.ok && r.salida.trim() === '0', r.salida.trim());
  r = psqlArchivo(REVERSA_ELEGIBILIDAD, dq);
  paso('la reversa de elegibilidad se niega con la quinta puesta', !r.ok && r.salida.includes('la corrección 20261005143843 sigue instalada'), r.ok ? 'se aplicó fuera de orden' : '');
  r = psqlArchivo(REVERSA_INGESTA, dq);
  paso('la reversa de la ingesta se niega con la quinta puesta', !r.ok && r.salida.includes('la corrección 20261005143843 sigue instalada'), r.ok ? 'se aplicó fuera de orden' : '');
  r = psqlArchivo(REVERSA_CORRECCION, dq);
  paso('reversa de la quinta (antes del primer aviso)', r.ok, r.ok ? '' : cola(r.salida));
  const h1 = huella(dq);
  const distintas = h1.salida.trim().split(/\r?\n/).filter((l, i) => l !== lineasH0[i]);
  paso('la reversa vuelve EXACTAMENTE a la huella de las cuatro', h1.ok && h1.salida === h0.salida,
    h1.ok ? distintas.slice(0, 4).join('\n') : cola(h1.salida));
  oraculoEn('oráculo de la corrección de elegibilidad tras la reversa', ORACULO_ELEGIBILIDAD, 'ORACULO ELEGIBILIDAD OK', dq);
  oraculoEn('oráculo de F3-a tras la reversa', ORACULO_INGESTA, 'ORACULO F3-a OK', dq);
  oraculoEn('oráculo de F2-c tras la reversa', ORACULO_NUCLEO, 'ORACULO F2-c OK', dq);
  r = psqlArchivo(MIG_CORRECCION, dq);
  paso('la quinta se vuelve a aplicar tras su reversa', r.ok, r.ok ? '' : cola(r.salida));
  oraculoEn('oráculo de la quinta tras reaplicar', ORACULO_CORRECCION, 'ORACULO CORRECCION OK', dq);
  // Barrera: con filas, la quinta se niega; tras el primer aviso, su reversa también.
  psqlSql('create database quinta_filas template plantilla_cuatro', 'postgres');
  psqlSql(`insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash) values ('C9', '${ACT.a1}', repeat('e', 64))`, 'quinta_filas');
  r = psqlArchivo(MIG_CORRECCION, 'quinta_filas');
  paso('la quinta se niega si hay filas (barrera)', !r.ok && r.salida.includes('hay filas en las tablas de llamadas'), r.ok ? 'se aplicó con filas' : '');
  psqlSql('drop database quinta_filas', 'postgres');
  psqlSql(`create database quinta_aviso template ${dq}`, 'postgres');
  r = psqlSql(`insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash) values ('C9', '${ACT.a1}', repeat('e', 64)) returning id`, 'quinta_aviso');
  psqlSql(`insert into private.llamadas_celular_recepciones (evento_origen_id, asignacion_id, recibido_en) values ('C9-1790000000', '${r.salida.trim()}', now())`, 'quinta_aviso');
  r = psqlArchivo(REVERSA_CORRECCION, 'quinta_aviso');
  paso('la reversa de la quinta se niega tras el primer aviso', !r.ok && r.salida.includes('ya se dio de alta algún celular'), r.ok ? 'revirtió con avisos' : '');
  psqlSql('drop database quinta_aviso', 'postgres');
  // Regresión de la revisión de Miguel (#190, 05/10): «ahora está vacío» no prueba «nunca se usó». Un aviso ignorado
  // deja solo su recepción; la purga real la retira a los 32 días; la reversa tiene que seguir negándose, también
  // después de rotar y cerrar todas las claves.
  psqlSql(`create database quinta_alta template ${dq}`, 'postgres');
  psqlSql(`insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash) values ('C9', '${ACT.a1}', repeat('e', 64))`, 'quinta_alta');
  r = psqlArchivo(REVERSA_CORRECCION, 'quinta_alta');
  paso('la reversa de la quinta se niega con un celular dado de alta, aunque no haya avisado', !r.ok && r.salida.includes('ya se dio de alta algún celular'), r.ok ? 'revirtió con un alta' : '');
  psqlSql('drop database quinta_alta', 'postgres');
  psqlSql(`create database quinta_caduca template ${dq}`, 'postgres');
  const ctxCaduca = sembrarCorreccion('quinta_caduca');
  r = psqlSql(enTx(SERVICIO + ingerirSql(ctxCaduca.k.C1, ctxCaduca.nuevoId('C1'), '900000099')), 'quinta_caduca');
  const aceptadoIgnorado = r.ok && r.salida.includes('"resultado": "aceptado"');
  psqlSql(`alter table private.llamadas_celular_recepciones disable trigger trg_llamadas_celular_recepciones_00_candado;
    update private.llamadas_celular_recepciones set recibido_en = now() - interval '33 days';
    alter table private.llamadas_celular_recepciones enable trigger trg_llamadas_celular_recepciones_00_candado;`, 'quinta_caduca');
  // La purga y los conteos en sentencias distintas: una sola sentencia vería la tabla como estaba al empezar.
  const purgadas = cuenta('quinta_caduca', 'select private.caducar_llamadas_celular()');
  const tras = `${purgadas}/${cuenta('quinta_caduca', 'select count(*) from private.llamadas_celular_recepciones')}/${cuenta('quinta_caduca', 'select count(*) from crm.llamadas_celular_eventos')}`;
  psqlSql(enTx(`${comoSql(ACT.g1)}select crm.rotar_credencial_celular('C1') is not null;`), 'quinta_caduca');
  const abiertas = cuenta('quinta_caduca', 'select id from crm.celulares_asignaciones where vigente_hasta is null').split(/\r?\n/).filter(Boolean);
  psqlSql(enTx(comoSql(ACT.g1) + abiertas.map((id) => `select crm.cerrar_asignacion_celular('${id}', 'otro') is not null;`).join('\n')), 'quinta_caduca');
  const vigentes = cuenta('quinta_caduca', 'select count(*) from crm.celulares_asignaciones where vigente_hasta is null');
  r = psqlArchivo(REVERSA_CORRECCION, 'quinta_caduca');
  paso('aviso ignorado → la purga real retira su recepción → claves rotadas y cerradas → la reversa sigue negándose',
    aceptadoIgnorado && tras === '1/0/0' && vigentes === '0' && !r.ok && r.salida.includes('ya se dio de alta algún celular'),
    `purga/recepciones/llamadas: ${tras} · vigentes: ${vigentes} · ${r.ok ? 'REVIRTIÓ' : lineaError(r.salida)}`);
  // Mutante: sin la guarda nueva (asignaciones y estado), esa misma reversa revierte; la regresión tiene que notarlo.
  const reversaSinGuarda = aplicarCambio(readFileSync(REVERSA_CORRECCION, 'utf8').replace(/\r\n/g, '\n'), {
    buscar: '  if exists (select 1 from crm.celulares_asignaciones) or exists (select 1 from private.celulares_estado)\n     or exists',
    poner: '  if exists' });
  if (reversaSinGuarda.error) paso('mut_reversa 01: sin la guarda de asignaciones y estado', false, `mutante obsoleto: ${reversaSinGuarda.error}`);
  else {
    writeFileSync(join(temporal, 'mut-reversa-1.sql'), reversaSinGuarda.texto);
    r = psqlArchivo(join(temporal, 'mut-reversa-1.sql'), 'quinta_caduca');
    paso('mut_reversa 01: sin la guarda de asignaciones y estado', r.ok, r.ok ? 'cazado por la regresión: la reversa mutada revierte tras la purga' : `SOBREVIVE: ${lineaError(r.salida)}`);
  }
  psqlSql('drop database quinta_caduca', 'postgres');

  pasadaMutantes('Pasada 8: mutantes de la quinta', MIG_CORRECCION, MUTANTES_CORRECCION, 'plantilla_cuatro', ORACULO_CORRECCION, 'mut_quinta');
  await pasadaConcurrenciaCorreccion();

  // ── Pasada 10: F4-a sobre las cinco ──
  console.log('\n— Pasada 10: F4-a (enlace exacto encuesta ↔ llamada) —');
  const de = 'enlace';
  psqlSql(`create database ${de} template plantilla_cinco`, 'postgres');
  const g0 = huella(de);
  const lineasG0 = g0.salida.trim().split(/\r?\n/);
  paso('huella del catálogo de las cinco', g0.ok && lineasG0.length > 100, g0.ok ? `${lineasG0.length} líneas` : cola(g0.salida));
  r = psqlArchivo(MIG_ENLACE, de);
  paso('F4-a aplicada (v5, intenciones, vía, ingesta que cumple, purga, postflight)', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_ENLACE, de);
  paso('F4-a se niega a sobrescribirse', !r.ok && r.salida.includes('los objetos ya existen'), r.ok ? 'se aplicó dos veces' : '');
  oraculoEn('oráculo de F4-a', ORACULO_ENLACE, 'ORACULO ENLACE EXACTO OK', de);
  oraculoEn('oráculo de la quinta con F4-a puesta', ORACULO_CORRECCION, 'ORACULO CORRECCION OK', de);
  r = psqlSql(`select (select count(*) from crm.llamadas_celular_eventos) + (select count(*) from crm.llamadas_celular_enlaces)
    + (select count(*) from private.llamadas_celular_intenciones) + (select count(*) from crm.celulares_asignaciones)`, de);
  paso('los oráculos no dejaron filas', r.ok && r.salida.trim() === '0', r.salida.trim());
  r = psqlArchivo(REVERSA_CORRECCION, de);
  paso('la reversa de la quinta se niega con F4-a puesta', !r.ok && r.salida.includes('F4-a (20261005155914) sigue instalada'), r.ok ? 'se aplicó fuera de orden' : '');
  r = psqlArchivo(REVERSA_ENLACE, de);
  paso('reversa de F4-a (antes del primer aviso)', r.ok, r.ok ? '' : cola(r.salida));
  const g1 = huella(de);
  const distintasG = g1.salida.trim().split(/\r?\n/).filter((l, i) => l !== lineasG0[i]);
  paso('la reversa de F4-a vuelve EXACTAMENTE a la huella de las cinco', g1.ok && g1.salida === g0.salida,
    g1.ok ? distintasG.slice(0, 4).join('\n') : cola(g1.salida));
  oraculoEn('oráculo de la quinta tras la reversa de F4-a', ORACULO_CORRECCION, 'ORACULO CORRECCION OK', de);
  r = psqlArchivo(MIG_ENLACE, de);
  paso('F4-a se vuelve a aplicar tras su reversa', r.ok, r.ok ? '' : cola(r.salida));
  oraculoEn('oráculo de F4-a tras reaplicar', ORACULO_ENLACE, 'ORACULO ENLACE EXACTO OK', de);
  psqlSql(`create database enlace_aviso template ${de}`, 'postgres');
  const ctxAviso = sembrarCorreccion('enlace_aviso');
  llamada(ctxAviso, 'C1', '900000001');
  psqlSql(enTx(comoSql(ACT.a1) + v5Sql(uuid(), ACT.c1, ctxAviso.nuevoId('C1'), 'al_colgar')), 'enlace_aviso');
  r = psqlArchivo(REVERSA_ENLACE, 'enlace_aviso');
  paso('la reversa de F4-a se niega con intenciones o enlaces', !r.ok && r.salida.includes('ya se dio de alta algún celular'), r.ok ? 'revirtió con datos' : '');
  psqlSql('drop database enlace_aviso', 'postgres');
  // Regresión (revisión de Miguel, #190): una intención que caduca sin aviso no vuelve a habilitar la reversa.
  psqlSql(`create database enlace_caduca template ${de}`, 'postgres');
  const ctxCad = sembrarCorreccion('enlace_caduca');
  r = psqlSql(enTx(comoSql(ACT.a1) + v5Sql(uuid(), ACT.c1, ctxCad.nuevoId('C1'), 'al_colgar')), 'enlace_caduca');
  const pendiente = r.ok && r.salida.includes('"estado": "pendiente"');
  psqlSql(`alter table private.llamadas_celular_intenciones disable trigger trg_llamadas_celular_intenciones_00_candado;
    update private.llamadas_celular_intenciones set creado_en = now() - interval '33 days';
    alter table private.llamadas_celular_intenciones enable trigger trg_llamadas_celular_intenciones_00_candado;
    select private.caducar_llamadas_celular();`, 'enlace_caduca');
  const restos = cuenta('enlace_caduca', `select (select count(*) from private.llamadas_celular_intenciones) || '/' || (select count(*) from crm.llamadas_celular_enlaces)
    || '/' || (select count(*) from private.llamadas_celular_recepciones) || '/' || (select count(*) from crm.llamadas_celular_eventos)`);
  r = psqlArchivo(REVERSA_ENLACE, 'enlace_caduca');
  paso('intención sin aviso → la purga real la retira → la reversa de F4-a sigue negándose',
    pendiente && restos === '0/0/0/0' && !r.ok && r.salida.includes('ya se dio de alta algún celular'),
    `intenciones/enlaces/recepciones/llamadas: ${restos} · ${r.ok ? 'REVIRTIÓ' : lineaError(r.salida)}`);
  const reversaEnlaceSinGuarda = aplicarCambio(readFileSync(REVERSA_ENLACE, 'utf8').replace(/\r\n/g, '\n'), {
    buscar: '  if exists (select 1 from crm.celulares_asignaciones) or exists (select 1 from private.celulares_estado)\n     or exists (select 1 from private.llamadas_celular_recepciones) or exists (select 1 from crm.llamadas_celular_eventos)\n     or exists',
    poner: '  if exists' });
  if (reversaEnlaceSinGuarda.error) paso('mut_reversa 02: F4-a sin la guarda de alta', false, `mutante obsoleto: ${reversaEnlaceSinGuarda.error}`);
  else {
    writeFileSync(join(temporal, 'mut-reversa-2.sql'), reversaEnlaceSinGuarda.texto);
    r = psqlArchivo(join(temporal, 'mut-reversa-2.sql'), 'enlace_caduca');
    paso('mut_reversa 02: F4-a sin la guarda de alta', r.ok, r.ok ? 'cazado por la regresión: la reversa mutada revierte tras la purga' : `SOBREVIVE: ${lineaError(r.salida)}`);
  }
  psqlSql('drop database enlace_caduca', 'postgres');

  pasadaMutantes('Pasada 11: mutantes de F4-a', MIG_ENLACE, MUTANTES_ENLACE, 'plantilla_cinco', ORACULO_ENLACE, 'mut_enlace');

  console.log('\n— Pasada 12: carreras de F4-a con dos sesiones reales —');
  psqlSql('create database conc_enlace template plantilla_cinco', 'postgres');
  r = psqlArchivo(MIG_ENLACE, 'conc_enlace');
  if (paso('banco de carreras listo (las cinco + F4-a)', r.ok, r.ok ? '' : cola(r.salida))) {
    const ctxE = sembrarCorreccion('conc_enlace');
    for (const [clave, titulo] of CARRERAS_ENLACE_TITULOS) {
      const c = await CARRERAS_ENLACE[clave](ctxE);
      paso(titulo, c.ok, c.detalle);
    }
  }

  // ── Pasada 13: la séptima sobre las seis ──
  console.log('\n— Pasada 13: la séptima (enlace exacto sin ciclo con Deshacer) —');
  const ds = 'sin_ciclo';
  psqlSql(`create database ${ds} template plantilla_seis`, 'postgres');
  const k0 = huella(ds);
  const lineasK0 = k0.salida.trim().split(/\r?\n/);
  paso('huella del catálogo de las seis', k0.ok && lineasK0.length > 100, k0.ok ? `${lineasK0.length} líneas` : cola(k0.salida));
  r = psqlArchivo(MIG_SIN_CICLO, ds);
  paso('séptima aplicada (resultado FOR KEY SHARE NOWAIT en la v5 y al cumplir la intención, postflight)', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_SIN_CICLO, ds);
  paso('la séptima se niega a sobrescribirse', !r.ok && r.salida.includes('ya está aplicada'), r.ok ? 'se aplicó dos veces' : '');
  oraculoEn('oráculo de F4-a con la séptima puesta', ORACULO_ENLACE, 'ORACULO ENLACE EXACTO OK', ds);
  oraculoEn('oráculo de la quinta con la séptima puesta', ORACULO_CORRECCION, 'ORACULO CORRECCION OK', ds);
  r = psqlArchivo(REVERSA_ENLACE, ds);
  paso('la reversa de F4-a se niega con la séptima puesta', !r.ok && r.salida.includes('la séptima (20261005182227) sigue instalada'), r.ok ? 'se aplicó fuera de orden' : '');
  r = psqlArchivo(REVERSA_SIN_CICLO, ds);
  paso('reversa de la séptima', r.ok, r.ok ? '' : cola(r.salida));
  const k1 = huella(ds);
  const distintasK = k1.salida.trim().split(/\r?\n/).filter((l, i) => l !== lineasK0[i]);
  paso('la reversa de la séptima vuelve EXACTAMENTE a la huella de las seis', k1.ok && k1.salida === k0.salida,
    k1.ok ? distintasK.slice(0, 4).join('\n') : cola(k1.salida));
  oraculoEn('oráculo de F4-a tras la reversa de la séptima', ORACULO_ENLACE, 'ORACULO ENLACE EXACTO OK', ds);
  r = psqlArchivo(MIG_SIN_CICLO, ds);
  paso('la séptima se vuelve a aplicar tras su reversa', r.ok, r.ok ? '' : cola(r.salida));
  // Solo cuerpos y COMMENT, sin datos: su reversa no depende de que haya celulares dados de alta.
  psqlSql(`insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash) values ('C9', '${ACT.a1}', repeat('e', 64))`, ds);
  r = psqlArchivo(REVERSA_SIN_CICLO, ds);
  paso('la reversa de la séptima corre también con un celular dado de alta', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_SIN_CICLO, ds);
  paso('y la séptima se vuelve a aplicar con datos', r.ok, r.ok ? '' : cola(r.salida));
  psqlSql(`drop database ${ds}`, 'postgres');

  // ── Pasada 14: carreras de la séptima ──
  console.log('\n— Pasada 14: carreras de la séptima con dos sesiones reales —');
  psqlSql('create database conc_sin_ciclo template plantilla_seis', 'postgres');
  r = psqlArchivo(MIG_SIN_CICLO, 'conc_sin_ciclo');
  if (paso('banco de carreras listo (las seis + la séptima)', r.ok, r.ok ? '' : cola(r.salida))) {
    const ctxS = sembrarCorreccion('conc_sin_ciclo');
    for (const [clave, titulo] of CARRERAS_ENLACE_TITULOS) {
      const c = await CARRERAS_ENLACE[clave](ctxS);
      paso(`con la séptima: ${titulo}`, c.ok, c.detalle);
    }
    for (const [clave, titulo] of CARRERAS_SIN_CICLO_TITULOS) {
      const c = await CARRERAS_SIN_CICLO[clave](ctxS);
      paso(titulo, c.ok, c.detalle);
    }
  }
  // Control: con F4-a sola, la misma carrera reproduce el interbloqueo de la revisión (la prueba distingue).
  psqlSql('create database conc_sin_septima template plantilla_seis', 'postgres');
  {
    const c = await CARRERAS_SIN_CICLO.deshacerEntreCandados(sembrarCorreccion('conc_sin_septima'));
    paso('control: sin la séptima, la misma carrera reproduce el interbloqueo del #190', !c.ok && /deadlock/.test(c.detalle), c.detalle);
  }
  const originalS = readFileSync(MIG_SIN_CICLO, 'utf8').replace(/\r\n/g, '\n');
  for (const [i, mutante] of MUTANTES_SIN_CICLO.entries()) {
    const etiqueta = `mut_sin_ciclo ${String(i + 1).padStart(2, '0')}: ${mutante.nombre}`;
    const m = aplicarMutante(originalS, mutante);
    if (m.error) { paso(etiqueta, false, `mutante obsoleto: ${m.error}`); continue; }
    const archivo = join(temporal, `mut-sin-ciclo-${i + 1}.sql`);
    writeFileSync(archivo, m.texto);
    const dbm = `mut_sin_ciclo_${i + 1}`;
    psqlSql(`create database ${dbm} template plantilla_seis`, 'postgres');
    r = psqlArchivo(archivo, dbm);
    if (mutante.por === 'postflight') {
      paso(etiqueta, !r.ok && r.salida.includes(mutante.espera),
        r.ok ? 'SOBREVIVE: la migración mutada se aplicó' : `cazado por el postflight: ${lineaError(r.salida)}`);
    } else if (!r.ok) {
      paso(etiqueta, false, `la migración mutada no se aplica (mutante inválido): ${lineaError(r.salida)}`);
    } else {
      const c = await CARRERAS_SIN_CICLO[mutante.escenario](sembrarCorreccion(dbm));
      paso(etiqueta, !c.ok, c.ok ? 'SOBREVIVE: la carrera no lo nota' : `cazado por la carrera: ${c.detalle}`);
    }
    psqlSql(`drop database ${dbm}`, 'postgres');
  }

  // ── Pasada 15: la octava (lecturas de F4-b) sobre las siete ──
  console.log('\n— Pasada 15: la octava (lecturas de F4-b: «Qué pasó hoy» y la marca «Celular») —');
  const dl = 'lecturas';
  psqlSql(`create database ${dl} template plantilla_siete`, 'postgres');
  const m0 = huella(dl);
  const lineasM0 = m0.salida.trim().split(/\r?\n/);
  paso('huella del catálogo de las siete', m0.ok && lineasM0.length > 100, m0.ok ? `${lineasM0.length} líneas` : cola(m0.salida));
  r = psqlArchivo(MIG_LECTURAS, dl);
  paso('octava aplicada (dos puertas de lectura, su núcleo, permisos, postflight)', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_LECTURAS, dl);
  paso('la octava se niega a sobrescribirse', !r.ok && r.salida.includes('los objetos ya existen'), r.ok ? 'se aplicó dos veces' : '');
  oraculoEn('oráculo de la octava', ORACULO_LECTURAS, 'ORACULO LECTURAS ANALISTA OK', dl);
  oraculoEn('oráculo de F4-a con la octava puesta', ORACULO_ENLACE, 'ORACULO ENLACE EXACTO OK', dl);
  oraculoEn('oráculo de la quinta con la octava puesta', ORACULO_CORRECCION, 'ORACULO CORRECCION OK', dl);
  r = psqlArchivo(REVERSA_SIN_CICLO, dl);
  paso('la reversa de la séptima se niega con la octava puesta', !r.ok && r.salida.includes('la octava (20261005201010) sigue instalada'), r.ok ? 'se aplicó fuera de orden' : '');
  r = psqlArchivo(REVERSA_ENLACE, dl);
  paso('la reversa de F4-a se niega con la octava puesta', !r.ok && r.salida.includes('sigue instalada'), r.ok ? 'se aplicó fuera de orden' : '');
  r = psqlArchivo(REVERSA_LECTURAS, dl);
  paso('reversa de la octava', r.ok, r.ok ? '' : cola(r.salida));
  const m1 = huella(dl);
  const distintasM = m1.salida.trim().split(/\r?\n/).filter((l, i) => l !== lineasM0[i]);
  paso('la reversa de la octava vuelve EXACTAMENTE a la huella de las siete', m1.ok && m1.salida === m0.salida,
    m1.ok ? distintasM.slice(0, 4).join('\n') : cola(m1.salida));
  r = psqlArchivo(MIG_LECTURAS, dl);
  paso('la octava se vuelve a aplicar tras su reversa', r.ok, r.ok ? '' : cola(r.salida));
  oraculoEn('oráculo de la octava tras reaplicar', ORACULO_LECTURAS, 'ORACULO LECTURAS ANALISTA OK', dl);
  psqlSql(`drop database ${dl}`, 'postgres');
  pasadaMutantes('Pasada 15b: mutantes de la octava', MIG_LECTURAS, MUTANTES_LECTURAS, 'plantilla_siete', ORACULO_LECTURAS, 'mut_lecturas');

  // ── Pasada 16: la novena («Qué pasó hoy» paginada y por la hora de resolución) sobre las ocho ──
  console.log('\n— Pasada 16: la novena («Qué pasó hoy» paginada y por la hora en que se resolvió) —');
  const dp = 'paginadas';
  psqlSql(`create database ${dp}_sin_octava template plantilla_siete`, 'postgres');
  r = psqlArchivo(MIG_PAGINADAS, `${dp}_sin_octava`);
  paso('la novena se niega sin la octava', !r.ok && r.salida.includes('falta la octava'), r.ok ? 'se aplicó sin la octava' : '');
  psqlSql(`drop database ${dp}_sin_octava`, 'postgres');
  psqlSql(`create database ${dp} template plantilla_ocho`, 'postgres');
  const n0 = huella(dp);
  const lineasN0 = n0.salida.trim().split(/\r?\n/);
  paso('huella del catálogo de las ocho', n0.ok && lineasN0.length > 100, n0.ok ? `${lineasN0.length} líneas` : cola(n0.salida));
  r = psqlArchivo(MIG_PAGINADAS, dp);
  paso('novena aplicada (retira la lectura de la octava, dos índices, lectura paginada, permisos, postflight)', r.ok, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(MIG_PAGINADAS, dp);
  paso('la novena se niega a sobrescribirse', !r.ok && r.salida.includes('los objetos ya existen'), r.ok ? 'se aplicó dos veces' : '');
  oraculoEn('oráculo de la novena', ORACULO_PAGINADAS, 'ORACULO RESUELTAS PAGINADAS OK', dp);
  oraculoEn('oráculo de F4-a con la novena puesta', ORACULO_ENLACE, 'ORACULO ENLACE EXACTO OK', dp);
  oraculoEn('oráculo de la quinta con la novena puesta', ORACULO_CORRECCION, 'ORACULO CORRECCION OK', dp);
  r = psqlArchivo(REVERSA_LECTURAS, dp);
  paso('la reversa de la octava se niega con la novena puesta', !r.ok && r.salida.includes('la novena (20261005224330) sigue instalada'), r.ok ? 'se aplicó fuera de orden' : '');
  r = psqlArchivo(REVERSA_PAGINADAS, dp);
  paso('reversa de la novena', r.ok, r.ok ? '' : cola(r.salida));
  const n1 = huella(dp);
  const distintasN = n1.salida.trim().split(/\r?\n/).filter((l, i) => l !== lineasN0[i]);
  paso('la reversa de la novena vuelve EXACTAMENTE a la huella de las ocho', n1.ok && n1.salida === n0.salida,
    n1.ok ? distintasN.slice(0, 4).join('\n') : cola(n1.salida));
  oraculoEn('oráculo de la octava tras la reversa de la novena', ORACULO_LECTURAS, 'ORACULO LECTURAS ANALISTA OK', dp);
  r = psqlArchivo(MIG_PAGINADAS, dp);
  paso('la novena se vuelve a aplicar tras su reversa', r.ok, r.ok ? '' : cola(r.salida));
  oraculoEn('oráculo de la novena tras reaplicar', ORACULO_PAGINADAS, 'ORACULO RESUELTAS PAGINADAS OK', dp);

  psqlSql(`drop database ${dp}`, 'postgres');
  pasadaMutantes('Pasada 16b: mutantes de la novena', MIG_PAGINADAS, MUTANTES_PAGINADAS, 'plantilla_ocho', ORACULO_PAGINADAS, 'mut_paginadas');

  // ── Pasadas 17 y 18: la décima (id de origen en la bandeja) y la undécima (salud sin hora exacta) ──
  // Mismo recorrido para las dos: se niega sin la anterior, huella, se aplica, se niega a repetirse, su oráculo y los
  // de F4-a y la quinta, la reversa de la anterior se niega con ella puesta, su reversa vuelve a la huella exacta y se
  // vuelve a aplicar; después, sus mutantes.
  const pasadaEnmienda = (p) => {
    console.log(`\n— ${p.titulo} —`);
    psqlSql(`create database ${p.db}_sin_anterior template ${p.plantillaAnterior}`, 'postgres');
    r = psqlArchivo(p.mig, `${p.db}_sin_anterior`);
    paso(`${p.nombre} se niega sin ${p.anterior}`, !r.ok && r.salida.includes(p.faltaAnterior), r.ok ? 'se aplicó sin la anterior' : '');
    psqlSql(`drop database ${p.db}_sin_anterior`, 'postgres');
    psqlSql(`create database ${p.db} template ${p.plantilla}`, 'postgres');
    const h0 = huella(p.db);
    const lineas0 = h0.salida.trim().split(/\r?\n/);
    paso(`huella del catálogo de ${p.base}`, h0.ok && lineas0.length > 100, h0.ok ? `${lineas0.length} líneas` : cola(h0.salida));
    r = psqlArchivo(p.mig, p.db);
    paso(`${p.nombre} aplicada (${p.que}, postflight)`, r.ok, r.ok ? '' : cola(r.salida));
    r = psqlArchivo(p.mig, p.db);
    paso(`${p.nombre} se niega a sobrescribirse`, !r.ok && r.salida.includes('ya está aplicada'), r.ok ? 'se aplicó dos veces' : '');
    oraculoEn(`oráculo de ${p.nombre}`, p.oraculo, p.marca, p.db);
    oraculoEn(`oráculo de F4-a con ${p.nombre} puesta`, ORACULO_ENLACE, 'ORACULO ENLACE EXACTO OK', p.db);
    oraculoEn(`oráculo de la quinta con ${p.nombre} puesta`, ORACULO_CORRECCION, 'ORACULO CORRECCION OK', p.db);
    r = psqlArchivo(p.reversaAnterior, p.db);
    paso(`la reversa de ${p.anterior} se niega con ${p.nombre} puesta`, !r.ok && r.salida.includes(p.niegaAnterior), r.ok ? 'se aplicó fuera de orden' : '');
    r = psqlArchivo(p.reversa, p.db);
    paso(`reversa de ${p.nombre}`, r.ok, r.ok ? '' : cola(r.salida));
    const h1 = huella(p.db);
    const distintas = h1.salida.trim().split(/\r?\n/).filter((l, i) => l !== lineas0[i]);
    paso(`la reversa de ${p.nombre} vuelve EXACTAMENTE a la huella de ${p.base}`, h1.ok && h1.salida === h0.salida,
      h1.ok ? distintas.slice(0, 4).join('\n') : cola(h1.salida));
    r = psqlArchivo(p.mig, p.db);
    paso(`${p.nombre} se vuelve a aplicar tras su reversa`, r.ok, r.ok ? '' : cola(r.salida));
    oraculoEn(`oráculo de ${p.nombre} tras reaplicar`, p.oraculo, p.marca, p.db);
    psqlSql(`drop database ${p.db}`, 'postgres');
    pasadaMutantes(`${p.titulo.split(':')[0]}b: mutantes de ${p.nombre}`, p.mig, p.mutantes, p.plantilla, p.oraculo, `mut_${p.db}`);
  };
  pasadaEnmienda({
    titulo: 'Pasada 17: la décima (id de origen en la bandeja y el detalle)', nombre: 'la décima', db: 'origen',
    mig: MIG_ORIGEN, oraculo: ORACULO_ORIGEN, marca: 'ORACULO BANDEJA CON ORIGEN OK', reversa: REVERSA_ORIGEN,
    mutantes: MUTANTES_ORIGEN, plantilla: 'plantilla_nueve', base: 'las nueve', que: 'bandeja y detalle con evento_origen_id',
    anterior: 'la novena', plantillaAnterior: 'plantilla_ocho', faltaAnterior: 'falta la novena',
    reversaAnterior: REVERSA_PAGINADAS, niegaAnterior: 'la décima (20261006150154) sigue instalada',
  });
  pasadaEnmienda({
    titulo: 'Pasada 18: la undécima (salud de los celulares sin la hora exacta del latido)', nombre: 'la undécima', db: 'salud',
    mig: MIG_SALUD, oraculo: ORACULO_SALUD, marca: 'ORACULO SALUD SIN HORA OK', reversa: REVERSA_SALUD,
    mutantes: MUTANTES_SALUD, plantilla: 'plantilla_diez', base: 'las diez', que: 'estado del latido sin horas exactas',
    anterior: 'la décima', plantillaAnterior: 'plantilla_nueve', faltaAnterior: 'falta la décima',
    reversaAnterior: REVERSA_ORIGEN, niegaAnterior: 'la undécima (20261006150254) sigue instalada',
  });
  // Duodécima: regresiones del informe #190, reversa exacta y carrera de reasignación.
  const cierre = join(RAIZ, 'supabase/migrations/20261006162813_crm_llamadas_celular_cierre_revision.sql');
  const ocierre = join(RAIZ, 'supabase/tests/llamadas-celular/oraculo-cierre-revision.sql');
  const rcierre = join(RAIZ, 'supabase/scripts/llamadas-celular/reversa-cierre-revision.sql');
  psqlSql('create database plantilla_once template plantilla_diez', 'postgres');
  r = psqlArchivo(MIG_SALUD, 'plantilla_once');
  paso('plantilla de las once para el cierre', r.ok, r.ok ? '' : cola(r.salida));
  const dc = 'cierre';
  psqlSql(`create database ${dc} template plantilla_once`, 'postgres');
  const h11 = huella(dc);
  r = psqlArchivo(cierre, dc);
  paso('duodécima aplicada', r.ok, r.ok ? '' : cola(r.salida));
  oraculoEn('regresiones de candidatos, visibilidad, reserva e ids', ocierre, 'ORACULO CIERRE REVISION OK', dc);
  oraculoEn('enlace exacto y cumplimiento diferido con la duodécima', ORACULO_ENLACE, 'ORACULO ENLACE EXACTO OK', dc);
  oraculoEn('quinta con la duodécima', ORACULO_CORRECCION, 'ORACULO CORRECCION OK', dc);
  oraculoEn('resueltas paginadas con la duodécima', ORACULO_PAGINADAS, 'ORACULO RESUELTAS PAGINADAS OK', dc);
  r = psqlArchivo(REVERSA_SALUD, dc);
  paso('undécima no revierte con la duodécima', !r.ok && r.salida.includes('primero la duodécima'));
  r = psqlArchivo(rcierre, dc);
  paso('reversa de la duodécima restaura la huella de las once', r.ok && huella(dc).salida === h11.salida, r.ok ? '' : cola(r.salida));
  r = psqlArchivo(cierre, dc);
  paso('reaplicar duodécima tras reversa', r.ok, r.ok ? '' : cola(r.salida));
  const cc = sembrarCorreccion(dc);
  const origenCarrera = cc.nuevoId('C1');
  const [reasignada, recibida] = await Promise.all([
    psqlParalelo(retenerTx(reasignarSql(ACT.c1, ACT.a3)), dc),
    pausa(400).then(() => psqlParalelo(enTx(SERVICIO + ingerirSql(cc.k.C1, origenCarrera, '900000001')), dc)),
  ]);
  const guardadas = psqlSql(`select count(*) from crm.llamadas_celular_eventos where evento_origen_id='${origenCarrera}'`, dc);
  paso('reasignación en vuelo: espera y no guarda con candidatura obsoleta',
    reasignada.ok && recibida.ok && esperoYo(recibida) && guardadas.salida.trim() === '0',
    `${recibida.ms} ms; guardadas=${guardadas.salida.trim()}`);
  r = psqlArchivo(rcierre, dc);
  paso('reversa de la duodécima se niega tras altas/uso', !r.ok && r.salida.includes('ya hubo altas o uso'));
  psqlSql(`drop database ${dc}`, 'postgres');
  pasadaMutantes('Duodécima: defensas de la revisión', cierre, [
    { nombre: 'candidatos omite veto', buscar: 'if not private.llamada_celular_contacto_admitido(p_dueno, p_formas) then', poner: 'if false then' },
    { nombre: 'antiguo dueño vuelve a ver llamada ajena', buscar: "and (l.etapa <> 'descartado' or l.vendedor_id = p_analista or p_actor = p_analista)", poner: 'and true' },
    { nombre: 'enlazar no limpia la intención anterior', buscar: '  delete from private.llamadas_celular_intenciones where actividad_id = new.actividad_id;', poner: '' },
    { nombre: 'veto cae en sin identificar', buscar: 'if v_admitido is distinct from true then return v_aceptado; end if;', poner: '' },
    { nombre: 'supervisor pierde llamada propia descartada', buscar: ' or p_actor = p_analista)', poner: ')' },
  ], 'plantilla_once', ocierre, 'mut_cierre');
} catch (error) {
  paso('arranque del banco', false, error.message);
} finally {
  if (arrancado) correr('pg_ctl', ['-D', datos, '-m', 'fast', '-w', 'stop'], { sinTuberias: true });
  try { rmSync(temporal, { recursive: true, force: true }); } catch { /* carpeta temporal */ }
}

const fallos = pasos.filter((p) => !p.ok).length;
console.log(fallos ? `\n${fallos} de ${pasos.length} pasos FALLARON` : `\nTODO EN VERDE: ${pasos.length} pasos`);
process.exit(fallos ? 1 : 0);
