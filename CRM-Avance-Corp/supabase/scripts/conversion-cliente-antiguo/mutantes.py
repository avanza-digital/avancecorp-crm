#!/usr/bin/env python3
"""Catálogo de MUTANTES del ensayo del bloque 2.10 (lo usa mutantes.sh; no toca la base).

Cada mutante rompe UNA defensa DESPUÉS de instalar la migración real (y las del 2.11 y el 2.16, delante) y declara qué casos del oráculo
(`pruebas.sql`) tienen que nombrar su fallo («FALLO <caso>»). Los de CUERPO cambian un fragmento del cuerpo vivo (pg_get_functiondef)
de la puerta, de un núcleo o de una pieza; cada fragmento tiene que aparecer EXACTAMENTE las veces declaradas o el mutante se niega
(«MUTANTE NO APLICABLE»): si la migración cambia, no muta otra cosa sin que nadie se entere. Los de CATÁLOGO son SQL libre.

Los del encargo (ENCARGO 2-2.10, punto 3): sin la absorción (M1), sin el enlace (M2), el enlace ANTES del UPDATE (M3: el verificador
lo contaría como otro lead), la conciliación contando la historia (M4, en el reintento), sin el veredicto del activo de otro (M5), los
clientes con ficha como candidatos (M6 puntero, M7 puente), sin FOR UPDATE NOWAIT (M8), sin retirar al activo del mismo asesor (M9), sin
la nota (M10), sin el libro (M11), el veredicto con datos de más (M12), el nombre sin la bandeja (M13), el primer candidato manda (M14),
el puente como canónico (M15), sin creado_por (M16), la historia también para el canónico (M17) o para un no convertido (M18), los
núcleos sin la historia (M19 escritura, M20 lectura), otro error que el P0481 (M21), la absorción antes del No insistir del lead (M22) y
antes de «ya está cerrado» (M23); ronda 2 (D-83, P3-2.i): sin completar el cierre inicial (M24), el retiro
sin envolver (M25), el cierre completado con un documento ajeno (M26), la absorción con un cierre de otra persona (M27); ronda 3 (D-85):
la absorción pese al documento ajeno, sin detenerse (M28); ronda 4 (D-86/D-87, P3-2, auditor r2): sin cada comprobación del perfil
(M29–M31), sin enlazar el perfil propio (M32), el perfil enlazado antes del UPDATE (M33), sin reponer la válvula (M34), el 23505 crudo
(M35), el detalle del retiro con el texto interno (M36); ronda 5 (D-89): enlaza la desactivada (M37), trata la activa como desactivada
(M38), D-89 antes que D-86 (M39); ronda 6 (Codex r1, D-90): las tareas del antiguo canceladas como asesor (M40), UPDATE físico a los
retirados (M41), la historia sin exigir el retiro (M42); ronda 7 (D-91): la puerta sin la comprobación de D-91 (M43: un retirado ya unido
ANTES vuelve a pasar la conciliación y lo para el verificador con P0481), D-91 sin eximir los puentes de ESTA conversión (M44: el reintento
se detiene), la exención sin exigir el mismo lead (M45) o sin exigir lead_conversion = este lead (M46); con D-91 la puerta también
detiene B7b y A1s por su puente de antes, así que M18 y M42 los matan los contratos de la pieza (U8, U7); ronda 8 (D-91 solo cuando la
preparación ESCRIBE el DNI): la comprobación sin la condición del DNI (M47: detiene también al lead que ya lleva el DNI y al CE), con la
condición invertida (M48: detiene solo al que ya lo lleva), sin el tipo de documento (M49: un CE también detiene) o por el puntero en vez
de por el DNI (M50: el lead con el DNI y sin puntero también se detiene); desde la ronda 8 el reintento (A13) ya lleva el DNI y no llega a
la comprobación, así que M44 (sin la exención de los puentes de ESTA conversión) lo mata la inspección C1d del cuerpo; ronda 9 (D-94, el
«No insistir» del antiguo detiene siempre): la puerta sin la comprobación (M51: también con el DNI ya escrito o con un CE se convierte, y se
absorbe), solo con la historia (M52: el candidato por absorber con No insistir pasa), solo con los candidatos (M53: el retirado ya unido con No
insistir pasa), la comprobación ANTES de la conciliación (M54: el lead SIN DNI recibe el P0481 en vez del P0409 de D-91), con otro detalle (M55) o con
otro código (M56); catálogo: EXECUTE de más en una pieza (MC1), otra función usa una pieza (MC2), la puerta pierde EXECUTE (MC3), un núcleo con otro SET (MC4), la pieza de
historia DEFINER (MC5).

Uso:  python3 -I mutantes.py lista                  → una línea por mutante: id|descripción|caso1;caso2;…
      python3 -I mutantes.py sql <id> <archivo.sql>  → escribe el SQL que instala ese mutante
      python3 -I mutantes.py comprobar <migración.sql> <carpeta con *-nuevo.def>
                                                     → comprueba en LOCAL que cada fragmento aparece las veces declaradas
"""
import os, sys

P = 'crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)'
E = 'private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid)'
L = 'private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid)'
A = 'private.conversion_absorber_cliente_antiguo(uuid,uuid,text,uuid,uuid)'
N = 'private.conversion_enlazar_cliente_antiguo(uuid,jsonb,uuid)'
H = 'private.lead_historia_de_persona(uuid,uuid)'

# ── Fragmentos vigentes (los que deja la migración, tal como los devuelve pg_get_functiondef) ────────────────────────────
ABSORCION = ("  if p_tipo_documento='DNI' then\n"
             "    v_antiguo:=private.conversion_absorber_cliente_antiguo(p_lead,v_persona,v_doc,v_l.vendedor_id,v_uid);\n"
             "    if v_antiguo ? 'veredicto' then\n"
             "      raise exception 'Contacto no disponible' using errcode='P0481', detail=(v_antiguo->'veredicto')::text;\n"
             "    end if;\n"
             "  end if;\n")
ENLACE = ("  if v_antiguo ? 'candidatos' then\n"
          "    perform private.conversion_enlazar_cliente_antiguo(v_persona,v_antiguo->'candidatos',v_uid);\n"
          "  end if;\n")
UPDATE_L2 = "  perform set_config('crm.op_privilegiada','on',true);\n  update crm.leads set inversionista_id=v_persona,nombre_completo=btrim(p_nombre),\n"
HISTORIA_X = " and not private.lead_historia_de_persona(x,v_persona)"
VETO_LEAD = "  if v_l.no_contactar then raise exception 'El lead tiene No insistir' using errcode='P0429'; end if;\n"
CERRADO = "  if v_l.etapa in ('convertido','descartado') then\n"
P0481 = "      raise exception 'Contacto no disponible' using errcode='P0481', detail=(v_antiguo->'veredicto')::text;\n"
# la pieza de absorción
VEREDICTO_IF = "      if v_c.activo and v_c.vendedor_id is distinct from p_vendedor then\n"
SIN_PUNTERO = "        and l.inversionista_id is null\n"
SIN_PUENTE = "        and not exists (select 1 from crm.inversionista_leads il where il.lead_id = l.id)\n"
NOWAIT = "      for update of l nowait\n"
RETIRO = ("      begin\n"
          "        update crm.leads set activo = false where id = v_c.id and activo;\n"
          "        get diagnostics v_n = row_count;\n"
          "      exception\n"
          "        when lock_not_available then\n"
          "          raise exception 'El lead está en uso por otra operación; vuelve a intentarlo' using errcode = '40001';\n"
          "        when serialization_failure or deadlock_detected then\n"
          "          raise;\n"
          "        when others then\n"
          "          -- Al cliente solo el código (capa 3: sin detalles internos); el texto original queda en el registro del servidor.\n"
          "          raise log 'conversion_absorber_cliente_antiguo: no se pudo retirar el cliente antiguo %: % %', v_c.id, sqlstate, sqlerrm;\n"
          "          raise exception 'El cliente antiguo no se puede retirar; requiere conciliación de Gerencia'\n"
          "            using errcode = 'P0409', detail = sqlstate;\n"
          "      end;\n"
          "      if v_n <> 1 then\n"
          "        raise exception 'El cliente antiguo no se puede retirar; requiere conciliación de Gerencia' using errcode = 'P0409';\n"
          "      end if;\n")
RETIRO_CRUDO = ("      update crm.leads set activo = false where id = v_c.id and activo;\n"
                "      get diagnostics v_n = row_count;\n"
                "      if v_n <> 1 then\n"
                "        raise exception 'El cliente antiguo no se puede retirar; requiere conciliación de Gerencia' using errcode = 'P0409';\n"
                "      end if;\n")
# ronda 4: el detalle del retiro (P3-2) y el paso del perfil (D-86/D-87), la válvula, el 23505
DETAIL_SQLSTATE = "            using errcode = 'P0409', detail = sqlstate;\n"
PERFIL_OTRA_RAISE = "        raise exception 'El perfil del Portal del cliente antiguo pertenece a otra persona; requiere conciliación de Gerencia' using errcode = 'P0409';\n"
PERFIL_FICHA_RAISE = "          raise exception 'La ficha ya tiene otra cuenta del Portal; requiere conciliación de Gerencia' using errcode = 'P0409';\n"
PERFIL_DOC_RAISE = "          raise exception 'El perfil del Portal del cliente antiguo lleva otro documento; requiere conciliación de Gerencia' using errcode = 'P0409';\n"
PERFIL_PENDIENTE = "          v_perfil_enlazar := v_c.perfil_id;\n"
ENLAZA_PERFIL = "      update crm.inversionistas set perfil_id = v_p.perfil_id where id = p_persona and perfil_id is null;\n"
VALVULA = "  perform pg_catalog.set_config('crm.op_privilegiada', v_previo, true);\n  return pg_catalog.jsonb_build_object('candidatos', v_salida);\n"
# ronda 5 (D-89): la cuenta propia desactivada no se enlaza; D-86 se mira antes
DESACTIVADA_IF = "          if v_pdesactivada then\n"
DESACTIVADA_PRED = "      v_pdesactivada := not found or v_pactivo is not true or v_prol <> 'cliente';\n"
D86_PRIMERO = "      if v_perfil_de is not null and v_perfil_de <> p_persona then\n"
# ronda 6 (Codex r1, D-90)
RETIRO_INICIO = ("      begin\n"
                 "        update crm.leads set activo = false where id = v_c.id and activo;\n")
SOLO_ACTIVOS = "    if v_c.activo then\n      insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)\n"
HISTORIA_RETIRO = "      and l.inversionista_id is null\n      and l.activo = false)\n"
UNICO_40001 = ("    exception when unique_violation then\n"
               "      raise exception 'La cuenta del Portal del cliente antiguo cambió mientras se enlazaba; vuelve a intentarlo' using errcode = '40001';\n")
# el cierre inicial (D-83)
CIERRE_UPDATE = "        update crm.cierres_externos set inversionista_id = p_persona where id = v_ce.id;\n"
CIERRE_DOCUMENTO = "      elsif v_ce.inversionista_id is null and not private.documento_es_de_identidad(p_persona, v_ce.documento_tipo, v_ce.documento) then\n"
D84_RAISE = "        raise exception 'El cierre del cliente antiguo pertenece a otra persona; requiere conciliación de Gerencia' using errcode = 'P0409';\n"
D85_RAISE = "        raise exception 'El cierre del cliente antiguo lleva otro documento; requiere conciliación de Gerencia' using errcode = 'P0409';\n"
NOTA = ("      insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)\n"
        "      values (v_c.id, 'nota', 'Lead enlazado a la ficha del cliente al convertir otro lead suyo; queda retirado (D-38)',\n"
        "              pg_catalog.jsonb_build_object('evento', 'enlace_identidad', 'operacion_id', v_op, 'inversionista_id', p_persona, 'lead_conversion', p_lead),\n"
        "              p_uid);\n")
LIBRO = ("    insert into crm.inversionista_operaciones (tipo, inversionista_id, lead_id, motivo, detalle, por)\n"
         "    values ('enlace', p_persona, v_c.id, 'Conversión: cliente antiguo sin ficha de persona, enlazado a la misma ficha (D-38)',\n"
         "            pg_catalog.jsonb_build_object('via', 'preparar_conversion_inversion', 'rol', 'historico', 'lead_conversion', p_lead,\n"
         "                                          'lead_antiguo_activo', v_c.activo, 'retirado_al_absorber', v_c.activo,\n"
         "                                          'vendedor_antiguo', v_c.vendedor_id, 'vendedor_conversion', p_vendedor,\n"
         "                                          'cierre_completado', v_cierre,\n"
         "                                          'cierre_no_completado', case when v_ce.id is not null and v_cierre is null then v_ce.id end,\n"
         "                                          'cierre_motivo', v_cierre_motivo,\n"
         "                                          'perfil_completado', v_perfil_enlazar,\n"
         "                                          'perfil_no_enlazado', v_perfil_no_enlazado,\n"
         "                                          'perfil_motivo', v_perfil_motivo),\n"
         "            p_uid)\n"
         "    returning id into v_op;\n")
VEREDICTO_BUILD = "          v_veredicto := pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(v_c.tenedor, 'sin asesor asignado'));\n"
TENEDOR = "             coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor\n"
PRIMERO = "        if v_veredicto is null then\n"
# la pieza de enlace y la de historia
PUENTE = "    values (p_persona, v_c.id, 'historico', p_uid);\n"
ROL_HIST = "      and il.rol = 'historico'\n"
ETAPA_CONV = "      and l.etapa = 'convertido'\n"
# ronda 7 (D-91): la comprobación de la puerta y sus condiciones; ronda 8: solo si la preparación ESCRIBE el DNI
D91_CONDICION = ("    or (p_tipo_documento='DNI' and v_l.dni is distinct from v_doc\n"
                 "      and exists(select 1 from crm.inversionista_leads il where il.inversionista_id=v_persona and il.rol='historico' and il.lead_id<>p_lead\n"
                 "        and not exists(select 1 from crm.inversionista_operaciones o where o.tipo='enlace' and o.lead_id=il.lead_id\n"
                 "          and o.detalle->>'lead_conversion'=p_lead::text))) then\n")
D91_EXIME = ("\n        and not exists(select 1 from crm.inversionista_operaciones o where o.tipo='enlace' and o.lead_id=il.lead_id\n"
             "          and o.detalle->>'lead_conversion'=p_lead::text))) then\n")
D91_MISMO_LEAD = " and o.lead_id=il.lead_id\n"
D91_ESTA_CONVERSION = "\n          and o.detalle->>'lead_conversion'=p_lead::text))) then\n"
D91_SOLO_SI_ESCRIBE = ("    or (p_tipo_documento='DNI' and v_l.dni is distinct from v_doc\n"
                       "      and exists(")
D91_TIPO = "(p_tipo_documento='DNI' and v_l.dni is distinct from v_doc\n"
D91_DNI = "v_l.dni is distinct from v_doc\n"

# ronda 9 (D-94): la comprobación del «No insistir» del antiguo, después de la conciliación y antes del UPDATE
D94_BLOQUE = ("  if exists(select 1 from private.leads_de_personas(array[v_persona]) x join crm.leads lx on lx.id=x\n"
              "        where x<>p_lead and lx.no_contactar and private.lead_historia_de_persona(x,v_persona))\n"
              "    or exists(select 1 from jsonb_array_elements(coalesce(v_antiguo->'candidatos','[]'::jsonb)) c join crm.leads lc on lc.id=(c->>'id')::uuid\n"
              "        where lc.no_contactar) then\n"
              "    raise exception 'Contacto no disponible' using errcode='P0481', detail=jsonb_build_object('estado','no_contactar')::text;\n"
              "  end if;\n")
D94_SOLO_HISTORIA = ("        where x<>p_lead and lx.no_contactar and private.lead_historia_de_persona(x,v_persona))\n"
                     "    or exists(select 1 from jsonb_array_elements(coalesce(v_antiguo->'candidatos','[]'::jsonb)) c join crm.leads lc on lc.id=(c->>'id')::uuid\n"
                     "        where lc.no_contactar) then\n")
D94_SOLO_CANDIDATOS = ("  if exists(select 1 from private.leads_de_personas(array[v_persona]) x join crm.leads lx on lx.id=x\n"
                       "        where x<>p_lead and lx.no_contactar and private.lead_historia_de_persona(x,v_persona))\n"
                       "    or exists(")
D94_DETALLE = "detail=jsonb_build_object('estado','no_contactar')::text;\n"
D94_RAISE = "    raise exception 'Contacto no disponible' using errcode='P0481', detail=jsonb_build_object('estado','no_contactar')::text;\n"

ABSORBEN = ['A1-', 'A2-', 'A4-', 'A10-', 'A12-', 'A1f-', 'A4e-', 'A23-', 'A1l-', 'A1m-']
DETENIDAS_D85 = ['A1e-', 'A1g-']
DETENIDAS_D86 = ['A1i-', 'A1j-', 'A1k-', 'A1p-', 'A1q-']
VEREDICTOS = ['A3-', 'A9-', 'A9b-', 'A16-', 'A17-', 'A21-', 'A22-']
CON_CIERRE = ['A1-', 'A2-', 'A4-', 'A10-', 'A11-', 'A12-', 'A13-', 'A4e-', 'A23-', 'A1l-', 'A1m-']

MUTANTES = [
  # ── Los del encargo ──
  ('M1', 'puerta: sin la absorción (persona nueva en el retirado, conciliación en el activo: lo de hoy)',
   [(P, ABSORCION, '', 1)], ABSORBEN + VEREDICTOS + DETENIDAS_D85 + DETENIDAS_D86 + ['A1m-', 'A1h-', 'A13-', 'C1-']),
  ('M2', 'puerta: sin el enlace (el antiguo queda retirado y con rastro, pero sin puente)',
   [(P, ENLACE, '', 1)], ABSORBEN + ['A13-', 'C1-']),
  ('M3', 'puerta: el enlace ANTES del UPDATE que escribe el DNI (el verificador cuenta el puente como otro lead de la persona)',
   [(P, ENLACE, '', 1), (P, UPDATE_L2, ENLACE + UPDATE_L2, 1)], ABSORBEN + ['C1-']),
  ('M4', 'puerta: la conciliación cuenta la historia como otro lead (el reintento se detiene en conciliación)',
   [(P, HISTORIA_X, '', 2)], ['A13-', 'C1-']),
  ('M5', 'absorción: sin el veredicto del activo de otro asesor (se absorbe también a él)',
   [(A, VEREDICTO_IF, "      if false then\n", 1)], VEREDICTOS),
  ('M6', 'absorción: los clientes CON puntero son candidatos (un convertido con puntero y sin puente recibe el veredicto en vez de conciliación)',
   [(A, SIN_PUNTERO, '', 1)], ['B2b-']),
  ('M7', 'absorción: los convertidos con puente ajeno son candidatos (reciben otro puente)',
   [(A, SIN_PUENTE, '', 1)], ['B5-']),
  ('M8', 'absorción: los candidatos sin FOR UPDATE NOWAIT (muere por la inspección del catálogo, C1b: NO prueba contención real)',
   [(A, NOWAIT, '', 1)], ['C1b-']),
  ('M9', 'absorción: sin retirar al activo del mismo asesor (el verificador lo cuenta como suelto vivo: P0481 vía identidad)',
   [(A, RETIRO, '', 1)], ['A4-', 'A11-']),
  ('M10', 'absorción: sin la nota en el lead antiguo activo',
   [(A, NOTA, '', 1)], ['A4-', 'A11-']),
  ('M11', 'absorción: sin el rastro en el libro de operaciones',
   [(A, LIBRO, "    v_op := pg_catalog.gen_random_uuid();\n", 1)], ABSORBEN),
  ('M12', 'absorción: el veredicto con datos de más (ya no es el formato del alta; la pantalla no lo presentaría)',
   [(A, VEREDICTO_BUILD, "          v_veredicto := pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(v_c.tenedor, 'sin asesor asignado'), 'via', 'conversion');\n", 1)],
   VEREDICTOS),
  ('M13', 'absorción: el nombre solo del vendedor (una bandeja de supervisor sale «sin asesor asignado», no como el alta)',
   [(A, TENEDOR, "             pv.nombre_completo as tenedor\n", 1)], ['A17-']),
  ('M14', 'absorción: el primer candidato manda (un activo del mismo asesor más reciente tapa al activo de otro)',
   [(A, PRIMERO, "        if v_veredicto is null and pg_catalog.jsonb_array_length(v_candidatos) = 0 then\n", 1)], ['A9b-']),
  ('M15', 'enlace: el puente como canónico (choca con el puente canónico del lead que se convierte)',
   [(N, PUENTE, "    values (p_persona, v_c.id, 'canonico', p_uid);\n", 1)], ABSORBEN),
  ('M16', 'enlace: el puente sin creado_por',
   [(N, PUENTE, "    values (p_persona, v_c.id, 'historico', null);\n", 1)], ABSORBEN),
  ('M17', 'historia: también el puente canónico es historia (un convertido con puente canónico y sin puntero deja de pedir conciliación)',
   [(H, ROL_HIST, '', 1)], ['B2d-']),
  ('M18', 'historia: también un lead NO convertido con puente histórico es historia (desde D-91 la puerta detiene B7b también por su puente de antes: lo mata el contrato U8)',
   [(H, ETAPA_CONV, '', 1)], ['U8-']),
  ('M19', 'núcleo de escritura: la conciliación cuenta la historia (la solicitud no se puede preparar)',
   [(E, HISTORIA_X, '', 1)], ['A1b-', 'C2-']),
  ('M20', 'núcleo de lectura: la conciliación cuenta la historia (la pantalla no podría seguir)',
   [(L, HISTORIA_X, '', 1)], ['A1b-', 'C2-']),
  ('M21', 'puerta: el veredicto con otro error (P0409 en vez del P0481 de la regla del cliente)',
   [(P, P0481, "      raise exception 'Contacto no disponible' using errcode='P0409', detail=(v_antiguo->'veredicto')::text;\n", 1)], VEREDICTOS),
  ('M22', 'puerta: la absorción ANTES del No insistir del lead que se convierte (el veredicto tapa el P0429 de hoy)',
   [(P, ABSORCION, '', 1), (P, VETO_LEAD, ABSORCION + VETO_LEAD, 1)], ['A18-']),
  ('M23', 'puerta: la absorción ANTES de «ya está cerrado» (el veredicto tapa el P0409 de hoy)',
   [(P, ABSORCION, '', 1), (P, CERRADO, ABSORCION + CERRADO, 1)], ['A19-']),
  # ── Ronda 2: el cierre inicial (D-83) y el retiro envuelto (P3-2.i) ──
  ('M24', 'absorción: sin completar el cierre inicial del antiguo (D-83; la operación lo dice igual)',
   [(A, CIERRE_UPDATE, '', 1)], CON_CIERRE),
  ('M25', 'absorción: sin envolver el retiro (el P0001 de la casa llega crudo, no el P0409 con el mensaje de la casa)',
   [(A, RETIRO, RETIRO_CRUDO, 1)], ['A4c-']),
  ('M26', 'absorción: completa el cierre aunque su documento no sea de la persona (D-85)',
   [(A, CIERRE_DOCUMENTO, "      elsif false then\n", 1)], DETENIDAS_D85),
  ('M27', 'absorción: absorbe aunque el cierre del antiguo ya sea de OTRA persona (sin el P0409 de D-84)',
   [(A, D84_RAISE, "        null;\n", 1)], ['A1d-']),
  ('M28', 'absorción: absorbe pese al documento ajeno del cierre, sin detenerse y sin completarlo (sin el P0409 de D-85)',
   [(A, D85_RAISE, "        null;\n", 1)], DETENIDAS_D85),
  # ── Ronda 4: el perfil del Portal (D-86/D-87), el detalle del retiro (P3-2), la válvula y el 23505 ──
  ('M29', 'absorción: sin la comprobación «el perfil es de OTRA persona» (D-86)',
   [(A, PERFIL_OTRA_RAISE, "        null;\n", 1)], ['A1i-']),
  ('M30', 'absorción: sin la comprobación «la ficha ya tiene otra cuenta del Portal» (D-86)',
   [(A, PERFIL_FICHA_RAISE, "          null;\n", 1)], ['A1j-']),
  ('M31', 'absorción: sin la comprobación del documento del perfil: enlaza un perfil con documento ajeno (D-86)',
   [(A, PERFIL_DOC_RAISE, "          null;\n", 1)], ['A1k-', 'A1p-']),
  ('M32', 'enlace: no enlaza el perfil propio a la ficha (D-87)',
   [(N, ENLAZA_PERFIL, "      v_m := 1;\n", 1)], ['A1l-']),
  ('M33', 'absorción: enlaza el perfil propio ANTES del UPDATE del lead que se convierte (el verificador lo cuenta: P0481 vía identidad)',
   [(A, PERFIL_PENDIENTE, "          v_perfil_enlazar := v_c.perfil_id;\n          update crm.inversionistas set perfil_id = v_c.perfil_id where id = p_persona;\n", 1)],
   ['A1l-']),
  ('M34', 'absorción: sin reponer la válvula crm.op_privilegiada como la encontró',
   [(A, VALVULA, "  return pg_catalog.jsonb_build_object('candidatos', v_salida);\n", 1)], ['U5-']),
  ('M35', 'enlace: la carrera por el perfil sale como 23505 crudo, no como el 40001 de la casa',
   [(N, UNICO_40001, "    exception when unique_violation then\n      raise;\n", 1)], ['U6-']),
  ('M36', 'absorción: el P0409 del retiro vuelve a llevar el texto interno del error en el detalle (P3-2)',
   [(A, DETAIL_SQLSTATE, "            using errcode = 'P0409', detail = sqlstate || ': ' || sqlerrm;\n", 1)], ['A4c-']),
  # ── Ronda 5: D-89 ──
  ('M37', 'absorción: enlaza la cuenta del Portal propia aunque esté DESACTIVADA (el núcleo detiene la conversión: «requiere revisión»)',
   [(A, DESACTIVADA_IF, "          if false then\n", 1)], ['A1m-']),
  ('M38', 'absorción: trata la cuenta ACTIVA como desactivada (no enlaza el perfil propio)',
   [(A, DESACTIVADA_PRED, "      v_pdesactivada := true;\n", 1)], ['A1l-']),
  ('M39', 'absorción: D-89 antes que D-86 (una cuenta desactivada en conflicto ya no detiene)',
   [(A, D86_PRIMERO, "      if v_pdesactivada then\n        v_perfil_no_enlazado := v_c.perfil_id; v_perfil_motivo := 'cuenta del Portal desactivada';\n      elsif v_perfil_de is not null and v_perfil_de <> p_persona then\n", 1)],
   ['A1q-', 'A1j-', 'A1k-', 'A1p-']),
  # ── Ronda 6: lo que pidió Codex r1 y D-90 ──
  ('M40', 'absorción: las tareas pendientes del antiguo activo se cancelan como «asesor» antes del retiro (no como «sistema»)',
   [(A, RETIRO_INICIO, "      perform pg_catalog.set_config('crm.op_tarea', 'on', true);\n      update crm.tareas set estado = 'cancelada' where lead_id = v_c.id and estado = 'pendiente';\n"
                       "      perform pg_catalog.set_config('crm.op_tarea', 'off', true);\n" + RETIRO_INICIO, 1)], ['A4e-']),
  ('M41', 'absorción: también «retira» (UPDATE físico) a los antiguos que ya estaban retirados',
   [(A, SOLO_ACTIVOS, "    if not v_c.activo then\n      update crm.leads set activo = false where id = v_c.id;\n    end if;\n" + SOLO_ACTIVOS, 1)],
   ['A23-', 'A1-', 'A10-', 'A13-']),
  ('M42', 'historia: sin exigir el retiro (un antiguo ya unido por puente y ACTIVO deja de ser otro lead; D-90; desde D-91 la puerta detiene A1s también por su puente de antes: lo mata el contrato U7)',
   [(H, HISTORIA_RETIRO, "      and l.inversionista_id is null)\n", 1)], ['U7-']),
  # ── Ronda 7 (D-91) ──
  ('M43', 'puerta: sin la comprobación de D-91 (un antiguo retirado ya unido ANTES pasa la conciliación como historia y el verificador lo detiene con P0481: lo de la ronda 6)',
   [(P, D91_CONDICION, "    then\n", 1)], ['A1r-', 'A1r2-', 'A1r3-', 'C1d-']),
  ('M44', 'puerta: D-91 sin eximir los puentes que puso ESTA conversión (desde la ronda 8 el reintento ya lleva el DNI y no llega a la comprobación: la exención solo la prueba la inspección C1d)',
   [(P, D91_EXIME, ")) then\n", 1)], ['C1d-']),
  ('M45', 'puerta: D-91 exime con cualquier operación de ESTA conversión, sin exigir que sea la del mismo lead (la absorción de otro antiguo tapa el puente de antes)',
   [(P, D91_MISMO_LEAD, "\n", 1)], ['A1r2-']),
  ('M46', 'puerta: D-91 exime con cualquier operación de enlace del lead, sin exigir lead_conversion = este lead (la de OTRA conversión tapa el puente de antes)',
   [(P, D91_ESTA_CONVERSION, "))) then\n", 1)], ['A1r3-', 'C1d-']),
  # ── Ronda 8 (D-91 solo cuando la preparación ESCRIBE el DNI) ──
  ('M47', 'puerta: D-91 sin la condición del DNI (la comprobación también detiene al lead que YA lleva el DNI y al CE: lo de la ronda 7)',
   [(P, D91_SOLO_SI_ESCRIBE, "    or (exists(", 1)], ['A1u-', 'A1ub-', 'A1u2-', 'A1v-', 'C1d-']),
  ('M48', 'puerta: D-91 con la condición invertida (solo detiene al lead que YA lleva el DNI; al que lo recibe ahora lo deja pasar y el verificador lo para con P0481)',
   [(P, D91_DNI, "v_l.dni is not distinct from v_doc\n", 1)], ['A1r-', 'A1r2-', 'A1r3-', 'A1u-', 'A1u2-', 'C1d-']),
  ('M49', 'puerta: D-91 sin el tipo de documento (un CE o un pasaporte, que no escriben el DNI, también se detienen)',
   [(P, D91_TIPO, "(v_l.dni is distinct from v_doc\n", 1)], ['A1v-', 'C1d-']),
  ('M50', 'puerta: D-91 por el puntero en vez de por el DNI (el lead que ya lleva el DNI y todavía no apunta a la persona también se detiene)',
   [(P, "v_l.dni is distinct from v_doc\n", "v_l.inversionista_id is null\n", 1)], ['A1u2-', 'C1d-']),
  # ── Ronda 9 (D-94: el «No insistir» del antiguo detiene siempre) ──
  ('M51', 'puerta: sin la comprobación de D-94 (con el DNI ya escrito o con un CE el veto del antiguo se salta: se convierte, y el candidato se absorbe)',
   [(P, D94_BLOQUE, '', 1)], ['A1w-', 'A1wc-', 'A1wv-', 'C1e-']),
  ('M52', 'puerta: D-94 solo con la historia (el candidato retirado por absorber con No insistir pasa y se absorbe)',
   [(P, D94_SOLO_HISTORIA, "        where x<>p_lead and lx.no_contactar and private.lead_historia_de_persona(x,v_persona)) then\n", 1)], ['A1wc-', 'C1e-']),
  ('M53', 'puerta: D-94 solo con los candidatos (el retirado ya unido por puente histórico con No insistir pasa y se convierte)',
   [(P, D94_SOLO_CANDIDATOS, "  if exists(", 1)], ['A1w-', 'A1wv-', 'C1e-']),
  ('M54', 'puerta: D-94 ANTES de la conciliación (el lead SIN DNI con un retirado ya unido y No insistir recibe el P0481 en vez del P0409 de D-91)',
   [(P, D94_BLOQUE, '', 1), (P, ABSORCION, ABSORCION + D94_BLOQUE, 1)], ['A1wb-', 'C1e-']),
  ('M55', 'puerta: D-94 con otro detalle (el veredicto ya no es exactamente {"estado": "no_contactar"})',
   [(P, D94_DETALLE, "detail=jsonb_build_object('estado','no_contactar','via','conversion')::text;\n", 1)], ['A1w-', 'A1wc-', 'A1wv-', 'C1e-']),
  ('M56', 'puerta: D-94 con otro código (P0409 en vez del P0481 de la regla del cliente)',
   [(P, D94_RAISE, "    raise exception 'Contacto no disponible' using errcode='P0409', detail=jsonb_build_object('estado','no_contactar')::text;\n", 1)], ['A1w-', 'A1wc-', 'A1wv-', 'C1e-']),
  # ── Catálogo ──
  ('MC1', 'authenticated gana EXECUTE sobre la pieza de absorción',
   'grant execute on function %s to authenticated;' % A, ['C1b-']),
  ('MC2', 'otra función usa la pieza de historia',
   "create function private.ensayo_2_10_otro_llamador() returns boolean language sql stable set search_path = '' as "
   "$m$ select private.lead_historia_de_persona(null::uuid, null::uuid) $m$;", ['C3-']),
  ('MC3', 'authenticated pierde EXECUTE sobre la puerta (su ficha ya no es la de hoy)',
   'revoke execute on function %s from authenticated;' % P, ['C1-']),
  ('MC4', 'el núcleo de escritura con otro SET (su ficha ya no es la de hoy)',
   "alter function %s set statement_timeout = '30s';" % E, ['C2-']),
  ('MC5', 'la pieza de historia pasa a security definer',
   'alter function %s security definer;' % H, ['C2-']),
]


def sql_de(frags):
    partes = []
    for firma, vigente, mutado, veces in frags:
        for t in ('$vigente$', '$mutado$', '$mutar$'):
            assert t not in vigente and t not in mutado, 'la etiqueta %s aparece en un fragmento' % t
        assert vigente != mutado, 'un fragmento no cambia nada'
        partes.append("""do $mutar$
declare
  v_def text;
  v_veces integer;
begin
  v_def := pg_get_functiondef('%s'::regprocedure);
  v_veces := (length(v_def) - length(replace(v_def, $vigente$%s$vigente$, ''))) / length($vigente$%s$vigente$);
  if v_veces <> %s then
    raise exception 'MUTANTE NO APLICABLE: el fragmento aparece %% veces en %s (debían ser %s)', v_veces;
  end if;
  execute replace(v_def, $vigente$%s$vigente$, $mutado$%s$mutado$);
end;
$mutar$;
""" % (firma, vigente, vigente, veces, firma, veces, vigente, mutado))
    return '\n'.join(partes)


def pieza(texto, nombre_con_args, cabecera):
    ini = 'create function %s\n' % nombre_con_args
    assert texto.count(ini) == 1, ini
    i = texto.index('as $function$', texto.index(ini)) + len('as $function$')
    cuerpo = texto[i:texto.index('$function$;', i)]
    return 'CREATE OR REPLACE FUNCTION %s\n%sAS $function$%s$function$\n' % (nombre_con_args, cabecera, cuerpo)


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == 'lista':
        ids = [m[0] for m in MUTANTES]
        assert len(ids) == len(set(ids)), 'ids repetidos'
        for id_, desc, _, casos in MUTANTES:
            assert casos, 'el mutante %s no declara por qué fallo tiene que morir' % id_
            print('%s|%s|%s' % (id_, desc, ';'.join(casos)))
        return
    if len(sys.argv) == 4 and sys.argv[1] == 'sql':
        m = [x for x in MUTANTES if x[0] == sys.argv[2]]
        if len(m) != 1:
            sys.exit('mutante desconocido: %s' % sys.argv[2])
        _, _, cuerpo, _ = m[0]
        sql = cuerpo + '\n' if isinstance(cuerpo, str) else sql_de(cuerpo)
        open(sys.argv[3], 'w', encoding='utf-8').write(sql)
        return
    if len(sys.argv) == 4 and sys.argv[1] == 'comprobar':
        mig = open(sys.argv[2], encoding='utf-8').read()
        d = sys.argv[3].rstrip('/') + '/'
        textos = {P: open(d + 'puerta-nuevo.def', encoding='utf-8').read(), E: open(d + 'escritura-nuevo.def', encoding='utf-8').read(),
                  L: open(d + 'lectura-nuevo.def', encoding='utf-8').read(),
                  A: pieza(mig, 'private.conversion_absorber_cliente_antiguo(p_lead uuid, p_persona uuid, p_dni text, p_vendedor uuid, p_uid uuid)', " RETURNS jsonb\n LANGUAGE plpgsql\n SET search_path TO ''\n"),
                  N: pieza(mig, 'private.conversion_enlazar_cliente_antiguo(p_persona uuid, p_candidatos jsonb, p_uid uuid)', " RETURNS integer\n LANGUAGE plpgsql\n SET search_path TO ''\n"),
                  H: pieza(mig, 'private.lead_historia_de_persona(p_lead uuid, p_persona uuid)', " RETURNS boolean\n LANGUAGE sql\n STABLE\n SET search_path TO ''\n")}
        malos = 0
        for id_, _, cuerpo, _ in MUTANTES:
            if isinstance(cuerpo, str):
                continue
            texto = dict(textos)
            for firma, vigente, mutado, veces in cuerpo:
                n = texto[firma].count(vigente)
                if n != veces:
                    print('✗ %s: el fragmento aparece %d veces en %s (debían ser %d): %r' % (id_, n, firma, veces, vigente[:70]))
                    malos += 1
                texto[firma] = texto[firma].replace(vigente, mutado)
            print('✓ %s aplicable' % id_)
        sys.exit(1 if malos else 0)
    sys.exit(__doc__)


if __name__ == '__main__':
    main()
