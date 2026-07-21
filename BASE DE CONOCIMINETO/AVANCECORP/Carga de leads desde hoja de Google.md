---
estado: ⏸️ EN PAUSA POR ROTACIÓN 2026-07-21 — edge v2 fail-closed; falta que Miguel pegue el secreto (2 pasos, ver §Rotación)
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

### Rotación 2026-07-21 — pasos de Miguel PENDIENTES (el conector queda caído hasta hacerlos)
1. **Dashboard de Supabase** → proyecto `dctqcbznekcyxhjujuci` → Edge Functions →
   Secrets → Add: clave `CRM_IMPORTAR_SECRET`, valor = el secreto nuevo (entregado
   en la sesión del 2026-07-21; NO se escribe aquí).
2. **La hoja** → Extensiones → Apps Script → ⚙️ Configuración del proyecto →
   Propiedades del script → Add: `IMPORTAR_SECRET` = el MISMO valor. Luego pegar el
   código actualizado de `CRM-Avance-Corp/scripts/hoja-leads-apps-script.gs`
   (reemplaza todo) y Guardar. El trigger de 5 min existente sigue sirviendo
   (no hace falta re-ejecutar `configurar()`).
Riesgo de la ventana caída: CERO hoy (crm.leads=0, sin leads reales fluyendo); si el
script corre antes de completar los pasos, pinta "ERROR temporal (401)" y reintenta solo.

**Rotaciones futuras** (sin redeploy): nuevo valor → actualizar el secret del dashboard
Y la propiedad del script. Nada más.

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
