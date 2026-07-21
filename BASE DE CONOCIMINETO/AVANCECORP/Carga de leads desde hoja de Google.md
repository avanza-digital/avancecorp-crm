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

## Relacionadas
[[CRM conexión a datos reales]] · [[Canales de origen de leads CRM]] · [[Distribución de leads por capital y trazabilidad CRM]] · [[Acceso y roles del CRM]]
