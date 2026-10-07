# F4-c y F4-d — plan corto (06/10/2026, solo análisis)

Salió de un análisis de solo lectura del 06/10. Las citas marcadas **[V]** las verificó ese análisis en el archivo y la
línea; Claude volvió a comprobar las dos que cambian el plan (el hueco del id de origen y la fuga del latido).

**Actualización 07/10/2026:** el #190 se fusionó el 06/10 (`d1f16fea`) y **F4-c ya está programada** en la rama
`crm/llamadas-f4c-celulares-20261006` (ver «Decisiones al programar», abajo). Prototipo aprobado por Jhosep el 06/10:
https://claude.ai/artifact/8ueovxHiTE5vqUyWXiAHcA (privado).

## En una línea

- **F4-c**: tarjeta «Celulares» en Configuración, solo para gerencia. Sirve para asignar, rotar y cerrar celulares y
  para ver su salud.
  - Es pantalla sobre puertas que ya existen, **sin migración**.
- **F4-d**: activar C1 de verdad: alta de la clave, macro con el id de la llamada y las pruebas de F4.4.
  - Casi no lleva código: es operación en producción y su evidencia.

## Decisiones ya tomadas (Jhosep, 06/10)

| # | Decisión | Por qué |
| --- | --- | --- |
| 1 | **F4-c espera al #190** (no se programa todavía) | Ordenarnos con Miguel: no crecer el #198 mientras él prueba la base |
| 2 | **Hueco «registrar desde la pestaña no une»** → décima migración (`20261006150154`) en el #198: la bandeja y el detalle traen `evento_origen_id` | Sin ella la pestaña cae a la v4 y la llamada queda pendiente |
| 3 | **Fuga del latido** → la macro manda el latido solo cada 6 h (`macrodroid.md` §3c) **y** el servidor deja de mostrar horas exactas (undécima, `20261006150254`) | La hora del latido era casi la de la última llamada, personales incluidas (como la N1) |
| 4 | **C1 trabaja con una cuenta de analista o supervisor** | La v5 solo une si el celular es del analista que registra (`enlace_exacto.sql:35-36`) [V] |

## F4-c · Mapa de reuso

| Qué hace falta | Qué existe ya | ¿Se reutiliza? |
| --- | --- | --- |
| Asignar | `crm.asignar_celular(text,uuid)` (`nucleo.sql:510-542, 807-819`) [V] | **Sí, tal cual.** Es solo de gerencia. Etiqueta `^C[1-9][0-9]{0,2}$`. La credencial se devuelve una vez; en la base queda solo el sha256 |
| Rotar | `crm.rotar_credencial_celular(text)` (`:576-609, 835-847`) [V] | **Sí, tal cual.** Analista de baja → 22023 «ciérralo y asígnalo a otro» |
| Cerrar | `crm.cerrar_asignacion_celular(uuid,text)` (`:544-574, 821-833`) [V] | **Sí, tal cual.** La pantalla no ofrece el motivo `rotacion` (lo usa la rotación) |
| Salud | `crm.celulares_salud_fn()`; núcleo vigente: **la undécima** | **Sí.** Muestra estado, horas enteras, reloj desfasado, versión y cola |
| Historial | `crm.celulares_asignaciones_fn()` (`nucleo.sql:701-717`) [V] | **Sí, tal cual**, sin el hash |
| Ruta, vista y permiso | `lib/router.ts` (`VISTAS_CONFIGURACION`), `lib/vistas.ts:91-94` [V] | **Adaptado.** `config-celulares` es solo de gerencia (directorio recibe 42501 en estas puertas) |
| Tarjeta y marco | `screens/config.tsx:39-47` (`SECCIONES`), `ConfiguracionShell` [V] | **Adaptado** / **sí, tal cual** |
| Cliente de datos | `data/llamadas-celular-api.ts` **no existe** (B3 de F4-b). Patrón: `data/crm-config-api.ts` [V] | **Parcial.** Los errores 22023 y 23505 muestran el texto del servidor, sin «la configuración cambió en otra sesión» |
| Selector de analista | `useCatalogoUsuariosAdministrables` (`data/crm-config-queries.ts:76`) [V] | **Sí, tal cual**: solo vendedor o supervisor con `activo_crm` |
| Clave con «Copiar» | Patrón de `components/app/calendario-google.tsx:106-179` [V] | **Parcial.** La clave no se puede volver a leer |
| Diálogos y vacíos | `Dialog`, `RadioGroup`, `Select`, `Tabs`, `Badge`, `PanelVacio`/`PanelCargando`/`PanelError` [V] | **Sí, tal cual** |
| Redactar la clave en los registros | `lib/observabilidad.ts:7` (`CLAVES_SENSIBLES`) [V] | **Adaptado:** falta `credencial` |
| Demo | `lib/demo-llamadas-celular.ts` (patrón) | **Adaptado** en un `demo-celulares.ts` |

**Archivos de F4-c**:
- A crear:
  - `screens/config-celulares.tsx`;
  - `lib/celulares.ts` (esquemas y reglas de salud para la pantalla);
  - `lib/demo-celulares.ts`;
  - `data/use-celulares.ts`;
  - las cinco puertas en `data/llamadas-celular-api.ts`;
  - `e2e/config-celulares.spec.ts`;
  - todos con sus pruebas.
- A modificar:
  - `router.ts`, `vistas.ts`, `config.tsx`, `App.tsx`, `observabilidad.ts`, `e2e/_helpers.ts`;
  - `database.types.ts`, **solo regenerado**.

## Decisiones de F4-c y F4-d (Jhosep, 06/10/2026)

| # | Decisión | Quedó en | Alternativa descartada |
| --- | --- | --- | --- |
| D1 | ¿En qué PR va F4-c? | **Resuelta el 07/10: PR nuevo desde `main`** (rama `crm/llamadas-f4c-celulares-20261006`), después de la fusión del #190 | Dentro del #190: ya estaba fusionado |
| D2 | Demo de «Celulares» | **Interactiva en memoria**, con una clave ficticia que diga «demo»: los botones funcionan y no se guarda nada | Solo lectura: el diálogo «se ve una vez» no se probaría hasta tener tipos |
| D3 | Sesión real antes de los tipos | **Ocultar la tarjeta**, como la pestaña de F4-b. No se preguntó: lo manda la norma de 4 capas | Llamar sin tipos |
| D4 | Cerrar el diálogo de la clave | **Pedir «Ya la copié al celular»**; Esc o un clic fuera no lo cierran | Cierre libre: riesgo de perderla (se recupera rotando) |
| D5 | `version_macro` en F4-d | **Pasar a `llamadas-v3`**: solo cambia el texto del latido en «Llamadas-Enviar cola», **sin macros nuevas** (siguen 4 de 5) | Seguir en v2: no se sabe qué celular ya une |
| D6 | Cómo se da de alta C1 | **Desde la tarjeta de F4-c**: la clave no pasa por una terminal ni por Claude | `alta-celular.sql`: la clave sale en claro en la terminal |
| D7 | Aviso en el celular ante un 401 | **Sí**: una notificación sin número dentro de «Enviar cola», sin sumar macros | No avisar: tras una rotación olvidada, los avisos se acumulan en silencio |
| D8 | Dónde vive la clave en la macro | **En una variable global** usada por las dos «Solicitud HTTP». Confirmar en el celular que MacroDroid la acepta en la cabecera; si no, se pega en las dos | Pegarla dos veces: pueden quedar distintas tras rotar |
| D9 | E2E de F4.4 | **Ruta real con dobles** (`montarBackendReal`) en Docker en esta PC, más el banco reducido y el gate. Decidido por Claude: lo manda el proyecto | Supabase local en Docker: hoy solo corre en la Mac de Miguel |

Pendiente de antes: el OK de Miguel a las decisiones 1–5 de `F4-PLAN-CORTO.md`. La 5 (tarjeta solo de gerencia)
habilita F4-c.

## Decisiones al programar F4-c (Claude, 07/10/2026; Jhosep informado)

| # | Decisión | Motivo |
| --- | --- | --- |
| P1 | La tarjeta **comparte el interruptor** `llamadasCelularHabilitadas` de `lib/config.ts` (`LLAMADAS_CELULAR_APROBADAS`, hoy `false`), el mismo de la pestaña de F4-b. Cerrado: la tarjeta no se ofrece en Configuración y por URL directa muestra «Todavía no está activa» sin llamar a ninguna puerta. En la demo siempre abierto | Hasta que Miguel aplique las doce, las puertas no existen en producción: la tarjeta fallaría |
| P2 | El cierre **no lleva campo de detalle** para «Otro» (el prototipo lo tenía) | `crm.cerrar_asignacion_celular(uuid, text)` solo recibe el motivo; no se inventa un campo que la base no guarda |
| P3 | «Analista de baja» se decide con el catálogo de usuarios (`activo_crm` y rol vendedor/supervisor). Sin catálogo, Rotar sigue habilitado y el servidor niega con su texto (22023) | La salud no dice si la persona sigue activa; el catálogo ya existe y el servidor es la verdad |
| P4 | La clave vive solo en el estado del diálogo y se suelta al cerrarlo; no pasa por toast, URL, almacenamiento, caché ni registros (`credencial` quedó en `CLAVES_SENSIBLES`). Las acciones no usan `useMutation`, para que la respuesta no quede en la caché | Requisito del plan: «la clave no queda en el DOM, el almacenamiento ni la caché» |
| P5 | Los textos de 22023 y 23505 se muestran tal cual (son mensajes de negocio del servidor); 42501 se dice como «No tienes permiso» | Decidido en el mapa de reuso: sin «la configuración cambió en otra sesión» |
| P6 | La ventana de la clave sabe de dónde viene. **Alta:** vaciar `cola_llamadas` y `errores_llamadas` (serían avisos de otra asignación). **Rotación:** conservarlas; la macro reenvía con la clave nueva (o «Enviar cola»). Regresión en unitarias y E2E | Revisión de Miguel en el #215 (07/10, P2): el texto compartido mandaba borrar llamadas que aún no habían llegado |

**Producción, comprobada por Miguel el 07/10:** 0/12 aplicadas, sin la Edge `crm-llamadas-ingesta`, y modo SLA
**activo** (no `legado`, que es lo que tenía su banco): el ensayo previo a aplicar tiene que repetirse con esa
configuración.

Verificado el 07/10: `lib/celulares.test.ts` + `data/celulares-api-msw.test.ts` 24/24, `screens/config-celulares.test.tsx`
9/9, E2E en Docker `e2e/config-celulares.spec.ts` + `config-demo.spec.ts` 4/4 (la primera corrida dio 2 «flaky» por el
arranque frío de Vite en el contenedor; la segunda, limpia), y prueba manual en el navegador (demo de gerencia).

## F4-d · Flujos de operación (repasados con Jhosep el 06/10)

- **Celular nuevo:** (1) preparar el celular: app del CRM con la cuenta del analista, «Abrir vínculos admitidos» para
  `crm.miavance.com`, hora automática, MacroDroid con las 4 macros de `macrodroid.md` §3c; (2) gerencia asigna desde la
  tarjeta, copia la clave y la pega en `clave_celular`; revisa `url_llamadas`, vacía las colas, `ultimo_latido = 0`;
  «Ya la copié al celular»; (3) en ≤ 5 min la fila pasa a «Al día» con `llamadas-v3` y cola 0; (4) una llamada de prueba
  abre la encuesta con la llamada unida.
- **Se pierde el celular:** cerrar con motivo «Extravío»: la clave muere al instante (la Edge responde 401). Lo guardado
  se conserva; lo que tenía en cola se pierde con el celular (en un celular sano la cola es casi siempre 0: envía
  segundos después de colgar; lo que el analista contestó en la encuesta ya está en el CRM). Con el celular nuevo:
  asignar con la misma etiqueta y el mismo analista. El número telefónico no importa: el CRM reconoce al celular por su
  clave.
- **El analista deja el CRM:** primero su baja en «Usuarios y jerarquía»; la fila pasa a «Analista de baja» (sin Rotar);
  cerrar con «Baja del analista»; asignar el celular físico al nuevo con la misma etiqueta. **Antes, cola en 0:** una
  cola vieja enviada con la clave nueva se atribuiría al nuevo analista (la tarjeta lo avisa en ámbar al cerrar).
- **Cómo llega la clave al celular (decisión de Jhosep, 07/10):** por WhatsApp o el canal que sea; equipo aislado,
  riesgo aceptado. Si se filtra, se rota desde la tarjeta y la vieja muere al instante.
- `llamadas-v3` no es una macro nueva: es el texto de versión que ya manda la macro final de C1 (P1 del 06/10).

## F4-d · Runbook de activación (instalar no es activar: esto es activar)

Cada aviso va con `QUÉ HICE · RESULTADO · TURNO PARA`. **La clave nunca va al repo, a un chat ni a Claude.**

| # | Quién | Paso | Qué se verifica |
| --- | --- | --- | --- |
| 0.1 | Miguel | El #190 aplicado | V1–V5 de `PUBLICAR-F2-F3.md`; Edge desplegada; los `curl` dan `{"error":"No autorizado"}` |
| 0.2 | Miguel | El #198 aplicado (F4-b, F4-c, décima y undécima) | Registradores con veredicto `t`; gate con `CRM_RLS_EXIGE_LLAMADAS=1` y `CRM_RLS_EXIGE_LLAMADAS_F4B=1`; advisors |
| 0.3 | Persona (`/release-crm`) | Release con F4-b y F4-c | La tarjeta y la pestaña están en el bundle publicado |
| 0.4 | Claude | `npm run check` y E2E en Docker | PASS, FAIL o NOT RUN con cifras |
| 0.5 | Jhosep | Preparar C1 | Cuenta de analista; dos leads «PRUEBA C1» con teléfonos del equipo (con su consentimiento) |
| 1.1 | Jhosep (C1) | Vaciar `cola_llamadas` y `errores_llamadas`; hora automática | Captura sin números |
| 1.2 | Gerencia | Configuración › Celulares › Asignar C1 → Copiar → pegar en MacroDroid → «Ya la copié» | La tarjeta muestra C1 «nunca habló». Se reporta solo la etiqueta y la hora |
| 1.3 | Jhosep (C1) | Macro: URL de la Edge y clave; `llamadas-v3`; «Abrir sitio web» con `…/llamada/{call_number}/{lv=id_llamada}`; latido solo cada 6 h; `ultimo_latido = 0` | Captura de las acciones, sin la clave |
| 1.4 | Gerencia | L1 | En ≤ 5 min la tarjeta dice «al día», `llamadas-v3` y cola 0 |
| 2 | Jhosep llama | Casos P1–P15 (abajo) | Cada caso PASS, FAIL o NOT RUN, sin números ni nombres |
| 3 | Miguel (SQL sin números) | Recibidas y guardadas; ningún resultado unido dos veces; sello v4 intacto | Cifras y veredicto (F4.4.3) |
| 4 | Claude | Casillas F4.3.2 y F4.4 con evidencia; bitácora y tablero | Commit y un push |

**Cómo volver atrás en C1** (en la base no hay reversa: se apaga):
1. **Falla el enlace.** La URL vuelve a `…/llamada/{call_number}`, sin id: la encuesta usa la v4 y las llamadas se unen a mano.
2. **Falla la captura.**
   - Cerrar C1 en la tarjeta, con motivo `otro`: la clave muere y la Edge da 401.
   - En la macro, la URL vuelve al receptor de pruebas y se vacían las colas.
   - Lo pendiente se descarta con `numero_de_prueba` o caduca a los 30 días.
3. **Último recurso.** Borrar la Edge (solo C1 está activo). La app vuelve a la release anterior.

## Pruebas

- **Unitarias de F4-c:**
  - estados de salud (al día, sin latido, nunca, reloj desfasado, macro vieja, analista de baja);
  - regex de la etiqueta;
  - esquemas: la credencial en hex de 64, la lista sin hash, la salud sin horas exactas;
  - API con MSW (argumentos y textos de 42501, 22023 y 23505);
  - pantalla: Copiar, Esc no cierra, **la clave no queda en el DOM, en el almacenamiento ni en la caché** al cerrar,
    doble clic = una llamada, un 23505 ofrece «Rotar»;
  - `credencial` redactada en los registros.
- **E2E en Docker:**
  - F4-c en la demo (con Supabase bloqueado; directorio no ve la tarjeta);
  - F4-c real con dobles, cuando haya tipos;
  - F4.4 en `llamadas-celular-circuito.spec.ts`: el aviso después o antes, dos llamadas en 10 min, dos pestañas,
    enlace fallido, respuesta perdida (repetido), Deshacer → corregido, lead reasignado, número sin lead, otra
    cuenta, URL vieja sin id.
- **En C1:**

  | Caso | Esperado |
  | --- | --- |
  | P1–P3 | Guardar enseguida, esperar y sin datos: «quedará unido» / «quedó unido» / se cumple en ≤ 5 min |
  | P4–P5 | Dos llamadas en 10 min; una con la encuesta abierta: cada fila con su llamada; no se pisan |
  | P6–P7 | Cerrar la encuesta sin guardar y registrar desde la pestaña (celular y PC): **se une con vía `pestana`** (décima) |
  | P8–P9 | URL con `C9-…`: «es de otro celular». Deshacer y corregir: un solo enlace |
  | P10–P11 | Lead reasignado; rotar (la vieja da 401, la nueva vacía la cola) |
  | P12–P15 | Entrante (nada); número sin lead; L2–L4; pruebas 1 y 6 de F3.3, A3 y A6 |

  Cierre: recibidas = registro del teléfono; 0 duplicadas; «encuesta abierta al colgar: N de N».

## Riesgos y límites

- **La clave en el navegador:** no puede pasar por toast, URL, almacenamiento ni registros. Queda visible en la pestaña
  Red de DevTools del gerente (aceptado).
- **Rotar sin actualizar la macro:** los avisos esperan en la cola. Pasados 30 días el id vence → 400 → `errores_llamadas`.
- **Reutilizar una etiqueta («reemplazo»):** una cola vieja enviada con la clave nueva se atribuye al analista nuevo.
  Antes de reemplazar, la cola tiene que estar en 0.
- **La salud es lo que declara el celular:** el latido prueba que el celular habla, no que capture llamadas.
- **Pruebas en producción:** dejan gestiones reales en las cifras del analista de C1.
- **E2E en Windows:** `scripts/e2e-docker.sh` no corre en Git Bash (lección del 30/09). Se lanza a mano con el contenedor.

## En llano

La tarjeta «Celulares» deja a gerencia dar de alta un celular, cambiarle la clave, darlo de baja y ver si está vivo,
sin tocar la base: las puertas ya existen. Se programa cuando Miguel termine la base. Activar C1 es una lista de pasos
con quién hace cada uno y cómo se apaga si algo falla. De este análisis salieron dos arreglos que ya están en el #198:
registrar desde la pestaña ahora une la llamada, y la salud del celular ya no delata la hora de la última llamada.
