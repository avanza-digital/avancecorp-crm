---

- [[Leads - marca y filtro de reasignados (2026-09-28)]] — publicado 29/09: filtro, contador y marca; conserva Sistema/Manual.

tags: [moc, inicio]
actualizado: 2026-09-25
---

# 🏠 Inicio — Portal Avance Corp

- [[Gestionado - ficha y vistas coherentes (2026-10-03)]] — **PUBLICADO Y VERIFICADO 03/10:** Gestionado en cabecera y etapas de la ficha, tabla, tarjeta, búsqueda y tareas. Build `build-20261004T025651347Z`, fuente `6b1c2538`; RLS 2.823, front 5.690, Docker 21/21 y HTTPS 98/98 PASS. Banco retirado. PR #181 pendiente de aprobación para integrar a Main; preservada la ficha Base F2 de #180.

- [[Llamadas desde el celular - auditoria de fases y pruebas S1-S3 (2026-10-09)]] — **ESTADO VIGENTE (09/10): C1 activo en producción desde el 07/10; 45/102.** Auditoría de lo que falta (tres puertas sin pantalla, entre ellas «unir a mano»), H-ESPERA arreglado en la macro y H-PERMISO abierto; tabla de pendientes por persona.
- (Superado: publicado e instalado desde el 07/10.) 🔴 **Llamadas desde el celular — REVISIÓN 02/10 (Miguel + Claude): NO PUBLICAR TODAVÍA.** Miguel aprobó #13–#15 y ratificó las decisiones. auditor-rls + Codex (BLOCK) + banco con esquema de prod: 5 fallos que bloquean (3 reproducidos: el reenvío delata si un número es lead, gerencia ve llamadas de leads borrados, la perilla de entrantes guarda «pide resultado»). Detalle: [[Llamadas desde el celular - revision antes de publicar (2026-10-02)]] y `CRM-Avance-Corp/docs/plans/llamadas-celular/REVISION-2026-10-02.md`.
- (Superado el 07/10: ya aplicado y desplegado.) 🔔 **PARA MIGUEL (actualizado el 05/10): llamadas desde el celular — NADA APLICADO NI DESPLEGADO.** Claude: avísale a Miguel al empezar. 05/10 18:32: su agente encontró un interbloqueo con Deshacer → corregido con la **séptima** (`20261005182227`, la llamada va a la pestaña si Deshacer tiene el resultado; banco 308/308); falta que vuelva a revisar. Los **pasos 1 a 6 del plan v2** están en el **PR #190**: quinta migración (`20261005143843`), F4-a (`20261005155914`, enlace exacto encuesta ↔ llamada), Edge del contrato nuevo, bloque del gate (sin correr), guías y el **encargo de Codex r2 ya generado** (`CRM-Avance-Corp/docs/encargos/2026-10-05-codex-llamadas-celular-correccion-r2.md`). Banco reducido 281/281. Ya se corrigió el [P2] de la reversa que encontró su agente (`260c0a4a`). Le toca: (1) **correr Codex r2** (`scripts/codex-review-mcp < <encargo>`) **y auditor-rls** sobre todo junto; (2) que su agente revise `260c0a4a`; (3) responder la **N1**, los criterios de Claude y el efecto del descartado reutilizable (comentario del #190); (4) el ensayo en su banco (reversas → gate → alta). MacroDroid Pro: todavía no. Handoff: `docs/plans/llamadas-celular/HANDOFF-2026-10-06.md`. Nota: [[Llamadas desde el celular - quinta, F4-a y Edge (2026-10-05)]] · antes: [[Llamadas desde el celular - decisiones de Miguel y plan v2 (2026-10-03)]].

- [[Llamadas desde el celular - F4-b lecturas y guia de cierre (2026-10-05)]] — **05/10 noche: F4-b escrita, SIN APLICAR.** Octava y novena en el #195 (la novena: «Qué pasó hoy» paginada y por lo RESUELTO hoy en Lima, decisión de Jhosep tras la revisión de Miguel); pestaña «Celular» en el #197 (solo demo). Guía ejecutable para el agente de Miguel en el #190: qué correr, en qué orden y qué contestar. Lección: «hoy» siempre es ambiguo, hay que decir hoy de qué.
- [[Llamadas desde el celular - quinta, F4-a y Edge (2026-10-05)]] — **05/10: quinta, F4-a, Edge, gate, guías y encargo r2 listos, SIN APLICAR (PR #190).** Miguel fusionó el plan v2 sin comentar; Jhosep lo contó como el OK. Su agente pidió cambios por un [P2] reproducido (la reversa volvía a correr tras la purga): corregido, las reversas solo corren antes de dar de alta celulares. Banco reducido 281/281, Edge 15/15. Lección: «ahora está vacío» no prueba «nunca se usó».
- [[Llamadas desde el celular - decisiones de Miguel y plan v2 (2026-10-03)]] — **03/10: Miguel decidió las seis decisiones de la corrección y una séptima** (los leads sin dueño y los descartados reutilizables son candidatos). Codex r1 dio BLOCK al plan v1 (6 P2 + 1 P3) y el **plan v2 (PR #179, borrador)** cierra cada hallazgo: id con forma fija, recepción en `private` con 32 días, la base como única validadora, candados en un solo orden y una propuesta nueva para su OK (salud sin `envios_hoy`). MacroDroid Pro: todavía no. Lección: dentro del CRM, saber si un teléfono existe no es secreto («Nuevo lead»).

- [[Cuentas de pago - F6 lista de Operaciones y decisiones (2026-10-02)]] — **F6 ENTREGADA 02/10 (~11:30):** Excel para Gloria con los 22 contratos sin cuenta de pago (20 reales: 8 con cuota vencida, S/ 3.248,75 + US$ 541,67; 7 con dos cuentas, 11 con cuenta en otra moneda, 2 sin cuenta; 2 demo que no se gestionan) y la acción por caso. Decisiones de Miguel: «Asignar cuenta» REEMPLAZA al «Marcar pagado» apagado en la agenda (portal `f69e190`, `pagos.js v47`, SW v139, 200/200; kit listo para subir), `2026-01-444444` se deja como demo, y la negativa de modo de transacción para «Retirar»/«Cambiar cuenta» va en migración aparte después de F6.



- [[Conversion - divisor de Coordinacion desde el nucleo (2026-09-30)]] — **v1 y v2 EN PROD (30/09 noche; front `build-20261001T002155841Z` desde `rescue/conversion-desglose-20261001` = vivo `6a9ad5e6` + v2):** el «62 en formulario» de la coordinadora era el reporte de ENTREGAS, no el divisor; pestaña «Conversiones» en `#/repartir` con el divisor del núcleo, cierres por origen y cartera (referidos, upgrade, renovación, sin peso) y consulta por mes o rango de fechas. Reviews Codex r1+r2, auditor-rls y a11y aplicadas. Pendiente: PR a `main`, advisors, decisión sobre el ajuste por persona visible para la coordinadora.

- [[Llamadas desde el celular - pruebas de MacroDroid en C1 (2026-10-02)]] — **LAS 6 PRUEBAS PASS (02/10):** MacroDroid envía solo cada llamada, la guarda si no hay red (también tras reiniciar) y la reenvía sola con el mismo id; sirve, sin otro adaptador. Requisito de Jhosep: la macro definitiva reenvía desde cualquier red y sin pedir ubicación. **La macro definitiva de salientes (F3-c) quedó armada en C1 y pasó sus 7 pruebas** (guía en `macrodroid.md` §3c); falta que Miguel aplique la base y publique la Edge. Límite: 5 macros en MacroDroid gratuito.

- [[Llamadas desde el celular - clientes como objetivo pendiente (2026-10-01)]] — **OBJETIVO PENDIENTE (Jhosep, 01/10):** llamadas, gestiones y tareas de leads y de clientes en general. Primero, completar la gestión de clientes en Gestión Diaria; la cola del día ya trae tareas de clientes desde el 29/09. El plan de llamadas cubre solo leads (propuesta #13 para Miguel). **02/10: ampliado a las llamadas ENTRANTES de leads y clientes** (atendida → encuesta; perdida → tarea «devolver la llamada»; métricas aparte): propuestas #14 y #15, que retiran el recorte #8.

- [[Llamadas desde el celular - F1 receptor por URL y ajuste Android (2026-09-30)]] — **F1 EN PRODUCCIÓN desde el 01/10 (build-20261002T005154879Z, con el #165; probada en C1 contra producción el 02/10, PASS):** al colgar, MacroDroid abre `#/gestion-diaria/llamada/{call_number}` y el CRM abre la misma encuesta de «Llamar» del lead (cola de intenciones por pestaña, coincidencia exacta con las dos formas canónicas, receptor en App). Probado en C1 con la build de la rama; la app instalada abre por URL solo con «Abrir vínculos admitidos» + dominio en Android. Unit 5093, E2E Docker 285/0. F2 (eventos en la base) con plan corto y 7 decisiones pendientes.
- [[Cuentas de pago - motivo del bloqueo, rezago y Asignar cuenta (2026-10-01)]] — **✅ EN PRODUCCIÓN 02/10 (~10:05): servidor (migraciones `20261001233019` y `20261002005004`) + portal (`bd3aab6`, SW v138), fusionado a `main`. Serial `AVC-CUENTAS-PAGO-20261002-R1`: Fase 5 cerrada; sigue F6 (Operaciones destraba los 22 con «Asignar cuenta»).** Tablero Figma `K2t5Padzr6FVXkFSPglILq`. 23 contratos viejos sin cuenta de pago no dejaban marcar sus pagos. Tres piezas: el bloqueo dice POR QUÉ (la carga vinculó solo 001086: los otros 7 «con cuenta» tenían DOS; censo 685·0·7·12·3 sobre 707), botón **«Asignar cuenta»** en Pagos para administración (solo motivo, sin correo) y el portal con la etiqueta por caso. Ensayo en prod `PASA` 5/5 antes de aplicar. Pendiente de decidir: posición del botón en la agenda, `2026-01-444444`, misma negativa de modo de transacción para «Retirar»/«Cambiar cuenta».

- [[Base para gestion del analista - F0 y decisiones (2026-10-01)]] — **F0 ENTREGADO 01/10 y re-verificado 02/10 (solo lectura, nada construido); plan en FigJam `zbgq3gjYGsaaMCo6e140bU`; carpeta de trabajo temporal `BASE PARA GESTION/` (README + ESTADO + ENCARGO) para retomar desde cualquier sesión:** la «base» del supervisor es el Centro de rescate (`#/rescate`); el resultado de llamada (7 valores), «no contactar» y `reabrir_lead_fn` ya existen y se reutilizan; el encargo choca en etapa al reactivar (`nuevo` vs Contactado), umbrales (6.º intento vs 3/30 días) y quién levanta «no contactar» (Gerencia). **BASE DE DATOS COMPLETA EN LOCAL (03/10): 7 migraciones (B1, B1b, B2, B3, B4, B4b, B3b) auditadas (auditor-rls ×5, Codex ×3) y verdes en el banco Docker; D1–D13 decididas. ✅ EN PRODUCCIÓN 02/10 20:15: las 7 aplicadas y registradas, con huellas iguales a las de la rama y gate de RLS en Docker a paridad (74/74, 0 rojos nuevos); tipos regenerados en `9c1d7296`; rama borrada. Sigue el FRONTEND F1–F4 (`BASE PARA GESTION/FRONTEND.md`). 🔴 `main` local diverge de GitHub (PR de integración sin Gloria: decide Miguel).**

- [[CRM - auditoria de indices (2026-09-30)]] — **MEDIDO 30/09 en prod (12 min en vivo + acumulado desde 25/09):** no falta ningún índice que valga la pena; lo que queda (`leads` 0,5 y `tarea_sla_contexto` 0,2 recorridos/s) es el filtro `p_lead_ids is null or …` del núcleo SLA y, en la ficha de inversionista, `cartera_f5_fuentes()` calculada 7 veces con dos CTE recursivas por FILA (291 de 490 ms). **Ensayado y deshecho:** fuentes con mapas jsonb = mismas 726 filas, 42 → 11 ms; ficha 509 → 284 ms, agenda postventa 164 → 97 (33/33 salidas idénticas). **Fase 1 HECHA 30/09: migración `20260930172255` + PR #144 (apilada sobre #143), banco Docker propio y prueba sintética 13/13, Codex r1 (P2 empates refutado por UNIQUE; P2 huellas aceptado) y auditor-rls PASS; **✅ EN PROD 30/09 ~13:49 por `!` de Miguel: ensayo 33/33 idénticas; verificación fuentes 42 → 11 ms, ficha 500 → 302 ms, agenda de postventa 165 → 101, cartera de inversionistas 190 → 95; advisors 242 = 242. **Medido con tráfico real el 01/10: ficha 920 → 351 ms (670 llamadas), agenda de postventa 286 → 107 (1.997), cartera de inversionistas 692 → 123 (1.596).** Integrada a `main` con la PR #164 (01/10): las PR #138 y #140–#144 se habían fusionado cada una en la rama de la anterior, no en `main`.** 156/370 índices sin lecturas: no se tocan.

- [[CRM - perfil de carga lectura vs escritura (2026-09-29)]] — **MEDIDO 29/09 en prod (~97 h):** el CRM es de LECTURA (13.143 M filas leídas vs 12.979 escritas); `crm.inversionistas` concentraba el 95 % (22,6 M recorridos completos por `cartera_f5_fuentes` sin índice usable en `perfil_id`). **✅ Paso 1 EN PROD 29/09:** índice `inversionistas_perfil_idx` (`20260929220021`): 545 → 0,8 recorridos/s. **✅ Paso 2 · Fase 1 EN PROD 29/09:** `cartera_f5_personas_visibles` sin el lateral por persona (`20260929230336`): lista de la cartera de inversionistas 2,3–3,2 s → **0,19 s**, resultados idénticos (46/46), Codex ×2 y auditor-rls PASS. PRs #136 y #138. **✅ Paso 2 · Fase 2 EN PROD 29/09 ~18:55:** sondeo adaptativo (tasas 15 s solo con pendiente, 2 min en reposo; postventa 60 s), build-20260929T235040143Z, PR #139; reducción de llamadas se mide el 30/09. **✅ Paso 3 · Fase 1 EN PROD 29/09 ~19:35:** agenda de postventa (`postventa_tarea_json` por familia, `20260930000550`): 509–532 → **211 ms** en cada carga de la lista de tareas, 13/13 idéntico, Codex APPROVE + auditor-rls PASS, PR #140. **✅ Paso 4 · Fase 1 EN PROD 29/09 ~20:05:** contador de avisos SLA evalúa solo oportunidades operativas (`20260930002929`): gerencia 1,75 → 1,26–1,29 s (−27 %, meta ≤ 1,2 no alcanzada del todo), supervisor 0,81 → 0,62; 15/15 idéntico; Codex ×2 + auditor-rls; PR #141. **✅ Gestión Diaria EN PROD 30/09 ~10:25:** sus dos consultas al núcleo SLA solo con operativas + resellado de guardianes (`20260930150852`): equipo de gerencia 1,85 → 1,35 s, avisos del supervisor grande 1,03 → 0,86; 20/20 idéntico; Codex + auditor-rls PASS; PR #142. SLA fase 2 (núcleo) medida y descartada: solo pagaría un «modo resumen» del motor (mini-proyecto). **✅ Vigilante del ayudante EN PROD 30/09 ~10:57:** `assert_sla_avisos` exige el ayudante por huella/dueño/permisos y que TODAS las llamadas del contador al núcleo vayan acotadas (`20260930154341`); 4 negativos en prod deshechos; Codex aceptado + auditor-rls APPROVE; PR #143. Siguen: 0,2 s de postventa, VOLATILE→STABLE, mutantes automatizados del vigilante (ítem aparte).

- [[Anexo de cronograma en el contrato PDF - plan v10 (2026-09-28)]] — **EN PRODUCCIÓN 29/09 (build-20260929T163327395Z, fb79c46f):** el analista imprime desde la ficha del contrato el anexo con el cronograma de liquidaciones parciales como documento aparte; el contrato PDF no cambia. Migración `20260929151350` (puertas solo service_role + núcleos + bitácora de emisiones con hash), acción «anexo» en la edge, botón en el front. Codex y auditor-rls aplicados. Pendiente: humo real de Miguel, rotar token de Hostinger, integrar #130 y PR.
- [[Boton GESTION DIARIA en Hoy del analista (2026-09-28)]] — **PUBLICADO 28/09 (build-20260928T233226790Z, 7e9b426a):** botón animado en la esquina de «Hoy» que lleva a Gestión diaria (teléfono que suena por estado, barra de avance, rebote, pop), diseñado en el UI Playground (CRM-02) y promovido con cifras de la misma cola que el destino. Codex y a11y aplicados. PR #129.

- [[Citas - validacion de cifras del supervisor Jorge (2026-09-28)]] — **VALIDADO 28/09:** 160 citas · 37 entrevistas · 40,2 % son exactas; el % divide por 92 citas CON RESULTADO (37 realizadas + 55 no asistió), no por las 160 creadas. Codex confirma. Pendientes: el pie «Total del equipo» no muestra el divisor; un «no asistió» con fecha futura (`53b4ac59`) entra al divisor el 30/09.

- [[Hoy del analista - sin espacios vacios (2026-09-28)]] — **PUBLICADO 28/09 en cuatro releases (último build-20260928T213044021Z, 7b72212a):** en producción «Tu agenda de hoy» + «Tus citas» v2 (cifras que filtran, tira de 7 días, filas de una línea) en dos columnas, «Tu cumplimiento del mes» siempre abierto y la pantalla sin scroll en escritorio; URL sin `?crm_version=…`; en el demo (legado), la pantalla «Hoy» del analista sin huecos: tarjetas de prioridad sin altura mínima, estados vacíos en horizontal (`VacioCompacto`) y las dos tarjetas de «Después» ya no se estiran a la misma altura. Solo presentación; check completo, E2E Docker 24/24, a11y y Codex PASS; humo en vivo PASS. El MCP de Hostinger 2.x cambió de contrato (ver «Deploy a Hostinger»).

- [[Ranking - desglose completo y nueva inversion de cartera (2026-09-28)]] — **PUBLICADO Y VERIFICADO:** desglose de Cartera desde operaciones reales; 577.554 PEN + 40.000 USD son Upgrade. Cuatro fuentes / S/70.000 recuperadas como Cartera → Nueva inversión; cuenta demo de Miguel excluida. Queda un contrato real de S/10.000 sin canal acreditado. SQL 381 → 383, check 4.763, Docker 280 PASS y 81 archivos HTTPS PASS; build-20260928T182709910Z. Commits `a764f140`, `a677381c`, `43b3d6d0`.

- [[Leads - franja compacta y capital convertido (2026-09-28)]] — **PUBLICADO 28/09 (build-20260928T174316188Z, 5f3656c0):** Leads sin espacio vacío (una franja con indicadores + etapas que filtran) y «Capital convertido» al filtrar convertidos (monto ESTIMADO; «confirmado» queda para contratos). Commit `5f3656c0` en main local; check 4.755, E2E 23/23 y gate de realidad PASS; Codex y revisor-a11y resueltos. PR #121 fusionada y traída al main local. Cerrado.

- [[Ranking - origen acreditado y desglose de cartera (2026-09-28)]] — **PUBLICADO:** recuperados 36 canales sin alterar dinero; caso reportado Formulario S/137.500, Referido S/15.000 y sin origen S/45.000. Cartera S/90.000 se desglosa Renovación S/10.000 / Upgrade S/80.000. SQL por merge nativo, check 4.740, RLS/HTTP y smoke 80 archivos PASS; build-20260928T171106059Z.

- [[Gestion Diaria - diseno VitaNova con colores del CRM, analisis y plan (2026-09-27)]] — **ANALISTA Y SUPERVISOR PUBLICADOS 27/09** (supervisor: build-20260928T014119651Z — cifras como filtros de la tabla, ficha protagonista, Registro y Pendientes compactos; analista: teléfono alto, «Llamar» 44 px, «Lo último con este lead»); **sigue gerencia, con su propio plan:** el diseño «Gestión diaria pantallas» (VitaNova) tiene la misma estructura que el módulo en producción; cambia la presentación. Vista previa con navy/azul y Plus Jakarta Sans en `GESTION DIARIA/`. Solo pantalla, sin migraciones. Decidido: 4 cifras en gerencia y resultado dentro de «Ahora».

- [[Integracion del main local y pendientes (2026-09-27)]] — **INTEGRADO:** main local al día con GitHub (#101–#113); PR #114 FUSIONADA y traída, sin lo de Gloria (cuentas de Gloria y Pagos del portal quedan SOLO en local, decisión de Miguel). Limpieza de 37 ramas y lista de pendientes al 27/09.

- [[Conversion - publicacion verificada (2026-09-27)]] — **PUBLICADA:** conversión por cierre comercial y vínculo confirmado hasta finalizar el día 10 siguiente, desde septiembre. 97 acreditadas, 9 tardías y 2 pendientes; históricos/importes intactos. PR #113, SQL por merge nativo, matriz 2268/0 y 80 archivos HTTP PASS. Límites previos documentados.

- [[Ranking cartera - publicacion verificada (2026-09-26)]] — **PUBLICADO:** continuidad legada acreditada aparece como Cartera; Betzabeth S/150000, totales y conversión intactos. SQL por merge nativo, PR #112, verificaciones PASS, rama temporal eliminada. Restricción de nueva inversión por empresa pendiente.

- [[Cuentas bancarias - Gloria ve y añade cuentas, fase 1 publicada (2026-09-26)]] — **FASE 1 PUBLICADA:** botón «Cuentas» en Clientes con «Añadir cuenta» (aparece en el CRM); admin/superadmin ven N°, CCI y beneficiario completos. Fases 2–4 (historial, cambiar cuenta de pago por pedido del cliente, retirar) pendientes. Verificación visual de Gloria pendiente.

- [[P-0XX - cierre productivo verificado (2026-09-26)]] — **CERRADO:** CRM y portal comparten cuentas; 501 registros válidos sin diferencias, dos avisos retirados y cero nuevos. 23 contratos sin vínculo: 21 operativos y 2 demo, reportados y bloqueados para pago. Rama temporal eliminada.

- [[Portal Pagos - plan de mejora en Figma (2026-09-26)]] — **F1–F5 PUBLICADAS Y VERIFICADAS EN PRODUCCIÓN 26/09 (commits `12d9d4f`, `bf32942`, `97895bb`, `232b2ea`, `10693b1`, `d13117a` del portal, por TUS archivo a archivo, caché purgada). F5 = decisión de Miguel «solo lo que toca pagar»: Pagos queda en Agenda + buscador, sin pestañas; la tabla de contratos aparece solo al buscar; «Pagados este mes» pasa al Dashboard; el tramo «Próximos 30 días» quedó RECHAZADO. Pendiente: pasada visual de Miguel y retirar `admin_pagos_resumen` ~03/10:** Pagos del admin se veía roto por un retardo de aparición sin tope (fila 650 → 18 s en blanco) y trae los 656 contratos de golpe; la función paginada del servidor ya existe y no se usa. F1 = solo estilos (tope 400 ms, aviso de cuenta alineado, letra ≥14 px), 116/116 pruebas. Siguen F2 paginar · F3 agenda por tramos · F4 lectura. Tablero FigJam vivo; actualizarlo al cerrar cada fase.

- [[Eliminacion de usuarios y contratos - preparada y Alvaro eliminado (2026-09-25)]] — **BACKEND INSTALADO Y VERIFICADO:** Álvaro eliminado; contratos con cotitular de alta corregidos; eliminación de usuarios exige transferir pendientes y conserva autoría. 33 SQL y 22 HTTP/Auth PASS; rama eliminada. Pantallas pendientes de publicación.

- [[Ranking - capital por canal de llegada (decision 2026-09-25)]] — Decisión para la ficha del Ranking: canales de llegada, Cartera separada y desglose mensual que cuadre con el capital confirmado. Botón de regreso retirado localmente; datos por origen pendientes de SQL.

- [[Gestion Diaria - Correccion de paridad horizontal de gerencia (2026-09-25)]] — **PUBLICADA Y VERIFICADA:** fuente `65e96df9`, paridad UI y orientación horizontal con menú abierto; 81/81 archivos y recorrido real 9/9 PASS. Observación y retirada de Seguimiento pendientes.

- [[Gestion Diaria - UX gerencial publicada y verificada (2026-09-25)]] — **UX F6 PUBLICADA Y VERIFICADA:** fuente `f9196dba`, 81/81 archivos HTTPS y recorrido gerencial 8/8 PASS. Fecha, tabla, detalle lateral, hábitos y ficha con contexto conservado. Mismo Figma actualizado; retirada pendiente de siete días estables y corte del sábado.

- [[Gestion Diaria - UX gerencial integrada y publicacion pendiente (2026-09-25)]] — Historial del paquete y los bloqueos anteriores, resueltos por la publicación verificada de F6.

- [[Gestion Diaria - UX horizontal de gerencia preparada (2026-09-25)]] — Evidencia técnica de la UX publicada: gate 4.421/298, Chromium 270/0/26, WebKit 10/0 y revisión independiente PASS. Estado vigente en el acta de publicación anterior.

- [[Gestion Diaria - F5 publicada y F6 en observacion (2026-09-24)]] — **F5 PUBLICADA Y VERIFICADA:** SQL por merge nativo, frontend `b402a7f1`, 2.267 aserciones y HTTP 21/21, cifras y 78 archivos servidos PASS. T0 24/09 21:57:11 Lima; retirada F6 no antes del 01/10 a esa hora y con estabilidad acreditada. Banco eliminado; sábado pendiente.

- [[Gestion Diaria - cola completa F6 preparada (2026-09-24)]] — **COLA PUBLICADA; RETIRADA PENDIENTE:** PR #97 integrado y servido inicialmente en `3027028d`; conservado en F6 `f9196dba`. Gate 4.393/297, Chromium 265/0/26 y WebKit 14/0 PASS. Los siete días reales aún no están acreditados.

- [[Gestion Diaria - F4.1 apagada y F5 en desarrollo (2026-09-24)]] — Historial de preparación y validación F5; publicación vigente en la nota anterior. F4.1 OFF; cierre F4 auditado, sábado pendiente.

- [[Gestion Diaria - auditoria y plan F4.1-F6 (2026-09-24)]] — Conformidad manual cerrada por Miguel; auditoría dirigida PASS, reaviso 13:39 comprobado. Plan F4.1–F6 definido; controles futuros conservados.

- [[Gestion Diaria - recorrido de supervision conforme (2026-09-24)]] — **RECORRIDO ACEPTADO POR MIGUEL:** H6.4 cerrada, 72/72 tareas. Primer corte contrastado: 4 cumplieron, 1 recuperó y 5 pendientes. Aplazamiento real hasta 13:34 Lima conservado tras recarga y nueva pestaña. F4 sigue abierto para reconocimiento, otra sesión/dispositivo, corte 16:00 y sábado 26/09.

- [[Venta cruzada - servidor probado en banco y P1 del PDF (2026-09-24)]] — **EN PRODUCCIÓN (24/09), SERVIDOR Y PANTALLAS:** la venta cruzada (B vende a un cliente de A sin tocar al responsable). Servidor con ensayo previo deshecho, advisors sin errores; frente `build-20260925T011258009Z` desde el PR #93, idéntico al ZIP.

- [[Gestion Diaria - supervisor con consulta por fecha (2026-09-24)]] — **PUBLICADA Y VERIFICADA:** selector de día y regreso a hoy; actividad y registro por fecha, equipo y pendientes actuales. PR #89 integrado, fuente `929fbbcc`, 4.281 pruebas y 251 E2E Docker aprobados en varios tramos (26 omisiones previstas). Archivos publicados y recorrido real del supervisor PASS; acta posterior sin nueva publicación.

- [[Gestion Diaria - H6.3 publicada y aceptacion pendiente (2026-09-24)]] — **PUBLICADA Y VERIFICADA:** H3 por merge nativo, frontend `bbe341f6`, 116 archivos HTTPS y recorrido técnico de supervisor PASS. Matrices alojadas 2.226/0 antes y después; banco eliminado (~US$0,018). 70/72 tareas: H6.4 pendiente de aceptación humana. Actas en PR #88; no volver a publicar por documentación.

- [[Gestion Diaria - H5 verificada y H6 preparada (2026-09-24)]] — **H1–H5 Y H6.1/H6.2 CERRADAS:** 4.274 pruebas y E2E completo 249/0/26, SQL/RLS y visual PASS. Producto `788834cc`, PR #87 integrado en Main `bbe341f6`; ZIP de 116 archivos y respaldo verificados. Mismo Figma 67/72, histórico intacto. Respaldo vivo verificado; publicación SQL/frontend y aceptación real pendientes.

- [[Gestion Diaria - plan vivo en Figma y mejora visual (2026-09-23)]] — **MEJORA VISUAL PUBLICADA:** PR #82, fuente `e8e4f35f`, build `build-20260923T204457952Z`; 4.179 pruebas, archivos y acceso de gerencia verificados. Mismo plan editable en Figma, 76 puntos. Pendientes aceptación de analista/supervisor y primera jornada real de F4 del 24/09. Fixtures integrados mediante PR #84; acta de publicación enlazada en la nota.

- [[Gestion Diaria F4 - publicado y cortes programados para el 24-09 (2026-09-23)]] — **SQL Y FRONTEND PUBLICADOS; V2 PROGRAMADA.** PR #77 fusionado y publicado, fuente `8e6f4357`, build `build-20260923T173450335Z`; 113 archivos y smoke gerencia PASS. Detalle opcional compatible con tipos regenerados; 4.175 pruebas y 32 E2E focalizados PASS. Cortes desde 24/09, 11:30 y 16:00 Lima; tasa baja OFF hasta F5. Banco eliminado (~US$0,070 acumulados). Pendiente primera jornada real y recorrido con supervisión.

- [[Gestion Diaria F4 - cinco SQL publicados OFF y PR 76 sin conflictos (2026-09-23)]] — Acta intermedia del ensayo y merge SQL; completada por la publicación y programación anteriores.

- [[Acceso Avance - apellidos y nombres separados (2026-09-22)]] — **PUBLICADO Y VERIFICADO:** apellidos primero, nombres después, sin campo duplicado. PR #72 integrado; fuente `7d65fcdb`, build `build-20260922T221442353Z`, 4.085 pruebas, 6 E2E y cotejo de archivos productivos PASS.

- [[Gestion Diaria F4 - etapa 3 publicada con cortes OFF (2026-09-22)]] — **PUBLICADA Y VERIFICADA:** SQL v1 OFF y frontend `e22c0cab`, build `build-20260922T165247339Z`. Respaldo anterior de 107 archivos cotejado byte a byte, controles SQL/HTTP y login PASS. Sigue F4 etapa 4; recorrido del supervisor, etapas 4–6 y activación pendientes. Índices INFO y conciliación del historial SQL registrados aparte.

- [[Gestion Diaria F4 - release detenido por historial de ramas (2026-09-22)]] — Historial del bloqueo de ramas y acceso; superado por la instalación SQL OFF y la publicación de etapa 3. Ver el checkpoint vigente anterior.
- [[Gestion Diaria F4 - cierre en copia aislada y banco Docker propio (2026-09-22)]] — Etapas 4–5 implementadas localmente: 4.153 tests, 232 E2E Docker y 25 mutantes PASS. Main integrado; propuesta SQL/entrega lista, autorización y primera jornada pendientes. Cortes productivos OFF.

- [[E2E del CRM en local con Docker (2026-09-22)]] — Los E2E se corren con `npm run test:e2e:docker`; regla escrita para Claude y Codex. Nunca en GitHub.

- [[Gestion Diaria F4 - cortes de jornada (2026-09-21)]] — **PR #68 ABIERTO, SQL EXACTO APROBADO; CI BLOQUEADA POR FACTURACIÓN DE GITHUB:** ensayo HTTP/matriz general cerrado en `8ca9045c`, baseline 2.164/0 fallos y candidato OFF 2.196/0; 4.085 tests de aplicación y 22 E2E PASS, navegador real y recuperación verificados. Banco HTTP instalado OFF. GitHub no inició los trabajos: revisar «Billing & plans» y reejecutar CI. Revisión solicitada a `miguejbs98`; después gates y `$release-crm`, sin merge ni SQL productivo todavía. Etapas 4–6 y activación pendientes; TypeSafe preparado pero sin integrar al CRM.

- [[Gestion Diaria F4.1 - banco humano y reglas de cortes (2026-09-21)]] — **PREPARACIÓN LOCAL:** guía y banco ciego ficticio para ambos supervisores; no hay revisión humana ni TypeSafe en CRM todavía. Reglas de cortes cerradas: sábado 3 llamadas, cartera vacía fuera de avisos de corte y aplazamiento único sin reaviso al cierre o después. Sin notas reales, SQL ni publicación.

- [[Gestion Diaria F4.1 - TypeSafe tecnico y piloto humano pendiente (2026-09-21)]] — **ENSAYO TÉCNICO LOCAL, CRM SIN ACTIVAR:** API verificada y apoyo técnico usado; control de notas aisladas 19/20, una falsa alerta conservada. Ambos supervisores validarán el piloto, cada uno únicamente por su equipo; responsables definidos, muestra y validación pendientes. Sin notas reales, SQL ni publicación; no confundir con el cierre de F4 etapa 2.

- [[CI del CRM sin E2E en GitHub (2026-09-21)]] — Por decisión de Miguel, GitHub Actions conserva el gate de calidad y retira el job E2E, que puede ejecutarse localmente cuando corresponde.

- [[Gestion Diaria F4 - detalle del analista preparado (2026-09-21)]] — **ETAPA 2 PUBLICADA Y VERIFICADA:** detalle de llamadas por hora, registro F1 y ficha con filtros/foco conservados; fuente `baa63aea`, PR #64, build `build-20260921T200508459Z`. 4.051 pruebas, 232 E2E/26 omitidos, preflight real de lectura y 110 controles HTTP finales PASS. Sin nuevas SQL, cortes ni TypeSafe. Sigue el recorrido humano productivo y F4 etapa 3; ver acta y límites.

- [[Eliminar contratos - permiso permanente y registro inicial (2026-09-21)]] — **PUBLICADO Y VERIFICADO:** permiso permanente de Admin/Superadmin corregido para el alta unificada. 001457 eliminado con auditoría exacta de contrato/13 cuotas/registro/solicitud y PDF conservado; 35 pruebas SQL y 48 Edge PASS. No retirar esta capacidad en futuros cambios.

- [[Pipeline - etiqueta sin asignar por nombre ausente (2026-09-21)]] — **PUBLICADO Y SESIÓN CERRADA:** Pipeline resuelve el nombre del analista por su ID y reserva «sin asignar» para leads sin responsable. Fuente `b0d2ff89`, PR #63; 4.016 pruebas, CI y 108 comprobaciones HTTP PASS. Conformidad de Miguel y checkpoint documental local; artefactos, evidencias y recuperación conservados.

- [[Gestion Diaria - publicacion de equipo y resultado (2026-09-21)]] — **PUBLICADO Y CHECKPOINT GUARDADO:** F4 etapa 1 y ampliación F2/F3, SQL instalado/registrado y frontend `526e728e`, PR #62. Build `build-20260921T170500239Z`; 4.016 pruebas, 231 E2E y verificaciones productivas PASS, con límites documentados. Miguel confirmó que la mejora le gusta y pidió guardar el progreso; conformidad visible registrada, sin atribuir una prueba completa. Sigue recorrido de negocio y F4 etapa 2; cortes y TypeSafe no activados.

- [[Gestion Diaria - resultado separado del descarte (2026-09-21)]] — **AMPLIACIÓN F2/F3 PUBLICADA:** las siete opciones se contraen al elegir; «No le interesa» y «Pide otro producto» permiten agendar y conservar el lead. Descarte explícito, veto respetado, v3/recibos preservados. Autorización productiva y publicación completadas; F4 conserva sus etapas 2–6 pendientes.

- [[Mi dia del analista - dos columnas y foco accesible (2026-09-21)]] — **INCLUIDO EN EL RELEASE `526e728e` (21/09):** «Mi día» conserva dos paneles hermanos —«Ahora» con una sola acción primaria y la cola en pestañas—, menú accesible, foco visible y rojo reservado a lo vencido. Historial y verificaciones iniciales en la nota; publicación vigente en [[Gestion Diaria - publicacion de equipo y resultado (2026-09-21)]].

- [[Conversion - una sola pieza para Metas y la oficial (2026-09-23)]] — **EN PRODUCCIÓN 23/09:** Metas dejó de calcular la conversión. La cifra por persona vive una sola vez en el núcleo, y la usan la oficial y Metas (tabla y «fuera del ranking»). En pantalla no cambia nada: 224/224 respuestas idénticas. Ensayado con mes sellado, deuda y reversa. Verificación: `metas-vs-oficial.sql` PASS.

- [[Conversion - tabla por origen al peso de la general (2026-09-23)]] — **EN PRODUCCIÓN Y EN PANTALLA 23/09:** «Resultados por origen» pesa cada cierre como la conversión general. Referido pasa de 72,7 % a 10,9 % (×0,15); Formulario y Landing no cambian. La cifra la calcula el servidor. Huella vigente de la función: `6e4fedb3…`.

- [[Auditoria de conversiones - capas backend a frontend (2026-09-21)]] — **AUDITORÍA CERRADA «CON LO QUE HAY» (21/09), CORRECCIONES PENDIENTES DE OK:** 10 de 11 cifras de gerencia salen del núcleo único (Citas no); pero rango/Distribución recalculan en vivo meses sellados y publican el numerador BRUTO mientras Ranking/Metas/HOY sirven foto y NETO — dos verdades para el mismo mes; la sonda de paridad compara el núcleo consigo mismo; la deuda por anulaciones se descuenta en dos meses abiertos a la vez; ningún gate protege «un solo núcleo». Sonda de producción escrita y pendiente (`supabase/scripts/sonda-paridad-conversion-prod.sql`). Cómo retomar desde otra cuenta: `CRM-Avance-Corp/docs/auditorias/conversion-2026-09-21/RETOMAR-EN-OTRA-CUENTA.md`.

- [[Ficha de lead - retiro del boton Registrar actividad 2026-09-20]] — **CORRECCIÓN DE SUPERVISIÓN PUBLICADA Y VERIFICADA:** el acceso rápido fue retirado y el historial conserva su scroll. El aviso de seguimiento ya no ofrece ni puede abrir el compositor para Supervisor o Gerencia; `vendedor` conserva su gestión SLA. Release `crm-20260920T223427Z-8b3252b48455`, build `build-20260920T223425954Z`; CI, hashes de producción y protección del ZIP PASS.

- [[Ficha de lead compacta - tasa plegable e historial con scroll 2026-09-20]] — **PUBLICADO Y VERIFICADO:** la solicitud de tasa inicia plegada sin desmontar su validación y el historial usa un riel de scroll de altura acotada. Commit `004bd69f`, build `build-20260920T182519890Z`; CI de `main`, artefacto, hashes y smoke HTTP en producción PASS.

- [[Gestion Diaria - modulo nuevo y absorcion de Seguimiento 2026-09-19]] — **F0–F3, resultado v4 y F4 etapa 1 EN PRODUCCIÓN (21/09).** Acta vigente: [[Gestion Diaria - publicacion de equipo y resultado (2026-09-21)]]. Objetivos de las seis etapas y piloto TypeSafe: [[Gestion Diaria F4 - objetivos y piloto TypeSafe (2026-09-20)]]. Recorrido humano, etapas 2–6 y F4.1 pendientes. Plan único: `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`.

- [[Conversion de lead con Nueva inversion - preparado 2026-09-19]] — **VALIDADO, SIN PUBLICAR:** Convertir a cliente usa el proceso de Cartera; el lead se cierra sólo al confirmar. SQL y banco hasta US$5 autorizados; pruebas locales/remotas y 284 aserciones bancarias PASS. Pendiente publicación coordinada mediante `$release-crm`.

- [[Interruptor integral de rentabilidad - preparado 2026-09-18]] — **PUBLICADO 18/09:** el botón controla toda la exigencia de tasa en CRM, portal, conversión y contratos; observación deja de solicitar o consumir aprobaciones. SQL, CRM y portal verificados en producción.

- [[Mapa de capas del servidor CRM - 2026-09-17]] — **PUBLICADO 17/09 (artifact privado):** mapa interactivo de las 4 capas (Tablas → Núcleo → Puerta → Pantalla) levantado del catálogo vivo: 398 conexiones sanas, 171 saltos (A 56 · M 81 · B 31 · D 3), 52 objetos sin llamador. Evidencia y scripts en `SERVIDOR-CRM/mapa-capas-2026-09-17/`.

- [[Solicitudes de tasa - rechazos solo en notificaciones (2026-09-16)]] — **PUBLICADO 16/09 17:47 Lima:** rechazos en la campana; «Mi jornada» conserva solicitudes activas. PR #7 aprobado e integrado, fuente `4c2fe9e44181`, 3.659 pruebas, cuatro recorridos focalizados, CI y 93 comprobaciones HTTP PASS. Acta con artefacto, huella, recuperación y límites.

- [[Eliminar contrato vinculado sin historial - preparado 2026-09-16]] — **PREPARADO, SIN PUBLICAR:** corrige el bloqueo de la captura; inversión/titulares auditados, pruebas completas y rama eliminada. Pendientes SQL autorizado y release.

**Cartera multiempresa, 16/09 — PUBLICADA:** [[Cartera multiempresa - publicacion (2026-09-16)]] — plan de gestión integral completado; SQL instalado, frontend `14be1e0581d8`, 95 comprobaciones web PASS. Banco temporal eliminado, coste estimado US$0,009353. Acta con pruebas, rollback y límites; trabajos ajenos conservados.

- [[Matriz RLS global - reparacion y candado F8 2026-09-16]] — **CERRADO:** corrección F8 autorizada, instalada y verificada el 16/09 10:31 Lima. Datos/permisos intactos, 23 cuentas de Cartera comprobadas; matriz reparada y rama temporal eliminada.

- [[Eliminar contratos con pagos por administrador - preparado 2026-09-15]] — **PUBLICADO:** SQL/Edge y frontend incluidos en la entrega de Cartera; 78 recursos web verificados. Reparación de la matriz general en la nota del 16/09.

- [[Citas Gerencia - ticket unificado en soles 2026-09-14]] — **PUBLICADO:** totales PEN/USD visibles y ticket/proyección en soles; 3555 tests, 7 E2E y 67 recursos HTTP verificados.

- [[Rentabilidades menores a 15 - publicacion autorizada 2026-09-14]] — **PUBLICADO 14/09:** nuevas inversiones desde 0,01 %; aprobaciones superiores y bloqueo de pendientes conservados. Banco eliminado, coste estimado US$0,059; cambio conservado por Citas, 67 recursos de código HTTP verificados.
- [[Rentabilidades menores a 15 - entrega local sin deploy 2026-09-14]] — historial del ensayo local y la pausa, sustituidos por la autorización y publicación del 14/09.
- [[Citas Gerencia - decisiones finales para publicar 2026-09-14]] — **PUBLICADO 14/09:** reglas 1,25 internas y 70/70 activas desde septiembre; clientes por persona, mes/analista del evento. Build `build-20260914T173227102Z`; acta y banco temporal cerrado.

- [[Citas Gerencia - avance integrado sin deploy 2026-09-13]] — historial de preparación local/banco del 13/09 y orden anterior de no desplegar, sustituida por la autorización y publicación del 14/09.
- [[Citas Gerencia - reglas confirmadas y propuesta revisada 2026-09-13]] — cuentan manuales y sus citas, cada asistencia cuenta como entrevista y el ticket es mensual por analista; historial de la propuesta aprobada.
- [[Citas Gerencia - meta incorrecta detectada y correccion local 2026-09-13]] — historial del reclamo por la meta anterior; corrección y métricas publicadas el 14/09.

Bóveda de conocimiento del **Portal Digital de Inversiones de Avance Corp S.A.C.** (dominio `miavance.com`). Es la **memoria de negocio y decisiones** del proyecto. Léela al inicio de cada sesión.

Estado vigente: [[F9 - apertura general autorizada (2026-09-15)]] — **ACTIVADA 15/09 21:08 Lima** para 18 analistas, 3 supervisores y 2 Gerencia; 17 escenarios PASS, 24 cuentas verificadas, 614 inversiones/468 personas conciliadas. F4/F5/F6 ON; F8 OFF; F7 OFF. Sigue observación G8.
Historial del piloto: [[F8 - piloto nominal activado (2026-09-14)]].
Publicación y punto de retoma: [[F8 - ensayo remoto y correccion de conflictos (2026-09-15)]].
Adaptación visual aprobada y publicada: [[F8 - ficha anterior recuperada para multiempresa (2026-09-15)]] — commit `d93d805`, 3.596 pruebas y 23 recorridos PASS; cuatro contextos reales y 80 archivos de código/configuración verificados. G7 abierto.
Rendimiento medido: [[Rendimiento ligero - medicion de Cartera y Hoy (2026-09-15)]] — 39 consultas; ficha Gerencia 2,7 s / Analista 0,8 s. Optimización del núcleo propuesta; web y concurrencia real no acreditadas. Sin cambios de producto.
Optimización publicada: [[Ficha rapida - publicada y verificada (2026-09-15)]] — ficha SQL Gerencia 2,67 → 0,72 s; datos/permisos idénticos, Auth/API remoto y producción verificados. Banco eliminado, coste estimado US$0,021. Siguiente: preparar apertura a los 18 analistas y cerrar pendientes reales G7.
Piloto nominal apagado al abrir F9; cuatro participantes conservados como historial. La apertura general no vence el 21/09. Conformidades G7 se conservan según su evidencia.
Revisión para apertura: [[G7 - revision real y apertura pendiente (2026-09-15)]] —
613 inversiones/467 personas coherentes internamente; 19 fichas y 24 cuentas
verificadas; diez reintentos, cinco carreras, veintiún contextos y transición/reversa
locales PASS. Miguel aprobó complementar la muestra real en una copia aislada:
15 grupos HTTP, 3 financieros y matriz ampliada de permisos PASS. Refresco 18:32:
614 inversiones/468 personas sin diferencias. La preparación productiva y
apertura se completaron después en F9; conformidades financieras no se inventan.
Pendiente resuelto: [[Cartera inversionistas - implementacion de filtros comerciales (2026-09-15)]] — **PUBLICADO 15/09:** mes comercial y filtros por rol, distribución compacta vertical/horizontal; 17 grupos SQL remotos, 20 comprobaciones Auth/HTTP, 23 cuentas y 91 recursos web verificados. Banco eliminado. Conserva la ficha anterior y los núcleos F5.

[[F8 - ajustes de cartera y condiciones COOPAC preparados (2026-09-14)]]:
timeout corregido en banco local, Ficha 360 recuperada y plazo/rentabilidad anual
manual COOPAC implementados. Acta local de 3.579 pruebas y 15 E2E PASS;
publicación y corrección PT409 verificadas en la nota del 15/09 (3.582 pruebas
finales PASS). Banco eliminado. G7 mantiene pendientes recorrido visual y conformidad.

Antecedentes: [[F8 - pausa segura de instalacion (2026-09-14)]],
[[F8 - instalacion autorizada en curso (2026-09-14)]],
[[F8 - instalacion apagada preparada (2026-09-13)]],
[[F8 - exclusion demo preparada (2026-09-13)]],
[[F8 - enlaces reales aplicados (2026-09-13)]],
[[F8 - enlaces historicos preparados (2026-09-13)]],
[[F8 - revision de identidades pendientes (2026-09-13)]] y
[[F8 - piloto economico preparado localmente (2026-09-13)]].
F7 publicada e instalada OFF; G6 cerrado el 13/09 para el corte conciliado.
F8 tiene control y exclusión demo instalados. Los diez movimientos reales ya
están enlazados; no se repite ese lote. El ensayo combinado pasó 31 pruebas SQL
locales, 27 remotas y 12 grupos Auth/Data API. Producción: 600 fuentes reales,
cero huecos y cinco demo conservadas fuera de la operación al corte del 14/09.
Las fuentes previas, hechos económicos, Vault y Cron conservaron sus huellas.
Rama exclusiva eliminada después de verificar. Main integrado y artefacto
construido desde el commit verificado; 3.513 pruebas frontend PASS.
Instalación y encendido ya aprobados y ejecutados; no volver a pedirlos.
F8 OFF después de la apertura general del 15/09; sus cuatro miembros quedan
como historial. F4/F5/F6 ON para el equipo según roles y ámbito; F7 sigue OFF.
Antecedente: [[F6 - cierre y ajustes publicados (2026-09-11)]].
Plan principal: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].

## 🧠 Cómo funciona la memoria de este proyecto

Hay **tres capas**, complementarias:

1. **Este vault de Obsidian** — conocimiento curado, decisiones y features (notas enlazadas).
2. **Grafo de código (CODEgraph)** — estructura del código, vía el MCP `codegraph` (`mcp__codegraph__*`). Consúltalo (p. ej. `codegraph_symbol_search`, `codegraph_get_ai_context`) en vez de grepear.
3. **Documentos canónicos** (la *fuente de verdad* técnica):
   - **`public_html/CLAUDE.md`** → memoria técnica detallada del portal. **GANA sobre todo lo demás** si hay diferencia.
   - **`PORTAL_AVANCE_CORP_IMPLEMENTACION.md`** → guía de implementación.
   - **`CRM-Avance-Corp/PLAN-CRM-AVANCE-CORP.md`** → plan maestro vigente del CRM;
     su sección inicial «Estado maestro vigente» concentra avance, ruta crítica y
     definición de «CRM listo».
   - *(`MEMORIA DE PROYECTOS.md` se eliminó el 2026-06-01 por estar desactualizado — era copia vieja del CLAUDE.md.)*

## 🗺️ Mapa de notas

- [[Arquitectura del portal]] — stack, base de datos, edge functions, seguridad (resumen).

**Features y decisiones:**
- [[Correccion de correo de clientes por admin - 2026-09-15]] — corrección de acceso autorizada; pruebas y acta de publicación.
- [[F8 - pausa segura de instalacion (2026-09-14)]] — pausa solicitada, producción sin F8, rama propia eliminada, revisión recibida y punto exacto de retoma guardado.
- [[F8 - instalacion autorizada en curso (2026-09-14)]] — dos SQL aprobados; rama propia creada, reconstrucción y verificación en curso; F8 productiva sin instalar ni activar.
- [[F8 - instalacion apagada preparada (2026-09-13)]] — SQL exacto y procedimiento para rama con paridad de esquema/historial/Edge; precondiciones actuales verificadas; instalación pendiente.
- [[F8 - exclusion demo preparada (2026-09-13)]] — 31 pruebas locales; SQL y reversa listos para revisión, sin aplicar ni activar producción.
- [[F8 - enlaces reales aplicados (2026-09-13)]] — SQL aprobado y aplicado; siete personas / diez movimientos, cero huecos reales y cuatro demo pendientes. F8 sigue OFF.
- [[F8 - enlaces historicos preparados (2026-09-13)]] — historial del ensayo de siete personas / diez movimientos; aplicación productiva completada después.
- [[F8 - revision de identidades pendientes (2026-09-13)]] — diagnóstico cerrado: ocho movimientos reales para completado, dos del caso multirrol y cuatro pruebas. Informe privado en el escritorio; correcciones pendientes.
- [[F8 - piloto economico preparado localmente (2026-09-13)]] — control nominal F8 probado en banco sintético; producción intacta y piloto todavía OFF. Faltan enlaces, equipo, rama e inicio autorizado.

- [[Citas Gerencia - preparacion verificada 2026-09-13]] — publicación existente comprobada: tres migraciones y 72 archivos HTTP coincidentes con `d3ce2c1`; deuda de pruebas generales y nuevas metas/proyección pendientes.
- [[Citas Gerencia - publicacion pausada 2026-09-12]] — preparación detenida por Miguel; candidatas ensayadas en rama propia, validaciones incompletas, sin commit ni publicación.
- [[Citas Gerencia - conexiones corregidas en local 2026-09-12]] — caché y lector canónico preparados y probados; SQL sin instalar, nuevas metas/proyección y gate global pendientes.
- [[Leads recibidos por dia para analistas 2026-09-12]] — rango y conteo diario de entradas operativas a la cartera; rama preview verificada, pendiente de publicación.
- [[Citas Gerencia - avance y proyeccion mensual por analista 2026-09-11]] — flujo cita/entrevista/cliente aclarado; propuesta visual del cierre con tasas y ticket, bases pendientes.
- [[Citas Gerencia - control de Superadmin en borrador 2026-09-11]] — panel local para metas y reglas; guardado compartido pendiente de SQL autorizado y nuevas métricas aún sin activar.
- [[Alertas de respuestas de tasa para analistas - 2026-09-11]] — avisos en la PC, sonido y lectura de respuestas propias mientras el CRM está abierto.
- [[Notificaciones de solicitudes de tasa - implementacion local 2026-09-10]] — SQL y coste autorizados; PWA verificada localmente, banco remoto exclusivo en pruebas antes de publicar.
- [[G6 - conciliacion real preparada (2026-09-11)]] — 218 inversiones reales conciliadas y conformidad humana/financiera recibida para el corte del 11/09. G6 cerrado; los diez enlaces pendientes se completaron después en F8.
- [[F7 - publicada y apagada (2026-09-11)]] — informe Empresas publicado y SQL instalado OFF; pruebas específicas PASS, cero regresiones sobre los 57 fallos de la matriz general, banco cerrado; G6 cerrado el 13/09/2026.
- [[F7 - informe multiempresa en sombra preparado (2026-09-11)]] — historial de construcción, decisiones, revisiones y autorizaciones previas a la publicación.
- [[F6 - cierre y ajustes publicados (2026-09-11)]] — últimos ajustes publicados y verificados, revisión manual cerrada con VoiceOver omitido; F4/F5/F6 apagadas y F7 siguiente.
- [[F6 - publicada y apagada (2026-09-10)]] — historial de instalación y 43 pruebas remotas PASS; observaciones RLS/Auth. La publicación de los últimos ajustes quedó resuelta el 11/09; F7–F9 siguen pendientes.
- [[F6 - conflicto HTTP y ensayo remoto (2026-09-10)]] — corrección PT409, pruebas y límites.
- [[F6 - implementación de postventa (2026-09-10)]] — decisiones e implementación inicial.
- [[F5 - instalada y apagada (2026-09-10)]] — SQL autorizado instalado y verificado; banco temporal eliminado, datos conservados.
- [[Citas Gerencia - cierre de sesion y punto de retoma 2026-09-09]] — publicado, avance guardado y respaldo privado; pendientes de revisión visual y mantenimiento del banco general.
- [[Solicitud de tasa en el lead - publicada 2026-09-09]] — aprobación antes de convertir publicada; banco temporal cerrado y verificaciones registradas.
- [[RETOMAR-64 - CARTERA F4 terminada y avance guardado (2026-09-08)]] — punto de retoma vigente, commits y respaldo privado; sigue F5.
- [[F4 cerrada - comisiones fuera del sistema (2026-09-08)]] — F4 técnica terminada; comisiones externas excluidas del sistema. Sigue F5.
- [[F4 multiempresa - reconstruccion, finanzas y lectura vigente (2026-09-08)]] — candidata técnica probada y guardada; G4 cerrado según la decisión de comisiones externas.
- [[UX1 y UX2 Gerencia - componentes y revision visual 2026-09-06]] — catálogo reutilizable y nueva revisión de Resumen/Conversiones; pendiente de revisión visual y validación humana de F0.
- [[Organizacion local y Figma - UI UX Gerencia 2026-09-06]] — carpeta `UX-UI-GERENCIA`, índice de Figma, estado de F0 y preparación de UX1.
- [[Rol Analista]]
- [[Rol Directorio]]
- [[Fusión asesor-analista]]
- [[Clave temporal = DNI]]
- [[Notificaciones de pagos]]
- [[Importador de clientes]]
- [[Gestión comercial de clientes - renovaciones y upgrades]]
- [[Nucleo de conversion - diagnostico de llegadas y asignaciones 2026-09-04]]
- [[Plan de correccion de metricas de Gerencia - requerimiento vigente]] — cinco puntos acordados, restricciones y punto de reanudación.
- [[Inventario de indicadores de Gerencia - Contrato de lectura]] — significado, fuente, período y límites de cada indicador; entregable documental del punto 1.
- [[Correccion de pantallas de Gerencia - punto 2 - 2026-09-04]] — correcciones implementadas, verificadas y publicadas; alcance y límites.
- [[Correccion de Cartera - punto 3 - conciliacion y SQL pendiente 2026-09-04]] — punto 3 completado: SQL aplicado y frontend publicado. Cifras conciliadas, pruebas y reversión.
- [[Main unico - sincronizacion y publicacion 2026-09-04]]
- [[Publicacion frontend metricas Gerencia 2026-09-04]] — todo guardado; frontend publicado desde `50f33a5`, archivos y acceso de Gerencia verificados. Los puntos 4–5 siguen pendientes.
- [[Datos faltantes de Gerencia - punto 4 - decision pendiente 2026-09-05]] — justificación histórica de las cuatro necesidades; alcance aprobado e implementación local completada después.
- [[Plan por fases - cuatro datos de Gerencia - aprobado 2026-09-05]] — N1–N4 implementados y auditados localmente; falta confirmar/aplicar SQL, versionar, sincronizar y publicar.
- [[Contrato tecnico de ampliaciones N1-N4 de Gerencia - 2026-09-05]] — contrato, huellas, migración, rollback y evidencia final. Título comercial acordado: «Resultados de los leads del mes».
- [[Auditoria final de Gerencia - punto 5 - avance 2026-09-05]] — ampliaciones y animación verificadas localmente con núcleos intactos; faltan las puertas productivas y el commit final.
- [[Cierre productivo de metricas de Gerencia - ejecucion 2026-09-05]] — ejecución autorizada de los seis pasos; preflight actual comprobado, SQL exacto pendiente de confirmación y publicación todavía no realizada.
- [[Identidad unificada de inversionistas - plan pendiente]]
- [[Handoff plan maestro multiempresa aprobado para firma F0 (2026-09-01)]]
- [[Incidente y restauracion Ficha 360 2026-08-31]]
- [[Nombres en mayúscula]]
- [[Interés compuesto]]
- [[Realtime de novedades]]
- [[Bug de fechas UTC]]
- [[Reporte diario de derivaciones para Coordinación]]
- [[Auditorías del portal]]
- [[Citas Gerencia - auditoria de conexion a nucleos 2026-09-11]] — auditoría de backend/frontend: lector fuera del núcleo, caché pendiente y nuevas metas/proyección aún sin conexión; 97 pruebas y TypeScript pasados, gate del servidor fallido.

**Herramientas independientes:**
- [[SubLínea — subtítulos locales para X]]

## 👤 Reglas de trabajo con Miguel

- Miguel **no es desarrollador** (analista comercial). Explicar en **lenguaje natural**, sin jerga.
- **Versiones de desarrollo:** usar siempre la **última versión estable** disponible del lenguaje, framework y dependencias aplicables. Antes de implementar, verificar las versiones y la documentación vigente con Context7. Si una actualización rompe compatibilidad con el proyecto, explicar el impacto y acordar la migración antes de aplicarla.
- **Cambios de base de datos:** mostrar el **SQL primero** y esperar confirmación.
- Lo **visual** decláralo explícito para que Miguel lo pruebe; las **capturas** son el input principal de debugging.
- **Deploy manual** a Hostinger (copiar a la carpeta espejo) + subir `?v=N` del módulo editado.
- Máximo 3 intentos automáticos; si sigue fallando, escalar con explicación clara.

- [[Notificaciones de tasa - publicadas 2026-09-11]] — Avisos de tasas activos en la PWA; falta permiso y prueba del teléfono.
