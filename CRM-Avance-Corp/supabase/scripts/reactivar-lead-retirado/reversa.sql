-- REVERSA de 20261022170200_crm_alta_reactiva_lead_retirado.sql («Registrar a una persona con lead retirado reactiva su ficha»,
-- ronda 2).
--
-- FALLA CERRADA. Antes de revertir exige que `crm.crear_lead_si_disponible(…16 parámetros…)` tenga EXACTAMENTE la definición
-- que dejó la migración: `md5(prosrc)` = `01ebf089b8428a02c6df387a9b4e899e` Y `md5(pg_get_functiondef)` =
-- `94ec2bd71eca8ab1663e75841723b6a5`, y que existan el núcleo `private.alta_reactivar_retirado` y su pieza
-- `private.alta_reactivar_bloqueo_conservado`. Se niega si la migración no está aplicada, si alguien cambió el CUERPO después,
-- o si alguien cambió un ATRIBUTO después sin tocar el cuerpo (p. ej. `ALTER FUNCTION … SET statement_timeout`, INVOKER o algo
-- que entre en la definición): en todos esos casos NO se revierte nada y se revisa a mano (o se corrige hacia delante con otra
-- migración). No se promete tolerancia a derivas. (Ensayado: `armar-ensayo.mjs --reversa-con-set` aplica, añade un
-- `SET statement_timeout` e intenta esta reversa: aborta en el preflight y la foto queda idéntica, SET incluido.)
--
-- QUÉ RESTAURA: el cuerpo anterior, quitando del cuerpo vivo los DOS bloques que la migración insertó (la variable
-- `v_reactivacion` en las declaraciones y la rama entre el verificador y la salida por veredicto; cada uno tiene que aparecer
-- EXACTAMENTE una vez o la reversa aborta); lo que queda es, byte a byte, el cuerpo vigente antes de la migración:
-- `md5(prosrc)` vuelve a `54fc34f7357d4d5688f210df6c521045` y `md5(pg_get_functiondef)` a `d1daa1c65f18b4b41a6c9ffa99372bcf`
-- (los de `fase-2/bloque-2.4/revision/cuerpos-antes.txt` y del preflight de 20260930193325). Repone el comentario anterior y
-- BORRA el núcleo y su pieza. El postflight exige esas huellas originales y la ausencia de las dos funciones.
--
-- QUÉ CONSERVA: firma, dueño, `security definer`, `search_path` vacío, `lock_timeout` y ACL del alta (`create or replace` no
-- los toca; con el preflight de arriba, los que encuentra son los que dejó la migración, que a su vez exigió que fueran los
-- auditados).
--
-- NO DESHACE DATOS: las fichas ya reactivadas siguen activas, con su dueño nuevo, su episodio y su actividad de rastro
-- (`reactivacion_alta`). Tras revertir, el alta vuelve a crear un SEGUNDO lead sobre un retirado: es el defecto que la
-- migración cerraba. Se aplica por el mismo ciclo que la migración.
-- RESELLE C2 (22/10/2026): huellas re-asentadas contra producción del 22/10 (sin generador: editada SOLO en huellas y comentario): exige 30109c53…/e06eca23… (antes 01ebf089…/94ec2bd7…) y vuelve a 145b30a3…/068d4d88… (antes 54fc34f7…/d1daa1c6…) con el comentario vivo (frase F3 incluida).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $preflight$
declare
  v_alta regprocedure := to_regprocedure('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)');
begin
  if v_alta is null then
    raise exception 'REVERSA alta_reactiva_lead_retirado: falta crm.crear_lead_si_disponible (16 parámetros); nada que revertir';
  end if;
  if to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)') is null
     or to_regprocedure('private.alta_reactivar_bloqueo_conservado(uuid)') is null then
    raise exception 'REVERSA alta_reactiva_lead_retirado: falta el núcleo private.alta_reactivar_retirado o su pieza alta_reactivar_bloqueo_conservado (la migración no está aplicada o alguien los borró); revisar antes de revertir';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_alta) is distinct from '30109c536ef0a73a85da1eb3465b8ed2' then
    raise exception 'REVERSA alta_reactiva_lead_retirado: el cuerpo de crm.crear_lead_si_disponible no es el que dejó la migración (no está aplicada o cambió después); revisar antes de revertir';
  end if;
  if md5(pg_get_functiondef(v_alta)) is distinct from 'e06eca2333bb11869d00913a004c8261' then
    raise exception 'REVERSA alta_reactiva_lead_retirado: crm.crear_lead_si_disponible no tiene exactamente la definición que dejó la migración (un atributo cambió después sin tocar el cuerpo, p. ej. un SET statement_timeout): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
end
$preflight$;

do $reemplazo$
declare
  v_firma regprocedure := 'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure;
  v_def   text;
  v_ancla text;
  v_orig  text;
  v_veces integer;
begin
  v_def := pg_get_functiondef(v_firma);

  -- Bloque 1: la variable de la rama, tal como la devuelve pg_get_functiondef.
  v_ancla := $r1$  v_hoy_lima date := (pg_catalog.clock_timestamp() at time zone 'America/Lima')::date;
  v_reactivacion jsonb;
begin
$r1$;
  v_orig := $o1$  v_hoy_lima date := (pg_catalog.clock_timestamp() at time zone 'America/Lima')::date;
begin
$o1$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA alta_reactiva_lead_retirado: el bloque de las declaraciones aparece % veces en crm.crear_lead_si_disponible (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  -- Bloque 2: la rama entre el verificador y la salida por veredicto no «libre».
  v_ancla := $r2$  v_disponibilidad := private.verificar_disponibilidad_lead_impl(v_telefono, v_dni);

  -- REACTIVAR UNA FICHA RETIRADA (plan AVANCE-BACKEND-0710-P1, bloque 2.4; D-11/Q1, D-15, D-17, D-21). Si la persona ya
  -- tuvo un lead y fue retirado (activo=false, no convertido, sin veto) y ningun lead ACTIVO, veto ni identidad coincide
  -- con lo tecleado NI con lo que esa ficha conserva, el alta reactiva ESA ficha a nombre del destino calculado arriba en
  -- vez de crear un segundo lead; tambien con el veredicto «enfriamiento» cuando su unico causante es un retirado (D-15).
  -- Un retirado ENLAZADO a persona bloquea («ya es cliente») aunque solo se teclee el telefono (D-21). El nucleo decide
  -- bajo los candados ya tomados, devuelve nulo cuando no actua (el alta sigue como siempre), bloquea (nunca «libre») si
  -- un dato CONSERVADO de la ficha choca con un lead activo, y repite la misma respuesta ante un reintento con el mismo
  -- p_id (la actividad de rastro lleva ese id; su huella lleva el telefono y el tipo de documento, no el DNI).
  v_reactivacion := private.alta_reactivar_retirado(
    v_id, v_actor, v_telefono, v_dni, v_vendedor, v_supervisor, v_disponibilidad,
    pg_catalog.jsonb_build_object(
      'telefono', v_telefono, 'nombre_completo', v_nombre, 'telefono_alternativo', v_alt, 'correo', v_correo,
      'distrito', v_distrito, 'origen', p_origen, 'etapa', p_etapa, 'monto_estimado', p_monto_estimado,
      'moneda', p_moneda, 'categoria_interes', v_categoria, 'vendedor_id', v_vendedor, 'nota', v_nota));
  if v_reactivacion is not null then
    return v_reactivacion;
  end if;

  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
$r2$;
  v_orig := $o2$  v_disponibilidad := private.verificar_disponibilidad_lead_impl(v_telefono, v_dni);

  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
$o2$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'REVERSA alta_reactiva_lead_retirado: el bloque de la rama aparece % veces en crm.crear_lead_si_disponible (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_orig);

  execute v_def;
end
$reemplazo$;

comment on function crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text) is
'Alta manual atomica con disponibilidad e idempotencia. Canales activos: referido, landing, formulario y oficina. Otro e historicos no admitidos en nuevas altas. Referido conserva restriccion de vendedor a su propio nombre. LANDING/FORMULARIO manuales conservan su politica del divisor. F3 (15/10/2026): origen formulario_3 separado; comparte turno y reglas de conversión de Formulario. Contrato compatible con lecturas legadas.';

drop function private.alta_reactivar_retirado(uuid, uuid, text, text, uuid, uuid, jsonb, jsonb);
drop function private.alta_reactivar_bloqueo_conservado(uuid);

do $postflight$
declare
  v_alta regprocedure := 'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'::regprocedure;
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_alta) is distinct from '145b30a30e69807a1838c1b960a0675d'
     or md5(pg_get_functiondef(v_alta)) is distinct from '068d4d88078faea102947a5616337811' then
    raise exception 'REVERSA alta_reactiva_lead_retirado: crm.crear_lead_si_disponible no quedó como estaba antes de la migración';
  end if;
  if (select position('alta_reactivar_retirado' in p.prosrc) from pg_proc p where p.oid = v_alta) <> 0 then
    raise exception 'REVERSA alta_reactiva_lead_retirado: la rama sigue en crm.crear_lead_si_disponible';
  end if;
  if to_regprocedure('private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)') is not null
     or to_regprocedure('private.alta_reactivar_bloqueo_conservado(uuid)') is not null then
    raise exception 'REVERSA alta_reactiva_lead_retirado: el núcleo o su pieza siguen existiendo';
  end if;
end
$postflight$;

commit;
