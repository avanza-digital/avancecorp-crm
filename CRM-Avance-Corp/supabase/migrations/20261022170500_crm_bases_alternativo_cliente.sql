-- 20261022170500_crm_bases_alternativo_cliente.sql — bloque 2.9 del plan «Mantenibilidad y consistencia del backend CRM» (fecha de trabajo 20261009235000_crm_bases_alternativo_cliente.sql; integrado el 2026/10/22, C2 del grupo C)
-- La CARGA DE BASES también mira el TELÉFONO ALTERNATIVO de los CLIENTES (plan AVANCE-BACKEND-0810-F2, fase 2, bloque 2.9; decisión
-- D-37 de Miguel, 09/10/2026: «la carga compara también con el teléfono alternativo de los clientes (misma regla que el 2.8)»;
-- alcance, 09/10 ~12:00, opción «Solo si es cliente»: SOLO el alternativo de los leads CONVERTIDOS). La regla del cliente convertido
-- es la del 2.7 (D-22, D-25, D-27) y la del 2.8 (D-30). Va sobre la carga de bases B8 (20261004184501) y, en el orden de
-- integración, después del 2.8 (20261009150000), con el grupo C: no usa la pieza del 2.8, pero su preflight exige el candado de
-- contacto del 2.8 r4 (abajo). RONDA 2 (09/10/2026; auditor de permisos r1 —PASS con cuatro P3— y Codex r1 —sin defectos del
-- predicado—, `fase-2/bloque-2.9/revision/CONCILIACION.md`; el predicado NO cambia): el comentario del cuerpo ya no nombra la pieza
-- del 2.8 (su reversa la buscaba en los cuerpos y se habría negado con el 2.9 aplicado); el preflight y el postflight fijan además el
-- verificador de 3 argumentos, la cadena del ámbito (`vendedor_ids_visibles`, `es_lector_global`, `rol_crm`) y el candado de contacto
-- del 2.8 r4, y buscan consumidores del envoltorio, de la regla del ámbito y del núcleo; la reversa también.
--
-- QUÉ PASA HOY. El núcleo de la carga (`private.bases_carga_cargar_lote_core`, detrás de la puerta `crm.cargar_base_lote`) da a cada
-- fila el veredicto del verificador de la casa y, si dice «libre», pregunta a su envoltorio de identidad
-- `private.bases_carga_contacto_existente(p_telefono, p_dni)` si existe CUALQUIER lead con ese teléfono o DNI; el envoltorio compara
-- solo `crm.leads.telefono` y `crm.leads.dni`. El verificador no mira el alternativo y excluye las fichas convertidas ⇒ una fila cuyo
-- teléfono es el ALTERNATIVO de un cliente ya convertido entra como contacto dormido (`cargada`), que después podría darse a un
-- analista. Con su teléfono PRINCIPAL ya sale `ya_existia` (motivo `convertido`; `retirado` si la ficha del cliente está retirada).
-- Medido en ROJO: `supabase/scripts/bases-alternativo-cliente/` (18 de 38 comprobaciones en la ronda 2; 14 de 31 en la 1).
--
-- QUÉ HACE. El envoltorio, por ANCLA ÚNICA (un solo sitio: su WHERE), compara además el teléfono de la fila con el
-- `telefono_alternativo` de los leads en etapa `convertido` (activos o retirados). Ese lead entra en el MISMO conjunto que los demás,
-- con la misma categoría (`convertido`; `retirado` si la ficha está retirada —D-E1, aceptada por el Director—), el mismo orden de
-- relevancia y la misma regla del ámbito. Por eso, cuando el alternativo es la ÚNICA coincidencia, la fila sale exactamente como con su
-- teléfono principal (mismo motivo y mismo id, si quien carga lo ve y sigue activo). Cuando hay VARIAS coincidencias: (a) GANA la más
-- relevante (vivo → descartado → convertido → retirado; a igual categoría, la creada más recientemente; después el id), así que el
-- motivo o el id pueden cambiar respecto de hoy (casos R1 y E1); (b) la regla del ámbito (`private.bases_carga_fuera_de_ambito`, que usa
-- este mismo envoltorio) mira TODAS: si alguna es de otro equipo, la fila solo dice `ya_existia`, sin motivo ni id —también si otra
-- coincidencia es un lead propio vivo o en No contactar, que hoy daría `con_dueno` o `no_contactar` (caso F3/F3b: decisión del
-- Director; cuenta en `ya_existian` del lote y del acumulado de la base, no en `no_contactar`)—. Comparación literal de formas
-- canónicas, como la regla del 2.8 (D-30): el alternativo se guarda en E.164 (CHECK `leads_telefono_alternativo_formato`) y el
-- teléfono de la fila llega normalizado (`private.normalizar_telefono` y la forma `^\+519[0-9]{8}$` que exige el núcleo); un
-- alternativo internacional nunca casa con una fila (la fila solo admite un móvil peruano), tampoco el de 9 dígitos (`+9…`, otro
-- número que el móvil `+51 9…`). Al comentario del envoltorio se le AÑADE una frase del 2.9 (la reversa la quita).
--
-- NO CAMBIA: el alternativo de un lead que NO es cliente (D-37: la carga sigue sin mirarlo); las filas libres; la fila cuyo teléfono
-- o DNI coincide con un lead y NO con el alternativo de un cliente (mismo veredicto, motivo e id); los veredictos del verificador
-- (van antes y mandan) salvo el ocultamiento por ámbito de arriba; el respaldo fila a fila del INSERT; la forma de la respuesta (ids y
-- motivos, sin nombres ni teléfonos); lo que no es carga de bases (el preflight exige que solo la carga use el envoltorio, el ámbito y
-- el núcleo); el núcleo, la puerta, el verificador, el ámbito, el importador, el alta y la edición; tablas, grants, policies ni nada de
-- `public`. Los contactos ya cargados no se tocan (fuera del plan); devolverlos a la cartera lo cubren D-55 (reactivar, bloque 2.11)
-- y D-62 (las demás puertas, bloque 2.16). Candados: sin DDL de tablas; la transacción retiene `AccessShareLock` sobre `crm.leads`
-- (medido en el laboratorio: ~1,9 s hasta el final, sobre todo los dos barridos de trinquetes; una medición, no una cota), compatible
-- con el DML ordinario y en conflicto solo con ACCESS EXCLUSIVE.
--
-- CONCURRENCIA. El núcleo toma, antes de juzgar, los candados de contacto de sus filas (`private.bloquear_contactos_lead`, clave
-- `telefono:` + forma normalizada); desde el 2.8 r4 el disparador de disponibilidad toma la MISMA clave para el alternativo viejo y
-- nuevo (toda UPDATE que lo dispara, también la conversión) y para el alternativo de un INSERT. Así una carga de X y quien pone X como
-- alternativo de un cliente (o convierte un lead que lo tiene) no se juzgan a la vez sobre fotos viejas: el resultado es uno de los
-- dos órdenes. No impide el orden «carga primero» (el contacto entra cuando X aún no era de un cliente: dentro de lo que D-37 promete;
-- después lo cubren D-55 y D-62). El preflight exige esas piezas del 2.8 r4; la carrera con COMMIT en los dos órdenes es de la branch.
--
-- PREFLIGHT (falla cerrada; si algo no coincide no se instala nada): que no esté ya aplicada; el envoltorio de B8 EXACTO (cuerpo
-- cf6489ee72122a33fd9c1da9b5e9446c, definición 563274f8186a7b8a186ec27322d69eb0; `20261004184501:464-491` y su postflight `:1450`),
-- su ficha (dueño postgres, INVOKER, STABLE, `search_path` vacío y nada más, EXECUTE solo para postgres sin opción de concesión) y su
-- comentario (1e1052db90104b21bef5b9a1c6267f38); la DEFINICIÓN COMPLETA, el dueño y la ACL EFECTIVA de doce funciones: sus dos
-- llamadores (`private.bases_carga_cargar_lote_core`, `private.bases_carga_fuera_de_ambito`), la puerta (`crm.cargar_base_lote`), el
-- verificador de 2 argumentos y el de 3 al que delega (`private.verificar_disponibilidad_lead_impl`), `private.normalizar_telefono`,
-- la cadena del ámbito y del id (`private.base_gestion_lead_visible`, `private.vendedor_ids_visibles`, `private.es_lector_global`,
-- `private.rol_crm` —también el rol de quien carga—, `private.bases_carga_lead_ref`) y la función del candado
-- (`private.bloquear_contactos_lead`); el candado del 2.8 r4 (el disparador `private.trg_leads_disponibilidad_atomica` de postgres y
-- DEFINER lo toma con el alternativo en sus dos ramas, una vez cada una, y sus dos disparadores de tabla están habilitados, el de la
-- edición con el alternativo en su lista); que NADIE MÁS consuma el envoltorio (salvo el núcleo y el ámbito), el ámbito (salvo el
-- núcleo) ni el núcleo (salvo la puerta): referencias LITERALES en los cuerpos de función (sin distinguir mayúsculas), dependencias
-- registradas en `pg_depend` (vistas, policies, defaults, funciones `BEGIN ATOMIC`…) y los comandos de `cron.job` que ve quien migra
-- —es una búsqueda conservadora (un comentario con el nombre también bloquea) y NO ve el SQL dinámico (un nombre armado en tiempo de
-- ejecución): no prueba ausencia; inventario revisado en el laboratorio: envoltorio ← núcleo, ámbito; ámbito ← núcleo; núcleo ←
-- puerta—; el CHECK `leads_telefono_alternativo_formato`, validado y exacto (la premisa de la comparación literal); y el inventario y
-- las definiciones de los 30 `private.assert_*()` que se barren (sin los `*_mutantes`). Lo que esas funciones llaman a su vez (p. ej.
-- lo que usa el verificador) no se fija aquí. Fotografía la ficha del envoltorio y el estado de esos trinquetes (se exige que NO
-- cambien, no que pasen).
-- POSTFLIGHT: el envoltorio con su cuerpo y su definición EXACTOS (la comparación nueva, una sola vez), la misma ficha que antes y su
-- comentario EXACTO; las doce funciones, el candado del 2.8 r4, los consumidores y el CHECK intactos; la foto de los trinquetes
-- EXACTAMENTE igual que antes.
--
-- CÓMO SE REVIERTE: `supabase/scripts/bases-alternativo-cliente/reversa.sql` (falla cerrada: exige EXACTAMENTE lo que deja esta
-- migración —cuerpo, definición, ficha, ACL y comentario del envoltorio, las doce funciones intactas— y que nadie más consuma el
-- envoltorio, el ámbito ni el núcleo: si alguien los usara, volver a B8 le quitaría el alternativo en silencio; repone el cuerpo de
-- B8 por la misma ancla, al revés, y su comentario; postflight con las huellas de B8). No deshace datos: la regla no escribe (solo deja
-- de cargar contactos). Tras revertir, una fila con el alternativo de un cliente vuelve a cargarse como contacto dormido. Mismo ciclo
-- que la migración. Orden de reversas: la del 2.8 entra con el 2.9 aplicado (ensayado: compatibilidad mecánica, no concurrencia); se
-- recomienda igual el orden inverso al de aplicación (LIFO). Ensayo: `supabase/scripts/bases-alternativo-cliente/` (ROJO/VERDE,
-- mutantes, derivas, reversa, reversa con un cambio posterior, reversa del 2.8 encima, trinquetes, rendimiento y los oráculos del 2.4,
-- del 2.7 y del 2.8 encima).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $preflight$
declare
  v_env regprocedure := to_regprocedure('private.bases_carga_contacto_existente(text,text)');
  v_nucleo regprocedure := to_regprocedure('private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)');
  v_ambito regprocedure := to_regprocedure('private.bases_carga_fuera_de_ambito(uuid,text,text,text)');
  v_puerta regprocedure := to_regprocedure('crm.cargar_base_lote(uuid,uuid,jsonb)');
  v_disp regprocedure := to_regprocedure('private.trg_leads_disponibilidad_atomica()');
  v_mal text;
  v_cron text;
  r record;
  v text;
  v_foto text := '';
begin
  if v_env is null or v_nucleo is null or v_ambito is null or v_puerta is null or v_disp is null then
    raise exception 'PREFLIGHT bases_alternativo_cliente: falta el envoltorio, el núcleo, la regla del ámbito o la puerta de la carga de bases (B8, 20261004184501), o el disparador de disponibilidad';
  end if;
  -- Ya aplicada: el envoltorio ya mira el alternativo.
  if position('telefono_alternativo' in (select p.prosrc from pg_proc p where p.oid = v_env)) > 0 then
    raise exception 'PREFLIGHT bases_alternativo_cliente: el envoltorio ya mira el teléfono alternativo: esta migración ya está aplicada';
  end if;
  -- El envoltorio de B8, exacto: cuerpo y definición (la definición incluye INVOKER/DEFINER, volatilidad y SET).
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_env) is distinct from 'cf6489ee72122a33fd9c1da9b5e9446c'
     or md5(pg_get_functiondef(v_env)) is distinct from '563274f8186a7b8a186ec27322d69eb0' then
    raise exception 'PREFLIGHT bases_alternativo_cliente: el envoltorio private.bases_carga_contacto_existente no es el de B8 (20261004184501) (md5 del cuerpo %, de la definición %; se esperaban cf6489ee72122a33fd9c1da9b5e9446c y 563274f8186a7b8a186ec27322d69eb0): revisar el cuerpo vivo antes de parchear',
      (select md5(p.prosrc) from pg_proc p where p.oid = v_env), md5(pg_get_functiondef(v_env));
  end if;
  -- Su ficha: dueño postgres, INVOKER, STABLE, search_path vacío y nada más; EXECUTE solo para postgres, sin opción de concesión.
  if not exists (select 1 from pg_proc p where p.oid = v_env and p.proowner = 'postgres'::regrole::oid and not p.prosecdef
                   and p.provolatile = 's' and p.proconfig = array['search_path=""'])
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_env)
        is distinct from 'postgres:EXECUTE:false'
     or has_function_privilege('anon', v_env, 'EXECUTE') or has_function_privilege('authenticated', v_env, 'EXECUTE')
     or has_function_privilege('service_role', v_env, 'EXECUTE') then
    raise exception 'PREFLIGHT bases_alternativo_cliente: la ficha del envoltorio no es la auditada (dueño postgres, security invoker, stable, search_path vacío, EXECUTE solo para postgres sin opción de concesión)';
  end if;
  if md5(coalesce(obj_description(v_env, 'pg_proc'), '')) is distinct from '1e1052db90104b21bef5b9a1c6267f38' then
    raise exception 'PREFLIGHT bases_alternativo_cliente: el comentario del envoltorio no es el de B8; revisar antes de añadirle nada (la reversa lo repone)';
  end if;
  -- Sus dos llamadores, la puerta y lo que decide su efecto (el verificador efectivo, la normalización, la cadena del ámbito y del id, la
  -- función del candado): DEFINICIÓN COMPLETA (cuerpo y atributos), dueño y ACL EFECTIVA (los valores por defecto expandidos, con la
  -- opción de concesión). Si alguna cambió, lo ensayado no valdría.
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.cargar_base_lote(uuid,uuid,jsonb)', 'b03d2e9d4500ca54fb8aec014786653a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.base_gestion_lead_visible(uuid,text,uuid,uuid)', 'e80a43724b64f0ed5ac67b846292fb6c', 'postgres:EXECUTE:false'),
    ('private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)', 'e5f25344437c0c54b289d4ae294b5e39', 'postgres:EXECUTE:false'),
    ('private.bases_carga_fuera_de_ambito(uuid,text,text,text)', '7341099506af3a2f2af3eeb9ec0862e4', 'postgres:EXECUTE:false'),
    ('private.bases_carga_lead_ref(uuid,text,uuid)', 'db760dd5ae42b06a886b9420fa927be8', 'postgres:EXECUTE:false'),
    ('private.bloquear_contactos_lead(text[],text[])', '0d52f58c2065c1c0dc37a7587eda5882', 'postgres:EXECUTE:false'),
    ('private.es_lector_global()', 'c8be602f84348a0125617995802db618', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.normalizar_telefono(text)', '00c30277b752de13be3ee0599485e6a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.vendedor_ids_visibles(uuid)', '85544c70a0920f3a7a1b5da06935f236', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text)', '742d44fff6a8a742292c8de702812e60', 'postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text,uuid)', 'cece9dd168c9beea935af2e05895e32a', 'postgres:EXECUTE:false')) e(firma, definicion, acl)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null
     or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion
     or p.proowner is distinct from 'postgres'::regrole::oid
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) is distinct from e.acl;
  if v_mal is not null then
    raise exception 'PREFLIGHT bases_alternativo_cliente: cambió un llamador del envoltorio, la puerta o una pieza que decide su efecto (%: definición, dueño o permisos); lo ensayado no valdría', v_mal;
  end if;
  -- El candado de contacto del 2.8 r4 (Codex P2-1, auditor P3-2): el disparador de disponibilidad (de postgres, DEFINER) lo toma con el
  -- alternativo viejo y nuevo en la UPDATE y con el alternativo en el INSERT (cada llamada exactamente una vez), y sus dos disparadores
  -- de tabla lo ejecutan habilitados (el de la edición con el teléfono, el alternativo, el DNI, la etapa y `activo` en su lista). Es la
  -- clave que ordena una carga frente a quien pone ese número como alternativo de un cliente o convierte un lead que lo tiene.
  if not exists (select 1 from pg_proc p
                  where p.oid = v_disp and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and (length(p.prosrc) - length(replace(p.prosrc, $candado_u$    perform private.bloquear_contactos_lead(
      array[old.telefono, new.telefono, old.telefono_alternativo, new.telefono_alternativo],
      array[old.dni, new.dni]
    );
$candado_u$, ''))) / length($candado_u$    perform private.bloquear_contactos_lead(
      array[old.telefono, new.telefono, old.telefono_alternativo, new.telefono_alternativo],
      array[old.dni, new.dni]
    );
$candado_u$) = 1
                    and (length(p.prosrc) - length(replace(p.prosrc, $candado_i$  perform private.bloquear_contactos_lead(array[new.telefono, new.telefono_alternativo], array[new.dni]);
$candado_i$, ''))) / length($candado_i$  perform private.bloquear_contactos_lead(array[new.telefono, new.telefono_alternativo], array[new.dni]);
$candado_i$) = 1)
     or not exists (select 1 from pg_trigger t
                     where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert'
                       and t.tgfoid = v_disp and t.tgenabled = 'O' and t.tgtype = 7)
     or not exists (select 1 from pg_trigger t
                     where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update'
                       and t.tgfoid = v_disp and t.tgenabled = 'O' and t.tgtype = 19
                       and (select array_agg(a.attname::text) from pg_attribute a
                             where a.attrelid = t.tgrelid and a.attnum = any (t.tgattr::int2[]))
                           @> array['activo', 'dni', 'etapa', 'telefono', 'telefono_alternativo']) then
    raise exception 'PREFLIGHT bases_alternativo_cliente: falta el candado de contacto del 2.8 r4 (el disparador de disponibilidad sin el alternativo en su candado, o un disparador de tabla deshabilitado o sin el alternativo): esta migración va después del 2.8 r4';
  end if;
  -- Nadie más consume el envoltorio (salvo el núcleo y el ámbito), la regla del ámbito (salvo el núcleo) ni el núcleo (salvo la puerta):
  -- referencias LITERALES en los cuerpos (sin distinguir mayúsculas: un identificador sin comillas en mayúsculas es el mismo), objetos
  -- registrados en pg_depend y comandos de cron.job (los que ve quien migra). CONSERVADORA: un comentario o una cadena con el nombre
  -- también bloquea. No ve el SQL dinámico (un nombre armado en tiempo de ejecución).
  select string_agg(x.quien, ', ' order by x.quien) into v_mal
  from (select p.oid::regprocedure::text || ' → ' || o.nombre as quien
          from (values ('bases_carga_contacto_existente', array[v_env::oid, v_nucleo::oid, v_ambito::oid]),
                       ('bases_carga_fuera_de_ambito', array[v_ambito::oid, v_nucleo::oid]),
                       ('bases_carga_cargar_lote_core', array[v_nucleo::oid, v_puerta::oid])) o(nombre, permitidos)
          join pg_proc p on pg_catalog.strpos(pg_catalog.lower(coalesce(p.prosrc, '')), o.nombre) > 0
         where p.oid <> all (o.permitidos)
        union all
        select pg_describe_object(d.classid, d.objid, d.objsubid) || ' → ' || d.refobjid::regprocedure::text
          from pg_depend d
         where d.refclassid = 'pg_proc'::regclass and d.refobjid in (v_env, v_ambito, v_nucleo)) x;
  if to_regclass('cron.job') is not null then
    execute $cron$select string_agg(j.jobid::text, ', ' order by j.jobid) from cron.job j
                   where pg_catalog.strpos(pg_catalog.lower(coalesce(j.command, '')), 'bases_carga_contacto_existente') > 0
                      or pg_catalog.strpos(pg_catalog.lower(coalesce(j.command, '')), 'bases_carga_fuera_de_ambito') > 0
                      or pg_catalog.strpos(pg_catalog.lower(coalesce(j.command, '')), 'bases_carga_cargar_lote_core') > 0$cron$
      into v_cron;
  end if;
  if v_mal is not null or v_cron is not null then
    raise exception 'PREFLIGHT bases_alternativo_cliente: otro posible consumidor del envoltorio, de la regla del ámbito o del núcleo (%; cron.job: %): este cambio lo alcanzaría y no es carga de bases; inspeccionar antes de migrar',
      coalesce(v_mal, '-'), coalesce(v_cron, '-');
  end if;
  -- La premisa de la comparación literal: el alternativo se guarda SIEMPRE canónico (E.164); si el CHECK cambia o falta, no valdría.
  if (select md5(pg_get_constraintdef(c.oid)) || '|' || c.convalidated::text || '|' || c.contype::text from pg_constraint c
       where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_telefono_alternativo_formato')
     is distinct from '4ce894b3dc052735877c5e1ae07b3219|true|c' then
    raise exception 'PREFLIGHT bases_alternativo_cliente: cambió o falta la restricción leads_telefono_alternativo_formato de crm.leads (la premisa de la comparación literal)';
  end if;
  -- El inventario y las DEFINICIONES de los trinquetes que se barren abajo, ANTES del primer barrido (no se exige que pasen; se exige
  -- que sean ellos).
  if (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0)
     is distinct from '30|3cefe40e1440f25d2daadb56d35a0f8d' then
    raise exception 'PREFLIGHT bases_alternativo_cliente: los private.assert_*() que barre la migración no son los auditados (inventario o definiciones: %); revisarlos antes de barrerlos',
      (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
         from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0);
  end if;
  -- Fotos para el postflight: la ficha del envoltorio y los private.assert_*() sin argumentos y SIN los `*_mutantes` (estado y texto
  -- íntegro del primer error: se exige que NO cambien, no que pasen).
  perform set_config('bases_alternativo_cliente.ficha_antes',
    (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_env), true);
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  perform set_config('bases_alternativo_cliente.trinquetes_antes', v_foto, true);
end
$preflight$;

-- ── 1. El envoltorio de identidad de la carga, por ancla única: su WHERE mira también el alternativo de los clientes ──────
do $envoltorio$
declare
  v_firma regprocedure := 'private.bases_carga_contacto_existente(text,text)'::regprocedure;
  v_def text;
  v_acl aclitem[];
  v_ancla text;
  v_nuevo text;
  v_veces integer;
begin
  select pg_get_functiondef(p.oid), p.proacl into v_def, v_acl from pg_proc p where p.oid = v_firma;

  v_ancla := $a1$   where l.telefono = p_telefono or (p_dni is not null and l.dni = p_dni)
$a1$;
  v_nuevo := $n1$   where l.telefono = p_telefono or (p_dni is not null and l.dni = p_dni)
      -- Bloque 2.9 (D-37 de Miguel, 09/10/2026): también el TELÉFONO ALTERNATIVO de un cliente ya convertido (lead en etapa
      -- convertido, activo o retirado), dentro del mismo conjunto: la misma categoría y el mismo orden de relevancia que cualquier
      -- otra coincidencia (gana la más relevante). El alternativo de un lead que no es cliente no cuenta (D-37). Comparación literal
      -- de formas canónicas, como la regla del 2.8 (D-30): el alternativo se guarda en E.164 (CHECK leads_telefono_alternativo_formato)
      -- y el teléfono de la fila llega normalizado.
      or (l.etapa = 'convertido' and l.telefono_alternativo = p_telefono)
$n1$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT bases_alternativo_cliente: el ancla del WHERE del envoltorio aparece % veces (debe ser 1)', v_veces;
  end if;

  execute replace(v_def, v_ancla, v_nuevo);

  if (select p.proacl from pg_proc p where p.oid = v_firma) is distinct from v_acl then
    raise exception 'POSTFLIGHT bases_alternativo_cliente: los permisos del envoltorio cambiaron al parchear';
  end if;
end
$envoltorio$;

-- ── 2. El comentario: al de B8 se le AÑADE el del 2.9; la reversa lo quita ─────────────────────────────────────────────
do $comentario$
begin
  execute pg_catalog.format('comment on function private.bases_carga_contacto_existente(text, text) is %L',
    obj_description('private.bases_carga_contacto_existente(text,text)'::regprocedure, 'pg_proc')
      || $c1$ Bloque 2.9 (D-37): tambien el telefono alternativo de un cliente ya convertido (lead en etapa convertido, activo o retirado), dentro del mismo conjunto: la misma categoria y el mismo orden de relevancia que cualquier otra coincidencia (gana la mas relevante; si alguna es de otro equipo, la regla del ambito oculta motivo e id); el alternativo de un lead que no es cliente no cuenta. Comparacion literal de formas canonicas, como la regla del 2.8 (D-30).$c1$);
end
$comentario$;

-- ── Postflight ───────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_env regprocedure := 'private.bases_carga_contacto_existente(text,text)'::regprocedure;
  v_nucleo regprocedure := 'private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)'::regprocedure;
  v_ambito regprocedure := 'private.bases_carga_fuera_de_ambito(uuid,text,text,text)'::regprocedure;
  v_puerta regprocedure := 'crm.cargar_base_lote(uuid,uuid,jsonb)'::regprocedure;
  v_disp regprocedure := 'private.trg_leads_disponibilidad_atomica()'::regprocedure;
  v_src text;
  v_h text;
  v_mal text;
  r record;
  v text;
  v_foto text := '';
  v_gates integer := 0;
begin
  -- El envoltorio: la comparación nueva una sola vez, cuerpo y definición exactos, la misma ficha que antes, comentario exacto.
  select p.prosrc, md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) into v_src, v_h from pg_proc p where p.oid = v_env;
  if (length(v_src) - length(replace(v_src, $t$or (l.etapa = 'convertido' and l.telefono_alternativo = p_telefono)$t$, '')))
       / length($t$or (l.etapa = 'convertido' and l.telefono_alternativo = p_telefono)$t$) <> 1 then
    raise exception 'POSTFLIGHT bases_alternativo_cliente: el envoltorio no quedó con la comparación del alternativo exactamente una vez';
  end if;
  if v_h is distinct from 'bcb6a83abdd7225bc048bfa4713ed8cf/76773d711c6c317153833456c1ed6bdb' then
    raise exception 'POSTFLIGHT bases_alternativo_cliente: el envoltorio no quedó exactamente como se ensayó (md5 del cuerpo / de la definición %)', v_h;
  end if;
  if (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
             || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
        from pg_proc p where p.oid = v_env) is distinct from current_setting('bases_alternativo_cliente.ficha_antes', true)
     or has_function_privilege('anon', v_env, 'EXECUTE') or has_function_privilege('authenticated', v_env, 'EXECUTE')
     or has_function_privilege('service_role', v_env, 'EXECUTE')
     or md5(coalesce(obj_description(v_env, 'pg_proc'), '')) is distinct from 'bfe5c84dce3ec76d854e6edc72d13ef9' then
    raise exception 'POSTFLIGHT bases_alternativo_cliente: la ficha o el comentario del envoltorio no son los esperados (comentario md5 %)',
      md5(coalesce(obj_description(v_env, 'pg_proc'), ''));
  end if;
  -- Las doce funciones: intactas.
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.cargar_base_lote(uuid,uuid,jsonb)', 'b03d2e9d4500ca54fb8aec014786653a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.base_gestion_lead_visible(uuid,text,uuid,uuid)', 'e80a43724b64f0ed5ac67b846292fb6c', 'postgres:EXECUTE:false'),
    ('private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)', 'e5f25344437c0c54b289d4ae294b5e39', 'postgres:EXECUTE:false'),
    ('private.bases_carga_fuera_de_ambito(uuid,text,text,text)', '7341099506af3a2f2af3eeb9ec0862e4', 'postgres:EXECUTE:false'),
    ('private.bases_carga_lead_ref(uuid,text,uuid)', 'db760dd5ae42b06a886b9420fa927be8', 'postgres:EXECUTE:false'),
    ('private.bloquear_contactos_lead(text[],text[])', '0d52f58c2065c1c0dc37a7587eda5882', 'postgres:EXECUTE:false'),
    ('private.es_lector_global()', 'c8be602f84348a0125617995802db618', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.normalizar_telefono(text)', '00c30277b752de13be3ee0599485e6a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.vendedor_ids_visibles(uuid)', '85544c70a0920f3a7a1b5da06935f236', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text)', '742d44fff6a8a742292c8de702812e60', 'postgres:EXECUTE:false'),
    ('private.verificar_disponibilidad_lead_impl(text,text,uuid)', 'cece9dd168c9beea935af2e05895e32a', 'postgres:EXECUTE:false')) e(firma, definicion, acl)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null
     or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion
     or p.proowner is distinct from 'postgres'::regrole::oid
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) is distinct from e.acl;
  if v_mal is not null then
    raise exception 'POSTFLIGHT bases_alternativo_cliente: cambió algo que esta migración no toca (%)', v_mal;
  end if;
  -- El candado de contacto del 2.8 r4: intacto.
  if not exists (select 1 from pg_proc p
                  where p.oid = v_disp and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and strpos(p.prosrc, 'array[old.telefono, new.telefono, old.telefono_alternativo, new.telefono_alternativo],') > 0
                    and strpos(p.prosrc, 'perform private.bloquear_contactos_lead(array[new.telefono, new.telefono_alternativo], array[new.dni]);') > 0)
     or not exists (select 1 from pg_trigger t
                     where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_insert'
                       and t.tgfoid = v_disp and t.tgenabled = 'O' and t.tgtype = 7)
     or not exists (select 1 from pg_trigger t
                     where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update'
                       and t.tgfoid = v_disp and t.tgenabled = 'O' and t.tgtype = 19) then
    raise exception 'POSTFLIGHT bases_alternativo_cliente: el candado de contacto del 2.8 r4 cambió';
  end if;
  -- Nadie más consume el envoltorio, el ámbito ni el núcleo (lo mismo que el preflight, sin cron: la migración no programa nada).
  select string_agg(x.quien, ', ' order by x.quien) into v_mal
  from (select p.oid::regprocedure::text || ' → ' || o.nombre as quien
          from (values ('bases_carga_contacto_existente', array[v_env::oid, v_nucleo::oid, v_ambito::oid]),
                       ('bases_carga_fuera_de_ambito', array[v_ambito::oid, v_nucleo::oid]),
                       ('bases_carga_cargar_lote_core', array[v_nucleo::oid, v_puerta::oid])) o(nombre, permitidos)
          join pg_proc p on pg_catalog.strpos(pg_catalog.lower(coalesce(p.prosrc, '')), o.nombre) > 0
         where p.oid <> all (o.permitidos)
        union all
        select pg_describe_object(d.classid, d.objid, d.objsubid) || ' → ' || d.refobjid::regprocedure::text
          from pg_depend d
         where d.refclassid = 'pg_proc'::regclass and d.refobjid in (v_env, v_ambito, v_nucleo)) x;
  if v_mal is not null then
    raise exception 'POSTFLIGHT bases_alternativo_cliente: otro objeto consume el envoltorio, el ámbito o el núcleo (%)', v_mal;
  end if;
  if (select md5(pg_get_constraintdef(c.oid)) || '|' || c.convalidated::text || '|' || c.contype::text from pg_constraint c
       where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_telefono_alternativo_formato')
     is distinct from '4ce894b3dc052735877c5e1ae07b3219|true|c' then
    raise exception 'POSTFLIGHT bases_alternativo_cliente: cambió la restricción leads_telefono_alternativo_formato';
  end if;
  -- La foto de los private.assert_*() sin argumentos (sin los `*_mutantes`) es EXACTAMENTE la de antes. No acredita PASS.
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    v_gates := v_gates + 1;
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  if v_foto is distinct from current_setting('bases_alternativo_cliente.trinquetes_antes', true) then
    raise exception E'POSTFLIGHT bases_alternativo_cliente: algún private.assert_*() da otro resultado que antes de la migración.\nANTES:\n%\nDESPUÉS:\n%',
      current_setting('bases_alternativo_cliente.trinquetes_antes', true), v_foto;
  end if;
  raise notice 'POSTFLIGHT bases_alternativo_cliente: envoltorio con el alternativo de los clientes (huellas, ficha y comentario) · doce funciones, candado del 2.8 r4, consumidores y CHECK intactos · % trinquetes idénticos a los previos',
    v_gates;
end
$postflight$;

commit;
