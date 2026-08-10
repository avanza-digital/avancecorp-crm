---
tags: [crm, observabilidad, sentry, seguridad, leccion]
actualizado: 2026-08-10
estado: implementado (commit dd6b610) · pendiente de deploy y de verificación en vivo
---

# La telemetría tiene DOS extremos: el gate de entrada y la CSP de salida

Relacionado con [[Plan de escalabilidad del CRM a data gigante]] (F4),
[[Deploy a Hostinger]] y [[Deuda técnica CRM 2026-07-10]].

## El hecho que lo destapó

El 2026-08-10 Miguel autenticó por fin el MCP de Sentry, el último bloqueo formal
de F4. Lo esperado era confirmar «llegan eventos, arranca F4». Lo que apareció:

> **742 eventos de error en 24 h**, repartidos en 11 issues, todos con formato
> propio del CRM (`crm.contratos.listado_fallido`, `crm.clientes.listado_fallido`,
> `crm.reparto.resumen_fallido`…), el último hacía 11 minutos.

Parecía una caída de producción. **No lo era, y la verdad era peor.**

## Las dos mitades del defecto (se anulaban entre sí)

Un diagnóstico de 5 lentes + 3 refutadores independientes (0 refutaciones)
encontró **dos defectos opuestos** que juntos daban la ilusión de telemetría:

### 1. La SALIDA estaba amordazada (lo grave)

`app/public/.htaccess` sirve una CSP con `default-src 'none'` y un `connect-src`
que enumeraba solo Supabase. **El host de ingesta de Sentry nunca estuvo ahí**
(`git log -S ingest -- app/public/.htaccess` → sin resultados). El navegador
bloqueaba cada envelope.

> **Producción no había emitido NI UN evento desde que el DSN entró a prod el
> 2026-08-09.** Los «0 errores de producción» no probaban salud: probaban
> silencio forzado. Y la CSP tampoco llevaba `report-uri`, así que ni las
> violaciones dejaban rastro — la mordaza era silenciosa hasta para el navegador.

### 2. La ENTRADA estaba abierta de par en par

`instalarSentry()` solo comprobaba que el DSN existiera, sin mirar el entorno.
Como `app/.env` es la única fuente de variables y **Vite la carga en TODOS los
modos**, cada `npm run dev` —y cada corrida de Playwright, que levanta ese mismo
servidor de dev— reportaba al proyecto de PRODUCCIÓN.

Los 742 eventos eran, uno a uno, ruido de laboratorio: mocks de los E2E
(`PGRST000` es un literal fabricado en `_helpers.ts`) y fetches cancelados.

**Prueba temporal que lo cerró:** el primer `crm.reparto.resumen_fallido` es de
las 21:32:55Z; el commit que creó esa ruta de código (`a0b395e`) es de las
22:23:52Z y se desplegó ~22:34Z. El evento precede al código en ~51 minutos. Y el
release vivo a esa hora no contiene el string en ningún asset.

### 3. De regalo: cancelaciones disfrazadas de caídas

`postgrest-js` deja `code: ''` cuando el fetch se aborta, y el fallback del CRM
(`error.code || 'POSTGREST_ERROR'`) lo convertía en un fallo indistinguible de una
caída real. Como **TanStack cancela de oficio** al desmontarse la última pantalla
observadora, *cambiar de pantalla* generaba «listado_fallido». 16 lecturas lo
hacían; las RPC de métricas ya tenían la guarda `lanzarAbortSiCorresponde`.

## La lección

> **Un DSN activo tiene DOS extremos. El gate de entorno en la ENTRADA y el
> `connect-src` de la CSP en la SALIDA. Comprobar uno solo da la ilusión de
> telemetría** — y las dos formas de fallar son opuestas: por la entrada se
> llena de ruido, por la salida enmudece. Aquí pasaron las dos a la vez, y el
> ruido de la entrada hacía creer que la salida funcionaba.

Corolarios que valen para cualquier canal de observabilidad:

1. **«0 eventos» nunca es una respuesta; es una pregunta.** Hasta que un error
   deliberado viaje de punta a punta y aparezca en el panel, no hay telemetría:
   hay una hipótesis. La verificación end-to-end es parte del trabajo, no un
   extra.
2. **`Users Impacted: 0` no significa que nadie sufriera nada.** Aquí era
   estructural por partida doble: `beforeSend` borra `evento.user` y además no
   hay ni un `Sentry.setUser` en todo `src/`. Un dato que SIEMPRE vale 0 no es
   evidencia de nada.
3. **Una etiqueta que colapsa causas distintas mata la alarma.**
   `POSTGREST_ERROR` mezcla cancelación, red caída y CORS: ningún umbral de F4
   puede construirse sobre ella. Queda anotado como deuda.
4. **El release se compila en LA MÁQUINA de Miguel**
   (`crear-artefacto-release.mjs` corre `npm --prefix app run build` local), así
   que lo que llega a producción es «lo que tenga el `.env` local al momento del
   build». La fuga es bidireccional: por eso el gate va en el CÓDIGO
   (`if (!import.meta.env.PROD) return`) y no en el `.env`, que se repone sin
   querer.

## El tercer defecto: abrir la CSP ACTIVABA una fuga de PII

Lo encontró la **revisión independiente de Codex** (`gpt-5.6-sol`) sobre `dd6b610`,
y es el hallazgo más caro del ciclo porque **ninguno de los cinco diagnósticos ni
de los tres refutadores lo vio**: todos miraban si la telemetría *funcionaba*,
nadie si *lo que iba a empezar a viajar* era seguro.

Sentry trae activas por defecto las migas (`breadcrumbs`) de UI, y su serializador
copia **literalmente** el árbol DOM del elemento pulsado, con su `aria-label`. El
CRM pone nombres de clientes justo ahí:

- `contacto.tsx` → `aria-label="Llamar a ${lead.nombre_completo}"`
- `repartir.tsx` → `aria-label="Repartir a ${lead.nombre_completo}"`

Nuestro `limpiarTexto` **no conoce nombres propios**: solo Bearer, JWT, correos y
números personales. Y `sendDefaultPii: false` NO desactiva esa integración.

> **Mientras la CSP bloqueaba la salida, el defecto era inofensivo. Abrirla lo
> convertía en una fuga efectiva.** Es decir: el «arreglo» de la mordaza habría
> estrenado, el mismo día, un canal de PII hacia un tercero.

Arreglado: las migas `ui.*` se descartan **enteras** (la miga de reproducción no
vale una fuga), y a las de red se les quita la **query** —donde viaja el texto que
el usuario escribe en el buscador, `nombre_completo=ilike.%…%`— conservando la
ruta, que dice QUÉ se llamó sin decir CON QUÉ datos.

### La lección de segundo orden

> **Al abrir un canal que estaba cerrado, hay que auditar lo que va a salir por
> él, no solo comprobar que ya sale.** Un defecto latente tras una barrera no es
> un defecto menor: es un defecto con fecha de activación, y la fecha la pone
> quien retira la barrera.

De paso, Codex encontró que el barrido de abortos estaba **incompleto** (5 lecturas
más: `esClienteDeMiCartera` y las 4 métricas de gerencia — eran 21, no 16) y que el
gate miraba `PROD`, que Vite deriva de `NODE_ENV`, así que `vite build --mode
staging` habría reportado a producción; ahora compara `MODE` contra `'production'`.

Y una lección sobre los propios tests: los míos **solo cubrían la rama negativa**,
así que un `return` incondicional al principio de `instalarSentry()` los dejaba
todos en verde y nos habría devuelto al silencio sin avisar. Hermana de la lección
del 2026-08-09: **una prueba de mutación hay que hacerla en las DOS direcciones —
quitar el arreglo Y anular la función entera.**

## Lo que se hizo (commits `dd6b610` y `0fe89cd`)

| Extremo | Arreglo |
|---|---|
| Salida | `connect-src` incluye `https://o4511877814026240.ingest.us.sentry.io` (host exacto, sin comodín) |
| Entrada | `if (import.meta.env.MODE !== 'production') return` en `instalarSentry()` — **silencio total fuera de producción, decisión de Miguel**. Con `PROD` no bastaba: Vite lo deriva de `NODE_ENV` y un build `--mode staging` habría reportado al DSN de producción |
| Privacidad | Migas `ui.*` descartadas y query de las URLs redactada — sin esto, abrir la CSP estrenaba una fuga de nombres de clientes |
| Instrumentación | `lanzarAbortSiCorresponde(signal)` en las **21** lecturas que no la tenían (16 + 5 que encontró Codex); desaparecen los TRES patrones que convivían para lo mismo |
| Honestidad de UI | `mi-cartera` gana su aviso de degradación: era la única pantalla donde un refetch fallido dejaba al asesor viendo datos rancios como si fueran frescos |

Gate: `npm run check` **1469/1469** (+9) · e2e **81** · **prueba de mutación**: 3
tests de mi-cartera y 2 del gate se ponen rojos al revertir el arreglo.

**Orden de despliegue (importa):** las guardas de aborto van ANTES o CON la
apertura de la CSP, nunca después. Si se abre la CSP primero, producción empieza
a reportar cancelaciones como caídas y la primera telemetría real nace mintiendo.

## Pendiente

- [ ] Desplegar y **verificar en vivo**: forzar un error desde crm.miavance.com y
      confirmar que llega con `environment: production`. Hasta ese evento, F4
      sigue sin línea base.
- [ ] Purgar los 11 issues de `environment: development` acumulados y, si el plan
      lo permite, filtro de ingesta por entorno.
- [ ] Desglosar `POSTGREST_ERROR` en causas distinguibles y que `falloMetricas`
      adjunte el contexto `{ pg, rpc }` como ya hace `aErrorApi`.
