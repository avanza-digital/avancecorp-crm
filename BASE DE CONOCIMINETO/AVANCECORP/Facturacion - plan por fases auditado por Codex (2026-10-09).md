# Facturación — plan por fases (09/10/2026, revisado y auditado por Codex)

## Contexto

- **Problema.** Facturación ya da cifras correctas: auditoría del 08/10, datos corregidos, fase 1 publicada (#229) y regla de bajas publicada hoy (#233/#234). Pero:
  - ningún número se abre para ver qué contratos lo forman;
  - la pantalla no se lee como una hoja de Excel;
  - el «supervisor de entonces» puede equivocarse cuando alguien cambia de equipo sin dejar rastro.
- **Objetivo.** Cada número abre la lista que lo forma y suma lo mismo; la pantalla se lee como una hoja; ningún cambio de equipo se pierde.
- **Meta.** Cumplir tus reglas «todo número se abre» y «listas como hoja de Excel» sin mover un sol de lo facturado y sin abrir datos a quien no debe verlos.

## Ya hecho (no se repite)

- **Datos:** los 12 «nuevo» que eran upgrades; limpieza del perfil de pruebas; 111111 eliminado con auditoría; 001490/001484 no es un duplicado.
- **Fase 1 de pantalla (#229):** el % del titular; «Total» solo con tipo de cambio; supervisor en el celular; cabecera fija; Directorio ve Facturación.
- **Regla de bajas (#233/#234):** quien está de baja no aparece y lo suyo cuenta a quien recibió a sus clientes. Ivette se queda a su nombre.

---

## FASE 0A — Asegurar septiembre ANTES del sello *(hoy o el 11/10 antes de las 09:20)*

- **Qué se hace:** una vista previa, solo leyendo, de lo que va a congelar el sello: septiembre por analista y moneda. Hay que confirmar que no salen ni Pierina ni Noelia, que Ivette sí sale y que los totales cuadran con Facturación.
- **Qué ves tú:** una tabla de septiembre tal como quedará sellado. Si algo no te cuadra, se para antes del sello.
- **Cómo se comprueba:** la misma cuenta que usa el sello (ya comprobé hoy que lee el capital con la regla de bajas).

**✅ HECHA 09/10 ~16:00 Lima (solo lectura).** Capital de septiembre: 34/34 filas idénticas entre lo que congelará el sello
(`produccion_mes_por_vendedor`) y Facturación (`capital_episodios`); ni Pierina ni Noelia con capital; Elizabeth Chiroque
S/ 88.000 (las 4 cooperativas de Noelia) + US$ 1.000; Ivette sin ventas en septiembre. **Conversión:** Noelia SÍ sale en el sello
(tiene meta de septiembre, objetivo 15 %): 108 leads, 3 cierres, 2,78 %, capital S/ 0. **Decisión de Miguel: «dejar que se
selle»** (su conversión de septiembre es suya; su capital cuenta a Elizabeth). El sello (cron `crm-cierre-mes-diario`,
`20 14 * * *` UTC = 09:20 Lima) incluye además a cualquier vendedor con producción y supervisor, aunque no tenga meta.

## FASE 0B — Comprobar la foto sellada *(el 11/10, después de las 09:20)*

- **Qué se hace:** comparar la foto sellada con la vista previa de 0A.
- **Qué ves tú:** «septiembre sellado = vista previa», o la diferencia exacta.

## FASE 0C — Red de pruebas antes de tocar el servidor *(~medio día)*

- **Qué se hace**
  - Poner al día con la regla de bajas la prueba de base de datos de Facturación y meterla en el gate de seguridad, que hoy no la corre.
  - Meter Facturación en el gate de realidad, que prueba con el estado real de producción y no solo con el de las pruebas.
  - Una prueba para la lectura de Facturación en la pantalla.
  - La prueba de Gestión Diaria que se cae cuando está la configuración real del front queda registrada a nombre de su dueño, con su alcance exacto.
- **Qué ves tú:** nada en pantalla. Desde aquí, cualquier error en Facturación salta en las pruebas.

**Fase 0C ✅ (09/10 tarde):** `test-facturacion.sql` al analista efectivo y EJECUTADO por el bloque K de `test-rls.mjs`
(antes solo se nombraba); supuesto `facturacion_ventas_de_analistas_de_baja` en `gate-realidad.mjs`; 4 pruebas MSW de
`listarFacturacionDiaria` (mutante cazado). Gate RLS REAL en banco completo propio (stack `avancecorp-fact0c-20261009`,
puertos 5642x, huellas = producción): 3077 aserciones, 9 rojos todos de fondo (potencial ×4, R2 ×3, fila bancaria, B7) y los
12 oráculos de Facturación PASS. Al banco le faltaba `crm.llamadas_celular_politica` (config del 07/10): sin ella, 34 rojos
falsos de llamadas.

**Decisiones de Miguel (09/10) para la fase 1:** maqueta APROBADA · días por venir PLEGADOS · vista Día POR TIPO.

## FASE 1 — Facturación se lee como una hoja de Excel *(solo pantalla; puede avanzar en paralelo, ~1–2 días)*

**Antes de programar:** abres la maqueta (`ui-playground/facturacion-hoja-excel.html`) a escala real y la apruebas.

**Qué se construye**
- **Arriba:** pastillas pequeñas en lugar de las 4 tarjetas grandes.
- **Hoja:** número de fila, equipos como bandas, nombre a la izquierda y total a la derecha siempre visibles.
- **Letra:** 16 px en nombres y 14 px en el resto.
- **Días por venir:** plegados en una sola columna.
- **Vista Día:** columnas por tipo. Los datos ya vienen por tipo, así que no hace falta tocar el servidor.
- **Celular:** una tarjeta por analista, agrupadas por equipo.
- **Sueltos de la auditoría:**
  - foco visible al usar el teclado;
  - lista y títulos accesibles;
  - «Sin supervisor» una sola vez;
  - comparar meses no bloquea la malla;
  - formatear las cifras sin trabarse.
  - Un mes cerrado se refresca **menos seguido**, pero **no se congela**: puede cambiar, como cambió hoy con la regla de bajas.
- Se conserva la forma accesible de «Ver el mes completo de…»; sus pruebas se adaptan, no se borran.

**Qué ves tú:** la maqueta aprobada, ya funcionando.

**Cómo se comprueba**
- Check del front y e2e en Docker a 1440 y a 390.
- Revisión de accesibilidad y gate de realidad.
- Las cifras de la pantalla, idénticas antes y después.
- Sale con `/release-crm`.

**Apta:** sí. No toca el servidor y se revierte publicando el build anterior.

**Fase 1 ✅ PUBLICADA (09/10 ~17:20 Lima):** PR #241 (`5f28b73c`), release `crm-20261009T221752Z-5f28b73c8c27`
(buildId `build-20261009T221751908Z`), preflight OK sobre el vivo `f379931c`, smoke OK (portada 200, JS idénticos al
artefacto, fragmento de la hoja publicado). Check 402/6502; e2e 18/18; revisor-a11y P1/P2 cerrados (el contexto de las
pastillas se ve en una línea; el tooltip es solo redundancia).

## FASE 2 — Ningún cambio de equipo se pierde (prevención) *(nivel 3, ~1 día)*

- **Qué se construye:** la base anota sola cada cambio de supervisor, venga de donde venga:
  - la pantalla;
  - la baja con reemplazo;
  - el alta;
  - las migraciones;
  - las operaciones internas.

  Es una sola pieza en lugar de varias que hoy se olvidan.
- **Qué ves tú:** nada en pantalla. Desde ese día, ninguna baja de supervisor ni ningún movimiento de equipo cambia el equipo de ventas pasadas.
- **Por qué va antes que las listas:** mientras no esté, cualquier baja de supervisor deja un hueco nuevo, y la pieza va en otra parte de la base: no estorba a las fases 3 y 4.
- **Cómo se comprueba:**
  - prueba de cada vía que cambia de supervisor, incluidas las repeticiones y los cambios simultáneos;
  - si anotar falla, el cambio de equipo tampoco se hace;
  - banco, auditor de seguridad y Codex.

**Fase 2 ✅ APLICADA EN PRODUCCIÓN (09/10 noche):** migración `20261009223000_crm_jerarquia_evento_en_toda_via` registrada
(md5 `b41616ad…`), PR #240 (después de la #237). Un trigger de `crm.equipo` es el único escritor de `jerarquia_actualizada`;
autor «sistema» = `f6d2941b-2e93-4c81-9a27-0c5e786b104d` para lo que no hace una persona (decisión de Miguel). Banco:
ensayo 22/22, mutante 10/22, negativas, gate sin rojos nuevos; auditor-rls sin P0/P1 (su P2 —el oráculo dependía del día—
arreglado en la #237 y probado forzando días 4 y 18). Ensayo en producción OK; verificado tras aplicar: 2 triggers
activos, ACL solo postgres, los 16 eventos previos intactos, advisors sin avisos nuevos.

## FASE 3 — «Todo número se abre»: el servidor *(nivel 3, en dos partes)*

**Antes de empezar decides:** cuando un mes ya está sellado, ¿Facturación muestra la foto sellada o la cuenta viva? Hoy es la viva, y la lista tiene que salir de la misma fuente que la cifra.

**Fase 3A ✅ APLICADA EN PRODUCCIÓN Y REGISTRADA (09/10 noche):** PR #242 fusionada (`0bac1e77`, `main` al día), migración `20261009224000` (md5 del texto `4665b950…`). Ensayo en producción: 13 meses (2025-09 a 2026-10), 1454 = 1454 filas, 820 operaciones, 4 supervisores con filas (no hay Directorio activo en producción), 1,9 s. Medición: septiembre 22,6 → 20,7 ms; octubre 11,2 → 10,4 ms. La cifra sale de una lista de operaciones (`private.facturacion_operaciones`, sin verja; `private.facturacion_operaciones_visibles`, la verja al byte); la puerta es un `group by` con la misma salida (oráculo en la misma transacción para Gerencia, Directorio, cada supervisor, vendedor y sin sesión). Banco: ciclo, 12/12, gate sin rojos nuevos + censo de llamadores, 4 mutantes cazados. auditor-rls y Codex sin P0/P1. Precondición: la fase 2 registrada; reversa antes que la de la fase 2. **Fase 3B ⏸️ EN PAUSA (09/10 ~19:00, pedido de Miguel):** encargo escrito (puerta `crm.listar_operaciones_facturacion_fn`, capa 1 = la misma pieza que la cifra, capa 2 = «Cliente de otro equipo» sin nombre ni ids, DNI nunca). Codex se detuvo a mitad: sus archivos parciales en el worktree `facturacion-fase3b-20261009` se revisan o se rehacen al retomar. La maqueta de la hoja lateral (fase 4) está encargada pero sin crear. Nada pendiente en producción.

**Fase 4 ✅ PUBLICADA (10/10 madrugada, `5a7fb9db`):** cada número de Facturación abre la hoja lateral con sus operaciones (maqueta aprobada; montos con coma). Accesibilidad revisada dos veces; check y e2e completos en verde. Se publica con `/release-crm`.

**Fase 3B ✅ APLICADA EN PRODUCCIÓN Y REGISTRADA (09/10 noche):** PR #244 fusionada (`46c238c9`, `main` al día), migración `20261009234500`. La puerta `crm.listar_operaciones_facturacion_fn` entrega la lista de cada número (misma fuente que la cifra; días/días sueltos, analista o sin analista, equipo o sin equipo, tipo, moneda; páginas 25/50/100; «Cliente de otro equipo» sin ids; DNI nunca; Directorio: cooperativas enmascaradas). Ensayo en producción: 13 meses, 1628 filas, 14 enmascaradas; página 13–32 ms.

**Fase 4 — maqueta APROBADA por Miguel (09/10 noche):** `docs/encargos/maqueta/facturacion-lista-operaciones.html` (copia de `ui-playground/`). Hoja lateral NO modal (~46 % a 1440), título en palabras, pastillas por moneda + línea «Cuadra», tabla tipo Excel (fijos # · Fecha · Monto; N.º/Analista/Supervisor deslizando), «Anulada · cuenta igual» bajo el cliente, «Cliente de otro equipo» apagado con su línea, páginas 25/50/100, cero → «Sin operaciones», promedio → su base con la cuenta, «Hay cifras nuevas · Actualizar» sin recarga sola, celular = panel inferior con tarjetas. Montos CON COMA como hoy («S/ 25,000»). La puerta 3B necesita `p_dias date[]` (días sueltos marcados de la hoja, regla de Miguel del 11/09).

**Corrección de Miguel (09/10 noche):** Directorio ve las operaciones de COOPERATIVAS como «Cliente de otro equipo» (sin nombre), igual que en el resto del CRM; los contratos sí con nombre. La decisión anterior se tomó creyendo que el CRM ya le mostraba esos nombres, y el auditor comprobó que no.

**Decisiones de Miguel (09/10 noche) para la fase 3:** mes sellado = CUENTA VIVA, como hoy · cliente de otro equipo = «Cliente de otro equipo» con importe (sin nombre ni N.º) · Directorio SÍ ve nombres de cooperativas · DNI nunca · sin registro de quién abre listas (recomendaciones del plan).

**3A — Una sola fuente** *(~1 día)*
- La cifra de hoy pasa a calcularse desde una lista de operaciones (contratos y cooperativas), así que lista y cifra ya no pueden diferir.
- **Oráculo, en la misma transacción y sobre los mismos datos:** toda la salida idéntica antes y después (día, analista, supervisor, tipo, moneda, número de operaciones e importe), en todos los meses con datos, para Gerencia, Directorio y varios supervisores.

**3B — La puerta de la lista y sus permisos** *(~1 día)*
- **Filtros:** días, equipo, uno o varios analistas, tipo y moneda.
- **Páginas:** de 25, 50 o 100, con un orden fijo que nunca repite ni salta una fila.
- **Permisos en dos capas:**
  1. **Qué operaciones** ve cada uno: exactamente las que forman su cifra.
  2. **Qué datos** de cada una:
     - si el cliente no es visible para quien mira, sale «Cliente de otro equipo» con su importe;
     - el DNI no sale nunca.

  Se revisa la respuesta completa (identificadores y enlaces incluidos), no solo lo que se pinta.
- **Rendimiento:**
  - la cifra del mes no puede pasar de la línea base del día +20 %;
  - una página de la lista, con totales, en el mes más grande, debe ir por debajo de ~150 ms.

**Qué ves tú:** nada todavía; las cifras no se mueven.

**Cómo se comprueba:**
- banco Docker y oráculo;
- pruebas por rol (Gerencia, Directorio, supervisor, vendedor, persona de baja y anónimo);
- auditor de seguridad, Codex y ensayo en producción que se deshace;
- la aplicas tú con `!`.

## FASE 4 — «Todo número se abre»: la pantalla *(~1–2 días)*

- **Qué se construye:** cada número (pastillas, celdas, total de fila, de día y de equipo) abre una hoja lateral con la lista. La hoja lateral:
  - tiene número de fila y encabezado fijo;
  - muestra subtotales por moneda;
  - en el celular se ve en tarjetas;
  - marca «Anulada · cuenta igual».

  Un cero abre «sin operaciones». Un % o un promedio abre la lista de su base, con una línea que explica la cuenta.

  Si la cifra y la lista dejan de cuadrar porque alguien acaba de vender, aparece un aviso «hay cifras nuevas · actualizar»; no se recarga solo en bucle.
- **Qué ves tú:** pulsas cualquier número y ves los contratos y cooperativas que lo forman, sumando exactamente eso.
- **Cómo se comprueba:** check, e2e, accesibilidad y `/release-crm`.

## FASE 5 — Corregir el pasado de Carmen y Jorge *(nivel 3, después de medir)*

- **Qué se hace:** primero se mide si Carmen Jaramillo y Jorge Marzano vendieron entre el 10/08 y el 29/08, cuando cambiaron de equipo sin dejar rastro. Solo si tú lo apruebas viendo el cambio mes a mes, se anota con pruebas.
- **Qué ves tú:** el cambio exacto antes de aplicarlo. Si no vendieron en esa ventana, no cambia nada.

### ✅ APLICADA en producción el 10/10/2026 ~11:00 Lima (Miguel con `!`)

Migración de solo datos `20261010150451_crm_jerarquia_relleno_carmen_jorge.sql` (PR #248), registrada con md5 del texto `00fb0e49…`. Dos eventos `via: 'relleno'` (autor «sistema») a las 12:56:38 del 29/08. Comprobado después: las 9 ventas de Jorge desde el 29/08 salen con ADMINISTRADOR; `medir-relleno.sql` ya no lista a Carmen ni a Jorge. Banco 14/14, Codex r1 sin P0/P1 (aceptados 2 P2: la reversa comprueba todos los campos del evento; candados en `crm.equipo` y `crm.usuario_eventos` antes de la instantánea) y ensayo de producción PASS antes de aplicar. Kit: `CRM-Avance-Corp/supabase/scripts/jerarquia-relleno/`; reversa: `reversa.sql`.
- Carlos Valles sigue de supervisor en 10 ventas de **AVANCECORP** (ventas propias de la empresa, mayo–octubre): su supervisor HOY es Carlos y no tiene derivas. No era parte de la fase 5.

### Medición en producción (10/10/2026 09:51 Lima, solo lectura) — aprobada por Miguel

- **Hora exacta, sin ventana:** `public.audit_log` registra el cambio de Carmen y Jorge (los dos son **supervisores**): CARLOS VALLES → ADMINISTRADOR AVANCE CORP el **29/08 12:56 Lima**, sin autor (el bloque `$normalizar_directorio$` de `20260828210351`); `crm.equipo.actualizado_en` dice la misma hora. Carlos pasó de Directorio a Gerencia a las 16:47.
- **Entre el 10/08 10:44 (su evento) y el 29/08 12:56: 0 ventas** de los dos.
- **Qué cambiaría el relleno** (un evento por persona, con esa hora): Carmen nada (sin ventas desde el 29/08); Jorge, 9 ventas pasan de «Carlos Valles» a «Administrador Avance Corp» en la columna Supervisor — septiembre 4 × S/ 1,271,900 + 1 × US$ 27,000; octubre 3 × S/ 213,600 + 1 × US$ 20,000. Totales de la empresa, agosto (sellado) y lo que ve cada supervisor no cambian (Carlos y Administrador son Gerencia).
- **Solo Facturación lee estos eventos** (`pg_proc` en prod: `private.facturacion_operaciones` + el trigger y las 2 RPC que los escriben): la foto del sello no los usa.
- **Fiabilidad:** el lado «hoy» sale de la función viva; la réplica de sus tramos coincide en 821/821 operaciones y, en el banco, la simulación = insertar el evento de verdad en 3 escenarios. Huellas de prod = las de la 3A.
- **Fuera de alcance, no se toca:** Ivett Teevin, 3 ventas mar–jun (S/ 121,400) «Sin supervisor»; la auditoría solo prueba que Jorge fue su supervisor del 15/07 (inicio del registro) al 20/07.
- Script y resultado: `AVANCECORP-desktop-worktrees/facturacion-banco-20261009-NO-VERSIONAR/fase5-medicion-20261010/`. La fase 2 aplicada NO trae candado ni válvula en `crm.usuario_eventos`: el relleno inserta directo (actor sistema `f6d2941b…`, `via:'relleno'`, id de la fila de auditoría como prueba) y su postflight exige exactamente este diff.

## Junto a la PR #236 de la otra sesión

Cuando esa sesión aplique su regla «sin ficha de cartera → solo nuevo», sale a la vez la parte de pantalla:
- «Corregir» deja de ofrecer cambiar la categoría cuando hay operación de cartera;
- el rechazo se explica en palabras.

La otra sesión ordena su migración en el historial.

## FASE 6 — Sueltos que necesitan una decisión tuya

1. **Cooperativas que en realidad son reinversiones** (10 casos, S/ 97.300 + US$ 10.000): ¿cuentan como capital nuevo?
2. **Ficha del inversionista:** que «Analista de la operación» distinga quién lo registró y a quién cuenta.

**Decidido por Miguel el 10/10/2026, viendo datos de producción (solo lectura):**
1. **Cooperativas: siguen contando como hoy. Punto cerrado.** No son reinversiones:
   - ninguna llega tras un depósito vencido;
   - el flujo formal de reinversión no se ha usado nunca (`crm.inversion_solicitud_origenes` vacía);
   - 4 son clientes que el mismo día firmaron también con Avance.

   Son dinero nuevo de clientes que ya tenían otra inversión. El rótulo «reinversiones» de la auditoría era impreciso.
2. **Ficha: «los dos nombres».** «Analista de la operación» muestra quién vendió. Debajo, «Cuenta para» muestra a quién cuenta hoy (cadena de upgrade o baja), solo cuando son personas distintas. Si no consta quién vendió, sale «Sin información».
   - En producción difieren 46 de 820 inversiones, todas de 2 analistas dados de baja.
   - Migración `20261010203951_crm_ficha_analista_venta.sql` (kit `supabase/scripts/ficha-analista-venta/`): el cuerpo vivo más dos fragmentos.
   - Verificación: banco 27/27, front con 4 mutantes, `npm run check` PASS y e2e 44/44.
   - Revisión de Codex r1: sin P0/P1; sus 4 P2 están corregidos.
   - auditor-rls: PASS. Ensayo en producción: PASS.
   - **APLICADA en producción el 10/10** (Miguel con `!`; texto `a163657c…`). Comprobado: huella `9d981c6c…`, comentario, permisos y advisors sin avisos nuevos.
   - **PUBLICADA el 10/10** (~20:35 Lima): PR #252 fusionada, release `3f81c40f` (`build-20261011T013450162Z`), preflight OK, smoke byte a byte. La fase 6 queda cerrada; del plan solo queda la 0B (11/10).

## Qué NO cambia

- Ni un sol de lo facturado: cada fase de servidor lleva oráculo completo.
- La regla de bajas, la de upgrades y las fotos selladas.
- Los permisos de hoy: nadie ve una operación que no forme ya su cifra.

## Orden

- **0A → 0B → 0C → 2 → 3A → 3B → 4 → 5.**
- La **fase 1** puede avanzar en paralelo en cuanto apruebes la maqueta.
- La parte de pantalla de la #236 sale cuando la otra sesión la aplique.
- La **fase 6**, cuando decidas.

## Decisiones tuyas (recomendada primero)

| Antes de | Decisión |
|---|---|
| Fase 1 | Aprobar la maqueta · días por venir **plegados** / ocultos · vista Día **por tipo** / lista del día |
| Fase 2 | Cambio hecho por el sistema o una migración: **anotarlo como «sistema»** / sin «quién» |
| Fase 3 | Mes sellado: **cuenta viva, como hoy** / foto sellada · cliente de otro equipo: **«Cliente de otro equipo» con importe** / nombre · Directorio y nombres de cooperativas: **sí** / no · DNI: **nunca** · registro de quién abre listas: **no** |
| Fase 5 | Aprobar el relleno de Carmen y Jorge viendo el cambio |
| Fase 6 | Reinversiones en cooperativas · ficha del inversionista |

---

## Auditoría de Codex (09/10) y decisión del PRIMARY

**Veredicto:** CHANGES_REQUESTED, sin P0. Incorporado:
- **P1-1:** 0A antes del sello; la decisión sobre los meses sellados pasa a requisito de la fase 3.
- **P1-2:** la prevención de jerarquía se adelanta (fase 2) y el relleno va aparte (fase 5).
- **P1-3:** permisos en dos capas: operaciones y datos.
- **P1-4:** oráculo completo en la misma transacción.
- **P1-5:** contrato del registro de equipo (ver anexo).
- **P1-6:** OK del plan ≠ `!`; orden explícito.
- **P2-1:** la pantalla de categoría va junto a la #236.
- **P2-2:** fase 0C con las pruebas antes del servidor; el rendimiento pendiente tiene destino (fase 1: formateo; fase 3: trabajo descartado en el servidor).
- **P2-3:** umbrales de rendimiento.
- **P2-4:** la fase 1 demuestra que es independiente: la vista Día ya tiene los datos por tipo, el mes cerrado no se congela y las pruebas de «Ver el mes completo» se conservan.
- **Estimaciones:** divididas y provisionales.

**No incorporado, con motivo:**
- Fusionar ANTES de aplicar. La regla de la casa es aplicar y fusionar a `main` el mismo día, y `main` debe contener lo aplicado; se mantiene la secuencia de hoy.
- CERRAR→OBSERVAR→DERRIBAR para las copias de trabajo locales. Esa regla es para producción.

## Anexo técnico (para la ejecución)

**Base:** `main` = VIVO = `9dc0b087`. Las líneas de los planes del 08/10 (`c0bff295`) se desplazan +1 en `facturacion.tsx`.

**Proceso**
- **Servidor:** decisiones y OK del plan → worktree propio → banco Docker (`montar-banco.sh` + configuración copiada de producción) → oráculo y mutantes → `auditor-rls` → Codex (`scripts/codex-review-mcp`) → PR con CI verde → ensayo y medición en producción con `raise` (solo DDL/SELECT, sin efectos externos) → Miguel aplica con `!` y registra → fusión a `main` el mismo día → `main` al día.
- **Pantalla:** worktree limpio → check (el fallo con el `.env` real se declara; vale el CI y el check sin `.env` sobre el mismo árbol) → e2e en Docker → `revisor-a11y` → PR → fusión → `/release-crm` desde el commit fusionado.

**Fase 0A:** `crm.cerrar_periodo` → `private.produccion_mes_por_vendedor` → `private.capital_episodios` (analista efectivo). Vista previa = `produccion_mes_por_vendedor('2026-09-01'…)` y `capital_episodios` por analista y moneda, más la conversión (`conversion_mensual_por_vendedor`), en solo lectura.

**Fase 0C**
- `supabase/scripts/test-facturacion.sql` elige el analista con `analista_atribuido_cadena`: pasarlo a `analista_efectivo_contrato/_cierre`.
- Engancharlo en `test-rls.mjs :9408-9413`.
- `gate-realidad.mjs`: añadir el supuesto de Facturación.
- Test de `listarFacturacionDiaria` (`crm-api.ts:4705`).

**Fase 1**
- `app/src/screens/facturacion.tsx`:
  - KPIs `:1266-1340`, `KpiCard` sin `onClick`.
  - `Celda` `:257-323`, con `valor>0`.
  - Panel `:1813-1891`.
  - Celular solo con CSS, sin `useEsMovil`.
- `lib/facturacion.ts`.
- Refresco: `crm-queries.ts:869`.
- Reutilizar:
  - `Pastilla` (`base-gestion/filtros-base.tsx:22`, ampliar a valor formateado);
  - las constantes `CELDA`/`ENCABEZADO` de `hoja-base.tsx` (no `HojaBase`, que está cableada a leads; añadir la columna fija a la derecha);
  - `Paginacion`;
  - `NumeroAbrible`/`AvisoReintentar` (`bases-cargadas/piezas-bases.tsx`);
  - `useEsMovil` (`lib/media.ts:35`).
- La vista Día por tipo sale de `facturacion_diaria_fn`, que ya devuelve `tipo` por día.

**Fase 2 (contrato del registro)**
- Trigger AFTER INSERT/UPDATE OF `supervisor_id` en `crm.equipo` como único escritor de `jerarquia_actualizada`. En la misma migración:
  - quitar el evento de `actualizar_jerarquia_usuario_fn` y `registrar_vendedor_usuario_fn`;
  - re-anclar sus repeticiones idempotentes, que hoy cuentan eventos (`20260807203740:1541-1555`, `20260821233241:63-84`).
- **Actor:** `actor_id NOT NULL` y `unique(actor, accion, idempotencia)`. Recomendado: un «sistema» fijo, porque un NULL rompería la unicidad. La idempotencia se deriva de la transacción y de la fila.
- **Una fila = un evento.** Sin cambio real, no hay evento. El fallo del evento revierte el cambio.
- **Garantía acotada:** quien desactive triggers o use `session_replication_role` queda fuera; se declara.
- **Supervisor histórico NULL:** sigue usando el de hoy (sin cambio de regla), salvo decisión.
- Nuevo timestamp con `/nueva-migracion`: `20261009120000` está ocupado.
- **Pruebas:** las 7 vías, repeticiones, concurrencia, `on delete set null`, migración sin sesión y `service_role`. Actualizar `test-usuarios-jerarquia.sql`, que cuenta 4 y 3 eventos.

**Fase 3A**
- `crm.facturacion_diaria_fn` (`20260916205617:78-213`, huella `79d75db2…`) → núcleo `private.facturacion_operaciones(p_desde, p_hasta)`, una fila por operación, construido sobre `private.capital_episodios` (`20261009200000:241`).
- La función pública pasa a ser un `group by`, con la misma firma, columnas y orden.
- No anidar SQL por fila (memoria `sql-anidado-replanifica-por-fila`).

**Fase 3B**
- Puerta `crm.listar_operaciones_facturacion_fn` en jsonb, con el patrón de `crm.cartera_inversionistas_filtrada_fn` (`20260916023055:4-126`; aquí los tamaños son 25/50/100).
- Orden `(fecha, tipo, id)`.
- **Capa de operaciones** = ámbito de la cifra (`:95-117, :205-207`).
- **Capa de datos:**
  - contratos con `private.cliente_ids_visibles_crm()` (`20260828210351:459-491`);
  - cooperativas con `private.analista_efectivo_cierre(ce.id) = any(vendedor_ids_visibles)`, como `crm.cierres_externos_fn` (`20261009200000`).
- Núcleo revocado; puerta solo para `authenticated`; `anon` sin `EXECUTE`.

**Fase 4**
- `ListaOperaciones` con el molde de `base-gestion/detalle-cifra.tsx`, pero no modal y paginada (`DetalleCifra` es modal y sin páginas).
- `parametrosDeCifra()` puro.
- Aviso de cuadre sin bucle.

**Fase 5:** `medir-relleno.sql`, corregido a `capital_episodios` de `20261009200000`. Relleno con `via:'relleno'` y evidencia.

**Junto a #236**
- `contrato-corregir.tsx:268,:523-531`.
- Traducir el 23514 de categoría en `crm-api.ts:2484-2488`.

**Fase 6:** `inversionista-ficha.tsx:113`.

## Verificación global

- **Servidor:** oráculo completo en la misma transacción y, tras aplicar, comparación en producción de septiembre y octubre por rol, como smoke.
- **Pantalla:** smoke del release (JS idéntico al artefacto) y comparación con la maqueta aprobada.
- **Al cerrar cada fase:** «¿apta para producción?» y «qué arregla comercialmente».
