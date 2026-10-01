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
// Seis pasadas:
//   1. Las migraciones tal cual: se aplican, se niegan a sobrescribirse, pasan sus oráculos, sus
//      reversas funcionan en orden (y se niegan fuera de orden o con filas) y se vuelven a aplicar.
//   2–5. Mutantes de F2-b, F2-c, F3-a y la corrección de elegibilidad: por cada defensa, una copia de
//      la migración que la neutraliza. Un mutante «de oráculo» tiene que APLICARSE y hacer fallar su
//      oráculo; uno «de postflight» tiene que ser rechazado por el postflight con su mensaje. Si
//      sobrevive, esa defensa no está probada.
//   6. Concurrencia con dos sesiones REALES: la primera abre su transacción y la retiene; la
//      segunda llega mientras tanto, tiene que ESPERAR (se mide) y responder bien al soltarse.
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
} catch (error) {
  paso('arranque del banco', false, error.message);
} finally {
  if (arrancado) correr('pg_ctl', ['-D', datos, '-m', 'fast', '-w', 'stop'], { sinTuberias: true });
  try { rmSync(temporal, { recursive: true, force: true }); } catch { /* carpeta temporal */ }
}

const fallos = pasos.filter((p) => !p.ok).length;
console.log(fallos ? `\n${fallos} de ${pasos.length} pasos FALLARON` : `\nTODO EN VERDE: ${pasos.length} pasos`);
process.exit(fallos ? 1 : 0);
