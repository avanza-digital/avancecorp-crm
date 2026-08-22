---
estado: ✅ VIVO — secreto ROTADO a env y RE-VERIFICADO end-to-end 2026-07-21
fecha: 2026-07-20
---

# Carga de leads desde hoja de Google

**Decisión de Miguel (2026-07-20):** el canal de carga de leads reales al CRM es la
hoja de cálculo de Google del equipo. El CRM no tiene (ni tendrá por ahora) un
importador CSV propio: se conecta la hoja.

## La plantilla (creada 2026-07-20)

- **Archivo:** "Leads AVANCE CORP — captura para CRM" en el Drive de avancecorp26@gmail.com
- **URL:** https://docs.google.com/spreadsheets/d/13daMj7xJfow4ViqSfgJQF5_MSCTQpD73lr8x2llu8ZA/edit
- **fileId:** `13daMj7xJfow4ViqSfgJQF5_MSCTQpD73lr8x2llu8ZA`
- Incluye 2 filas de EJEMPLO marcadas "borrar".

Columnas (espejo de `crm.leads` Insert; las que tienen `*` son obligatorias):

| Columna | Mapea a | Validación que aplicará el conector |
|---|---|---|
| Nombre completo * | `nombre_completo` | no vacío |
| Teléfono * | `telefono` | `normalizarTelefono`: `9########` o `+51 9########` → E.164 `+519########`; otro formato = fila rechazada |
| Capital estimado * | `monto_estimado` | numérico, ≤ 9 999 999 999.99 |
| Moneda * | `moneda` | `PEN` \| `USD` |
| Canal de origen * | `origen` | catálogo vivo: Referido/LANDING/FORMULARIO/Wallking(=`oficina`)/Otro (los heredados web/campania/whatsapp solo lectura) |
| Correo | `correo` | regex laxa espejo del CHECK |
| DNI | `dni` | 8 dígitos |
| Género (F/M) | `genero` | `F` \| `M` |
| Fecha de nacimiento | `fecha_nacimiento` | DD/MM/AAAA → ISO; edad ≥ 18 (`EDAD_MINIMA`, capa app no CHECK) |
| Distrito | `distrito` | libre |
| Interés | `categoria_interes` | Nuevo/Renovación/Upgrade |
| Nota | `nota` | libre |
| Vendedor asignado (correo) | `vendedor_id` | resolver contra `crm.equipo`; vacío = bandeja "por repartir" (`vendedor_id null`) |
| ¿Autorizó contacto? | `consentimiento_en` | SI registra consentimiento; NO o vacío importan igual como lead visible y repartible |
| Fuente del consentimiento | `consentimiento_fuente` | libre |

`etapa` no va en la hoja: todo lead entra como `nuevo`. `creado_por` lo pone el conector.

## El conector (CONSTRUIDO 2026-07-20, opción B automática — decisión de Miguel)

Arquitectura: **Apps Script dentro de la hoja** (trigger cada 5 min) → POST al
**edge `crm-importar-leads`** (v1 DESPLEGADO en prod, verify_jwt) → valida +
dedup por teléfono + INSERT con service_role → el script pinta el resultado en
la **columna P "Estado importación"** de la propia hoja (la hoja es la UI de
rechazos: corregir la fila y borrar su estado = reintento en el próximo ciclo).

- **Edge:** `_supabase_functions/functions/crm-importar-leads/index.ts` (fuente en repo = lo desplegado).
  Probado contra prod 2026-07-20: sin/mal secreto→401; teléfono malo, moneda mala,
  menor de edad→RECHAZADO con motivo; fila válida→IMPORTADO (verificado en BD:
  tel normalizado `+51999000111`, Wallking→`oficina`, por repartir); reintento→DUPLICADO.
  Dato de prueba borrado.
- **Apps Script:** copia de respaldo en `CRM-Avance-Corp/scripts/hoja-leads-apps-script.gs`.
  `configurar()` (una vez) crea encabezado col. P + trigger 5 min; `importarLeads()` con
  LockService, `getDisplayValues` (texto tal cual), lotes de 200, "ERROR temporal" reintenta solo.
  **UPGRADE UX 2026-07-21 (v2 del script, "a prueba de errores"):** `configurar()` ahora también
  pone **menús desplegables** (Moneda/Canal/Género/Interés/¿Autorizó?) con lista cerrada,
  fuerza a **TEXTO** las columnas numéricas (teléfono/capital/DNI/fecha) — elimina de raíz el
  "DNI inválido" por separadores de miles que mete Sheets —, colorea la columna de estado
  (verde/ámbar/rojo/azul) y congela la cabecera. Nuevo disparador simple **`onEdit`**: al editar
  cualquier campo A–O de una fila, borra su estado → se re-importa sola (ya no hay que borrar la
  col. P a mano). Requiere **re-pegar el .gs y correr `configurar()` una vez**.
- **Resoluciones de las 3 decisiones:** dedup por teléfono normalizado (DUPLICADO, no inserta) ·
  sync automático cada 5 min · rechazos en la columna P.
- **Vendedor asignado:** correo→`perfiles`→`crm.equipo` (activo, vendedor|supervisor);
  si no resuelve, el lead entra igual SIN dueño con aviso "(vendedor no encontrado → por repartir)".
- Leads importados nacen: `etapa='nuevo'`, sin dueño (cola por repartir de gerencia,
  permitido porque `auth.uid()` es null con service_role), `creado_por=null` (= importación de sistema).

### Seguridad — ROTADO Y MOVIDO A ENV (2026-07-21)
Doble capa: anon key como Bearer (verify_jwt) + secreto compartido `x-importar-secret`
(comparación tiempo-constante). Desde el 2026-07-21 el secreto **NO vive en ningún
archivo**: la edge (v2, sha `0bf64ffe…`) lo lee de `Deno.env.get("CRM_IMPORTAR_SECRET")`
y el Apps Script de `PropertiesService` (propiedad `IMPORTAR_SECRET`). **Fail-closed**:
sin env la edge responde 401 a todo (verificado en vivo: secreto viejo→401, sin
secreto→401). El secreto anterior (hardcodeado) quedó INVALIDADO. El ANON_KEY sí va
inline en el .gs: es la llave pública. Con esto los archivos del conector quedaron
COMMITEABLES (deuda del go-live saldada).

### Rotación 2026-07-21 — COMPLETADA Y VERIFICADA
1. **Dashboard de Supabase** → proyecto `dctqcbznekcyxhjujuci` → Edge Functions →
   Secrets → `CRM_IMPORTAR_SECRET` = secreto nuevo. ✅ HECHO por Miguel (agregarlo
   reinició la función a versión 3, visto en logs).
2. **La hoja** → Propiedades del script → `IMPORTAR_SECRET` = mismo valor + código
   actualizado pegado. ✅ HECHO por Miguel (su ejecución completó sin el throw
   "Falta IMPORTAR_SECRET" → la propiedad está puesta).
**Verificación end-to-end (2026-07-21):** POST con el secreto nuevo → HTTP 200
"IMPORTADO ✓"; la fila aterrizó en crm.leads con teléfono normalizado
(`+51999000111`), origen `referido`, etapa `nuevo`, sin dueño, `creado_por` null;
dato de prueba BORRADO (crm.leads de vuelta a 0). El secreto viejo da 401 (invalidado).
**El conector queda VIVO de nuevo, con el secreto fuera del código.**

**Rotaciones futuras** (sin redeploy): nuevo valor → actualizar el secret del dashboard
Y la propiedad del script. Nada más.

### Endurecimiento tras auditoría Codex (2026-07-21, edge v4 desplegada, verificada en vivo)
Codex auditó el conector (8 hallazgos: 0C/0A/4M/4B). **7 corregidos** en la edge (v4,
sha `04b1fcc4…`); el #4 quedó como decisión pendiente (ver abajo).
- **Consentimiento estricto** (Medio): "¿Autorizó contacto?" solo acepta SI/SÍ/S,
  NO/N, o vacío. Un typo tipo `N0`/`FALSE` RECHAZA la fila en vez de fabricar
  `consentimiento_en`; `consentimiento_fuente` solo se guarda con un SÍ explícito.
  **Decisión posterior 2026-08-22:** NO y vacío ya no activan `no_contactar`; todos
  los leads de la hoja quedan visibles y repartibles.
- **Errores de resolución de vendedor** (Medio): un fallo consultando `perfiles`/
  `crm.equipo` ahora corta con HTTP 500 ANTES de insertar (el Apps Script reintenta
  como "ERROR temporal") — antes se leía como "sin vendedor" e importaba todo sin dueño.
- **parseCapital estricto** (Medio): un solo formato (coma=millar, punto=decimal);
  RECHAZA `5000.999` (3 dec), `12,50` y `50.000,00` (antes daban 5001/1250/50). Espejo
  de `validacion.ts` del CRM: rechazar, nunca redondear.
- **Edad en calendario de LIMA** (Bajo): `edadCumplida` resta 5 h a UTC (antes 19-24 h
  Lima aceptaba a alguien un día antes de cumplir 18).
- **Fortaleza del secreto** (Bajo): la edge exige `/^[0-9a-f]{64}$/i` en el secreto del
  env; un valor débil ("x") ahora falla cerrado igual que ausente.
- **Versión fija** (Bajo): `jsr:@supabase/supabase-js@2.110.8` (no `@2`).
- Verificado en vivo (POST reales): typo→RECHAZADO, formatos UE/3-dec→RECHAZADO,
  NO→sin consentimiento, SI→con consentimiento y fuente; datos borrados, crm.leads=0.
- **#4 (Medio, PENDIENTE — decisión de Miguel):** el conector usa las **llaves legacy**
  de Supabase (anon JWT + service_role). Supabase las mantiene hasta fin de 2026 pero
  recomienda migrar a las nuevas API keys (publishable/secret). Migración: cliente admin
  a `SUPABASE_SECRET_KEY`, y el Apps Script de "anon JWT + verify_jwt=true" a
  "verify_jwt=false + solo el secreto compartido estricto". No urgente; requiere
  aprovisionar la secret key nueva y re-verificar. NO ejecutado.

### Instalación VERIFICADA (2026-07-20, mismo día)
Miguel pegó el script y ejecutó `configurar()`. Verificado end-to-end: columna P creada,
las 2 filas de EJEMPLO de la plantilla se importaron solas ("IMPORTADO ✓" en la hoja,
filas correctas en `crm.leads` con teléfono normalizado y canal mapeado) y luego se
BORRARON de la BD (eran ficticias; `crm.leads` de vuelta en 0, listo para leads reales).
Las 2 filas de ejemplo pueden quedarse en la hoja (estado no vacío = no se reimportan)
pero lo limpio es borrarlas. **El conector queda VIVO: toda fila nueva en la hoja entra
sola al CRM en ≤5 min.**

## Puente desde el documento de origen (CONSTRUIDO 2026-07-22)

> ⚠️ **Corrección 2026-07-27:** esta nota decía "sin instalar". Es falso: el puente se
> instaló y corre desde el **2026-07-23** (memoria de sesión: «cadena de leads viva» —
> origen ~12.056 filas → puente → hoja → conector → `crm.leads`, primer lote 55).
> `crm.leads` acumula **121** (1 del 21-jul + 55 del 23 + 65 del 24). Las cifras
> "377 filas / 324 entran" de más abajo son de ANTES del arreglo del tope de lectura:
> el origen real es mucho más grande. **Desde el 25-jul no entra nada nuevo** —
> coincide con que las filas nuevas del origen vienen SIN "Fecha de Registro" y la
> regla vieja las mandaba TODAS a REVISAR (159 presas; arreglado hoy, ver «Reglas
> nuevas de REVISAR»).

**El problema:** los leads caen primero en un documento de la empresa,
`02PLAZOFIJOMAS LANDING` (`1VriA6vr-QjLDRnyH-sx-sgNwyYNvsNFR1d1JZbRBwEs`, dueño
`consultas@creaemprendedor.com`, compartido con Miguel). **Rosa** filtraba a mano y
transcribía a nuestra plantilla → con el conector automático eso era doble trabajo.

**La solución:** `CRM-Avance-Corp/scripts/puente-drive-origen.gs`, un segundo Apps
Script que va DENTRO de nuestra hoja, LEE el documento de origen y escribe solo en la
nuestra. De ahí el conector de 5 min sigue igual. Menú "AVANCE CORP" → *Vista previa*
(no escribe nada) / *Traer leads del origen*.

> ⚠️ **El documento de origen es de la empresa y NO SE TOCA** (orden de Miguel
> 2026-07-22). El script solo llama `getSheets/getName/getDataRange/getDisplayValues`
> sobre `origen`; la única variable que recibe escrituras es `destino`.

### Qué trae y qué tira
| Nuestra hoja | Origen |
|---|---|
| Nombre completo * | `nombre` + `Apellidos` |
| Teléfono * | `Celular` → `+51XXXXXXXXX` (respaldo: WhatsApp / celular 2) |
| Capital estimado * | piso del rango: "50,000 a más" → 50000, "más de 100,000" → 100000 |
| Moneda * | "Soles"→PEN, "Dólares"→USD, "Soles/Dólares"→PEN + aviso en la Nota |
| Canal de origen * | pestaña `landing` → LANDING; el resto → FORMULARIO |
| Distrito | `Distrito`, o `ciudad` en la pestaña sin distrito |
| Interés | siempre `Nuevo`; "ya es socio" se guarda en la Nota (55 casos) |
| Nota | fecha original + la pregunta que dejó + socio + trazabilidad pestaña/fila |
| ¿Autorizó contacto? | la columna real donde existe; si la pestaña no la tiene, `CONSENTIMIENTO_SI_NO_HAY_COLUMNA` |

**Descartado a propósito:** WhatsApp (= Celular en 175/190 filas), Departamento (la
hoja trabaja a nivel de distrito), "¿deseas aperturar tus ahorros?" (186 de 187
responden lo mismo), emojis y guiones bajos, filas de encabezado repetidas.
Género, fecha de nacimiento, correo y DNI **no existen en el origen** → quedan vacíos.
"Vendedor asignado" queda vacío **a propósito**: el reparto ocurre DENTRO del CRM
([[Fase C1 — Reparto de la cola (plan build-ready)]]).

### Decisiones de diseño
- **Mapeo por palabra clave, no por posición**: si renombran o mueven una columna del
  origen, el puente sigue. El orden de las reglas importa — "¿Deseas depositar en soles
  o dólares?" tiene que caer en *moneda*, no en *monto*, y "¿deseas aperturar tus
  AHORROS?" no es el monto.
- **Fecha = la MÁS ANTIGUA de la fila**: las pestañas traen dos columnas de fecha y la
  reciente es marca de exportación, no de captación. Los leads son de jul–dic 2025.
- **Lo rechazado no se pierde**: pestaña `REVISAR (no importados)` con motivo y fila
  cruda. Rosa solo mira excepciones (sin teléfono, duplicado, sin monto).
- **Idempotente**: pestaña oculta `_puente_huellas` (pestaña|teléfono) + cotejo contra
  los teléfonos ya escritos en la hoja → re-ejecutar no duplica.
- La columna P (estado) se deja VACÍA: es la señal de "pendiente" del conector.
- Escribe solo valores de los menús cerrados que puso `configurar()` (PEN/USD,
  LANDING/FORMULARIO, Nuevo, SI/NO); si no, la hoja los marcaría inválidos.

### Verificación
`scratchpad/probar-puente.mjs` carga el `.gs` en Node con Sheets simulado y corre 33
aserciones sobre filas reales de las dos pestañas (mapeo de columnas, teléfonos con
espacios, correo metido en la columna de WhatsApp, fijo de 7 dígitos rechazado, montos
con separador de miles, moneda mixta, emojis, fecha más antigua). **33/33 en verde.**

### Formato de REVISAR arreglado (2026-07-27)

Miguel reportó que la pestaña `REVISAR (no importados)` era ilegible. Causa: la
columna F volcaba la fila cruda del origen entera en una sola celda, unida con `|` y
SIN encabezados (`fila.join(" | ")`) — imposible saber qué campo era cuál.

**Arreglo:** `filaLegible()` + `legible()` en el `.gs`. Cada celda ahora trae
`Encabezado: valor`, UNA LÍNEA POR DATO (salto de línea dentro de la misma celda,
`setWrap(true)` + ancho de columna fijado). `legible()` limpia guiones BAJOS y
símbolos/emojis sueltos al inicio del encabezado de Facebook
(`✅_si_deseo_aperturar_mi_cuenta` → "si deseo aperturar mi cuenta") — a propósito NO
toca el guion normal, porque rompería fechas ISO (`2026-07-23T18:47:09-05:00`) y
formatos de teléfono. Se aplica tanto al encabezado como al valor (el valor también
venía crudo con guiones bajos: `"si_"`, `"50,000_"`).

**Pendiente:** el `.gs` vive en el repo pero Apps Script no lo toma solo — falta que
Miguel **re-pegue el archivo actualizado** en Extensiones → Apps Script de la hoja
para que el arreglo tenga efecto. Hasta entonces, la pestaña REVISAR sigue mostrando
el formato viejo (ilegible) porque ahí no corrió el .gs nuevo todavía.

### Reglas nuevas de REVISAR (2026-07-27, orden de Miguel)

Miguel, al ver REVISAR: la fecha NO es motivo de revisión — «la fecha la determinas
por el día en el que entre el lead». Los motivos que importan son **duplicado** y
**que pida préstamo**. Ese día había **159 leads potenciales presos** por "Sin fecha
legible" (el origen dejó de llenar "Fecha de Registro" en las filas nuevas de la
pestaña `landing`).

1. **Sin fecha → ENTRA igual**, con "Sin fecha en el origen (vale la del ingreso)"
   en la Nota. El motivo "Sin fecha legible" ya no existe. El corte del 2026-07-22
   sigue frenando SOLO lo que trae fecha legible VIEJA (el backlog 2025 viene
   fechado, así que sigue fuera). Se quitó la constante
   `DESCARTAR_SIN_FECHA_SI_HAY_CORTE`.
2. **Rescate de teléfono**: si celular/WhatsApp no dan número usable, se busca en
   TODA la fila (saltando monto y DNI; `telefonoPeru()` es estricto, así que fechas
   y montos no pasan por número). Razón: la pestaña de Facebook tiene DOS columnas
   "celular" — la 1ª trae lo que la persona tipeó (a veces un monto o su nombre) y
   el número real está en la 2ª con prefijo `p:`; el mapeo por encabezado solo veía
   la 1ª. De los 7 "Sin teléfono válido" de ese día, 3 se rescataban solos. Entra
   con aviso en la Nota; el motivo restante es "Sin teléfono válido (se buscó en
   toda la fila)".
3. **Préstamo → REVISAR**: comentario que mencione préstamo/crédito
   (`/presta|credito/` sobre texto normalizado) cae con motivo **"Pide PRÉSTAMO — no
   es lead de ahorro"** (captamos depósitos, no colocamos créditos). El chequeo corre
   ANTES que los rechazos por dato faltante y con nombre/teléfono ya resueltos, para
   que quien revise vea a la persona. ⚠️ Ya entró al CRM al menos un lead con
   "quiero prestamo" ANTES de esta regla (fila de prueba de Miguel).
4. REVISAR queda solo con lo accionable: duplicados, pide préstamo, sin teléfono
   (tras rescate), sin nombre.

**Tests:** `scripts/puente-drive-origen.test.mjs` (`npm run test:puente`, 14/14) —
EN EL REPO esta vez, con encabezados y filas reales del origen como fixtures; el
arnés viejo se perdió por vivir en scratchpad.

**Al re-pegar el .gs y correr "Traer leads del origen"**: los ~159 presos entran
solos (REVISAR se reescribe entera en cada pasada) y de ahí el conector los sube al
CRM en su ciclo de 5 min.

### Primera corrida real con las reglas nuevas (2026-07-27 noche) — VERIFICADA

- Miguel pegó el `.gs` y corrió "Traer" (dos veces). **158 leads entraron al CRM esa
  noche → `crm.leads` = 279**, incluidos **4 con teléfono rescatado** de otra columna
  (Hestilber/cuillrmo/David/Manuel Lomas — verificados por SQL, están en la base).
- La 1ª corrida escribió ~165 filas en LEADS pero **murió antes de guardar huellas**
  (timeout probable de Apps Script sobre las ~12k filas del origen) → la 2ª corrida
  re-listó esas mismas filas como "Teléfono ya presente en la hoja" (163). **Ningún
  duplicado entró**: la defensa por teléfono de la hoja funcionó, y el conector frenó
  ~7 más que ya existían en el CRM (dedup de la edge, tercera línea).
- ⚠️ **El export de Drive TRUNCA hojas grandes** (mostraba 154 filas de LEADS cuando
  había ~232): verificar SIEMPRE contra `crm.leads` por SQL, no contra el export.
- **Fix aplicado al `.gs` (2026-07-27 noche):** (1) las huellas se guardan ANTES de
  escribir REVISAR — si la corrida muere a mitad, lo grave era "leads sin huella";
  (2) los **duplicados también se huellán** → se listan en REVISAR UNA sola vez y las
  corridas siguientes los saltan en silencio (sin esto, las 163 filas reaparecerían
  en CADA corrida para siempre, enterrando lo accionable); (3) REVISAR **ordenada**:
  préstamo / sin teléfono / sin nombre arriba, duplicados al final (`ordenRevision`,
  pura y testeada). Tests `npm run test:puente` **15/15**.
- **FALTA: re-pegar el `.gs` UNA vez más** (misma rutina de 2 min; no hay que correr
  nada después). La próxima corrida normal mostrará los ~163 "ya presente" una última
  vez —quedan huellados en esa pasada— y de ahí en adelante REVISAR queda limpio.
- Lo único real que quedó en REVISAR hoy: 2 "Sin teléfono válido" (un fijo mal
  tipeado `51481414044` y una fila basura "JULIO 2026*" del origen) y 2 "Sin nombre".
  Cero préstamos en este lote.

> ⚠️ Ese arnés **se perdió** (vivía en `scratchpad/`, nunca se commiteó). El `.gs` sobrevive
> porque está en `CRM-Avance-Corp/scripts/`. Si hace falta re-verificar, se reconstruye
> cargando el `.gs` con `new Function()` en Node y alimentándolo con las filas del origen.

### Corrida de vista previa contra el origen real (2026-07-22)

Puente ejecutado en local sobre las 377 filas del origen (sin tocar ninguna hoja):

| | |
|---|---|
| **Entran** a nuestra hoja | **324** (160 de `landing` + 164 del formulario FB) |
| Van a `REVISAR` | 53 → 31 duplicados por teléfono, 22 sin teléfono válido |
| Nombre real de la pestaña 1 | **`landing`** (confirmado) → `CANAL_POR_PESTANA` acierta |

Ignoradas tal como se diseñó: `Departamento` (landing) y `¿deseas aperturar tus ahorros
a plazofijo?` + marca de tiempo de exportación + `celular` duplicado (FB).

### Horario automático (Miguel, 2026-07-22)

El puente corre solo **lunes a sábado, 9 a. m. de Lima. Domingos NO.** Apps Script no tiene
"todos los días menos domingo", así que son **6 disparadores semanales** (`onWeekDay` +
`atHour(9)`), uno por día. Menú: *Activar horario automático* / *Ver horario* / *Apagar*.

- La zona va fijada con `.inTimezone("America/Lima")` en el código, **no** se hereda de la
  zona del proyecto de Apps Script — si el proyecto quedara en hora del Pacífico, el
  horario igual dispara a las 9 de Lima.
- `atHour(9)` es una **ventana 9–10 a. m.**, Google no garantiza el minuto.
- `instalarHorario()` es **idempotente**: borra los suyos antes de crear (no duplica
  corridas) y no toca el disparador del menú ni el del conector.
- Cadena completa: 9 a. m. el puente escribe en la hoja → el conector la sube al CRM en su
  ciclo de 5 min → los leads caen en la cola global.
- Si una corrida falla, Google manda correo al dueño del script; el detalle queda en el
  Registro de ejecución.

Verificado con Apps Script simulado: **10/10** (6 disparadores, domingo excluido, hora y
zona correctas, idempotencia al reinstalar, no pisa otros disparadores, apagar deja 0).

### Columna "¿Autorizó contacto?" — CERRADO, no volver a preguntar

Miguel lo zanjó el **2026-07-22**: la pestaña del formulario de Facebook no trae esa
columna → sus 164 leads entran con **`SI`**. Punto. **No re-abrir el tema con él.**

Donde la pestaña sí trae el dato (`landing`), manda el dato real: 175 "Si" / 15 "No",
sin celdas vacías. La columna se conserva como dato de origen y para registrar un SÍ
explícito, pero desde el 2026-08-22 ya no controla `no_contactar` ni el reparto.

Codificado en `CONSENTIMIENTO_SI_NO_HAY_COLUMNA` + `FUENTE_POR_PESTANA` /
`FUENTE_POR_DEFECTO` (esta última aplica a toda pestaña sin entrada propia y su texto
nombra a Facebook: si el origen gana una pestaña nueva, añadirla al mapa).

## 2026-08-16 — La cadena, auditada de punta a punta (y la puerta de atrás, cerrada)

Miguel pidió arreglar los dos scripts. Antes de tocar nada, los hechos:

| Hecho | Cómo se comprobó |
|---|---|
| **El origen está CONGELADO desde el 24-jul** | `modifiedTime` del fichero de Drive. No hay nada nuevo que traer: la cadena está seca **en la fuente**, no en el puente |
| El origen **no es nuestro** | dueño `consultas@creaemprendedor.com`. Quién lo alimenta es pregunta para ellos; nosotros solo leemos |
| La pestaña LEADS está **vacía** | mirada en el navegador: solo la cabecera |
| `_puente_huellas` conserva **279 huellas** (280 filas con cabecera) | contadas en la hoja. Coinciden **exactamente** con los 279 leads del 27-jul. Esos NO vuelven a entrar — correcto, la limpieza del dataset fue deliberada |
| `crm.leads` = **5**, ninguno de importación | SQL: `creado_por is null` → 0 |
| La suite del puente llevaba **rota desde el 11-ago** | 5 de 15 en rojo; `4473fd5` movió el corte y no tocó los fixtures |
| Nadie la corría | `test:puente` no estaba en ningún gate ni en CI |

### La puerta de atrás del corte (lo que de verdad había que arreglar)

`FECHA_CORTE` **solo frena las filas CON fecha legible**. Las que vienen sin fecha lo
esquivan por diseño (regla de Miguel del 27-jul) — y en este origen **las filas sin
fecha son backlog viejo disperso**: las huellas lo enseñan (`landing` 671-872 y
2508-5288 sin fecha, mientras lo fechado del 23-24 de julio está al final, 6122-6158).
La única defensa era **acordarse de apagar el temporizador a mano**, y con el corte ya
vencido la puerta estaba abierta de par en par: encender el puente habría metido leads
de julio con etiqueta de agosto, falseando el divisor de la conversión del mes.

**El arreglo — MARCA DE AGUA** (`_puente_marcas`, oculta y protegida, **por sheetId**
para que renombrar una pestaña no borre la memoria):

- una fila **sin fecha que ya estaba** la vez anterior es historia → no entra;
- una fila **sin fecha que aparece después** es un lead nuevo → entra, como pidió Miguel.

**La frontera se pone A MANO, una vez**: menú → *Inicializar marca de agua*. Importa
**cero** leads, deja reporte y **no mueve una marca ya puesta** (si se volviera a correr
por costumbre, empujaría la frontera y los leads llegados entretanto desaparecerían sin
rastro). **Si no hay marcas, el puente se detiene y lo dice** — una primera pasada que
la adoptara en silencio sería la misma trampa con otra cara.

**Y la marca por número de fila solo vale mientras el origen crezca por abajo, que es un
supuesto y no una ley.** `revisarPestana()` lo comprueba en CADA pasada y **detiene la
pestaña entera** si: desaparecen filas · cambian los encabezados · la pestaña es nueva ·
las **tres últimas filas ancladas por contenido** ya no dicen lo mismo (= se ordenó o se
insertó en medio). La pestaña detenida sale arriba del reporte y su marca queda intacta.

### Otras trampas cerradas el mismo día

- **`insertSheet(nombre)` coloca la pestaña junto a la ACTIVA**, no al final — y el
  conector importa de `getSheets()[0]`. Una pestaña de memoria delante lo pondría a leer
  huellas como si fueran leads. Las tres creaciones van ahora con índice fijado al final.
- **La huella lleva una "h" delante**: sin ella, `"00123456"` viaja a la celda, Sheets la
  lee como el número `123456` y la comparación **falla en cada corrida** (falsa alarma
  perpetua).
- **Candado en toda pasada que escribe**: la corrida de las 9 y un *Traer* a mano se
  solapaban y, como las huellas se guardan al final, escribían los mismos leads dos veces.
- La marca **avanza solo después** de escribir los leads y guardar sus huellas.

### Gate nuevo: `npm run gate:apps-script`

Falla si un `.gs` **invoca una función que no existe** — exactamente el fallo que se
cometió ese día (`leerMarcas`/`guardarMarcas` llamadas antes de escribirlas) — y si dos
archivos del mismo proyecto de Apps Script **chocan de nombre** (dos `const` iguales en
el ámbito global es un SyntaxError que tumba el proyecto entero, menú incluido).
`node --check` no ve nada de esto: es JavaScript válido y revienta **en caliente**, a las
9 de la mañana, tras leer 12.000 filas.

⚠️ **A prueba de comentarios, textos y expresiones regulares.** La versión ingenua leía
la prosa de los comentarios y las regex como llamadas: **60 falsos positivos**, tanto
ruido que se acabaría ignorando. Misma lección que el oráculo del cierre de mes.

`check:scripts` ahora corre el gate **y** `test:puente`.

### Estado de las pruebas

**15 (5 en rojo) → 30 en verde.** Las fechas **se derivan del corte**, que es justo lo
que las pudrió en silencio: las tres que hablan de fechas prueban la frontera (víspera,
día del corte, día siguiente) y las que no hablan de fechas ya no pueden romperse al
moverla. **Los 8 mutantes** que neutralizan cada arreglo **mueren**.

### Fecha de arranque: LUNES 17 DE AGOSTO

Orden de Miguel (2026-08-16): «los leads quiero que desde el lunes que viene comiencen a
llegar al sistema desde el 17 de agosto». `FECHA_CORTE = "2026-08-17"`. El 15 y el 16
cayeron en sábado y domingo con la cadena apagada. **El 17 marca desde cuándo cuentan los
leads, no obligatoriamente el día en que se enciende.**

### La hoja, mirada por dentro (2026-08-16, navegador)

Miguel dio acceso y se comprobó en vivo lo que el export de Drive no puede decir:

- **Tres pestañas exactas, ninguna oculta de más:** `LEADS` · `REVISAR (no importados)` ·
  `_puente_huellas` (con **candado**: la protección funciona). `_puente_marcas` aún no
  existe, como debe ser: la crea `inicializarMarcas()`.
- ✅ **La primera pestaña se llama literalmente `LEADS`** → `getSheetByName("LEADS")`
  estricto es SEGURO. El respaldo `getSheets()[0]` no estaba tapando nada; se puede
  quitar en la Fase 2 sin romper la cadena.
- ⚠️ **`LEADS` tiene exactamente 2001 filas** (cabecera + las 2.000 que preparó
  `configurar()`). El techo **no es teórico**: el puente escribe hasta 500 por pasada, así
  que **la quinta pasada llena revienta** con "out of bounds" al escribir en la 2002 —
  después de haber leído las 12.000 filas del origen, y sin llegar a guardar la marca.
- **279 huellas** — no las ~230 que yo había estimado leyendo el export de Drive, que
  **trunca** (la trampa que esta misma nota ya advertía). Es el número exacto que hay que
  volver a ver después de pegar los scripts.

### Fase 2 — la hoja crece sola y preparar deja de encender (2026-08-16, `99d088d`)

- **El techo de 2001 filas era una pared, no holgura.** Con 500 leads por pasada, la
  **quinta pasada llena reventaba** con «out of bounds» al escribir en la 2002 — tras
  leer las 12.000 filas del origen y sin llegar a guardar la marca, o sea repitiendo el
  mismo trabajo para siempre. Ahora `asegurarCapacidadLeads()` inserta las filas que
  falten (de 500 en 500) y `prepararTramo()` les da **formato de texto y menús**: las
  filas recién insertadas nacen crudas y son justo donde Sheets vuelve a «arreglar» el
  teléfono y el DNI. Las otras tres escrituras que podían desbordar la rejilla (huellas,
  marcas, REVISAR) también crecen antes de escribir.
- **`configurar()` partido en dos.** Hacía formato + disparador + importación inmediata
  en un botón: no había forma de dejar la hoja lista y **mirarla** antes de encender.
  Ahora `prepararHoja()` y `activarConector()`, más **`apagarConector()`** para la vuelta
  atrás de la Fase 5. La vieja queda como aviso con instrucciones.
- **La pestaña se resuelve por NOMBRE** en los dos archivos (y `onEdit` deja de ir por
  índice): bastaba arrastrar una pestaña — o que el puente creara una de memoria en el
  sitio equivocado — para poner al conector a importar **huellas creyendo que eran leads**.
- **El secreto se lee dentro de la función**, no en el nivel superior: ahí corría en cada
  ejecución del proyecto, **incluidos los disparadores simples que van sin autorización**
  (el menú, `onEdit`), y congelaba el valor al cargar (rotarlo obligaba a reiniciar).
- **El menú ahora es el guion del arranque**: 1 · Preparar la hoja · 2 · Inicializar marca
  de agua · 3 · Vista previa · luego traer / encender / apagar.
- **El gate modela bien Apps Script**: los `.gs` de un proyecto comparten **un solo ámbito
  global**, así que las llamadas se contrastan contra la **unión** de los archivos. Sin
  eso, que el puente llame a `asegurarCapacidadLeads` del conector daba un falso positivo.

**Pruebas 30 → 36.** Las seis nuevas son **estructurales sobre el código con los
comentarios quitados** (varios comentarios nombran justo lo que prohíben). ⚠️ **Un mutante
sobrevivió y tenía razón**: la comprobación del secreto solo miraba el texto anterior a la
*primera* función, y las declaraciones de nivel superior van **intercaladas** entre
funciones. Corregida por indentación (columna 0) y ubicación única; ahora muere en las
tres posiciones probadas. Los otros 6 mutantes mueren, incluido uno que escribe en el origen.

### Fase 3 — el puente se ejecuta de verdad en las pruebas (2026-08-16, `52415ae`)

`scripts/apps-script-simulado.mjs` monta los dobles de Hojas de Google, y
`puente-extremo-a-extremo.test.mjs` ejecuta `procesar()` entero. **Los dos `.gs` se
cargan JUNTOS en un mismo ámbito**, que es como los corre Apps Script — si dos
constantes chocaran, la prueba revienta igual que reventaría la hoja.

**El simulador es fiel donde el código se rompe, no en general:**
- `getRange` **LANZA** si se sale de la rejilla — el fallo exacto que mataba la quinta
  pasada llena. Un simulador permisivo lo habría escondido para siempre.
- `getDisplayValues` devuelve **siempre texto** (la diferencia entre leer `"00123456"` y
  leer el número `123456`).
- `getLastRow` mira contenido, no rejilla; los disparadores se cuentan de verdad.

**26 pruebas nuevas** — los 12 escenarios que faltaban y los del conector: inicialización
que importa cero y **no pisa una frontera ya puesta** · parada en seco sin marcas · camino
feliz entero (hoja + huella + marca) · **pestaña renombrada** (sigue, la memoria va por
sheetId) · pestaña nueva · encabezados cambiados · filas perdidas · filas reordenadas ·
dos corridas a la vez · fallo de escritura · el tope · el crecimiento de la hoja ·
`prepararHoja` / `activarConector` / `apagarConector` / `importarLeads` con y sin secreto.

**Dos correcciones que salieron de los mutantes:**
1. Una prueba mía **no probaba nada**: `gs.configurar && gs.configurar()` cortocircuitaba
   porque no había expuesto la función.
2. ⚠️ Un mutante que adelantaba la marca a antes de las huellas **SOBREVIVÍA, y tenía
   razón**: ese orden **no era load-bearing** como afirmaba mi comentario — si fallaran
   las huellas con la marca ya movida, los leads ya estarían escritos y el conector los
   subiría igual. Comentario corregido para no vender una defensa que no existe, y el
   orden pinchado con la prueba que sí dice algo cierto: **la marca es lo último que se
   mueve**, y si falla cualquiera de las escrituras de memoria, no avanza.

**Total: 36 puras + 26 de extremo a extremo**, todas dentro de `npm run check:scripts`
junto al gate.

### Fase 4 — cada 15 minutos sin gastar cuota, y un panel que diga si esto vive (2026-08-16, `2fe375c`)

**El problema de negocio:** con la corrida única de las 9 a. m., un lead que entraba a
las 9:05 esperaba casi 24 horas a que alguien lo llamara.

**Lo que impedía subir la frecuencia era el coste**, no el código: cada pasada se
descarga las ~12.000 filas × 11 columnas de cada pestaña del origen, y 96 de esas al
día se comen el tope diario de tiempo de disparadores de la cuenta — que además
comparte con el conector, que ya corre cada 5 minutos.

**El pre-chequeo.** Cada corrida pregunta primero cuántas filas tiene cada pestaña
(`getLastRow`: metadato, no descarga ni una celda) y termina ahí si nada creció. La
lectura completa se paga solo cuando hay algo nuevo. En las pruebas esto no es una
promesa de comentario: **el simulador cuenta las celdas descargadas** y la prueba
exige **cero**.

**El suelo diario.** «El mismo número de filas» NO prueba que nadie borrara una y
metiera otra en el mismo cuarto de hora, así que hay al menos **una lectura completa
al día**. Peor caso: lo que costaba el horario viejo. Mejor caso: un lead entra en 15
minutos. `decidirPasada` está escrita para **equivocarse hacia MIRAR** — pestaña sin
marca, filas que desaparecen, trabajo que dejó el tope a medias o diario ilegible
mandan leer entero, porque ahorrar una lectura nunca puede costar un lead.

**La ventana** (decisión de Miguel, 2026-08-16): **lunes a sábado, 7 a. m. – 10 p. m.
de Lima**; domingos no. El disparador de Apps Script no sabe de días ni de zonas, así
que decide la función; y **la hora se lee SOLO por `Utilities.formatDate` en la zona de
Lima** (heredar la zona del proyecto es correr de madrugada sin enterarse). El
simulador **lanza** si alguien pide otra zona. `instalarHorario` **migra**: se lleva los
seis disparadores semanales viejos y deja uno.

**La corrida automática ya NO lanza.** Con 96 corridas al día, una excepción no
controlada son 96 correos de fallo de Google: el aviso se vuelve ruido y el ruido se
ignora, que es la única forma de que un puente parado pase inadvertido semanas.
Ahora atrapa, anota y avisa **una vez al día**. A mano sigue lanzando en pantalla:
ahí hay alguien mirando.

**El panel** (menú → *Ver estado del puente*): qué está encendido, si a esta hora toca
correr, última corrida y última lectura completa, frontera de cada pestaña, **cuánto
lleva el origen sin recibir una fila** y cuántas filas de la hoja esperan al CRM.

**Los avisos, SIN CORREO** (decisión de Miguel el mismo día, revisando la fase): se
anotan en el diario y salen por dos vías que alguien mira — el panel, con los avisos
**arriba del todo**, y un **banner al ABRIR la hoja**, que es lo que se abre todos los
días. Tres: puente sin frontera · pestaña detenida · corrida fallida.

- Cada aviso guarda **desde cuándo** está activo, no cuántas veces se repitió:
  «parado desde el lunes a las 9:15» dice algo, «se avisó 96 veces» no dice nada.
- Y **se apaga solo** cuando el problema deja de existir. Un aviso que no se apaga
  miente igual que uno que nunca suena, y encima enseña a ignorar el panel.
- **El origen seco dejó de ser alerta**: es un dato del panel con los días contados.
  Como alarma sería un rojo permanente —lleva seco desde el 24-jul y es hoja ajena—,
  y a un rojo permanente no lo mira nadie.
- ⚠️ Con el `onOpen` **simple** el banner no está garantizado (corre sin
  autorización). Donde sí lo está es con el disparador **instalable** que crea
  `instalarMenu()`: ejecutarlo una vez es lo que lo convierte en canal fiable.
- ✅ **Sin `MailApp` el proyecto no pide NINGÚN permiso nuevo**, así que pegar los
  scripts ya no obliga a re-autorizar nada. Hay **prueba estructural** que falla si
  alguien vuelve a meter `MailApp`/`GmailApp`.

**El diario de a bordo vive en las Propiedades del script**, no en una pestaña (una
pestaña de más delante de LEADS pone al conector a importar cualquier cosa — ya pasó).
Y es **observabilidad, no memoria**: quién entra lo deciden la marca y las huellas, que
están en la hoja. Si el diario se pierde, se lee de más, nunca de menos.

**Dos cosas que salieron de mirar el propio diseño, no de las pruebas:**
- **Dos corridas solapadas no son un error**, es el candado trabajando: alertar de eso
  sería avisar de que las defensas funcionan, y a los tres días nadie mira las alertas.
- **Una pestaña detenida chocaría con su marca en CADA pre-chequeo** → 96 lecturas
  completas al día por una avería ya conocida. Se recuerda lo detenido… pero esa
  memoria es **de averías, no un «ya miré»**: una pestaña sana con trabajo a medias
  por el tope sigue disparando la lectura (hay prueba y mutante para ese matiz).

**Pruebas 62 → 95** (52 puras + 43 de extremo a extremo) y **21 mutantes muertos**.
Tres enseñaron algo:
1. Una pestaña **vacía** medía 1 fila con una vara y 0 con la otra → el pre-chequeo
   habría gritado «perdió filas» en cada corrida, para siempre.
2. Un puente parado **daba el día por leído** sin haber leído nada: no pierde leads,
   pero el panel mentía justo en lo único que el panel existe para decir.
3. ⚠️ La memoria de averías **debilitó una prueba que ya existía** (la de «una alerta
   al día» dejó de ejercitarse porque el atajo evitaba el segundo intento). Repinchada
   por una vía sin atajo. Misma lección que [[Cierre de mes]]: un arreglo puede tapar
   el test de otro.

### Documento para revisión externa (2026-08-16)

Miguel pidió el detalle técnico de las Fases 2 y 3 para un auditor suyo. Publicado como
artefacto privado (él decide si lo comparte): defectos corregidos uno a uno con su modo de
fallo, tabla de invariantes con dónde se imponen y cómo se comprueban, la tabla de los 15
mutantes **incluido el que sobrevivió**, y una sección explícita de lo que NO está cubierto.

https://claude.ai/code/artifact/3b3ed2d5-970d-4820-bd0a-59b9c5b54848

### ⛔ NO DESPLEGADO — qué falta

Nada de esto está pegado en Apps Script todavía. Por fases:

- **Fase 0 (de Miguel, manda sobre todo):** confirmar quién alimenta el origen, probar
  con una respuesta controlada que la campaña escribe fila, y decidir la vía si esa hoja
  ya no es la fuente oficial. **Sin agua, el resto es fontanería.**
- ~~**Fase 2 — capacidad**~~ ✅ **HECHA** (2026-08-16, commit `99d088d`) — ver abajo.
- ~~**Fase 3 — simulador de Hojas**~~ ✅ **HECHA** (2026-08-16, commit `52415ae`) — ver abajo.
- ~~**Fase 4 — cadencia y observabilidad**~~ ✅ **HECHA** (2026-08-16, commit `2fe375c`) — ver arriba.
- **Fase 5 — activación controlada:** exportar `_puente_huellas` **antes** de pegar nada
  (memoria irrecuperable) · pegar los dos archivos · **ejecutar `verEstado()` a mano y
  aceptar el permiso nuevo de correo** (si no, los disparadores fallan con
  "Authorization is required") · `prepararHoja()` · `inicializarMarcas()` y comprobar
  que importa cero · vista previa sin nada anterior al 17 · lead controlado extremo a
  extremo · encender el conector · y solo entonces *Activar horario del puente* (que de
  paso se lleva los seis disparadores viejos si quedara alguno). Rollback = apagar
  disparadores y restaurar scripts, **sin borrar** `_puente_huellas` ni `_puente_marcas`.


## 2026-08-16 — ENCENDIDO (Fase 5): lo medido en producción

Los scripts se pegaron por fin en Apps Script. Cifras reales de la hoja, no estimaciones:

| | |
|---|---|
| Filas del origen | `landing` **6.158** · `formulario` **5.973** (id de `landing` = **0**) |
| Fronteras puestas a mano | en esas mismas filas, el 16/08 a las 16:48 |
| Vista previa, filas leídas | **12.127** |
| **Leads utilizables** | **0** ✅ — la prueba de fuego |
| Frenados por el corte del 17-ago | **11.968** |
| Frenados por la marca de agua | **159** |

**Los 159 son la demostración de que la Fase 1 valía.** Es exactamente el número de leads
que el 27 de julio estaban presos en REVISAR por venir SIN fecha. Sin marca de agua habrían
entrado hoy al CRM con fecha de agosto, contando como leads del mes y falseando el divisor
de la conversión. Es el agujero que abrimos y cerramos, medido.

`landing` **no salió detenida**, lo que confirma que el `sheetId 0` funciona — un caso que
ninguna prueba ejercitaba y que sobrevivía **por casualidad** (el texto `"0"` es verdadero
en JavaScript; el número `0` no). Ahora tiene prueba y mutante.

### El fallo que solo apareció al abrir el panel de verdad

La primera lectura real del panel mostró:
`frontera en la 6158 (puesta el Sun Aug 16 2026 16:48:00 GMT-0500 (hora estándar de Perú))`.

Se escribe el texto `"16/08/2026 16:48"`, **Sheets lo reconoce como FECHA** y lo guarda como
fecha; `getValues` devuelve un objeto `Date`. Misma familia que la huella `"00123456"` que
volvía como el número `123456`. Y con una vuelta de tuerca que encontró la revisión:
**`String(fecha)` re-renderiza en la zona horaria del PROYECTO** de Apps Script — justo la
dependencia que `relojDeLima` existe para matar; con el proyecto en hora del Pacífico, una
frontera puesta a las 00:30 de Lima aparecería con la fecha del **día anterior**.

Arreglado con `forzarTexto()` (blindaje: toda la rejilla de las dos pestañas de memoria en
formato texto, cubriendo `getMaxRows()` porque `insertRowsAfter` hereda el formato de arriba)
y `momentoDeCelda()` (cura de lo ya guardado). De paso, la columna «Actualizado» deja de
sellarse con la hora de hoy en TODAS las filas: una pestaña detenida conserva su sello, que
es lo único que permite ver «esta pestaña lleva días sin mirarse».

⚠️ **El culpable de que ninguna prueba lo cazara era el SIMULADOR**: guardaba el texto tal
cual y lo devolvía idéntico, así que la ida y vuelta que rompe en producción salía verde.
Ahora imita a Sheets — interpreta lo que se le escribe y `getDisplayValues` lo MUESTRA con
el formato de la celda, que es justo lo que lo diferencia de `getValues`.

⚠️ **Y los dos arreglos se tapaban mutuamente**: con el blindaje puesto, la cura nunca se
ejercita; con la cura puesta, quitar el blindaje no se nota. **Los dos mutantes sobrevivían.**
Separados en dos pruebas: una mira el valor CRUDO de la celda, la otra parte de una pestaña
ya envenenada como la de producción. Tercera vez que aparece esta trampa en este proyecto
(ver [[Cierre de mes]]): **un arreglo puede tapar el test de otro**.

**Pruebas 95 → 101 · mutantes 21 → 25**, todos muertos.

### El barrido que lo encontró

Se lanzó un barrido multiagente sobre TODA la clase de fallo «un valor va a una celda y
vuelve deformado»: cuatro inventarios (uno por pestaña) y **tres escépticos independientes
por cada sospechoso**, cada uno con una lente distinta (tipos · configuración regional ·
ejemplo real del negocio). **42 candidatos juzgados, 1 defecto confirmado** — el de la fecha.
Los otros 41 tenían defensa: el formato texto de LEADS, la «h» de las huellas, o que nadie
vuelve a leer el valor.


### Codex contra seis afirmaciones: rompió cinco (2026-08-16, `8dcdf8e`)

Regla de Miguel reafirmada ese día: *«apóyate en Codex para avanzar siempre»*. En vez de
pedirle «revisa esto», se le dieron **seis afirmaciones concretas para REFUTAR**, con los
archivos y el estado real de producción. **Rompió cinco.** El método vale más que el
resultado: pedir refutación de afirmaciones nombradas encuentra lo que «¿ves algún
problema?» no encuentra.

| Lo que afirmé | Lo que encontró |
|---|---|
| Ningún lead se pierde | Límites conocidos confirmados (fila editada bajo la frontera) |
| La marca no avanza si algo falla | 🔴 **FALSO**: `guardarMarcas` iba ANTES de `escribirRechazos` |
| El puente no puede quedarse callado | 🔴 **FALSO**: renombrar las columnas de teléfono lo silencia |
| Los leads viejos no se cuelan | 🟠 una fecha imposible (`99/99/2026`) era salvoconducto |
| Nada se deforma al pasar por Sheets | 🟡 un nombre con `=` inicial se vuelve fórmula |
| Las pruebas prueban lo que dicen | 🟠 cuatro agujeros, uno en la regla más dura del proyecto |

**El peor: la pestaña muda.** El chequeo «¿hay columna de teléfono?» iba ANTES de
«¿sigue siendo la misma pestaña?». Si en el origen renombran esas dos columnas, el
puente se salta la pestaña **sin incidencia, sin aviso y apagando el aviso anterior**
—porque la pasada termina «sin incidencias»—. Los leads dejarían de llegar y el panel
diría que todo está bien: exactamente el fallo que el panel existe para hacer imposible.
Invertido el orden; una pestaña que *nunca* tuvo teléfonos se sigue saltando en silencio,
que es correcto porque no ha cambiado nada.

**El segundo: el lead que se evapora.** La marca se guardaba antes que REVISAR, bajo un
comentario mío que decía «REVISAR es cosmético». Era falso: si esa escritura falla con la
marca ya movida, la fila queda por debajo de la frontera y en la pasada siguiente es
historia. Ni en LEADS, ni en REVISAR, ni en ningún sitio. Ahora **la marca es lo último,
sin excepciones**.

**Y la memoria podía perderse entera:** `guardarMarcas` borraba y luego escribía. Si lo
segundo fallaba, quedaba vacía → el puente se planta (bien), pero al re-inicializar la
frontera se pone al final de hoy y **todo lo llegado entretanto se convierte en historia**.
Ahora es UNA sola escritura que cubre lo nuevo y lo sobrante.

**Lo que más duele, y también de Codex:** el arnés de mutantes vivía en una carpeta
temporal — el **mismo error que en julio** costó perder el arnés de 33 aserciones. Ahora
es **`npm run test:mutantes`**, dentro de `check:scripts`: **32 mutantes en 15 segundos**.
Sin poder re-ejecutarlo desde el repo, «N mutantes muertos» no era evidencia, era palabra.

⚠️ Y una prueba que no probaba lo que decía: **«el origen sigue siendo SOLO LECTURA»**
—la regla más dura del proyecto— solo buscaba llamadas que empezaran por `origen.`, y el
código recorre las pestañas en una variable llamada `pestana`. Un mutante que escribiera
en el documento ajeno **habría pasado**. Ahora prohíbe toda escritura dentro de las tres
funciones que abren el origen.

**Pruebas 62 → 107 · mutantes 32, todos muertos.**

### ✅ VIVO desde el 2026-08-16 (primera corrida: lunes 17 a las 7:00)

- Los dos `.gs` pegados, `instalarMenu()` ejecutado, hoja preparada.
- Fronteras puestas a mano: `landing` 6158 · `formulario` 5973.
- Vista previa **0 utilizables**, repetida después de todos los arreglos: idéntica.
- Lead canario probado de extremo a extremo (hoja → conector → CRM, teléfono normalizado
  solo, sin dueño; lo asignó una persona 14 min después desde el CRM) y **borrado**.
- `crm.leads` = **0**. Portal intacto: 385 contratos, 350 perfiles. **22 candados del CRM,
  ninguno caído.**
- **Horario ACTIVADO**: cada 15 min, lun–sáb 7–22 h de Lima.

⛔ **Lo único que falta no es técnico:** el origen no recibe una fila desde el 24-jul. El
puente funcionará perfectamente y traerá cero hasta que la campaña vuelva a escribir ahí.

## 2026-08-22 — “NO” deja de bloquear leads de la hoja

Decisión de Miguel: la respuesta `NO` en «¿Autorizó contacto?» no debe ocultar ni
bloquear al lead. El importador ahora siempre crea las filas de la hoja con
`no_contactar = false`; un `SI` explícito conserva `consentimiento_en` y su fuente,
mientras que `NO` o vacío simplemente no registran ese sello. También se eliminó la
herencia automática de un `no_contactar` histórico durante reingresos por la hoja.

- Edge `crm-importar-leads` **v12 desplegada** y activa.
- La función pura `interpretarAutorizacionContacto()` cubre SI/SÍ/S, NO/N, vacío e
  inválidos; 7 pruebas Deno y 54 pruebas de extremo a extremo de la hoja quedaron verdes.
- Los dos leads del 22-ago que tenían el valor anterior fueron corregidos en producción:
  Renato Constantino (`+51952949862`) y Maria Astocondor Fuertes (`+51962823210`).
  Verificación final: **29 LANDING de hoy, 29 visibles/repartibles, 0 bloqueados**.

## Relacionadas
[[CRM conexión a datos reales]] · [[Canales de origen de leads CRM]] · [[Distribución de leads por capital y trazabilidad CRM]] · [[Acceso y roles del CRM]] · [[Distribución de leads y base fría (plan revisado)]]
