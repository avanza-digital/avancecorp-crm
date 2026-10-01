ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo de revisión — RONDA 2 y ÚLTIMA (LEVEL 3: puerta DEFINER de lectura que copia una policy) · Potencial del lead, FASE 3 entrega A (servidor)

Eres el revisor secundario. Sin base de datos ni red: todo está transcrito abajo. Responde con VERDICT (APPROVE / CHANGES_REQUESTED), SUMMARY, FINDINGS P0–P3 con evidencia (archivo/línea/fragmento), riesgos y test gaps, NEXT ACTIONS y CONFIDENCE. Sin hallazgo sin evidencia; separa hechos de hipótesis. Te pido REFUTAR los arreglos, no confirmarlos. Esta ronda existe porque hay evidencia nueva: se aplicaron tus hallazgos de la ronda 1 y los del auditor de RLS, y el diseño de `baja_el` cambió.

## Contexto mínimo
Marca «potencial del lead» (frío, tibio, estrella). Marcan el analista dueño y su supervisor; gerencia y directorio solo ven. La marca baja sola (fase 2): Estrella → Tibio con 5 días completos sin gestión, Tibio → Frío con 10, lunes a sábado; la tarea `private.potencial_caducar()` corre con pg_cron a las 05:10 y 05:40 Lima (`10,40 10 * * *` GMT) y solo toca leads activos y abiertos. Esta migración añade la puerta de LECTURA `crm.potencial_leads_fn(uuid[])` (DEFINER, STABLE, EXECUTE solo authenticated) que devuelve `{version, habilitada, items}`; con la bandera `potencial_lead` apagada, `habilitada:false` sin leer nada. No modifica nada existente.

## Tu respuesta de la ronda 1 (íntegra)
**VERDICT: CHANGES_REQUESTED**

**SUMMARY:** No identifico una fuga de RLS en la puerta transcrita con sus permisos actuales. El espejo, la admisión y la vinculación del actor a la sesión son coherentes. Solicito cambios en las verificaciones: admiten estados que contradicen las restricciones declaradas. `baja_el` cumple la decisión 5 como fecha de elegibilidad; no garantiza cuándo se ejecutará la bajada.

**FINDINGS**

1. **P2 — El postflight admite configuración y permisos adicionales.**  
   Evidencia: `$postflight$` de [la migración](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead/supabase/migrations/20261001151704_crm_potencial_lead_lectura.sql) comprueba `proconfig @> array['search_path=""']` y los destinatarios de la ACL, pero no `is_grantable`.

   Dos contraejemplos:
   
   - `EXECUTE TO authenticated WITH GRANT OPTION` pasa: el destinatario sigue siendo `authenticated`.
   - Añadir un `SET request.jwt.claims = ...` conserva el `search_path` requerido y pasa ese postflight, aunque puede alterar la identidad que obtiene `auth.uid()`.

   Son falsos verdes del verificador, **no estados presentes en el SQL entregado**. Comparar la configuración completa esperada, rechazar grant options para `authenticated` y comprobar también los permisos efectivos de los roles API.

2. **P2 — La verificación independiente interpreta una ACL implícita como ausencia de permisos ajenos.**  
   Evidencia: [verificar-lectura.sql](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead/supabase/scripts/potencial-lead/verificar-lectura.sql), cálculo de `v_nucleo` mediante `aclexplode(p.proacl)`.

   Si `proacl IS NULL`, `aclexplode` no produce filas y el resultado anunciado es `0`. Sin embargo, para funciones esa ACL implícita incluye `EXECUTE` para `PUBLIC`. El postflight de instalación rechaza ese estado, pero este verificador posterior lo informaría incorrectamente.

   Rechazar explícitamente una ACL nula o expandir `coalesce(proacl, acldefault('f', proowner))`; complementar con `has_function_privilege` para comprobar permisos efectivos.

3. **P3 — El gate oculta duplicados en los ítems.**  
   Evidencia: [test-rls.mjs](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead/supabase/scripts/test-rls.mjs), `new Set(data.items.map((item) => item.lead_id))`.

   Una respuesta con cada lead visible repetido dos veces pasa la comparación. Añadir una comprobación de unicidad y comparar también las cantidades. La prueba sintética de IDs repetidos cubre otro caso: duplicados en la entrada.

**Riesgos y test gaps**

- **a. Visibilidad, NULL y actor.** `IN (SELECT ...)` y `= ANY(array(SELECT ...))` conservan aquí la misma aceptación de filas, incluidos NULL y conjuntos vacíos. Un resultado desconocido no concede acceso; el gate usa `IS NOT TRUE`. No encuentro exposición por `puede_marcar`, orden o errores explícitos.  
  El núcleo sí mezcla identidades si recibe otro `p_actor`: por ejemplo, una sesión de vendedor y un parámetro de gerencia activan la rama `v_rol = 'gerencia'`. Actualmente la API no puede invocarlo y la puerta siempre pasa `auth.uid()`. Es una precondición protegida por la arquitectura, no comprobada dentro del núcleo.

- **b. Preflight.** `polcmd IN ('r','*')` incluye todas las policies pertinentes para este SELECT; omitir las de UPDATE es correcto. El cast a `regrole[]` evita depender de los OID concretos de los roles. Con la misma versión y configuración de deparsing, el `search_path` vacío resulta coherente.  
  La huella no es completamente independiente de la sesión: `quote_all_identifiers` puede cambiar el texto de `pg_get_expr`; también puede cambiar entre versiones de PostgreSQL. Fijaría esa opción y verificaría las huellas en producción antes de aplicar. El sellado tampoco protege frente a cambios de policies **posteriores** a la instalación.

- **c. Calendario.** La fórmula coincide con la fase 2 bajo el mismo estado, fecha y corte. El domingo puede ser la fecha correcta porque el sábado ya terminó y la tarea corre diariamente.  
  **No coincide siempre con la ejecución real.** Contraejemplo: una Estrella marcada el 05/10, reabierta el viernes 16/10 después de las 05:40, tiene nueve días completos. La lectura devuelve `tibio@2026-10-16`; la siguiente corrida, el sábado 17, contará diez y bajará directamente a Frío. No hace falta ningún contacto intermedio. El límite y los candados también pueden retrasarla; un contacto posterior puede evitarla. Documentar esta semántica antes de que la pantalla prometa una madrugada concreta.

- **d. Costo.** La medición no representa un subárbol grande: el fixture crea un supervisor y un vendedor. `potencial_rechazo` vuelve a resolver el subárbol por cada ítem; `STABLE` no implica memorizar ese resultado entre llamadas. Además, `dias_lunes_a_sabado` genera días y se repite dentro de la búsqueda de fechas: el costo crece con la antigüedad de la marca. Hay riesgo de crecimiento, pero no evidencia suficiente para afirmar una latencia inaceptable. Medir con el tamaño de equipo, antigüedad e historial máximos esperados.

- **e. Zona horaria.** El contrato es utilizable: interpretar `marcado_en` respetando su offset y mostrarlo en Lima. Tratar `baja_el` como fecha de calendario. `new Date('2026-10-11')` representa medianoche UTC y, al mostrarla en Lima, puede terminar como **10/10**.

- **f. Reversa.** Los dos `DROP FUNCTION`, dentro de una transacción y sin `CASCADE`, eliminan también sus comentarios y permisos. Permanecen intencionalmente las tablas y el registro de migración. El manejo de “función inexistente” en la pantalla está declarado, pero no está demostrado por esta evidencia.

- **g. Cobertura pendiente.** Añadiría directorio histórico sin membresía, perfil inactivo con equipo activo, roles desalineados y los mutantes de verificación anteriores. Con la bandera apagada, el gate omite la comparación contra RLS; `CRM_RLS_EXIGE_POTENCIAL=1` no obliga a ejecutarla. Debe quedar visible que esa comprobación está **NOT RUN** en ese estado. El fragmento tampoco permite comprobar que el runner invoque `testPotencialLectura`.

**NEXT ACTIONS:** Corregir ambos verificadores y la comprobación de unicidad; añadir sus mutantes. Explicitar que `baja_el` es elegibilidad y cubrir el caso posterior a la última corrida. Ejecutar el gate con sesiones reales y bandera encendida en un banco autorizado, y medir el caso de equipo grande.

**CONFIDENCE:** Alta en el análisis estático de autorización y los falsos verdes descritos; limitada para rendimiento y ejecución real. Los PASS citados son evidencia aportada. Pruebas ejecutadas por este revisor: **NOT RUN**. El gate con sesiones reales sigue **NOT RUN**.


## Qué se hizo con cada hallazgo

### Tuyos (ronda 1)
1. **P2 postflight con configuración y permisos de más → ACEPTADO.** Ahora exige `proconfig = array['search_path=""']` EXACTO en las cuatro funciones; en la ACL de la puerta, `authenticated` solo con EXECUTE y sin `is_grantable`; y permisos EFECTIVOS con `has_function_privilege` (authenticated sí; anon y service_role no; los tres roles no en los tres ayudantes). Mutantes nuevos, todos rechazados: `puerta-set-de-mas`, `puerta-con-opcion`, `puerta-service-role`, `ayudante-abierto`, `ayudante-a-authenticated`.
2. **P2 verificador con ACL nula → ACEPTADO.** `verificar-lectura.sql` usa `has_function_privilege` y además cuenta las funciones con `proacl is null`. Prueba en el ciclo: con un ayudante abierto a PUBLIC (en una transacción que se deshace) el verificador dice 3, no 0.
3. **P3 duplicados en el gate → ACEPTADO.** El bloque comprueba unicidad y cantidades. Y la sintética afirma «ningún lead repetido en los ítems».
- **Riesgo a (núcleo con otro `p_actor`) → ACEPTADO como defensa:** el núcleo lanza 42501 si `p_actor` no es `auth.uid()`. Caso en la sintética (sesión de V2, actor gerencia), mutante `actor-ajeno` cazado, y el postflight comprueba que el núcleo lo rechaza (mutante `nucleo-acepta-otro-actor` rechazado).
- **Riesgo b (`quote_all_identifiers`) → ACEPTADO:** el preflight lo fija en `off` (local a la transacción) antes de calcular huellas. Que el sellado no protege de cambios POSTERIORES queda escrito en el ledger y en el LEEME («si cambian leads_select o crm_actor_activo_gate, re-auditar private.potencial_lectura»), y lo vigila el gate (ver abajo).
- **Riesgo c (`baja_el` no coincide con la tarea cuando la corrida de hoy ya pasó) → ACEPTADO, cambio de diseño:** `private.potencial_proxima_corrida(instante)` devuelve la fecha de la próxima pasada (hoy si aún no dieron las 05:40 Lima; si no, mañana) y `baja_el`/`baja_a` se buscan desde esa fecha con `private.potencial_proxima_baja`. Tu contraejemplo está en la sintética: estrella del lunes 05 vista el viernes 16 tras la corrida → `frio@2026-10-17`; antes de la corrida → `tibio@2026-10-16`. La hora 05:40 queda atada al horario del job: el postflight se niega si `cron.job` no tiene `10,40 10 * * *`. La semántica («primera madrugada con lo que se sabe ahora, no una promesa») está en la cabecera, el ledger y el LEEME; la pantalla siempre dice «si no se gestiona».
- **Riesgo d (costo) → MEDIDO con el caso caro:** supervisor con un equipo de 67 personas en tres niveles: 50 ids = 6–8 ms; 200 ids = 20–25 ms; 200 marcas de hace 400 días con 20 contactos cada una = 28–40 ms; un analista que pide 200 = 1–2 ms. La búsqueda de fechas ya no recorre 22 días por fila: `potencial_proxima_baja` es un bucle que para en la primera fecha y no recorre nada si el nivel nunca baja (se lo pregunta a la regla con `potencial_nivel_tras(nivel, 2147483647)`).
- **Riesgo e (`new Date('2026-10-11')`) → cubierto en el front:** trata `baja_el` como cadena de calendario (compara cadenas y hace aritmética en UTC); tiene pruebas unitarias en zona de Lima.
- **Riesgo g (cobertura) → ACEPTADO:** actores nuevos en la sintética: directorio histórico sin membresía, perfil inactivo con equipo activo, usuario solo del portal y pareja desalineada (perfil directorio con equipo vendedor). El runner sí invoca el bloque: `await testPotencialLead(sessions, verifiedSeed);` y `await testPotencialLectura(sessions, verifiedSeed);` van seguidos en `main()`.

### Del auditor de RLS (PASS con observaciones: 0 P0, 0 P1)
- **P2 la comparación «puerta = RLS» del gate era inalcanzable (la bandera siempre apagada) → ACEPTADO:** el bloque enciende la bandera fuera de banda en un try/finally y la repone; compara rol por rol; añade `clientBank` (authenticated ajeno al CRM → 42501) y casos de `puede_marcar`. Sigue NOT RUN en local (exige el gestor de credenciales).
- **P2 fila del ledger → ACEPTADO.** **P3 actor = sesión → ACEPTADO** (arriba). **P3 la reversa de la fase 2 no se negaba con la lectura aplicada → ACEPTADO:** `reversa-caducidad.sql` se niega; los ciclos de las fases 1 y 2 retiran la lectura y la reponen.
- Huecos: matriz 2-D de 201 elementos → 22023 (caso añadido; mutante `tope-una-dimension` cazado); roles de puente (`crm_gestion_diaria_lector` es miembro de `authenticated` a propósito desde 20260922184459 y hereda el EXECUTE de la puerta: sin sesión recibe 42501, caso añadido).

## Evidencia nueva (banco Docker propio; esquema de producción del 30/09 más las migraciones posteriores del repo)
- Los TRES ciclos seguidos (fase 1, fase 2 y fase 3A) conviven: fase 1 75/75 y concurrencia 11/11; fase 2 51/51, concurrencia 10/10 y corrida real de pg_cron `succeeded`; cada uno retira y repone la lectura.
- prueba-lectura.sql: **94 de 94**. Trinquetes (36 `private.assert_*()` + censo de contadores): idénticos sin y con la migración.
- Mutantes de lógica: 29. Caen 28 (ve-inactivos, sin-ambito, sin-propios, sin-parqueo, sin-gerencia, sin-lector, actor-ajeno, puede-siempre, puede-nunca, marcado-cualquier-evento, marcado-el-primero, sin-zona-lima, reloj-sin-contactos, corte-infinito, dias-hasta-manana, cerrados-bajan, proxima-es-hoy, baja-un-dia-tarde, baja-nivel-fijo, baja-no-para, corrida-a-las-0510, corrida-siempre-hoy, corrida-sin-zona, sin-gate, sin-bandera, sin-tope, tope-una-dimension, sin-sesion-ni-gate). Sobrevive A PROPÓSITO sin-sesion (sin sesión el gate ya rechaza con el mismo 42501).
- Mutantes de la migración y del preflight: 24, todos rechazados (puerta invoker/volátil/sin search_path/con SET de más/anon/service_role/con grant option/sin grant; núcleo abierto/definer/acepta otro actor; ayudante abierto/concedido a authenticated; con conteo; corrida a otra hora; bajada un día tarde; y, en el preflight o postflight: ayudante cambiado, policy restrictiva nueva, permisiva nueva, leads_select cambiada, gate cambiado, roles de la policy cambiados, sin la fase 2, job con otro horario).
- `test:rls` con sesiones reales: NOT RUN. `node --check` del gate: PASS. `npm run check:scripts`: PASS.

## Preguntas de esta ronda
a. ¿`potencial_proxima_corrida` (hora fija 05:40 Lima, atada al job por el postflight) y `potencial_proxima_baja` dejan algún caso en que `baja_a`/`baja_el` contradigan a `potencial_caducar`, aparte de los declarados (contacto o marca nuevos, lead ocupado, límite del lote)? Mira el intervalo 05:10–05:40 y el cambio de día.
b. ¿El postflight nuevo tiene falsos verdes o falsos rojos (igualdad exacta de `proconfig`, `has_function_privilege` con herencia de roles, el bloque que espera `insufficient_privilege`, la comprobación de `cron.job`)?
c. ¿La comprobación `p_actor is distinct from (select auth.uid())` puede romper un uso legítimo (la puerta siempre pasa `auth.uid()`)?
d. ¿Algo en el bloque del gate (encender la bandera fuera de banda y reponerla) deja la base peor que la encontró si falla a mitad?
e. ¿Queda algún hallazgo de la ronda 1 mal resuelto?

## Archivos (versión actual, íntegros)

### supabase/migrations/20261001151704_crm_potencial_lead_lectura.sql
```sql
-- 20261001151704_crm_potencial_lead_lectura.sql
--
-- Potencial del lead · FASE 3, entrega A (servidor): la puerta de LECTURA. Plan aprobado por
-- Miguel el 01/10/2026 («vamos dale» al plan en dos entregas: A marcar y ver, B filtrar). Nota
-- del vault: «Potencial del lead - Frio Tibio Estrella (2026-09-30)», «Fase 3 · mapa y plan».
--
-- QUÉ HACE
--   · private.potencial_proxima_corrida(instante): la fecha (Lima) de la próxima pasada de la tarea
--     de la fase 2. La tarea corre a las 05:10 y 05:40 Lima: antes de las 05:40 es hoy; después,
--     mañana. El postflight comprueba que el horario del job sigue siendo ese.
--   · private.potencial_proxima_baja(nivel, día del reloj, desde): la primera fecha, desde la
--     próxima corrida, en que la regla de la fase 2 da un nivel menor, y ese nivel. Bucle que para
--     en la primera (no recorre fechas de más) y no hace nada con un nivel que nunca baja.
--   · private.potencial_lectura(actor, lead_ids, hoy, corte, próxima corrida): por cada lead
--     pedido que el actor PUEDE VER (espejo de la policy leads_select), la marca vigente y lo que
--     la pantalla tiene que decir: nivel, origen (manual | caducidad), el último nivel que puso una
--     PERSONA, cuándo se marcó, los días completos sin gestión (lunes a sábado), a qué nivel
--     bajará y en qué madrugada si nadie gestiona, y si el actor puede marcarlo. Un lead visible
--     sin marca viaja con nivel null. UNA sola regla: los días salen de private.potencial_reloj y
--     private.dias_lunes_a_sabado, el nivel siguiente de private.potencial_nivel_tras (fase 2), y
--     el permiso de private.potencial_rechazo (la misma función que decide en la puerta de
--     marcar, fase 1). Recibe hoy, el corte y la próxima corrida para ensayarse con calendario.
--     El actor DEBE ser el de la sesión (Codex f3a r1): con otro, 42501.
--   · crm.potencial_leads_fn(uuid[]): la puerta. Sesión, el gate restrictivo del CRM
--     (private.puede_acceder_crm, invocado y no copiado), tope de 200 ids y la bandera
--     'potencial_lead': apagada devuelve {version:1, habilitada:false, items:[]} SIN leer nada;
--     encendida, {version:1, habilitada:true, items:[…]}.
-- QUÉ SIGNIFICA baja_el (Codex f3a r1): la primera madrugada en que la tarea la bajaría con lo que
--   se sabe AHORA. No es una promesa: un contacto o una marca nuevos la aplazan; si el lead está
--   ocupado o la pasada llega a su límite de 200, la bajada queda para la pasada siguiente.
-- NO TOCA nada de lo existente: ninguna puerta de cartera, cola, SLA ni Gestión Diaria cambia. La
--   pantalla une la marca por lead_id, igual que hace con crm.cierres_estado_fn.
-- CAPAS: puerta crm (valida, autoriza, delega) → núcleo private (INVOKER, sin EXECUTE para la
--   API) → tablas (crm.lead_potencial y su historial, sin grants para la API).
-- SECURITY DEFINER, justificación: las tablas de la marca no tienen grants para la API (fase 1,
--   auditor-rls r1) y el reloj y la regla de la fase 2 no tienen EXECUTE para la API: una puerta
--   INVOKER no puede leerlos. Molde: crm.cierres_estado_fn. La visibilidad se verifica de forma
--   explícita con el ESPEJO de leads_select; el preflight fija por md5 esa policy, el gate
--   restrictivo de crm.leads y los ayudantes en que se apoyan: si alguno cambió desde el ensayo en
--   el banco, la migración se niega y hay que volver a revisarla.
-- SIN contar: private.contadores_crudos_leads_citas vigila toda función que nombre crm.leads y
--   use un agregado de conteo; aquí no hay ninguno (jsonb_agg y cardinality).
-- REVERSA: supabase/scripts/potencial-lead/reversa-lectura.sql (quita las dos funciones; no hay
--   datos que perder).

begin;
set local lock_timeout = '5s';

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────
do $preflight$
declare
  v_huellas text;
  v_policies text;
begin
  -- Texto de catálogo independiente de la sesión: todo calificado y sin comillas forzadas
  -- (quote_all_identifiers cambiaría el texto de pg_get_expr y con él las huellas; Codex f3a r1).
  perform pg_catalog.set_config('search_path', '', true);
  perform pg_catalog.set_config('quote_all_identifiers', 'off', true);

  if (
    pg_catalog.to_regclass('crm.lead_potencial') is not null
    and pg_catalog.to_regclass('crm.lead_potencial_eventos') is not null
    and pg_catalog.to_regprocedure('private.potencial_rechazo(uuid,uuid)') is not null
    and pg_catalog.to_regprocedure('private.potencial_reloj(uuid,timestamp with time zone,timestamp with time zone)') is not null
    and pg_catalog.to_regprocedure('private.dias_lunes_a_sabado(date,date)') is not null
    and pg_catalog.to_regprocedure('private.potencial_nivel_tras(crm.nivel_potencial,integer)') is not null
    and exists (select 1 from crm.multiempresa_flags f where f.nombre = 'potencial_lead')
  ) is not true then
    raise exception 'PREFLIGHT potencial_lectura: faltan la fase 1 (20260930213647) o la fase 2 (20260930235917)';
  end if;

  if (
    not exists (
      select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where (n.nspname = 'crm' and p.proname = 'potencial_leads_fn')
         or (n.nspname = 'private' and p.proname in ('potencial_lectura', 'potencial_proxima_baja', 'potencial_proxima_corrida')))
  ) is not true then
    raise exception 'PREFLIGHT potencial_lectura: ya aplicada o aplicada a medias';
  end if;

  -- La visibilidad de la puerta descansa en estos ayudantes: identidad por cuerpo + DEFINER +
  -- volatilidad + configuración + dueño (pg_get_functiondef no sirve: cambia con la sesión).
  select pg_catalog.string_agg(
           p.oid::pg_catalog.regprocedure::text || '=' ||
           pg_catalog.md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|'
                          || coalesce(pg_catalog.array_to_string(p.proconfig, ','), '') || '|' || p.proowner::pg_catalog.regrole::text),
           ' ' order by p.oid::pg_catalog.regprocedure::text)
    into v_huellas
  from pg_catalog.pg_proc p
  where p.oid in (pg_catalog.to_regprocedure('private.rol_crm(uuid)'),
                  pg_catalog.to_regprocedure('private.vendedor_ids_visibles(uuid)'),
                  pg_catalog.to_regprocedure('private.es_lector_global()'),
                  pg_catalog.to_regprocedure('private.puede_acceder_crm()'),
                  pg_catalog.to_regprocedure('crm.bandera_activa(text)'),
                  pg_catalog.to_regprocedure('private.potencial_rechazo(uuid,uuid)'));
  if v_huellas is distinct from
       'crm.bandera_activa(text)=bb817f2b07b561356959f25dc3aae4dc'
    || ' private.es_lector_global()=5b8ac0c37dcbf5b82057d7b98c65c303'
    || ' private.potencial_rechazo(uuid,uuid)=8893beeecea076e7fd7dbafec174500f'
    || ' private.puede_acceder_crm()=4e2c1caf7ead51be450d5018be4c6092'
    || ' private.rol_crm(uuid)=16960a2a21cc5c372431c2dd67acafe4'
    || ' private.vendedor_ids_visibles(uuid)=45ae492c03234b80336c0b8f5c8ac09b' then
    raise exception 'PREFLIGHT potencial_lectura: un ayudante de visibilidad no es el ensayado: %', coalesce(v_huellas, '(ninguno)');
  end if;

  -- Las policies que deciden qué leads se LEEN: exactamente la permisiva leads_select (la que el
  -- núcleo copia) y el gate restrictivo crm_actor_activo_gate (el que la puerta invoca). Una
  -- policy de lectura nueva o un cambio en estas dos dejaría la puerta viendo de más o de menos.
  select pg_catalog.string_agg(
           pol.polname::text || '|' || pol.polcmd::text || '|' || pol.polpermissive::text || '|'
           || pol.polroles::pg_catalog.regrole[]::text || '|' || pg_catalog.md5(pg_catalog.pg_get_expr(pol.polqual, pol.polrelid)),
           ' ## ' order by pol.polname)
    into v_policies
  from pg_catalog.pg_policy pol
  where pol.polrelid = 'crm.leads'::pg_catalog.regclass and pol.polcmd in ('r', '*');
  if v_policies is distinct from
       'crm_actor_activo_gate|*|false|{authenticated}|c5e6c90632bc616212336e1d089a68b3'
    || ' ## leads_select|r|true|{authenticated}|073deaeb5700bac14209ec795b71567e' then
    raise exception 'PREFLIGHT potencial_lectura: las policies de lectura de crm.leads no son las ensayadas: %', coalesce(v_policies, '(ninguna)');
  end if;
end;
$preflight$;

-- ── 1 · Cuándo es la próxima pasada de la tarea ───────────────────────────────
create function private.potencial_proxima_corrida(p_instante timestamptz)
returns date
language sql
immutable
security invoker
set search_path = ''
as $function$
  -- La tarea crm-potencial-lead-caducidad corre a las 05:10 y a las 05:40 Lima (10:10 y 10:40 GMT).
  -- Hasta las 05:40 todavía queda una pasada HOY; desde las 05:40, la próxima es mañana.
  select case
    when (p_instante at time zone 'America/Lima')::time < time '05:40'
      then (p_instante at time zone 'America/Lima')::date
    else (p_instante at time zone 'America/Lima')::date + 1
  end;
$function$;
comment on function private.potencial_proxima_corrida(timestamptz) is
'Fecha (Lima) de la próxima pasada de la tarea de caducidad del potencial: hoy si aún no dieron las 05:40 Lima, si no mañana. Debe ir a la par del horario del job crm-potencial-lead-caducidad (10,40 10 * * * GMT): lo comprueba el postflight de la migración de lectura. Sin EXECUTE para la API.';

-- ── 2 · Cuándo bajaría una marca, y a qué nivel ───────────────────────────────
create function private.potencial_proxima_baja(p_nivel crm.nivel_potencial, p_reloj_dia date, p_desde date)
returns table (baja_a crm.nivel_potencial, baja_el date)
language plpgsql
immutable
security invoker
set search_path = ''
as $function$
declare
  v_dia date;
  v_nuevo crm.nivel_potencial;
begin
  if p_nivel is null or p_reloj_dia is null or p_desde is null then
    return;
  end if;
  -- Un nivel que no baja ni con todos los días del mundo (frío) no se recorre. Se le pregunta a
  -- la regla; no se copia aquí qué niveles bajan.
  if (private.potencial_nivel_tras(p_nivel, 2147483647) < p_nivel) is not true then
    return;
  end if;
  -- De la próxima corrida en adelante, la primera fecha en que la regla da un nivel menor. 21 días
  -- cubren de sobra los 10 días hábiles más sus domingos; para en la primera que encuentra.
  for i in 0..21 loop
    v_dia := p_desde + i;
    v_nuevo := private.potencial_nivel_tras(p_nivel, private.dias_lunes_a_sabado(p_reloj_dia, v_dia));
    if v_nuevo < p_nivel then
      baja_a := v_nuevo;
      baja_el := v_dia;
      return next;
      return;
    end if;
  end loop;
  return;
end;
$function$;
comment on function private.potencial_proxima_baja(crm.nivel_potencial, date, date) is
'Primera fecha, desde p_desde (la próxima pasada de la tarea), en que la regla de la caducidad (private.potencial_nivel_tras con private.dias_lunes_a_sabado desde el día del reloj) da un nivel menor, y ese nivel. Sin filas si el nivel nunca baja o falta un dato. Sin EXECUTE para la API.';

-- ── 3 · Núcleo de la lectura ──────────────────────────────────────────────────
create function private.potencial_lectura(p_actor uuid, p_lead_ids uuid[], p_hoy date, p_corte timestamptz, p_proxima date)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_rol text;
  v_lector boolean;
  v_visibles uuid[];
  v_items jsonb;
begin
  if p_actor is null or p_hoy is null or p_corte is null or p_proxima is null then
    raise exception 'Actor, fecha, instante de corte y próxima corrida requeridos' using errcode = '22023';
  end if;
  -- El actor es SIEMPRE el de la sesión (Codex f3a r1): los ayudantes de visibilidad miran
  -- auth.uid(), y con otro actor el rol y el ámbito saldrían de identidades distintas.
  if p_actor is distinct from (select auth.uid()) then
    raise exception 'El actor no es el de la sesión' using errcode = '42501';
  end if;
  if p_lead_ids is null or pg_catalog.cardinality(p_lead_ids) = 0 then
    return '[]'::jsonb;
  end if;

  v_rol := private.rol_crm(p_actor);
  v_lector := private.es_lector_global();
  -- Se resuelve UNA vez (la policy lo evalúa como SubPlan en cada fila).
  v_visibles := array(select private.vendedor_ids_visibles(p_actor));

  select coalesce(pg_catalog.jsonb_agg(f.item order by f.lead_id), '[]'::jsonb)
    into v_items
  from (
    select
      l.id as lead_id,
      pg_catalog.jsonb_build_object(
        'lead_id', l.id,
        'nivel', p.nivel,
        'origen', p.origen,
        'nivel_marcado', m.nivel_marcado,
        'marcado_en', p.marcado_en,
        'dias_sin_gestion', r.dias,
        'baja_a', b.baja_a,
        'baja_el', b.baja_el,
        -- La MISMA regla de la puerta de marcar; cualquier valor que no sea 'ok' (NULL incluido) es no.
        'puede_marcar', coalesce(private.potencial_rechazo(p_actor, l.id) = 'ok', false)
      ) as item
    from crm.leads l
    left join crm.lead_potencial p on p.lead_id = l.id
    -- El último nivel que puso una PERSONA: si la marca bajó sola, es el nivel de antes.
    left join lateral (
      select e.nivel_nuevo as nivel_marcado
      from crm.lead_potencial_eventos e
      where e.lead_id = p.lead_id and e.motivo = 'manual'
      order by e.orden desc
      limit 1
    ) m on true
    -- El reloj y los días, con las funciones de la fase 2 (las mismas que usa la tarea).
    left join lateral (
      select x.reloj_dia, private.dias_lunes_a_sabado(x.reloj_dia, p_hoy) as dias
      from (select (private.potencial_reloj(p.lead_id, p.marcado_en, p_corte) at time zone 'America/Lima')::date as reloj_dia) x
      where p.lead_id is not null
    ) r on true
    -- La primera madrugada, desde la próxima pasada de la tarea, en que la bajaría si nadie
    -- gestiona, y a qué nivel. Solo leads abiertos: la tarea no toca los cerrados.
    left join lateral (
      select x.baja_a, x.baja_el
      from private.potencial_proxima_baja(p.nivel, r.reloj_dia, p_proxima) x
      where l.etapa is not null and l.etapa not in ('convertido', 'descartado')
    ) b on true
    where l.id = any (p_lead_ids)
      -- ── ESPEJO EXACTO de la policy leads_select (fijada por md5 en el preflight) ──
      --   activo = true and ( vendedor_id in (vendedor_ids_visibles(uid))
      --                       or (vendedor_id is null and asignado_supervisor_id in (...))
      --                       or rol_crm(uid) = 'gerencia' or es_lector_global() )
      -- El lector global va DENTRO del activo: ve todo lo vivo y nada de lo borrado.
      and l.activo = true
      and (
        l.vendedor_id = any (v_visibles)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any (v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      )
  ) f;

  return v_items;
end;
$function$;
comment on function private.potencial_lectura(uuid, uuid[], date, timestamptz, date) is
'Lectura de la marca de potencial: un ítem por cada lead pedido que el actor puede ver (espejo de la policy leads_select; el actor debe ser el de la sesión, si no 42501). Por lead: nivel vigente (null sin marca), origen, último nivel puesto por una persona, cuándo, días completos sin gestión (lunes a sábado), a qué nivel bajará y en qué madrugada desde la próxima pasada de la tarea, y si el actor puede marcarlo (private.potencial_rechazo). No mira la bandera ni el gate del CRM: eso lo hace la puerta. Sin EXECUTE para la API.';

-- ── 4 · Puerta ─────────────────────────────────────────────────────────────────
create function crm.potencial_leads_fn(p_lead_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
begin
  if v_actor is null then
    raise exception 'Sesión requerida' using errcode = '42501';
  end if;
  -- El gate RESTRICTIVO de crm.leads (crm_actor_activo_gate) se INVOCA en vez de copiarse: quien
  -- no es del CRM ni lector global, o fue dado de baja, no pregunta.
  if private.puede_acceder_crm() is not true then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  -- Sirve a una página en pantalla, no a un volcado (mismo tope que crm.cierres_estado_fn).
  if p_lead_ids is not null and pg_catalog.cardinality(p_lead_ids) > 200 then
    raise exception 'Parámetro p_lead_ids inválido: máximo 200' using errcode = '22023';
  end if;
  -- Con la bandera apagada la pantalla no pinta nada del potencial y aquí no se lee nada.
  if crm.bandera_activa('potencial_lead') is not true then
    return pg_catalog.jsonb_build_object('version', 1, 'habilitada', false, 'items', '[]'::jsonb);
  end if;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'habilitada', true,
    'items', private.potencial_lectura(
      v_actor, p_lead_ids, (pg_catalog.now() at time zone 'America/Lima')::date, pg_catalog.now(),
      private.potencial_proxima_corrida(pg_catalog.now()))
  );
end;
$function$;
comment on function crm.potencial_leads_fn(uuid[]) is
'Puerta de lectura del potencial del lead. Devuelve {version, habilitada, items}: con la bandera potencial_lead apagada, habilitada=false e items vacío; encendida, un ítem por cada lead pedido que el actor puede ver: {lead_id, nivel, origen, nivel_marcado, marcado_en, dias_sin_gestion, baja_a, baja_el, puede_marcar}. Máximo 200 ids (22023). Sin sesión o fuera del CRM: 42501. Solo lectura.';

-- ── 5 · Dueños y permisos ──────────────────────────────────────────────────────
alter function private.potencial_proxima_corrida(timestamptz) owner to postgres;
alter function private.potencial_proxima_baja(crm.nivel_potencial, date, date) owner to postgres;
alter function private.potencial_lectura(uuid, uuid[], date, timestamptz, date) owner to postgres;
alter function crm.potencial_leads_fn(uuid[]) owner to postgres;
revoke all on function private.potencial_proxima_corrida(timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.potencial_proxima_baja(crm.nivel_potencial, date, date) from public, anon, authenticated, service_role;
revoke all on function private.potencial_lectura(uuid, uuid[], date, timestamptz, date) from public, anon, authenticated, service_role;
revoke all on function crm.potencial_leads_fn(uuid[]) from public, anon, authenticated, service_role;
grant execute on function crm.potencial_leads_fn(uuid[]) to authenticated;

-- ── 6 · Postflight ─────────────────────────────────────────────────────────────
do $postflight$
declare
  v_puerta pg_catalog.regprocedure := 'crm.potencial_leads_fn(uuid[])'::pg_catalog.regprocedure;
  v_nucleo pg_catalog.regprocedure := 'private.potencial_lectura(uuid,uuid[],date,timestamp with time zone,date)'::pg_catalog.regprocedure;
  v_privadas pg_catalog.regprocedure[] := array[
    'private.potencial_lectura(uuid,uuid[],date,timestamp with time zone,date)'::pg_catalog.regprocedure,
    'private.potencial_proxima_baja(crm.nivel_potencial,date,date)'::pg_catalog.regprocedure,
    'private.potencial_proxima_corrida(timestamp with time zone)'::pg_catalog.regprocedure
  ];
begin
  perform pg_catalog.set_config('search_path', '', true);

  -- Puerta: DEFINER, STABLE, dueño postgres y configuración EXACTA (solo search_path vacío: un SET de
  -- más podría cambiar la identidad que ve auth.uid(); Codex f3a r1). ACL explícita: postgres y
  -- authenticated, y authenticated solo EXECUTE y sin opción de concederlo. Permisos EFECTIVOS:
  -- authenticated la ejecuta; anon y service_role no.
  if (
    exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid = v_puerta and p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.provolatile = 's'
        and p.proconfig = array['search_path=""']::text[]
        and p.proacl is not null
    )
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = v_puerta
                      and (a.grantee not in ('postgres'::pg_catalog.regrole, 'authenticated'::pg_catalog.regrole)
                           or (a.grantee = 'authenticated'::pg_catalog.regrole
                               and (a.is_grantable or a.privilege_type <> 'EXECUTE'))))
    and pg_catalog.has_function_privilege('authenticated', v_puerta, 'EXECUTE')
    and not pg_catalog.has_function_privilege('anon', v_puerta, 'EXECUTE')
    and not pg_catalog.has_function_privilege('service_role', v_puerta, 'EXECUTE')
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lectura: la puerta no quedó DEFINER/STABLE/postgres/solo search_path vacío/EXECUTE solo authenticated y sin opción de concederlo';
  end if;

  -- Privadas: INVOKER, dueño postgres, configuración EXACTA, ACL explícita solo de postgres y
  -- permisos EFECTIVOS en cero para los tres roles de la API.
  if (
    (select count(*) from pg_catalog.pg_proc p
      where p.oid = any (v_privadas) and not p.prosecdef and p.proowner = 'postgres'::pg_catalog.regrole
        and p.proconfig = array['search_path=""']::text[]
        and p.proacl is not null) = 3
    and not exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
                    where p.oid = any (v_privadas) and a.grantee <> 'postgres'::pg_catalog.regrole)
    and not exists (
      select 1
      from pg_catalog.unnest(v_privadas) f(fn), pg_catalog.unnest(array['anon', 'authenticated', 'service_role']) r(rol)
      where pg_catalog.has_function_privilege(r.rol, f.fn, 'EXECUTE'))
    and (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_nucleo) = 's'
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lectura: los ayudantes privados no quedaron INVOKER/solo search_path vacío/sin EXECUTE para la API';
  end if;

  -- Ninguna cuenta filas (censo de contadores crudos de leads y citas).
  if exists (select 1 from pg_catalog.pg_proc p
             where (p.oid = v_puerta or p.oid = any (v_privadas)) and p.prosrc ~* '(count|sum)\s*\(') then
    raise exception 'POSTFLIGHT potencial_lectura: una de las funciones usa un agregado de conteo';
  end if;

  -- Contrato de la próxima corrida y de la próxima bajada, a mano (no depende de la fecha de hoy).
  if (
    private.potencial_proxima_corrida('2026-10-05 05:39:59-05'::timestamptz) = '2026-10-05'::date
    and private.potencial_proxima_corrida('2026-10-05 05:40:00-05'::timestamptz) = '2026-10-06'::date
    and private.potencial_proxima_corrida('2026-10-05 23:59:59-05'::timestamptz) = '2026-10-06'::date
    and private.potencial_proxima_corrida('2026-10-06 00:00:00-05'::timestamptz) = '2026-10-06'::date
    and (select b.baja_a::text || '@' || b.baja_el::text
         from private.potencial_proxima_baja('estrella', '2026-10-05', '2026-10-06') b) = 'tibio@2026-10-11'
    and (select b.baja_a::text || '@' || b.baja_el::text
         from private.potencial_proxima_baja('estrella', '2026-10-05', '2026-10-17') b) = 'frio@2026-10-17'
    and (select b.baja_a::text || '@' || b.baja_el::text
         from private.potencial_proxima_baja('tibio', '2026-10-05', '2026-10-06') b) = 'frio@2026-10-17'
    and not exists (select 1 from private.potencial_proxima_baja('frio', '2026-10-05', '2026-10-06'))
  ) is not true then
    raise exception 'POSTFLIGHT potencial_lectura: la próxima corrida o la próxima bajada no son las acordadas';
  end if;

  -- La próxima corrida supone el horario del job de la fase 2: si no es ese, se niega.
  if pg_catalog.to_regclass('cron.job') is not null then
    if (select count(*) from cron.job j
         where j.jobname = 'crm-potencial-lead-caducidad' and j.schedule = '10,40 10 * * *' and j.active) <> 1 then
      raise exception 'POSTFLIGHT potencial_lectura: el job crm-potencial-lead-caducidad no tiene el horario 10,40 10 * * * con el que se calcula la próxima corrida';
    end if;
  end if;

  -- El núcleo no acepta un actor que no sea el de la sesión (aquí no hay sesión de usuario).
  begin
    perform private.potencial_lectura('00000000-0000-0000-0000-000000000001'::uuid, null,
                                      '2026-10-06'::date, pg_catalog.now(), '2026-10-06'::date);
    raise exception 'POSTFLIGHT potencial_lectura: el núcleo aceptó un actor que no es el de la sesión' using errcode = 'P0001';
  exception when insufficient_privilege then
    null;
  end;

  raise notice 'potencial_lectura OK: 3 ayudantes INVOKER sin EXECUTE de la API, puerta DEFINER STABLE solo authenticated, sin conteos, horario del job comprobado.';
end;
$postflight$;

commit;
```

### supabase/scripts/potencial-lead/verificar-lectura.sql
```sql
-- VERIFICACIÓN (solo lectura, termina SIEMPRE en raise) de 20261001151704_crm_potencial_lead_lectura.
-- Se corre en producción después de aplicar y registrar. No escribe nada.
-- Permisos EFECTIVOS con has_function_privilege (Codex f3a r1): una ACL nula significa «PUBLIC
-- ejecuta», y contar filas de aclexplode la daría por buena.
do $v$
declare
  v_puerta pg_catalog.regprocedure := 'crm.potencial_leads_fn(uuid[])'::pg_catalog.regprocedure;
  v_privadas pg_catalog.regprocedure[] := array[
    'private.potencial_lectura(uuid,uuid[],date,timestamp with time zone,date)'::pg_catalog.regprocedure,
    'private.potencial_proxima_baja(crm.nivel_potencial,date,date)'::pg_catalog.regprocedure,
    'private.potencial_proxima_corrida(timestamp with time zone)'::pg_catalog.regprocedure
  ];
  v_ejecutan text; v_ajenos int; v_acl_nula int; v_forma text; v_bandera boolean; v_marcas int; v_registro text; v_job text;
begin
  select string_agg(r.rol, ',' order by r.rol) into v_ejecutan
    from unnest(array['anon', 'authenticated', 'service_role']) r(rol)
   where has_function_privilege(r.rol, v_puerta, 'EXECUTE');
  select count(*) into v_ajenos
    from unnest(v_privadas) f(fn), unnest(array['anon', 'authenticated', 'service_role']) r(rol)
   where has_function_privilege(r.rol, f.fn, 'EXECUTE');
  select count(*) into v_acl_nula from pg_proc p where (p.oid = v_puerta or p.oid = any (v_privadas)) and p.proacl is null;
  select (case when p.prosecdef then 'DEFINER' else 'INVOKER' end) || '/' || p.provolatile::text || '/' || coalesce(array_to_string(p.proconfig, ','), '')
    into v_forma from pg_proc p where p.oid = v_puerta;
  select f.activo into v_bandera from crm.multiempresa_flags f where f.nombre = 'potencial_lead';
  select count(*) into v_marcas from crm.lead_potencial;
  select coalesce(max(name), '(sin registrar)') into v_registro
    from supabase_migrations.schema_migrations where version = '20261001151704';
  if to_regclass('cron.job') is not null then
    select coalesce((select schedule || ' activo=' || active::text from cron.job where jobname = 'crm-potencial-lead-caducidad'), '(sin job)') into v_job;
  else
    v_job := '(sin pg_cron)';
  end if;
  raise exception 'VERIFICAR potencial_lectura: ejecutan la puerta [%] (debe ser authenticated), EXECUTE de la API en los 3 ayudantes % (debe ser 0), funciones con ACL nula % (debe ser 0), forma [%] (debe ser DEFINER/s/search_path=""), job [%] (debe ser 10,40 10 * * * activo=true), bandera %, marcas %, registro %',
    coalesce(v_ejecutan, '(ninguno)'), v_ajenos, v_acl_nula, coalesce(v_forma, '(no existe)'), v_job, coalesce(v_bandera::text, '(no existe)'), v_marcas, v_registro;
end $v$;
```

### supabase/scripts/potencial-lead/reversa-lectura.sql
```sql
-- REVERSA de 20261001151704_crm_potencial_lead_lectura (fase 3, entrega A).
-- Quita la puerta de lectura, su núcleo y sus dos ayudantes. No hay datos que perder: las marcas y
-- su historial son de las fases 1 y 2 y se quedan. Con la puerta quitada, la pantalla recibe
-- «función inexistente» y lo trata como potencial apagado (no pinta nada). Conserva la fila de
-- schema_migrations: anotarlo en MIGRACIONES.md. Debe correr ANTES que las reversas de las fases 2 y 1.
begin;
set local lock_timeout = '5s';
do $chk$
begin
  if (
    pg_catalog.to_regprocedure('crm.potencial_leads_fn(uuid[])') is not null
    and pg_catalog.to_regprocedure('private.potencial_lectura(uuid,uuid[],date,timestamp with time zone,date)') is not null
    and pg_catalog.to_regprocedure('private.potencial_proxima_baja(crm.nivel_potencial,date,date)') is not null
    and pg_catalog.to_regprocedure('private.potencial_proxima_corrida(timestamp with time zone)') is not null
  ) is not true then
    raise exception 'REVERSA potencial_lectura: la puerta de lectura no está aplicada';
  end if;
end;
$chk$;

drop function crm.potencial_leads_fn(uuid[]);
drop function private.potencial_lectura(uuid, uuid[], date, timestamptz, date);
drop function private.potencial_proxima_baja(crm.nivel_potencial, date, date);
drop function private.potencial_proxima_corrida(timestamptz);

do $post$
begin
  if exists (
    select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where (n.nspname = 'crm' and p.proname = 'potencial_leads_fn')
       or (n.nspname = 'private' and p.proname in ('potencial_lectura', 'potencial_proxima_baja', 'potencial_proxima_corrida'))
  ) then
    raise exception 'REVERSA potencial_lectura: quedaron funciones';
  end if;
  raise notice 'REVERSA potencial_lectura OK: sin puerta ni ayudantes de lectura (las marcas se conservan).';
end;
$post$;
commit;
```

### supabase/scripts/potencial-lead/reversa-caducidad.sql (fase 2; se añadió la guarda de la lectura)
```sql
-- REVERSA de 20260930235917_crm_potencial_lead_caducidad (fase 2).
-- Desprograma el job (si existe) y quita las cuatro funciones. Los eventos con motivo 'caducidad'
-- ya escritos SE QUEDAN: son historial inmutable, y los niveles bajados no se «suben» solos (una
-- persona vuelve a marcar si quiere). Conserva la fila de schema_migrations: anotarlo en
-- MIGRACIONES.md. Debe correr ANTES que la reversa de la fase 1 y DESPUÉS de reversa-lectura.sql (se
-- niega si la puerta de lectura de la fase 3A sigue aplicada).
-- Codex f2 r1 F3: todo lo que nombra cron.job va en un IF propio (plpgsql prepara cada expresión al
-- llegar a ella), para que funcione también en una base sin pg_cron.
begin;
set local lock_timeout = '5s';
do $chk$
begin
  if (
    pg_catalog.to_regprocedure('private.potencial_caducar(date,timestamp with time zone,integer)') is not null
    and pg_catalog.to_regprocedure('private.dias_lunes_a_sabado(date,date)') is not null
  ) is not true then
    raise exception 'REVERSA potencial_caducidad: la fase 2 no está aplicada';
  end if;
  -- La puerta de lectura (fase 3A) calcula con estas funciones: quitarlas con ella puesta la dejaría
  -- expuesta y rota (auditor-rls f3a P3-2). Primero reversa-lectura.sql.
  if exists (
    select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where (n.nspname = 'crm' and p.proname = 'potencial_leads_fn')
       or (n.nspname = 'private' and p.proname in ('potencial_lectura', 'potencial_proxima_baja', 'potencial_proxima_corrida'))
  ) then
    raise exception 'REVERSA potencial_caducidad: la puerta de lectura (20261001151704) sigue aplicada; corre antes reversa-lectura.sql';
  end if;
  if pg_catalog.to_regclass('cron.job') is not null and pg_catalog.to_regprocedure('cron.unschedule(text)') is not null then
    if exists (select 1 from cron.job where jobname = 'crm-potencial-lead-caducidad') then
      perform cron.unschedule('crm-potencial-lead-caducidad');
    end if;
  end if;
end;
$chk$;

drop function private.potencial_caducar(date, timestamptz, integer);
drop function private.potencial_nivel_tras(crm.nivel_potencial, integer);
drop function private.potencial_reloj(uuid, timestamptz, timestamptz);
drop function private.dias_lunes_a_sabado(date, date);

do $post$
begin
  if (
    pg_catalog.to_regprocedure('private.potencial_caducar(date,timestamp with time zone,integer)') is null
    and pg_catalog.to_regprocedure('private.potencial_nivel_tras(crm.nivel_potencial,integer)') is null
    and pg_catalog.to_regprocedure('private.potencial_reloj(uuid,timestamp with time zone,timestamp with time zone)') is null
    and pg_catalog.to_regprocedure('private.dias_lunes_a_sabado(date,date)') is null
  ) is not true then
    raise exception 'REVERSA potencial_caducidad: quedaron funciones';
  end if;
  if pg_catalog.to_regclass('cron.job') is not null then
    if exists (select 1 from cron.job where jobname = 'crm-potencial-lead-caducidad') then
      raise exception 'REVERSA potencial_caducidad: quedó el job';
    end if;
  end if;
  raise notice 'REVERSA potencial_caducidad OK: sin job ni funciones (el historial se conserva).';
end;
$post$;
commit;
```

### supabase/scripts/test-rls.mjs (bloque de lectura, reescrito)
```js
// ── Potencial del lead (20261001151704): puerta de LECTURA crm.potencial_leads_fn ─────────────
// Solo lectura: no escribe marcas. Dos tiempos:
//   1 · Bandera 'potencial_lead' APAGADA (así nace): la puerta admite y devuelve habilitada=false
//       sin ítems.
//   2 · El bloque la ENCIENDE fuera de banda y la repone (auditor-rls f3a P2-1: sin esto la
//       comparación de abajo era inalcanzable en una corrida verde, porque el bloque de marcar exige
//       la bandera apagada). Encendida, lo que entrega la puerta debe ser EXACTAMENTE lo que la RLS de
//       crm.leads deja ver a ese actor, sin repetidos (Codex f3a r1): la puerta es DEFINER y copia la
//       policy leads_select, y esta comparación es la que caza un espejo desincronizado DESPUÉS de
//       aplicar (el preflight de la migración solo protege el instante de aplicar).
// Denegados en los dos tiempos: usuario dado de baja, authenticated ajeno al CRM, 201 ids, anon y
// service_role. El calendario («baja el…»), «puede marcar» contra la puerta de marcar y los mutantes
// viven en supabase/scripts/potencial-lead/prueba-lectura.sql y banco/ciclo-fase3a.sh. Salto RUIDOSO
// si la puerta no está en esta base o falta la vía fuera de banda; con CRM_RLS_EXIGE_POTENCIAL=1 es
// un FALLO.
async function testPotencialLectura(sessions, seed) {
  console.log('\n— Potencial del lead: puerta de lectura (sin escribir marcas) —');
  const saltar = (msg) => {
    if (process.env.CRM_RLS_EXIGE_POTENCIAL === '1') fail(msg);
    else console.log(`  ${msg}`);
  };
  const leerBandera = () => contarFueraDeBanda('potencial lectura: bandera',
    `select coalesce((select activo::int from crm.multiempresa_flags where nombre = 'potencial_lead'), 0)`);
  const contarMarcas = () => contarFueraDeBanda('potencial lectura: marcas', `select count(*)::int from crm.lead_potencial`);
  let aplicada;
  let encendida;
  let marcasAntes;
  try {
    aplicada = contarFueraDeBanda('potencial lectura: puerta aplicada',
      `select (to_regprocedure('crm.potencial_leads_fn(uuid[])') is not null)::int`);
    encendida = aplicada === 1 ? leerBandera() : 0;
    marcasAntes = aplicada === 1 ? contarMarcas() : 0;
  } catch (error) {
    saltar(`⚠ Lectura del potencial SALTADA: sin vía fuera de banda para leer la bandera (${error?.message ?? String(error)})`);
    return;
  }
  if (aplicada !== 1) {
    saltar('⚠ crm.potencial_leads_fn NO desplegada en esta base: bloque de lectura del potencial SALTADO (no probado)');
    return;
  }
  if (encendida !== 0) {
    fail('potencial lectura: la bandera potencial_lead está ENCENDIDA al empezar; el bloque la espera apagada y la enciende él mismo');
    return;
  }

  const FN = 'potencial_leads_fn';
  const ROLES = ['vend1', 'vend3', 'sup1', 'sup1Nested', 'sup2', 'gerencia', 'coordinador', 'directorio'];
  const ids = [...seed.leadByName.values()].map((lead) => lead.id).slice(0, 200);
  const idDe = (clave) => seed.leadByName.get(LEAD_BY_KEY[clave].name)?.id;
  const leer = (cliente, lista = ids) => cliente.schema('crm').rpc(FN, { p_lead_ids: lista });
  const DENEGADO = /permission denied|denegado/i;
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-potencial-lectura'));
  const denegados = async (momento) => {
    await expectExpectedFailure(`potencial lectura vendInactive (${momento}) → 42501: la baja revoca la lectura`,
      leer(sessions.vendInactive.client), ['42501'], /no autorizado/i);
    await expectExpectedFailure(`potencial lectura clientBank, authenticated ajeno al CRM (${momento}) → 42501`,
      leer(sessions.clientBank.client), ['42501'], /no autorizado/i);
    await expectExpectedFailure(`potencial lectura con 201 ids (${momento}) → 22023`,
      leer(sessions.vend1.client, Array.from({ length: 201 }, () => randomUUID())), ['22023'], /m[aá]ximo 200/i);
    await expectExpectedFailure(`potencial lectura anon (${momento}) → 42501 (sin EXECUTE)`, leer(anon), ['42501'], DENEGADO);
    await expectExpectedFailure(`potencial lectura service_role (${momento}) → 42501 (sin EXECUTE)`, leer(admin), ['42501'], DENEGADO);
  };

  // 1 · Bandera APAGADA: los admitidos reciben el sobre vacío.
  for (const clave of ROLES) {
    const { data, error } = await leer(sessions[clave].client);
    if (error) {
      fail(`potencial lectura ${clave} (apagada): error inesperado ${error.code ?? ''} ${error.message}`);
      continue;
    }
    check(data?.version === 1 && data?.habilitada === false && Array.isArray(data?.items) && data.items.length === 0,
      `potencial lectura ${clave}: bandera apagada → {version:1, habilitada:false, items:[]}`,
      JSON.stringify(data ?? null).slice(0, 200));
  }
  await denegados('bandera apagada');

  // 2 · Bandera ENCENDIDA fuera de banda; se repone pase lo que pase.
  const fijarBandera = (valor) => ejecutarFueraDeBanda('bandera potencial_lead (lectura)',
    `update crm.multiempresa_flags set activo = ${valor ? 'true' : 'false'}, actualizado_en = now() where nombre = 'potencial_lead';`);
  try {
    fijarBandera(true);
    for (const clave of ROLES) {
      const { data, error } = await leer(sessions[clave].client);
      if (error) {
        fail(`potencial lectura ${clave} (encendida): error inesperado ${error.code ?? ''} ${error.message}`);
        continue;
      }
      if (!check(data?.version === 1 && data?.habilitada === true && Array.isArray(data?.items),
        `potencial lectura ${clave}: bandera encendida → {version:1, habilitada:true, items:[…]}`,
        JSON.stringify(data ?? null).slice(0, 200))) continue;
      const visibles = await sessions[clave].client.schema('crm').from('leads').select('id').in('id', ids);
      if (visibles.error) {
        fail(`potencial lectura ${clave}: no se pudo leer crm.leads para comparar (${visibles.error.message})`);
        continue;
      }
      const dePuerta = data.items.map((item) => item.lead_id);
      check(new Set(dePuerta).size === dePuerta.length, `potencial lectura ${clave}: ningún lead repetido en los ítems`,
        `${dePuerta.length} ítems, ${new Set(dePuerta).size} leads distintos`);
      check(dePuerta.length === visibles.data.length
        && [...dePuerta].sort().join(',') === visibles.data.map((fila) => fila.id).sort().join(','),
      `potencial lectura ${clave}: los ítems son EXACTAMENTE los leads que su RLS deja ver`,
      `puerta ${dePuerta.length} vs RLS ${visibles.data.length}`);
      if (['gerencia', 'coordinador', 'directorio'].includes(clave)) {
        check(data.items.every((item) => item.puede_marcar === false), `potencial lectura ${clave}: ve pero no puede marcar ninguno`);
      }
    }
    // «Puede marcar», en los casos que el fixture permite (los cerrados e inactivos viven en la sintética).
    const itemDe = async (clave, leadId) => {
      const { data, error } = await leer(sessions[clave].client, [leadId]);
      if (error) return { error };
      return data?.items?.[0] ?? null;
    };
    const juan = idDe('juan');
    check((await itemDe('vend1', juan))?.puede_marcar === true, 'potencial lectura vend1: puede marcar su lead (juan)');
    check((await itemDe('sup1', juan))?.puede_marcar === true, 'potencial lectura sup1: puede marcar el lead de su analista (juan)');
    check((await itemDe('gerencia', juan))?.puede_marcar === false, 'potencial lectura gerencia: ve a juan y no puede marcarlo');
    check((await itemDe('vend3', juan)) === null, 'potencial lectura vend3: el lead de otro equipo (juan) no viaja');
    check((await itemDe('sup1', idDe('luis')))?.puede_marcar === true, 'potencial lectura sup1: puede marcar el lead parqueado en su bandeja (luis)');
    check((await itemDe('vend1', idDe('luis'))) === null, 'potencial lectura vend1: el lead parqueado en la bandeja de su supervisor (luis) no viaja');
    await denegados('bandera encendida');
  } finally {
    try {
      fijarBandera(false);
    } catch (error) {
      fail(`potencial lectura: no se pudo reponer la bandera potencial_lead — ${error?.message ?? String(error)}`);
    }
  }
  check(leerBandera() === 0, 'potencial lectura: la bandera quedó APAGADA, como estaba');
  check(contarMarcas() === marcasAntes, 'potencial lectura: el bloque no creó ni borró marcas');
}

```

### supabase/scripts/potencial-lead/prueba-lectura.sql
```sql
-- Prueba sintética de 20261001151704_crm_potencial_lead_lectura (fase 3, entrega A).
-- SOLO en un banco, como supabase_admin, en UNA transacción que termina en raise (no deja nada).
-- ⚠️ Nunca se llama a una función sin EXECUTE bajo `set role` (tumba Postgres 17.6 con plan_filter):
-- el núcleo se llama como supabase_admin con la sesión del actor fijada; la puerta, como authenticated.
--
-- Mundo: gerencia G · supervisor S1 con sub-supervisor S1n · analista V1 (de S1) y V1n (de S1n) ·
-- supervisor S2 con analista V2 · coordinador C · directorio D · X con equipo inactivo ·
-- DH directorio HISTÓRICO (perfil de directorio sin fila en crm.equipo: lector global por la vía
-- vieja) · XP con el PERFIL inactivo aunque su fila de equipo siga activa · P usuario solo del
-- portal (sin fila en crm.equipo) · DM pareja desalineada (perfil de directorio con equipo vendedor).
-- Calendario simulado (hora de Lima): las marcas se ponen el lunes 2026-10-05 10:00.
--   L1  V1  contactado  estrella (antes tibio)      L1n V1n nuevo       tibio
--   L2  V2  contactado  estrella + contacto jue 08  LP  parqueado en S1 frío
--   LC  V1  convertido  estrella (congelada)        LD  V1  descartado  tibio (congelada)
--   LI  V1  INACTIVO    estrella (nadie lo ve)      L3  V1  contactado  sin marca
--   LPV parqueado con «supervisor» V1, sin marca    LK  V1  contactado  tibio que BAJÓ SOLA de estrella
--   LZ  V1  contactado  estrella marcada vie 09 21:00 Lima (en UTC ya es sábado)
--   LS  SIN ASIGNAR (sin analista ni supervisor), sin marca: solo lo ven gerencia y directorio, y
--       es el único lead que depende de la rama «rol = gerencia» de la policy.
--   NADA: un id que no existe.
begin;
set local lock_timeout = '5s';

create temp table act (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into act (k) values ('G'), ('S1'), ('S1n'), ('V1'), ('V1n'), ('S2'), ('V2'), ('C'), ('D'), ('X'), ('DH'), ('XP'), ('P'), ('DM');
create temp table lds (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into lds (k) values ('L1'), ('L1n'), ('L2'), ('LP'), ('LC'), ('LD'), ('LI'), ('L3'), ('LPV'), ('LK'), ('LZ'), ('LS'), ('NADA');
create temp table res (n serial, caso text, esperado text, obtenido text) on commit drop;

create function pg_temp.a(p_k text) returns uuid language sql as $$ select id from act where k = p_k $$;
create function pg_temp.l(p_k text) returns uuid language sql as $$ select id from lds where k = p_k $$;
create function pg_temp.todos() returns uuid[] language sql as $$ select array_agg(id) from lds $$;
create function pg_temp.esperar(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$
  insert into res (caso, esperado, obtenido) values (p_caso, p_esperado, coalesce(p_obtenido, '(null)'))
$$;
create function pg_temp.lima(p_texto text) returns timestamptz language sql as $$
  select (p_texto::timestamp at time zone 'America/Lima')
$$;

-- Fixtures sin disparadores (solo filas que cumplen los CHECK).
set local session_replication_role = replica;
insert into auth.users (id, email) select id, lower(k) || '@lectura.banco' from act;
insert into public.perfiles (id, nombre_completo, rol, activo)
  select id, 'LECTURA ' || k, case when k in ('D', 'DH', 'DM') then 'directorio' when k = 'G' then 'admin' else 'analista' end, k <> 'XP' from act;
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
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, asignado_supervisor_id, activo, motivo_descarte) values
  (pg_temp.l('L1'),  'LECTURA L1',  '+51987640001', 'landing', 50000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('L1n'), 'LECTURA L1N', '+51987640002', 'landing', 15000, 'PEN', 'nuevo',      pg_temp.a('V1n'), null, true, null),
  (pg_temp.l('L2'),  'LECTURA L2',  '+51987640003', 'landing', 30000, 'PEN', 'contactado', pg_temp.a('V2'),  null, true, null),
  (pg_temp.l('LP'),  'LECTURA LP',  '+51987640004', 'landing', 12000, 'PEN', 'nuevo',      null, pg_temp.a('S1'), true, null),
  (pg_temp.l('LC'),  'LECTURA LC',  '+51987640005', 'landing', 20000, 'PEN', 'convertido', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LD'),  'LECTURA LD',  '+51987640006', 'landing', 20000, 'PEN', 'descartado', pg_temp.a('V1'),  null, true, 'sin_interes'),
  (pg_temp.l('LI'),  'LECTURA LI',  '+51987640007', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, false, null),
  (pg_temp.l('L3'),  'LECTURA L3',  '+51987640008', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LPV'), 'LECTURA LPV', '+51987640009', 'landing', 20000, 'PEN', 'nuevo',      null, pg_temp.a('V1'), true, null),
  (pg_temp.l('LK'),  'LECTURA LK',  '+51987640010', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LZ'),  'LECTURA LZ',  '+51987640011', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LS'),  'LECTURA LS',  '+51987640012', 'landing', 20000, 'PEN', 'nuevo',      null, null, true, null);
insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en) values
  (pg_temp.l('L1'),  'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('L1n'), 'tibio',    'manual',    pg_temp.a('S1n'), pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('L2'),  'estrella', 'manual',    pg_temp.a('V2'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LP'),  'frio',     'manual',    pg_temp.a('S1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LC'),  'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LD'),  'tibio',    'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LI'),  'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LK'),  'tibio',    'caducidad', pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LZ'),  'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-09 21:00'));
insert into crm.lead_potencial_eventos (lead_id, nivel_anterior, nivel_nuevo, motivo, por, creado_en) values
  (pg_temp.l('L1'),  null,       'tibio',    'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-02 09:00')),
  (pg_temp.l('L1'),  'tibio',    'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('L1n'), null,       'tibio',    'manual',    pg_temp.a('S1n'), pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('L2'),  null,       'estrella', 'manual',    pg_temp.a('V2'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LP'),  null,       'frio',     'manual',    pg_temp.a('S1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LC'),  null,       'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LD'),  null,       'tibio',    'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LI'),  null,       'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LK'),  null,       'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LK'),  'estrella', 'tibio',    'caducidad', null,             pg_temp.lima('2026-10-11 05:10')),
  (pg_temp.l('LZ'),  null,       'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-09 21:00'));
-- L2: un CONTACTO el jueves 10-08 15:00 reinicia su reloj.
insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en) values
  (pg_temp.l('L2'), 'llamada_no_contestada', 'prueba de lectura', pg_temp.a('V2'), pg_temp.lima('2026-10-08 15:00'));
set local session_replication_role = origin;

-- Identidad de la sesión, en las DOS formas (producción lee request.jwt.claims; la imagen del banco
-- solo request.jwt.claim.sub).
create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

-- El núcleo con calendario simulado. Por defecto, justo antes de la corrida de las 05:10 Lima de
-- p_hoy (la próxima corrida es hoy); p_proxima permite ensayar «ya pasó la corrida de hoy».
create function pg_temp.leer(p_actor uuid, p_ids uuid[], p_hoy date, p_corte timestamptz default null, p_proxima date default null) returns jsonb language plpgsql as $f$
begin
  perform pg_temp.sesion(p_actor);
  return private.potencial_lectura(p_actor, p_ids, p_hoy, coalesce(p_corte, (p_hoy::timestamp + time '05:10') at time zone 'America/Lima'), coalesce(p_proxima, p_hoy));
end $f$;

-- Un ítem resumido: nivel/origen/nivel_marcado · días · baja_a@baja_el · puede.
create function pg_temp.item(p_items jsonb, p_k text) returns text language sql as $$
  select coalesce((
    select coalesce(i ->> 'nivel', '-') || '/' || coalesce(i ->> 'origen', '-') || '/' || coalesce(i ->> 'nivel_marcado', '-')
           || ' d=' || coalesce(i ->> 'dias_sin_gestion', '-')
           || ' baja=' || coalesce(i ->> 'baja_a', '-') || '@' || coalesce(i ->> 'baja_el', '-')
           || ' puede=' || (i ->> 'puede_marcar')
    from jsonb_array_elements(p_items) i where (i ->> 'lead_id')::uuid = pg_temp.l(p_k)), '(no viaja)')
$$;
-- Las claves de los leads que trae una lista de ítems.
create function pg_temp.claves(p_items jsonb) returns text language sql as $$
  select coalesce(string_agg(d.k, ',' order by d.k), '(ninguno)')
  from jsonb_array_elements(p_items) i join lds d on d.id = (i ->> 'lead_id')::uuid
$$;

-- La puerta, como la llama la pantalla: authenticated. Devuelve el sobre o {"error": SQLSTATE}.
create function pg_temp.puerta(p_actor uuid, p_ids uuid[]) returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    v := crm.potencial_leads_fn(p_ids);
    reset role;
    return v;
  exception when others then
    reset role;
    return jsonb_build_object('error', sqlstate);
  end;
end $f$;

-- Lo que la RLS REAL de crm.leads deja ver a un actor (la vara con la que se mide el espejo).
create function pg_temp.ve_rls(p_actor uuid) returns text language plpgsql as $f$
declare v_ids uuid[] := pg_temp.todos(); v_vistos uuid[];
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    select array_agg(l.id) into v_vistos from crm.leads l where l.id = any (v_ids);
  exception when others then
    reset role;
    return 'error ' || sqlstate;
  end;
  reset role;
  return coalesce((select string_agg(d.k, ',' order by d.k) from lds d where d.id = any (v_vistos)), '(ninguno)');
end $f$;

-- ¿Puede marcar DE VERDAD? Se intenta por la puerta de la fase 1 y se deshace (subtransacción).
create function pg_temp.puede_real(p_actor uuid, p_lead uuid) returns boolean language plpgsql as $f$
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    perform crm.marcar_potencial_lead_fn(p_lead, 'tibio'::crm.nivel_potencial);
    raise exception 'deshacer' using errcode = 'P9999';
  exception
    when sqlstate 'P9999' then reset role; return true;
    when others then reset role; return false;
  end;
end $f$;
-- «clave:t/f» de lo que la puerta dice que el actor puede marcar, y de lo que puede de verdad.
create function pg_temp.puede_puerta(p_actor uuid) returns text language sql as $$
  select coalesce(string_agg(d.k || ':' || left(i ->> 'puede_marcar', 1), ',' order by d.k), '(ninguno)')
  from jsonb_array_elements(pg_temp.puerta(p_actor, pg_temp.todos()) -> 'items') i
  join lds d on d.id = (i ->> 'lead_id')::uuid
$$;
create function pg_temp.puede_verdad(p_actor uuid) returns text language plpgsql as $f$
declare v text; v_items jsonb := pg_temp.puerta(p_actor, pg_temp.todos()) -> 'items';
begin
  select coalesce(string_agg(d.k || ':' || left(pg_temp.puede_real(p_actor, d.id)::text, 1), ',' order by d.k), '(ninguno)') into v
  from jsonb_array_elements(v_items) i join lds d on d.id = (i ->> 'lead_id')::uuid;
  return v;
end $f$;

do $prueba$
declare
  v jsonb;
  v_n integer;
  r record;
  v_muchos uuid[];
begin
  -- ── Permisos (del catálogo: nunca se llama sin EXECUTE bajo set role) ──
  perform pg_temp.esperar('EXECUTE de la puerta: authenticated sí; anon y service_role no', 'true/false/false',
    has_function_privilege('authenticated', 'crm.potencial_leads_fn(uuid[])', 'EXECUTE')::text || '/' ||
    has_function_privilege('anon', 'crm.potencial_leads_fn(uuid[])', 'EXECUTE')::text || '/' ||
    has_function_privilege('service_role', 'crm.potencial_leads_fn(uuid[])', 'EXECUTE')::text);
  perform pg_temp.esperar('EXECUTE del núcleo: nadie de la API', 'false/false/false',
    has_function_privilege('authenticated', 'private.potencial_lectura(uuid,uuid[],date,timestamptz,date)', 'EXECUTE')::text || '/' ||
    has_function_privilege('anon', 'private.potencial_lectura(uuid,uuid[],date,timestamptz,date)', 'EXECUTE')::text || '/' ||
    has_function_privilege('service_role', 'private.potencial_lectura(uuid,uuid[],date,timestamptz,date)', 'EXECUTE')::text);
  perform pg_temp.esperar('EXECUTE de los dos ayudantes de fechas: nadie de la API', '0',
    (select count(*)::text from unnest(array['anon', 'authenticated', 'service_role']) rr(rol),
            unnest(array['private.potencial_proxima_baja(crm.nivel_potencial,date,date)', 'private.potencial_proxima_corrida(timestamptz)']) f(fn)
      where has_function_privilege(rr.rol, f.fn, 'EXECUTE')));

  perform pg_temp.esperar('los roles de puente (métricas y gestión diaria) no ejecutan ninguno de los 3 ayudantes privados', '0',
    (select count(*)::text from unnest(array['crm_metricas_bridge', 'crm_gestion_diaria_lector']) rr(rol),
            unnest(array['private.potencial_lectura(uuid,uuid[],date,timestamptz,date)',
                         'private.potencial_proxima_baja(crm.nivel_potencial,date,date)', 'private.potencial_proxima_corrida(timestamptz)']) f(fn)
      where has_function_privilege(rr.rol, f.fn, 'EXECUTE')));
  -- crm_gestion_diaria_lector es miembro de authenticated a propósito (20260922184459): hereda el
  -- EXECUTE de toda puerta. No inicia sesión ni lleva JWT: sin sesión, la puerta lo rechaza.
  perform pg_temp.esperar('EXECUTE de la puerta en los roles de puente: solo el lector, heredado de authenticated', 'false/true',
    has_function_privilege('crm_metricas_bridge', 'crm.potencial_leads_fn(uuid[])', 'EXECUTE')::text || '/' ||
    has_function_privilege('crm_gestion_diaria_lector', 'crm.potencial_leads_fn(uuid[])', 'EXECUTE')::text);
  begin
    perform pg_temp.sesion(null);
    set local role crm_gestion_diaria_lector;
    perform crm.potencial_leads_fn(pg_temp.todos());
    reset role;
    perform pg_temp.esperar('el rol lector de gestión diaria, sin sesión → 42501', '42501', 'sin error');
  exception when others then
    reset role;
    perform pg_temp.esperar('el rol lector de gestión diaria, sin sesión → 42501', '42501', sqlstate);
  end;

  -- ── Bandera APAGADA: la puerta admite, pero no entrega nada ──
  perform pg_temp.esperar('bandera apagada al empezar', 'false', (select activo::text from crm.multiempresa_flags where nombre = 'potencial_lead'));
  perform pg_temp.esperar('apagada: V1 recibe habilitada=false y sin ítems', '{"items": [], "version": 1, "habilitada": false}',
    pg_temp.puerta(pg_temp.a('V1'), pg_temp.todos())::text);
  perform pg_temp.esperar('apagada: gerencia igual', '{"items": [], "version": 1, "habilitada": false}',
    pg_temp.puerta(pg_temp.a('G'), pg_temp.todos())::text);
  perform pg_temp.esperar('apagada: sin sesión sigue siendo 42501', '{"error": "42501"}', pg_temp.puerta(null, pg_temp.todos())::text);
  perform pg_temp.esperar('apagada: X (equipo inactivo) sigue siendo 42501', '{"error": "42501"}', pg_temp.puerta(pg_temp.a('X'), pg_temp.todos())::text);

  -- ── Bandera ENCENDIDA ──
  update crm.multiempresa_flags set activo = true where nombre = 'potencial_lead';

  -- Admisión y validación de la puerta.
  perform pg_temp.esperar('sin sesión → 42501', '{"error": "42501"}', pg_temp.puerta(null, pg_temp.todos())::text);
  perform pg_temp.esperar('X (equipo inactivo) → 42501', '{"error": "42501"}', pg_temp.puerta(pg_temp.a('X'), pg_temp.todos())::text);
  perform pg_temp.esperar('XP (perfil inactivo con equipo activo) → 42501', '{"error": "42501"}', pg_temp.puerta(pg_temp.a('XP'), pg_temp.todos())::text);
  perform pg_temp.esperar('P (usuario del portal sin membresía en el CRM) → 42501', '{"error": "42501"}', pg_temp.puerta(pg_temp.a('P'), pg_temp.todos())::text);
  perform pg_temp.esperar('sin ids (null) → encendida y vacía', '{"items": [], "version": 1, "habilitada": true}', pg_temp.puerta(pg_temp.a('V1'), null)::text);
  perform pg_temp.esperar('sin ids (vacío) → encendida y vacía', '{"items": [], "version": 1, "habilitada": true}', pg_temp.puerta(pg_temp.a('V1'), array[]::uuid[])::text);
  select array_agg(gen_random_uuid()) into v_muchos from generate_series(1, 200);
  perform pg_temp.esperar('200 ids → pasa', 'true', (pg_temp.puerta(pg_temp.a('V1'), v_muchos) ->> 'habilitada'));
  perform pg_temp.esperar('201 ids → 22023', '{"error": "22023"}', pg_temp.puerta(pg_temp.a('V1'), v_muchos || gen_random_uuid())::text);
  -- El tope cuenta TODOS los elementos: una matriz de 3 × 67 = 201 no se cuela (auditor-rls f3a).
  perform pg_temp.esperar('matriz 3×67 (201 ids) → 22023', '{"error": "22023"}', pg_temp.puerta(pg_temp.a('V1'),
    (select array_agg(s.fila) from (select array_agg(gen_random_uuid()) as fila from generate_series(1, 201) g group by g % 3) s))::text);
  perform pg_temp.esperar('matriz 2×2 con leads propios: se leen igual', 'L1,L3',
    pg_temp.claves(pg_temp.puerta(pg_temp.a('V1'), array[array[pg_temp.l('L1'), pg_temp.l('L3')], array[pg_temp.l('L2'), pg_temp.l('NADA')]]) -> 'items'));

  -- Forma del sobre y del ítem.
  v := pg_temp.puerta(pg_temp.a('V1'), pg_temp.todos());
  perform pg_temp.esperar('sobre: version, habilitada, items', 'habilitada,items,version', (select string_agg(k, ',' order by k) from jsonb_object_keys(v) k));
  perform pg_temp.esperar('ítem: las 9 claves del contrato', 'baja_a,baja_el,dias_sin_gestion,lead_id,marcado_en,nivel,nivel_marcado,origen,puede_marcar',
    (select string_agg(k, ',' order by k) from jsonb_object_keys(v -> 'items' -> 0) k));
  perform pg_temp.esperar('ítems ordenados por lead_id', 'true',
    ((select array_agg(i ->> 'lead_id') from jsonb_array_elements(v -> 'items') i)
     = (select array_agg(x order by x) from (select i ->> 'lead_id' as x from jsonb_array_elements(v -> 'items') i) s))::text);
  perform pg_temp.esperar('ningún lead repetido en los ítems', 'true',
    ((select count(*) from jsonb_array_elements(v -> 'items') i) = (select count(distinct i ->> 'lead_id') from jsonb_array_elements(v -> 'items') i))::text);
  perform pg_temp.esperar('ids repetidos: un ítem por lead', '1',
    jsonb_array_length(pg_temp.puerta(pg_temp.a('V1'), array[pg_temp.l('L1'), pg_temp.l('L1'), pg_temp.l('L1')]) -> 'items')::text);

  -- ── Visibilidad: lo que entrega la puerta por actor (LI inactivo y NADA no viajan nunca) ──
  perform pg_temp.esperar('V1 ve lo suyo (y LPV, parqueado a su nombre)', 'L1,L3,LC,LD,LK,LPV,LZ', pg_temp.claves(pg_temp.puerta(pg_temp.a('V1'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('V1n ve solo L1n', 'L1n', pg_temp.claves(pg_temp.puerta(pg_temp.a('V1n'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('S1n ve su subárbol', 'L1n', pg_temp.claves(pg_temp.puerta(pg_temp.a('S1n'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('S1 ve su subárbol y su parqueo', 'L1,L1n,L3,LC,LD,LK,LP,LPV,LZ', pg_temp.claves(pg_temp.puerta(pg_temp.a('S1'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('V2 ve solo L2', 'L2', pg_temp.claves(pg_temp.puerta(pg_temp.a('V2'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('S2 ve solo L2', 'L2', pg_temp.claves(pg_temp.puerta(pg_temp.a('S2'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('gerencia ve todo lo vivo, también lo sin asignar', 'L1,L1n,L2,L3,LC,LD,LK,LP,LPV,LS,LZ', pg_temp.claves(pg_temp.puerta(pg_temp.a('G'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('directorio (lector global) ve todo lo vivo', 'L1,L1n,L2,L3,LC,LD,LK,LP,LPV,LS,LZ', pg_temp.claves(pg_temp.puerta(pg_temp.a('D'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('directorio histórico (sin membresía) ve todo lo vivo', 'L1,L1n,L2,L3,LC,LD,LK,LP,LPV,LS,LZ', pg_temp.claves(pg_temp.puerta(pg_temp.a('DH'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('coordinación: admitida y sin leads', '(ninguno)', pg_temp.claves(pg_temp.puerta(pg_temp.a('C'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('S1 no ve el lead sin asignar', '(ninguno)', pg_temp.claves(pg_temp.puerta(pg_temp.a('S1'), array[pg_temp.l('LS')]) -> 'items'));
  perform pg_temp.esperar('V2 preguntando por un lead ajeno: no viaja', '(ninguno)', pg_temp.claves(pg_temp.puerta(pg_temp.a('V2'), array[pg_temp.l('L1')]) -> 'items'));

  -- ── EQUIVALENCIA con la RLS real de crm.leads, actor por actor ──
  for r in select k, id from act where k not in ('X', 'XP', 'P', 'DM') order by k loop
    perform pg_temp.esperar('espejo = RLS real para ' || r.k, pg_temp.ve_rls(r.id), pg_temp.claves(pg_temp.puerta(r.id, pg_temp.todos()) -> 'items'));
  end loop;
  perform pg_temp.esperar('X: la RLS real tampoco le deja ver nada', '(ninguno)', pg_temp.ve_rls(pg_temp.a('X')));
  perform pg_temp.esperar('XP: la RLS real tampoco le deja ver nada', '(ninguno)', pg_temp.ve_rls(pg_temp.a('XP')));
  perform pg_temp.esperar('P: la RLS real tampoco le deja ver nada', '(ninguno)', pg_temp.ve_rls(pg_temp.a('P')));
  perform pg_temp.esperar('DM (perfil de directorio con equipo vendedor): la RLS real no le deja ver nada', '(ninguno)', pg_temp.ve_rls(pg_temp.a('DM')));
  perform pg_temp.esperar('DM: la puerta lo rechaza (una pareja desalineada es una revocación)', '{"error": "42501"}', pg_temp.puerta(pg_temp.a('DM'), pg_temp.todos())::text);

  -- ── puede_marcar: lo que dice la puerta = lo que la puerta de marcar permite de verdad ──
  perform pg_temp.esperar('V1 puede marcar lo abierto y suyo (no cerrados ni parqueo)', 'L1:t,L3:t,LC:f,LD:f,LK:t,LPV:f,LZ:t', pg_temp.puede_puerta(pg_temp.a('V1')));
  perform pg_temp.esperar('S1 puede marcar su subárbol abierto y su parqueo', 'L1:t,L1n:t,L3:t,LC:f,LD:f,LK:t,LP:t,LPV:t,LZ:t', pg_temp.puede_puerta(pg_temp.a('S1')));
  perform pg_temp.esperar('gerencia ve pero no marca', 'L1:f,L1n:f,L2:f,L3:f,LC:f,LD:f,LK:f,LP:f,LPV:f,LS:f,LZ:f', pg_temp.puede_puerta(pg_temp.a('G')));
  perform pg_temp.esperar('directorio ve pero no marca', 'L1:f,L1n:f,L2:f,L3:f,LC:f,LD:f,LK:f,LP:f,LPV:f,LS:f,LZ:f', pg_temp.puede_puerta(pg_temp.a('D')));
  perform pg_temp.esperar('directorio histórico ve pero no marca', 'L1:f,L1n:f,L2:f,L3:f,LC:f,LD:f,LK:f,LP:f,LPV:f,LS:f,LZ:f', pg_temp.puede_puerta(pg_temp.a('DH')));
  for r in select k, id from act where k not in ('X', 'XP', 'P', 'DM', 'C') order by k loop
    perform pg_temp.esperar('puede_marcar = marcar de verdad para ' || r.k, pg_temp.puede_verdad(r.id), pg_temp.puede_puerta(r.id));
  end loop;
  perform pg_temp.esperar('probar «puede de verdad» no dejó marcas nuevas', '9/11',
    (select count(*)::text from crm.lead_potencial where lead_id in (select id from lds)) || '/' ||
    (select count(*)::text from crm.lead_potencial_eventos where lead_id in (select id from lds)));

  -- ── El calendario (núcleo con fecha simulada, como V1 salvo que se diga) ──
  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-06');
  perform pg_temp.esperar('mar 10-06 · L1 estrella recién marcada: 0 días, baja a tibio el dom 10-11', 'estrella/manual/estrella d=0 baja=tibio@2026-10-11 puede=true', pg_temp.item(v, 'L1'));
  perform pg_temp.esperar('mar 10-06 · L3 sin marca: todo null y puede marcar', '-/-/- d=- baja=-@- puede=true', pg_temp.item(v, 'L3'));
  perform pg_temp.esperar('mar 10-06 · LPV parqueado sin marca: V1 lo ve pero no lo marca', '-/-/- d=- baja=-@- puede=false', pg_temp.item(v, 'LPV'));
  perform pg_temp.esperar('mar 10-06 · LI inactivo no viaja', '(no viaja)', pg_temp.item(v, 'LI'));
  perform pg_temp.esperar('mar 10-06 · un id que no existe no viaja', '(no viaja)', pg_temp.item(v, 'NADA'));
  perform pg_temp.esperar('mar 10-06 · marcado_en viaja', '2026-10-05 10:00', (
    select to_char((i ->> 'marcado_en')::timestamptz at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
    from jsonb_array_elements(v) i where (i ->> 'lead_id')::uuid = pg_temp.l('L1')));

  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-10');
  perform pg_temp.esperar('sáb 10-10 · L1: 4 días (mar-vie), sigue bajando el dom 10-11', 'estrella/manual/estrella d=4 baja=tibio@2026-10-11 puede=true', pg_temp.item(v, 'L1'));
  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-11');
  perform pg_temp.esperar('dom 10-11 · L1: 5 días, baja HOY (pendiente de la corrida)', 'estrella/manual/estrella d=5 baja=tibio@2026-10-11 puede=true', pg_temp.item(v, 'L1'));

  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-12');
  perform pg_temp.esperar('lun 10-12 · LC convertido: conserva la estrella, no baja ni se marca', 'estrella/manual/estrella d=5 baja=-@- puede=false', pg_temp.item(v, 'LC'));
  perform pg_temp.esperar('lun 10-12 · LD descartado: conserva el tibio, no baja ni se marca', 'tibio/manual/tibio d=5 baja=-@- puede=false', pg_temp.item(v, 'LD'));
  perform pg_temp.esperar('lun 10-12 · LK bajó sola: tibio por caducidad, la persona puso estrella, baja a frío el sáb 10-17', 'tibio/caducidad/estrella d=5 baja=frio@2026-10-17 puede=true', pg_temp.item(v, 'LK'));
  perform pg_temp.esperar('lun 10-12 · LZ marcada vie 21:00 Lima: 1 día (el sábado), no 0', 'estrella/manual/estrella d=1 baja=tibio@2026-10-16 puede=true', pg_temp.item(v, 'LZ'));

  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-19');
  perform pg_temp.esperar('lun 10-19 · L1 con 11 días sin corrida: va directo a frío, hoy', 'estrella/manual/estrella d=11 baja=frio@2026-10-19 puede=true', pg_temp.item(v, 'L1'));

  -- La próxima corrida (Codex f3a r1): a las 05:39 aún queda la pasada de hoy; desde las 05:40, mañana.
  perform pg_temp.esperar('próxima corrida: 05:39 → hoy; 05:40 → mañana; 23:59 → mañana; 00:00 → hoy', '2026-10-05/2026-10-06/2026-10-06/2026-10-06',
    private.potencial_proxima_corrida(pg_temp.lima('2026-10-05 05:39:59'))::text || '/' || private.potencial_proxima_corrida(pg_temp.lima('2026-10-05 05:40:00'))::text || '/' ||
    private.potencial_proxima_corrida(pg_temp.lima('2026-10-05 23:59:59'))::text || '/' || private.potencial_proxima_corrida(pg_temp.lima('2026-10-06 00:00:00'))::text);
  -- El caso de Codex: estrella del lun 05 vista el VIERNES 16 después de la corrida (9 días). La
  -- próxima pasada es el sábado 17, que ya cuenta 10: va directo a frío, no a tibio.
  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-16', pg_temp.lima('2026-10-16 09:00'), '2026-10-17');
  perform pg_temp.esperar('vie 10-16 tras la corrida · L1 con 9 días: baja a FRÍO el sáb 10-17', 'estrella/manual/estrella d=9 baja=frio@2026-10-17 puede=true', pg_temp.item(v, 'L1'));
  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-16', pg_temp.lima('2026-10-16 05:00'), '2026-10-16');
  perform pg_temp.esperar('vie 10-16 antes de la corrida · L1 con 9 días: baja a tibio HOY', 'estrella/manual/estrella d=9 baja=tibio@2026-10-16 puede=true', pg_temp.item(v, 'L1'));
  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-11', pg_temp.lima('2026-10-11 09:00'), '2026-10-12');
  perform pg_temp.esperar('dom 10-11 tras la corrida · L1 pendiente: baja MAÑANA lun 10-12', 'estrella/manual/estrella d=5 baja=tibio@2026-10-12 puede=true', pg_temp.item(v, 'L1'));

  v := pg_temp.leer(pg_temp.a('S1'), pg_temp.todos(), '2026-10-06');
  perform pg_temp.esperar('mar 10-06 · L1n tibio: baja a frío el sáb 10-17 (10 días)', 'tibio/manual/tibio d=0 baja=frio@2026-10-17 puede=true', pg_temp.item(v, 'L1n'));
  v := pg_temp.leer(pg_temp.a('S1'), pg_temp.todos(), '2026-10-12');
  perform pg_temp.esperar('lun 10-12 · LP frío: no baja más', 'frio/manual/frio d=5 baja=-@- puede=true', pg_temp.item(v, 'LP'));

  v := pg_temp.leer(pg_temp.a('V2'), pg_temp.todos(), '2026-10-12');
  perform pg_temp.esperar('lun 10-12 · L2 con contacto el jue 10-08: 2 días, baja el jue 10-15', 'estrella/manual/estrella d=2 baja=tibio@2026-10-15 puede=true', pg_temp.item(v, 'L2'));
  v := pg_temp.leer(pg_temp.a('V2'), pg_temp.todos(), '2026-10-07');
  perform pg_temp.esperar('mié 10-07 · L2 antes de su contacto: el contacto futuro aún no cuenta', 'estrella/manual/estrella d=1 baja=tibio@2026-10-11 puede=true', pg_temp.item(v, 'L2'));

  v := pg_temp.leer(pg_temp.a('G'), pg_temp.todos(), '2026-10-12');
  perform pg_temp.esperar('gerencia · L1: ve la marca y cuándo baja, no marca', 'estrella/manual/estrella d=5 baja=tibio@2026-10-12 puede=false', pg_temp.item(v, 'L1'));

  -- Núcleo: argumentos.
  perform pg_temp.esperar('núcleo sin ids → []', '[]', pg_temp.leer(pg_temp.a('V1'), null, '2026-10-06')::text);
  begin
    perform private.potencial_lectura(null, pg_temp.todos(), '2026-10-06', now(), '2026-10-06');
    perform pg_temp.esperar('núcleo sin actor → 22023', '22023', 'sin error');
  exception when others then
    perform pg_temp.esperar('núcleo sin actor → 22023', '22023', sqlstate);
  end;
  -- El núcleo con un actor que NO es el de la sesión (Codex f3a r1): sesión de V2, actor gerencia.
  begin
    perform pg_temp.sesion(pg_temp.a('V2'));
    perform private.potencial_lectura(pg_temp.a('G'), pg_temp.todos(), '2026-10-06', now(), '2026-10-06');
    perform pg_temp.esperar('núcleo con actor ajeno a la sesión → 42501', '42501', 'sin error');
  exception when others then
    perform pg_temp.esperar('núcleo con actor ajeno a la sesión → 42501', '42501', sqlstate);
  end;

  -- ── Solo lectura: nada cambió en las tablas de la marca ──
  perform pg_temp.esperar('la lectura no escribió marcas ni eventos', '9/11',
    (select count(*)::text from crm.lead_potencial where lead_id in (select id from lds)) || '/' ||
    (select count(*)::text from crm.lead_potencial_eventos where lead_id in (select id from lds)));

  -- ── Veredicto (el raise deshace todo) ──
  select count(*) into v_n from res where esperado is distinct from obtenido;
  if v_n = 0 then
    raise exception 'LECTURA potencial_lead: % de % OK', (select count(*) from res), (select count(*) from res) using errcode = 'P0001';
  else
    raise exception 'LECTURA potencial_lead: % FALLAS de %: %', v_n, (select count(*) from res),
      (select string_agg(n || ' ' || caso || ' → esperado ' || esperado || ', obtenido ' || obtenido, ' | ' order by n)
       from res where esperado is distinct from obtenido) using errcode = 'P0001';
  end if;
end;
$prueba$;
rollback;
```
