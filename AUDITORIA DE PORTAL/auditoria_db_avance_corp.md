# AUDITORÍA DE BASE DE DATOS — PORTAL AVANCE CORP
## Resultado y correcciones pendientes
**Fecha:** Junio 2026 | **Supabase Project:** `dctqcbznekcyxhjujuci` | **Auditor:** Claude.ai

---

## CONTEXTO

Se realizó una auditoría completa de la base de datos de producción del Portal Avance Corp. Se revisaron: 9 tablas, 32 políticas RLS, 41 índices, 11 funciones custom, 21 triggers, 9 Edge Functions, políticas de Storage, integridad referencial y tamaños de tablas.

**Estado general: la base de datos está sana para producción.** Los hallazgos son mejoras de higiene que deben resolverse ANTES de registrar los ~1,000 clientes planificados.

---

## ESTADO ACTUAL DE DATOS (al momento de la auditoría)

| Tabla | Filas | Tamaño |
|---|---|---|
| audit_log | 11,798 | 6.9 MB |
| perfiles | 8 | 4.6 MB (inflado por índices trigram, se normaliza con más datos) |
| cronograma_pagos | 74 | 464 KB |
| suscripciones_push | 42 | 208 KB |
| contratos | 7 | 224 KB |
| novedades | 5 | 80 KB |
| novedades_leidas | 3 | 72 KB |
| documentos | 1 | 64 KB |
| asesores | 2 | 48 KB |

---

## HALLAZGO 1 — AUDIT_LOG INFLADO (Prioridad: ALTA)

### Problema
La tabla `audit_log` tiene 11,798 filas y es la más pesada (6.9 MB) para un sistema con solo 8 perfiles y 7 contratos reales. El volumen viene de ciclos de prueba masivos:

- cronograma_pagos: 3,991 DELETEs + 3,981 INSERTs
- perfiles: 1,524 DELETEs + 1,523 INSERTs  
- contratos: 324 DELETEs + 323 INSERTs

### Acción requerida
Limpiar registros de prueba. Conservar solo los registros posteriores al inicio de operación real.

### SQL sugerido
```sql
-- Opción A: Borrar todo (si aún no hay operación real)
TRUNCATE audit_log;

-- Opción B: Borrar solo lo anterior a una fecha de corte
-- Ajustar la fecha según cuándo empezó la operación real
DELETE FROM audit_log WHERE ts < '2026-05-25T00:00:00Z';
```

### Verificación
```sql
SELECT COUNT(*) as total, pg_size_pretty(pg_total_relation_size('audit_log')) as tamaño
FROM audit_log;
-- Esperado: total cercano a 0, tamaño < 100 KB
```

---

## HALLAZGO 2 — TRIGGER AUDIT EN CRONOGRAMA_PAGOS (Prioridad: ALTA)

### Problema
El trigger `trg_audit_cronograma` registra CADA INSERT, UPDATE y DELETE en `cronograma_pagos` hacia `audit_log`, incluyendo `to_jsonb(OLD)` y `to_jsonb(NEW)` completos.

Proyección con 1,000 clientes:
- ~1,000 contratos × ~15 cuotas = 15,000 filas en cronograma
- Cada registro de pago = 1 UPDATE → 1 fila en audit_log con JSON completo
- Cada generación de cronograma = 15 INSERTs → 15 filas en audit_log
- Resultado: audit_log crece más rápido que cualquier otra tabla

Esto contradice el principio de diseño del proyecto: "audit selectivo en tablas críticas, no en tablas operativas de alto volumen".

### Acción requerida
Eliminar el trigger de audit en `cronograma_pagos`. Mantener audit en `perfiles`, `contratos`, `asesores`, `novedades` y `documentos`.

### SQL sugerido
```sql
DROP TRIGGER IF EXISTS trg_audit_cronograma ON cronograma_pagos;
```

### Verificación
```sql
SELECT trigger_name, event_object_table
FROM information_schema.triggers
WHERE trigger_schema = 'public' AND event_object_table = 'cronograma_pagos';
-- Esperado: 0 filas con nombre trg_audit_cronograma (solo debe quedar vacío o triggers no-audit)
```

### Nota
Si en el futuro se necesita auditar pagos específicamente, se puede crear un trigger más selectivo que solo registre UPDATEs donde `estado` cambie a `'pagado'`, en vez de auditar toda operación.

---

## HALLAZGO 3 — COLUMNA `novedades.leido` REDUNDANTE (Prioridad: MEDIA)

### Problema
Existen dos mecanismos de lectura compitiendo:

1. `novedades.leido` — boolean en la tabla principal, solo puede rastrear UN lector
2. `novedades_leidas` — tabla junction con `novedad_id` + `usuario_id`, rastreo multi-usuario correcto

Con novedades dirigidas a todos los clientes (`destinatario_id IS NULL`), el boolean `leido` no puede representar el estado de lectura de 1,000 clientes diferentes. La tabla `novedades_leidas` es el patrón correcto.

### Acción requerida
1. Verificar que TODO el frontend (cliente y admin) lea estado de lectura desde `novedades_leidas`, NO desde `novedades.leido`.
2. Verificar que la policy RLS de UPDATE en `novedades` no se esté usando solo para marcar `leido = true`.
3. Una vez confirmado, eliminar la columna.

### Pasos
```
Paso 1: Buscar en TODOS los archivos JS/HTML del proyecto referencias a:
  - novedades.leido  
  - .update({ leido: true })
  - SET leido = true
  Si existen, migrarlas a usar novedades_leidas (INSERT en novedades_leidas en vez de UPDATE en novedades).

Paso 2: Solo después de confirmar que no hay dependencias frontend:
```
```sql
ALTER TABLE novedades DROP COLUMN leido;
```

### Verificación
```sql
SELECT column_name FROM information_schema.columns 
WHERE table_name = 'novedades' AND column_name = 'leido';
-- Esperado: 0 filas
```

---

## HALLAZGO 4 — POLÍTICAS RLS CON ROL `{public}` (Prioridad: MEDIA)

### Problema
Dos políticas en `perfiles` usan roles `{public}` en vez de `{authenticated}`:

1. `superadmin_elimina_perfiles` (DELETE) → roles: `{public}`
2. `admin_crea_perfiles` (INSERT) → roles: `{public}`

Ambas están protegidas internamente por `es_superadmin()` / `es_admin()` que requieren `auth.uid()`, así que un usuario anónimo no pasaría la condición. Pero por defensa en profundidad, un request no autenticado no debería ni siquiera evaluar la condición del `qual`.

### SQL sugerido
```sql
-- Corregir superadmin_elimina_perfiles
DROP POLICY IF EXISTS superadmin_elimina_perfiles ON perfiles;
CREATE POLICY superadmin_elimina_perfiles ON perfiles
  FOR DELETE TO authenticated
  USING (es_superadmin());

-- Corregir admin_crea_perfiles
-- Primero obtener la condición actual:
-- WITH CHECK: (es_superadmin() OR (es_admin() AND rol = 'cliente'))
DROP POLICY IF EXISTS admin_crea_perfiles ON perfiles;
CREATE POLICY admin_crea_perfiles ON perfiles
  FOR INSERT TO authenticated
  WITH CHECK (
    es_superadmin() 
    OR (es_admin() AND rol = 'cliente')
  );
```

### Verificación
```sql
SELECT policyname, roles 
FROM pg_policies 
WHERE tablename = 'perfiles' AND policyname IN ('superadmin_elimina_perfiles', 'admin_crea_perfiles');
-- Esperado: ambas con roles = {authenticated}
```

---

## HALLAZGO 5 — FALTA ÍNDICE `idx_cronograma_estado` (Prioridad: BAJA)

### Problema
El documento maestro de implementación especifica este índice pero no existe en la base de datos. Los índices presentes en `cronograma_pagos` son:
- `idx_cronograma_contrato` (contrato_id)
- `idx_cronograma_fecha` (fecha_programada)
- `idx_cronograma_registrado_por` (registrado_por)

Falta: `idx_cronograma_estado` (estado)

Con 15,000 cuotas y filtros frecuentes por estado ('pendiente', 'pagado', 'vencido') desde el panel admin, este índice mejora performance.

### SQL sugerido
```sql
CREATE INDEX idx_cronograma_estado ON cronograma_pagos(estado);
```

### Verificación
```sql
SELECT indexname FROM pg_indexes 
WHERE tablename = 'cronograma_pagos' AND indexname = 'idx_cronograma_estado';
-- Esperado: 1 fila
```

---

## HALLAZGO 6 — FALTA TRIGGER `set_actualizado_en` EN `suscripciones_push` (Prioridad: BAJA)

### Problema
La tabla `suscripciones_push` tiene columna `actualizado_en` pero NO tiene el trigger `set_actualizado_en` que sí tienen `perfiles`, `contratos` y `asesores`. Cuando un cliente actualiza su suscripción push, `actualizado_en` se queda con el valor del INSERT original.

### SQL sugerido
```sql
CREATE TRIGGER trg_suscripciones_push_actualizado_en
  BEFORE UPDATE ON suscripciones_push
  FOR EACH ROW
  EXECUTE FUNCTION set_actualizado_en();
```

### Verificación
```sql
SELECT trigger_name FROM information_schema.triggers 
WHERE event_object_table = 'suscripciones_push' AND trigger_name LIKE '%actualizado%';
-- Esperado: 1 fila
```

---

## HALLAZGO 7 — RUTA DE STORAGE DIVERGE DEL DOCUMENTO (Prioridad: INFORMATIVO)

### Problema
El documento maestro especifica la ruta de storage como:
```
{cliente_id}/{contrato_id}/{nombre_archivo}.pdf
```

La implementación real usa:
```
{contrato_id}/{nombre_archivo}.pdf
```

La policy RLS `cliente_descarga_sus_docs` valida correctamente:
```sql
contratos.id = (storage.foldername(objects.name))[1]::uuid
AND contratos.cliente_id = auth.uid()
```

**Funciona bien.** Solo es una divergencia documental.

### Acción requerida
No requiere cambio en código ni en DB. Solo actualizar el documento maestro de implementación para reflejar la ruta real: `{contrato_id}/{filename}`.

---

## RESUMEN DE ACCIONES

| # | Hallazgo | Prioridad | Tipo de fix |
|---|---|---|---|
| 1 | Limpiar audit_log | ALTA | SQL (TRUNCATE o DELETE) |
| 2 | Quitar trigger audit en cronograma_pagos | ALTA | SQL (DROP TRIGGER) |
| 3 | Eliminar columna novedades.leido | MEDIA | Frontend + SQL |
| 4 | Cambiar roles {public} → {authenticated} en 2 policies | MEDIA | SQL (DROP + CREATE POLICY) |
| 5 | Crear índice idx_cronograma_estado | BAJA | SQL (CREATE INDEX) |
| 6 | Crear trigger actualizado_en en suscripciones_push | BAJA | SQL (CREATE TRIGGER) |
| 7 | Actualizar documentación de ruta Storage | INFO | Solo documentación |

### Orden de ejecución recomendado
1. Hallazgo 3 primero (requiere revisar frontend antes de tocar DB)
2. Hallazgos 1, 2, 4, 5, 6 juntos (puro SQL, sin dependencias frontend)
3. Hallazgo 7 al final (solo documentación)

---

## LO QUE ESTÁ BIEN (no tocar)

- ✅ Integridad referencial: 0 huérfanos en toda la base
- ✅ CHECK constraints en todas las columnas con valores enumerados
- ✅ Índices trigram (gin_trgm_ops) en perfiles para búsqueda fuzzy
- ✅ Índice parcial inteligente: `idx_contratos_estado_venc`
- ✅ Unique constraints: `numero_contrato`, `dni`, `correo`, `whatsapp`
- ✅ Unique compuesto: `suscripciones_push(cliente_id, endpoint)` y `novedades_leidas(novedad_id, usuario_id)`
- ✅ Funciones `es_admin()` y `es_superadmin()` validan `activo = true`
- ✅ 9 Edge Functions activas y funcionales
- ✅ `notificar-pagos` con `verify_jwt: false` (correcto para cron) + protección via `verificar_cron_secret`
- ✅ Storage policies correctas para documentos y comunicados
- ✅ Triggers `set_actualizado_en` en perfiles, contratos y asesores

---

*Auditoría realizada: Junio 2026 — Proyecto Supabase dctqcbznekcyxhjujuci*
