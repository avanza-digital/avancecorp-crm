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
| ¿Autorizó contacto? | `no_contactar` (invertido) + `consentimiento_en` | SI/NO — capa legal "No Insista" |
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
  NO/N, o vacío (contactable sin consentimiento). Un typo tipo `N0`/`FALSE` ahora
  RECHAZA la fila en vez de fabricar `consentimiento_en`. `consentimiento_fuente`
  solo se guarda con un SÍ explícito.
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

## Puente desde el documento de origen (CONSTRUIDO 2026-07-22, sin instalar)

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
NO instalado todavía: falta que Miguel lo pegue y corra *Vista previa*.

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
sin celdas vacías. Es una columna obligatoria de la hoja, como Teléfono o Moneda — el
conector la necesita para poblar `no_contactar`, no es un añadido.

Codificado en `CONSENTIMIENTO_SI_NO_HAY_COLUMNA` + `FUENTE_POR_PESTANA` /
`FUENTE_POR_DEFECTO` (esta última aplica a toda pestaña sin entrada propia y su texto
nombra a Facebook: si el origen gana una pestaña nueva, añadirla al mapa).

## Relacionadas
[[CRM conexión a datos reales]] · [[Canales de origen de leads CRM]] · [[Distribución de leads por capital y trazabilidad CRM]] · [[Acceso y roles del CRM]] · [[Distribución de leads y base fría (plan revisado)]]
