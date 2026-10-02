---
fecha: 2026-09-30
estado: ✅ fase 1 EN PROD 30/09 (bandera APAGADA) · ✅ fase 2 EN PROD 01/10 13:27 (la marca baja sola) · ✅ puerta de lectura EN PROD 01/10 13:40 (fase 3A, servidor) · ✅ pantalla de la fase 3A PUBLICADA 01/10 13:57 (`build-20261001T185238130Z`, `54690b06`) · ✅ **BANDERA ENCENDIDA 01/10 14:04: el potencial está VIVO para los usuarios** · 🎨 **Tibio NARANJA PUBLICADO 01/10 16:06** (`build-20261001T205946155Z`, `83674f19`; PR #163 sin fusionar) · 🟡 **entrega B (filtro en Leads) APROBADA y EN CONSTRUCCIÓN 01/10 noche: servidor y pantalla listos en el worktree, SIN publicar** · fase 4 (Jev) sin empezar · ver «Para retomar»
---

# Potencial del lead: Frío · Tibio · Estrella (2026-09-30)

## ▶️ Para retomar (estado del 01/10/2026, tarde)

> **🎨 Colores — ✅ PUBLICADO el 01/10/2026 16:06 Lima** (Miguel invocó `/release-crm` y lanzó la subida con `!`).
> Artefacto `crm-20261001T205947Z-83674f19eb7e.zip` (SHA-256 `13d7639d…`), commit `83674f19`, buildId
> `build-20261001T205946155Z`. Check completo PASS sobre ese commit (340 archivos, 5 339 pruebas), manifiesto
> verificado (130 archivos, 391 migraciones: igual que el vivo anterior), preflight OK contra `54690b06`. Paquete
> comparado con el vivo anterior archivo por archivo: quitando las huellas de los nombres solo cambian las 3 reglas
> CSS de Tibio y el identificador de build. Smoke: inicio 200, `version.json` nuevo, 117 de 130 archivos byte a byte
> iguales al paquete (los otros 13 son los falsos positivos de siempre: `.htaccess` 403 y 12 PNG que Hostinger
> recomprime), el CSS vivo trae `--pot-tibio:#f97316`, el ZIP no queda en la raíz web. ZIP y manifiesto en
> `CRM-Avance-Corp/releases/` del taller. 🔴 **El CRM VIVO es ahora `83674f19`** (rama
> `release/potencial-tibio-naranja-20261001`, en GitHub): quien publique después (Gestionado #162, Llamadas #160)
> debe partir de ahí. Falta: que Miguel fusione la PR #163 y mire el color en producción.
>
> **Cómo se preparó (01/10/2026, tarde).** Antes de la entrega B
> Miguel quiso cambiar los colores y eligió en un probador local a escala real
> (`ui-playground/colores-potencial.html`; pidió local, no artifact): **Frío se queda en gris pizarra `#64748b` y
> Tibio pasa a naranja `#f97316`** con tinta oscura `#431407` (5,6 a 1; con letra blanca daba 2,8 a 1). Solo
> pantalla: tokens en `index.css` (nuevo `--pot-tibio-tinta`), dos reglas de `potencial.css` y una prueba e2e que
> mide el contraste que pinta el navegador en el chip y en el botón elegido (su mutante de letra blanca cae con 2,80).
> - Rama de publicación: `release/potencial-tibio-naranja-20261001` (`83674f19`) = el vivo `54690b06` + ese commit y
>   nada más. NO lleva Llamadas F1 (#160) ni Pipeline «Gestionado» (#162), que están en `main` sin publicar. Subida
>   a GitHub. El worktree `wt-potencial-lead` quedó en esa rama, limpio y con el archivo de entorno ya copiado.
> - PR a `main`: **#163** (`crm/potencial-tibio-naranja`, `2b9a7aa3`), sin fusionar.
> - Verificación: `npm run check` PASS sobre vivo + cambio (340 archivos, 5 339 pruebas); pruebas sobre `main` +
>   cambio PASS (5 349); e2e Docker `potencial-lead.spec.ts` 8 de 8; fotos de Leads, ficha y Pipeline miradas.
>   Suite e2e completa NOT RUN (cambio de dos colores). Codex: no (LEVEL 1).
> - 🔑 Antes de publicar, volver a mirar `version.json`: si el vivo ya no es `build-20261001T185238130Z` (otra sesión
>   publicó Gestionado o Llamadas), rehacer la rama sobre el nuevo vivo con `git cherry-pick 83674f19`.
> - Las piezas del laboratorio (CRM-04 y CRM-05) siguen con el azul viejo: la referencia de color es el CRM.
> - ✅ El plan de la entrega B se entregó y Miguel lo aprobó el mismo 01/10: ver «Fase 3 · entrega B: ejecución».

*(Lo que sigue es el texto del mediodía, antes de publicar; lo que pasó después está en los pasos 1 a 7.)* Al
mediodía no había nada del potencial nuevo en producción. La entrega A de la fase 3 está terminada, revisada y **fusionada
en `avancecorp/main`** (PR #158, `8eeaf805`, el 01/10 a las 12:18; comprobado que llegó entera, migración con md5
`7c2b8534…`). Después Miguel publicó OTRA cosa (PR #159, wizard de conversión, solo pantalla): el CRM VIVO pasó a ser
`e304cc44` (rama `rescue/wizard-conversion-foco-20261001`, `build-20261001T174928972Z`). `avancecorp/main` (`12861fd9`)
es exactamente ese vivo MÁS el potencial (27 archivos de `app/`, ni uno más), y sobre esa combinación `npm run check`
pasa (340 archivos, 5 339 pruebas) y el e2e en Docker da 304 en verde, 26 saltadas y los MISMOS 2 fallos que ya tenía
`main` antes del potencial (`gerencia-operativa.spec.ts:108`, `gestion-diaria-vuelta.spec.ts:11`). El worktree `wt-potencial-lead` quedó en `avancecorp/main` (HEAD suelto): los
archivos de los `!` están ahí con el mismo contenido. Lo que queda son pasos de Miguel, EN ESTE ORDEN (cada `!` desde
`CRM-Avance-Corp/` del taller, leyendo archivos de ese worktree):

1. ✅ **Fase 2 EN PROD** (Miguel con `!`, 01/10/2026 13:27 Lima): migración, registro y verificación. Salida:
   job `[10,40 10 * * * select private.potencial_caducar() postgres@postgres activo=true]`, última corrida «aún no
   corrió», 0 EXECUTE ajenos, 0 marcas vivas, 0 bajarían hoy, registro `crm_potencial_lead_caducidad`. Traída al `main`
   local (`7aec101b`, junto con la migración y los scripts de la 3A). Faltan: advisors (los lanza Miguel: la sesión no
   puede leer producción), ledger a «EN PROD» en GitHub, y mañana 02/10 tras las 05:40 `verificar-caducidad.sql` debe
   decir `succeeded`.
2. ✅ **Volcado y banco a paridad** (01/10 13:31): Miguel sacó el volcado con `!`; banco NUEVO
   `avancecorp-potencial-20261001` (puerto 55471). Comparado con el banco de las pruebas: 873 funciones (cuerpo,
   DEFINER, volatilidad, configuración, dueño y ACL), 110 policies, 1 336 columnas y 337 disparadores IDÉNTICOS. Los
   tres ciclos en verde sobre él (75, 51 y 94; pasada real de pg_cron; 30 + 28 mutantes). Advisors tras la fase 2:
   248, las mismas 6 clases.
3. ✅ **Puerta de lectura EN PROD** (Miguel con `!`, 01/10/2026 13:40 Lima). Salida de `verificar-lectura.sql`:
   ejecutan la puerta `[authenticated]`, 0 EXECUTE de la API en los 3 ayudantes, 0 funciones con ACL nula, forma
   `DEFINER/s/search_path=""`, job `10,40 10 * * * activo=true`, bandera false, 0 marcas, registro
   `crm_potencial_lead_lectura`. Advisors de después: 249; el único nuevo es `crm.potencial_leads_fn` en la clase
   `authenticated_security_definer_function_executable`, que ya existía. Ninguna clase nueva.
4. ✅ **Tipos y ledger: PR #161** (`crm/potencial-lead-f3a-en-prod`, `b166f399` + `2f91fdd3`, sin fusionar). Miguel
   corrió `npm run gen:types`: los bloques del potencial salieron IDÉNTICOS a los trasplantados desde el banco;
   entraron además `contrato_pdf_anexo_*` y los argumentos `p_desde`/`p_hasta` de la conversión, que ya estaban en
   producción. `npm run check` con esos tipos: PASS (340 archivos, 5 339 pruebas).
5. ✅ PR #158 fusionada (`8eeaf805`) y comprobada en `avancecorp/main`.
6. ✅ **FRONT PUBLICADO** (Miguel invocó `/release-crm`; 01/10/2026 13:57 Lima): artefacto
   `crm-20261001T185238Z-54690b06a861.zip` (SHA-256 `75a16bb1…`), commit `54690b06`, buildId
   `build-20261001T185238130Z`. Check completo PASS (340 archivos, 5 339 pruebas), manifiesto verificado (391
   migraciones, última la de la lectura), preflight OK contra el vivo `e304cc44`. La subida la lanzó Miguel con `!`
   (token leído del llavero); el primer intento murió en «timeout initialize» SIN subir nada (ver lección 8). Smoke:
   inicio 200, `version.json` nuevo, `index-Dxaq7Z7e.js` y otros 116 archivos byte a byte iguales al paquete; las 12
   imágenes PNG difieren en bytes porque el CDN de Hostinger las recomprime; el ZIP no queda en la raíz web. Rama
   subida a GitHub: `release/potencial-lead-f3a-20261001`. ZIP y manifiesto en `CRM-Avance-Corp/releases/` del taller.
   🔴 **El CRM VIVO es ahora `54690b06`**: quien publique después (la #160 de Llamadas sigue en `main` sin publicar)
   debe partir de esa rama. Con la bandera apagada la pantalla se ve igual que antes.
   Cómo se preparó la rama, por si hay que repetirlo. La rama se armó en el worktree `wt-potencial-lead`:
   `release/potencial-lead-f3a-20261001` (`54690b06`, solo local). Nace del commit VIVO `e304cc44` (lo contiene) y su
   árbol es idéntico al de la rama de cierre (`main` en `12861fd9` + ledger + tipos), que pasó el check completo.
   🔴 NO incluye la PR #160 (Llamadas F1, fusionada en `main` a las 13:38 y SIN publicar): la publica su sesión; quien
   publique segundo debe partir de lo que haya vivo. 🔑 Antes de construir, volver a mirar
   `crm.miavance.com/version.json`: si el vivo ya no es `build-20261001T174928972Z`, rehacer la rama sobre el nuevo.
   Falta: que Miguel copie el archivo de entorno a `app/` del worktree (el hook se lo bloquea a la sesión) y que
   invoque `/release-crm`. El ZIP y su manifiesto deben quedar en `CRM-Avance-Corp/releases/` del taller (ahí
   resuelve el preflight el manifiesto vivo). Después de publicar: subir la rama de release y dejarla en `main`.
7. ✅ **BANDERA ENCENDIDA por Miguel el 01/10/2026 14:04 Lima** (`encender-bandera.sql` con `!`);
   `verificar-lectura.sql`: bandera true, 0 marcas. Anotado en el ledger (PR #161, `9db5a37e`). La sesión NO pudo
   hacer la pasada visual (el conector de Chrome no estaba conectado; se dejó una vista previa demo en
   `127.0.0.1:5180`, ya detenida) ni entrar a producción. ✅ **Miguel lo miró en producción el mismo 01/10: «hasta
   ahora lo veo todo muy bien».** Interruptor de emergencia: `apagar-bandera.sql` (no borra marcas).
8. A la mañana siguiente de publicar la fase 2: `verificar-caducidad.sql` debe decir `succeeded`.

Pendientes menores: ledger a «EN PROD» y traer al `main` local los archivos de las fases 2 y 3A cuando se publiquen;
la entrega B (filtro con conteo en Leads) necesita su propio plan y OK.

### Estado al cierre del 30/09/2026 (histórico)

Miguel cerró el día con «guarda todo y seguimos mañana». En orden:

1. **Miguel aplica la fase 2 en producción con `!`** (la migración, su registro y su verificación). Ya se comprobó
   en solo lectura que producción está lista: fase 1 intacta con su candado, sin objetos de la fase 2, sin tarea con
   ese nombre, 0 marcas y bandera apagada. Línea exacta:

   ```
   ! cd /Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp && W=/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead/CRM-Avance-Corp/supabase && supabase db query --linked --file $W/migrations/20260930235917_crm_potencial_lead_caducidad.sql && supabase db query --linked --file $W/scripts/potencial-lead/registrar-caducidad.sql && supabase db query --linked --file $W/scripts/potencial-lead/verificar-caducidad.sql
   ```

   Debe terminar en «VERIFICAR potencial_caducidad: job [10,40 10 * * * select private.potencial_caducar()
   postgres@postgres activo=true] … marcas vivas 0 … registro crm_potencial_lead_caducidad».
2. **Después de aplicarla:** `supabase db advisors --linked --type all` (ninguna clase nueva; el 30/09 eran 248),
   ledger a «EN PROD» en la rama `crm/potencial-lead-f2-main`, push, y traer migración y scripts al `main` local con
   `git checkout crm/potencial-lead-f2-main -- <rutas>` + `git commit -- <rutas>` (sin tocar `MIGRACIONES.md` mientras
   tenga cambios sin commitear de otra sesión).
3. **A la mañana siguiente de aplicarla:** `verificar-caducidad.sql` otra vez; «última corrida» debe decir
   `succeeded` (prueba de que el planificador de producción la ejecuta).
4. ✅ **Supuestos CONFIRMADOS por Miguel el 01/10/2026** (cuatro preguntas con opciones; eligió en las cuatro lo ya
   construido, así que la fase 2 queda como está, sin enmienda): Estrella llega a Frío a los 10 días en total (no
   5 + 10); el tiempo cerrado o inactivo SÍ cuenta como sin gestión; solo el contacto real (y volver a marcar) reinicia
   el reloj: notas, tareas agendadas y reasignaciones no; al reasignar, la marca viaja con el lead y la cuenta sigue
   igual. (Feriados = día normal, ya comunicado.)
5. **PRs:** la #153 (fase 1) ya está fusionada en el `main` de GitHub (`11ec4326`). La #156 (fase 2) se fusionó
   40 minutos después, pero sobre la rama `crm/potencial-lead-f1`: su contenido quedó ahí (`346d3a93`) y NO llegó a
   `main`. Por eso existe la **PR #157** (rama `crm/potencial-lead-f2-main`): el mismo contenido asentado sobre el
   `main` actual, más los arneses del banco y esta nota. ✅ **Miguel la fusionó el 01/10/2026 09:35** (`78ede498`) y se
   comprobó que la migración de la fase 2 está en `avancecorp/main` con su md5 (`a4dbc97c…`). 🔴 Lección: una PR apilada
   que se fusiona después de su base cae en la rama base; «MERGED» no es «llegó a `main`».
6. **Fase 3 (pantalla):** plan por fases en lenguaje de negocio y OK de Miguel ANTES de tocar código. Lleva: puerta
   de LECTURA (las tablas no tienen grants: 4 capas), chip con el `Badge` del CRM, selector en la ficha, filtro en Leads
   resuelto en el servidor (el store no carga todos los leads), Pipeline, cola de hoy, «baja en N días» con fecha y
   hora prevista (reusar `potencial_nivel_tras`, `potencial_reloj` y `dias_lunes_a_sabado`), prueba en el estado de
   producción (ningún lead marcado) y encender la bandera al final. Diseño aprobado: pieza CRM-05.
7. **Fase 4 (Jev):** depende de la temperatura (su F1 sigue sin branch: dos secretos, rotar la clave de TypeSafe,
   desplegar la edge). Sugiere desde los seguimientos y lleva interruptor propio.

**Dónde está cada cosa**

- Servidor: worktree `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead` (base `avancecorp/main`), hoy en la
  rama `crm/potencial-lead-f2-main` (PR #157). Las ramas `crm/potencial-lead-f1` y `crm/potencial-lead-f2` siguen en
  GitHub como referencia: no se borran sin que Miguel lo diga. `main` local: commit `ea5f84de` con la fase 1
  (falta su fila del ledger: `MIGRACIONES.md` tenía cambios sin commitear de otra sesión).
- Banco: contenedor Docker `avancecorp-potencial-20260930` (puerto 55470, fases 1 y 2 aplicadas, `pg_cron`). Se dejó
  CORRIENDO a propósito (un contenedor parado lo borra `docker container prune`). Receta y ciclos repetibles en
  `CRM-Avance-Corp/supabase/scripts/potencial-lead/banco/` (montaje + dos ciclos en menos de 3 minutos).
- Diseño: `ui-playground/galeria/src/componentes/PotencialLead.tsx` (CRM-04, concepto) y `PotencialEscalaCrm.tsx`
  (CRM-05, a escala real, la aprobada). Ojo: la carpeta `ui-playground` NO es un repo git.

**Pedido de los analistas:** marcar cada lead como malo (rojo), regular (amarillo) o con
potencial (verde).

**Decisiones de Miguel (30/09), en orden:**
1. **Jev propone la marca** leyendo las notas del analista, y **el analista la puede cambiar**.
   Es la [[Temperatura del lead - señal de TypeSafe para ordenar Mi dia (2026-09-20)]] puesta
   en pantalla.
2. **Nada de barras de señal** («no me convence para nada»).
3. El máximo potencial con un diferencial tipo «carta legendaria de videojuego».
4. «Algo más suave para un CRM corporativo»: fuera el foil saturado.
5. «La animación no la elimines, eso sí me gusta» y **que reaccione al movimiento del mouse**.
6. **Nombre comercial en vez de «Legendario» → «Estrella».** Ninguno de los candidatos
   (Estrella, Premium, Oro, VIP, Prioritario, Caliente, Destacado) existía en el CRM.
7. **«Que los colores se distingan»**: insignias sólidas y franja de color en cada fila.

## Por qué no rojo/amarillo/verde

En el CRM el rojo significa «actuar hoy» y el ámbar «esta semana» (urgencia de tiempo), y el
verde está fuera de la paleta ([[Fundamentos UX del CRM]]). Un lead «malo» en rojo llevaría la
vista a los leads que menos valen. Por eso: **Frío** gris pizarra `#64748b` con copo,
**Tibio** naranja `#f97316` con termómetro y tinta oscura `#431407`, **Estrella** dorado (marca `#c8922a`) con
estrella. Tibio fue azul `#2563eb` hasta el 01/10/2026: Miguel lo cambió viéndolo junto al ámbar y al rojo del CRM
(el ámbar de urgencia no se tocó). Con daltonismo rojo-verde el naranja y el dorado se parecen más que el azul y el
dorado: ahí distinguen el ícono, el texto y el fondo crema de Estrella. Ícono y texto siempre.

## Cómo se ve (pieza CRM-04 del [[UI Playground (laboratorio de animaciones)]])

- **Confirmada = insignia sólida** del color de su nivel. **Sugerida por Jev = insignia
  blanca con borde punteado** del mismo color y la etiqueta «Jev». El dorado completo aparece
  solo cuando una persona confirma.
- **Filas:** franja de 4 px del color del nivel; punteada si es sugerencia de Jev. La fila
  estrella lleva fondo dorado tenue, barrido de luz lento y un foco que sigue al cursor.
- **Carta estrella (Pipeline, cola del día):** se inclina hacia el mouse (±12–14°) con un
  reflejo que lo sigue, marco dorado que gira despacio y aura suave.
- Al confirmar Estrella: chispas doradas pequeñas en la ficha.
- **Sin movimiento** (`prefers-reduced-motion`): sigue siendo dorada, sin animación.
- La lista **sigue ordenada por vencimiento**: potencial y urgencia son ejes distintos. El
  potencial se ve y se filtra (filtros con conteo).
- Truco de rendimiento: el foco de las filas escribe variables CSS en el elemento, sin
  re-renderizar React en cada movimiento.

Archivo: `ui-playground/galeria/src/componentes/PotencialLead.tsx`.

## Reglas decididas por Miguel (30/09, preguntas de los pendientes)

- **Sin tope de estrellas**: no hace falta porque la estrella se cae sola.
- **Caducidad:** Estrella → Tibio tras **5 días sin gestión**; Tibio → Frío tras **10 días sin
  gestión**. Cuentan **lunes a sábado**; cada gestión registrada reinicia el reloj. Frío no baja.
- **Quién la cambia:** el analista dueño del lead y su supervisor. Gerencia solo ve y filtra.
- **No cambia el orden** de la cola del día: el vencimiento manda; el potencial se ve y se filtra.
- **Arranque: primero la marca MANUAL.** Jev se suma después.
- **Confirmado el 01/10:** Estrella llega a Frío a los 10 días en total; el tiempo con el lead cerrado o inactivo
  cuenta; solo el contacto real o volver a marcar reinician la cuenta (ni notas, ni tareas agendadas, ni reasignar);
  al reasignar, la marca viaja con el lead.
- **Jev (fase 2):** no marca al inicio (lead sin seguimientos). Sugiere a partir de los
  **seguimientos**: si son positivos o comercialmente se acercan a una venta, sugiere Estrella.
  **Debe poder desactivarse** (interruptor) por si Jev no funciona bien.

## ¿Se adapta al diseño del CRM? (medido el 30/09)

- **Igual:** tokens de color (navy, azul `#2563eb`, grises, fondo `#f6f8fc`, bordes), Plus
  Jakarta Sans, radios 12/16 px, sin verde, ícono + texto.
- **Distinto, se ajusta al promover:** la pieza es más grande que el CRM. Chips del CRM =
  componente `Badge` a 11 px (10 px en Pipeline); la pieza usa 14 px y 30 px de alto. El nombre
  en Leads va a 13 px en una TABLA (`Td` = `px-3 py-1.5`), no a 16 px en rejilla. La marca va como
  chip junto al nombre (como «Manual» o «Reasignado») y la franja en el borde de la fila.
- La ficha es un panel lateral: el selector pasa a una fila compacta de tres botones.
- El Pipeline arrastra tarjetas dentro de columnas con scroll: inclinación 3D menor, sin
  agrandar (se cortaría en el borde) y apagada mientras se arrastra.
- El dorado no existe como token: crear `--estrella` y su variante oscura para texto (patrón
  de `--warning-text`). Vigilar que no se confunda con el ámbar de «sin asignar».

## Pieza a escala real: CRM-05 (30/09)

Miguel pidió «necesito verlo» a escala del CRM. `ui-playground/galeria/src/componentes/PotencialEscalaCrm.tsx`
replica las medidas del código del CRM: Badge de 11 px (10 px en Pipeline), tabla de Leads con
`Td px-3 py-1.5` y nombre de 13 px, ficha lateral de 460 px, columna del Pipeline de 290 px y
filas de 62 px en la cola de hoy. Las cuatro vistas comparten el estado: lo que se marca en la
ficha aparece en todas. Trae la bajada automática («+1 día sin gestión») y un interruptor de
fase 2 con Jev. **Marcar también reinicia el reloj** de la caducidad (supuesto: si no, una
estrella puesta a un lead sin gestión reciente caería al instante).

## Plan técnico INICIAL (superado en dos puntos: la marca va en tablas propias y no en columnas de `crm.leads`; la caducidad cuenta días completos y corre a diario; lo vigente está en «Fase 1» y «Fase 2»)

**F1 · Servidor: guardar y marcar** (una migración, ciclo branch → gate → advisors → merge):
- Tipo enum `crm.nivel_potencial` ('frio','tibio','estrella'). Columnas nuevas en `crm.leads`:
  nivel, quién (perfil), cuándo marcó, y cuándo bajó sola. ⚠️ `crm.leads` tiene **grants por
  columna**: SELECT explícito a `authenticated`; **sin UPDATE directo** (solo por la puerta).
- Puerta `crm.marcar_potencial_lead_fn(p_lead_id, p_nivel)`. La edición actual
  (`crm.editar_lead_fn`) es INVOKER y se apoya en la policy `leads_update`, que deja pasar a
  gerencia; aquí gerencia NO marca, así que: DEFINER con `search_path = ''`, nombres
  calificados y verificación explícita (analista dueño = `vendedor_id`, o supervisor de ese
  analista). Justificación escrita. Pasar por `auditor-rls` y Codex (LEVEL 3).
- Historial: el evento «marcó Estrella» **no debe contar como gestión** (ni reiniciar SLA ni
  sumar en métricas de `crm.actividades`). Verificar qué tipos de actividad cuentan antes de
  elegir dónde se registra.
- Interruptor general con `crm.bandera_activa(...)` (ya existe) para encender la función.

**F2 · Servidor: caducidad** — tarea `pg_cron` diaria (ya hay cron en 5 migraciones del CRM).
Reloj = el más reciente entre «marcó» y la última gestión en `crm.actividades`; cuenta lunes
a sábado (feriados cuentan como día normal: supuesto). Estrella→Tibio ≥5, Tibio→Frío ≥10.
Cada bajada deja evento «bajó sola». Ensayar con fechas simuladas en el banco Docker propio.

**F3 · Pantalla** — añadir la clave (aditiva, nunca mover claves) a `cartera_pagina_fn`,
`resumen_cartera_fn` (filtro `p_potencial` + conteos en el servidor: el store no carga todos
los leads), la fuente del Pipeline, `cola_accion_fn`/cola de hoy y la ficha. Esquemas valibot
con `v.optional` (bundles viejos). Componentes: chip, selector en `lead-drawer`, píldoras en
`cartera`, tarjeta de `pipeline`, fila de `cola-de-hoy`. Test en el ESTADO DE PRODUCCIÓN
(ningún lead marcado). Correr specs que usan `postDataJSON()` si cambian args de RPC.
Checks: `gen:types`, `npm run check`, `test:rls:preflight`, e2e Docker, `revisor-a11y`.
Orden de deploy: servidor primero, luego front con preflight y `/release-crm`.

**F4 · Jev** — depende de la F1 de temperatura (secretos, rotar clave, desplegar edge). Solo
leads con seguimientos; umbral según los seguimientos; bandera propia para apagarlo.

## Fase 1 · ejecución (30/09, tras el «HAZLO» de Miguel)

- Rama `crm/potencial-lead-f1` en el worktree `wt-potencial-lead`, nacida de `avancecorp/main` (51bd18e5), NO del
  `main` local (lleva lo de Gloria, que no va a GitHub). Sin push: Miguel pidió esperar su aviso para publicar.
- **Cambio de diseño respecto al plan:** la marca NO va en columnas de `crm.leads` sino en tablas propias
  (`crm.lead_potencial` vigente + `crm.lead_potencial_eventos` historial). Motivo medido en el volcado:
  `private.leads_before_update` pone `actualizado_en := now()` en todo UPDATE, y esa columna ordena la cartera
  (`leads_orden_cartera_idx`); además hay ~20 disparadores (SLA, tenencia, identidad). Marcar no debe reordenar ni
  tocar plazos. Tampoco usa `crm.actividades`: marcar no es gestión.
- Migración `20260930213647_crm_potencial_lead` + scripts en `supabase/scripts/potencial-lead/` (LEEME con el orden).
- Banco Docker propio `avancecorp-potencial-20260930` (paridad 280 crm + 540 private). Sintética 63/63; 6 mutantes de
  migración rechazados; 3 de lógica cazados; reversa y registro idempotentes. `check:scripts` PASS.
- 🔑 `pg_get_functiondef` cambia con el `search_path` de la sesión (`DEFAULT uid()` vs `auth.uid()` en 6 funciones de
  postventa): para fijar identidad de funciones usar md5 de `prosrc|prosecdef|provolatile|proconfig`.
- 🔑 El `auth.uid()` de la imagen del banco solo lee `request.jwt.claim.sub`; el de prod también `request.jwt.claims`.
- ⚠️ El hook de Bash bloquea variables con forma de credencial en línea (aunque sean ficticias): `test:rls:preflight`
  queda NOT RUN sin el gestor de credenciales.

### Cierre de la fase 1 (30/09, noche)

- Revisiones: auditor-rls r1 y Codex r1 + r2 (máximo del protocolo), todas aplicadas. Codex r1: carrera de
  autorización (reasignación/cierre en vuelo) y de la reversa, suite con UUID, postflight sin definiciones.
  Codex r2: FOR SHARE sin fila, antirrebote con `now()`, interbloqueo de la reversa por el DROP de las FK.
- 🔑 **Medido:** `DROP TABLE` de una tabla con FK toma AccessExclusiveLock sobre las tablas REFERENCIADAS
  (`crm.leads` y `public.perfiles`). Una reversa que borra tablas con FK al lead bloquea un instante la
  lectura de leads y perfiles del portal, y debe tomar esos candados ANTES que los de sus propias tablas.
- 🔑 Para probar carreras de verdad: dos sesiones con `pg_sleep` y **medir que la segunda esperó** (≥ 1,5 s);
  cada arreglo con su mutante que reproduce el fallo (sin el bloqueo, V1 escribía con permiso caducado; con
  el orden viejo, `deadlock detected`).
- Resultado: sintética 75/75, concurrencia 11/11, 9 mutantes de migración y 7 de lógica cazados.
- Sin grants de lectura para la API: la fase 3 debe exponer la marca por una puerta (4 capas).
- Riesgo residual: una baja o cambio de jerarquía en `crm.equipo` en el mismo instante no se serializa.
- Pendiente de Miguel: el aviso para publicar; luego él aplica con `!` según el LEEME de los scripts.

### ✅ Publicada (30/09, noche)

- Miguel: «ya podemos publicar». Lo lanzó él con `!`: migración + `registrar.sql` + `verificar.sql` → marcas 0,
  eventos 0, bandera false, permisos correctos, registro presente. Antes, en solo lectura: 0 objetos previos y
  huellas de `rol_crm`/`vendedor_ids_visibles` idénticas a las ensayadas.
- Advisors: 248; el único de lo nuevo es `authenticated_security_definer_function_executable` de la puerta
  (clase existente: patrón de todas las puertas DEFINER). Ninguna clase nueva.
- GitHub: PR #153 (rama `crm/potencial-lead-f1`, reubicada sobre `avancecorp/main` 62e809c6). Main local:
  commit `ea5f84de` con migración, scripts, suite y encargos; la fila del ledger `MIGRACIONES.md` llega con la
  PR porque ese archivo tenía cambios sin commitear de otra sesión en el taller.
- ⚠️ `MIGRACIONES.md` en `avancecorp/main` ya traía marcadores de conflicto de una integración anterior
  (`<<<<<<< avancecorp/main` … `>>>>>>> rescue/conversion-coordinacion-20260930`): avisado en la PR.

## Fase 2 · la marca baja sola (30/09 noche, tras el «hazlo» de Miguel)

- Migración `20260930235917_crm_potencial_lead_caducidad`, rama `crm/potencial-lead-f2` (apilada sobre la f1), PR #156. (La #156 cayó en la rama de la fase 1; a `main` va por la PR #157, rama `crm/potencial-lead-f2-main`.)
- Regla en UN lugar: `private.potencial_nivel_tras` (≥10 días → frío; ≥5 y estrella → tibio) y `private.potencial_reloj`
  (última marca o último CONTACTO hasta el instante de la corrida). `private.dias_lunes_a_sabado` cuenta días COMPLETOS
  estrictamente entre dos fechas (domingo fuera). Tarea `pg_cron` 05:10 y 05:40 Lima, todos los días, como postgres.
- **Gestión = contacto**: llamada realizada o no contestada, WhatsApp enviado o recibido, reunión realizada (el mismo
  criterio del índice `actividades_contacto_episodio_idx`). Las notas NO cuentan (el sistema también escribe notas).
- **La tarea nunca espera**: try-lock del consultivo de la marca + `FOR SHARE SKIP LOCKED` del lead; lo ocupado queda
  para la próxima pasada. Lote de 200 como mucho (34 ms medido con 2 000 marcas vencidas).
- 🔑 Lecciones: (1) una regla escrita dos veces (filtro + bucle) esconde mutantes: unificarla en un ayudante; (2) con dos
  cálculos a propósito (filtro + relectura bajo candado) el mutante hay que ponerlo en LOS DOS; (3) el corte de «qué
  contactos cuentan» es el INSTANTE de la corrida, no el inicio del día (un WhatsApp de la 01:00 debe salvar la marca a
  las 05:10); (4) un procedimiento con `SET search_path` no puede hacer COMMIT, por eso lote acotado y no «un commit por
  lead»; (5) `pg_cron` en Supabase corre como cliente (`cron.use_background_workers=off`), en GMT, como postgres.
- **Supuestos (✅ confirmados por Miguel el 01/10/2026):** Estrella llega a Frío a los 10 días en total (no
  5 + 10); el tiempo cerrado o inactivo cuenta como sin gestión; agendar o reasignar no reinicia el reloj; feriados = día
  normal.
- Banco: caducidad 51/51, fase 1 sin regresión 75/75, concurrencia 10/10, corrida real de pg_cron, ciclo con y sin
  pg_cron. auditor-rls PASS; Codex r1 + r2 aplicados.

## Fase 3 · mapa y plan (01/10/2026, tras el «seguimos» de Miguel)

**Estado:** PR #157 fusionada (`78ede498`); la fase 2 sigue sin el `!`; supuestos confirmados. Plan de la fase 3 presentado
en dos entregas; **esperando el OK de Miguel. Nada de código todavía.**

**Mapa (dos agentes Explore, front y servidor; rutas del worktree `wt-potencial-lead`):**
- Las 4 vistas leen de TRES fuentes en sesión real. Tabla de Leads (`screens/cartera.tsx`) y Pipeline (`screens/pipeline.tsx`,
  4 listas, una por columna) → `crm.cartera_filtrada_fn` (INVOKER, `to_jsonb` de un CTE, contrato con eco y coherencia por
  fila; ojo: NO `cartera_pagina_fn`, aunque varios comentarios lo digan). Ficha (`components/app/lead-drawer.tsx`) → SELECT
  directo a `crm.leads` (`obtenerLeadDelAmbitoPorId`, `data/crm-api.ts:611`). Cola de hoy
  (`components/gestion-diaria/cola-de-hoy.tsx`) → `crm.gestion_diaria_cola_trabajo_fn` (`data/gestion-diaria-cola-api.ts`),
  con filas que NO son `Lead`.
- Varias puertas del SLA y de Gestión Diaria están selladas por md5 (`private.assert_cola_v3`,
  `assert_gestion_diaria_analista`, `assert_sla_nucleo`) y hay un censo diario de «contadores crudos»
  (`private.contadores_crudos_leads_citas`): toda función que nombre `crm.leads` y use `count(` debe estar declarada.
- El store ya no carga todos los leads y en la fusión «la fila nueva manda» (`fusionarLeadsConocidos`, `lib/store.tsx:537`):
  un dato que viaje en la lista y no en la ficha se pierde al abrirla (ya pasó con `reasignado`). Las listas pintan sus
  páginas de TanStack, no el store.
- No hay lector genérico de banderas en el front: cada módulo tiene su puerta de estado (`{version:1, habilitada}`; el error
  `PGRST202` se trata como apagado: `data/inversionistas-api.ts:31`). `crm.bandera_activa(text)` existe (DEFINER, EXECUTE
  para authenticated) pero el front no la llama.
- **Precedente exacto:** `crm.cierres_estado_fn(p_lead_ids uuid[])` (DEFINER, tope de 200, admisión + `puede_acceder_crm()`,
  espejo de la policy `leads_select`, devuelve solo los leads «con algo que decir»). En el front: `obtenerCierresEstado`
  (lotes de 200, `data/crm-api.ts:6420`) y `useCierresEstado` (`data/crm-queries.ts:1188`), usados por la tabla con los ids
  de la página (`cartera.tsx:325`) y por la ficha con `[l.id]` (`lead-drawer.tsx:406`).
- Molde de escritura desde la ficha: «Reabrir» (`lead-drawer.tsx:412`, `store.tsx:2995`, `crm-api.ts:2295`); `aErrorApi`
  traduce 42501, P0409, P0001 y 22023. La puerta de marcar lanza además 55000 (bandera apagada) y P0002 (fuera de ámbito).
- `motion` NO es dependencia del CRM (sí `gsap` y `@gsap/react`): la pieza CRM-05 usa Motion, así que la animación se
  porta a CSS con eventos de puntero o a GSAP. `prefers-reduced-motion` ya tiene bloque global (`index.css:391`). Tokens en
  `index.css:24-106`; no hay token dorado; el ámbar `#d97706` ya significa cuatro cosas.
- Las pruebas cierran en falso: una RPC nueva sin mock da 500 en todos los specs e2e de sesión real
  (`e2e/_helpers.ts:3429`) y rompe los msw (`onUnhandledRequest: 'error'`). La demo guarda copia en `sessionStorage`
  (`ac-crm-demo-datos-v2`). `database.types.ts` aún no conoce `marcar_potencial_lead_fn` (falta `gen:types`, que lee
  producción).
- El CRM VIVO es `c6e65d9e` (rama `rescue/conversion-desglose-20261001`, `build-20261001T002155841Z`): no es ancestro de
  `main`, aunque `app/` es idéntico al de `avancecorp/main`. La rama del front debe contener ese commit para pasar el
  preflight.
- Otra sesión tiene cambios SIN commitear en el taller sobre `lead-drawer.tsx`, `cola-de-hoy.tsx`, `cartera.tsx`,
  `store.tsx`, `crm-api.ts`, `tipos.ts` y `e2e/_helpers.ts`: tocar esos archivos lo mínimo y poner lo nuevo en archivos
  propios.
- El volcado del banco (30/09 16:32) va por detrás: faltan `20260930193325_crm_documentos_lead`,
  `20260930221500_crm_conversion_coordinacion_desglose_cierres` y `20260930235814_crm_pdf_analista_asignado`. El 01/10 el
  modo automático bloqueó a la sesión las lecturas de producción: el volcado nuevo lo lanza Miguel con `!`.

**Entrega A · marcar y ver (diseño elegido: lectura APARTE, sin tocar ninguna puerta existente):**
- Servidor: una migración con `crm.potencial_leads_fn(p_lead_ids uuid[]) returns jsonb`. DEFINER justificado: las tablas
  no tienen grants y el núcleo no tiene EXECUTE para la API; molde `cierres_estado_fn`. Sobre `{version, habilitada, items}`;
  con la bandera apagada devuelve `habilitada: false` sin leer nada. Por lead: nivel, origen, quién y cuándo, días sin
  gestión, a qué nivel baja y qué día (con `potencial_reloj`, `dias_lunes_a_sabado` y `potencial_nivel_tras`: la regla
  sigue en UN lugar) y `puede_marcar` (con `private.potencial_rechazo`: la misma regla de la puerta de marcar). Prueba de
  equivalencia contra la RLS real de `crm.leads`, mutantes, auditor-rls y Codex (LEVEL 3).
- Front: archivos nuevos (`data/potencial-api`, `data/potencial-queries`, `lib/potencial`, chip, selector y estilos) y UNA
  inserción por vista; caché propia por ids; sin tocar `Lead`, `aLead` ni el store. Demo con marcas en memoria. Test en el
  ESTADO DE PRODUCCIÓN (bandera apagada y bandera encendida sin marcas).
- Orden: servidor con la bandera apagada → front (`/release-crm` de Miguel) → encender la bandera con `!` de Miguel.

**Entrega B · filtrar:** filtro por potencial con conteo en Leads, resuelto en el servidor. Toca `cartera_filtrada_fn`
(argumento nuevo, eco, coherencia por fila, conteos del resumen, clave de caché, espejo demo y espejo e2e) y, por ser
INVOKER, necesita un ayudante DEFINER al estilo de `private.cartera_recepciones_fn`. Plan propio.

## Fase 3 · entrega A: ejecución (01/10/2026, tras el «vamos dale» de Miguel)

**Qué quedó hecho (PR #158, sin fusionar ni publicar):**
- **Servidor**, migración `20261001151704_crm_potencial_lead_lectura` (no modifica nada existente):
  `crm.potencial_leads_fn(uuid[])` (DEFINER, STABLE, EXECUTE solo authenticated; sesión, gate del CRM invocado, tope
  de 200 ids, bandera) + `private.potencial_lectura` (espejo de `leads_select`, actor = sesión) +
  `private.potencial_proxima_baja` y `private.potencial_proxima_corrida`. Devuelve
  `{version, habilitada, items[{lead_id, nivel, origen, nivel_marcado, marcado_en, dias_sin_gestion, baja_a, baja_el,
  puede_marcar}]}`; con la bandera apagada, `habilitada: false` sin leer nada. Scripts: reversa, registrador (con
  generador `banco/generar-registrador.py`), verificación, `encender-bandera.sql` y `apagar-bandera.sql`.
- **Pantalla:** archivos nuevos `lib/potencial*.ts`, `data/potencial-api.ts`, `data/potencial-queries.ts`,
  `components/app/potencial-{chip,seccion,efectos}` y `potencial.css`, más UNA inserción por vista (tabla de Leads,
  ficha, Pipeline, cola de hoy). Lectura aparte por ids con caché propia colgada de `['crm','leads','potencial']` (lo
  que el store ya invalida al mutar un lead refresca la marca). La regla de la caducidad NO se copia en sesión real: el
  optimista solo cambia el nivel y la nota dice «Guardando la marca…» hasta la relectura; el espejo vive solo en el
  modo demo. Animación en CSS con eventos de puntero, sin dependencias nuevas.
- **Gate:** `testPotencialLectura` en `test-rls.mjs` enciende la bandera fuera de banda, compara rol por rol lo que
  entrega la puerta con lo que la RLS deja ver, y la repone.

**Revisiones (todas aplicadas):** auditor-rls PASS con observaciones (0 P0/P1) · Codex r1 y r2 (máximo del protocolo),
sin fuga de RLS en ninguna · revisor-a11y PASS con observaciones, sin bloqueantes (no se tocaron los bucles de
animación de la pieza aprobada).

**Verificación:** banco 94/94 + fases 1 y 2 sin regresión (75 y 51) · 30 mutantes de lógica (29 caen; `sin-sesion`
sobrevive a propósito) y 28 de migración y preflight · trinquetes `private.assert_*()` y censo idénticos sin y con la
migración · `npm run check` PASS (338 archivos, 5 306 pruebas) · e2e Docker 303 pasan, 26 saltadas y 2 fallan IGUAL en
`avancecorp/main` sin el cambio (`gerencia-operativa.spec.ts:108`, `gestion-diaria-vuelta.spec.ts:11`) · gate RLS con
sesiones reales NOT RUN · paridad del banco con la producción de hoy NOT RUN.

**Decisiones de diseño que conviene recordar:**
- `baja_el` es la primera madrugada, contando desde el siguiente horario NOMINAL de la tarea (hoy hasta las 05:45
  Lima; después, mañana), en que la regla la bajaría con lo que se sabe ahora. No acredita ejecución. Por eso la
  pantalla usa siempre el `baja_a` del servidor (una Estrella con 9 días vista tras la corrida anuncia Frío, no Tibio).
- `puede_marcar` sale de `private.potencial_rechazo`, la misma función de la puerta de marcar.
- Un ítem por cada lead visible pedido, también sin marca (`nivel: null`), para que la ficha sepa si puede marcar.
- `crm_gestion_diaria_lector` es miembro de `authenticated` a propósito y hereda el EXECUTE de la puerta; sin sesión
  recibe 42501.

**🔑 Lecciones del día:**
1. El clasificador del modo automático denegó LEER producción (`supabase db query --linked` de solo lectura). No se
   rodea: línea con `!` para Miguel. Para acercar el banco sin leer producción se aplicaron las tres migraciones
   posteriores al volcado que ya estaban en el repo (una exigió una fila sintética en `crm.conversion_pesos`).
2. Un mutante que sobrevive enseña el caso que falta: quitar la rama «rol = gerencia» del espejo no rompía nada
   porque esa rama solo decide para un lead SIN ASIGNAR, que la prueba no tenía.
3. `leads_select` ya está copiada en tres funciones DEFINER (`cierres_estado_fn`, `conversion_estado_lead_v1`,
   `potencial_lectura`): tocar la policy obliga a re-auditar las tres.
4. e2e Docker en un worktree con `node_modules` ENLAZADO: el `npm ci` del contenedor borra el enlace y deja
   dependencias de Linux en el worktree. Va un clon APFS (`cp -cR`), no un enlace, aunque el `CLAUDE.md` diga enlace.
   Quedó apartada `app/.e2e-linux/` en el worktree (basura inofensiva, ignorada por git).
5. La demo trae el potencial ENCENDIDO: un chip nuevo dentro de una fila cambia selectores estructurales de specs
   demo (`span > span`).
6. El Escritorio de este Mac se sincroniza con iCloud y devuelve `.git/index.lock` viejos: comprobar que no hay git vivo y
   apartarlo con `mv`.
7. Dentro de un `DO` con una variable `r record`, un alias SQL `r` choca con ella.
8. El script de despliegue (`_DEV_NO_SUBIR/deploy-hostinger-mcp.mjs`) esperaba 60 s el arranque del conector de
   Hostinger, y con `@latest` npx tarda ~50 s solo en preparar el paquete (medido dos veces): «ERR timeout initialize»
   sin subir nada. Se subió esa espera a 180 s (un número; copia del script anterior en el scratchpad de la sesión).
9. La rama de publicación debe llevar TODO el árbol de `main`, no solo `app/`: el manifiesto del release lista las
   migraciones del árbol, y la línea viva (ramas de rescate) no traía las cuatro últimas ya aplicadas en producción.

## Fase 3 · entrega B: plan (01/10/2026 tarde) — ✅ APROBADO por Miguel: «ok dale con el plan B, todo lo recomendado»

Miguel pidió «pásame el plan de la entrega B» y lo dejó en pausa por los colores. Lo propuesto:

- **Qué se entrega:** en Leads, una fila «Por potencial» con cuatro botones con número (Estrella, Tibio, Frío, Sin
  marcar). Al tocar uno, lista, totales y capital se quedan con ese nivel. Los números respetan los demás filtros y
  la visibilidad de cada quien, y NO cambian al elegir un nivel (se cuentan antes de aplicar el filtro de potencial).
- **Fases:** (1) pieza local a escala real para que Miguel apruebe viendo; (2) servidor; (3) pantalla.
- **Servidor (LEVEL 3):** `crm.cartera_filtrada_fn` gana el argumento 14, `p_potencial` (`estrella`, `tibio`, `frio`,
  `sin_marca`; null = como hoy), y el resumen gana los conteos por nivel. 🔴 La base ya NO es la firma de 12: el
  01/10 la sesión del Pipeline «Gestionado» la llevó a 13 (`p_gestion`, migración `20261001154153`, EN PROD); su
  cabecera es el molde (una sola firma, mover la exención analítica y resellar, servidor primero). La función es
  INVOKER y las tablas del potencial no tienen grants: hace falta un ayudante en `private` con visibilidad propia
  (molde `private.cartera_recepciones_fn`) o una policy de lectura atada a la visibilidad del lead; se decide con
  auditor-rls y Codex. Los conteos nuevos son claves ADITIVAS: el esquema del front es `v.object` (valibot), que
  tolera claves de más; comprobarlo contra el bundle vivo antes de publicar.
- **Pantalla:** botones con conteo en `cartera.tsx`, argumento que solo viaja cuando recorta (como `p_gestion`),
  clave de caché, espejo demo y e2e. Toca los mismos archivos que la #162 (Gestionado): se construye sobre `main`.
- **Dependencias:** volcado nuevo de producción para el banco (lo lanza Miguel con `!`; hoy cambió la base) y que
  las pantallas de Gestionado (#162) y Llamadas F1 (#160), en `main` sin publicar, salgan antes o junto con B.
- **Decisiones de Miguel pendientes:** solo Leads o también Pipeline · «Sin marcar» como opción · uno o varios
  niveles a la vez. Recomendado: solo Leads, con «Sin marcar», uno a la vez.

## Fase 3 · entrega B: ejecución (01/10/2026, noche)

**Decidido por Miguel:** solo en Leads (no en Pipeline) · «Sin marcar» es una opción · un nivel a la vez.
**Estado (01/10 ~19:20 Lima): NADA publicado.** Rama `crm/potencial-lead-f3b` (`364a0fc9`, en GitHub; ya integra
`avancecorp/main` `fd169aac`, que trae el color #163 y el refactor #164). **PR #165 en BORRADOR** hasta repetir el
ciclo sobre un volcado nuevo de producción. Commits: pantalla `70ae49c4`, servidor `dd44c806`.

### Qué se ve
Fila «Por potencial» debajo de «Por etapa», en la misma tarjeta de resumen: cuatro pastillas con número (Frío, Tibio,
Estrella, Sin marcar). Tocar una filtra lista, totales y capital; los cuatro números NO cambian al elegir (se cuentan
antes del filtro); una cifra en cero no se abre; la elegida se pinta con el color de su nivel. Maqueta local a escala
real: `ui-playground/filtro-potencial-leads.html`. ✅ **Miguel la aprobó el 01/10 (~19:04): «sí me gusta la
maqueta»** (la variante construida: el botón elegido se pinta con el color de su nivel). Fotos de la app real en el
scratchpad `f3b/capturas/`.

### Servidor — migración `20261001212341_crm_cartera_filtro_potencial` (SIN aplicar)
- `crm.cartera_filtrada_fn` pasa de 13 a 14 argumentos (`p_potencial`: `estrella|tibio|frio|sin_marca`) y el resumen
  gana `resumen.potencial = {filtro, estrella, tibio, frio, sin_marca}` contado sobre `previa` (antes del filtro).
  🔴 La base ya era la de 13: la sesión del Pipeline «Gestionado» añadió `p_gestion` el mismo día. El cuerpo nuevo se
  GENERÓ desde el texto de su migración con sustituciones exactas (una función viva no se reteclea).
- Ayudante `private.cartera_potencial_fn()` DEFINER (las tablas del potencial no tienen grants): sesión + gate +
  bandera + **espejo exacto de `leads_select`** (CUARTA copia de esa policy).
- 🔑 **Decisión de ámbito.** La primera versión daba al ayudante el predicado de la base de la cartera (con la bandeja
  del reparto) para que `crm.resumen_cartera_fn` —DEFINER, llama a la cartera SIN RLS— contara bien. Codex y el
  auditor-rls vieron que así coordinación recibía conteos por nivel de leads que su RLS no deja leer. Se cambió sin
  preguntarle a Miguel porque la alternativa no amplía nada: espejo de la RLS, y la cartera no emite
  `resumen.potencial` (ni llama al ayudante) para quien no tiene ámbito de filas. Regla: ve y cuenta la marca solo
  quien ve el lead.
- Con la bandera apagada: respuesta byte a byte la de la firma de 13 y 55000 si se pide el filtro.
- Huellas: cartera de 14 `23a63cc3…`, ayudante `73e993d6…`; la de 13 que se sustituye `bf06666f…`.
- Evidencia en el banco `avancecorp-potencial-20261001` (`banco/ciclo-fase3b.sh`, veredicto de máquina «TODO COMO SE
  ESPERABA»): 145 de 145; fases 1, 2 y 3A sin regresión (75, 51, 94); el oráculo de gestión de la otra sesión
  128/128 contra la firma de 14; 28 mutantes de lógica, 51 de migración/preflight y 8 de la reversa, ninguno
  sobrevive; reversa byte a byte; +1,5 a 2 ms por llamada. (Cifras finales: 152 de 152.)
- Reviews: Codex r1 (2 P2 de verificación), auditor-rls (sin P0/P1) y Codex r2 (diseño confirmado; 3 P2 y 1 P3 de
  VERIFICACIÓN: bloque vacío en el verificador de sumas, oráculo caído en «ayudante ⊆ RLS», reversa que no veía `:=`
  ni llamadas por posición → censo estricto de consumidores, y `PGRST106` en el gate). Todo aplicado. Rondas agotadas.
- NOT RUN: `test-rls.mjs` con sesiones reales (bloque `testPotencialFiltro` escrito) y advisors.

### Pantalla (sobre `main`, que ya trae Gestionado #162 y Llamadas #160)
`lib/potencial.ts` (tipos del filtro y esquema de conteos), `crm-api.ts` (`p_potencial`, eco y coherencia, 55000 →
`POTENCIAL_APAGADO`), clave de caché, `use-cartera-paginada.ts` (espejo demo + limpiar caché si el servidor apaga el
potencial), `potencial-filtro.tsx` + CSS, `cartera.tsx`, simulador e2e. Marcar un lead refresca la lista y los
números. revisor-a11y aplicado (foco cuando la fila se retira, aviso, cifra en cero legible). e2e del potencial 13 de
13; suite completa 320 pasan y los mismos 2 fallos ajenos de `main`.

### Lo que falta, en orden
1. ✅ Codex r2 aplicado, `npm run check` PASS (346 archivos, 5 592 pruebas), commits y PR #165 (borrador).
2. **Volcado NUEVO de producción (Miguel con `!`)** → banco nuevo a paridad → repetir `ciclo-fase3b.sh` ahí.
3. Miguel publica el servidor con `!`: migración → `registrar-filtro.sql` → `verificar-filtro.sql` → sonda HTTP →
   advisors → `gen:types`.
4. Pantalla: `/release-crm`. 🔴 Se construyó sobre `main`: para publicarla, las pantallas de Gestionado (#162) y
   Llamadas (#160) tienen que estar ya vivas o salir junto con ella (el vivo hoy es `83674f19`, sin ellas).

### Lecciones de esta entrega
1. **Un envoltorio DEFINER se salta la RLS de la función INVOKER que envuelve.** `crm.resumen_cartera_fn` llama a la
   cartera como dueño: toda clave nueva del resumen sale también por ahí, con el ámbito del PREDICADO de la función y
   no el de la RLS. Antes de añadir una clave, preguntar a `pg_proc` quién envuelve y probar esa ruta.
2. **Un banco de solo esquema no trae el trinquete analítico** (`private.analitica_leads_citas_exenciones`, sello):
   toda migración que toque `cartera_filtrada_fn` se niega. Sembrarlo con
   `scripts/cartera-gestion/siembra-control-banco.sql` (de la otra sesión), no desmontar la guarda.
3. **El kit de otra sesión atado a una firma no se edita:** su oráculo se corre contra la firma nueva cambiando al
   vuelo solo la firma y su aserción de forma (lo hace el ciclo); en su README, una nota.
4. **Un verificador que compara con `is distinct from` acepta errores** (NULL contra NULL): contar aparte las
   respuestas nulas, con error o sin el bloque, y probar el verificador con una respuesta rota.
5. **El ciclo termina con veredicto de máquina** (sale con 1): un superviviente no puede depender de que alguien lea.
6. **`sed` de macOS no entiende `\n` en el reemplazo:** para partir líneas, Python.

## Propuesta INICIAL de servidor (superada: ver «Fase 1 · ejecución» y «Fase 2»)

- La sugerencia de Jev ya tiene casa en `crm.lead_temperatura` (F1 de temperatura, escrita y
  **sin branch**). Traducción propuesta: 0 → Frío · 1–2 → Tibio · 3 → Estrella (3 = «dio
  fecha, monto o pidió el contrato»: Jev es conservador con la estrella).
- La marca del analista: columnas nuevas en `crm.leads` (nivel, quién, cuándo) con grants por
  columna, una puerta `crm.marcar_potencial_lead` y su línea en el historial.
- Vale lo del analista; si no marcó, se muestra la sugerencia de Jev.

## Abierto

- «Frío» no es descartar: el descarte con motivo sigue siendo la única salida.
- ✅ Al reasignar el lead, la marca viaja con él y la cuenta de días sigue igual (confirmado por Miguel el 01/10/2026).
