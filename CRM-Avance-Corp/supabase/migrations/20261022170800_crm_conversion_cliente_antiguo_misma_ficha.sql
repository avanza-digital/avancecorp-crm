-- 20261022170800_crm_conversion_cliente_antiguo_misma_ficha.sql — bloque 2.10 del plan «Mantenibilidad y consistencia del backend CRM» (fecha de trabajo 20261009235900_crm_conversion_cliente_antiguo_misma_ficha.sql; integrado el 2026/10/22, C2 del grupo C)
-- Convertir a un cliente antiguo sin ficha de persona usa su misma ficha (plan AVANCE-BACKEND-0810-F2, fase 2, bloque 2.10;
-- decisiones D-38, D-81, D-83, D-84, D-85, D-86, D-87, D-88, D-89, D-90, D-91, D-92, D-93 y D-94 de Miguel, 09 al 12/10/2026, plan aprobado en D-45; la regla del
-- cliente y lo que revela «ya es cliente de X» son las del 2.7 y el 2.8: D-22, D-25, D-27, D-29). Orden de instalación fijado por el Director: 2.8 → 2.9 → 2.11 → 2.16 →
-- 2.13 → 2.10 (ESTA va la última: se renombra al integrar, después del 2.16 y del 2.13 definitivos; ensayada con el 2.11 y el 2.16
-- pegados delante, y también sin ellos: no depende de ninguno de los dos, ni del 2.9 ni del 2.13; el oráculo se repite con el 2.13
-- delante en la branch). No toca ninguna función que fije el preflight del 2.11 ni el del 2.16 (`private.persona_vetada`,
-- `private.juicio_reapertura`, `private.bloquear_personas_de_leads`, `private.lead_dentro_de_bloqueo`,
-- `private.trg_leads_disponibilidad_atomica`, los dos núcleos del 2.11 ni las cuatro puertas del 2.16).
--
-- QUÉ PASA HOY (medido en el 2.8, caso P2, y en ROJO aquí: `supabase/scripts/conversion-cliente-antiguo/`). La preparación de la
-- conversión (`crm.preparar_persona_lead_inversion_fn`, DEFINER, válvula `crm.op_privilegiada`) resuelve o crea la persona del
-- documento (`private.inversionista_resolver`) y solo detecta otros leads de esa persona por sus enlaces
-- (`private.leads_de_personas` / `private.leads_de_identidades`: puntero, puente o «sueltos VIVOS» con su documento). Un cliente
-- antiguo SIN ficha de persona (lead `convertido` con `inversionista_id` nulo y sin puente) que está RETIRADO no aparece por ningún
-- camino ⇒ se crea una persona nueva y el cliente queda con dos registros (P2). Si ese cliente antiguo sigue ACTIVO, es un «suelto
-- vivo» ⇒ hoy se detiene con «Esta persona ya tiene otra identidad o lead; requiere conciliación» (P0409), tanto si es de otro asesor
-- como del mismo. Con un cliente que SÍ tiene ficha (puntero o puente), hoy se detiene con ese mismo P0409: eso NO cambia (D-38).
--
-- QUÉ HACE. En `crm.preparar_persona_lead_inversion_fn`, por ancla única, bajo los mismos candados que hoy (documento → persona →
-- la fila del lead que se convierte FOR UPDATE NOWAIT), DESPUÉS de todo lo que hoy decide (rol, ámbito, documento, identidad que
-- cambió, el reintento idempotente, «ya está cerrado», persona que no opera, No insistir, analista activo) y ANTES de la conciliación:
--   1. Pieza nueva `private.conversion_absorber_cliente_antiguo(p_lead, p_persona, p_dni, p_vendedor, p_uid)` (INVOKER, volátil,
--      dueño postgres, EXECUTE solo postgres): busca los leads `convertido` SIN persona ni puente cuyo `dni` es el de la conversión
--      (distintos del que se convierte), toma sus filas FOR UPDATE NOWAIT (40001 «El lead está en uso por otra operación; vuelve a
--      intentarlo» si otra operación las tiene: el mensaje de la casa) y decide por prioridad (activo → más reciente → id):
--        · si alguno sigue ACTIVO a nombre de OTRO asesor (vendedor distinto del analista del lead que se convierte; sin vendedor,
--          la bandeja del supervisor) ⇒ devuelve el veredicto «ya es cliente de X» con el formato y los datos del alta para un
--          convertido sin persona (D-29: estado ya_es_cliente, asesor = dueño de esa ficha o «sin asesor asignado») y NO escribe nada;
--        · si no (todos retirados, o activos del MISMO asesor) ⇒ los ABSORBE en la ficha de esta conversión, bajo la válvula y como
--          hace la puerta de enlace de Gerencia (`crm.enlazar_lead_inversionista_fn`), en su orden (medido en la ronda 4: perfil →
--          cierre): (a0) su PERFIL DEL PORTAL, si tiene: si ya es de OTRA persona no fusionada ⇒ `P0409` «El perfil del Portal del cliente
--          antiguo pertenece a otra persona; requiere conciliación de Gerencia»; si es de nadie pero la ficha YA tiene otro perfil ⇒
--          `P0409` «La ficha ya tiene otra cuenta del Portal; requiere conciliación de Gerencia»; si es de nadie y su documento
--          (`public.perfiles.dni`, `tipo_documento`) no es de esta persona —otro DNI, otro tipo, sin documento— ⇒ `P0409` «El perfil del
--          Portal del cliente antiguo lleva otro documento; requiere conciliación de Gerencia» (D-86; nada escrito); si es de nadie, la
--          ficha no tiene otro y su documento es de esta persona ⇒ se enlaza a la ficha (`crm.inversionistas.perfil_id`, D-87), pero
--          DESPUÉS del UPDATE del lead que se convierte, en la pieza de enlace: el verificador que corre al escribir el DNI trata como
--          «ya es cliente» (vía identidad) a una persona con perfil enlazado (medido: mutante M33), y el detalle de la operación lo dice
--          (`perfil_completado`); D-89: si esa cuenta propia está DESACTIVADA —exactamente el predicado con el que el núcleo del contexto de
--          la persona responde «El perfil Avance requiere revisión antes de operar»: `not found or activo is not true or rol <> 'cliente'`,
--          en `private.inversion_persona_contexto_para` y `private.inversion_contexto_lectura_para`, l. 37 de sus cuerpos vivos, fijados por
--          este preflight— NO se enlaza (Gerencia puede hacerlo después): la absorción y la conversión siguen y el detalle dice
--          `perfil_no_enlazado` (su id) y `perfil_motivo` «cuenta del Portal desactivada»; así un perfil enlazado pasa el núcleo con lo
--          leído (el núcleo lo vuelve a leer FOR SHARE: un cambio simultáneo del perfil puede detener la preparación);
--          los conflictos de D-86 se miran ANTES y detienen aunque la cuenta esté desactivada; si ya es de esta persona ⇒ no se toca (y el verificador, sellado, detiene la conversión con «ya es
--          cliente» vía identidad, como hoy: la persona ya es cliente del Portal). `public.perfiles` se LEE con un SELECT simple, SIN
--          candado (regla de `public`); un cambio simultáneo del perfil es carrera de F4.6. Completar `perfil_id` no pide la válvula;
--          su clave foránea toma, como toda escritura de esa columna, un FOR KEY SHARE sobre la fila del perfil (solo choca con borrarlo
--          o cambiar su id) y el disparador de la casa `trg_zzzz_usuario_retirado` un FOR SHARE NOWAIT sobre el perfil del responsable,
--          como cualquier UPDATE de `crm.inversionistas` (la puerta ya lo hace hoy al poner el responsable): esta migración no añade
--          ningún FOR SHARE explícito sobre `public`, pero el núcleo PREEXISTENTE del contexto de la persona sí lee el perfil FOR SHARE (y la
--          FK y el disparador de la casa toman los suyos, implícitos); el índice único del perfil
--          convierte una carrera con otra persona en 23505, que la pieza traduce al 40001 de la casa. (a) su CIERRE EXTERNO INICIAL se completa con
--          la persona (D-83: `update crm.cierres_externos set inversionista_id` solo si sigue NULL y
--          `private.documento_es_de_identidad(persona, tipo, documento)`; el asesor de origen del cierre, `vendedor_id`, no cambia:
--          no se mueven cifras entre asesores; si el cierre ya es de OTRA persona (D-84) ⇒ `P0409` «El cierre del cliente antiguo
--          pertenece a otra persona; requiere conciliación de Gerencia» y nada se escribe; si sigue sin persona y su documento NO es de
--          esta persona —otro DNI, un CE, un pasaporte— (D-85) ⇒ `P0409` «El cierre del cliente antiguo lleva otro documento; requiere
--          conciliación de Gerencia» y nada se escribe: lo mismo, en el mismo orden, que esa puerta (medido en la ronda 3: ella
--          tampoco distingue un CE de otro DNI, y un cierre SIN documento no existe —`documento` y `documento_tipo` son NOT NULL con
--          formato—); si ya es de esta persona, no se toca y el detalle lo dice); (b) su rastro en el libro append-only
--          `crm.inversionista_operaciones` (tipo enlace, motivo sin documento, detalle con la vía, el rol, el lead de la conversión, si
--          el antiguo estaba activo y se retiró, los dos asesores, `cierre_completado` —o, si el cierre ya era de esta persona,
--          `cierre_no_completado` + `cierre_motivo`—); (c) si el lead antiguo sigue ACTIVO, una nota en `crm.actividades` (evento
--          enlace_identidad) y su RETIRO (`activo = false`; D-81): la casa no admite dos leads vivos de una persona (el verificador de
--          disponibilidad, sellado, aplica «un solo lead total por persona» al escribir el DNI en el lead que se convierte y
--          rechazaría la conversión), y el que sigue vivo es el que se convierte; si la casa no deja retirarlo
--          (`private.leads_before_update`: convertido sin perfil del Portal ni cierre inicial; un episodio abierto anómalo), `P0409`
--          «El cliente antiguo no se puede retirar; requiere conciliación de Gerencia» con el error original en el detalle y nada
--          escrito. Ni el dueño ni la etapa del antiguo cambian; el cliente pasa al asesor que convierte porque la persona nace (o
--          sigue) con ese responsable (el bloque de responsable que ya existe en la puerta). Devuelve los candidatos absorbidos.
--      La puerta responde el veredicto con el `P0481` «Contacto no disponible» de la regla del cliente (el mismo error con el que la
--      edición, el INSERT, la base para gestión y las puertas del 2.16 responden esa regla) y el veredicto en el detalle; o sigue.
--   1b. Pieza nueva `private.conversion_enlazar_cliente_antiguo(p_persona, p_candidatos, p_uid)` (INVOKER, volátil, dueño postgres,
--      EXECUTE solo postgres): DESPUÉS del UPDATE que escribe la persona y el DNI en el lead que se convierte (ese UPDATE pasa por el
--      verificador, que contaría un puente como «otro lead de la persona»), pone a cada absorbido el puente HISTÓRICO
--      (`crm.inversionista_leads` rol historico, sin tomar el puntero: el estado que el backfill de identidad y la puerta única dan a
--      un lead convertido de una persona que ya tiene su lead vivo; `creado_por` = quien convierte). Si alguno cambió entre medias,
--      40001 y nada se escribe.
--   2. Pieza nueva `private.lead_historia_de_persona(p_lead, p_persona)` (INVOKER, estable, dueño postgres, EXECUTE solo postgres):
--      «este lead es historia absorbida de esta persona» = puente historico a esa persona, lead convertido, sin puntero y RETIRADO
--      (`activo = false`; D-90: solo los retirados, como los que deja la absorción; un antiguo ya unido por puente y ACTIVO sigue siendo
--      «otro lead», como hoy). La
--      comprobación de conciliación de la puerta («otra identidad o lead») y las de los dos núcleos del contexto de la persona
--      (`private.inversion_persona_contexto_para`, que corre al preparar la solicitud y al confirmarla, y
--      `private.inversion_contexto_lectura_para`, que decide lo que la pantalla puede hacer) dejan de contar esa historia como
--      «otro lead» (por ancla única, una línea cada una): sin eso, la conversión seguiría deteniéndose en el paso siguiente. Para
--      cualquier otra persona nada cambia: un lead canónico, un puntero o un suelto vivo siguen siendo «otro lead». En la PUERTA, desde
--      la ronda 7 (D-91), esa historia solo exime si la puso ESTA conversión (la operación de enlace del antiguo lleva `lead_conversion`
--      = el lead que se convierte); un puente HISTÓRICO a la persona que ya existía ANTES (de Gerencia, de la carga o de la conversión
--      de OTRO lead) ⇒ el `P0409` de conciliación de hoy, nada escrito (una condición más en la misma comprobación) y, desde la ronda
--      8, SOLO cuando esta preparación SOLICITA escribir el DNI del lead, que es cuando corre el verificador sellado (el UPDATE de la puerta
--      cambia el DNI si el documento es un DNI que el lead aún no lleva; en el flujo ordinario auditado eso alcanza el verificador: el disparador de
--      disponibilidad, que esta migración no fija, tiene una salida anticipada para la corrección de documento de Gerencia —la GUC
--      `crm.correccion_documento` bajo la válvula, con la persona conservada—, y que ninguna sesión la conserve al llamar a esta puerta es una PREMISA que
--      se verifica al integrar, con el 2.13 delante, no algo que esta migración demuestre): si el lead YA lleva ese DNI (el estado del backfill de
--      identidad y de la carga: el lead vivo canónico y un convertido retirado con puente histórico) o el documento es un CE o un
--      pasaporte, el verificador no corre y manda D-90 (la historia cuenta y la conversión sigue). Los núcleos mantienen D-90.
--      D-94 (ronda 9, la excepción a esa frase): el «No insistir» de esa historia (los leads de la persona que la pieza de historia reconoce) o de
--      los candidatos que la pieza de absorción tomó detiene SIEMPRE la conversión con la respuesta exacta del alta y del verificador (`P0481`
--      «Contacto no disponible», detalle `{"estado": "no_contactar"}`) y nada escrito, también con el DNI ya escrito o con un CE o un pasaporte, casos
--      en los que el verificador no corre y el veto se saltaba (la ronda 8 convertía y hasta absorbía). Es una comprobación más en la puerta,
--      DESPUÉS de la conciliación (el antiguo que no es historia sigue yendo al `P0409` de hoy y, con el lead SIN DNI, manda el `P0409` de D-91) y ANTES
--      del UPDATE del lead, bajo los candados de hoy: los candidatos ya los tiene tomados la pieza `FOR UPDATE NOWAIT`; la marca de los leads de la
--      historia se lee con un SELECT simple, como la lee el verificador (no se abre ningún candado nuevo). Si la persona volvió por su cuenta, Supervisión
--      o Gerencia levantan la marca con «Quitar No contactar» (`crm.levantar_no_contactar`: levanta la persona y todos sus leads) y se vuelve a convertir.
--   3. Comentarios: a la puerta (hoy sin comentario) se le PONE uno; a los dos núcleos se les AÑADE una frase (la reversa los quita).
--
-- NO CAMBIA (y por qué): los leads sin coincidencia (la pieza devuelve NULL); los clientes CON ficha (puntero o puente: no son
-- candidatos; la conciliación sigue en P0409); un lead vivo NO convertido con ese DNI (suelto vivo: P0409 como hoy); CE y pasaporte
-- (`crm.leads.dni` solo guarda DNI); todo lo que hoy ya rechaza y va antes (42501, 22023, PT409, P0409 «ya está cerrado», P0429); el
-- reintento idempotente de una conversión confirmada; la validación, la solicitud, el comprobante y la confirmación de la inversión;
-- `private.leads_de_personas`, `private.leads_de_identidades`, el verificador, el disparador de disponibilidad, el puente de
-- identidad, tablas, grants, policies ni nada de `public`. Los duplicados que ya existen no se limpian (D-38: «lo que NO cubre»).
-- Concurrencia: no se añade ningún candado nuevo de contacto; la pieza toma la fila de cada candidato FOR UPDATE NOWAIT con los
-- candados de hoy ya tomados (documento → persona → lead que se convierte → candidatos por id): quien edita o retira el lead antiguo
-- a la vez hace fallar la conversión con 40001 (se reintenta) y quien pone ese DNI en otro lead pasa por el candado del documento
-- que la puerta ya toma. La carrera con COMMIT se ensaya en la branch (`supabase/scripts/conversion-cliente-antiguo/f46-contencion-con-commit.sql`).
--
-- PANTALLA: la pantalla de conversión (`inversion-desde-lead.tsx` → `prepararPersonaLeadInversion` → `respuestaInversionistas`)
-- enseña hoy el MENSAJE del servidor («Contacto no disponible»), no «ya es cliente de X»: el veredicto viaja en el detalle, como en
-- la edición antes de D-36. El cambio de app es de otro bloque (descrito en `fase-2/bloque-2.10/salidas/INFORME-ESCRITOR.md`).
--
-- PREFLIGHT (falla cerrada; si algo no coincide no se instala nada): no aplicada (las tres piezas no existen y nadie —función ni
-- trabajo programado— las nombra); la puerta EXACTA (cuerpo d1c9358d…/definición b40dded8…, dueño postgres, DEFINER, volátil, su SET
-- —search_path vacío y lock_timeout 5s—, ACL EXECUTE para authenticated y postgres, SIN comentario); los dos núcleos EXACTOS
-- (b67d8181…/dcc540a4… y b1106c6c…/477d0e80…, DEFINER, volátil, su SET, EXECUTE solo postgres, comentarios 5e022638… y 84620ea8…);
-- la definición completa, el dueño y la ACL efectiva de las 43 funciones que llaman a las tres o deciden su efecto (entre ellas el
-- resolver, los dos enlaces de identidad, el puente, la pieza del 2.8, la puerta de enlace de Gerencia, el núcleo de preparación y la
-- confirmación de la inversión, y las que deciden el retiro y el cierre: `private.leads_before_update`,
-- `private.trg_leads_tenencia_desde`, `private.documento_es_de_identidad`, `private.trg_cierres_externos_inmutables`,
-- `private.f4_fuente_inmutable`, y desde la ronda 4 `private.inversionista_fusion_destino_activo`); que NADIE MÁS nombre a las tres (cuerpos sin distinguir mayúsculas, salvo los conocidos; `pg_depend`;
-- `cron.job`); las restricciones de las que depende la regla (`leads_dni_check`, el rol del puente, el puente único por lead y por
-- persona canónica, el puntero único, el tipo y el motivo del libro de operaciones) y la RLS activa sin grants en el puente y el
-- libro; las PREMISAS de D-83/D-85 y D-86/D-87 (ronda 4: un cierre inicial por lead —`cierres_externos_inicial_por_lead_uidx`—, el
-- documento del cierre y su tipo NOT NULL con su formato, `crm.inversiones.inversionista_id` NOT NULL, el disparador
-- `trg_cierres_externos_00_inmutables` enlazado y activo, el perfil único por persona —`inversionistas_perfil_uidx`— y su clave foránea,
-- y el conjunto exacto y activo de los disparadores de `crm.inversionistas`); el inventario y las definiciones de los 29 `assert_*` que ningún bloque de la fase 2 toca (el trinquete que re-sella el
-- 2.16 solo tiene que existir: esta migración se instala igual antes o después de él) y que los 30 se barren. Fotografía las fichas de las tres funciones y esos
-- `assert_*()` (SIN los `*_mutantes`, como el 2.7/2.8/2.9/2.11/2.16).
-- POSTFLIGHT: las tres piezas EXACTAS (cuerpo, definición, INVOKER, dueño, ACL, comentario); la puerta y los dos núcleos con su cuerpo
-- nuevo EXACTO (en la puerta: la pieza de absorción una vez, la de enlace una vez y después del UPDATE, la de historia tres veces —las dos
-- comprobaciones de conciliación y la de D-94—; la de historia una vez en cada núcleo), la
-- misma ficha que antes y su comentario nuevo EXACTO; las dependencias, los llamadores, las restricciones, las premisas y la RLS intactos; nadie
-- más que las tres usa las piezas; el inventario de los `assert_*` el de antes y su foto EXACTAMENTE igual. Sin DDL de tablas.
--
-- LO QUE DECIDE EL EFECTO Y NO SE FIJA (y por qué): `private.trg_leads_disponibilidad_atomica` y
-- `private.verificar_disponibilidad_lead_impl` (el 2.13 cambia el disparador y las bases cargadas fijan el verificador; lo que esta
-- migración necesita de ellos —que el verificador corra al escribir el DNI y no juzgue el retiro— se MIDE en el oráculo);
-- `private.trg_leads_sync_tareas` (cancela como `sistema` las tareas pendientes del antiguo retirado: efecto de la casa, medido, no de
-- esta regla); `private.trg_leads_asignaciones` (el ledger: con el episodio cerrado no escribe; con uno abierto anómalo rechaza:
-- límite); `private.trg_leads_zz_reapertura_solo_rpc` (lo fija el 2.16); `private.trg_leads_guard_tenencia`;
-- `private.log_audit_sin_secretos` (la auditoría del retiro y del cierre, sin el documento); `private.f4_sincronizar_cierre` y
-- `private.conversion_acreditacion_evento_trg` (no se disparan: sus UPDATE OF no incluyen `inversionista_id`); `private.juicio_persona`
-- e `private.inversionista_canonica` (los fijan el 2.11 y el 2.16; aquí solo se leen); `private.no_asignar_usuario_retirado` y
-- `private.set_actualizado_en_crm` (funciones de la casa que comparten muchas tablas —leads, tareas, perfiles, equipo, personas—: lo
-- que necesita de ellas el enlace del perfil se MIDE en el oráculo, A1l). LÍMITES medidos o razonados (P3-2 del auditor):
-- (i) un antiguo ACTIVO del mismo asesor sin perfil del Portal ni cierre inicial no se puede retirar ⇒ P0409 «El cliente antiguo no
-- se puede retirar; requiere conciliación de Gerencia» (en el detalle, solo el código del error original; el texto va al registro del
-- servidor) y nada escrito; (ii) un convertido sin persona con perfil del Portal ACTIVO con ese DNI: el verificador responde «ya es
-- cliente de <asesor del perfil>» por el perfil (P0481) al escribir el DNI y todo se deshace, como hoy (medido, A1l-c); si ese perfil es
-- de OTRA persona, ahora se detiene antes con el P0409 de D-86; (iii) un convertido activo con episodio abierto anómalo ⇒ el mismo
-- P0409 (el ledger rechaza); (iv, D-89) el perfil propio DESACTIVADO no se enlaza: la conversión sigue sin él (medido, A1m; en la ronda 4
-- se enlazaba y el núcleo detenía la preparación con «El perfil Avance requiere revisión antes de operar»); (v) un cambio simultáneo del perfil (su documento, o enlazarlo a otra persona) es carrera de F4.6: lo segundo lo frena
-- el índice único (40001); (vi, Codex r2, medido por el Director como M3) un perfil ACTIVO del Portal con el mismo DNI o teléfono y el lead que YA
-- lleva el DNI: el verificador no corre y la conversión sigue como hoy (hoy `ok`, ronda 8 `ok`); el alta de un lead nuevo con ese DNI sí lo frena. D-94 no lo
-- cambia (solo el No insistir del antiguo): queda para el bloque de D-92. El conteo D-82 los dimensiona antes de publicar.
-- D-88 (aceptado por Miguel): quien convierte ve la ficha del antiguo —su dinero (cierres: monto, cooperativa, tasa, número, asesor de
-- origen, comprobante) y su historia— desde ESTA preparación, aunque no confirme la inversión: es la consecuencia de D-38 + D-83 (la
-- persona tiene fuentes y su responsable es quien convierte). Queda el rastro: el libro de operaciones (`por`), el `audit_log` del
-- cierre y las lecturas de la ficha (`private.cartera_f5_registrar('ficha')`).
-- «RETIRADO ⇒ SE ABSORBE Y CONVIERTE» TIENE EXCEPCIONES (todas detienen sin escribir): la persona del DNI ya tiene otro responsable
-- (el `P0409` de responsable: A1fb); un perfil del Portal ACTIVO coincide con el DNI o el teléfono del lead (P0481, límite ii: A1n); el
-- antiguo tiene No insistir (P0481 `no_contactar`: A15/A20; desde la ronda 9, D-94, también el retirado ya unido o por absorber cuando el lead ya
-- lleva el DNI o el documento es un CE o un pasaporte: A1w, A1wc, A1wv); el retiro es imposible (P0409: A4c); D-84, D-85 y D-86; y (D-91, ronda 7,
-- limitado en la ronda 8 al caso en que la conversión ESCRIBE el DNI) un antiguo RETIRADO que YA estaba unido por puente histórico a la
-- persona ANTES de esta preparación, con el lead que se convierte SIN ese DNI ⇒ el `P0409` «Esta persona ya tiene otra identidad o
-- lead; requiere conciliación» de hoy, nada escrito (A1r; también con otro antiguo del mismo DNI por absorber, A1r2, y con la operación
-- de enlace de OTRA conversión, A1r3; en la ronda 6 la conciliación lo dejaba pasar y el verificador sellado paraba con P0481 «ya es
-- cliente» vía identidad); el mismo ACTIVO, igual (A1s); la conversión de OTRO lead de una persona ya absorbida, igual (A1t, A1tb).
-- Si el lead YA lleva ese DNI (A1u, A1u2) o el documento es un CE (A1v), el verificador no corre y el retirado ya unido cuenta como
-- historia (D-90): la conversión SIGUE y la confirmación entra (salvo que ese antiguo tenga No insistir: D-94, A1w, A1wv). El REINTENTO de la misma preparación sigue (A13: ya lleva el DNI y esta
-- comprobación no lo evalúa; su primera llamada dejó el puente con `lead_conversion` = ese lead). DEUDA (D-92, con H-3): un bloque
-- corto posterior al grupo C, con su plan aprobado por Miguel, ajustará el verificador
-- (`private.verificar_disponibilidad_lead_impl` / su disparador) para que esos antiguos RETIRADOS ya unidos conviertan sin trámite (lo
-- que pedía D-90) y resolverá H-3 (`private.juicio_cliente_convertido`: el alta con el TELÉFONO de un antiguo absorbido nombra al
-- asesor viejo).
-- CUÁNDO SE DETIENE LA CONVERSIÓN (nada escrito; el mensaje es el de la casa): cliente CON ficha, un lead vivo de la persona, o un
-- antiguo RETIRADO ya unido por puente histórico ANTES de esta preparación cuando ésta ESCRIBE el DNI del lead (D-91; si el lead ya lo
-- lleva, o el documento es un CE o un pasaporte, no: D-90) ⇒ P0409 «requiere conciliación» (como hoy); cliente
-- antiguo ACTIVO de otro asesor ⇒ P0481 con «ya es cliente de X» en el detalle; antiguo (retirado ya unido que cuenta como historia, o candidato de
-- la absorción) con No insistir ⇒ P0481 «Contacto no disponible» con {"estado": "no_contactar"} (D-94; también con el DNI ya escrito, un CE o un
-- pasaporte); su cierre
-- es de OTRA persona ⇒ P0409 (D-84); su cierre lleva otro documento ⇒ P0409 (D-85); su perfil del Portal es de OTRA persona, la ficha
-- ya tiene otro perfil o el perfil lleva otro documento ⇒ P0409 (D-86, también con la cuenta desactivada); no se puede retirar ⇒ P0409
-- (P3-2.i); otra operación tiene la fila del antiguo o de su cierre, o la cuenta del Portal cambió mientras se enlazaba ⇒ 40001 (se
-- reintenta). CUÁNDO SE ENLAZA EL PERFIL (D-87): de nadie, la ficha sin otro, su documento de la persona y la cuenta NO desactivada; si
-- está desactivada (D-89), no se enlaza y la conversión sigue.
--
-- CÓMO SE REVIERTE: `supabase/scripts/conversion-cliente-antiguo/reversa.sql` (falla cerrada: antes de revertir exige las tres piezas, la
-- puerta y los dos núcleos con su cuerpo, su ficha y su comentario EXACTOS como los deja esta migración; las 43 dependencias, los
-- llamadores conocidos y que nadie más use las piezas; las restricciones, los índices únicos y la RLS del puente y del libro; las
-- PREMISAS de D-83/D-85 y D-86/D-87 —ronda 6: índices del cierre y del perfil, FK del perfil, NOT NULL y CHECK del documento,
-- `crm.inversiones.inversionista_id` NOT NULL, los disparadores de inmutables, de `leads_before_update` y de tenencia habilitados y el
-- conjunto de disparadores de `crm.inversionistas`— y el inventario de los trinquetes; repone las tres funciones por ancla única, quita el comentario de la puerta y la frase de los
-- dos núcleos, y borra las tres piezas sin CASCADE). LO QUE LA REVERSA NO DESHACE (datos): los puentes históricos, los retiros, las
-- operaciones del libro, los cierres iniciales completados (D-83) y los perfiles del Portal enlazados a la ficha (D-87) que la regla haya
-- escrito se quedan (son el estado que el backfill de identidad y la puerta de enlace de Gerencia ya producen; revertirlos sería una
-- fusión inversa de Gerencia). Tras revertir, la conversión con el DNI de un cliente antiguo sin ficha vuelve a crear una persona nueva
-- (retirado) o a pedir conciliación (activo); y una conversión PREPARADA y no confirmada que ya absorbió historia se detiene al seguir
-- (preparar la solicitud) con «La persona ya tiene una conversión inicial; requiere conciliación» (P0409: el núcleo vuelve a contar el
-- puente histórico como otro lead; medido en la ronda 4). Reversas LIFO: esta antes que la del 2.16 y la del 2.11 solo si se quiere volver al punto de partida; no
-- bloquea la reversa de ninguno de los dos (no toca lo que fijan) y ninguno bloquea la suya.
-- RESELLE C1 (13/10/2026): `crm.inversionista_ficha_fn(uuid,integer,integer)` se fija ahora por la huella de producción del 13/10 (`9d981c6c…`, antes `d0c6543b…`: la Fase 6 de Facturación, migración `20261010203951`, le añadió `analista_venta_id` y `analista_venta_nombre` por inversión; la autorización de lectura, la firma, los permisos y las filas que ve quien convierte, D-88, no cambian); la regla no cambia.
-- RESELLE C2 (22/10/2026, plan AVANCE-BACKEND-1310-C2): re-asentado contra producción del 22/10: la puerta crm.preparar_persona_lead_inversion_fn (4eebf912…/df451bd3…, antes d1c9358d…/b40dded8…: «retomar» y private.recorrido_exigir de 20261019001700; las tres anclas aplican tal cual y el cuerpo parcheado conserva esas líneas; después da360b19…/f921422d…, antes eda40bbe…/f0e6a96b…), seis dependencias (acceso_inversion_fn b45c309f…, confirmar_inversion_revisada_fn 33af606a…, inversionista_ficha_fn be113f3c… —D-88 intacta: quien convierte ve la misma ficha—, f4_comprobante_autorizado cdecad21…, f4_fuente_inmutable f4608368…, trg_cierres_externos_inmutables c9f55c70…) y el censo de los 29 private.assert_*() (29|60a08512…, antes 29|a11bf250…); reversa regenerada; regla, mensajes y candados sin cambio.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $pf$
declare
  v_puerta regprocedure := to_regprocedure('crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)');
  v_escritura regprocedure := to_regprocedure('private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid)');
  v_lectura regprocedure := to_regprocedure('private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid)');
  v_mal text;
  r record;
  v text;
  v_foto text := '';
begin
  if v_puerta is null or v_escritura is null or v_lectura is null then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: falta la puerta de conversión o uno de los dos núcleos del contexto de la persona';
  end if;
  -- Ya aplicada: las piezas no existen y nadie las nombra todavía (función por su cuerpo, sin distinguir mayúsculas; trabajo programado).
  if to_regprocedure('private.conversion_absorber_cliente_antiguo(uuid,uuid,text,uuid,uuid)') is not null
     or to_regprocedure('private.conversion_enlazar_cliente_antiguo(uuid,jsonb,uuid)') is not null
     or to_regprocedure('private.lead_historia_de_persona(uuid,uuid)') is not null
     or exists (select 1 from pg_proc p where p.proname in ('conversion_absorber_cliente_antiguo', 'conversion_enlazar_cliente_antiguo', 'lead_historia_de_persona')) then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: alguna de las tres piezas ya existe: esta migración ya está aplicada (o hay un objeto con su nombre)';
  end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v_mal
  from pg_proc p where strpos(lower(p.prosrc), 'conversion_absorber_cliente_antiguo') > 0 or strpos(lower(p.prosrc), 'conversion_enlazar_cliente_antiguo') > 0
     or strpos(lower(p.prosrc), 'lead_historia_de_persona') > 0;
  if v_mal is null and to_regclass('cron.job') is not null then
    execute $q$select string_agg('cron.job ' || j.jobid::text, ', ') from cron.job j
                where strpos(lower(j.command), 'conversion_absorber_cliente_antiguo') > 0 or strpos(lower(j.command), 'conversion_enlazar_cliente_antiguo') > 0
                   or strpos(lower(j.command), 'lead_historia_de_persona') > 0$q$ into v_mal;
  end if;
  if v_mal is not null then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: otro posible llamador de las piezas nuevas antes de que existan (%): esta migración ya está aplicada o hay un objeto escrito de antemano', v_mal;
  end if;
  -- La puerta de conversión: cuerpo, definición, ficha y comentario (ninguno) EXACTOS (texto vivo de producción).
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_puerta) is distinct from '4eebf912d4abc0b101e3c39688dc0c54/df451bd3cc831e2b47a26eb867c9e65e' then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: crm.preparar_persona_lead_inversion_fn no es la auditada (md5 del cuerpo / de la definición %; se esperaba 4eebf912d4abc0b101e3c39688dc0c54/df451bd3cc831e2b47a26eb867c9e65e): revisar el cuerpo vivo antes de parchear',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_puerta);
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_puerta and p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.provolatile = 'v'
                   and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_puerta)
        is distinct from 'authenticated:EXECUTE:false,postgres:EXECUTE:false'
     or has_function_privilege('anon', v_puerta, 'EXECUTE') or has_function_privilege('service_role', v_puerta, 'EXECUTE') then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: la ficha de crm.preparar_persona_lead_inversion_fn no es la auditada (dueño postgres, security definer, volátil, su SET, ACL authenticated:EXECUTE:false,postgres:EXECUTE:false)';
  end if;
  if obj_description(v_puerta, 'pg_proc') is not null then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: crm.preparar_persona_lead_inversion_fn ya tiene comentario (md5 %); esta migración le pone uno y la reversa lo quita: revisar antes', md5(obj_description(v_puerta, 'pg_proc'));
  end if;
  -- El núcleo del contexto operativo (escritura): cuerpo, definición, ficha y comentario EXACTOS.
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_escritura) is distinct from 'b67d8181139ab76ff9232523a67dfa11/dcc540a48b7f252c783f814f6a184144' then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: private.inversion_persona_contexto_para no es la auditada (md5 del cuerpo / de la definición %; se esperaba b67d8181139ab76ff9232523a67dfa11/dcc540a48b7f252c783f814f6a184144): revisar el cuerpo vivo antes de parchear',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_escritura);
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_escritura and p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.provolatile = 'v'
                   and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_escritura)
        is distinct from 'postgres:EXECUTE:false'
     or has_function_privilege('anon', v_escritura, 'EXECUTE') or has_function_privilege('service_role', v_escritura, 'EXECUTE') or has_function_privilege('authenticated', v_escritura, 'EXECUTE') then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: la ficha de private.inversion_persona_contexto_para no es la auditada (dueño postgres, security definer, volátil, su SET, ACL postgres:EXECUTE:false)';
  end if;
  if md5(coalesce(obj_description(v_escritura, 'pg_proc'), '')) is distinct from '5e0226384bc1c2db4fa72bb8dad54fff' then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: el comentario de private.inversion_persona_contexto_para no es el auditado (md5 %); revisar antes de añadirle nada (la reversa lo repone)', md5(coalesce(obj_description(v_escritura, 'pg_proc'), ''));
  end if;
  -- El núcleo del contexto de lectura: cuerpo, definición, ficha y comentario EXACTOS.
  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_lectura) is distinct from 'b1106c6c67be483f8fb655a276e3def4/477d0e80266faa6add30929337f00701' then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: private.inversion_contexto_lectura_para no es la auditada (md5 del cuerpo / de la definición %; se esperaba b1106c6c67be483f8fb655a276e3def4/477d0e80266faa6add30929337f00701): revisar el cuerpo vivo antes de parchear',
      (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_lectura);
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_lectura and p.proowner = 'postgres'::regrole::oid and p.prosecdef and p.provolatile = 'v'
                   and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_lectura)
        is distinct from 'postgres:EXECUTE:false'
     or has_function_privilege('anon', v_lectura, 'EXECUTE') or has_function_privilege('service_role', v_lectura, 'EXECUTE') or has_function_privilege('authenticated', v_lectura, 'EXECUTE') then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: la ficha de private.inversion_contexto_lectura_para no es la auditada (dueño postgres, security definer, volátil, su SET, ACL postgres:EXECUTE:false)';
  end if;
  if md5(coalesce(obj_description(v_lectura, 'pg_proc'), '')) is distinct from '84620ea87a16f7610aa05d3a636b3623' then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: el comentario de private.inversion_contexto_lectura_para no es el auditado (md5 %); revisar antes de añadirle nada (la reversa lo repone)', md5(coalesce(obj_description(v_lectura, 'pg_proc'), ''));
  end if;
  -- Lo que llama a las tres o decide su efecto: su DEFINICIÓN COMPLETA (cuerpo y atributos), su dueño y su ACL EFECTIVA.
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.acceso_inversion_fn(uuid,text,jsonb)', 'b45c309fce1003058ee42de5804d95a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.buscar_cliente_existente_fn(text,text,text,uuid)', '43b317c13c40471a3e3eec2fbbe0fb8a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.confirmar_inversion_fn(uuid)', 'e69358303d4b6220354460965179c28d', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.confirmar_inversion_revisada_fn(uuid,integer)', '33af606a814c74de5de8a080430bb299', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.contexto_cliente_existente_fn(uuid,uuid)', '8cd36f9311dd59327fa749f4568861cb', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.contexto_conversion_inversion_fn(uuid,uuid)', 'a616232e3ada628404fc6a1a8356eb13', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)', 'c41aa8ee34da4b3f828289058c41e4f4', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.enlazar_lead_inversionista_fn(uuid,uuid,text)', '1159aa8443c117c8c9384a2bcf17ae2b', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.inversionista_ficha_fn(uuid,integer,integer)', 'be113f3c638e3fdf6e0ca9a45eb86a6d', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.preparar_inversion_fn(uuid,jsonb)', '5fefbc143578a735a8648f686f71bf9a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text)', 'dc622b938e8d8e9777a033cfa625b11a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.documento_es_de_identidad(uuid,text,text)', '724c4c781b1ed289a5320ab6c9d2eea8', 'postgres:EXECUTE:false'),
    ('private.f4_comprobante_autorizado(text)', 'cdecad21e77c38d023ba156efd8faa74', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.f4_fuente_inmutable()', 'f4608368a957e5ce1fe191562d5b5bea', 'postgres:EXECUTE:false'),
    ('private.identidad_bloquear_documento(text,text)', '9c08b500af7bc11aeba5e0e7d3a63330', 'postgres:EXECUTE:false'),
    ('private.identidad_bloquear_documentos_de(uuid[])', '81dffba49b46f2defc723e53a9a96d67', 'postgres:EXECUTE:false'),
    ('private.inversion_contexto_lectura(uuid,uuid)', '7ae71408f49ecd1eb2a05ed746746dde', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_autorizada_para(uuid,uuid,uuid)', 'c91e82b30558d121782f94aefab39d6e', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_contexto(uuid)', '335fa43d5eed5d0d8010d9d0716483ce', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_contexto(uuid,uuid)', 'a7ce8164838edc6b64cdc3f933c5a276', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_lectura_para(uuid,uuid,uuid)', '6539960f2d9b7896e2c4083f80361f57', 'postgres:EXECUTE:false'),
    ('private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text)', 'c34bc06eafdb62f128476a8bffbfa642', 'postgres:EXECUTE:false'),
    ('private.inversiones_escritura_bajo_candado()', '2122bbf3b22996f2e8373081a259db9b', 'postgres:EXECUTE:false'),
    ('private.inversionista_canonica(uuid)', '34702897135078893b7d3a726b0c1816', 'postgres:EXECUTE:false'),
    ('private.inversionista_fusion_destino_activo()', '861f359c23ab031945f4bad75f8dc3a7', 'postgres:EXECUTE:false'),
    ('private.inversionista_operaciones_append_only()', '909d41d42674ccb6775597fd4235ebca', 'postgres:EXECUTE:false'),
    ('private.inversionista_resolver(text,text,boolean,text)', '95d502fcae257bf2a439ec3e4aa6a2dc', 'postgres:EXECUTE:false'),
    ('private.juicio_cliente_convertido(text,text,text,uuid)', 'a2b38faf42a875c7dffb7968b106e36f', 'postgres:EXECUTE:false'),
    ('private.juicio_persona(uuid,uuid)', '69794e137dd642e0b529612fb2a623eb', 'postgres:EXECUTE:false'),
    ('private.leads_before_update()', '4ae909f2d56ca650b5595b505e6aa51d', 'postgres:EXECUTE:false'),
    ('private.leads_de_identidades(uuid[])', '2421b2b78b02b8e93fd01598e2f54128', 'postgres:EXECUTE:false'),
    ('private.leads_de_personas(uuid[])', '6eded477639796c1053f0190f6decc18', 'postgres:EXECUTE:false'),
    ('private.leads_protege_inversionista_id()', '6151f6d4da6c80fc62ad7f131ea398a4', 'postgres:EXECUTE:false'),
    ('private.log_audit_crm()', 'c25c2af183b650f4d4c85abedd5bcc97', 'postgres:EXECUTE:false'),
    ('private.puede_gestionar_contratos_crm()', '94b5fb2af92bf4187802b1f3d26659c5', 'postgres:EXECUTE:false'),
    ('private.resolver_en_puertas_bajo_candado()', '5f74d26262fcc83e5975672da141be63', 'postgres:EXECUTE:false'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.trg_cierres_externos_inmutables()', 'c9f55c70e526975476b1f6aead562cd4', '-:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.trg_gestion_lead_serializada()', '7af0e66b8a4849566e43b514245e1b86', 'postgres:EXECUTE:false'),
    ('private.trg_leads_tenencia_desde()', '900508fa3ccf3eec2e738ccdeebad7be', 'postgres:EXECUTE:false'),
    ('private.trg_leads_zz_enlaza_identidad()', '6ea5abfcc7bc7113f62f175df4e65879', 'postgres:EXECUTE:false'),
    ('private.trg_leads_zz_puente_identidad()', 'e96f21d1c58623f6c2a84e7c04683a5c', 'postgres:EXECUTE:false'),
    ('private.vendedor_ids_visibles(uuid)', '85544c70a0920f3a7a1b5da06935f236', 'authenticated:EXECUTE:false,postgres:EXECUTE:false')) e(firma, definicion, acl)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null
     or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion
     or p.proowner is distinct from 'postgres'::regrole::oid
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) is distinct from e.acl;
  if v_mal is not null then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: cambió algo que llama a las tres funciones o decide su efecto: definición, dueño o permisos; lo ensayado no valdría (%)', v_mal;
  end if;
  -- Nadie más nombra a las tres (el cambio lo alcanzaría): ni otra función por su cuerpo (sin distinguir mayúsculas; se exceptúan los
  -- llamadores conocidos de los dos núcleos), ni un objeto registrado en pg_depend, ni un trabajo programado. Un «posible llamador»
  -- bloquea de forma conservadora.
  select string_agg(x.f, ', ' order by x.f) into v_mal
  from (select p.oid::regprocedure::text as f
          from pg_proc p
         where (strpos(lower(p.prosrc), 'preparar_persona_lead_inversion_fn') > 0 and p.oid <> v_puerta)
            or (strpos(lower(p.prosrc), 'inversion_persona_contexto_para') > 0
                and p.oid not in (v_escritura, v_lectura,
                                  coalesce(to_regprocedure('private.inversion_persona_contexto(uuid,uuid)'), 0),
                                  coalesce(to_regprocedure('private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text)'), 0),
                                  coalesce(to_regprocedure('crm.confirmar_inversion_revisada_fn(uuid,integer)'), 0),
                                  coalesce(to_regprocedure('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)'), 0),
                                  coalesce(to_regprocedure('crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text)'), 0),
                                  coalesce(to_regprocedure('crm.acceso_inversion_fn(uuid,text,jsonb)'), 0),
                                  coalesce(to_regprocedure('private.f4_comprobante_autorizado(text)'), 0)))
            or (strpos(lower(p.prosrc), 'inversion_contexto_lectura_para') > 0
                and p.oid not in (v_escritura, v_lectura,
                                  coalesce(to_regprocedure('private.inversion_contexto_lectura(uuid,uuid)'), 0),
                                  coalesce(to_regprocedure('crm.buscar_cliente_existente_fn(text,text,text,uuid)'), 0),
                                  coalesce(to_regprocedure('crm.contexto_cliente_existente_fn(uuid,uuid)'), 0)))
        union all
        select pg_describe_object(d.classid, d.objid, d.objsubid)
          from pg_depend d
         where d.refclassid = 'pg_proc'::regclass and d.refobjid in (v_puerta, v_escritura, v_lectura)) x;
  if v_mal is null and to_regclass('cron.job') is not null then
    execute $q$select string_agg('cron.job ' || j.jobid::text, ', ') from cron.job j
                where strpos(lower(j.command), 'preparar_persona_lead_inversion_fn') > 0 or strpos(lower(j.command), 'inversion_persona_contexto_para') > 0
                   or strpos(lower(j.command), 'inversion_contexto_lectura_para') > 0$q$ into v_mal;
  end if;
  if v_mal is not null then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: otro posible llamador de la puerta o de los núcleos (%): el cambio lo alcanzaría; inspeccionar antes de seguir', v_mal;
  end if;
  -- Las premisas de la regla: el DNI de ocho dígitos (la comparación literal), el rol del puente (historico existe), el puente único por
  -- lead y por persona canónica, el puntero único de crm.leads, el tipo «enlace» y el motivo del libro de operaciones; la RLS activa y
  -- sin grants a la Data API en el puente y en el libro (lo escriben solo las piezas DEFINER, como la puerta de enlace de Gerencia).
  select string_agg(e.nombre, ', ' order by e.nombre) into v_mal
  from (values
    ('crm.leads', 'leads_dni_check', '6dcca3c962687ba896d101adf845d281'),
    ('crm.inversionista_leads', 'inversionista_leads_rol_check', 'f6a33854861793c8dc204e1b32c07716'),
    ('crm.inversionista_leads', 'inversionista_leads_lead_id_fkey', 'c6c7de31923066a9f3b843e9c875aec6'),
    ('crm.inversionista_leads', 'inversionista_leads_inversionista_id_fkey', '99bee63006ab85e4e5c1d5fdf071a137'),
    ('crm.inversionista_leads', 'inversionista_leads_creado_por_fkey', '8b21ba4ae6f1720bfba13340e69e1f2e'),
    ('crm.inversionista_operaciones', 'inversionista_operaciones_tipo_check', 'c3b74a13c0bd2414b83c800af4f02d4b'),
    ('crm.inversionista_operaciones', 'inversionista_operaciones_motivo_check', '6c884dea657b7a534f19f04abd86d684')) e(tabla, nombre, definicion)
  left join pg_constraint c on c.conrelid = e.tabla::regclass and c.conname = e.nombre
  where c.oid is null or not c.convalidated or md5(pg_get_constraintdef(c.oid)) is distinct from e.definicion;
  if v_mal is not null then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: cambió o falta una restricción de la que depende la regla (%)', v_mal;
  end if;
  select string_agg(e.nombre, ', ' order by e.nombre) into v_mal
  from (values
    ('leads_inversionista_uidx', 'a9f9b423261a56190a909eeea80a4a27'),
    ('inversionista_leads_lead_uidx', md5('CREATE UNIQUE INDEX inversionista_leads_lead_uidx ON crm.inversionista_leads USING btree (lead_id)')),
    ('inversionista_leads_canonico_uidx', md5('CREATE UNIQUE INDEX inversionista_leads_canonico_uidx ON crm.inversionista_leads USING btree (inversionista_id) WHERE (rol = ''canonico''::text)'))) e(nombre, definicion)
  left join pg_indexes i on i.schemaname = 'crm' and i.indexname = e.nombre
  where i.indexname is null or md5(i.indexdef) is distinct from e.definicion;
  if v_mal is not null then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: cambió o falta un índice único del que depende la regla (%)', v_mal;
  end if;
  if exists (select 1 from pg_class c where c.oid in ('crm.inversionista_leads'::regclass, 'crm.inversionista_operaciones'::regclass)
               and (not c.relrowsecurity or c.relacl is not null or c.relowner <> 'postgres'::regrole::oid)) then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: el puente persona-lead o el libro de operaciones ya no es como se auditó (RLS activa, sin grants, dueño postgres)';
  end if;
  -- Las premisas de D-83/D-85 (el cierre) y de D-86/D-87 (el perfil), fijadas (auditor r2): a lo sumo un cierre inicial por lead; el
  -- documento del cierre y su tipo NOT NULL y con su formato (por eso no hay rama «sin documento»); crm.inversiones.inversionista_id NOT
  -- NULL (un cierre sin persona no tiene inversión); el disparador de inmutables del cierre, enlazado y activo; el perfil único por
  -- persona no fusionada (la carrera da 23505, que la pieza de enlace traduce al 40001) y su clave foránea; los disparadores de
  -- crm.inversionistas que reaccionan al completar el perfil (su conjunto exacto y activo).
  select string_agg(z.x, ', ' order by z.x) into v_mal
  from (
    select 'restricción ' || e.nombre as x
    from (values
      ('crm.cierres_externos', 'cierres_externos_documento_formato', 'e5f8b87595e008282602e238bf581984'),
      ('crm.cierres_externos', 'cierres_externos_documento_tipo_check', 'e2c34a1a34e26c147329f046c1e1da5b'),
      ('crm.inversionistas', 'inversionistas_perfil_id_fkey', '7f74ba99b1e24898320e925b0cd3563a')) e(tabla, nombre, definicion)
    left join pg_constraint c on c.conrelid = e.tabla::regclass and c.conname = e.nombre
    where c.oid is null or not c.convalidated or md5(pg_get_constraintdef(c.oid)) is distinct from e.definicion
    union all
    select 'índice ' || e.nombre
    from (values
      ('cierres_externos_inicial_por_lead_uidx', 'cf8c81018d22bd499463d6cd8f101f6b'),
      ('inversionistas_perfil_uidx', '9bda30dce00b9694bc5aab719b053305')) e(nombre, definicion)
    left join pg_indexes i on i.schemaname = 'crm' and i.indexname = e.nombre
    where i.indexname is null or md5(i.indexdef) is distinct from e.definicion
    union all
    select 'NOT NULL ' || e.tabla || '.' || e.columna
    from (values ('crm.cierres_externos', 'documento'), ('crm.cierres_externos', 'documento_tipo'), ('crm.inversiones', 'inversionista_id')) e(tabla, columna)
    left join pg_attribute a on a.attrelid = e.tabla::regclass and a.attname = e.columna and not a.attisdropped
    where a.attnum is null or not a.attnotnull
    union all
    select 'disparador trg_cierres_externos_00_inmutables'
    where not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_cierres_externos_00_inmutables'
                        and t.tgenabled = 'O' and md5(pg_get_triggerdef(t.oid)) = 'e6e9970fea6f192205d0000d5b5f3dc6')
    union all
    select 'disparador ' || e.nombre
    from (values
      ('trg_leads_before_update', '02b8824f01e2f5aa026f478241711c8a'),
      ('trg_leads_zzz_tenencia_desde', 'f5849e264eb05e8a253dbd78c2362fba')) e(nombre, definicion)
    where not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = e.nombre and t.tgenabled = 'O'
                        and md5(pg_get_triggerdef(t.oid)) = e.definicion)
    union all
    select 'disparadores de crm.inversionistas'
    where (select count(*) || '|' || md5(string_agg(t.tgname || ':' || t.tgenabled::text || ':' || pg_get_triggerdef(t.oid), '|' order by t.tgname))
             from pg_trigger t where t.tgrelid = 'crm.inversionistas'::regclass and not t.tgisinternal) is distinct from '5|104c0bb1234815233ef1bfe823936553'
  ) z;
  if v_mal is not null then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: cambió o falta una premisa del cierre o del perfil (%)', v_mal;
  end if;
  -- El inventario y las DEFINICIONES de los trinquetes que se barren abajo, ANTES del primer barrido: tienen que ser los auditados
  -- (no se exige que pasen; se exige que sean ellos). Se fijan los 29 que ningún bloque de la fase 2 toca; el trinquete
  -- private.assert_gestion_diaria_resultado() lo RE-SELLA el 2.16 (su huella es suya y cambia con sus rondas): de él solo se exige
  -- que exista. Así esta migración se instala igual antes o después del 2.16 (el orden fijado es después).
  if (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0 and p.proname <> 'assert_gestion_diaria_resultado')
     is distinct from '29|60a0851245859d8e1f0da6e2276a2594'
     or to_regprocedure('private.assert_gestion_diaria_resultado()') is null then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: los private.assert_*() que barre la migración no son los auditados (inventario o definiciones de los 29 que no re-sella el 2.16: %; y el trinquete private.assert_gestion_diaria_resultado() tiene que existir); revisarlos antes de barrerlos',
      (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0 and p.proname <> 'assert_gestion_diaria_resultado');
  end if;
  -- Fotos para el postflight: las fichas de las tres funciones y los private.assert_*() sin argumentos y SIN los `*_mutantes`
  -- (estado y texto íntegro del primer error: se exige que NO cambien, no que pasen).
  perform set_config('conversion_cliente_antiguo.puerta_antes', (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_puerta), true);
  perform set_config('conversion_cliente_antiguo.escritura_antes', (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_escritura), true);
  perform set_config('conversion_cliente_antiguo.lectura_antes', (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_lectura), true);
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
  perform set_config('conversion_cliente_antiguo.trinquetes_antes', v_foto, true);
end
$pf$;

-- ── 1. La pieza de absorción: los clientes antiguos sin ficha con ese DNI, FOR UPDATE NOWAIT; el veredicto, o el rastro y el retiro ──
create function private.conversion_absorber_cliente_antiguo(p_lead uuid, p_persona uuid, p_dni text, p_vendedor uuid, p_uid uuid)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  v_dni text := nullif(pg_catalog.btrim(p_dni), '');
  v_previo text;
  v_c record;
  v_candidatos jsonb := '[]'::jsonb;
  v_veredicto jsonb;
  v_op uuid;
  v_n integer;
  v_ce crm.cierres_externos%rowtype;
  v_cierre uuid;
  v_cierre_motivo text;
  v_pdni text;
  v_ptipo text;
  v_perfil_de uuid;
  v_perfil_ficha uuid;
  v_perfil_enlazar uuid;
  v_pactivo boolean;
  v_prol text;
  v_pdesactivada boolean;
  v_perfil_no_enlazado uuid;
  v_perfil_motivo text;
  v_salida jsonb := '[]'::jsonb;
begin
  -- Bloque 2.10 (D-38, D-81, D-83, D-84, D-85, D-86, D-87, D-88, D-89). Contrato: quien llama ya tiene tomados el candado del documento, la persona FOR UPDATE y la fila del lead que
  -- se convierte FOR UPDATE; aquí se toman las de los CANDIDATOS (orden de la casa: documento → persona → lead → candidatos por id).
  if p_lead is null or p_persona is null or p_vendedor is null or p_uid is null or v_dni is null then
    return null;
  end if;
  -- 1. Los candidatos: leads CONVERTIDOS sin persona (sin puntero y sin puente) cuyo DNI es el de la conversión, distintos del que se
  --    convierte, FOR UPDATE NOWAIT (si otra operación tiene alguno —editar, retirar, enlazar—, 40001 con el mensaje de la casa y
  --    nada se escribe: se reintenta). La prioridad es la de la regla del cliente (2.7/2.8): activo → más reciente → id.
  begin
    for v_c in
      select l.id, l.activo, l.vendedor_id, l.perfil_id,
             coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
      from crm.leads l
      left join public.perfiles pv on pv.id = l.vendedor_id
      left join public.perfiles ps on ps.id = l.asignado_supervisor_id
      where l.etapa = 'convertido'
        and l.inversionista_id is null
        and l.dni = v_dni
        and l.id <> p_lead
        and not exists (select 1 from crm.inversionista_leads il where il.lead_id = l.id)
      order by l.activo desc, l.convertido_en desc nulls last, l.id
      for update of l nowait
    loop
      -- 2. Un cliente antiguo que sigue ACTIVO a nombre de OTRO asesor manda: «ya es cliente de X», con el formato y los datos del alta
      --    para un convertido sin persona (D-29): el dueño de esa ficha (vendedor o bandeja del supervisor; si no, «sin asesor asignado»).
      if v_c.activo and v_c.vendedor_id is distinct from p_vendedor then
        if v_veredicto is null then
          v_veredicto := pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(v_c.tenedor, 'sin asesor asignado'));
        end if;
      else
        v_candidatos := v_candidatos || pg_catalog.jsonb_build_object('id', v_c.id, 'activo', v_c.activo, 'vendedor_id', v_c.vendedor_id, 'perfil_id', v_c.perfil_id);
      end if;
    end loop;
  exception when lock_not_available then
    raise exception 'El lead está en uso por otra operación; vuelve a intentarlo' using errcode = '40001';
  end;
  if v_veredicto is not null then
    return pg_catalog.jsonb_build_object('veredicto', v_veredicto);
  end if;
  if pg_catalog.jsonb_array_length(v_candidatos) = 0 then
    return null;
  end if;
  -- 3. Los demás (retirados, o activos del MISMO asesor) se absorben, bajo la válvula privilegiada y como hace la puerta de enlace
  --    de Gerencia (crm.enlazar_lead_inversionista_fn), en su orden —primero el perfil, después el cierre—: por cada uno, (a0) su
  --    PERFIL DEL PORTAL, si tiene (D-86): de OTRA persona no fusionada, o la ficha ya tiene OTRO perfil, o su documento no es de esta
  --    persona ⇒ P0409 «… requiere conciliación de Gerencia» y nada se escribe; de nadie, la ficha sin otro y su documento de esta
  --    persona ⇒ se enlazará a la ficha (D-87), pero DESPUÉS del UPDATE del lead que se convierte (private.conversion_enlazar_cliente_antiguo:
  --    el verificador trata como «ya es cliente» a una persona con perfil enlazado), salvo si la cuenta está DESACTIVADA (D-89: el mismo
  --    predicado del núcleo) ⇒ no se enlaza, la conversión sigue y el detalle lo dice; ya de esta persona ⇒ no se toca. public.perfiles
  --    se lee con un SELECT simple, SIN candado (regla de public; un cambio simultáneo del perfil es la carrera de F4.6); (a) su CIERRE
  --    EXTERNO INICIAL se completa con la persona (D-83)
  --    si sigue sin persona y su documento es de esta persona (private.documento_es_de_identidad); el asesor de origen del cierre
  --    (vendedor_id) no cambia —no se mueven cifras entre asesores—; si el cierre ya es de OTRA persona (D-84) o su documento no es de
  --    esta persona (D-85), P0409 (como esa puerta) y nada se escribe; si ya es de esta persona, no se toca y el detalle lo dice;
  --    (b) su rastro en el libro append-only de operaciones de
  --    identidad (tipo enlace, sin el documento en claro); (c) si sigue activo, una nota en el lead y su RETIRO (activo = false; D-81):
  --    la casa no admite dos leads vivos de una persona —el verificador que corre al escribir el DNI en el lead que se convierte lo
  --    rechazaría— y el que sigue vivo es el que se convierte; si la casa no deja retirarlo (private.leads_before_update: convertido
  --    sin perfil ni cierre; un episodio abierto anómalo), P0409 con mensaje propio y nada escrito. Ni el dueño ni la etapa del
  --    antiguo cambian. El puente HISTÓRICO lo pone private.conversion_enlazar_cliente_antiguo DESPUÉS del UPDATE del lead que se
  --    convierte (antes, el verificador lo contaría como otro lead de la persona).
  v_perfil_ficha := (select i.perfil_id from crm.inversionistas i where i.id = p_persona);
  v_previo := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off');
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  for v_c in select (c ->> 'id')::uuid as id, (c ->> 'activo')::boolean as activo, (c ->> 'vendedor_id')::uuid as vendedor_id,
                    (c ->> 'perfil_id')::uuid as perfil_id
             from pg_catalog.jsonb_array_elements(v_candidatos) c order by 1 loop
    v_ce := null; v_cierre := null; v_cierre_motivo := null; v_perfil_enlazar := null; v_perfil_no_enlazado := null; v_perfil_motivo := null;
    if v_c.perfil_id is not null then
      select p.dni, p.tipo_documento, p.activo, p.rol into v_pdni, v_ptipo, v_pactivo, v_prol from public.perfiles p where p.id = v_c.perfil_id;
      -- D-89: «desactivada» es EXACTAMENTE el predicado con el que el núcleo del contexto de la persona responde «El perfil Avance requiere
      -- revisión antes de operar» (los dos núcleos, el de escritura y el de lectura; cuerpos fijados por el preflight): así un perfil
      -- enlazado aquí pasa el núcleo con lo leído (el núcleo lo vuelve a leer; un cambio simultáneo del perfil puede detener la preparación).
      v_pdesactivada := not found or v_pactivo is not true or v_prol <> 'cliente';
      v_perfil_de := (select i.id from crm.inversionistas i where i.perfil_id = v_c.perfil_id and i.estado <> 'fusionado' limit 1);
      if v_perfil_de is not null and v_perfil_de <> p_persona then
        -- D-86: el perfil ya es de OTRA persona ⇒ la conversión se detiene (como la puerta de enlace de Gerencia).
        raise exception 'El perfil del Portal del cliente antiguo pertenece a otra persona; requiere conciliación de Gerencia' using errcode = 'P0409';
      elsif v_perfil_de is null then
        if v_perfil_ficha is not null and v_perfil_ficha <> v_c.perfil_id then
          -- D-86: la ficha ya tiene OTRA cuenta del Portal ⇒ se detiene.
          raise exception 'La ficha ya tiene otra cuenta del Portal; requiere conciliación de Gerencia' using errcode = 'P0409';
        end if;
        if not private.documento_es_de_identidad(p_persona, v_ptipo, v_pdni) then
          -- D-86: el documento del perfil no es de esta persona (otro DNI, otro tipo, o sin documento) ⇒ se detiene.
          raise exception 'El perfil del Portal del cliente antiguo lleva otro documento; requiere conciliación de Gerencia' using errcode = 'P0409';
        end if;
        if v_perfil_ficha is null then
          if v_pdesactivada then
            -- D-89: la cuenta es de la persona pero está desactivada ⇒ NO se enlaza (Gerencia puede hacerlo después); la absorción y la
            -- conversión siguen y el detalle lo dice. Los conflictos de D-86, arriba, detienen aunque esté desactivada.
            v_perfil_no_enlazado := v_c.perfil_id;
            v_perfil_motivo := 'cuenta del Portal desactivada';
          else
            -- D-87: se enlazará a la ficha después del UPDATE (la pieza de enlace); el detalle lo dice.
            v_perfil_ficha := v_c.perfil_id;
            v_perfil_enlazar := v_c.perfil_id;
          end if;
        end if;
      end if;
    end if;
    begin
      select ce.* into v_ce from crm.cierres_externos ce where ce.lead_id = v_c.id and ce.es_cierre_inicial for update nowait;
    exception when lock_not_available then
      raise exception 'El lead está en uso por otra operación; vuelve a intentarlo' using errcode = '40001';
    end;
    if v_ce.id is not null then
      if v_ce.inversionista_id is not null and v_ce.inversionista_id <> p_persona then
        -- D-84: el cierre ya es de OTRA persona ⇒ la conversión se detiene (como la puerta de enlace de Gerencia).
        raise exception 'El cierre del cliente antiguo pertenece a otra persona; requiere conciliación de Gerencia' using errcode = 'P0409';
      elsif v_ce.inversionista_id is null and not private.documento_es_de_identidad(p_persona, v_ce.documento_tipo, v_ce.documento) then
        -- D-85: el documento del cierre no es de esta persona (otro DNI, un CE, un pasaporte) ⇒ la conversión se detiene (como esa
        -- puerta). Un cierre sin documento no existe: documento y tipo son NOT NULL con formato (medido en la ronda 3).
        raise exception 'El cierre del cliente antiguo lleva otro documento; requiere conciliación de Gerencia' using errcode = 'P0409';
      elsif v_ce.inversionista_id is null then
        -- D-83: se completa con la persona; el asesor de origen (vendedor_id) no cambia.
        update crm.cierres_externos set inversionista_id = p_persona where id = v_ce.id;
        v_cierre := v_ce.id;
      else
        -- El cierre YA es de esta persona: no se toca (como esa puerta); el detalle lo dice.
        v_cierre_motivo := 'el cierre ya es de esta persona';
      end if;
    end if;
    insert into crm.inversionista_operaciones (tipo, inversionista_id, lead_id, motivo, detalle, por)
    values ('enlace', p_persona, v_c.id, 'Conversión: cliente antiguo sin ficha de persona, enlazado a la misma ficha (D-38)',
            pg_catalog.jsonb_build_object('via', 'preparar_conversion_inversion', 'rol', 'historico', 'lead_conversion', p_lead,
                                          'lead_antiguo_activo', v_c.activo, 'retirado_al_absorber', v_c.activo,
                                          'vendedor_antiguo', v_c.vendedor_id, 'vendedor_conversion', p_vendedor,
                                          'cierre_completado', v_cierre,
                                          'cierre_no_completado', case when v_ce.id is not null and v_cierre is null then v_ce.id end,
                                          'cierre_motivo', v_cierre_motivo,
                                          'perfil_completado', v_perfil_enlazar,
                                          'perfil_no_enlazado', v_perfil_no_enlazado,
                                          'perfil_motivo', v_perfil_motivo),
            p_uid)
    returning id into v_op;
    if v_c.activo then
      insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
      values (v_c.id, 'nota', 'Lead enlazado a la ficha del cliente al convertir otro lead suyo; queda retirado (D-38)',
              pg_catalog.jsonb_build_object('evento', 'enlace_identidad', 'operacion_id', v_op, 'inversionista_id', p_persona, 'lead_conversion', p_lead),
              p_uid);
      begin
        update crm.leads set activo = false where id = v_c.id and activo;
        get diagnostics v_n = row_count;
      exception
        when lock_not_available then
          raise exception 'El lead está en uso por otra operación; vuelve a intentarlo' using errcode = '40001';
        when serialization_failure or deadlock_detected then
          raise;
        when others then
          -- Al cliente solo el código (capa 3: sin detalles internos); el texto original queda en el registro del servidor.
          raise log 'conversion_absorber_cliente_antiguo: no se pudo retirar el cliente antiguo %: % %', v_c.id, sqlstate, sqlerrm;
          raise exception 'El cliente antiguo no se puede retirar; requiere conciliación de Gerencia'
            using errcode = 'P0409', detail = sqlstate;
      end;
      if v_n <> 1 then
        raise exception 'El cliente antiguo no se puede retirar; requiere conciliación de Gerencia' using errcode = 'P0409';
      end if;
    end if;
    v_salida := v_salida || pg_catalog.jsonb_build_object('id', v_c.id, 'activo', v_c.activo, 'vendedor_id', v_c.vendedor_id,
                                                          'perfil_a_enlazar', v_perfil_enlazar);
  end loop;
  perform pg_catalog.set_config('crm.op_privilegiada', v_previo, true);
  return pg_catalog.jsonb_build_object('candidatos', v_salida);
end;
$function$;

-- Dueño postgres SIEMPRE (como la puerta que la llama), corra quien corra la migración; EXECUTE solo para él.
alter function private.conversion_absorber_cliente_antiguo(uuid, uuid, text, uuid, uuid) owner to postgres;
revoke all on function private.conversion_absorber_cliente_antiguo(uuid, uuid, text, uuid, uuid) from public, anon, authenticated, service_role;

comment on function private.conversion_absorber_cliente_antiguo(uuid, uuid, text, uuid, uuid) is
  'Bloque 2.10 (D-38, D-81, D-83, D-84, D-85, D-86, D-87, D-88 y D-89 de Miguel, 09 y 10/10/2026; regla del cliente del 2.7/2.8: D-22, D-25, D-27, D-29). Pieza de la preparacion de la conversion (crm.preparar_persona_lead_inversion_fn): los CLIENTES ANTIGUOS SIN FICHA DE PERSONA con el DNI de la conversion (leads en etapa convertido sin puntero ni puente, distintos del lead que se convierte), con sus filas tomadas FOR UPDATE NOWAIT (40001 si otra operacion las tiene). Si alguno sigue ACTIVO a nombre de OTRO asesor, devuelve {veredicto: {estado: ya_es_cliente, asesor: <dueno de esa ficha>}} (el formato y los datos del alta) y no escribe nada; si no (retirados, o activos del mismo asesor), mira primero su PERFIL DEL PORTAL, como esa puerta (D-86: de otra persona, ficha con otro perfil o documento ajeno ⇒ P0409 requiere conciliacion de Gerencia y nada se escribe; D-87: de nadie y con documento de la persona ⇒ lo devuelve como perfil_a_enlazar para que la pieza de enlace lo complete DESPUES del UPDATE; D-89: si esa cuenta esta desactivada —el predicado del nucleo que responde El perfil Avance requiere revision antes de operar— no se enlaza, la conversion sigue y el detalle dice perfil_no_enlazado y perfil_motivo; public.perfiles se lee sin candado), completa su CIERRE EXTERNO INICIAL con la persona (D-83: si sigue sin persona y su documento es de esta persona, como la puerta de enlace de Gerencia; el asesor de origen del cierre no cambia; si el cierre ya es de otra persona -D-84- o su documento no es de esta persona -D-85-, P0409 requiere conciliacion de Gerencia y nada se escribe; si ya es de esta persona, no se toca), deja su rastro (crm.inversionista_operaciones tipo enlace, por = quien convierte, con cierre_completado, o cierre_no_completado y cierre_motivo cuando el cierre ya era de esta persona, en el detalle, y perfil_completado) y, si el antiguo sigue activo, una nota en crm.actividades y su RETIRO (activo = false: la casa no admite dos leads vivos de una persona; si la casa no deja retirarlo, P0409 El cliente antiguo no se puede retirar; requiere conciliacion de Gerencia, con solo el codigo del error original en el detalle —el texto va al registro del servidor—; si otra operacion tiene la fila, 40001), bajo la valvula privilegiada, y devuelve {candidatos: [{id, activo, vendedor_id, perfil_a_enlazar}]} para que private.conversion_enlazar_cliente_antiguo ponga los puentes historicos DESPUES del UPDATE del lead que se convierte. NULL si no hay candidatos. Contrato: quien la llama ya tiene el candado del documento, la persona FOR UPDATE y la fila del lead que se convierte FOR UPDATE; decide como responder (la puerta: P0481 Contacto no disponible con el veredicto en el detalle, o sigue). INVOKER y volatil; solo la ejecuta postgres.';

-- ── 1b. La pieza de enlace: los puentes históricos, DESPUÉS del UPDATE del lead que se convierte ───────────────────────────────
create function private.conversion_enlazar_cliente_antiguo(p_persona uuid, p_candidatos jsonb, p_uid uuid)
returns integer
language plpgsql
set search_path = ''
as $function$
declare
  v_c record;
  v_p record;
  v_n integer := 0;
  v_m integer;
begin
  -- Bloque 2.10 (D-38, D-87). Los candidatos que dejó private.conversion_absorber_cliente_antiguo (convertidos, sin puntero, ya retirados y
  -- sin puente): el puente HISTÓRICO a la persona de la conversión, sin tomar el puntero (el que se convierte es el canónico), con
  -- creado_por = quien convierte. Si alguno cambió entre medias, 40001 y nada se escribe.
  if p_persona is null or p_uid is null or p_candidatos is null or pg_catalog.jsonb_typeof(p_candidatos) <> 'array' then
    return 0;
  end if;
  for v_c in select (c ->> 'id')::uuid as id from pg_catalog.jsonb_array_elements(p_candidatos) c order by 1 loop
    if not exists (select 1 from crm.leads l where l.id = v_c.id and l.etapa = 'convertido' and l.inversionista_id is null and not l.activo)
       or exists (select 1 from crm.inversionista_leads il where il.lead_id = v_c.id) then
      raise exception 'El cliente antiguo % cambió mientras se enlazaba; vuelve a intentarlo', v_c.id using errcode = '40001';
    end if;
    insert into crm.inversionista_leads (inversionista_id, lead_id, rol, creado_por)
    values (p_persona, v_c.id, 'historico', p_uid);
    v_n := v_n + 1;
  end loop;
  -- D-87: la cuenta del Portal del antiguo que la pieza de absorción dio por buena (de nadie, su documento es de la persona y la ficha
  -- no tiene otra) se enlaza a la ficha AHORA, después del UPDATE del lead que se convierte: el verificador que corre al escribir el DNI
  -- trata como «ya es cliente» (vía identidad) a una persona con perfil enlazado y antes rechazaría la conversión. Como la puerta de
  -- enlace de Gerencia y sin la válvula (crm.inversionistas no la pide). El índice único del perfil frena una carrera con otra persona:
  -- 23505 ⇒ el 40001 de la casa.
  for v_p in select distinct (c ->> 'perfil_a_enlazar')::uuid as perfil_id from pg_catalog.jsonb_array_elements(p_candidatos) c
             where c ->> 'perfil_a_enlazar' is not null loop
    begin
      update crm.inversionistas set perfil_id = v_p.perfil_id where id = p_persona and perfil_id is null;
      get diagnostics v_m = row_count;
    exception when unique_violation then
      raise exception 'La cuenta del Portal del cliente antiguo cambió mientras se enlazaba; vuelve a intentarlo' using errcode = '40001';
    end;
    if v_m <> 1 then
      raise exception 'La cuenta del Portal del cliente antiguo cambió mientras se enlazaba; vuelve a intentarlo' using errcode = '40001';
    end if;
  end loop;
  return v_n;
end;
$function$;

alter function private.conversion_enlazar_cliente_antiguo(uuid, jsonb, uuid) owner to postgres;
revoke all on function private.conversion_enlazar_cliente_antiguo(uuid, jsonb, uuid) from public, anon, authenticated, service_role;

comment on function private.conversion_enlazar_cliente_antiguo(uuid, jsonb, uuid) is
  'Bloque 2.10 (D-38, D-87). Segunda mitad de la absorcion de un cliente antiguo sin ficha: pone el puente HISTORICO (crm.inversionista_leads rol historico, sin tomar el puntero, creado_por = quien convierte) a cada candidato que dejo private.conversion_absorber_cliente_antiguo (convertido, sin puntero, retirado y sin puente; si alguno cambio entre medias, 40001 y nada se escribe). La llama crm.preparar_persona_lead_inversion_fn DESPUES del UPDATE que escribe la persona y el DNI en el lead que se convierte: antes, el verificador de disponibilidad (un solo lead por persona) contaria el puente como otro lead. D-87: si la pieza de absorcion devolvio un perfil_a_enlazar, completa crm.inversionistas.perfil_id de la persona (solo si sigue sin perfil; sin la valvula; 23505 o ninguna fila ⇒ 40001 La cuenta del Portal del cliente antiguo cambio mientras se enlazaba; vuelve a intentarlo): tambien despues del UPDATE, porque el verificador trata como ya es cliente a una persona con perfil enlazado. Devuelve cuantos enlazo. INVOKER y volatil; solo la ejecuta postgres.';

-- ── 2. La pieza de historia: «este lead es historia absorbida de esta persona» ────────────────────────────────────────────────────
create function private.lead_historia_de_persona(p_lead uuid, p_persona uuid)
returns boolean
language sql
stable
set search_path = ''
as $function$
  select exists (
    select 1
    from crm.inversionista_leads il
    join crm.leads l on l.id = il.lead_id
    where il.lead_id = p_lead
      and il.inversionista_id = p_persona
      and il.rol = 'historico'
      and l.etapa = 'convertido'
      and l.inversionista_id is null
      and l.activo = false)
$function$;

alter function private.lead_historia_de_persona(uuid, uuid) owner to postgres;
revoke all on function private.lead_historia_de_persona(uuid, uuid) from public, anon, authenticated, service_role;

comment on function private.lead_historia_de_persona(uuid, uuid) is
  'Bloque 2.10 (D-38, D-90). Verdadero si el lead p_lead es HISTORIA absorbida de la persona p_persona: puente crm.inversionista_leads con rol historico a esa persona, lead en etapa convertido, sin puntero y RETIRADO (activo = false; D-90: un antiguo ya unido por puente y ACTIVO sigue siendo otro lead, como hoy) (el estado que deja private.conversion_absorber_cliente_antiguo, el mismo que el backfill de identidad da a un convertido de una persona que ya tiene su lead vivo). Lo usan la comprobacion de conciliacion de la preparacion de la conversion y los dos nucleos del contexto de la persona (inversion_persona_contexto_para, inversion_contexto_lectura_para) para no contar esa historia como otro lead; un lead canonico, un puntero o un suelto vivo siguen siendo otro lead. INVOKER y estable; solo la ejecuta postgres.';

-- ── 3. La puerta de conversión, por ancla única: su variable, la absorción antes de la conciliación (sin contar la historia) y el enlace tras el UPDATE ──
do $g1$
declare
  v_firma regprocedure := 'crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)'::regprocedure;
  v_def text;
  v_acl aclitem[];
  v_ancla text;
  v_nuevo text;
  v_veces integer;
begin
  select pg_get_functiondef(p.oid), p.proacl into v_def, v_acl from pg_proc p where p.oid = v_firma;

  -- la variable del resultado de la absorción
  v_ancla := $a1$  v_config text:=coalesce(current_setting('crm.op_privilegiada',true),'off');
begin
$a1$;
  v_nuevo := $n1$  v_config text:=coalesce(current_setting('crm.op_privilegiada',true),'off');
  v_antiguo jsonb;
begin
$n1$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: el ancla «la variable» de crm.preparar_persona_lead_inversion_fn aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  -- la absorción antes de la conciliación, y la conciliación sin contar la historia
  v_ancla := $a2$  if (v_l.inversionista_id is not null and v_l.inversionista_id is distinct from v_persona)
    or exists(select 1 from crm.inversionista_leads il where il.lead_id=p_lead
      and private.inversionista_canonica(il.inversionista_id) is distinct from v_persona)
    or exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead)
    or exists(select 1 from private.leads_de_identidades(array[v_persona]) x where x<>p_lead) then
    raise exception 'Esta persona ya tiene otra identidad o lead; requiere conciliación' using errcode='P0409';
  end if;
$a2$;
  v_nuevo := $n2$  -- Bloque 2.10 (D-38 de Miguel, 09/10/2026; caso P2 del 2.8): el DNI de un CLIENTE ANTIGUO SIN FICHA DE PERSONA (lead
  -- convertido sin persona ni puente). Con la fila del lead que se convierte ya tomada FOR UPDATE, la pieza toma las de esos
  -- convertidos (FOR UPDATE NOWAIT) y decide: si alguno sigue ACTIVO a nombre de OTRO asesor ⇒ «ya es cliente de X» (el veredicto
  -- del alta, D-29) con el P0481 de la regla del cliente y nada se escribe; si no (retirados, o activos del mismo asesor) ⇒ los
  -- absorbe en la ficha de esta conversión: su rastro (libro de operaciones; nota en el lead si está activo) y, si está activo, su
  -- RETIRO (la casa no admite dos leads vivos de una persona), y la conversión sigue: el cliente pasa al asesor que convierte (el
  -- responsable de la persona, abajo). El puente HISTÓRICO se pone después del UPDATE de este lead (más abajo). Solo con DNI
  -- (crm.leads.dni solo guarda DNI). Va después de todo lo que hoy decide y antes de la conciliación, que no cuenta esa historia como
  -- «otro lead» (private.lead_historia_de_persona) si la puso ESTA conversión (D-91, abajo). Nada cambia para leads sin coincidencia
  -- ni para clientes con ficha.
  if p_tipo_documento='DNI' then
    v_antiguo:=private.conversion_absorber_cliente_antiguo(p_lead,v_persona,v_doc,v_l.vendedor_id,v_uid);
    if v_antiguo ? 'veredicto' then
      raise exception 'Contacto no disponible' using errcode='P0481', detail=(v_antiguo->'veredicto')::text;
    end if;
  end if;
  if (v_l.inversionista_id is not null and v_l.inversionista_id is distinct from v_persona)
    or exists(select 1 from crm.inversionista_leads il where il.lead_id=p_lead
      and private.inversionista_canonica(il.inversionista_id) is distinct from v_persona)
    or exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead and not private.lead_historia_de_persona(x,v_persona))
    or exists(select 1 from private.leads_de_identidades(array[v_persona]) x where x<>p_lead and not private.lead_historia_de_persona(x,v_persona))
    -- D-91 (Miguel, 10/10/2026), SOLO cuando esta preparación ESCRIBE el DNI del lead (ronda 8): aquí, en la puerta, esa historia solo
    -- exime si la puso ESTA conversión (su operación de enlace lleva lead_conversion = este lead); un puente HISTÓRICO a la persona que
    -- ya existía antes (de Gerencia, de la carga o de la conversión de OTRO lead) ⇒ la conciliación de hoy y nada escrito, porque el
    -- verificador sellado lo contaría como lead de la persona al escribir el DNI y pararía con P0481 «ya es cliente» (D-92 lo ajustará).
    -- Ese verificador solo corre si el UPDATE de abajo SOLICITA cambiar el DNI (l. 93-94 de la definición auditada b40dded8…: dni=case when
    -- p_tipo_documento='DNI' then v_doc else dni end; el teléfono no se toca): el disparador de disponibilidad lo llama solo si cambia
    -- el teléfono o el DNI (l. 42-43 y 70 de la función de ese disparador, 418b0976…, que esta migración no fija), es decir
    -- si p_tipo_documento='DNI' y el lead aún no lleva ese documento (antes del UPDATE, l. 34 y 47, su DNI está vacío o es v_doc); en el flujo
    -- ordinario auditado eso alcanza el verificador (el disparador tiene una salida anticipada para la corrección de documento de Gerencia, l. 58-69, con
    -- la GUC crm.correccion_documento bajo la válvula: que ninguna sesión la conserve al llamar a esta puerta es una premisa que se verifica al integrar). Si el
    -- lead YA lleva ese DNI —el estado del backfill de identidad y de la carga: el lead vivo canónico y un convertido retirado con
    -- puente histórico— o el documento es un CE o un pasaporte, el verificador NO corre y manda D-90: la historia cuenta y la
    -- conversión sigue. Si ese lead no es historia, las dos comprobaciones de arriba ya lo detienen igual. Los núcleos siguen contando
    -- la historia como tal (D-90). El reintento de la misma preparación ya lleva el DNI: esta condición no lo evalúa (la exención por
    -- lead_conversion se conserva).
    or (p_tipo_documento='DNI' and v_l.dni is distinct from v_doc
      and exists(select 1 from crm.inversionista_leads il where il.inversionista_id=v_persona and il.rol='historico' and il.lead_id<>p_lead
        and not exists(select 1 from crm.inversionista_operaciones o where o.tipo='enlace' and o.lead_id=il.lead_id
          and o.detalle->>'lead_conversion'=p_lead::text))) then
    raise exception 'Esta persona ya tiene otra identidad o lead; requiere conciliación' using errcode='P0409';
  end if;
  -- D-94 (Miguel, 12/10/2026; P2-1 de Codex r2, medido en rollback): el «No insistir» de un antiguo de la persona detiene SIEMPRE la conversión con la
  -- respuesta que el alta y el verificador sellado dan a ese veto (P0481 «Contacto no disponible», detalle {"estado": "no_contactar"}) y no deja
  -- nada escrito (el rechazo deshace la absorción de arriba, como el del verificador en A15/A20). Cubre (a) los leads de la persona que la conversión
  -- cuenta como HISTORIA (D-90: la pieza de historia, que aquí es el retirado ya unido por puente histórico) y (b) los candidatos que la pieza de
  -- absorción acaba de tomar (D-38: v_antiguo, ya bloqueados FOR UPDATE NOWAIT por ella). Sitio: DESPUÉS de la conciliación —el antiguo que no es
  -- historia sigue yendo al P0409 de hoy y, con el lead SIN DNI, manda el P0409 de D-91— y ANTES del UPDATE de abajo (l. 93-94 de la definición
  -- auditada b40dded8…), que es donde hoy el verificador pararía este veto; pero el verificador solo corre si ese UPDATE solicita cambiar el DNI, y con
  -- el DNI ya escrito o con un CE o un pasaporte no corre y el veto se saltaba (M1, M2 y M4 de la medida del Director: hoy P0409 o convierte sin
  -- absorber; la ronda 8 convertía y absorbía). Lee `no_contactar` de los antiguos con un SELECT simple, sin candados nuevos (como el verificador:
  -- una marca levantada a la vez es la carrera de siempre del veto). Con CE o pasaporte no hay candidatos (la absorción solo corre con un DNI).
  if exists(select 1 from private.leads_de_personas(array[v_persona]) x join crm.leads lx on lx.id=x
        where x<>p_lead and lx.no_contactar and private.lead_historia_de_persona(x,v_persona))
    or exists(select 1 from jsonb_array_elements(coalesce(v_antiguo->'candidatos','[]'::jsonb)) c join crm.leads lc on lc.id=(c->>'id')::uuid
        where lc.no_contactar) then
    raise exception 'Contacto no disponible' using errcode='P0481', detail=jsonb_build_object('estado','no_contactar')::text;
  end if;
$n2$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: el ancla «la conciliación» de crm.preparar_persona_lead_inversion_fn aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  -- después del UPDATE que escribe la persona y el DNI, los puentes históricos
  v_ancla := $a4$  perform set_config('crm.op_privilegiada',v_config,true);
  -- Además aplica las banderas/membresía de F4 y el ámbito canónico de Cartera.
$a4$;
  v_nuevo := $n4$  perform set_config('crm.op_privilegiada',v_config,true);
  -- Bloque 2.10 (D-38): los clientes antiguos absorbidos (ya retirados, con su rastro) se enlazan AHORA, después del UPDATE —el
  -- verificador que corre al escribir el DNI aplica «un solo lead por persona» y contaría el puente—, como HISTÓRICO de la persona
  -- (puente sin puntero; el canónico es este lead).
  if v_antiguo ? 'candidatos' then
    perform private.conversion_enlazar_cliente_antiguo(v_persona,v_antiguo->'candidatos',v_uid);
  end if;
  -- Además aplica las banderas/membresía de F4 y el ámbito canónico de Cartera.
$n4$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then
    raise exception 'PREFLIGHT conversion_cliente_antiguo: el ancla «tras el UPDATE» de crm.preparar_persona_lead_inversion_fn aparece % veces (debe ser 1)', v_veces;
  end if;
  v_def := replace(v_def, v_ancla, v_nuevo);

  execute v_def;

  if (select p.proacl from pg_proc p where p.oid = v_firma) is distinct from v_acl then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: los permisos de crm.preparar_persona_lead_inversion_fn cambiaron al parchear';
  end if;
end
$g1$;

-- ── 4. Los dos núcleos del contexto de la persona, por ancla única: la conciliación sin contar la historia ─────────────────────────
do $g2$
declare
  v_firma regprocedure;
  v_def text;
  v_acl aclitem[];
  v_ancla text;
  v_nuevo text;
  v_veces integer;
begin
  v_ancla := $a3$    if exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead)
      or exists(select 1 from crm.inversiones where inversionista_id=v_persona and es_primera_conversion) then
      raise exception 'La persona ya tiene una conversión inicial; requiere conciliación' using errcode='P0409';
    end if;
$a3$;
  v_nuevo := $n3$    -- Bloque 2.10 (D-38): la historia absorbida de un cliente antiguo sin ficha (private.lead_historia_de_persona) no es «otro lead».
    if exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead and not private.lead_historia_de_persona(x,v_persona))
      or exists(select 1 from crm.inversiones where inversionista_id=v_persona and es_primera_conversion) then
      raise exception 'La persona ya tiene una conversión inicial; requiere conciliación' using errcode='P0409';
    end if;
$n3$;
  foreach v_firma in array array['private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid)'::regprocedure,
                                 'private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid)'::regprocedure] loop
    select pg_get_functiondef(p.oid), p.proacl into v_def, v_acl from pg_proc p where p.oid = v_firma;
    v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
    if v_veces <> 1 then
      raise exception 'PREFLIGHT conversion_cliente_antiguo: el ancla «la conciliación» de % aparece % veces (debe ser 1)', v_firma, v_veces;
    end if;
    v_def := replace(v_def, v_ancla, v_nuevo);
    execute v_def;
    if (select p.proacl from pg_proc p where p.oid = v_firma) is distinct from v_acl then
      raise exception 'POSTFLIGHT conversion_cliente_antiguo: los permisos de % cambiaron al parchear', v_firma;
    end if;
  end loop;
end
$g2$;

-- ── 5. Los comentarios: a la puerta (sin comentario hoy) se le PONE uno; a los dos núcleos se les AÑADE la frase del 2.10 ─────────
comment on function crm.preparar_persona_lead_inversion_fn(uuid, text, text, text) is
  'Bloque 2.10 (D-38 de Miguel, 09/10/2026): el DNI de un cliente antiguo SIN ficha de persona (lead convertido sin puntero ni puente) usa la MISMA ficha: si ese cliente sigue activo a nombre de otro asesor, P0481 Contacto no disponible con el veredicto del alta (ya es cliente de X; D-29) en el detalle y nada se escribe; si esta retirado o es del mismo asesor, se absorbe en la persona de la conversion (private.conversion_absorber_cliente_antiguo: rastro, nota y retiro si estaba activo; private.conversion_enlazar_cliente_antiguo: puente historico tras el UPDATE) y la conversion sigue; la conciliacion no cuenta esa historia como otro lead (private.lead_historia_de_persona: solo antiguos RETIRADOS, D-90) si la puso ESTA conversion (D-91: un puente historico a la persona que ya existia antes de esta preparacion —de Gerencia, de la carga o de la conversion de otro lead— ⇒ P0409 Esta persona ya tiene otra identidad o lead; requiere conciliacion, nada escrito, SOLO cuando esta preparacion SOLICITA escribir el DNI del lead —ronda 8—, que es cuando corre el verificador en el flujo ordinario auditado (el disparador de disponibilidad tiene una salida anticipada para la correccion de documento de Gerencia, la GUC crm.correccion_documento bajo la valvula: premisa a verificar al integrar): si el lead YA lleva ese DNI o el documento es un CE o un pasaporte, el verificador no corre, manda D-90 y la conversion sigue; el reintento de la misma preparacion ya lleva el DNI y la operacion de enlace de su absorcion lleva lead_conversion = este lead; D-92: un bloque posterior ajustara el verificador para que esos antiguos conviertan). D-94 (ronda 9): el No insistir de un antiguo de la persona que esta conversion cuenta como historia (la pieza de historia) o acaba de absorber (los candidatos de la pieza de absorcion) detiene SIEMPRE la conversion, tambien con el DNI ya escrito o con un CE o un pasaporte: P0481 Contacto no disponible con {estado: no_contactar} en el detalle (la respuesta del alta y del verificador) y nada escrito; va despues de la conciliacion (el antiguo que no es historia sigue yendo al P0409; con el lead sin DNI manda el P0409 de D-91) y antes del UPDATE del lead, sin candados nuevos. Los clientes con ficha siguen en conciliacion. Al juntar, como la puerta de enlace de Gerencia y en su orden: el perfil del Portal del antiguo (D-86: de otra persona, ficha con otro perfil o documento ajeno ⇒ P0409 requiere conciliacion de Gerencia y nada se escribe; D-87: de nadie y con documento de la persona ⇒ se enlaza a la ficha despues del UPDATE, salvo si la cuenta esta desactivada —D-89: no se enlaza y la conversion sigue—) y despues su cierre externo inicial (D-83: se completa con la persona, el asesor de origen no cambia; D-84: de otra persona ⇒ P0409; D-85: con otro documento ⇒ P0409). D-81: el antiguo activo del mismo asesor queda retirado. D-88: quien convierte ve la ficha del antiguo (dinero e historia) desde esta preparacion, aunque no confirme; queda el rastro (libro de operaciones con por, audit_log del cierre, lecturas de la ficha).';
do $c1$
begin
  execute pg_catalog.format('comment on function private.inversion_persona_contexto_para(uuid, uuid, uuid, uuid) is %L',
    obj_description('private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid)'::regprocedure, 'pg_proc') || $c2$ Bloque 2.10 (D-38): la historia absorbida de un cliente antiguo sin ficha (private.lead_historia_de_persona) no cuenta como otro lead en la conciliacion.$c2$);
  execute pg_catalog.format('comment on function private.inversion_contexto_lectura_para(uuid, uuid, uuid, uuid) is %L',
    obj_description('private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid)'::regprocedure, 'pg_proc') || $c3$ Bloque 2.10 (D-38): la historia absorbida de un cliente antiguo sin ficha (private.lead_historia_de_persona) no cuenta como otro lead en la conciliacion.$c3$);
end
$c1$;

-- ── Postflight ───────────────────────────────────────────────────────────────────────────────────────────────────────
do $post$
declare
  v_puerta regprocedure := 'crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)'::regprocedure;
  v_escritura regprocedure := 'private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid)'::regprocedure;
  v_lectura regprocedure := 'private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid)'::regprocedure;
  v_absorber regprocedure := to_regprocedure('private.conversion_absorber_cliente_antiguo(uuid,uuid,text,uuid,uuid)');
  v_enlazar regprocedure := to_regprocedure('private.conversion_enlazar_cliente_antiguo(uuid,jsonb,uuid)');
  v_historia regprocedure := to_regprocedure('private.lead_historia_de_persona(uuid,uuid)');
  v_src text;
  v_h text;
  v_mal text;
  r record;
  v text;
  v_foto text := '';
  v_gates integer := 0;
begin
  -- Las tres piezas: cuerpo y definición EXACTOS, INVOKER, dueño postgres, EXECUTE solo postgres, comentario EXACTO.
  if v_absorber is null
     or (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_absorber) is distinct from 'e42060a4052c903e899015e5e65b6820/c7c41e6a612dfbbc858e6c7035aa4731' then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: la pieza private.conversion_absorber_cliente_antiguo no quedó exactamente como se ensayó (md5 del cuerpo / de la definición %)',
      coalesce((select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_absorber), 'AUSENTE');
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_absorber and p.proowner = 'postgres'::regrole::oid and not p.prosecdef and p.provolatile = 'v'
                   and p.proconfig = array['search_path=""'])
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_absorber)
        is distinct from 'postgres:EXECUTE:false'
     or has_function_privilege('anon', v_absorber, 'EXECUTE') or has_function_privilege('authenticated', v_absorber, 'EXECUTE') or has_function_privilege('service_role', v_absorber, 'EXECUTE')
     or md5(coalesce(obj_description(v_absorber, 'pg_proc'), '')) is distinct from '0fe920d982d5e1cb8b78cdb52e6d4e95' then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: la ficha o el comentario de private.conversion_absorber_cliente_antiguo no son los esperados (INVOKER, volátil, search_path vacío, dueño postgres, EXECUTE solo postgres, comentario md5 %)', md5(coalesce(obj_description(v_absorber, 'pg_proc'), ''));
  end if;
  if v_enlazar is null
     or (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_enlazar) is distinct from '5f3ff24473ab6e09ea561a555e75913c/b950e46ffa971abe6c5fc758de4a40d0' then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: la pieza private.conversion_enlazar_cliente_antiguo no quedó exactamente como se ensayó (md5 del cuerpo / de la definición %)',
      coalesce((select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_enlazar), 'AUSENTE');
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_enlazar and p.proowner = 'postgres'::regrole::oid and not p.prosecdef and p.provolatile = 'v'
                   and p.proconfig = array['search_path=""'])
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_enlazar)
        is distinct from 'postgres:EXECUTE:false'
     or has_function_privilege('anon', v_enlazar, 'EXECUTE') or has_function_privilege('authenticated', v_enlazar, 'EXECUTE') or has_function_privilege('service_role', v_enlazar, 'EXECUTE')
     or md5(coalesce(obj_description(v_enlazar, 'pg_proc'), '')) is distinct from 'c3ce07337d5c62279d5b3dab4bcad2e6' then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: la ficha o el comentario de private.conversion_enlazar_cliente_antiguo no son los esperados (INVOKER, volátil, search_path vacío, dueño postgres, EXECUTE solo postgres, comentario md5 %)', md5(coalesce(obj_description(v_enlazar, 'pg_proc'), ''));
  end if;
  if v_historia is null
     or (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_historia) is distinct from '32c3b18303b0a32c1d92d1d73d73c28f/fbde8ab20dbf41604427a72a3c457328' then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: la pieza private.lead_historia_de_persona no quedó exactamente como se ensayó (md5 del cuerpo / de la definición %)',
      coalesce((select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_historia), 'AUSENTE');
  end if;
  if not exists (select 1 from pg_proc p where p.oid = v_historia and p.proowner = 'postgres'::regrole::oid and not p.prosecdef and p.provolatile = 's'
                   and p.proconfig = array['search_path=""'])
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_historia)
        is distinct from 'postgres:EXECUTE:false'
     or has_function_privilege('anon', v_historia, 'EXECUTE') or has_function_privilege('authenticated', v_historia, 'EXECUTE') or has_function_privilege('service_role', v_historia, 'EXECUTE')
     or md5(coalesce(obj_description(v_historia, 'pg_proc'), '')) is distinct from '80f36c9d023d2d804162bbb0068f4e29' then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: la ficha o el comentario de private.lead_historia_de_persona no son los esperados (INVOKER, estable, search_path vacío, dueño postgres, EXECUTE solo postgres, comentario md5 %)', md5(coalesce(obj_description(v_historia, 'pg_proc'), ''));
  end if;
  -- La puerta: la pieza de absorción una vez, la de enlace una vez (después del UPDATE) y la de historia tres veces, cuerpo exacto, la misma
  -- ficha que antes, comentario exacto.
  select p.prosrc, md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) into v_src, v_h from pg_proc p where p.oid = v_puerta;
  if (length(v_src) - length(replace(v_src, 'private.conversion_absorber_cliente_antiguo(', ''))) / length('private.conversion_absorber_cliente_antiguo(') <> 1
     or (length(v_src) - length(replace(v_src, 'private.conversion_enlazar_cliente_antiguo(', ''))) / length('private.conversion_enlazar_cliente_antiguo(') <> 1
     or (length(v_src) - length(replace(v_src, 'private.lead_historia_de_persona(', ''))) / length('private.lead_historia_de_persona(') <> 3
     or strpos(v_src, 'private.conversion_enlazar_cliente_antiguo(') < strpos(v_src, 'update crm.leads set inversionista_id=v_persona') then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: crm.preparar_persona_lead_inversion_fn no quedó con la pieza de absorción una vez, la de enlace una vez (después del UPDATE) y la de historia tres veces';
  end if;
  if v_h is distinct from 'da360b1929752a3e26371bf838813130/f921422dfc1567ffc82980222e299601' then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: crm.preparar_persona_lead_inversion_fn no quedó exactamente como se ensayó (md5 del cuerpo / de la definición %)', v_h;
  end if;
  if (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_puerta) is distinct from current_setting('conversion_cliente_antiguo.puerta_antes', true)
     or has_function_privilege('anon', v_puerta, 'EXECUTE') or has_function_privilege('service_role', v_puerta, 'EXECUTE')
     or md5(coalesce(obj_description(v_puerta, 'pg_proc'), '')) is distinct from '7b00e6ea92634d5e8ceb55687c588a38' then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: la ficha o el comentario de crm.preparar_persona_lead_inversion_fn no son los esperados (comentario md5 %)', md5(coalesce(obj_description(v_puerta, 'pg_proc'), ''));
  end if;
  -- Los dos núcleos: la pieza de historia una vez, cuerpo exacto, la misma ficha, comentario exacto.
  select p.prosrc, md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) into v_src, v_h from pg_proc p where p.oid = v_escritura;
  if (length(v_src) - length(replace(v_src, 'private.lead_historia_de_persona(', ''))) / length('private.lead_historia_de_persona(') <> 1 then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: private.inversion_persona_contexto_para no quedó con la pieza de historia exactamente una vez';
  end if;
  if v_h is distinct from '514fda0a0ca115c620637e6408bc346c/151b1ae1fa511bf728e3d5d8c11434f6' then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: private.inversion_persona_contexto_para no quedó exactamente como se ensayó (md5 del cuerpo / de la definición %)', v_h;
  end if;
  if (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_escritura) is distinct from current_setting('conversion_cliente_antiguo.escritura_antes', true)
     or has_function_privilege('anon', v_escritura, 'EXECUTE') or has_function_privilege('authenticated', v_escritura, 'EXECUTE') or has_function_privilege('service_role', v_escritura, 'EXECUTE')
     or md5(coalesce(obj_description(v_escritura, 'pg_proc'), '')) is distinct from 'ae77826890d3421cab96831002056dd4' then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: la ficha o el comentario de private.inversion_persona_contexto_para no son los esperados (comentario md5 %)', md5(coalesce(obj_description(v_escritura, 'pg_proc'), ''));
  end if;
  select p.prosrc, md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) into v_src, v_h from pg_proc p where p.oid = v_lectura;
  if (length(v_src) - length(replace(v_src, 'private.lead_historia_de_persona(', ''))) / length('private.lead_historia_de_persona(') <> 1 then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: private.inversion_contexto_lectura_para no quedó con la pieza de historia exactamente una vez';
  end if;
  if v_h is distinct from '8e96ddefae91ca9e1587cccb103129a7/c79c0a93ad9acd23e3ee152c32c32fb7' then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: private.inversion_contexto_lectura_para no quedó exactamente como se ensayó (md5 del cuerpo / de la definición %)', v_h;
  end if;
  if (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(p.proconfig::text, '-')
            || '|' || coalesce(p.proacl::text, '-') || '|' || pg_get_function_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
       from pg_proc p where p.oid = v_lectura) is distinct from current_setting('conversion_cliente_antiguo.lectura_antes', true)
     or has_function_privilege('anon', v_lectura, 'EXECUTE') or has_function_privilege('authenticated', v_lectura, 'EXECUTE') or has_function_privilege('service_role', v_lectura, 'EXECUTE')
     or md5(coalesce(obj_description(v_lectura, 'pg_proc'), '')) is distinct from '2f1723984e222937ef171266e51e9897' then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: la ficha o el comentario de private.inversion_contexto_lectura_para no son los esperados (comentario md5 %)', md5(coalesce(obj_description(v_lectura, 'pg_proc'), ''));
  end if;
  -- Lo que llama a las tres o decide su efecto, intacto.
  select string_agg(e.firma, ', ' order by e.firma) into v_mal
  from (values
    ('crm.acceso_inversion_fn(uuid,text,jsonb)', 'b45c309fce1003058ee42de5804d95a9', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.buscar_cliente_existente_fn(text,text,text,uuid)', '43b317c13c40471a3e3eec2fbbe0fb8a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.confirmar_inversion_fn(uuid)', 'e69358303d4b6220354460965179c28d', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.confirmar_inversion_revisada_fn(uuid,integer)', '33af606a814c74de5de8a080430bb299', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.contexto_cliente_existente_fn(uuid,uuid)', '8cd36f9311dd59327fa749f4568861cb', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.contexto_conversion_inversion_fn(uuid,uuid)', 'a616232e3ada628404fc6a1a8356eb13', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)', 'c41aa8ee34da4b3f828289058c41e4f4', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.enlazar_lead_inversionista_fn(uuid,uuid,text)', '1159aa8443c117c8c9384a2bcf17ae2b', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.inversionista_ficha_fn(uuid,integer,integer)', 'be113f3c638e3fdf6e0ca9a45eb86a6d', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.preparar_inversion_fn(uuid,jsonb)', '5fefbc143578a735a8648f686f71bf9a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text)', 'dc622b938e8d8e9777a033cfa625b11a', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.documento_es_de_identidad(uuid,text,text)', '724c4c781b1ed289a5320ab6c9d2eea8', 'postgres:EXECUTE:false'),
    ('private.f4_comprobante_autorizado(text)', 'cdecad21e77c38d023ba156efd8faa74', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.f4_fuente_inmutable()', 'f4608368a957e5ce1fe191562d5b5bea', 'postgres:EXECUTE:false'),
    ('private.identidad_bloquear_documento(text,text)', '9c08b500af7bc11aeba5e0e7d3a63330', 'postgres:EXECUTE:false'),
    ('private.identidad_bloquear_documentos_de(uuid[])', '81dffba49b46f2defc723e53a9a96d67', 'postgres:EXECUTE:false'),
    ('private.inversion_contexto_lectura(uuid,uuid)', '7ae71408f49ecd1eb2a05ed746746dde', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_autorizada_para(uuid,uuid,uuid)', 'c91e82b30558d121782f94aefab39d6e', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_contexto(uuid)', '335fa43d5eed5d0d8010d9d0716483ce', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_contexto(uuid,uuid)', 'a7ce8164838edc6b64cdc3f933c5a276', 'postgres:EXECUTE:false'),
    ('private.inversion_persona_lectura_para(uuid,uuid,uuid)', '6539960f2d9b7896e2c4083f80361f57', 'postgres:EXECUTE:false'),
    ('private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text)', 'c34bc06eafdb62f128476a8bffbfa642', 'postgres:EXECUTE:false'),
    ('private.inversiones_escritura_bajo_candado()', '2122bbf3b22996f2e8373081a259db9b', 'postgres:EXECUTE:false'),
    ('private.inversionista_canonica(uuid)', '34702897135078893b7d3a726b0c1816', 'postgres:EXECUTE:false'),
    ('private.inversionista_fusion_destino_activo()', '861f359c23ab031945f4bad75f8dc3a7', 'postgres:EXECUTE:false'),
    ('private.inversionista_operaciones_append_only()', '909d41d42674ccb6775597fd4235ebca', 'postgres:EXECUTE:false'),
    ('private.inversionista_resolver(text,text,boolean,text)', '95d502fcae257bf2a439ec3e4aa6a2dc', 'postgres:EXECUTE:false'),
    ('private.juicio_cliente_convertido(text,text,text,uuid)', 'a2b38faf42a875c7dffb7968b106e36f', 'postgres:EXECUTE:false'),
    ('private.juicio_persona(uuid,uuid)', '69794e137dd642e0b529612fb2a623eb', 'postgres:EXECUTE:false'),
    ('private.leads_before_update()', '4ae909f2d56ca650b5595b505e6aa51d', 'postgres:EXECUTE:false'),
    ('private.leads_de_identidades(uuid[])', '2421b2b78b02b8e93fd01598e2f54128', 'postgres:EXECUTE:false'),
    ('private.leads_de_personas(uuid[])', '6eded477639796c1053f0190f6decc18', 'postgres:EXECUTE:false'),
    ('private.leads_protege_inversionista_id()', '6151f6d4da6c80fc62ad7f131ea398a4', 'postgres:EXECUTE:false'),
    ('private.log_audit_crm()', 'c25c2af183b650f4d4c85abedd5bcc97', 'postgres:EXECUTE:false'),
    ('private.puede_gestionar_contratos_crm()', '94b5fb2af92bf4187802b1f3d26659c5', 'postgres:EXECUTE:false'),
    ('private.resolver_en_puertas_bajo_candado()', '5f74d26262fcc83e5975672da141be63', 'postgres:EXECUTE:false'),
    ('private.rol_crm(uuid)', '99827f3fe2fbc3cfae5668c30015c758', 'authenticated:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.trg_cierres_externos_inmutables()', 'c9f55c70e526975476b1f6aead562cd4', '-:EXECUTE:false,postgres:EXECUTE:false'),
    ('private.trg_gestion_lead_serializada()', '7af0e66b8a4849566e43b514245e1b86', 'postgres:EXECUTE:false'),
    ('private.trg_leads_tenencia_desde()', '900508fa3ccf3eec2e738ccdeebad7be', 'postgres:EXECUTE:false'),
    ('private.trg_leads_zz_enlaza_identidad()', '6ea5abfcc7bc7113f62f175df4e65879', 'postgres:EXECUTE:false'),
    ('private.trg_leads_zz_puente_identidad()', 'e96f21d1c58623f6c2a84e7c04683a5c', 'postgres:EXECUTE:false'),
    ('private.vendedor_ids_visibles(uuid)', '85544c70a0920f3a7a1b5da06935f236', 'authenticated:EXECUTE:false,postgres:EXECUTE:false')) e(firma, definicion, acl)
  left join pg_proc p on p.oid = to_regprocedure(e.firma)
  where p.oid is null
     or md5(pg_get_functiondef(p.oid)) is distinct from e.definicion
     or p.proowner is distinct from 'postgres'::regrole::oid
     or (select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text collate "C")
           from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) is distinct from e.acl;
  if v_mal is not null then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: cambió algo que esta migración no toca (%)', v_mal;
  end if;
  -- Nadie más que la puerta y los dos núcleos usa las piezas; los llamadores de las tres son los de antes.
  select string_agg(x.f, ', ' order by x.f) into v_mal
  from (select p.oid::regprocedure::text as f
          from pg_proc p
         where (strpos(lower(p.prosrc), 'conversion_absorber_cliente_antiguo') > 0 and p.oid not in (v_absorber, v_enlazar, v_puerta))
            or (strpos(lower(p.prosrc), 'conversion_enlazar_cliente_antiguo') > 0 and p.oid not in (v_enlazar, v_absorber, v_puerta))
            or (strpos(lower(p.prosrc), 'lead_historia_de_persona') > 0 and p.oid not in (v_historia, v_puerta, v_escritura, v_lectura))
        union all
        select pg_describe_object(d.classid, d.objid, d.objsubid)
          from pg_depend d
         where d.refclassid = 'pg_proc'::regclass and d.refobjid in (v_absorber, v_enlazar, v_historia)) x;
  if v_mal is null and to_regclass('cron.job') is not null then
    execute $q$select string_agg('cron.job ' || j.jobid::text, ', ') from cron.job j
                where strpos(lower(j.command), 'conversion_absorber_cliente_antiguo') > 0 or strpos(lower(j.command), 'conversion_enlazar_cliente_antiguo') > 0
                   or strpos(lower(j.command), 'lead_historia_de_persona') > 0$q$ into v_mal;
  end if;
  if v_mal is not null then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: otro objeto usa las piezas (%)', v_mal;
  end if;
  select string_agg(x.f, ', ' order by x.f) into v_mal
  from (select p.oid::regprocedure::text as f
          from pg_proc p
         where (strpos(lower(p.prosrc), 'preparar_persona_lead_inversion_fn') > 0 and p.oid <> v_puerta)
            or (strpos(lower(p.prosrc), 'inversion_persona_contexto_para') > 0
                and p.oid not in (v_escritura, v_lectura,
                                  coalesce(to_regprocedure('private.inversion_persona_contexto(uuid,uuid)'), 0),
                                  coalesce(to_regprocedure('private.inversion_preparar_nucleo(uuid,jsonb,text,uuid,text)'), 0),
                                  coalesce(to_regprocedure('crm.confirmar_inversion_revisada_fn(uuid,integer)'), 0),
                                  coalesce(to_regprocedure('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)'), 0),
                                  coalesce(to_regprocedure('crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text)'), 0),
                                  coalesce(to_regprocedure('crm.acceso_inversion_fn(uuid,text,jsonb)'), 0),
                                  coalesce(to_regprocedure('private.f4_comprobante_autorizado(text)'), 0)))
            or (strpos(lower(p.prosrc), 'inversion_contexto_lectura_para') > 0
                and p.oid not in (v_escritura, v_lectura,
                                  coalesce(to_regprocedure('private.inversion_contexto_lectura(uuid,uuid)'), 0),
                                  coalesce(to_regprocedure('crm.buscar_cliente_existente_fn(text,text,text,uuid)'), 0),
                                  coalesce(to_regprocedure('crm.contexto_cliente_existente_fn(uuid,uuid)'), 0)))
        union all
        select pg_describe_object(d.classid, d.objid, d.objsubid)
          from pg_depend d
         where d.refclassid = 'pg_proc'::regclass and d.refobjid in (v_puerta, v_escritura, v_lectura)) x;
  if v_mal is null and to_regclass('cron.job') is not null then
    execute $q$select string_agg('cron.job ' || j.jobid::text, ', ') from cron.job j
                where strpos(lower(j.command), 'preparar_persona_lead_inversion_fn') > 0 or strpos(lower(j.command), 'inversion_persona_contexto_para') > 0
                   or strpos(lower(j.command), 'inversion_contexto_lectura_para') > 0$q$ into v_mal;
  end if;
  if v_mal is not null then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: otro objeto nombra a la puerta o a los núcleos (%)', v_mal;
  end if;
  -- Las restricciones, los índices y la RLS de las que depende la regla, intactos.
  select string_agg(e.nombre, ', ' order by e.nombre) into v_mal
  from (values
    ('crm.leads', 'leads_dni_check', '6dcca3c962687ba896d101adf845d281'),
    ('crm.inversionista_leads', 'inversionista_leads_rol_check', 'f6a33854861793c8dc204e1b32c07716'),
    ('crm.inversionista_leads', 'inversionista_leads_lead_id_fkey', 'c6c7de31923066a9f3b843e9c875aec6'),
    ('crm.inversionista_leads', 'inversionista_leads_inversionista_id_fkey', '99bee63006ab85e4e5c1d5fdf071a137'),
    ('crm.inversionista_leads', 'inversionista_leads_creado_por_fkey', '8b21ba4ae6f1720bfba13340e69e1f2e'),
    ('crm.inversionista_operaciones', 'inversionista_operaciones_tipo_check', 'c3b74a13c0bd2414b83c800af4f02d4b'),
    ('crm.inversionista_operaciones', 'inversionista_operaciones_motivo_check', '6c884dea657b7a534f19f04abd86d684')) e(tabla, nombre, definicion)
  left join pg_constraint c on c.conrelid = e.tabla::regclass and c.conname = e.nombre
  where c.oid is null or not c.convalidated or md5(pg_get_constraintdef(c.oid)) is distinct from e.definicion;
  if v_mal is not null then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: cambió una restricción que esta migración no toca (%)', v_mal;
  end if;
  if not exists (select 1 from pg_indexes i where i.schemaname = 'crm' and i.indexname = 'leads_inversionista_uidx' and md5(i.indexdef) = 'a9f9b423261a56190a909eeea80a4a27')
     or not exists (select 1 from pg_indexes i where i.schemaname = 'crm' and i.indexname = 'inversionista_leads_lead_uidx')
     or not exists (select 1 from pg_indexes i where i.schemaname = 'crm' and i.indexname = 'inversionista_leads_canonico_uidx')
     or exists (select 1 from pg_class c where c.oid in ('crm.inversionista_leads'::regclass, 'crm.inversionista_operaciones'::regclass)
                  and (not c.relrowsecurity or c.relacl is not null or c.relowner <> 'postgres'::regrole::oid)) then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: cambió un índice único, la RLS o los grants de los que depende la regla';
  end if;
  -- Las premisas de D-83/D-85 y de D-86/D-87, intactas: a lo sumo un cierre inicial por lead; el
  -- documento del cierre y su tipo NOT NULL y con su formato (por eso no hay rama «sin documento»); crm.inversiones.inversionista_id NOT
  -- NULL (un cierre sin persona no tiene inversión); el disparador de inmutables del cierre, enlazado y activo; el perfil único por
  -- persona no fusionada (la carrera da 23505, que la pieza de enlace traduce al 40001) y su clave foránea; los disparadores de
  -- crm.inversionistas que reaccionan al completar el perfil (su conjunto exacto y activo).
  select string_agg(z.x, ', ' order by z.x) into v_mal
  from (
    select 'restricción ' || e.nombre as x
    from (values
      ('crm.cierres_externos', 'cierres_externos_documento_formato', 'e5f8b87595e008282602e238bf581984'),
      ('crm.cierres_externos', 'cierres_externos_documento_tipo_check', 'e2c34a1a34e26c147329f046c1e1da5b'),
      ('crm.inversionistas', 'inversionistas_perfil_id_fkey', '7f74ba99b1e24898320e925b0cd3563a')) e(tabla, nombre, definicion)
    left join pg_constraint c on c.conrelid = e.tabla::regclass and c.conname = e.nombre
    where c.oid is null or not c.convalidated or md5(pg_get_constraintdef(c.oid)) is distinct from e.definicion
    union all
    select 'índice ' || e.nombre
    from (values
      ('cierres_externos_inicial_por_lead_uidx', 'cf8c81018d22bd499463d6cd8f101f6b'),
      ('inversionistas_perfil_uidx', '9bda30dce00b9694bc5aab719b053305')) e(nombre, definicion)
    left join pg_indexes i on i.schemaname = 'crm' and i.indexname = e.nombre
    where i.indexname is null or md5(i.indexdef) is distinct from e.definicion
    union all
    select 'NOT NULL ' || e.tabla || '.' || e.columna
    from (values ('crm.cierres_externos', 'documento'), ('crm.cierres_externos', 'documento_tipo'), ('crm.inversiones', 'inversionista_id')) e(tabla, columna)
    left join pg_attribute a on a.attrelid = e.tabla::regclass and a.attname = e.columna and not a.attisdropped
    where a.attnum is null or not a.attnotnull
    union all
    select 'disparador trg_cierres_externos_00_inmutables'
    where not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_cierres_externos_00_inmutables'
                        and t.tgenabled = 'O' and md5(pg_get_triggerdef(t.oid)) = 'e6e9970fea6f192205d0000d5b5f3dc6')
    union all
    select 'disparador ' || e.nombre
    from (values
      ('trg_leads_before_update', '02b8824f01e2f5aa026f478241711c8a'),
      ('trg_leads_zzz_tenencia_desde', 'f5849e264eb05e8a253dbd78c2362fba')) e(nombre, definicion)
    where not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = e.nombre and t.tgenabled = 'O'
                        and md5(pg_get_triggerdef(t.oid)) = e.definicion)
    union all
    select 'disparadores de crm.inversionistas'
    where (select count(*) || '|' || md5(string_agg(t.tgname || ':' || t.tgenabled::text || ':' || pg_get_triggerdef(t.oid), '|' order by t.tgname))
             from pg_trigger t where t.tgrelid = 'crm.inversionistas'::regclass and not t.tgisinternal) is distinct from '5|104c0bb1234815233ef1bfe823936553'
  ) z;
  if v_mal is not null then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: cambió o falta una premisa del cierre o del perfil (%)', v_mal;
  end if;
  -- El inventario de los private.assert_*() (los 29 que no re-sella el 2.16): el de antes (esta migración no los toca) y la foto de los
  -- 30, EXACTAMENTE la de antes. No acredita PASS.
  if (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0 and p.proname <> 'assert_gestion_diaria_resultado')
     is distinct from '29|60a0851245859d8e1f0da6e2276a2594'
     or to_regprocedure('private.assert_gestion_diaria_resultado()') is null then
    raise exception 'POSTFLIGHT conversion_cliente_antiguo: el inventario de los private.assert_*() no es el de antes (los 29 que no re-sella el 2.16: %)',
      (select count(*) || '|' || md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text collate "C"))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0 and p.proname <> 'assert_gestion_diaria_resultado');
  end if;
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
  if v_foto is distinct from current_setting('conversion_cliente_antiguo.trinquetes_antes', true) then
    raise exception E'POSTFLIGHT conversion_cliente_antiguo: algún private.assert_*() da otro resultado que antes de la migración.\nANTES:\n%\nDESPUÉS:\n%',
      current_setting('conversion_cliente_antiguo.trinquetes_antes', true), v_foto;
  end if;
  raise notice 'POSTFLIGHT conversion_cliente_antiguo: las tres piezas, la puerta y los dos núcleos con sus huellas · dependencias, llamadores, restricciones y RLS intactos · % trinquetes idénticos a los previos', v_gates;
end
$post$;

commit;
