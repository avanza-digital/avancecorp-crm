---
tags: [crm, leads, conversion, contratos, incidente, front, accesibilidad]
fecha: 2026-10-01
estado: CERRADO 01/10 — publicado 12:53 Lima (build-20261001T174928972Z, `e304cc44`) y en `main` de GitHub por la PR #159 (`12861fd9`, 13:10 Lima)
---

# Convertir a cliente: el wizard se cerraba al volver a la ventana (2026-10-01)

> **`e304cc44` fue el vivo del CRM el 01/10 de 12:53 a 13:52 Lima** (rama
> `rescue/wizard-conversion-foco-20261001` = vivo anterior `c6e65d9e` + este arreglo). Release
> `crm-20261001T174929Z-e304cc443ed2`, build `build-20261001T174928972Z`, SHA-256
> `ef552e72197a41be2da0a7c98cf514eeee1b7e26c89feb677180a20d8c8aacce`.
> **Desde las 13:52 el vivo es `54690b06`** (release del potencial del lead, otra sesión, construido
> ENCIMA de `e304cc44`): comprobado que el arreglo sigue servido en producción, byte a byte.

## Qué pasaba

En la ficha del lead (`#/cartera/lead/<id>`): «Convertir a cliente» → «Registrar la inversión del
lead» → «Continuar a Nueva inversión» → wizard «Crear contrato», paso 2. Si el analista cambiaba a
otra aplicación (Bloc de notas, WhatsApp) y volvía al navegador, el wizard desaparecía y reaparecía
el modal de identidad. Se perdía lo escrito.

## Por qué (causa única, reproducida)

No era la sesión ni el refresco del token. Era una consulta que decidía qué diálogo se pinta:

1. «Continuar a Nueva inversión» llama a `crm.preparar_persona_lead_inversion_fn`, que **escribe en
   el lead** (`inversionista_id`, nombre). El servidor le cambia `actualizado_en`; la pantalla no se
   entera.
2. Al volver a la ventana, la cartera se resincroniza (`store.tsx`, eventos de foco) y el lead llega
   con la fecha nueva.
3. `useDocumentoLead` lleva `lead.actualizado_en` en su clave y no guarda caché (`gcTime: 0`): clave
   nueva = «cargando». `InversionDesdeLead` pintaba entonces el diálogo de carga y **desmontaba** el
   formulario con el wizard dentro. Al terminar, el formulario nacía de cero: modal de identidad.
4. Segundo camino con el mismo final: la relectura por foco devolvía el documento ya vinculado y
   cambiaba la `key` del formulario.

Regresión del cambio de documentos tipados (DNI · CE · pasaporte, PR #151; ver
[[Leads - DNI CE y pasaporte sin recortes (2026-09-30)]]): fue ahí donde el formulario quedó colgado
de esa consulta. Sale en cada conversión en cuanto se vuelve a la ventana, no es intermitente.

**Lo que se descartó leyendo el código** (no hubo que tocarlo): la sesión ignora el aviso de Auth
cuando el usuario es el mismo (`auth-maquina.ts`, «mismo usuario: eco del listener — se ignora»), la
revalidación por foco es silenciosa y `yo` conserva su referencia. Una hora con la pestaña oculta no
remonta la aplicación (comprobado en navegador: token vencido → renovación real → el wizard sigue).
El store tampoco suelta la ficha abierta al resincronizar: la relee por id antes de actualizar.

## El arreglo (solo pantalla; sin SQL, sin permisos, sin puertas nuevas)

- **`inversion-desde-lead.tsx`** — el documento solo *precarga* la identidad y se **fija**: con la
  primera respuesta del servidor posterior a abrir, o antes si ya hay persona. Desde ahí la consulta
  queda apagada y ninguna relectura ni cambio de clave desmonta nada. Mientras llega esa respuesta
  el formulario abre con la copia que la ficha ya tenía (sin espera ni parpadeo) y el botón
  «Continuar» está apagado: la identidad no se envía con un documento sin confirmar.
- **Marca «conversión abierta»** en la pestaña (`sessionStorage`,
  `crm:f5:conversion-abierta:<actor>:<lead>`; solo guarda de quién es, la persona). Se guarda al
  preparar la identidad. Se borra al cerrar el diálogo (también si se cierra mientras carga), al
  confirmar la inversión, al perder el acceso y al salir de la sesión.
- **`lead-drawer.tsx`** — tras recargar la página (F5), la ficha vuelve por la URL y, si hay marca,
  **reabre el wizard sola**: con el mismo permiso que el botón, solo cuando ya conoce las condiciones
  de tasa (el contrato las toma al montarse) y solo si la persona todavía no tocó nada (al primer
  clic o tecla deja de abrirse sola; «Convertir a cliente» la retoma igual). El wizard entra directo,
  sin pedir otra vez la identidad; el servidor vuelve a comprobar persona ↔ lead y ámbito
  (`crm.contexto_conversion_inversion_fn`).
- Lo que ya existía hace el resto: `InversionNueva` guardaba en la pestaña la solicitud (con su clave
  y su token de idempotencia) y los borradores del paso 1 y del paso 2. Por eso el contrato no se
  duplica: la retoma **no vuelve a llamar** ni a preparar la identidad ni a preparar la solicitud.

## Decisiones tomadas (y por qué)

- **No se apagó la relectura por foco del wizard** (`conversionQ`, cada 15 s y al volver): es el
  control que cierra el wizard si al analista le quitan el lead. No desmontaba nada.
- **La marca no se borra al desmontar**, solo en cierres explícitos: recargar no avisa a nadie, y así
  cualquier remontaje imprevisto también retoma el wizard. Efecto: si el analista se va con «atrás»
  del navegador dejando el wizard abierto y vuelve a ese lead en la misma pestaña, se reabre.
- **«Cancelar solicitud» no borra la marca**: el wizard sigue abierto mostrando «Solicitud
  cancelada»; recargar ahí muestra eso mismo. Tras «Iniciar otra inversión», recargar vuelve a la
  elección de empresa. La marca no guarda la solicitud (se quedaría vieja): la trae el intento.
- **Los datos sensibles del paso 2 siguen sin guardarse en la pestaña** (cuenta bancaria nueva,
  co-titulares; decisión anterior). Al volver a la ventana ya no se pierden —nada se desmonta—, pero
  tras **recargar** hay que reescribirlos.

## Límites conocidos

- Si la persona ya tenía acceso al portal (no pasa por «Paso 1 de 3»), el paso de condiciones no
  tiene borrador hasta que existe la solicitud: tras F5 el wizard se reabre, pero en la elección de
  empresa y sin los campos. Volver a la ventana sí conserva todo.
- **Accesibilidad, pendiente aparte:** al cerrar el wizard el foco cae en `body` (ya pasaba en
  producción: el wizard releva al diálogo de identidad y nace sin origen de foco). Se probó un
  respaldo en `ui/dialog.tsx` (enfocar la capa abierta de debajo): pasaba en jsdom pero en Chromium
  real el foco siguió en `body` al cerrar el wizard reabierto tras F5. Se retiró para no tocar todos
  los modales en un arreglo urgente; `dialog.tsx` queda idéntico a producción.

## Revisiones

- **Codex r1** (LEVEL 2): pidió cambios. Aceptado: cerrar mientras carga no borraba la marca (P2),
  permiso de contratar antes de reabrir, frontera explícita por cuenta y lead, y la marca sin
  `solicitud_id`.
- **revisor-a11y**: pidió cambios. Aceptado: cancelar la identidad devuelve el foco al botón (el
  formulario vuelve a ser el primer diálogo), el diálogo de carga avisa a lector de pantalla, la
  reapertura sola ya no pilla a la persona escribiendo, y una comprobación vacía del e2e (nombre
  accesible equivocado). NO resuelto: el foco al cerrar el wizard (ver «Límites conocidos»).
- **Codex r2** (segunda y última): pidió cambios. Aceptado: una respuesta tardía del documento podía
  descartar una identidad en curso → el envío queda apagado hasta fijar el documento. Su segunda
  observación (el respaldo de foco) quedó sin objeto al retirarlo.

## Verificación

- Reproducción: `inversion-desde-lead-foco.test.tsx` con el lector REAL del documento; 2 pruebas
  fallaban contra el vivo `c6e65d9e` mostrando «Registrar la inversión del lead».
- 15 mutantes de las defensas nuevas, los 15 cazados y el original restaurado byte a byte (13 siguen
  aplicando; los 2 del respaldo de foco se fueron con él).
- E2E en Chromium real (Docker, contenedor y volumen propios), caso nuevo en
  `acceso-avance-ux.spec.ts`: paso 2 con datos → volver a la ventana (la cartera trae el lead
  actualizado) → sigue igual; token vencido → renovación real → sigue igual; F5 → el wizard se reabre
  en el paso 2 con capital, número y cuenta; una sola identidad y una sola solicitud; cerrado a mano,
  otra recarga ya no lo reabre. Sin el arreglo, ese caso falla justo al volver a la ventana.
- `npm run check` sobre el código final: PASS (330 archivos, 5.184 pruebas, build y bundle).
- E2E Docker del flujo (conversión, ficha, cartera, clientes, postventa) sobre el código final: 40
  pasan, 13 omitidas, 0 fallan. Suite completa (325) con el mismo código de aplicación: solo fallan
  `gerencia-operativa.spec.ts:108` y `gestion-diaria-vuelta.spec.ts:11`, que fallan igual sobre la
  base sin este cambio (acreditado con una corrida aparte).
- Gate de realidad: NOT RUN (pide la llave de servicio de producción).

## Publicación (01/10/2026, 12:53 Lima)

Urgente: los analistas no podían terminar contratos. Miguel copió el archivo de entorno a la copia
aislada y lanzó la subida con `!` (token del llavero, entrada `hostinger-api`). Antes: `release:crm`,
`release:crm:verify` y preflight OK (`live=build-20261001T002155841Z/c6e65d9e8b4a
candidate=e304cc443ed2`). Hostinger respondió `upload success` / `deploy Request accepted`.

Comprobado en vivo: `version.json` = `build-20261001T174928972Z`; portada 200 con
`assets/index-BserWyDZ.js` y `index-vJJCtQmx.css`; de los 130 archivos del paquete, 117 de código y
configuración idénticos byte a byte, `.htaccess` 403, y las 12 imágenes PNG responden 200 (la CDN de
Hostinger las optimiza, por eso sus bytes difieren, como en releases anteriores); el arreglo está en
el JS servido; el ZIP da 404 en el CRM y en el portal; el portal sigue 200; el login carga sin
errores ni avisos de consola. No se probó una conversión real autenticada en producción.

## Para retomar

- **Sesión cerrada y limpia (01/10).** La copia aislada `wt-wizard-foco`, su volumen Docker y la rama
  de la PR (local y en GitHub) se borraron. Lo que QUEDA a propósito: la rama
  `rescue/wizard-conversion-foco-20261001` (local y en GitHub), commit **`e304cc44`** = el VIVO, sobre
  el vivo anterior `c6e65d9e`; y su ZIP + manifiesto en `CRM-Avance-Corp/releases/` del taller
  (historial de releases). La rama ya es solo un respaldo —el vivo `54690b06` contiene su commit— y se
  puede borrar en la próxima limpieza de ramas.
- **Receta que funcionó para publicar desde una copia aislada:** (1) Miguel copia con `!` el archivo
  de entorno de `app/` del taller a `app/` de la copia (el hook no deja a Claude tocarlo);
  (2) `npm run release:crm` y `release:crm:verify` desde `CRM-Avance-Corp/` de la copia; (3) copiar
  ZIP + manifiesto a `CRM-Avance-Corp/releases/` del TALLER (`cp -pn`) y pasar ahí el preflight (en el
  taller viven `_DEV_NO_SUBIR/` y los manifiestos de lo vivo); (4) la línea de deploy con el token la
  lanza Miguel con `!`.
- **Integración a `main`: PR #159** (`crm/wizard-conversion-foco-pr`, commit `5ec0c236` = cherry-pick
  limpio de `e304cc44` sobre `avancecorp/main` `8eeaf805`, que ya trae #155 y el potencial del lead
  #158). Sobre esa rama: `npm run check` PASS (340 archivos, 5.339 pruebas) y e2e de conversión 14/14.
  **Fusionada por Miguel el 01/10 13:10 Lima: `avancecorp/main` = `12861fd9`**; comprobado que los
  archivos están en `main` y que el código coincide con el publicado. La rama de rescate con el commit
  vivo también está en GitHub. El `main` LOCAL del taller todavía no trae `12861fd9` (tiene trabajo sin
  commit de otras sesiones): entra en la próxima integración.
- **Para el próximo release:** `main` contiene estos cambios por contenido pero NO por historia (los
  squash no conservan `e304cc44`). El preflight pedirá una rama que nazca de `e304cc44` con lo nuevo
  de `main` asentado encima (lo que aún no está en producción: potencial del lead, fases 2 y 3A).
- La copia del archivo de entorno que Miguel puso en la copia aislada se fue con ella.
- Ojo, iCloud: en la copia aislada apareció un duplicado `inversion-solicitud 2.ts` (el Escritorio se
  sincroniza). Salió DESPUÉS de construir el paquete (árbol limpio en el manifiesto), pero un archivo
  « 2» suelto ensucia el árbol y haría negarse al release: mirar `git status` justo antes de construir.
- Archivos: `app/src/components/app/inversion-desde-lead.tsx`, `lead-drawer.tsx`,
  `app/src/data/documento-lead.ts`, `app/src/lib/inversion-solicitud.ts` y sus pruebas
  (`inversion-desde-lead-foco.test.tsx`, `lead-drawer-retomar-conversion.test.tsx`,
  `lead-drawer-convertir.test.tsx`, `inversion-solicitud.test.ts`, `e2e/acceso-avance-ux.spec.ts`).
- Encargos y respuestas de Codex (r1 y r2) y la resolución de las tres revisiones: versionados en
  `CRM-Avance-Corp/docs/encargos/2026-10-01-wizard-conversion-foco-*` (mismo commit).

Relacionadas: [[Conversion de lead con Nueva inversion - preparado 2026-09-19]] ·
[[RETOMAR-61 - Contrato duplicado e idempotencia del alta (2026-09-05)]] ·
[[Leads - DNI CE y pasaporte sin recortes (2026-09-30)]]
