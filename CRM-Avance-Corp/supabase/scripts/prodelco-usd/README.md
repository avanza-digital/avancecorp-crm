# Prodelco admite inversiones en dólares

Estado: **✅ EN PRODUCCIÓN el 18/09/2026** (SQL ~12:35 Lima, front ~12:52 Lima).

Petición de Miguel (17/09/2026): que en la cooperativa **Prodelco** se puedan
registrar inversiones en **dólares**. **Qorilazo se queda solo en soles**
(confirmado por él en la misma conversación).

## El problema que había

La moneda de un cierre en cooperativa estaba decidida **a mano en cinco sitios**,
aunque el catálogo `crm.empresas.monedas` existía desde F1 justo para eso:

| Sitio | Qué decía |
|---|---|
| `crm.empresas.monedas` (Prodelco) | `{PEN}` |
| CHECK de `crm.cierres_externos.moneda` | `moneda = 'PEN'` |
| `crm.convertir_lead_externo` | `if p_moneda is distinct from 'PEN' then raise` |
| `crm.corregir_cierre_externo` | igual |
| `private.inversion_validar_datos` | `... is distinct from 'PEN' or not ('PEN'=any(monedas))` |
| `crm.confirmar_inversion_revisada_fn` | el check, **y el INSERT fijaba `'PEN'`** |

Ese último es el que más importaba: una inversión adicional F4 en dólares se
habría **guardado como soles**.

## Lo que hace la entrega

1. El CHECK de la columna pasa a `moneda = any (array['PEN','USD'])`. Sigue
   siendo un dominio estructural, como en contratos.
2. Los cuatro escritores dejan de decir «PEN» y preguntan al catálogo
   (`crm.empresas.monedas`), con `for share` y **guarda explícita del null**:
   sin fila, `= any(null)` da `NULL` y el `if` sería falso, o sea el candado se
   abriría solo.
3. `crm.confirmar_inversion_revisada_fn` inserta la moneda de la solicitud.
4. Una fila: `update crm.empresas set monedas = array['PEN','USD']
   where clave = 'prodelco'`.
5. Tres defensas que antes no hacían falta (ver abajo).

**Consecuencia de diseño:** a partir de ahora abrir o cerrar una moneda a una
cooperativa **es un UPDATE de una fila, no un despliegue**. Lo único que no se
mueve solo es el *selector* del formulario, que refleja el catálogo en
`app/src/lib/cierres-externos.ts` (`INFO_COOPERATIVA[...].monedas`).

## Las dos defensas nuevas

Salieron de la revisión independiente (Codex como reviewer, más el `auditor-rls`
del proyecto). **Ninguna quita conducta anterior: acotan lo que se acaba de
abrir.**

### 1. La moneda es inmutable entre revisiones de una solicitud F4

Quinto escritor, `crm.corregir_solicitud_inversion_fn`. **El problema real que
cierra:** un bundle anterior manda `moneda: 'PEN'` fijo. Alguien con una pestaña
sin recargar que corrigiera, por ejemplo, la referencia de una solicitud en
dólares la habría **reescrito como soles, con el mismo importe y sin avisar**.

La casa ya tenía la lista de campos inmutables entre revisiones (persona,
empresa, referencias del contrato, ruta del comprobante); la moneda entra ahí.
Si está mal, se cancela la solicitud y se prepara otra: la moneda es parte de lo
que el comprobante acredita, no un texto corregible.

🔴 **Nota de despliegue:** con el bundle anterior, corregir una solicitud F4 en
USD ahora **falla con 22023**. Es fail-closed y deseado, pero hay que
anunciarlo a quien opere.

### 2. `coalesce` sobre las monedas del catálogo en los dos escritores F4

Hoy `crm.empresas.monedas` es `NOT NULL` (F1), pero si algún día se relajara,
`= any(null)` daría `NULL`, el `if` sería falso y esos dos candados se abrirían
solos **mientras los de las cooperativas siguen cerrados**. Un array vacío no
admite nada, que es el lado correcto del que fallar.

## La decisión que se planteó y Miguel resolvió

**Gerencia SÍ puede cambiar la moneda de un cierre imputado a un mes ya
SELLADO** (Miguel, 18/09/2026).

Se le planteó el reparo con su consecuencia: cambiar la moneda mueve capital de
la columna de soles a la de dólares **en un mes cuya foto ya se tomó y se
reportó**. Con la alternativa de bloquearlo sobre la mesa, eligió permitirlo.

Lo que sí queda es el **rastro**: la corrección escribe una nota en la línea de
tiempo del lead con la moneda de antes y la de después, y el auditor guarda la
fila entera. Quien revise después puede ver qué se re-denominó y cuándo.

**PUSD-13 asevera que está PERMITIDO.** Si una sesión futura lo bloquea «por
prudencia» sin preguntar, el oráculo lo caza. Si algún día se quiere bloquear de
verdad, el patrón a seguir es el de `crm.confirmar_inversion_revisada_fn`, que
imputa a un mes posterior en vez de rechazar.

## Orden de candados, y por qué importa

La migración toma, **en este orden**:

1. candado de despliegue (`pg_advisory_xact_lock`), que serializa a los
   aplicadores que lo tomen;
2. **la FILA del catálogo** (`crm.empresas … for no key update`);
3. la tabla del catálogo (`share row exclusive`);
4. `crm.cierres_externos` en `access exclusive`.

Ese es el MISMO orden que siguen los escritores vivos. Al revés —tabla primero—
un cierre en vuelo que ya tuviera la fila quedaría esperando la tabla mientras la
migración espera la fila: **interbloqueo**. Y la tabla se bloquea **antes de
medir** la foto del preflight: si se midiera primero, un cierre confirmado en ese
hueco haría abortar el postflight por actividad legítima ajena.

## Lo que NO cambia, y por qué no hacía falta tocarlo

El dinero **ya viajaba con su moneda** por todo el camino de lectura: el núcleo
único `private.capital_episodios` toma `ce.moneda`, la cuota agrupa por
`(categoría, moneda)` y PEN/USD jamás se suman. Se midió en producción antes de
escribir nada: de las 38 funciones que leen `crm.cierres_externos`, las únicas
con la moneda escrita a mano eran las cuatro de arriba. Por eso un cierre en
dólares entra en su propia columna **sin tocar una sola calculadora**.

Tampoco cambian: tablas nuevas, políticas, permisos, dueños, `search_path`,
firmas ni la tabla `crm.inversiones` (que no guarda moneda: apunta a la fuente).

## Ensayo

Copia sintética local llevada a **paridad con producción**. `banco.mjs` fija
contenedor y base y no acepta destinos externos.

```bash
node supabase/scripts/prodelco-usd/ensayar.mjs
```

Dos detalles de paridad que cambian el resultado si se olvidan:

- `paridad-corregir-cierre-externo.sql` instala la definición **viva** de
  `crm.corregir_cierre_externo`: las plantillas del banco van un commit por
  detrás (les falta la guarda de `crm.gestion_neutral`). Sin esto el parche se
  habría derivado de una función que producción no tiene.
- Las **cuatro banderas** de F3/F4/F5 se encienden, como están en producción.
  En las plantillas locales estaban apagadas, y con `inversiones_escritura`
  apagada la ruta F4 —la que escribe la moneda— no se recorre: el ensayo habría
  medido otra cosa y dado verde.

Y una trampa de SQL que costó una vuelta: **`coalesce` va SIN calificar** dentro
de funciones con `search_path=''`. Es una construcción del lenguaje, no una
función del catálogo, y `pg_catalog.coalesce(...)` **no existe** (42883).
`date_trunc` sí se califica.

El ensayo escribe `verificacion.json`. Resultado del 18/09/2026:

| Paso | Resultado |
|---|---|
| Migración aplicada (su postflight manda) | PASS |
| Oráculo `test-prodelco-usd.sql`, 13 casos | PASS |
| Mutantes cazados | 6 de 6 |
| Segunda aplicación | negada por el preflight |
| Registrador | registra, idempotente, se niega con otro cuerpo |
| Reversa con dólares vivos o solicitudes F4 en USD | negada |
| Reversa limpia | devuelve los CINCO escritores byte a byte |
| Reinstalación + oráculo | PASS |

Casos decisivos:

- **PUSD-10** — la ruta F4 completa (preparar → confirmar) deja la fila en
  `prodelco / USD / 4321.00`. Con el mutante que devuelve el INSERT a `'PEN'`,
  el oráculo la caza con `ESPERADO USD · OBTENIDO PEN`.
- **PUSD-11** — corregir una solicitud en USD mandando PEN se rechaza y la
  solicitud sigue en USD; corregir otro campo conservando la moneda sí funciona.
- **PUSD-12** — si la cooperativa retira la moneda entre preparar y confirmar,
  la confirmación se niega y no deja nada escrito.
- **PUSD-13** — Gerencia sí cambia la moneda de un cierre imputado a un mes
  sellado, en los dos sentidos, y queda la nota con el antes y el después.

⚠️ **`test:rls` (el gate del proyecto): 4 casos USD ESCRITOS pero NOT RUN.** El
gate necesita el banco con las cuentas `*.crm@demo.avancecorp.pe` sembradas y el
banco local tiene 0. Van al próximo ciclo de banco, como el resto de pendientes
de esa suite. Los casos son: Prodelco/USD permitido y la fila en USD;
Qorilazo/USD denegado con `22023`; la corrección de gerencia en ambos sentidos;
y el lector global sigue recibiendo agregados sin filas existiendo un cierre USD.

## Front

| Archivo | Cambio |
|---|---|
| `lib/cierres-externos.ts` | `INFO_COOPERATIVA[...].monedas` + `monedaPorDefecto`, `pideMoneda`, `admiteMoneda` |
| `components/app/lead-drawer.tsx` | selector de moneda solo si la coop admite más de una; el rótulo del monto lleva el símbolo; al cambiar de coop la moneda se **recoloca** |
| `components/app/inversion-nueva.tsx` | lo mismo en la inversión adicional F4 |
| `data/crm-api.ts` | `ConvertirLeadExternoDatos.moneda` y `CorregirCierreExternoDatos.moneda` pasan de `'PEN'` a `Moneda` |
| `lib/store.tsx` | el cierre DEMO guarda la moneda elegida (antes fijaba PEN y el demo habría mentido) |

La moneda arranca **en soles** en las dos cooperativas: un cierre en dólares es
la excepción, y abrir el formulario ya puesto en dólares invita al error.

**No se puso un candado de moneda en el cliente a propósito.** El cliente ya
relaya el mensaje del servidor (22023) tal cual, y un candado en el front
volvería a atar «abrir una moneda» a un despliegue, que es justo lo que esta
entrega quita. El selector refleja; el servidor manda.

`CorregirCierreExternoDatos` hoy no lo llama ninguna pantalla, pero la primera
que se construyera sobre el tipo viejo habría convertido un cierre en dólares a
soles por el mismo importe. Lleva el aviso escrito en el propio tipo.

Verificación del front: typecheck PASS, oxlint sin avisos en los archivos
tocados, `vitest` **3680/3680**, `npm run build` PASS. Dos mutantes de front
cazados: quitar el recolocado de la moneda al cambiar de cooperativa, y volver a
mandar `'PEN'` fijo en el formulario F4.

## Publicación — HECHA el 18/09/2026

Registro **304**. Artefacto `crm-20260918T174456Z-57009ee15b7f` (commit `57009ee1`), preflight OK,
`version.json` → `build-20260918T174455375Z`, y el `index-CtfSb426.js` servido es **byte a byte** el
del dist. Verificado en producción sin escribir nada (bloque `DO` que termina en `raise`):
Prodelco/USD aceptado y guardado en USD, Qorilazo/USD rechazado, EUR rechazado, y el núcleo de
capital reporta los dólares como USD.

🔑 **La nota de que la MCP de Hostinger de la sesión no veía `crm.miavance.com` quedó
DESACTUALIZADA**: el 18/09 sí lo ve, en la cuenta correcta (`u318796122`), así que el deploy salió
por `hosting_deployStaticWebsite` sin necesitar el token de Miguel en el terminal. Eso además evita
tener que rotarlo.

**Orden, para la próxima: servidor primero, front después.** El front empieza a mandar un valor
nuevo (`p_moneda: 'USD'`) en la petición; con el servidor viejo ese cierre
moriría con el mensaje de «solo soles». Al revés no hay ventana: el servidor
nuevo acepta los soles que manda el front viejo.

1. Preflight y aplicación por la vía autorizada (Miguel con `!`,
   `db query --linked --file`), y **después** el registrador
   `supabase/scripts/registrar-20260917235656.sql`. El registrador se **genera**
   (`node supabase/scripts/prodelco-usd/generar-registrador.mjs`), nunca se
   edita a mano: si se edita la migración y no se regenera, registraría en
   `supabase_migrations` un cuerpo que no es el que se ejecutó.
2. Comprobar que el catálogo quedó abierto solo para Prodelco:
   `select clave, monedas from crm.empresas order by clave`.
3. Publicar el front del commit verificado (release + preflight del CRM).
4. Anotar el acta en `supabase/migrations/MIGRACIONES.md`.
5. Avisar a quien opere: con una pestaña sin recargar, corregir una solicitud F4
   en dólares falla con 22023 hasta que recargue.

## Reversa

**Casi nunca hace falta el guion.** Para cerrar la puerta basta con una fila:

```sql
update crm.empresas set monedas = array['PEN'] where clave = 'prodelco';
```

Deja de admitir dólares nuevos en el acto, sin desplegar nada y sin tocar los
cierres en USD que ya existan.

`reversa.sql` (volver al código anterior) solo se justifica si un escritor
resultó defectuoso por otra causa. Restaura **los CINCO** y **exige que no haya
cierres en dólares ni solicitudes F4 preparadas en otra moneda**: el CHECK vuelve
a `moneda = 'PEN'` y una fila en USD lo violaría. Si ya hay dólares vivos el
guion se niega y lo dice: qué se hace con ese dinero es una decisión de negocio,
no de despliegue.

🔑 **Si la reversa dejara fuera el quinto escritor, la migración ya no se podría
reinstalar**: su preflight exige la huella anterior de esa función. Por eso el
POSTREVERSA comprueba las cinco huellas previas, no cuatro.

## Si mañana se abre otra combinación

- **Qorilazo en dólares**, o una cuarta empresa: `update crm.empresas set
  monedas = ... ` y **actualizar el espejo** `INFO_COOPERATIVA` en el front en
  ese release (sin eso el servidor ya lo admite, pero el formulario no lo
  ofrece).
- Una moneda **que no sea PEN ni USD** sí necesita migración: el CHECK de la
  columna y `crm.empresas.monedas` la acotan a esas dos.
