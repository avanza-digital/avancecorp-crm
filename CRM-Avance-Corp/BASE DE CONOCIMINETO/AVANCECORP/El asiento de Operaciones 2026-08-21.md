# El asiento de Operaciones

*2026-08-21 · Portal · **COMPLETO EN PRODUCCIÓN**: base, servidor y panel, los tres verificados*

## La pregunta

Miguel pidió una cuenta para **la asistente de Gloria** que gestione **pagos,
contratos y clientes, y que pueda subir documentos**. Nada más.

## Por qué no existía

Gloria es —hoy— la **única cuenta `admin` del Portal**. Y `admin` es un
interruptor de **todo o nada**:

- las **nueve** pantallas del panel pasan por el mismo portero (`verificarAdmin`),
- y en la base, por la misma llave (`public.es_admin()`, que solo distingue
  «admin» de «superadmin»).

Lo que la asistente necesita son **cuatro** de esas nueve. Darle `admin` le
regalaba, además: comunicados masivos a los **360 clientes**, alta y baja de los
**19 analistas**, y borrar clientes y contratos.

El otro rol que existe, `analista`, tampoco servía: solo ve **su propia cartera**
(clientes con `asesor_perfil_id` = él) y ni siquiera alcanza las pantallas de
Pagos ni Documentos.

## La decisión de diseño (lo importante de esta nota)

Había dos caminos, y la diferencia entre ellos no es de estilo:

| | Camino A — meter el rol en `es_admin()` | Camino B — llave nueva ✅ |
|---|---|---|
| Trabajo | Menos ediciones | Más ediciones |
| Por defecto | **Concede** | **Niega** |
| Un objeto que se me olvide | Queda **abierto** | Queda **cerrado** |
| Un objeto que alguien cree **mañana** usando `es_admin()` | Se le abre **solo** | Sigue cerrado |

Se eligió **B**: `public.es_gestor_cartera()` = `es_admin() OR es_operaciones()`.
**`es_admin()` no se tocó.** Lo que se abre, se abre uno a uno y con nombre.

Y no es una opinión: el **mutante m2** del arnés contamina `es_admin()` con el rol
nuevo y el oráculo canta **siete** puertas abiertas que nadie pidió —comunicados,
borrado de documentos, borrado de cuotas, edición de analistas, `audit_log`,
Actividad y el cockpit del Directorio—. El camino A es una fuga con forma de atajo.

> **Regla para el futuro:** si algún día hay que ampliarle algo al asiento, se
> añade `es_gestor_cartera()` a **ese objeto concreto**. Meterlo dentro de
> `es_admin()` abre siete puertas de golpe.

## Qué puede y qué no

**Puede** (en sus cuatro pantallas): ver, crear, corregir y activar/desactivar
**clientes**; crear y corregir términos y número de **contratos**; registrar y
revertir **pagos**; y ver, descargar y **subir documentos**.

**No puede:** Dashboard, Comunicados, Actividad, Equipo, Conciliación ni
Directorio · **borrar nada** (clientes, contratos, cuotas, documentos) ·
importar clientes desde Excel · leer `audit_log` · tocar personal · entrar al CRM
(no es candidato a rol CRM). Y **no puede ascenderse**: crear el asiento es
exclusivo del **superadmin**.

**Las tres puertas que Miguel cerró al revisar el alcance** — yo las había dejado
abiertas con el default defendible y él las cerró, las tres:

| Puerta | Dónde se corta |
|---|---|
| **Cerrar ciclo** de contrato | `cerrar_contrato` sigue en `es_admin()`; la migración ni la nombra |
| **Reasignar asesor** de un cliente | El trigger `proteger_campos_inmutables` |
| **Resetear contraseñas**, ni de un cliente | La edge `resetear-password`, sin tocar |

La segunda tiene enseñanza propia: **la RLS decide por FILA y esto había que
decidirlo por COLUMNA**. No hay política que lo exprese, así que el corte baja al
trigger — donde ya viven las columnas privilegiadas de `perfiles`. Y **levanta una
excepción** en vez de restaurar en silencio como hace la rama del analista: un
guardado que dice «listo» y no reasigna nada es peor que un error claro. Solo
salta si el asesor **de verdad cambia**, porque el formulario reenvía el mismo
valor en cada guardado y si no reventaría toda edición de cliente.

## Cómo se probó

`supabase/scripts/run-test-portal-asiento-operaciones.sh --mutantes`

El oráculo corre **contra el esquema y los datos REALES de producción**, dentro de
una transacción que termina **siempre en `rollback`** (la técnica de
[[probar-en-prod-sin-escribir]]): siembra una identidad efímera y en tres actos
**ejecuta** cada afirmación —crear la política no prueba nada—: el asiento nuevo,
que **Gloria no pierde nada**, y que **un analista no gana nada**.
**6 mutantes, 6 cazados** (uno de ellos solo tras arreglar la prueba: ver trampa 5).

## Cinco trampas que costaron tiempo

1. **`text[] || 'literal'` revienta en runtime.** Ya estaba documentada en
   [[codigo-retomar-53]] y volvió a morder: el oráculo daba verde porque *nunca
   llegaba a acumular un fallo*; en cuanto tenía algo que reportar, se caía con
   «malformed array literal». Los mutantes salían rojos por la razón equivocada.
   Se cierra con `array_append`.

2. **La función viva llevaba un arreglo que el repo no tenía.** `resetear-password`
   en producción traduce el rechazo de contraseñas filtradas (HIBP) al castellano;
   esa traducción **no estaba** en `_supabase_functions/`. Editar la copia del repo
   y desplegar la habría **borrado de producción**. Es exactamente
   [[parche-solo-en-el-artefacto-no-existe]]: se descargaron las tres funciones
   **vivas**, se editaron ésas, y el repo se sincronizó con lo vivo + el cambio.

3. **Y la misma trampa, al revés, justo antes de desplegar.** `crear-cliente`
   importa `_shared/domicilio.mjs`. El **repo** tiene el validador endurecido del
   19-ago (mínimo 15 en vez de 5, exige un dígito, rechaza invisibles de ancho
   cero, rechaza un solo carácter repetido y rechaza la dirección de la propia
   Avance Corp); el **bundle vivo** tiene todavía el viejo, con mínimo 5 y nada
   de eso. Desplegar desde el repo habría metido un cambio de reglas de negocio
   —silencioso, dentro de un cambio de permisos— en el alta de clientes del
   portal. Se desplegó con el `_shared` **VIVO**: el único delta es el permiso.
   👉 **Deuda abierta, pendiente de decisión de Miguel:** ¿se lleva ese validador
   endurecido al portal, o el listón de 15 era solo para el CRM?

4. 🔴 **Hay una CDN delante del portal, y casi tira las cuatro pantallas.** Una
   revisión adversaria de 5 lentes (33 agentes) lo cazó **antes** de subir: el JS
   se sirve con `max-age=604800` (**7 días**) desde una CDN (`server: hcdn`), **el
   query string forma parte de la clave de caché**, y el HTML va a `max-age=0`.
   Lo verifiqué yo: `js/auth.js?v=22` respondía **HIT** con el `auth.js` **viejo**
   — la clave ya estaba envenenada porque los propios revisores la habían pedido
   para comprobar. Si llego a subir sin más, el HTML nuevo habría pedido esa
   clave, el módulo no habría enlazado (`SyntaxError: does not provide an export
   named verificarGestorCartera`) y **Clientes, Contratos, Pagos y Documentos se
   apagan para todos, Gloria incluida, durante 7 días**. Se cerró con: orden de
   subida + **purga de la caché** + verificar la URL versionada exacta.
   La regla queda escrita en los anti-patrones de `public_html/CLAUDE.md`.

5. 🔴 **Una aserción mía dependía del dato y no probaba nada.** El oráculo
   comprobaba que el asiento no puede reasignar el asesor haciendo
   `update … where asesor_perfil_id is distinct from <Rosa>`. Pero el cliente de
   la prueba **ya tenía a Rosa**: el `UPDATE` no tocaba ninguna fila, el trigger
   nunca se ejercitaba, y el mutante que le quita el corte pasaba en **VERDE**.
   Lo destapó volver a correr los mutantes al final, no la primera vez. Arreglado
   sembrando un analista *garantizado distinto*. Otra vez
   [[ejecutar-contra-la-forma-real]]: un fixture no es un invariante.

## Estado

**✅ Base EN PRODUCCIÓN.** Migración `20260821222348_portal_asiento_operaciones.sql`,
registrada en el índice remoto. Postflight contando objetos (no fiándose de la
respuesta, [[merge-de-supabase-puede-mentir]]): **2/2** funciones nuevas · **9/9**
políticas abiertas · **6/6** funciones abiertas · `es_admin()` **intacta** ·
trigger cortando el asesor · `cerrar_contrato` sigue de Gloria · datos intactos
(389 perfiles, 426 contratos) · **0 cuentas** con el rol nuevo.

**✅ Servidor EN PRODUCCIÓN.** `crear-admin` v16→**v17** y `crear-cliente`
v29→**v30**, ambas con `verify_jwt` conservado y **byte-idénticas** al bundle que
subí (descargadas y contrastadas). `resetear-password` **no se tocó**.

**✅ Panel EN PRODUCCIÓN.** 42 archivos subidos uno a uno por TUS (nunca
`deployStaticSiteArchive`, que **sobrescribe el sitio entero**), en orden fijo:
`auth.js` primero, `service-worker.js` último. Verificado por hash contra el
servidor: **21/21 páginas y 32/32 recursos versionados idénticos al repo**.

**Lo único que falta:** el **superadmin** crea la cuenta desde Equipo →
*+ Nuevo miembro del equipo* → **Operaciones**, con contraseña explícita (este
asiento no admite la clave temporal por DNI).

Mientras no exista ninguna cuenta con el rol, **nada cambia para nadie**: por eso
se pudo aplicar base y servidor antes que el panel sin riesgo.

Relacionado: [[portal-llamaba-puerta-cerrada-cors]] (la otra puerta administrativa
que el sistema contemplaba y la pantalla no dejaba abrir) · [[crm-portal-separados]]
