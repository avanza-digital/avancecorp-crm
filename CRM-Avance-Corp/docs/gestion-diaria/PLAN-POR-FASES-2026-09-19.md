# Plan por fases — Módulo GESTIÓN DIARIA (CRM Avance Corp)

> **Estado al 20/09/2026:** F0, F1 y F2 EN PRODUCCIÓN; sigue F3. Dónde estamos y cómo retomar: `ESTADO-Y-RETOMAR-2026-09-20.md` (misma carpeta).


Fuente: `CRM-Avance-Corp/GESTION DIARIA/gestion-diaria-handoff.zip` (PLAN.md 18–19/09/2026, 6 mockups, UI-UX-playbook.pdf). Diagnóstico del 19/09 leyendo el código real (front, 295 migraciones, vault): 67 elementos de los mockups mapeados a su fuente, y el plan sometido a tres refutadores independientes (SQL, front, fidelidad al negocio). Todo lo que sigue cita archivo y línea verificados.

## Context

**Problema.** «Seguimiento» no permite decidir nada porque la captura de llamadas es pobre: dos tipos (`llamada_realizada` / `llamada_no_contestada`), `detalle` en texto libre (31 % vacío), `metadata` 100 % vacío, compromisos («prox. llamada 21-09») que viven en prosa sin tarea. La tasa de contacto está contaminada.

**Meta.** Un módulo nuevo, **Gestión Diaria**, que responde una sola pregunta: *¿qué está pasando hoy y qué hay que hacer ahora?* Tres vistas por rol (analista / supervisor / gerencia) y la pieza que lo desbloquea: **el resultado de llamada tipificado y obligatorio** (7 opciones aprobadas en el mockup 5), guardado en `crm.actividades.metadata` sin tocar el CHECK de `tipo`.

**Decisiones de Miguel (19/09, esta sesión):**
1. **«Hoy» se queda igual.** Gestión Diaria es un módulo DISTINTO en el menú (grupo Operación, donde hoy está Seguimiento). La pantalla de entrada de cada rol no cambia.
2. **Cola del analista: el lead nuevo sin primer intento va primero**, luego vencidas, luego las de hoy (regla del 25/08).
3. **Plus Jakarta Sans sí, verde no.** Se carga la tipografía en todo el CRM; los estados «Bien» van en navy sobre fondo tenue (el azul `#2563eb` se reserva a enlaces, selección y foco, como manda el mockup 6 «un significado, un color»).
4. **«Contestó · no le interesa» descarta el lead en la misma operación**, con submotivo obligatorio y deshacer de 24 h (ese deshacer NO existe hoy para el analista: se construye, ver Fase 2).
5. **«Pide otro producto» también descarta**, con motivo «pide crédito / otro producto» y submotivo agregable. Ambos descartes (4 y 5) caen en el **Centro de rescate** ya existente (`crm.rescate_descartes_mes`, `20260820181756:87-126`), donde el supervisor o gerencia pueden reabrirlos (`crm.reabrir_lead_fn`, `20260906150000:87-180`). Verificado: esa carpeta lee los episodios descartados del equipo y excluye a propósito `datos_invalidos`.
6. **«Número errado» / «No es la persona»: el analista decide.** Si el lead tiene segundo número, el panel propone la tarea «llamar al segundo número» hoy; si no, el panel ofrece «Descartar por datos inválidos» (con deshacer 24 h) o «Mantener con reintento a 7 días» y el analista elige. Estas llamadas cuentan como intento pero NO entran en la tasa de contacto.
7. **Tasa de contacto: el % se muestra siempre con el conteo al lado** («100 % · 2 llamadas», como el mockup 3). Con menos de 5 llamadas no hay chip Bien/Atención/Bajo ni alerta, y esas filas van al final del orden por tasa.

8. **Llamadas por rango de horas del analista** (pedido el 19/09 tras la medición): supervisor y gerencia ven cuántas llamadas hace cada analista por franja horaria del día (barras por hora, 08–20 Lima). Sale del mismo núcleo; se muestra en la tabla de equipo (fila expandible) y en el registro.

**Decisiones previas del ZIP que se respetan:** lista de 7 resultados · cuota diaria FUERA de v1 · el supervisor SÍ ve el texto de su equipo · la alerta «SLA de primer CONTACTO» está eliminada (§11); la de «primer INTENTO» (§4) NO fue eliminada y se conserva · playbook UI-UX es norma.

## Lo que el código real cambia respecto al PLAN.md y los mockups (verificado)

| PLAN.md / mockup dice | Realidad verificada | Consecuencia |
|---|---|---|
| §12: metadata resuelve el resultado «sin tocar el CHECK» | Cierto para el CHECK; pero `crm.registrar_actividad_v2` inserta solo `(id, lead_id, tipo, detalle, creado_por)` (`20260907025220:147-149`) y su firma está SELLADA por `private.assert_sla_comandos` (`:710-735`) | Puerta nueva `crm.registrar_llamada_v3` que COMPONE sobre las selladas, patrón `cerrar_reunion_v3` (`20260918213000:198-297`) |
| §7.1 «obligatorio al cerrar la llamada» | Hay DOS caminos: `registrar_actividad_v2` (id de la actividad = `p_operacion_id`) y `cerrar_tarea_v2` (el id vuelve en la clave `actividad_id` de la respuesta, `:357-359`); `cerrar_tarea_v2` YA exige resultado (contestó/no contestó, `:305-308`) | La v3 cubre los dos caminos; en el segundo toma `actividad_id` de la respuesta y aborta si viene nulo |
| «Deshacer» del mockup 4/6 | El log es inmutable, pero el mockup pide deshacer los EFECTOS (tarea creada, descarte), no el log. El único deshacer de descarte hoy (`crm.deshacer_descarte`) es de coordinación y solo para leads SIN dueño (`20260723120000:531-541`, `20260807203740:383-392`); el analista solo tiene `reabrir_lead_fn`, sin ventana y que devuelve el lead a `nuevo` | Se construye `crm.deshacer_resultado_llamada` (24 h, autor, restaura la etapa previa) y el toast lleva «Deshacer» sobre la tarea creada y el descarte. La actividad queda en el log |
| §4 «reusar `alertas_reconocimientos`, no armar otro mecanismo» | `alerta_id` con CHECK regex cerrado a 4 tipos en singular (`20260823204930:43-45`); el uuid del id debe ser el del ACTOR (`:105-113`); gerencia no puede insertar; el 07/09 se decidió que los avisos SLA nuevos NO se reconocen | v1: reconocer solo `tarea_vencida` y `por_repartir` como UN grupo por supervisor (`grupo:<tipo>:<supervisorId>`, `lib/alertas.ts:434,506`); los demás avisos «se retiran solos al resolverse» y lo dicen en pantalla (el mockup 3 pone Reconocer en dos alertas que aquí no lo llevan) |
| §5 «conversiones de hoy» y «rango normal 42–52 %» | No hay núcleo diario por fecha de conversión (cambiando ahora); el rango es ilustrativo (§13) | Fuera de v1, dicho en pantalla. El pulso compara con ayer y con el promedio de los últimos 7 días con actividad |
| Mockup 1: fila «Sin equipo · coordinador» | El ámbito de gerencia es TODO `crm.equipo` (`20260803164348`); el mockup cuadra 35+46+2 = 83 | Se conserva como fila de CUADRE «Fuera de equipos comerciales» (llamadas y contestadas, sin tasa ni «Ver equipo»). Coordinador y directorio no ENTRAN al módulo como usuarios |
| Mockup 5: panel lateral de 520 px | El drawer del lead ya es un `Sheet` (`lead-drawer.tsx:167`); no hay precedente ni test de Sheet dentro de Sheet; el probado es `Dialog` dentro de `Sheet` (`ui/dialog.test.tsx:26`) | El formulario del mockup 5 se monta en `Dialog` (mismo contenido, misma jerarquía) |
| Mockup 5: «En llamada · 00:42», «4.º intento» | No hay duración (§2.4); el ordinal sí es derivable | Sin cronómetro; «N.º intento» lo devuelve el servidor |
| Mockup 2: «Marcar para revisión», «Crear tarea», «Avisar al supervisor» | Sin dónde persistir la marca; sin canal de aviso | «Marcar para revisión» = nota correctiva (`nota` con `metadata.evento='revision'`). Los otros dos, fuera de v1 |
| Mockup 1: nav «Métricas» | No existe ese módulo | Sin ese ítem en v1 |
| Mockups 4/5: «agendó reunión», «Reuniones» | Decisión del 27/08: en la interfaz se dice **cita** (vault «Terminologia de citas en el CRM»); las claves técnicas (`reunion`) no cambian | Etiquetas «Contestó · agendó cita», «Citas agendadas» desde la Fase 2 |
| §2.6: `resultado_reunion` tiene 4 valores | Tiene 6 (`20260805180000:83-90`) | Catálogo nuevo separado (desenlace de llamada ≠ de cita) |
| §3 Bloque 1: «vencidas arriba de todo» | Contradice la regla del 25/08 protegida por 35 pruebas (`prioridades-vendedor.ts:32-84`) | Decisión #2 de Miguel: lead nuevo primero |
| Riesgo «dos colas»: «misma RPC, mismo orden» (borrador anterior) | FALSO: Hoy usa `cola_accion_fn` v1 + un TOP-3 plano por severidad (`seleccionarPrioridadesVendedor`, `prioridades-vendedor.ts:41-70`); Gestión Diaria usará `cola_accion_v2_fn` agrupada por bucket | Son DOS presentaciones distintas y se declara: Hoy = «las 3 cosas de ahora», Gestión Diaria = la cola completa. Test compartido: el primer ítem de Hoy (speed-to-lead) es también el primero de Gestión Diaria |

## Definiciones fijadas por escrito (una sola vez, en el servidor)

- **Llamada** = actividad con `tipo in ('llamada_realizada','llamada_no_contestada')`. **Contacto** = `llamada_realizada`. **Llamada útil** = llamada cuyo resultado no es `numero_errado` ni `no_es_la_persona`. **Tasa de contacto** = contactos / llamadas útiles. En pantalla toda cifra se rotula «Llamadas», nunca «gestiones» ni «toques», con pie fijo: «Llamadas = marcadas + no contestadas. No incluye WhatsApp ni citas (eso son «toques», en Agenda)». Los 5 toques de `metricas_agenda_fn` (`20260727032429:359-366`) son otro concepto y no se mezclan.
- **Tarea vencida** = `estado='pendiente' and activo and vence_en < now()` (comentario canónico de la tabla, `20260718180001:87-89`). El «735» se remide con esta definición.
- **Jerarquía** = `crm.equipo.supervisor_id` de HOY vía `private.vendedor_ids_visibles`. **Roster activo** = `crm.equipo.activo = true` con `private.rol_crm` = vendedor (nunca `vendedor_ids_visibles`, que incluye inactivos a propósito).
- **Parkeado del equipo** = `l.activo and l.vendedor_id is null and l.asignado_supervisor_id in (visibles)` (NO `leads_por_repartir`, que es la cola global del coordinador y daría siempre cero: `20260903250000:50-79`).
- **Resultado tipificado** (claves): `no_contesto` · `volver_a_llamar` · `agendo_reunion` · `no_interesado` · `numero_errado` · `no_es_la_persona` · `pide_otro_producto`. Viaja en `metadata` como `{evento:'resultado_llamada', resultado, submotivo?, intento_n, etapa_anterior}` (vocabulario ya usado por otros writers: `evento`, `etapa_anterior`, `motivo`).
  - Tipo de actividad: `no_contesto`, `numero_errado`, `no_es_la_persona` → `llamada_no_contestada` (no avanzan etapa ni sellan contacto; sí sellan primera gestión: `trg_zy`, `20260807203757:1038-1046`). Los otros cuatro → `llamada_realizada`.
  - Efectos: `no_contesto` → siguiente intento propuesto por la cadencia existente (`sugerirSiguiente()` de `lib/motor-siguiente.ts`, editable; al 6.º intento ofrece «marcar perdido: no responde») · `volver_a_llamar` → tarea `llamada` obligatoria con fecha · `agendo_reunion` → tarea `reunion` con fecha/modalidad (`campos-reunion.tsx`) · `no_interesado` → submotivo + descarte `sin_interes` (+ casilla opcional «Pidió que no lo vuelvan a llamar» → puerta existente `crm.marcar_no_contactar`, Ley 29571) · `pide_otro_producto` → submotivo + descarte `pide_credito` · `numero_errado` / `no_es_la_persona` → decisión #6.
  - Submotivos APROBADOS por Miguel (19/09): no_interesado → `sin_fondos_ahora` (motivo `sin_fondos`), `ya_invirtio_con_otro` (motivo `competencia`), `desconfianza`, `no_le_interesa_invertir`, `otro` (motivo `sin_interes`); pide_otro_producto → `prestamo`, `credito`, `otro` (motivo `pide_credito`). El submotivo elige el motivo real del catálogo existente y no lo duplica.
- **Ventana legal** de toda fecha propuesta: L–S 07:00–20:00 Lima (`slotHabil()`, `lib/motor-siguiente.ts:45-66`).
- **Umbrales** (un solo sitio: `private.gestion_diaria_umbrales()`): chip Bien ≥ 45 %, Atención 25–44 %, Bajo < 25 % (los mockups 2 y 3 son incoherentes entre sí: 33 % «Bajo» y 25 % «Atención»; APROBADOS por Miguel el 19/09 tras contrastarlos con 14 días reales: 8 Bien / 6 Atención / 2 Bajo); mínimo 5 llamadas útiles para chip y alerta; «sin llamadas hoy» desde las 11:00 Lima; «parado» = última llamada hace > 2 h entre 08:00 y 19:00; «tasa muy baja» = tasa < tasa del equipo − 15 pp.
- **Frescura**: sin realtime; refresco cada 60 s y «Corte HH:MM» visible.

## Arquitectura (4 capas)

```
1. Tablas   crm.actividades sin columnas nuevas + CHECK de FORMA sobre metadata (NOT VALID + VALIDATE)
            + índice actividades_llamadas_autor_dia_idx (creado_por, creado_en desc) where tipo in (llamadas)
2. Núcleo   private.gestion_diaria_llamadas(p_ini, p_fin, p_vendedor_ids)  ← UNA definición de llamada/contacto/tasa (registrada como auxiliar auditado del censo)
            private.llamada_registrar(...)  ← efectos del resultado, atómico, con pre-chequeo de replay
            private.gestion_diaria_umbrales()
3. Puerta   crm.registro_actividad_fn(p_desde, p_hasta, p_supervisor_id, p_analista_id, p_tipo, p_etapa, p_limite, p_cursor)   [F1]
            crm.registrar_llamada_v3(...) · crm.deshacer_resultado_llamada(p_actividad_id)                                     [F2]
            crm.gestion_diaria_analista_fn(p_dia)                                                                                [F3]
            crm.gestion_diaria_equipo_fn(p_dia, p_supervisor_id)                                                                 [F4]
            crm.gestion_diaria_pulso_fn(p_dia)                                                                                   [F5]
4. Pantalla vista 'gestion-diaria' → screens/gestion-diaria.tsx (switch por rol como screens/hoy.tsx:13-27)
            components/gestion-diaria/: registro-actividad, registrar-resultado, tabla-equipo-diaria, alertas-del-dia
```

**Reglas que aplican a todas las fases.** Puertas `SECURITY DEFINER` + `STABLE` (lecturas) + `search_path=''` + `revoke all … from public, anon, authenticated, service_role` + `grant execute … to authenticated`; preflight con md5 de lo vivo (incluido el md5 de `crm.cola_accion_v2_fn`, que NO está sellada por ningún gate y se acuerda no tocar); postflight que llama SOLO a `assert_sla_*` (verdes) más el propio `private.assert_gestion_diaria()`. **Censo analítico** (`assert_analitica_leads_citas`, en rojo, tope 30 que solo baja y ya desbordado: `20260912181045:152-163`): las puertas nuevas NO usan `count(` ni `sum(1)` (delegan al núcleo) y el núcleo se registra en `private.auxiliares_analitica_lc_auditados()` (definición + owner + ACL) para no subir `v_n`; el postflight exige que el conjunto rojo quede idéntico (patrón `20260919170500:73-75, 271-272`, adaptado para no exigir «mismo número» si el censo cambia por lo declarado). `gen:types` está roto → cada RPC nueva se añade A MANO a `app/src/lib/database.types.ts`. Clave nueva en RESPUESTA → front tolerante con `v.optional`; RPC nueva → SQL primero, front después. Terminología visible: «Analista», «cita». Cobertura: medir `npm run test:coverage` antes de cada PR de pantalla (umbrales 26/23/30/29, `vitest.config.ts:43-48`) y ajustar en la misma entrega si hace falta.

---

## Fase 0 — Cimientos · LEVEL 1–2 · 2 PR front, 0 SQL

**Qué obtiene Miguel:** el CRM con la letra correcta, umbrales y submotivos confirmados con datos reales, y las decisiones escritas en el vault.

1. **Medición en producción (solo lectura, `DO` que termina en `raise`):** modo de `crm.sla_operacion_control` y cuántas filas devuelve hoy `cola_accion_v2_fn` con bucket `primera_atencion` (de eso depende el orden prometido); 735 vencidas con la definición canónica; tasa real por analista/equipo de 14 días aplicada a los umbrales propuestos (antes/después sobre las filas del mockup 3); distribución horaria. Miguel confirma umbrales y submotivos.
2. **Tipografía:** `npm i @fontsource/plus-jakarta-sans`, importar 400–800 en `app/src/index.css:2-5`; `--font-sans` ya la declara (línea 101). PR + release.
3. **Primitivas UI:** `components/ui/tabs.tsx` (APG, de `ranking-vendedores.tsx:801-818`), `components/ui/radio-group.tsx` (fieldset/legend/label de `rescate-descartados.tsx:192-208`, 44 px, borde 2 px), `lib/exportar-csv.ts` (de `citas/avance-mensual.tsx:85-99`, BOM + anti-inyección). Con tests. No se refactorizan las copias viejas.
4. **Documentación:** copiar `docs/gestion-diaria/` del ZIP a `CRM-Avance-Corp/docs/gestion-diaria/`; nota del vault «Gestion Diaria - modulo nuevo y absorcion de Seguimiento 2026-09-19.md» que declara qué deroga (Seguimiento del 07/09) y qué NO (orden del 25/08, «Hoy»), con wikilinks a Seguimiento, Hoy del vendedor, Núcleo SLA, Plan de avisos por acción y rol, Acceso y roles, Fundamentos UX, Terminologia de citas, capa semántica, Agenda comercial (plan v2). Bullet en `Inicio.md`.

Verificación: `npm run check`. Codex: no.

---

## Fase 1 — Alta del módulo + Registro crudo compartido · LEVEL 3 · 1 migración + 1 PR

**Qué obtiene Miguel:** el módulo existe en el menú y el supervisor puede leer HOY el texto íntegro de las llamadas de su equipo (4 889 históricas), con pestañas, paginación y exportación para gerencia. Es solo lectura, no toca ninguna puerta sellada y adelanta la conversación de calidad con los analistas sin esperar al resultado tipificado.

**Servidor (`…_crm_gestion_diaria_registro.sql`, skill `nueva-migracion`):** `crm.registro_actividad_fn(p_desde date, p_hasta date, p_supervisor_id uuid default null, p_analista_id uuid default null, p_tipo text default null, p_etapa text default null, p_limite int default 50, p_cursor jsonb default null)` con rango desde el primer día (Gestión Diaria lo llama con hoy; Métricas lo reutilizará). Devuelve `id, creado_en, lead_id, lead_nombre, etapa_actual, etapa_en_ese_momento` (derivada en SQL de los `cambio_etapa` previos del lead vía `metadata->>'etapa_nueva'`, que existe desde `20260709000001:342-345`; nunca parseando prosa), `tipo, detalle, metadata, creado_por, autor_nombre`, keyset como `cola_accion_v2_fn`. Ámbito por AUTOR cruzado con `vendedor_ids_visibles` (la policy `actividades_select` filtra por dueño del lead, por eso es definer); vendedor solo lo suyo; gerencia global. Sin `count(`. Índice nuevo. Coordinar con la sesión paralela de «historial por lead» (`actividades_de_lead_fn`, `20260919185718`): son entradas distintas (por lead vs por ámbito) con la misma forma de fila; pedirles que añadan `metadata` a la suya. `assert_gestion_diaria` inicial. `test-rls.mjs`: copiar `testFacturacionDiaria` (línea 7262): supervisor A no ve equipo B; vendedor solo autor propio; gerencia global. `auditor-rls`. Ensayo en banco (contenedor local, plantilla `supabase/scripts/cartera-procedencia/`). Línea base de `test:rls` antes/después.

**Front:** alta de la vista `gestion-diaria` en TODOS los registros: `lib/router.ts` `VISTAS` (insertar DESPUÉS de las tres primeras entradas: `router.test.ts:126` fija `['hoy','alertas','seguimiento']`) y `VISTAS_LEADS` (línea 87); `App.tsx` lazy + `PANTALLA_POR_VISTA`; `lib/vistas.ts` DOS cosas: entrada `'gestion-diaria': 'verLeads'` (línea ~24) y el early-return espejo de la línea 100 (`rol === 'gerencia' || 'supervisor' || 'vendedor'`), porque `directorio` también tiene `verLeads`; `vistas.test.ts:12-14`; `sidebar.tsx` `NAV_META` + `GRUPO_GERENCIA` (grupo Operación) y `sidebar.test.tsx:117-130` (lista ordenada); `topbar.tsx` `TITULOS`; `ayuda-vendedor-panel.tsx` `ETIQUETA_VISTA` (línea 20) y el ternario `contextoAyuda` (líneas 65-67) → `'hoy'` (el servidor tiene lista blanca cerrada, `20260818034822:1142-1149`). Regla #10: cada rol debe poder abrirla con el gate de leads cerrado igual que Seguimiento. `screens/gestion-diaria.tsx` (switch por rol) con, en esta fase, la sección «Registro» para los tres roles. `components/gestion-diaria/registro-actividad.tsx`: pestañas Llamadas/WhatsApp/Notas/Todo (`ui/tabs.tsx`), filtros analista/tipo/etapa (+ equipo y buscador de analista para gerencia), «Ver más» por cursor, «Exportar CSV» solo gerencia (incluye `detalle`: requisito «ver absolutamente todo»), acción «Nota de revisión» (vía `registrar_actividad_v2`, tipo `nota`). `data/gestion-diaria-api.ts` + `data/use-registro-actividad.ts` (real/demo/fail-closed), clave bajo `crmQueryKeys`, `database.types.ts` a mano. Datos demo en `lib/demo.ts`. Tests con fixture y con estado real (31 % sin detalle); `revisor-a11y`; e2e demo por rol. `npm run check:all` (navegación nueva).

**Despliegue:** SQL primero (Miguel `!`), front después (`/release-crm`). Codex: 1 (diff; visibilidad entre equipos).

---

## Fase 2 — El resultado tipificado · LEVEL 3 · 1 migración + 1 PR

**Qué obtiene Miguel:** cada llamada del CRM, en cualquier pantalla, se cierra con uno de los 7 resultados; «volver a llamar» crea la tarea sola; «no le interesa» y «pide otro producto» descartan con motivo real hacia el Centro de rescate; todo con «Deshacer» de 24 h.

**Servidor (`…_crm_gestion_diaria_resultado_llamada.sql`):**
- CHECK de FORMA sobre `crm.actividades.metadata` (`metadata->>'resultado' is null or … in (catálogo)`), `NOT VALID` + `VALIDATE` (patrón `actividades_creado_en_finito`, `20260818045032:248-252`). De forma, no de presencia: `registrar_actividad_v2` y `cerrar_tarea_v2` siguen insertando sin metadata. Gobierna también el INSERT directo de `insertarActividad` (`crm-api.ts:2163-2166`).
- Núcleo `private.llamada_registrar(p_actor, p_operacion_id, p_lead_id, p_resultado, p_submotivo, p_detalle, p_siguiente, p_tarea_id, p_descartar boolean, p_no_insista boolean) returns jsonb`. Orden fijo: (1) **pre-chequeo de replay** copiado de `cerrar_reunion_v3` (`20260918213000:251-266`): si `crm.sla_operacion_recibos` ya tiene respuesta para `(actor, operacion_id)`, devuelve la guardada sin tocar nada (el recibo no guarda resultado/submotivo, así que sin esto un reenvío pisaría metadata y descartaría dos veces); (2) valida catálogo y coherencia (fecha futura en ventana legal, submotivo obligatorio); (3) delega en la puerta sellada: `crm.registrar_actividad_v2` (actividad con `id = p_operacion_id`) o, si `p_tarea_id`, `crm.cerrar_tarea_v2` con `p_resultado_tipo` (el id vuelve en `respuesta->>'actividad_id'`; abortar si nulo); (4) `update crm.actividades set metadata = …` sobre ese id (verificado: ningún trigger lo bloquea; `trg_audit_actividades_cambio_baja` solo audita, `20260831055000:3369-3371`; el único veto es gerencia, `trg_00_gerencia_solo_lectura`, que tampoco podrá registrar llamadas por aquí); (5) si `p_descartar`: `update crm.leads set etapa='descartado', motivo_descarte=…` (columnas exactas que hoy toca el store en `store.tsx:2525`; `descartado_en/por` los sella `private.trg_leads_zz_sello_descarte`; la cascada del ledger asienta el episodio que lee el Centro de rescate) DESPUÉS de la actividad (el comando SLA rechaza leads cerrados, `20260907025220:143-145`); (6) si `p_no_insista`: `crm.marcar_no_contactar`. Sobre de respuesta `{ok:true, version:2, operacion_id, comando:'registrar_llamada', lead_id, actividad_id, siguiente_id, descartado}` (lo exige `ejecutarComandoSla`, `data/sla-operacion-comandos.ts:160`).
- Puerta `crm.registrar_llamada_v3(p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_submotivo text default null, p_detalle text default null, p_siguiente jsonb default null, p_tarea_id uuid default null, p_descartar boolean default false, p_no_insista boolean default false) returns jsonb`.
- Puerta `crm.deshacer_resultado_llamada(p_actividad_id uuid)`: solo el autor, ≤ 24 h, revalida ámbito; cancela la tarea creada (`siguiente_id`, por la puerta de cierre existente con estado `cancelada`), y si hubo descarte lo revierte componiendo sobre `crm.reabrir_lead_fn` (que verifica ledger, identidad y «No insistir») y restaurando `etapa_anterior` guardada en metadata; deja `nota` con `metadata.evento='resultado_deshecho'`. La actividad de la llamada permanece.
- `assert_gestion_diaria` ampliado; `test-rls.mjs`: permitido/denegado por rol, lead ajeno, lead cerrado, resultado fuera de catálogo, fecha pasada, sin submotivo, replay idéntico, replay con otro resultado, deshacer ajeno, deshacer a las 25 h. `auditor-rls`. Ensayo en banco. **Revisión Codex de arquitectura ANTES de implementar** (consulta 1) y de diff después (consulta 2).

**Front (PR `gestion-diaria/f2-resultado-llamada`):**
- `components/gestion-diaria/registrar-resultado.tsx`: el formulario del mockup 5 dentro de `Dialog` (ver tabla): `RadioGroup` de 7 opciones con atajos 1–4, paso 2 condicional (fecha con atajos legales `slotHabil()`/`camposDeSugerencia`/`isoDeCampos`; cita con `campos-reunion.tsx`; submotivo; para número errado la elección de la decisión #6; casilla «Pidió que no lo vuelvan a llamar»), nota opcional, `BotonGuardar`. Con el lead en `contactado`/`propuesta_enviada` el descarte muestra «Saldrá de tu cartera; puedes deshacerlo durante 24 h». El botón «Omitir» (`contacto.tsx:526-529`) NO se retira (en móvil no hay Esc y `ui/dialog.tsx` no pinta X): se renombra «Cerrar sin registrar» y el toast dice qué NO quedó registrado.
- `contacto.tsx`: la rama `OPCIONES.tel` (`:274-283`) de `DialogResultado` (`:341-536`) pasa a montar el panel nuevo; la rama `wa` (WhatsApp) se conserva tal cual. Se aplica en todas las superficies (drawer, cola, agenda, Hoy) → una sola definición de «resultado de llamada». `tareaQueCierra` (`lib/contacto-tarea.ts:45-57`) sigue decidiendo `p_tarea_id`.
- Toast con `avisoDe()` (`contacto.tsx:292-316`) enumerando lo ocurrido + acción «Deshacer» 15 s (patrón `repartir.tsx:255-268`) → `deshacer_resultado_llamada`.
- Capa de datos: `registrar_llamada_v3` y `deshacer_resultado_llamada` en `gestion-diaria-api.ts`; `data/sla-operacion-comandos.ts`: union `Comando`, set `COMANDOS` y **`clave()` (líneas 28-30) con cubo nuevo `'llamada'` y sujeto = `lead_id`** (si no, colisiona con `cerrar_tarea_v2` y bloquea el guardado con `SLA_CONFIRMACION_PENDIENTE`); `NOMBRES` de `guardados-sla-pendientes.tsx`; `database.types.ts` a mano; `ActividadRowSchema` (`crm-api.ts:1498-1505`, ya es `v.object`, tolerante) y `Actividad` (`tipos.ts:342-356`) ganan `metadata` opcional; `store.registrarLlamada(...)` con espejo optimista coherente con `avancePorContacto` (`avance-automatico.ts:56-59`); `lib/resultado-llamada.ts` (catálogo, etiquetas «cita», mapeo resultado→tipo, test que fija el espejo del servidor).
- Los chips de resultado se pintan donde la fila trae `metadata` (registro de la Fase 1; el timeline del drawer cuando `actividades_de_lead_fn` lo devuelva).
- Nota de corte en el pulso (Fase 5): «desde el DD/MM las llamadas llevan resultado».
- Tests: catálogo, panel (estado real: 100 % del histórico sin resultado), `contacto.test`, e2e demo «llamar → resultado → tarea creada → deshacer». `npm run check:all`.

**Despliegue:** SQL primero, front después. Codex: 2.

---

## Fase 3 — Analista «Mi día» · LEVEL 2–3 · 1 migración + 1 PR

**Qué obtiene Miguel:** el analista ve a quién llamar ahora, su marcador del día, sus compromisos y sus descartes de hoy (con deshacer), y salta al siguiente al guardar.

**Servidor (`…_crm_gestion_diaria_analista.sql`):** núcleo `private.gestion_diaria_llamadas(p_ini, p_fin, p_vendedor_ids)` (llamadas, útiles, contestadas, tasa, leads únicos, ratio, primera/última, desglose por resultado, **llamadas por hora Lima**, citas agendadas con la definición de `metricas_agenda_fn:128-135`), registrado como auxiliar auditado del censo. Puerta `crm.gestion_diaria_analista_fn(p_dia date default null)` (gate: molde `metricas_vendedores_fn:793-835`): `marcador`, `compromisos` (tareas pendientes futuras llamada/cita sobre leads en `contactado`/`propuesta_enviada`), `sin_conversacion` (estrena `crm.politica_abandono.dias_abandono` con `greatest(última conversación real, tenencia_desde)`; los intentos no protegen), `telefonos` por lead de la cola (teléfono, segundo número, última observación de número errado), `intentos`, `descartados_hoy` (para el deshacer), `generado_en`. La cola sigue saliendo de `crm.cola_accion_v2_fn` (md5 en el preflight).

**Front:** `screens/gestion-diaria/analista.tsx`. Fuente ÚNICA de la cola: `listarColaSla` (v2, `data/sla-operacion-api.ts:20`); orden por una función pura NUEVA y probada `ordenarColaDiaria()` = `primera_atencion` → `tarea_vencida` → `tarea_hoy` → `sin_conversacion`, agrupada por bucket (no se reutiliza `seleccionarPrioridadesVendedor`, que es un TOP-3 del ítem v1 y sigue gobernando la franja «Ahora» de Hoy); test compartido que comprueba que el primer ítem de Hoy es el primero aquí. Filas con `AccionesContacto` (tel/WhatsApp 44 px) y «Registrar resultado» (panel de la Fase 2; al guardar avanza a la siguiente fila). Marcador con `StatStrip` (sin meta). «Mi seguimiento» (compromisos). «Descartados hoy» con «Deshacer». `<GuardadosSlaPendientes/>` pasa a montarse UNA vez en `App.tsx` y se retira de `sla-operacion.tsx:80` y `:172` en la misma entrega. `SlaOperacionBoundary` para el modo legado. Vacíos con `PanelVacio`. Hook real/demo/fail-closed, 60 s. Tests con estado real, `gate:realidad`, `revisor-a11y`, e2e Analista.

**Despliegue:** SQL primero, front después. Codex: 1.

---

## Fase 4 — Supervisor «Mi equipo hoy» · LEVEL 3 · 1 migración + 1 PR

**Qué obtiene Miguel:** el supervisor ve, ordenado por problema, quién se está cayendo hoy y la tabla de su equipo con el ratio llamadas/lead; desde cada fila abre el registro de la Fase 1.

**Servidor (`…_crm_gestion_diaria_equipo.sql`):** `crm.gestion_diaria_equipo_fn(p_dia date default null, p_supervisor_id uuid default null)` (supervisor: su subárbol; gerencia: cualquier equipo; vendedor: 42501). Devuelve `equipo` (una fila por analista activo del núcleo + `vencidas` canónicas + `citas_hoy` + `primer_intento_vencido` + `llamadas_por_hora` [24 enteros, hora Lima, decisión #8]), `resumen`, y `alertas[]` en servidor con `private.gestion_diaria_umbrales()`: `sin_llamadas_hoy`, `tasa_baja`, `parado_2h`, `primer_intento_vencido` (asignaciones con `primera_gestion_en is null` y `primera_gestion_limite_en < now()`, leídas del núcleo SLA por definer), `tarea_vencida` y `por_repartir` (estos dos como UN grupo por supervisor, con `miembros[]`, `tipo` en singular exacto). Postflight que ensaya identidad por identidad (`set_config('request.jwt.claims')`, patrón `20260916205617:240-379`). `auditor-rls`, `test-rls`.

**Front:** `components/gestion-diaria/tabla-equipo-diaria.tsx` (UNA tabla para supervisor y Nivel 3 de gerencia; `jscpd` 0,8 % vigila) sobre `common/tabla.tsx`, orden por columna con `aria-sort` (pocas llamadas al final), chips con texto («55 % · Bien», «100 % · 2 llamadas»), fila expandible con las barras «llamadas por hora» del analista (decisión #8), patrón responsive de `ranking-vendedores.tsx`, buscador de analista y chip «Con problema hoy» (filtros de cliente). `components/gestion-diaria/alertas-del-dia.tsx`: 1 rojo por decisión, máx. 2 ámbar; Reconocer/Posponer SOLO en `tarea_vencida` y `por_repartir` mediante un adaptador `alertaDiariaAAlertaCRM()` (id `grupo:<tipo>:<supervisorId>`, campos de `AlertaCRM`, `lib/alertas.ts:39-60`) + `reconocerAlertaSupervisor` + `aplicarReconocimientos`; los demás llevan «Se retira sola al resolverse». `screens/gestion-diaria/supervisor.tsx` con tira KPI, tabla y drawer del registro. Tests + estado real + e2e Supervisor.

**Despliegue:** SQL primero, front después. Codex: 1.

---

### F4 · Los CORTES DEL DÍA y sus perillas (decisiones de Miguel, 20/09/2026)

Sustituyen a la alerta «sin llamadas a las 11:00» del plan original, que nunca se probó contra
datos reales. Miguel fijó dos cortes y una regla: **los números los pone GERENCIA, no el código.**

#### Los dos cortes

| Corte | Hora (Lima) | Qué exige | Si no se cumple |
|---|---|---|---|
| **Primero** | **11:30** | un mínimo de llamadas, configurable | avisa al supervisor con un aviso que **exige atención** |
| **Segundo** | **16:00** | **150 % MÁS** que lo que tenía en el primer corte | avisa al supervisor |

**«150 % más» es la lectura literal, confirmada:** con 20 llamadas a las 11:30, el segundo corte
exige **50** (20 + el 150 % de 20 = ×2,5). Para que nadie vuelva a dudar, **la pantalla de
gerencia muestra la cuenta en vivo** mientras se escribe el número: «con 20 llamadas al primer
corte, exige 50 al segundo». La perilla se guarda como el porcentaje, no como el multiplicador.

#### Los valores de arranque, medidos contra producción (20/09/2026)

Se midieron **90 días reales: 22 analistas, 399 días de trabajo** (lectura de solo lectura sobre
`crm.actividades`, llamadas realizadas + no contestadas, hora de Lima, sin domingos).

**Lo que hace el equipo HOY:**

| | A las 11:30 | A las 16:00 | Todo el día |
|---|---|---|---|
| La mitad de los días | **2** | **7** | **10** |
| 1 de cada 4 (los buenos) | 5 | 13 | 17 |
| 1 de cada 10 (los muy buenos) | 10 | 22 | 28 |
| Récord | — | 56 | **70** |

**Por qué los números de arranque son los que son.** Se simularon contra esos 399 días:

| Mínimo a las 11:30 | Días que fallarían |
|---|---|
| 8 | **82 %** |
| 5 | 71 % |
| **3** | **54 %** |
| 2 | ~35 % |

Un mínimo de 8 —la primera intuición— haría saltar la alerta **8 de cada 10 días**. Eso no es una
alerta: es ruido, y el supervisor la apaga mentalmente en una semana. **Miguel fijó 3** el
20/09/2026: señala a la mitad peor, que es algo real, sin quemar la alerta.

El **techo casi no cambia nada**: con 25 recortaría el 8 % de los días, con 30 el 6 %. Se pone en
**30** porque sin él la cuenta llegaría a pedir **73** llamadas en la tarde de una mañana
excepcional, que es más que el récord absoluto del equipo en un día entero.

**Valores con los que nace la versión 2 (los que gerencia publica el primer día):**

| Perilla | Arranque | Por qué |
|---|---|---|
| Hora del primer corte | **11:30** | decisión de Miguel |
| Mínimo de llamadas al primer corte | **3** | fallaría el 54 % de los días; con 8 sería el 82 % |
| Hora del segundo corte | **16:00** | decisión de Miguel |
| Crecimiento exigido | **150 %** | decisión de Miguel: con 20 exige 50 |
| Piso absoluto del segundo corte | **8** | decisión de Miguel: caza al que llegó a mediodía con cero |
| Techo absoluto del segundo corte | **30** | sin él la cuenta pediría hasta 73, más que el récord del equipo |
| Mínimo del sábado (medio día) | **sin fijar** | Miguel lo pone al publicar |
| Tasa muy baja | **vacía** | no hay dato; la produce el reporte de F5 |

**Todos son perillas: gerencia los sube cuando el equipo suba.** Ese es el punto de que sean
configurables y no constantes en el código.

#### Dos cosas que la medición dejó a la vista, y que no son de F4

- **Diez llamadas al día de media es poco** para un equipo comercial. Puede que llamen más de lo
  que registran — y entonces el problema es de REGISTRO, no de actividad. Lo aclara el reporte de
  hábitos de F5.
- **399 días con llamadas entre 22 analistas en 90 días** son unos 18 días por persona. O no todos
  llaman a diario, o no todos registran. Mismo reporte.

#### Qué configura gerencia, y qué NO

Configurables desde la pantalla de gerencia, con valores de arranque:

- **Hora del primer corte** — 11:30.
- **Llamadas mínimas al primer corte** — **3** de arranque, medido (ver arriba).
- **Hora del segundo corte** — 16:00.
- **Crecimiento exigido en el segundo corte** — 150 %, con **piso 8** y **techo 30**.
- **Tasa muy baja** — **nace VACÍA y esa alerta NO salta hasta que se ponga.** Decisión explícita
  de Miguel: «todavía no hay esa data». El reporte de F5 (abajo) es el que la va a producir.

NO configurable, queda como está: **«parado» = más de 2 horas sin llamar** entre 09:00 y 18:00.

#### La semana laboral (decisión de Miguel, 20/09/2026)

| Día | Jornada | Cortes |
|---|---|---|
| Lunes a viernes | 09:00 – 18:00 | **dos**: 11:30 y 16:00 |
| **Sábado** | **09:00 – 13:00** | **UNO: 11:30** |
| **Domingo** | no se trabaja | **ninguno**; no salta ninguna alerta |

**Por qué el sábado lleva un solo corte:** la jornada acaba a las 13:00, así que un corte a las
16:00 no existe. El de las 11:30 sí encaja — cae a dos horas y media de empezar, exactamente igual
que en un día entre semana. El sábado tiene su **propio mínimo de llamadas**, también configurable:
medio día no puede exigir lo mismo que uno entero.

El domingo la pantalla no calcula cortes ni pinta alertas de este tipo. Si un analista trabaja un
domingo, sus llamadas se registran igual: lo que no se hace es juzgarlas contra un corte.

**Ojo con la ventana de «parado»:** hoy es 09:00–18:00 todos los días. El sábado tiene que cerrarse
a las 13:00, o marcará como «parado» a todo el equipo cada sábado por la tarde.

#### El aviso: un POP-UP (decisión de Miguel, 20/09/2026)

Miguel lo pidió así de claro: *«un aviso tipo pop-up para que se les haga complicado ignorar»*.
Un chip en una lista se ignora; un diálogo, no.

Reglas para que sea eficaz y no odioso — todas obligatorias:

- **Una vez por corte y por día.** Salta al llegar el corte, o la primera vez que el supervisor
  abre la pantalla después de esa hora. Nunca dos veces por el mismo corte.
- **Se reconoce, y el reconocimiento se guarda EN EL SERVIDOR.** Si viviera en el navegador,
  volvería a saltar al cambiar de equipo o de máquina, y eso es lo que mata una alerta.
- **Dice quién y cuánto**, no «hay incumplimientos»: la lista de analistas con su cifra y lo que
  se esperaba. Desde ahí se entra a su día.
- **Nunca interrumpe algo a medias:** si hay otro diálogo abierto o el supervisor está escribiendo,
  espera. Un pop-up que se come una tecla se gana el odio el primer día.
- **No salta en domingo**, ni por un corte que no aplica a ese día.
- **Se puede posponer** (a una hora), y quien lo pospone queda registrado: si se pospone siempre,
  el número está mal puesto y eso hay que poder verlo.

Va sobre el `Dialog` que ya existe en el CRM (Radix, con trampa de foco, `Escape` por capas y
retorno de foco), no sobre uno nuevo.

**Lo que la revisión añadió, y que es lo que hace que funcione:** hoy en esta app no existe nada
bloqueante, y Codex desaconseja un modal que no se pueda cerrar. Pero encontró la razón por la que
el pop-up **necesita** el reconocimiento en servidor, y no es un detalle técnico:

> El corte de las 16:00 **no cesa**: es un hecho del pasado. Sin una forma de cerrarlo, el aviso
> sería papel pintado a las 16:05 — y una alerta que no se puede apagar deja de ser una alerta.

El de las 11:30 sí puede apagarse solo, si el analista se pone al día antes del segundo corte.
Así que: **pop-up que exige reconocer, reconocimiento guardado en el servidor, y el aviso de las
11:30 se retira solo si se resuelve.** Además, contador en la campana del topbar, que ya existe.

#### Las dos reglas que Miguel cerró (20/09/2026)

**1 · El corte cuenta TODA llamada, no solo las «útiles».**

Entran `llamada_realizada` y `llamada_no_contestada`; NO se descuenta el número errado ni el «no
es la persona». El corte mide **actividad**: si marcó, marcó. La **calidad ya la mide la tasa de
contacto**, que es otra cosa y tiene su propio umbral.

Y hay una razón práctica: si el corte descontara las llamadas inútiles, un analista con una lista
de números malos aparecería como si no hubiera trabajado — y el problema de esa lista no es suyo.

*(La medición del 20/09 que fijó los valores de arranque se hizo con esta definición: toda llamada.
Si se cambiara a «solo útiles», esos números dejan de valer y hay que volver a medir.)*

**2 · El fallo de las 11:30 SE BORRA si se pone al día antes de las 16:00.**

El primer corte es un empujón, no un expediente. Si a las 11:30 lleva 1 llamada y a las 13:00 ya
lleva 6, el aviso **se retira solo** y no deja rastro en la pantalla del supervisor.

El de las 16:00 **no se borra**: cierra el día. Es lo que justifica que ese sí exija reconocer y
el otro no (ver el apartado del pop-up).

Consecuencia para el pop-up de las 11:30: se comprueba si el fallo **sigue vigente** en el momento
de pintarlo, no si ocurrió. Un supervisor que abre el CRM a las 15:00 no debe ver un aviso de las
11:30 que el analista ya resolvió a mediodía.

#### Quien tiene CERO llamadas entra en el aviso del corte

Parece obvio y es justo lo contrario de lo que salía a la primera: si a quien no ha llamado nada
se le deja solo en la alerta «sin llamadas», **el que peor está recibe el aviso más débil**. Entra
en el grupo del corte, y es «sin llamadas» lo que se calla para no decir dos veces lo mismo.

#### Los feriados: la alerta NO se silencia sola

El CRM no conoce el calendario laboral peruano, y **no se va a inferir**. La tentación era
silenciar el aviso cuando casi nadie del equipo llamó — pero eso apaga la alarma exactamente el día
en que nadie llamó, que es el día que más importa. En su lugar: **el aviso sale siempre**, y cuando
la actividad de todo el equipo está por los suelos lleva una marca de contexto («actividad
excepcionalmente baja en todo el equipo — revisa si hoy es feriado o hubo una incidencia») y se
presenta como UNA alerta de equipo, no como N individuales. Silenciar un día es una decisión
explícita de alguien, nunca una deducción del código.

#### Cómo se guarda, y por qué VERSIONADA y no una perilla que se pisa

Diseñado con Codex el 20/09/2026. Tabla nueva `crm.politica_gestion_diaria`, con el molde
**versionado con vigencia** de `crm.sla_politicas`, **no** el singleton de `crm.politica_abandono`.

**El motivo es uno y es duro:** la puerta de F3 ya admite consultar **días pasados** (hasta un año
atrás). Con una fila que se pisa, el martes pasado se re-juzgaría con la perilla de hoy — y eso
convierte un historial en una ficción. Absorbe además los tres umbrales que hoy están a fuego
(45 / 25 / 5), para que siga habiendo **una sola** fuente.

Reglas que salieron de la revisión y que no son negociables:

- **La versión 1 se siembra con los umbrales de hoy y los cortes APAGADOS.** Los cortes nacen en la
  versión 2, la que Miguel publique. Sembrarlos desde el principio haría parecer que la obligación
  existía antes de inventarla, y juzgaría hacia atrás a gente que no la conocía.
- **La política del día se resuelve al AMANECER de esa jornada**, no con la hora actual. Publicar
  al mediodía no puede cambiar las reglas de un corte que ya ocurrió esa mañana. Y `vigente_desde`
  tiene que ser el inicio de una jornada futura: **las reglas del día se fijan al amanecer y no se
  mueven**.
- **Solo gerencia escribe**, y por una función con `expected_version`: dos personas editando a la
  vez no pueden pisarse. Ninguna escritura directa por la API.
- **El cálculo vive en el núcleo**, no en la puerta ni en la pantalla, componiendo
  `private.gestion_diaria_llamadas` que ya está en producción. Una sola definición de «llamada».

#### El objetivo del segundo corte, con sus bordes

`objetivo = techo( max( base × 2,5 ; mínimo absoluto ) )`, acotado por un **techo**.

- **Se redondea hacia ARRIBA.** «Al menos un 150 % más» de 8 llamadas es 20; pero si el porcentaje
  fuera 30 %, 8 × 1,3 = 10,4 y «al menos» significa **11**, no 10. Con 150 % el error queda oculto
  porque salen enteros — por eso conviene fijarlo ahora.
- **Un piso absoluto**, porque si a las 11:30 lleva **cero**, la cuenta siempre se cumple (0 × 2,5
  = 0) y el que peor está sería el único que aprueba.
- **Un techo absoluto**, porque si la mañana fue excepcional —40 llamadas— exigir 100 por la tarde
  no es una meta, es una trampa.

#### Lo que hay que resolver al construirlo

- **Dónde se guarda.** Siguiendo el patrón que ya usa el CRM para perillas
  (`crm.politica_abandono`, fila `singleton`), no uno nuevo. Con RLS, y escritura solo de
  gerencia. `private.gestion_diaria_umbrales()` hoy está **a fuego** y tendrá que leer de ahí.
- **Quién calcula el corte.** El SERVIDOR, nunca la pantalla: los dos cortes son hora de Lima y el
  navegador del supervisor puede estar en otro huso.
- **El analista que entró a media mañana.** Con permiso, una capacitación o media jornada: el
  corte lo juzga igual. Hay que decidir si eso se corrige (con una marca de jornada) o se acepta y
  el supervisor lo descarta al verlo. Sin resolver.
- **Dónde se guarda el reconocimiento del pop-up.** La tabla de reconocimientos que ya existe tiene
  los tipos cerrados por CHECK: ampliarla exige una migración a propósito, que es lo correcto.
- Todo lo demás está decidido: ver «Las dos reglas que Miguel cerró» justo abajo.
- **Un día pasado se recalcula con el equipo y la jerarquía de HOY**, no con los de entonces. Hay
  que decirlo en pantalla. Si algún día esto se usa para evaluar desempeño, hará falta guardar la
  evaluación del día, que es un contrato distinto y más caro.
- **El riesgo de siempre:** una alerta que salta de más se ignora a la semana, y entonces da igual
  lo bien construida que esté. Por eso los números los pone gerencia y no el código.

---

## Fase 5 — Gerencia «Toda la operación» · LEVEL 3 · 1 migración + 1 PR

**Qué obtiene Miguel:** «¿Hoy es un día normal?» sin un clic; el supervisor con el problema; su equipo (misma tabla); el registro crudo exportable.

**Servidor (`…_crm_gestion_diaria_pulso.sql`):** `crm.gestion_diaria_pulso_fn(p_dia date default null)` (gerencia / `es_lector_global`): Nivel 1 = llamadas, útiles, contestadas, tasa, sin actividad (activos vs roster activo), leads únicos + ratio, citas agendadas, cada uno contra AYER completo y contra el promedio de los últimos 7 días con actividad (una pasada del núcleo sobre 8 días); Nivel 2 = fila por supervisor activo (organigrama de hoy): tasa, llamadas, contestadas, sin actividad, dispersión mejor→peor (analistas con ≥ 5 llamadas útiles), vencidas, **primera gestión fuera de plazo**; fila de cuadre «Fuera de equipos comerciales»; `vencidas_global` canónico. Sin conversiones ni «rango normal» (dicho en pantalla). Niveles 3 y 4 reutilizan las puertas de las fases 1 y 4.

**Front:** `screens/gestion-diaria/gerencia.tsx` con selector de DÍA único (por defecto hoy Lima; `validarPeriodoGerencia`), pulso con `StatStrip`/`KpiCard` (número que responde la pregunta en 32/800), tabla por equipo peor primero → «Ver equipo» → `TablaEquipoDiaria` → «Ver registro» → `RegistroActividad`. Drill-down enlazable: ampliar `RutaHash` (`router.ts:93-98`), `hashDe`/`leerHash` (`:132-156`) con `#/gestion-diaria/equipo/<uuid>` y `#/gestion-diaria/analista/<uuid>` (precedentes `:133-134`); el día vive en estado de sesión (v1). Banner «N tareas vencidas siguen pendientes» → desglose por equipo. Nota de corte del resultado tipificado. Tests + e2e Gerencia + protocolo `design-qa.md`.

**Despliegue:** SQL primero, front después. Codex: 1.


### F5 · El reporte de HÁBITOS para capacitar (decisión de Miguel, 20/09/2026)

**Qué obtiene Miguel:** no el pulso del día, sino **dónde está el problema de fondo** — para saber
a quién capacitar y en qué.

Por analista, sobre los últimos N días:

- **A qué hora hace su primera llamada.** Quien arranca a las 11 no tiene el mismo día que quien
  arranca a las 9.
- **Su hueco más largo sin llamar**, y a qué hora ocurre.
- **Cómo se reparte su tasa de contacto** frente a la de su equipo y la de la operación.
- **Cómo le fue en los dos cortes del día** (F4), cuántas veces los cumplió.

**Este reporte cierra un círculo:** es el que produce el dato que hoy falta para poner el número de
la alerta «tasa muy baja», que nace vacía en F4. Gerencia mira el reparto real, decide el umbral y
lo publica en la misma pantalla de configuración.

El núcleo vuelve a ser `private.gestion_diaria_llamadas`, que ya acepta varios analistas y rangos
de fechas: no hace falta un contador nuevo.

---

## Fase 6 — Absorber Seguimiento y cerrar (CERRAR → OBSERVAR → DERRIBAR) · LEVEL 2 · 1 PR

Cuando las fases 3–5 lleven al menos una semana en producción sin incidencias: `#/seguimiento` a `ALIAS_HEREDADO` → `gestion-diaria` (`router.ts:111-119`); retirar `'seguimiento'` de `VISTAS`, `CAPACIDAD_POR_VISTA` (línea 24) y su early-return (línea 100), sidebar, `App.tsx`, `TITULOS`; repuntar `lib/sla-avisos-presentacion.ts:22`, `screens/hoy/supervisor.tsx:836`, `ayuda-vendedor-panel.tsx:65-67`, `e2e/sla-operacion.spec.ts`; `ColaSlaPanel` sigue vivo. Actualizar los ~10 tests que mencionan `seguimiento`. `npm run check:all`. Vault, `Inicio.md`, actas en `MIGRACIONES.md`, PLAN.md del repo con «Lo construido vs lo planteado».

## Fuera de v1 (escrito para no perderlo)

Cuota diaria (§7.2) · reconocer/posponer para `sin_llamadas_hoy`, `tasa_baja`, `parado_2h`, `primer_intento_vencido` (exige ampliar el CHECK regex y policy para gerencia) · columna de estado del teléfono en `crm.leads` · «Crear tarea» sobre lead ajeno desde el registro · «Avisar al supervisor» · conversiones de hoy · «rango normal» de la tasa · alternancia de canal de la cadencia (llamada fallida → WhatsApp) más allá de lo que ya propone `sugerirSiguiente` · entrada por rango del registro desde un módulo Métricas · refactor de las 4 copias artesanales de tabs · fecha en el hash · medición del abandono del panel (paneles abiertos vs resultados).

## Riesgos que quedan aunque el plan se cumpla

- **Dos colas del día conviven** (Hoy = 3 cosas de ahora; Gestión Diaria = cola completa), por decisión de Miguel. Se declara en ambas pantallas y un test las mantiene coherentes en el primer ítem.
- **Fase 2 cambia el diálogo de llamada de TODO el CRM.** Es lo que pide §7.1 y es el cambio de mayor exposición: e2e completo y ventana de publicación con Miguel disponible.
- **Deshacer** es nuevo código sobre un descarte que hoy es irreversible para el analista; se apoya en `reabrir_lead_fn` y en una ventana de 24 h propia.
- **Histórico sin resultado**: 4 889 llamadas con `metadata = {}`; los tableros dicen «sin resultado» para lo anterior a la Fase 2.
- **Gates rojos ajenos** (4 de 8): el módulo solo puede demostrar «conjunto rojo idéntico».
- **`gen:types` roto**: 6 RPC nuevas a mano en `database.types.ts`.
- **Codex no conectó en esta sesión** (`CONNECTION_CLOSED`): reconectar antes de la Fase 1.
- **Banco compartido** entre sesiones y sesión paralela de «historial por lead»: pedir turno por `SendMessage` y coordinar `metadata` en `actividades_de_lead_fn`.

## Verification (punta a punta)

**SQL (por migración):** `npm run check:scripts` · `npm run test:rls:preflight` · `auditor-rls` · ensayo en banco (`banco.mjs`/`ensayar.mjs`: preflight md5 en verde, postflight fila por fila, reversa y registrador generados, `verificacion.json`) · `test:rls` línea base antes/después (sin regresiones; hay fallos de base conocidos) · `assert_sla_*` + `assert_gestion_diaria` en verde y censo rojo idéntico · advisors si hay rama · acta en `MIGRACIONES.md` · en prod: `db query --linked --file` por Miguel con `!`, registrador, objetos contados, prueba read-only con identidad real (`DO` + `set_config(jwt)` + `raise`).

**Front (por PR):** `npm run test:coverage` antes · `npm run check` · `npm run check:all` en fases 1, 2, 3 y 6 · `gate:realidad` · `revisor-a11y` · `design-qa.md` en fases 3–5 · preflight `node _DEV_NO_SUBIR/deploy-hostinger-mcp.mjs preflight crm.miavance.com <zip>` · PR con merge commit ANTES de construir · `/release-crm` por Miguel · bundle vivo contrastado · `git push avancecorp main` el mismo día.

**Prueba de negocio (Miguel, tras cada fase):** F1: como supervisor, leer el texto de una llamada de su equipo y comprobar que NO ve otro equipo; como gerencia, exportar CSV. F2: registrar una llamada real con «volver a llamar» y ver la tarea en Agenda; «no le interesa» → el lead aparece en el Centro de rescate con motivo; «Deshacer» dentro de 24 h lo devuelve a su etapa. F3: como analista, comprobar que el primer ítem coincide con «Ahora» de Hoy. F4: alertas y ratio del equipo; Reconocer solo en vencidas y por repartir. F5: pulso con el 735 remedido, cuadre 83 = 35+46+2, drill-down hasta el registro.

## Acciones manuales de Miguel

1. Confirmar submotivos y umbrales con los datos de la Fase 0. 2. Reconectar el MCP de Codex. 3. Autorizar el ensayo en banco (contenedor local: sin coste). 4. Instalar cada migración con `!` y publicar cada front con `/release-crm`, en ese orden, fase por fase. 5. Probar en producción lo indicado tras cada fase.
