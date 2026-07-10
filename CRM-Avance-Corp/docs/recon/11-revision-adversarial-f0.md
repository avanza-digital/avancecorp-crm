## Lente 1

**Veredicto:** apto_con_fixes — El núcleo RLS es sólido: el cliente del portal queda totalmente contenido (no lee/escribe crm.*), el vendedor solo ve/edita su cartera, el directorio/admin son solo-lectura real y el log de actividades es inmutable. No hallé escalada directa ni fuga de datos bancarios (la vista es security_invoker y el embed por FK sigue gobernado por la RLS de perfiles). Pero hay una fuga de privacidad explotable por cualquier cliente y varios acoplamientos/gaps que conviene cerrar antes de tocar producción.

### [alta] Oracle de membresía por DNI expuesto a TODO authenticated (incluidos los 127 clientes)

**Detalle:** crm.existe_cliente_por_dni(text) (líneas 442-451) es SECURITY DEFINER, está en el esquema crm (que SÍ se expone por PostgREST según el paso manual, líneas 16-18) y se otorga a authenticated (línea 460). Ataque concreto: un usuario con rol='cliente' (o cualquiera con sesión) llama supabase.schema('crm').rpc('existe_cliente_por_dni',{p_dni:'12345678'}) contra /rest/v1/rpc/ y recibe un boolean que confirma si ese DNI es inversor ACTIVO de Avance Corp. En contexto financiero, confirmar dirigidamente 'X es inversor de Avance' es una fuga de privacidad de fricción cero (y enumerable). El comentario 'Superficie mínima: devuelve solo boolean' no mitiga: el problema es QUIÉN puede llamarla, no cuánto devuelve.

**Fix:** Gatear la autorización DENTRO de la función: al inicio 'if private.rol_crm((select auth.uid())) is null and not private.es_lector_global() then raise exception ...' (solo roles comerciales/lector global captan). Alternativa: revocar de authenticated y exponerla solo vía una RPC de captación gerencia/vendedor-gated.

### [media] Los nuevos FKs crm.*→public.perfiles cambian el comportamiento de DELETE de public.perfiles en prod

**Detalle:** crm.equipo.creado_por (línea 40), crm.leads.creado_por (línea 166, NOT NULL) y crm.actividades.creado_por (línea 202) referencian public.perfiles SIN cláusula on delete → NO ACTION (RESTRICT). Escenario: el superadmin (único DELETE de perfiles) intenta borrar por SQL a un analista/vendedor que ya creó leads/actividades → falla con 'update or delete on table perfiles violates foreign key constraint on crm.leads' (error opaco, no el mensaje amable del portal). Además crm.leads.perfil_id (línea 161) es 'on delete set null' pero choca con el CHECK convertido_requiere_perfil (líneas 171-172): borrar un cliente vinculado a un lead 'convertido' con contrato_id NULL (posible: el CHECK solo exige perfil_id) dispara SET NULL → viola el CHECK → el DELETE del perfil ABORTA. Aunque los FKs están permitidos por la regla dura, el efecto lateral es que la migración condiciona el borrado de filas de public que antes funcionaba.

**Fix:** Para creado_por usar 'on delete set null' (y hacerlo nullable en leads) o documentar/limpiar CRM antes del borrado. Reconciliar perfil_id: quitar el SET NULL en el FK de perfil_id (dejar NO ACTION explícito y borrar por soft-delete) o relajar el CHECK, para que un lead convertido nunca quede en estado inconsistente por un DELETE de perfiles.

### [media] Leads huérfanos al desactivar un vendedor: sin ruta de reasignación en-app

**Detalle:** private.vendedor_ids_visibles para gerencia solo devuelve 'where activo=true' (línea 81) y desactivar un vendedor es equipo.activo=false, que NO nula vendedor_id (el on delete set null de la línea 159 solo aplica a DELETE, no a desactivación). Escenario: gerencia pone activo=false a un vendedor con 50 leads abiertos; esos leads mantienen vendedor_id apuntando a un miembro ya invisible. En leads_update (líneas 368-377) la primera rama del USING exige 'vendedor_id in visibles' (falla), las ramas de parkeo exigen vendedor_id null (falla) y es_lector_global NO aparece en el UPDATE (admin/directorio son solo-lectura). Resultado: ningún rol comercial (ni gerencia) pasa el USING para hacer SELECT...FOR UPDATE y reasignarlos; solo recuperables por SQL de superadmin o un RPC futuro inexistente en F0.

**Fix:** Al desactivar en equipo (RPC de F1) reasignar/nular vendedor_id de sus leads, o añadir una rama de recuperación para gerencia en leads_update que permita ver/actualizar leads cuyo vendedor_id ya no esté activo (p.ej. vendedor_id not in (select ... where activo) and rol_crm=gerencia).

### [media] creado_por/creado_en de crm.leads son mutables vía UPDATE (falsificación de atribución)

**Detalle:** A diferencia de public (trigger proteger_campos_inmutables congela id/creado_en/creado_por), la migración NO añade ningún trigger de inmutabilidad a crm.leads/crm.equipo, y el with_check de leads_update (líneas 379-385) no restringe creado_por ni creado_en. Ataque: un vendedor hace PATCH crm.leads?id=eq.<propio> {"creado_por":"<uuid-de-otro>"}; pasa el USING (lead propio, activo) y el with_check (vendedor_id sin cambiar, activo=true), por lo que reescribe la autoría del lead. En un CRM de ventas esto corrompe atribución/comisiones y auditoría (el INSERT sí está protegido por creado_por=auth.uid() en línea 356, pero el UPDATE no).

**Fix:** Añadir un BEFORE UPDATE trigger (SECURITY DEFINER en private) sobre crm.leads y crm.equipo que restaure new.id/new.creado_en/new.creado_por := old.* (espejo del proteger_campos_inmutables del portal).

### [baja] Helpers SECURITY DEFINER de private confían en un uuid arbitrario del llamador (riesgo latente de enumeración)

**Detalle:** private.vendedor_ids_visibles(uuid), private.puede_ver_cartera(uuid,uuid) y private.rol_crm(uuid) (líneas 56-109) reciben p_perfil_id arbitrario en vez de derivarlo de auth.uid(), y se otorga execute a authenticated (líneas 126-128). HOY no es explotable porque el esquema private NO se agrega a Exposed schemas (el paso manual de líneas 16-18 solo añade crm), así que no son alcanzables por /rest/v1/rpc/. Pero todo el modelo depende de ese único toggle: si algún día se expone private (error de config de una línea), cualquier authenticated podría llamar vendedor_ids_visibles('<uuid-de-un-supervisor>') para volcar su subárbol completo o puede_ver_cartera(a,b) como oráculo de relaciones. Respondiendo a la pregunta explícita del encargo: sí son invocables con argumentos arbitrarios por diseño; la única barrera es no exponer private.

**Fix:** Defensa en profundidad: que los helpers ignoren el parámetro y usen (select auth.uid()) internamente donde la semántica lo permita, o agreguen assert 'p_perfil_id = (select auth.uid()) or private.es_lector_global()'. Y dejar constancia dura de que private JAMÁS entra en Exposed schemas.

### [baja] es_lector_global()/rol_crm() invocados 'crudos' en las policies: subconsulta a perfiles/equipo por fila

**Detalle:** En equipo_select (línea 138), leads_select (líneas 347,349), actividades_select (líneas 401,403) y leads_insert/update se llama private.es_lector_global() y private.rol_crm(...) SIN envolver en (select ...). A diferencia de (select auth.uid()) (que sí queda como initplan de una sola evaluación), una función STABLE llamada 'cruda' puede reevaluarse por fila, y cada llamada corre un lookup a public.perfiles/crm.equipo. Irrelevante con 148 perfiles, pero el listado de leads es el camino caliente hacia el objetivo de ~5.000 clientes y muchos leads, donde se convierte en una subconsulta por fila candidata.

**Fix:** Envolver como (select private.es_lector_global()) y hoistear rol_crm a un (select ...) por query, igual que ya se hace con (select auth.uid()) — mismo patrón initplan de VITANOVA.

## Lente 2

**Veredicto:** apto_con_fixes — la base es sólida (no altera ningún objeto de public, audit_log acepta el insert del trigger tal cual está — fila_id text acepta uuid por conversión de asignación, verificado en vivo —, sin colisión de esquemas crm/private, bandeja_actividad del portal no se contamina y la RLS deny-by-default está bien armada), pero NO aplicar sin cerrar antes el oráculo de DNI (hallazgo 1) y sin decidir conscientemente el impacto de FKs/CHECK sobre los flujos de borrado del portal (hallazgo 2); los hallazgos 3-5 conviene resolverlos en esta misma migración antes de F1.

### [alta] crm.existe_cliente_por_dni es un oráculo de enumeración de DNIs abierto a los 148 usuarios del portal (incluidos los 127 clientes)

**Detalle:** Líneas 442-451: la función es SECURITY DEFINER (bypassa RLS de public.perfiles) y devuelve si un DNI pertenece a un cliente activo. Línea 460 la otorga a `authenticated` y la línea 25 da `usage` del esquema crm a `authenticated` — rol que incluye a TODOS los usuarios logueados del portal, no solo al staff del CRM. Al completar el paso manual de exponer `crm` en PostgREST, cualquier cliente logueado (o una cuenta cliente comprometida) puede hacer POST /rest/v1/rpc/existe_cliente_por_dni con header Content-Profile: crm y body {"p_dni":"12345678"} y confirmar/enumerar qué DNIs son inversionistas de Avance Corp. Es divulgación de la cartera de clientes de una financiera a usuarios finales. Verificado en prod: no hay ninguna otra barrera (la RLS no aplica dentro del DEFINER).

**Fix:** Gatear dentro de la función antes del SELECT: `if private.rol_crm((select auth.uid())) is null and not private.es_lector_global() then raise exception 'No autorizado'; end if;`. Así solo staff CRM/directorio/admin puede consultarla, manteniendo el grant a authenticated.

### [media] El CHECK convertido_requiere_perfil + FK ON DELETE SET NULL rompe el flujo eliminar-cliente del superadmin (y los FKs creado_por NO ACTION bloquean borrar perfiles de staff)

**Detalle:** Escenario 1: un lead llega a etapa='convertido' con perfil_id enlazado (línea 161, FK on delete set null) pero el cliente aún no tiene contrato registrado. El superadmin lo elimina vía edge eliminar-cliente (que solo bloquea si hay contratos): el DELETE de auth.users cascadea a public.perfiles, el SET NULL sobre crm.leads.perfil_id viola el CHECK convertido_requiere_perfil (líneas 171-172, etapa sigue 'convertido') y TODO el borrado aborta → la edge devuelve un 500 críptico donde hoy funciona. Escenario 2: crm.leads.creado_por es NOT NULL sin cláusula ON DELETE (línea 166, default NO ACTION) y crm.equipo.creado_por igual (línea 40): en cuanto un vendedor cree un lead, el DELETE de su perfil por superadmin (policy superadmin_elimina_perfiles vigente en prod) pasará de funcionar a fallar con error de FK. Puede ser deseable (fuerza soft-delete), pero es un cambio de comportamiento del portal en producción que hay que decidir explícitamente, no heredar por accidente.

**Fix:** Quitar el CHECK convertido_requiere_perfil de la tabla y validar 'convertido requiere perfil' en la transición (trigger BEFORE UPDATE cuando new.etapa='convertido' y old.etapa<>'convertido', o en la RPC de conversión de F1) — así el SET NULL posterior no viola nada. Para creado_por: decidir política consciente — o documentar que perfiles con actividad CRM solo se desactivan (activo=false), o hacer la columna nullable con on delete set null.

### [media] La conversión NO está realmente restringida a RPC: un vendedor puede auto-convertir leads y enlazar perfil_id/contrato_id arbitrarios

**Detalle:** El encabezado (líneas 11-12) declara que la conversión va SOLO por RPC SECURITY DEFINER, pero leads_insert (352-366) y leads_update (368-385) no restringen las columnas etapa, perfil_id ni contrato_id. Escenario: un vendedor hace UPDATE de su lead con etapa='convertido' y perfil_id = uuid de un cliente existente de su cartera (legible vía crm.clientes_basicos); pasa el USING y el WITH CHECK, el trigger bloquear_reasignacion no aplica (vendedor_id no cambia), trg_leads_cambio_etapa (262-284) le sella convertido_en como conversión legítima. Resultado: métricas de conversión y ranking comercial inflables a voluntad sin pasar por la RPC. Vía INSERT directo con etapa='convertido' ni siquiera se sella convertido_en. Además actividades_insert (línea 412) solo veta tipo='cambio_etapa': los tipos 'conversion' y 'reasignacion' se pueden insertar a mano, falseando el timeline inmutable.

**Fix:** Trigger BEFORE INSERT OR UPDATE en crm.leads que rechace etapa='convertido' y cualquier seteo/cambio de perfil_id/contrato_id salvo contexto privilegiado (p. ej. GUC local `set local crm.conversion_autorizada` que solo fija la RPC de F1). Y en actividades_insert ampliar el veto: tipo not in ('cambio_etapa','conversion','reasignacion').

### [media] asignado_supervisor_id sin validación: parkeo cruzado entre equipos y escritura de actividades en leads parkeados ajenos

**Detalle:** Ni leads_insert (352-366) ni el WITH CHECK de leads_update (379-385) validan asignado_supervisor_id: un supervisor puede crear o mover leads parkeados a la bandeja de OTRO supervisor (y dejar de verlos él mismo, sin poder deshacer: el USING de la línea 374-375 ya no le matchea), o asignarlos directamente a un vendedor ajeno — que entonces los ve y edita, porque para un vendedor vendedor_ids_visibles = {él} y las ramas parked (líneas 345-346, 374-375) usan `asignado_supervisor_id in (…)`, saltándose la jerarquía. Además actividades_insert (líneas 419-421) permite a cualquier supervisor insertar actividades en CUALQUIER lead parkeado (`l.vendedor_id is null` sin comprobar asignado_supervisor_id), es decir escribir en leads que su propio leads_select no le deja ver.

**Fix:** En leads_insert/leads_update añadir al WITH CHECK: `asignado_supervisor_id is null or asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid())))` (gerencia pasa igual porque ve a todos), idealmente validando también rol supervisor/gerencia del asignado. En actividades_insert cambiar la rama parked a `(l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles((select auth.uid()))))` con excepción para gerencia.

### [media] service_role sin USAGE ni grants en crm/private: las edges de F1 nacerán rotas

**Detalle:** Verificado en prod: los default ACLs solo cubren el esquema public (pg_default_acl no tiene entrada global ni para crm), y service_role tiene rolbypassrls pero NO es superusuario, así que los ACLs de esquema sí le aplican. La migración solo otorga usage a authenticated (líneas 25-26) y los grants de tabla a authenticated (454-456). El plan declarado (líneas 11-12) es que las escrituras privilegiadas (alta de equipo, conversión) vayan por RPC/edge: cualquier Edge Function que siga el patrón del portal (crear-cliente, etc.) haciendo `.schema('crm').from('equipo').insert(...)` con la service key fallará con 42501 'permission denied for schema crm'. No afecta al portal hoy, pero rompe F1 en silencio hasta el primer deploy.

**Fix:** Añadir a la migración: `grant usage on schema crm, private to service_role; grant all on all tables in schema crm to service_role;` (y default privileges futuros si se crearán más tablas), o comprometerse a que F1 use exclusivamente RPCs SECURITY DEFINER en crm invocadas vía PostgREST (que sí funcionan al ser owned by postgres).

### [baja] Un ciclo de supervisores (A↔B) cuelga todas las queries de los afectados: el CTE recursivo usa UNION ALL sin guard

**Detalle:** El constraint equipo_no_autosupervision (líneas 43-44) solo bloquea el auto-ciclo de longitud 1. Si por error de la futura RPC de F1 o de un INSERT manual del superadmin quedan A.supervisor_id=B y B.supervisor_id=A (ambos supervisores), el CTE recursivo de private.vendedor_ids_visibles (líneas 83-92, UNION ALL) entra en bucle infinito, y como esa función se evalúa en las policies de TODA query de equipo/leads/actividades, ambos usuarios quedan con el CRM colgado hasta el statement_timeout en cada request.

**Fix:** Cambiar `union all` por `union` en el CTE (la deduplicación corta el ciclo y el resultado es idéntico) y, en la RPC de alta/edición de equipo de F1, validar que el nuevo supervisor_id no esté en el subárbol del perfil editado.

### [baja] Campos inmutables de crm.leads (creado_por, creado_en, id) editables por el dueño — rompe la convención del portal

**Detalle:** El grant de UPDATE (línea 455) es de tabla completa y ningún WITH CHECK ni trigger congela creado_por/creado_en/id (el portal lo hace con proteger_campos_inmutables en perfiles, convención documentada). Escenario: un vendedor hace UPDATE de su lead seteando creado_por = uuid de otro perfil o creado_en retroactivo, falseando autoría y antigüedad del lead en reportes y en el dedup de captación (audit_log registra el cambio, pero nadie lo mira por defecto).

**Fix:** Replicar el patrón del portal: trigger BEFORE UPDATE en crm.leads (y crm.equipo) que restaure new.id/new.creado_en/new.creado_por desde OLD; alternativamente usar grant de UPDATE por columnas excluyéndolas.

## Lente 3

**Veredicto:** apto_con_fixes — la migración es sintácticamente válida y aplicaría sin errores en el orden escrito, pero NO debe tocar producción sin resolver antes los dos hallazgos de severidad alta (el CHECK de conversión que rompe el hard-delete de clientes del portal existente, y la conversión/vinculación de perfil_id-contrato_id que queda abierta a cualquier vendedor pese al invariante declarado de solo-RPC).

### [alta] FK perfil_id ON DELETE SET NULL choca con el CHECK convertido_requiere_perfil: rompe el hard-delete de clientes del portal

**Detalle:** Línea 161: `perfil_id uuid references public.perfiles(id) on delete set null`. Líneas 171-172: `check (etapa <> 'convertido' or perfil_id is not null)`. La acción referencial SET NULL se ejecuta como un UPDATE sobre crm.leads que DEBE satisfacer los CHECK de la tabla. Escenario: un lead se convierte (etapa='convertido', perfil_id=cliente nuevo, aún sin contrato); el superadmin borra ese cliente (edge eliminar-cliente borra el auth.user → cascade a public.perfiles → SET NULL en crm.leads → check_violation). El DELETE completo aborta con un error críptico de constraint de crm, es decir, el CRM rompe un flujo EXISTENTE del portal en producción (eliminar-cliente solo bloquea si hay contratos, no si hay leads convertidos). Lo mismo aplica al DELETE directo de perfiles por la policy superadmin_elimina_perfiles.

**Fix:** Quitar el CHECK de tabla y mover la exigencia al trigger de transición (en trg_leads_cambio_etapa: `if new.etapa='convertido' and new.perfil_id is null then raise exception ...`), que solo valida en el momento de convertir y no en acciones referenciales. Alternativa si se prefiere bloquear el borrado: cambiar la FK a `on delete restrict` para que el error sea explícito y predecible.

### [alta] La conversión NO queda restringida a RPC: leads_insert/leads_update permiten a un vendedor convertir y enlazar perfil_id/contrato_id arbitrarios

**Detalle:** El header (líneas 11-12) declara: conversión SOLO por RPC SECURITY DEFINER, 'no hay policies de INSERT/UPDATE para eso'. Pero leads_update (368-385) no restringe columnas: WITH CHECK solo valida vendedor_id y activo. Escenario 1: un vendedor hace UPDATE de su lead con etapa='convertido' y perfil_id=cualquier uuid de perfiles (le basta su propia uid, que ES un perfiles.id, o la de un cliente de su cartera visible en crm.clientes_basicos); el CHECK convertido_requiere_perfil se satisface, el trigger sella convertido_en y registra la actividad — conversión falsa que infla métricas/comisiones. La FK a public.contratos se valida internamente sin RLS, así que también puede enlazar contrato_id de contratos ajenos que nunca pudo leer. Escenario 2 (INSERT directo, 352-366): la policy no restringe etapa, y trg_leads_cambio_etapa es solo BEFORE UPDATE (283), así que un lead insertado ya 'convertido' queda SIN sello convertido_en y SIN actividad en el timeline — estado inconsistente con la semántica declarada.

**Fix:** En leads_insert: exigir `etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')` y `perfil_id is null and contrato_id is null and convertido_en is null`. En leads_update: añadir trigger BEFORE UPDATE (o extender trg_leads_bloquear_reasignacion) que rechace cambios de etapa a 'convertido' y cualquier cambio de perfil_id/contrato_id cuando auth.uid() no sea null (es decir, cuando no venga de la RPC SECURITY DEFINER de F1) o al menos cuando rol_crm(auth.uid()) <> 'gerencia'.

### [media] Desactivar un miembro del equipo (activo=false) deja sus leads vivos invisibles e inactualizables para supervisor y gerencia

**Detalle:** private.vendedor_ids_visibles filtra `activo = true` tanto en la rama gerencia (línea 81) como en el paso recursivo del subárbol (línea 90). Escenario: un vendedor con 30 leads abiertos sale de la empresa → equipo.activo=false (el soft-delete institucional). Sus leads tienen vendedor_id NOT NULL, que ya no está en visibles() de nadie; las ramas de 'parkeado' de leads_select (345-347) exigen vendedor_id IS NULL; es_lector_global solo cubre directorio/admin y SOLO para SELECT — leads_update (370-377) no tiene rama de lector global. Resultado: nadie puede ver (salvo admin/directorio en solo-lectura) ni reasignar esos leads por API; la cartera queda huérfana hasta que alguien entre por SQL. Además un supervisor intermedio inactivo corta el subárbol recursivo: los vendedores por debajo desaparecen de la vista de gerencia. Ojo: el doc VITANOVA (línea 87) documenta 'usuarios desactivados no ven nada y NO SON VISTOS' como parte del patrón, pero allí conviven con reasignación por SLA; aquí, sin la RPC de reasignación (F1 futuro), el bloqueo es total.

**Fix:** Que el filtro `activo` aplique solo a quién CONSULTA, no a quién es visto: en la rama gerencia devolver todos los perfil_id (sin filtro activo) y en el CTE del supervisor quitar `e.activo = true` del paso recursivo (la membresía jerárquica no desaparece al desactivar). Alternativa mínima: añadir en leads_select/leads_update una rama `private.rol_crm(auth.uid())='gerencia'` sin condición sobre vendedor_id.

### [media] Recursión infinita en vendedor_ids_visibles si la jerarquía forma un ciclo (UNION ALL sin guarda)

**Detalle:** El CTE recursivo (líneas 84-91) usa UNION ALL y la única protección es el constraint equipo_no_autosupervision (43-44), que solo bloquea ciclos de longitud 1. Escenario: por SQL manual del superadmin (que es la vía de alta declarada mientras no exista la RPC de F1) se crea A supervisa a B y B supervisa a A; desde ese momento CUALQUIER SELECT de leads/equipo/actividades por parte de A o B entra en bucle infinito hasta el statement_timeout, tumbando de facto el CRM para esos usuarios y consumiendo CPU del proyecto en producción compartido con el portal.

**Fix:** Cambiar UNION ALL por UNION: como el CTE solo proyecta perfil_id, la deduplicación de UNION corta cualquier ciclo y termina siempre. Complemento: trigger BEFORE INSERT/UPDATE en crm.equipo que recorra la cadena de supervisor_id y rechace ciclos.

### [media] Columnas de trazabilidad de crm.leads son editables por el propio vendedor (id, creado_por, creado_en, convertido_en)

**Detalle:** Línea 455 otorga `grant update on crm.leads` sin lista de columnas y el WITH CHECK (379-385) no restringe columnas; no existe equivalente al trigger proteger_campos_inmutables que el portal SÍ tiene en public.perfiles. Escenario: un vendedor hace UPDATE de su lead cambiando creado_por a otro perfil (falsea quién captó el lead ante el ranking), retro-data creado_en, fija convertido_en a una fecha arbitraria ANTES de convertir (el trigger de 275-277 solo sella si es null, así que respeta el valor falsificado), o cambia id a otro uuid si el lead aún no tiene actividades (rompe la correlación con audit_log, que guarda el fila_id viejo).

**Fix:** Replicar el patrón del portal: trigger BEFORE UPDATE en crm.leads que restaure new.id/new.creado_en/new.creado_por desde OLD (y new.convertido_en cuando old.etapa <> 'convertido'), o usar grant de UPDATE por columnas dejando fuera id/creado_por/creado_en/convertido_en/perfil_id/contrato_id.

### [media] crm.existe_cliente_por_dni es un oráculo de DNIs abierto a CUALQUIER usuario autenticado, incluidos los 127 clientes del portal

**Detalle:** Líneas 442-451 y 459-460: la función es SECURITY DEFINER (lee public.perfiles sin RLS), está en el esquema crm (que se expondrá por PostgREST) y tiene grant execute a authenticated sin validar nada del caller. Escenario: un cliente logueado del portal llama `rpc('existe_cliente_por_dni', {p_dni:'12345678'})` en bucle y enumera qué DNIs peruanos son clientes de Avance Corp — fuga de la cartera de inversores desde un proyecto con datos bancarios. Contrasta con el resto de la migración, donde todo exige enrolamiento en crm.equipo o rol lector global.

**Fix:** Dentro de la función, cortocircuitar el acceso: `select case when private.rol_crm((select auth.uid())) is not null or private.es_lector_global() then exists(...) else null end` (o raise exception), de modo que solo el staff del CRM pueda consultar el oráculo.

### [baja] actividades_insert solo veta tipo 'cambio_etapa': un vendedor puede fabricar entradas 'conversion' y 'reasignacion' en el log inmutable

**Detalle:** Línea 412: `tipo <> 'cambio_etapa'` es la única exclusión, pero el CHECK de tipo (196-199) incluye 'reasignacion' y 'conversion', que por diseño deben emitir el trigger y la RPC de F1. Escenario: un vendedor inserta a mano una actividad tipo='conversion' sobre su lead; como el log es inmutable (sin UPDATE/DELETE por API, líneas 425 y 456), la entrada falsa queda grabada para siempre y contamina el timeline/auditoría comercial sin posibilidad de corrección desde la app.

**Fix:** Cambiar la condición a `tipo not in ('cambio_etapa','reasignacion','conversion')`, dejando esos tres tipos en exclusiva para triggers/RPCs SECURITY DEFINER.

