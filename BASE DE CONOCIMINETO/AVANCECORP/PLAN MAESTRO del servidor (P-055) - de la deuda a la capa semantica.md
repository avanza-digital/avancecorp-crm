# PLAN MAESTRO del servidor (P-055) — de la deuda a la capa semántica

Código para retomar: **`RETOMAR-SERVIDOR`** · Escrito el 2026-08-28 · Reemplaza como plan vigente a [[Plan de saneamiento del servidor (P-053) - implementacion por tandas]] y a [[Capa semantica del servidor - plan por nucleos (episodios)]] (ambos siguen valiendo como detalle técnico). Inventario de origen: [[Auditoria servidor Supabase - duplicacion y deuda (2026-08-28)]].

Producido con tres arquitecturas independientes, un crítico de cobertura y **una auditoría adversarial de Codex** que refutó dos conclusiones mías antes de que llegaran al plan.

---

## 📍 ESTADO — se actualiza al final de cada sesión

**Fase actual:** **FASE 2** — el 10/09 solo queda mirar el primer sellado. **FASES 0, 1, 3, 4, 5.a y ahora la 6.a EN PRODUCCIÓN.**

**🆕 FASE 6.a EN PRODUCCIÓN (30/08 tarde) — «el núcleo de citas y el censo sellado».** Registro **182**. La medición cambió el plan a mejor: **el núcleo de leads ya existía** (`conversion_episodios`, de la «conversión única») y las pantallas beben de él directa o transitivamente (el SELLO incluido, verificado); lo que faltaba era el **núcleo de CITAS** (nació hoy: `private.citas_episodios`, la pantalla de reuniones lo consume con el payload idéntico byte a byte) y la **gobernanza**: censo por LLAMADA con **30 contadores declarados y sellados por huella** (las mixtas también, sin pases automáticos), tope 30 que solo baja, sello de lista, vigía 06:49 con tabla de alertas propia y `npm run gate:analitica` con **mutante de 10 filos en verde contra producción**. Dos auditorías, dos NO-GO atendidos enteros — el P0: **el vigía escribía en una tabla inexistente, y el de la F5.a tenía el mismo defecto vivo** (reparado aquí). Y la **F6.b de rótulos quedó HECHA en el código** el mismo día («Leads que llegaron a cita» / «Cosecha por analista»; 2439/2439) — **pendiente solo de `/release-crm`**, que invoca Miguel. Quedan las **dos deudas declaradas** en las exenciones (la conversión de cohorte de series y el numerador local de registrar_ajuste). ⏳ **Firma pendiente de Miguel:** la relectura de la decisión 5 (los 45 días eran de la VISTA, no de la métrica).

**🆕 FASE 5.a EN PRODUCCIÓN (2026-08-30) — «una sola pregunta: ¿es analista vigente?».** Registro **181**. Cierra la *revocación a medias* que se midió el 29/08, y la cierra por el molde de la Fase 4: **un solo sitio decide y un trinquete impide que nazca el siguiente**. Verificado en vivo: la persona revocada pasó de **3 contratos / 39 cuotas / 3 fichas / 1 co-titular / ficha 360 con banca / selector de productos** a **cero en todo** (y 42501 en el selector); una analista **activa** sigue con sus 58 contratos, 549 cuotas, 44 fichas y su ficha 360 intactos. Advisors **0 ERROR**. Gate `npm run gate:vigencia` en verde contra producción y su **mutante cazado por los siete filos**.

**Qué se cerró, y por qué era más ancho de lo que parecía:** no eran 4 políticas sino **SIETE puertas**. Además de contratos, cuotas, fichas y su edición, seguían abiertas la **ficha 360 completa** (`crm.cliente_detalle_fn`: DNI, correo, teléfono, domicilio y **banca en PEN y USD**), los **co-titulares** (`public.puede_ver_contrato` → `contrato_titulares` y `contrato_tiene_pagos`) y el **selector de productos**. Cerrar solo las políticas cerraba la *enumeración*, no el *acceso dirigido*: con los identificadores que su propia pantalla le mostró el día anterior, seguía sacando las fichas.

**Tres cosas que salieron por el camino y no eran de esta fase:**
1. 🔴 **`private.membresia_crm_revocada()` no tenía permiso para `authenticated`.** La única política que ya la usaba —la del historial de reasignaciones, de la **F3.4**— **nació muerta**: reventaba con 42501 **incluso para gerencia**. Ya está reparada; ahora esa tabla se lee como la F3 escribió.
2. 🔴 **Borrar la fila de `crm.equipo` convertía a un REVOCADO en AJENO** y le devolvía los accesos del Portal. Decisión de Miguel (30/08): **«vamos con la 1, mantén el candado»** → `crm.equipo` tiene candado `BEFORE DELETE`, y la baja deliberada sale por una **puerta declarada** (`crm.purgar_membresia_crm(perfil_id, motivo)`): **solo llave de servidor**, motivo escrito y **lápida** en `private.membresias_purgadas`. **Consecuencia asumida:** el borrado duro de un colaborador desde el panel deja de funcionar; la baja es desactivar. Se adaptaron los dos programas que borraban: `test-rls.mjs` y `clean-crm-data.mjs`.
3. 🔴 **`perfiles.creado_en` es INMUTABLE** — un trigger lo restaura en silencio. Rejuvenecer una ficha para probar la ventana de 5 h **no ocurre** y el caso positivo medía 0 filas por un defecto del oráculo.

**El trinquete, y por qué el primero no valía:** medía **texto**, así que bastaba un comentario (`-- ya migrado`) para desaparecer del radar, una puerta **mixta** no salía y **tres exenciones casaban por accidente** con el nombre de la tabla `crm.reasignaciones_analista`. Ahora mide **llamadas** (sin comentarios, con inicio de palabra y paréntesis), vigila también el **rol comprobado a mano**, mira **vistas y procedimientos**, y cada exención va **sellada con la huella de su cuerpo**: si esa función cambia, su razón caduca y el gate se pone rojo. Quedan **9 puertas declaradas, tope 9, 0 sin declarar**, con vigía diario (`crm-vigencia-analista-vigia`, 06:39).

**✅ Y la sesión, cerrada el mismo día (30/08).** La F5.a quitaba los datos, no la sesión. Se cerraron **las cuatro**: perfil del Portal apagado, **sesiones cerradas** (14 abiertas entre todas), llaves de renovación anuladas —sin eso una pestaña abierta se renueva sola— y **entrada bloqueada** (`banned_until`). Detalle: **IVETT TEEVIN** es la única persona real; las otras tres (`avancecorp26+crm-gerente/analista/supervisor`) son **cuentas de prueba del propio Miguel**, y él decidió cerrarlas también. Guiones: `scripts/cerrar-sesion-revocada-ivett.sql` · `scripts/cerrar-sesion-demos-crm.sql` · **reapertura** de las de prueba en `scripts/reabrir-cuentas-demo-crm.sql` (no toca a Ivett a propósito). Sigue abierto, y no lo cierra ninguna fase todavía: un enlace de PDF firmado ANTES de la revocación vale 300 s más.

**Lo que bloquea:** nada. Ninguna pregunta abierta.

**🔬 EL CIERRE YA SE ENSAYÓ (29/08), sin esperar al 10/09 y sin escribir una fila:** el cierre real de agosto, ejecutado contra producción dentro de un bloque que se deshace solo. **Funciona** — 48 ms, 18 personas, y todos los candados rebotan como deben. El reloj que lo dispara está vivo y sano. **Lo que salió:** agosto se sellará como **mes parcial** porque el registro de leads empieza el 17/08 — la conversión de agosto cubre 15 de 31 días. Eso es una decisión tuya, no un fallo. Detalle en la Fase 2.

**🆕 FASE 1.4 — «la regla que obliga a las que vengan» (29/08).** El arquitecto de servidor de Miguel señaló que la Fase 1 dejó su meta a medias. Medido: de sus tres ejemplos, **dos se refutan** (`operaciones_cartera` NO puede cambiar —candado append-only + solo `SELECT` por API—; `usuario_eventos` y `novedades_leidas` son del 7 y el 21 de agosto, no posteriores al 28) y **el punto estructural es correcto y es el bueno**: no existía regla que obligara a las tablas futuras. Escrita en `20260829230000_crm_f1_4_regla_de_auditoria.sql` con TRES FILOS — `private.tablas_sin_rastro()` (la regla en el servidor, con lista blanca en `private.auditoria_exenciones` y CHECK de razón ≥ 40 caracteres) · vigía diario por pg_cron (**sustituye al event trigger: `postgres` NO es superusuario aquí**) · `npm run gate:auditoria`, que además compara la lista blanca VIVA con la del repo. Cierra los 3 huecos reales (`operaciones_cartera`, `agenda_ics`, `suscripciones_push`), las dos últimas con un auditor que **enmascara secretos** porque `audit_log` lo lee cualquier `es_admin()`. **✅ EN PRODUCCIÓN el 29/08**, en dos migraciones (registro **179**): la F1.4 y la **F1.5**, que corrige lo que la auditoría rompió ANTES de publicar. 🔴 Tres bloqueantes que valieron la auditoría: (a) **el canal `db query` NO transporta los `raise notice`** → el gate buscaba su «OK» en un aviso y NUNCA habría podido ponerse verde; ahora el veredicto viaja como FILA; (b) el mutante **confirmaba** su DDL de prueba en producción → ahora termina en `raise exception` y se deshace entero; (c) **la regla solo miraba «¿hay trigger?»**, no «¿audita?» → medidas **9 tablas** con auditoría a medias (metas y SLA sin UPDATE/DELETE, ledgers de asignación sin DELETE), ahora exige trigger activo, por fila, auditor **por OID** y los tres verbos, y la migración completó las nueve. Verificado en vivo: 0 sin rastro · 45 tablas auditadas (antes 42) · sello cuadrado · vigía activo 06:29 · advisors **0 ERROR** · gate+mutante en verde contra producción · humo del flujo real del portal sin fugas y sin ruido. Commits `9c31fdd` · `90b4590` · `0aa19b2`.

**Y la F1.6 (registro 180), tras el NO-GO de Codex:** de sus 9 hallazgos, 6 ciertos y arreglados, 2 ya resueltos y 1 parcial. Lo gordo: **la regla aceptaba vigilantes decorativos** (en modo réplica, BEFORE, con `UPDATE OF` parcial o anulados por un `WHEN (false)`) y **el mutante probaba las piezas, no el gate** — se podía romper el gate y seguir verde. Ahora el gate entero vive en `private.assert_auditoria()` y los **cinco** filos del mutante ejecutan esa misma función. ⚖️ Dos correcciones suyas hubo que cambiarlas AL MEDIR (él no pudo leer producción): exigir `search_path` vacío habría puesto en rojo media base (`log_audit_change` vive con `'public, pg_temp'`), y prohibir el `WHEN` habría marcado como rota a `cronograma_pagos`, que lo usa a propósito → se permite pero **declarado** en `private.auditoria_condicionada`. Además el enmascarado deja de ser un oráculo (`***` plano) y tapa `user_agent`/`dispositivo`. Commit `68b3f2e`.

**🆕 HALLAZGO DEL 29/08 — EL CONFLICTO DE ADMIN (lo intuyó Miguel, se midió).** Conviven **TRES** definiciones de autoridad: el rol del Portal (24 funciones), la membresía del CRM (**114**) y 6 híbridas que las mezclan. Hay **funciones gemelas** con el mismo nombre en los dos esquemas y criterios distintos, así que el poder depende de por dónde se entre. 🔴 **Lo urgente: una revocación a medias** — una analista con la membresía del CRM apagada sigue activa en el Portal y las políticas de tabla solo miran eso, de modo que **sigue leyendo contratos, cronogramas y fichas de sus clientes** aunque las funciones se lo nieguen. Informe: [[Las tres definiciones de autoridad (2026-08-29)]]. **Encaja en la Fase 5**, en 3 pasos.

**👉 DÓNDE SE RETOMA:** lo que falta, en orden:

1. **10/09 — media sesión de vigilancia (Fase 2):** ver que el disparo automático de las 09:20 selle agosto igual que el ensayo y **guardar la copia del mes**. Agosto sella como **mes parcial** (el ledger de leads empieza el 17/08): es consecuencia del dato, no un fallo.
2. **Publicar el front con `/release-crm`** (lo invoca Miguel): lleva los rótulos de la F6.b ya hechos y verdes. Después, las 2 deudas declaradas (series y registrar_ajuste) cuando toque.
3. **Fase 5 — cerrar puertas** (permisos muertos + el conflicto de las tres autoridades; ~2 sesiones. **La revocación a medias se puede adelantar sola**: es el único punto con efecto sobre datos reales hoy).
4. **Fase 7 — ordenar la casa** (retiros REVOKE→observar→DROP, con OK de Miguel por pieza).
5. **Fase 8 — un solo idioma** (renombre «analista», al final, por el orden seguro).

**Menor, de la Fase 4:** re-medir Conversiones a escala de 10 000 leads y pasar trinquete+gate en el próximo ciclo de banco.

**Nota operativa del 29/08 (fuera del plan):** **CARLOS VALLES pasó de Directorio a Gerencia.** El candado de la Fase 1 amarra el par de identidades (Directorio en el Portal ⇒ Directorio en el CRM), así que el cambio exigió el orden: bajar la membresía → mover el rol de Portal (`directorio`→`admin`, que NO tiene UI) → poner `gerencia` → volver a subirla, todo en una transacción con los candados activos. Se eligió `admin` y no `comercial` porque `es_admin()` es lo que gatean cerrar/actualizar contrato, los productos de inversión y `es_gestor_cartera`; además conserva el tablero de Directorio del Portal (`es_directorio() OR es_admin()`) y **no** recibe superadmin: la llave que asigna roles CRM sigue siendo de una sola persona. Guion reutilizable en `supabase/scripts/carlos-valles-directorio-a-gerencia.sql` (+ `…-verificar.sql`). Efecto colateral: bajar la membresía rota el token de agenda ICS.

| Fase | Estado |
|---|---|
| 0 · Decidir | ✅ **cerrada** — 21 decisiones, cero preguntas abiertas |
| 1 · Proteger lo que ya tienes | ✅ **EN PRODUCCIÓN** — 3 migraciones aplicadas y verificadas · **F1.4 + F1.5 EN PRODUCCIÓN (29/08): la regla que obliga a las tablas futuras, con 9 auditorías a medias completadas** |
| 2 · Mirar el primer cierre | 🟡 **lo único vivo** — el 10/09, media sesión: mirar el sello automático y guardar la copia (ensayado 3 veces) |
| 3 · Que cada venta tenga dueño | ✅ **EN PRODUCCIÓN** (29/08) — migraciones 156→166, front desplegado, obligatoriedad viva |
| 4 · Una sola calculadora de capital | ✅ **COMPLETA EN PRODUCCIÓN** (30/08) — núcleo + 16 consumidores + motor del sello + **trinquete en CERO**; el ensayo del cierre viejo-vs-nuevo dio foto sellada idéntica |
| 5 · Cerrar puertas | 🟡 **5.a EN PRODUCCIÓN (30/08)**: la revocación a medias, cerrada por «una sola pregunta» + trinquete + candado de borrado (7 puertas, registro 181). **Quedan los pasos 2 y 3**: una sola pregunta por capacidad (retirar la puerta gemela que sobre) y decidir el par de cada persona ([[Las tres definiciones de autoridad (2026-08-29)]]). Y, fuera de la fase: **cerrar la sesión de los revocados**, que las puertas de datos no cierran |
| 6 · Las otras dos calculadoras | 🟡 **6.a EN PRODUCCIÓN (30/08)**: núcleo de citas + censo sellado de 30 contadores + trinquete/vigía/gate (registro 182). El núcleo de leads YA existía y el sello bebe de él por transitividad (verificado). **Queda la 6.b**: rótulos del front (dos preguntas de «citas» con su apellido, `conversion_cohorte` en series) y las 2 deudas declaradas |
| 7 · Ordenar la casa | ⚪ sin empezar |
| 8 · Un solo idioma | ⚪ sin empezar |

**Lo que quedó protegido el 28/08:** el rastro de quién toca los co-titulares, el historial de gestión y las cuotas · 16 casillas de dinero blindadas contra valores imposibles antes del primer cierre · las puertas que la seguridad por filas no gobierna, cerradas.

**Git:** todo subido al remoto (`avancecorp/wip/workspace-20260823-completo`, 35 commits el 29/08; incluye la integración de la rama paralela `fb7e53d`).

**Para retomar en una sesión nueva:** decir **`RETOMAR-SERVIDOR`**. Con eso se carga este plan, las decisiones ya tomadas y el punto exacto donde quedó.

### Lo que hay escrito de la Fase 1, archivo por archivo

| Archivo | Qué hace |
|---|---|
| `migrations/20260828190000_…rastro_titulares_gestion_cuotas` | Deja rastro de quién toca los **co-titulares** de una cuenta mancomunada, el **historial de gestión** del cliente y del lead, y el **alta y la baja de cuotas** |
| `migrations/20260828190500_…malla_anti_nan_montos` | **16 guardianes** que impiden que entre un monto inválido al cronograma de pagos y a las tres tablas del cierre de mes |
| `migrations/20260828191000_…puertas_baratas_anon` | Cierra los cuatro permisos que la seguridad por filas **no** gobierna en las 10 tablas, y las 5 consultas de administración |
| `scripts/rollback-f1-p055.sql` | La **marcha atrás**, con las definiciones vivas copiadas literalmente |
| `scripts/test-f1-puertas.sql` | La **aceptación**: caso bueno, caso malo y dos mutantes que rompen el arreglo para comprobar que la prueba lo nota |
| `snippets/NO-APLICAR-numeracion-automatica-contratos.sql` | El cerrojo de la numeración automática, **aparcado** por decisión tuya hasta que se necesite |

### Cierre de la sesión del 2026-08-28

**Qué se hizo:** auditoría completa del servidor (solo lectura, cero escrituras en producción) · este plan, con tres arquitecturas independientes, un crítico de cobertura y una auditoría adversarial de Codex · 14 decisiones de negocio tomadas · el ranking real de agosto verificado contigo.

**Qué NO se hizo:** ninguna migración, ningún despliegue, ninguna escritura en producción. El servidor está exactamente como estaba.

**Dos errores míos, corregidos y anotados para que no se repitan:** leí «analista» y «vendedor» como dos grupos distintos siendo el mismo equipo, y di por hecho que el mes se contaba por fecha de registro cuando el sistema ya usaba la fecha de cierre comercial. Los dos salieron a la luz porque Miguel preguntó y porque Codex refutó.

**Evidencia guardada fuera de esta nota:** `CRM-Avance-Corp/.tmp-verificar-atribucion-capital.mjs` — diagnóstico de solo lectura que compara quién registró contra quién trabajó el lead. Útil para la Fase 3.

**Acceso desde Obsidian:** el vault del proyecto quedó enlazado dentro del vault de `Documents` como carpeta `AVANCECORP`. Es un enlace, no una copia: hay un solo archivo.

### Cierre de la sesión 2 del 2026-08-28

**Qué se hizo:** la Fase 0 quedó cerrada. Las **7 preguntas** del §8 están respondidas y el plan pasa de 14 a **21 decisiones**. Se explicó qué es el AUM y se comprobó que ya vive en el sistema: el tablero de Directorio lo muestra por moneda con su variación y su captación del mes (`public_html/js/admin/directorio.js:91`).

**Qué NO se hizo:** ninguna migración, ningún despliegue, ninguna escritura en producción. El servidor sigue exactamente como estaba.

**Los tres cambios de rumbo respecto de lo que este plan asumía:**
1. **Se cae el filtro de equipo mensual** — agosto pasa de 115 a 123 unidades y el podio puede mostrar a quien ya no está. Es una decisión de negocio, no un descuido.
2. **El renombre va completo, por dentro también**, contra la recomendación de dos auditorías independientes. Queda anotado como elección consciente, con el orden seguro del §6 como condición.
3. **Los 12 contratos históricos se quedan sin dueño** en lugar de repartirse.

**Lo único que falta para arrancar:** tu visto bueno a la Fase 1.

---

### Cierre de la sesión 3 del 2026-08-28 — la Fase 1, escrita y ensayada

**Qué se hizo:** las **cuatro migraciones de la Fase 1**, en
`CRM-Avance-Corp/supabase/migrations/` (`20260828190000`, `190500`, `191000`,
`191500`), con su ficha completa en el ledger `MIGRACIONES.md`.

**Qué NO se hizo:** no se aplicaron. Producción sigue byte a byte como estaba
(comprobado al terminar: 9 co-titulares, 4252 cuotas, `crear_contrato` con su md5
original, cero auditores en `contrato_titulares`, `anon` con TRUNCATE).

**Cómo se probaron sin gastar un branch y sin escribir una fila:** las cuatro se
aplicaron **contra producción dentro de bloques que siempre terminan en error**,
así que todo se deshace solo. Con mutantes: se rompe el arreglo a propósito para
comprobar que la prueba lo nota. Un ejemplo de lo que eso demuestra: borrar un
co-titular deja su rastro con el documento; **quitando el trigger, no lo deja**.

**Dos auditorías independientes, las dos con hallazgos reales.** La de seguridad
por filas: 3 altos, 4 medios, 6 notas. La adversarial de Codex: veredicto
**NO-GO** con 4 graves. **Todo corregido**, y dos de sus hallazgos quedaron
refutados con evidencia medida, no con opinión.

**El fallo más caro lo encontró Codex, y era mío:** una comprobación de seguridad
que habría hecho **fallar siempre** la cuarta migración. La había añadido después
de la última prueba, así que nunca llegó a ejecutarse. Ya está corregida y, además,
probada al revés: se comprobó que la versión anterior efectivamente fallaba.

**La numeración automática sale de la Fase 1 (decisión tuya, 28/08):** no se
necesita todavía. El cerrojo estaba escrito y probado, pero reemplazar una
función viva del portal para proteger una rama que hoy no usa nadie es riesgo sin
beneficio. Y Codex encontró que esa rama necesita **cuatro** arreglos, no uno:
generaría `AC-2026-0001` cuando **ninguno de tus 466 contratos usa ese formato**
(todos son `2026-01-NNNNNN`), el año lo toma de una zona horaria que no es Lima, y
el número escrito a mano no se valida. Se deciden juntos el día que se encienda.
El trabajo queda guardado y anotado, fuera de la carpeta de migraciones para que
nadie lo aplique sin querer.

**Nada de esto necesita decisión tuya para avanzar:** la comprobación en el banco
de pruebas la hago yo, y su resultado por defecto ya está decidido (si el banco
se cayera, ese bloque no se publica y el resto sí).

**Dos fallos míos, cazados por esas pruebas antes de tocar nada:**
1. **Revocarle el permiso a «los visitantes sin cuenta» no revocaba nada.** Las 5
   consultas de administración estaban abiertas a *todo el mundo* (`PUBLIC`), no a
   `anon`; quitárselo a `anon` dejaba la puerta igual de abierta. Medido, no
   supuesto.
2. **Estuve a punto de borrar en silencio un filtro puesto a propósito** en el
   auditor de cuotas (auditoría del portal del 13/06). Sin él, el aviso
   automático diario de cuotas habría empezado a escribir una línea de auditoría
   por cada recordatorio enviado. Ahora el filtro se queda y el hueco —el
   borrado— se cierra con un trigger aparte.

**Lo que falta antes de publicar:** aplicarlas en un banco de pruebas, pasar el
gate de seguridad por filas y los advisors, y tu merge.


### Cierre de la sesión 5 (2026-08-29) — la Fase 3, de cero a producción en un día

**Qué se hizo:** la Fase 3 entera — escrita, auditada dos veces, corregida, publicada y
desplegada. El servidor pasó de 156 a **166 migraciones** (las 10 nuevas registradas CON su
cuerpo); el front nuevo (`crm-20260829T182429Z`) está vivo en crm.miavance.com; la
obligatoriedad está encendida. También se **ensayó el cierre de mes por adelantado** (sella
agosto en 48 ms; el camino de la deuda por anulación funciona y no cobra dos veces) y se
cerró de paso el hueco de la sanción de cooperativa con mes sellado.

**Las dos auditorías, con lo suyo:** el auditor RLS trajo 15 hallazgos (1 bloqueante: el
respaldo del rollback iba a `public`, legible con la llave anónima) y Codex un **NO-GO** con
10 (los 2 graves: la atribución era decorativa —el ranking no la leía— y los demos seguían
contando en el Directorio). **Los 25 corregidos y re-probados.** Gracias a eso el ranking
vivo ya da la cifra exacta de la tabla de este plan (Adelayda S/ 383 600).

**Decisiones nuevas de Miguel:** solo activos en el selector del alta (la venta vieja de
alguien que se fue entra por la reasignación de gerencia) · una anulación no elimina capital
de la empresa: es una sanción al analista, y ahora cae completa esté el mes abierto o sellado.

**Sorpresa del día:** una sesión paralela publicó dos migraciones y reemplazó
`crear_contrato` mientras se trabajaba. Las huellas lo cazaron (el preflight abortó solo),
se verificó que las anclas sobrevivían, se re-ancló, y la rama del vivo se integró ANTES de
construir el release (2439/2439 pruebas tras el merge). Las dos lecciones de la casa
—huella viva y rama del vivo como ancestro— pagaron su precio en el mismo día.

**Todo subido al remoto.** Commits del tren: `c10f5d6` · `6088501` · `99ad475`.

---

### Cierre de la sesión 4 (2026-08-28 → 29) — la Fase 1, publicada

**Qué se hizo:** la Fase 1 **está en producción**. El servidor pasa de 152 a 155
migraciones. Antes de publicar: banco de pruebas idéntico a producción, gate de
seguridad por filas **1185 de 1185**, advisors sin un solo error, marcha atrás
probada de verdad y banco borrado al terminar.

**Cómo se comprobó que de verdad se aplicó** — contando objetos y probando
comportamiento, no creyéndole al comando: 4 rastros nuevos vivos · 16 casillas de
dinero blindadas · 0 tablas con permisos que la seguridad por filas no gobierna ·
0 consultas de administración abiertas a visitantes, y las 5 vivas para el portal
· la función de crear contratos **intacta** (misma huella) · los datos sin tocar
(466 contratos, 9 co-titulares, 663 leads, 4252 cuotas). Y en vivo, con una sonda
que se deshace sola: el monto imposible rebota, el aviso automático no ensucia la
auditoría, borrar un co-titular deja rastro con su documento, cambiar la gestión
de un lead deja rastro.

**🔴 El botón de merge de Supabase dijo «éxito» y no hizo nada — dos veces.** Lo
cacé contando objetos. La causa quedó identificada y anotada. Se publicó por la
vía de siempre en este proyecto, migración por migración. **Secuela cosmética:**
en el panel de Supabase la rama principal figura como «migraciones fallidas»
aunque la base está sana y completa; si aparece en rojo, es eso.

**Un arreglo de paso:** el gate de seguridad se moría a mitad por un error de
programación mío del 28/08 (moría tras 650 comprobaciones verdes, sin llegar a
las del cierre de mes). Corregido y commiteado con lo demás.

**Commit `01dd52f`** — 9 archivos: las 3 migraciones, la marcha atrás, la
aceptación, el arreglo del gate, el ledger, este plan y el snippet aparcado.
Está solo en la máquina de Miguel; **no se subió al remoto**.

**Qué NO se hizo:** no se tocó nada del front, ni de las edges, ni de los datos.
La numeración automática sigue aparcada fuera de la carpeta de migraciones.

---

## 1. La problemática

El servidor funciona y el negocio opera. El problema no es que algo esté caído: es que **el sistema no tiene una sola versión de la verdad**, y eso ya empezó a costar decisiones.

**1. La misma cifra se calcula en muchos lugares distintos.**
El capital se calcula en **16 sitios**, la cantidad de leads en **21**, las citas en **6**. Cada pantalla lleva su propio cuaderno. Cuando dos no coinciden, nadie sabe cuál creer — y ya pasó dos veces este mes: el «Capital S/ 0» cuando había S/ 3,7 millones reales, y los dos contadores de leads que no cuadraban.

**2. Ninguna venta sabe quién la cerró.**
El sistema guarda quién *registró* el contrato, no quién lo *vendió*. En la mayoría coincide, pero no siempre: hay contratos cargados por administración o gerencia por encargo de un analista. Mientras eso siga así, **el ranking no puede ser exacto** y una futura comisión se calcularía sobre un dato aproximado.

**3. El mismo concepto tiene dos nombres.**
La misma persona es «analista» en el portal y «vendedor» en el CRM. No es cosmético: **en la sesión que produjo este plan, esa ambigüedad me hizo dar un diagnóstico comercial equivocado sobre datos correctos** — leí un grupo como si fueran dos.

**4. Datos con peso legal que se pueden cambiar sin dejar rastro.**
Los co-titulares de una cuenta mancomunada se pueden agregar o quitar sin que quede registro de quién ni cuándo, mientras el contrato al que pertenecen sí lo deja. Lo mismo con el borrado del historial de gestión de un cliente y con las cuotas de pago.

**5. Puertas abiertas heredadas.**
Permisos que vinieron de fábrica y nunca se recortaron, funciones viejas que ya nadie llama, dos contratos de prueba contando como producción real, y montos sin protección justo antes del primer cierre de mes.

**Por qué ahora:** se acerca el **primer cierre de mes real**. Las tablas que hay que blindar están hoy vacías — hacerlo antes de ese cierre no cuesta nada; después, sí.

---

## 2. El objetivo

Un servidor donde:

- **Cada cifra tiene una sola calculadora.** Preguntar «cuánto cerramos este mes» tiene una única respuesta, igual en todas las pantallas, y cambiar una regla de negocio se hace en un solo lugar en vez de dieciséis.
- **Cada venta tiene dueño.** Todo contrato sabe qué analista lo cerró, ese dato no se mueve solo, y se puede reasignar dejando rastro. El ranking de agosto en adelante es exacto y sirve para pagar comisiones.
- **Nada con valor probatorio cambia sin dejar rastro.** Ante un reclamo, la historia se puede reconstruir.
- **Todo se llama igual en todas partes.** Un solo idioma entre el CRM y el portal.
- **Y no vuelve a degradarse:** una prueba automática impide que nazca una calculadora paralela o que se rompa el idioma. Es la diferencia entre una regla escrita y una regla que se aplica sola.

Todo esto es **medible**: el §9 trae el tablero con el número de hoy y la meta de cada punto.

---

## 3. Decisiones tomadas por Miguel (2026-08-28)

| # | Tema | Decisión |
|---|---|---|
| 1 | **De quién es un contrato** | **Del analista que lo cierra.** El vínculo cliente↔analista es para que el cliente vea a su analista en la app; **no es la guía del ranking**. |
| 2 | **Campo «analista que cierra»** | **Se crea y es obligatorio desde ya.** Cuando registra un administrativo o un supervisor, tiene que **seleccionar el analista**; si no corresponde a nadie, lo pone a su nombre. **Debe poder reasignarse** después. El histórico se rellena con la regla de respaldo. |
| 3 | **Qué fecha define el mes** | **La fecha de inicio del contrato**, no la de registro. |
| 4 | **Cooperativas** | **Son parte del capital**: el núcleo lee contratos **y** cierres en cooperativas (solo vigentes; los anulados descuentan). |
| 5 | **Desglose renovado/adicional** | **Se completa**: hoy está vacío en las 62 operaciones aunque 53 dicen «completo». |
| 6 | **Contratos demo en producción** | **444444 y 888282 son demos** (de Kirk) → se excluyen de métricas y ranking. **001163 es de Adelayda** y cuenta para agosto; **001325 es de Miguel Briceño**. |
| 7 | **Catálogo de productos versionados** (6 funciones dormidas) | **Eliminar.** |
| 8 | **4 funciones esperando pantalla** | **Publicar las pantallas** (Mi cartera, Ficha 360°, período comercial). Salen de la lista de retiros. |
| 9 | **Botón «eliminar cliente»** | **Avisar** qué se va a borrar antes de hacerlo. |
| 10 | **Superadmin borrando perfiles** | **Queda abierto como hoy** — excepción consciente, con su consecuencia aceptada. |
| 11 | **Nomenclatura** | **«analista» en todo el sistema**, CRM y portal. *(Ver §6: Codex recomienda acotar el alcance interno; requiere decisión final.)* |
| 12 | **Tablero por analista** | **Se abre**, verificado contra el cuadro de agosto. |
| 13 | **Conexión `crm_metricas_bridge`** | No se sabe qué la usa → **investigar antes de retirar nada** que dependa de ella. |
| 14 | **Arranque** | **Nada se ejecuta hasta aprobar este plan.** |
| 15 | **Analista que ya no está en el equipo** | **Su venta cuenta igual.** Se elimina el filtro de la foto mensual: «necesitamos ver un historial». Efecto: agosto pasa de 115 a **123** unidades (vuelven los 8 que hoy quedan fuera) y el podio puede mostrar a alguien que ya no trabaja aquí — aceptado a propósito. |
| 16 | **Pipeline estimado** | **Métrica aparte, nunca sumada** al capital real. Lo firmado y lo esperado jamás comparten un mismo número. |
| 17 | **AUM** (capital gestionado, el que ya se ve en Directorio) | **Misma calculadora, cifra aparte.** Sale del mismo núcleo para que nunca se contradigan: el mes = lo que entró; el AUM = todo lo vigente. |
| 18 | **Los 12 contratos de mayo a julio** registrados por gerencia | **Se quedan sin dueño** y fuera del ranking histórico. El podio arranca limpio desde agosto. |
| 19 | **Alcance del renombre** a «analista» | **Completo, también por dentro** — con la recomendación contraria de dos auditorías a la vista. Se ejecuta por el único orden seguro del §6 (aditivo primero, migrar las 19 filas al final). |
| 20 | **Tipo de documento** (DNI/CE/Pasaporte) | **Una sola lista** para todo el sistema. Agregar un tipo nuevo se hace en un solo lugar. |
| 21 | **Borrar un perfil con historia en el equipo** | **Se impide:** hay que darlo de baja, no borrarlo. Acota la decisión 10 — el superadmin sigue pudiendo borrar, pero no a quien tenga historia de equipo, porque esa historia es la que sostiene la decisión 15. |

---

## 4. Los hallazgos que cambiaron el plan

### 4.1 La doble nomenclatura ya costó un diagnóstico

17 personas tienen a la vez `perfiles.rol='analista'` (portal) y `crm.equipo.rol_crm='vendedor'` (CRM), más 2 analista+supervisor. **No son dos grupos: son el mismo equipo.** Leerlos como grupos distintos me llevó a afirmar que «el capital lo registra el back office» y que «el CRM no captura la venta nueva». **Las dos afirmaciones eran falsas y quedan retractadas.**

### 4.2 Lo que Codex refutó de mi corrección

| Afirmación mía | Veredicto de Codex |
|---|---|
| (a) analista y vendedor son la misma persona | **Confirmada** — 17 + 2, verificado |
| (b) `creado_por` identifica a quien vendió | **Refutada como regla universal.** Reconstruyendo el asesor vigente al momento del alta desde `audit_log`: **7 contratos fueron registrados por gerencia para 3 asesores distintos**. El flujo de conversión ya separa explícitamente operador y asesor (`creado_por: callerId` vs `asesor_perfil_id: asesorId`). |
| (c) 465 de 466 registrados por el equipo comercial | **Confirmada, pero solo como distribución del registrador** — no demuestra quién vendió |
| (d) el mes se cuenta por fecha de registro | **Refutada — hallazgo principal.** El módulo vivo **ya usa `fecha_cierre_comercial`**, no la fecha de registro. Mi cuadro por «quién registró» difiere de la pantalla real en **15 de 18 personas** (S/ 6,53 M contra S/ 4,00 M). |
| (e) el núcleo debe atribuir por `creado_por` | **Refutada.** El núcleo vivo ya es **híbrido**: usa el analista explícito del lead si existe, si no el autor; exige pertenecer al **roster mensual** y suma los cierres en cooperativas. Agosto vivo = 118 − 8 (fuera del roster) + 5 (cooperativas) = **115 unidades**. |

**Conclusión de Codex, que coincide con lo que decidió Miguel:** conservar `creado_por` como *registrador* y **añadir una autoría comercial inmutable**. Ni `creado_por` ni la operación de cartera sirven solos.

**Dato relevante:** hoy **no existe módulo de comisiones** en el servidor (0 tablas, 0 funciones). El ranking no está pagando plata todavía — hay margen para hacerlo bien antes de que lo haga.

### 4.3 Cuánto se mueve el ranking según cómo se cuente

Producción de agosto de las tres primeras, según el criterio:

| Analista | Por fecha de registro | Por fecha de inicio | Definitivo (inicio + coop) |
|---|---:|---:|---:|
| Grecia Ramírez | S/ 1 170 600 | S/ 607 600 | **S/ 807 600** |
| Adelayda Gaspar | S/ 1 104 100 | S/ 366 600 | S/ 383 600 |
| Astrid Centenaro | S/ 653 100 | S/ 573 100 | **S/ 573 100** |

De 210 contratos registrados en agosto, **92 empezaron antes** (S/ 2,61 M, el 42 %). El podio cambia según el criterio: por registro, Adelayda es 2.ª; por fecha de inicio, cae al 5.º y sube Astrid.

⚠️ **Salvedad:** el ranking de arriba aún no aplica el filtro de roster mensual que el sistema vivo sí aplica (8 contratos quedan fuera). El núcleo debe decidir si ese filtro se conserva — está en las preguntas abiertas.

---

## 5. El diseño del capital

**Las tres reglas de la capa:**
1. **El núcleo no autoriza** — recibe la visibilidad resuelta, devuelve filas-hecho. En `private`, sin acceso desde la API.
2. **La ventana autoriza una vez** — un despachador por métrica.
3. **La pantalla no calcula** — solo suma, filtra y da forma.

**La regla que desbloquea todo:** las dimensiones con decisión abierta **viajan como columnas del hecho**. Así una respuesta tardía cambia números, no estructura.

**La fila-hecho de capital lleva:**
- El **analista que cerró** (campo nuevo, inmutable, reasignable con rastro)
- El registrador (`creado_por`), que se conserva y **no se pisa**
- Fecha de inicio del contrato (eje del mes) y fecha de registro (para auditar cargas tardías)
- Moneda (PEN y USD **nunca** se suman)
- Origen: contrato del portal o cierre en cooperativa
- Estado de anulación
- Marca de demo/prueba (para excluir 444444 y 888282 y los que vengan)

**Tres reglas más, que salieron de las respuestas del §8:**
- **Sin filtro de equipo** (decisión 15): la venta entra al mes aunque el analista ya no esté. El hecho guarda si estaba o no en el equipo ese mes, como columna, por si algún día se quiere separar el podio del capital — pero por defecto no descuenta nada.
- **El pipeline no vive en este hecho** (decisión 16). Es otra métrica, con su propia ficha.
- **El AUM sale del mismo núcleo** (decisión 17), como una consulta distinta: el mes pregunta «qué entró en este período», el AUM pregunta «qué está vigente hoy». Una sola calculadora, dos preguntas.

---

## 6. La campaña de nomenclatura — con el veredicto de Codex

**Inventario corregido por Codex:** 10 columnas, 4 tablas, 13 funciones, 17 índices con el término en el nombre; **54 funciones** con el literal; **7 políticas** que comparan el valor (no 18: las otras solo lo mencionan); **3 CHECK** (no 6); 19 filas de equipo; 3 236 apariciones en 218 archivos del CRM (228 son literales, 3 008 son identificadores y textos). **El portal desplegable tiene 0 apariciones.**

**Lo que rompería, por gravedad:**

| Nivel | Qué se rompe |
|---|---|
| **P0** | Si se migran las 19 filas primero, `crm.mi_acceso_fn` no reconoce el rol y devuelve **«revocado»**: el CRM deja de dejar entrar a todo el mundo. |
| **P0** | `vendedor_ids_visibles` cae a su rama vacía y `roster_metas_vendedores` devuelve nada: **leads, ranking y metas en blanco**. |
| **P0** | La edge de conversión rechaza al rol nuevo con **403**, y `ciclo-contratos` deja de enviar avisos a esos analistas. |
| **P0** | **Colisión de significados:** `perfiles.rol='analista'` habilita el portal; el nuevo `rol_crm='analista'` significaría fuerza de ventas. Además hay 2 vendedores del CRM cuyo rol de portal es `comercial`. |
| **P1** | Renombrar columnas, tablas o funciones **cambia las direcciones de la API**: los navegadores con la versión vieja reciben errores. |
| **P1** | La edge de usuarios llama por nombre a `registrar_vendedor_usuario_fn`, y la hoja de leads manda la clave `vendedor_correo`. |
| **P2** | Los tres gates de pruebas usan el literal: quedarían verdes probando el mundo viejo. |
| **P3** | Los 17 índices solo tienen el término en el nombre: renombrarlos no cambia nada. |

**Recomendación de Codex:** cambiar **solo lo que se lee** a «Analista» y conservar `vendedor` como contrato interno estable. Es la única variante sin indisponibilidad y sin compatibilidad eterna.

**El renombre interno se mantiene** (decisión 19, confirmada el 28/08): el único orden seguro es: aditivo en la base (aceptar ambos valores) → edges que aceptan ambos → CRM que lee ambos → recién ahí migrar las 19 filas → y la limpieza final **solo** con un gate de versión que fuerce recarga y telemetría que pruebe que no queda nadie en la versión vieja.

---

## 7. El plan por fases

*El plan no lleva fechas de calendario: lleva **orden** y **esfuerzo**. El único anclaje real es el cierre de mes, que corre el día 10 — dos fases dependen de él y está dicho en cada una. Todo lo demás avanza al ritmo que tú marques.*

### FASE 0 · Decidir — ✅ CERRADA (2026-08-28)
Las **7 preguntas** del §8 están respondidas —4 de capital y 3 estructurales— y son 21 decisiones. Falta solo aprobar el arranque de la Fase 1.

**Por qué hoy y no «esta semana»:** la Fase 1 tiene que estar publicada antes del próximo cierre de mes. Si esto se corre, la Fase 1 entra al cierre a medio hacer.
**Por qué las de capital también van aquí:** decidir no compite con ejecutar. Se pueden contestar mientras corren las fases 1 a 3; si llegan recién cuando arranca la Fase 4, la Fase 4 arranca frenada.
**Al terminar:** ninguna fase se detiene a mitad de camino esperando una respuesta.
**De ti:** una conversación.

---

### FASE 1 · Proteger lo que ya tienes — ✅ **EN PRODUCCIÓN (28/08)**, commit `01dd52f`
- Que quede registro de quién agrega o quita un co-titular de una cuenta mancomunada. Hoy no queda ninguno, y es el dato con más peso legal del sistema.
- Que quede registro de quién borra el historial de gestión de un cliente y quién borra cuotas de pago. Hoy tampoco.
- Blindar los montos para que no pueda entrar un valor inválido al cronograma de pagos ni al cierre mensual.

- **Cerrar los permisos baratos que no tocan el portal vivo:** quitarle a los visitantes sin cuenta el acceso a 5 consultas de administración y el permiso de vaciar tablas enteras — ese último la seguridad por filas no lo gobierna. *(No filtran nada hoy: son de solo lectura y la seguridad por filas las deja en cero. Se adelantan porque cuestan cinco minutos, no porque estén sangrando.)*
- **Poner guarda a la numeración de contratos.** El generador automático calcula «el último + 1» sin candado. *(Hoy es una rama muerta: los 466 contratos usan numeración manual, cero autogenerados. Se arregla ahora porque es chico, independiente, y el día que se encienda con dos altas simultáneas da un error feo al usuario.)*

**Por qué ahora:** esas tablas hoy están vacías, así que blindarlas no cuesta nada. Una vez que el primer cierre las llene, sí cuesta.
**Al terminar:** ningún dato con valor probatorio se puede cambiar sin dejar rastro.
**De ti:** revisión y merge a producción. **Duración:** 2 sesiones.

> ✅ **HECHO.** Publicado el 28/08 con tu autorización; verificado por conteo y por
> comportamiento. **La numeración automática salió de esta fase** por decisión tuya:
> el trabajo queda escrito y guardado en `snippets/`, fuera de migraciones, hasta el
> día que se necesite. Lo demás entró completo.

---

### FASE 2 · Mirar el primer cierre de mes — la semana del cierre
Semana de quietud: no se publica ni una sola modificación. Se observa que el cierre corra bien y se guarda una copia de ese mes como referencia para verificar todo lo que venga después.

**Qué se mira, en concreto** (añadido el 29/08, ya con la Fase 1 viva):
1. Que el cierre **selle el mes sin error** y las cifras cuadren con lo que se ve en pantalla.
2. Que **las 16 casillas nuevas de dinero no rechacen nada legítimo** — están puestas para frenar valores imposibles, no ventas reales.
3. Que **los cuatro rastros nuevos no hayan llenado la auditoría de ruido** desde el 28/08.
4. **Guardar la copia del mes** como referencia para verificar todo lo que venga después.

**Por qué:** si algo falla en el cierre, quiero saber que fue el cierre y no un cambio nuestro.
**Al terminar:** el primer cierre real, ejecutado y observado.
**De ti:** revisión y merge (ninguno esa semana, por diseño). **Duración:** media sesión de vigilancia.

> ✅ **ENSAYADA POR ADELANTADO el 29/08 — el cierre de agosto YA se probó.** No hizo falta
> banco: se copió la función viva del cierre, se le movió **solo el calendario** (los dos
> candados de fecha) y se ejecutó **el cierre real de agosto contra producción** dentro de un
> bloque que se deshace solo. Resultado: **sella en 48 ms, 18 personas, 17 medibles**;
> cerrar dos veces rebota; sellar hacia atrás rebota; un monto imposible rebota (la malla de
> la Fase 1 funciona *dentro* del cierre); y la pantalla de gerencia pasa de «cierra el
> 10/09» a «último cerrado: agosto». Producción quedó intacta (0 meses sellados, 466
> contratos, la función del cierre con su huella original).
>
> **El reloj está vivo:** `crm-cierre-mes-diario` corre **todos los días a las 09:20 de Lima**,
> 14 corridas y 14 éxitos, la última hoy. El 10/09 disparará solo.
>
> 🔴 **LO QUE ENCONTRÓ EL ENSAYO — decisión tuya:** agosto se va a sellar marcado como
> **mes parcial**. El registro de reparto de leads **empieza el 17 de agosto**: entre el 1 y el
> 16 hay **cero** repartos anotados. Así que el porcentaje de conversión de agosto se calcula
> sobre **15 de los 31 días**. El sistema lo dice solo y con todas las letras
> (`medible: false, motivo: mes_parcial`), no lo esconde — pero si esa cifra se va a usar para
> pagar, hay que decidir antes: sellar agosto como está con la marca, o dar agosto por no
> medible y empezar a contar conversión desde septiembre.
>
> Queda por ver el 10/09, y solo eso: que el disparo automático de ese día haga lo mismo que
> hizo el ensayo a mano.

---

### FASE 3 · Que cada venta tenga dueño — ✅ **EN PRODUCCIÓN (29/08)**
- Crear el campo **«analista que cierra»** en el contrato, obligatorio al registrar.
- Cuando registra un administrativo o un supervisor, tiene que **elegir el analista**; si la venta no es de nadie, va a su nombre.
- Poder **reasignar** después, dejando rastro de quién reasignó.
- Rellenar el histórico con la regla de respaldo y **marcar los dos contratos demo** para que dejen de contar.

**Al terminar:** el ranking de agosto en adelante es exacto, y ya no depende de quién tipeó.
**De ti:** confirmar los casos dudosos del histórico + revisión y merge. **Duración:** 2 sesiones.

> 🔨 **HECHA Y ENSAYADA (29/08), pendiente de auditorías y de tu merge.**
> Siete migraciones (`20260829180000`–`183000`) + el front del CRM (selector «Analista de la
> venta» en el alta, bloque de atribución con reasignar y su historial en el detalle).
> La cadena entera se probó contra producción dentro de un bloque que se deshace solo:
> el relleno deja **exactamente 15 sin dueño** (los 12 de tu decisión + 2 demos + 1 caso
> declarado), los demos **dejan de contar** (las métricas bajan exactamente lo que valían:
> S/ 100 000 + USD 100 000), la atribución **solo se mueve por la puerta con motivo** (el
> UPDATE directo rebota, y el mutante demuestra que el candado es real), y las 2353 pruebas
> del front pasan. Marcha atrás escrita con la versión original anclada por huella.
>
> **El único caso sin regla tuya:** el contrato `000180` (S/ 160 000, febrero), registrado
> por GLORIA (administrativa, nunca del equipo comercial). Quedó **sin dueño y declarado**;
> si quieres dárselo a alguien, es una reasignación con motivo, no una migración.
>
> ⛔ **Orden de publicación:** las 9 migraciones → el front → recién entonces la
> obligatoriedad (que vive aparcada en `snippets/APLICAR-TRAS-EL-FRONT-…`, imposible de
> publicar por accidente).
>
> ✅ **Las DOS auditorías, pasadas y corregidas (29/08 tarde).** La de seguridad trajo 15
> hallazgos (1 bloqueante) y la adversarial de Codex un NO-GO con 10 (2 graves); **los 25
> están corregidos y re-probados contra producción**. Los dos graves de Codex cambiaron el
> alcance a mejor: **el ranking y el sello YA leen al analista que cierra** (Adelayda queda
> con la cifra exacta de la tabla de este plan: S/ 383 600), y los demos salieron también
> del **Directorio y de los paneles de pagos** (no solo del CRM). La marcha atrás quedó
> probada de punta a punta: tren completo + rollback = producción byte a byte como estaba.
>
> ⚠️ Mientras se corregía, una **sesión paralela** publicó una migración que reemplazó
> `crear_contrato`; se detectó por las huellas, se verificó que las anclas sobreviven y se
> re-ancló. Queda una **pregunta chica para ti** (sin inventarte la regla): ¿el selector del
> alta debe seguir ofreciendo a quien ya no está en el equipo (hoy sale marcado «ya no
> está»), o solo a los activos?

---

### FASE 4 · Una sola calculadora de capital — después de la Fase 3
- Construir la calculadora única, que lee **contratos y cierres en cooperativas**, cuenta por fecha de inicio y descuenta lo anulado.
- Pasar las **16 pantallas** que hoy calculan capital por su cuenta a consumirla, en tres tandas, verificando que ningún número cambie ni un céntimo.
- Al final, las dos funciones que sellan el mes también leen de ahí — con una semana de margen antes de un cierre, porque ese cierre es su prueba de aceptación.

- **El candado sale con esta fase, no después:** la prueba automática que impide que nazca una calculadora paralela se activa a medida que cada pantalla migra. Sin fecha ni dueño sería solo una intención, y es la pieza que evita volver aquí en seis meses.

**Al terminar:** gerencia, el supervisor y el analista ven siempre el mismo número, y cambiar una regla se hace en un solo lugar.
**De ti:** revisión y merge de cada tanda (las respuestas ya vinieron en la Fase 0). **Duración:** 6–7 sesiones.

---

### FASE 5 · Cerrar puertas — después del cierre, sin compartir su semana
*(Lo barato y sin riesgo ya salió en la Fase 1. Aquí queda solo lo que toca el portal vivo y por eso no puede compartir semana con el estreno del cierre.)*
- Recortar los permisos que sí usan las pantallas del portal, dejando exactamente lo que necesitan. Va con una prueba completa del portal con cuenta real el mismo día, y con la marcha atrás escrita antes de publicar.
- Unificar las políticas de seguridad que repiten el chequeo de rol a mano en vez de usar la regla central.
- Limitar quién puede borrar un perfil, y poner el aviso en «eliminar cliente» antes de borrar.
- Arreglar el alta de usuarios con pasaporte corto, que hoy falla.

**Al terminar:** no queda ninguna puerta abierta que nadie esté usando.
**De ti:** revisión y merge. **Duración:** 2 sesiones.

---

### FASE 6 · Las otras dos calculadoras — después de la Fase 4
Lo mismo que la fase 4, para el conteo de leads (21 lugares) y de citas (6 lugares). Y un solo criterio de «producto seleccionable», que hoy está escrito tres veces: si alguien lo ajusta en una sola copia, CRM y portal ofrecerían catálogos distintos sin que nadie se entere.

**Al terminar:** las cuatro cifras del negocio tienen una sola fuente.
**De ti:** revisión y merge. **Duración:** 7–8 sesiones.

---

### FASE 7 · Ordenar la casa — sin dependencia dura
Índices que faltan y los que sobran, campos obligatorios donde el dato ya está siempre, listas de valores con un solo punto de verdad, corrección de 3 documentos que hoy quedan fuera de todo cruce, y retiro de lo que nadie usa (el catálogo de productos dormido incluido), siempre apagando primero y borrando después.

**Al terminar:** el servidor no arrastra piezas muertas ni reglas duplicadas.
**De ti:** una sesión corta para los 3 documentos y el visto bueno de cada retiro. **Duración:** 5–6 sesiones.

---

### FASE 8 · Un solo idioma — al final de todo
«Analista» en todo el sistema. Va al final a propósito: hacerlo a mitad de una verificación de cifras haría imposible saber qué cambió un número. El alcance depende de tu respuesta a la pregunta 5 de §8.

**Alcance decidido: completo, también por dentro** (decisión 19), con las dos auditorías recomendando lo contrario y esa recomendación a la vista al decidir. Queda anotado para que dentro de seis meses se sepa que fue una elección, no un descuido.

⚠️ **Lo que eso implica, sin adornos:** son 4 roturas de nivel P0 (§6) que hay que desactivar una por una — entre ellas, que el CRM deje de dejar entrar a todo el mundo si se migran las 19 filas de equipo antes de tiempo. Por eso el orden del §6 no es negociable: **aditivo en la base → edges que aceptan ambos → CRM que lee ambos → recién ahí migrar las 19 filas → limpieza final solo con telemetría que pruebe que nadie quedó en la versión vieja.** Cada paso se publica por separado y con su marcha atrás escrita.

**Al terminar:** el mismo concepto se llama igual en todas partes, por fuera y por dentro, y no vuelve a pasar lo que pasó en esta sesión.
**De ti:** revisión y merge de cada paso (son varios, pequeños, a propósito). **Duración:** 4–5 sesiones.

---

## ⚠️ Lo que este plan NO promete

**Durante octubre, los conteos de leads y de citas todavía pueden diferir entre pantallas.** El capital sí queda unificado para el cierre del 10 de octubre (la Fase 4 termina antes del 3 justamente para eso), pero leads y citas siguen calculándose en 21 y 6 lugares hasta que cierre la Fase 6, en el curso de octubre. «Diferir» quiere decir lo que ya pasó dos veces este mes: dos pantallas respondiendo distinto a la misma pregunta.

**El único escenario en que el capital también quedaría afectado** es que la Fase 4 no llegue antes del 3 de octubre. En ese caso no se toca el motor del cierre esa semana —regla del plan— y el cierre de octubre corre con la calculadora vieja, quedando la migración para el mes siguiente. Es un retraso, no una rotura.

**Ninguna fase dice «De ti: nada».** Todas piden tu revisión y tu merge a producción; el plan no toca producción sin eso. Planificar cero tiempo tuyo es la forma más rápida de terminar con tres días encima.

---

## 8. Las 7 preguntas — RESPONDIDAS (2026-08-28, sesión 2)

**Del capital:**

1. **El filtro de equipo mensual** → **se elimina.** La venta cuenta aunque el analista ya no esté en la foto del mes: «necesitamos ver un historial». Agosto pasa de 115 a **123** unidades. Contrapartida aceptada: el podio de un mes puede mostrar a alguien que ya se fue. *(Decisión 15. El hecho guarda igual si la persona estaba o no en el equipo, por si alguna vez quieres separar podio de capital sin rehacer nada.)*
2. **El pipeline estimado** → **dos métricas, nunca sumadas.** Lo firmado y lo esperado no comparten número. *(Decisión 16.)*
3. **El AUM** → **misma calculadora, cifra aparte.** El Directorio deja de llevar su cuenta propia: pide al núcleo «qué está vigente hoy», mientras el mes pide «qué entró». *(Decisión 17.)*
4. **Los 12 contratos históricos de mayo a julio** → **sin dueño**, fuera del ranking histórico. Nadie se lleva una venta que no se puede probar; el podio arranca limpio en agosto. *(Decisión 18.)*

**Estructurales:**

5. **Alcance del renombre** → **completo, también por dentro**, con la recomendación contraria de las dos auditorías a la vista. Se ejecuta por el orden aditivo del §6, que es lo que convierte las 4 roturas P0 en pasos aburridos. *(Decisión 19.)*
6. **`tipo_documento` en 3 tablas** → **se unifica** en una sola lista. Va en la Fase 7. *(Decisión 20.)*
7. **El borrado en cascada de la membresía del equipo** → **se impide.** Si la persona tiene historia de equipo, hay que darla de baja. Es la condición para que la decisión 15 tenga sentido: no serviría de nada contar la venta del que se fue si borrar su perfil se lleva su historia. *(Decisión 21, que acota la 10.)*

---

## 9. Tablero (lo que mide que esto terminó)

| Contador | Hoy | Meta |
|---|---|---|
| Capital calculado fuera del núcleo | 16 + indirectos | 0 |
| Leads contados fuera del núcleo | 21 | 0 |
| Citas contadas fuera del núcleo | 6 | 0 |
| Contratos sin analista que cierra | 466 | 0 |
| Contratos demo contando en métricas | 2 | 0 |
| Tablas sin rastro ni declaración | 8 | 0 |
| Puertas de borrado sin auditoría | 4 | 0 |
| Montos sin protección | 11+ | 0 |
| Permisos de fábrica sin recortar | 10 tablas | 0 |
| Políticas que repiten el rol a mano | 3 + 13 | 0 |
| Versiones vivas de la misma métrica | 3 | 1 |
| Cierres de mes sanos | 0 | 2 |
| Fichas de la capa semántica | 1 | 6 |

---

## 10. Definición de terminado

1. Cada cifra tiene una sola calculadora, y una prueba automática impide que nazca otra.
2. Cada contrato sabe qué analista lo cerró, y ese dato no se mueve solo.
3. Dos cierres de mes reales ejecutados sanos.
4. Ningún hallazgo de la auditoría sin destino: arreglado, retirado, o declarado a propósito y firmado.
5. Un solo idioma en todo el sistema.
