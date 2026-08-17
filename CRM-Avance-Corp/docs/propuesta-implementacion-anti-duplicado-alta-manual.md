# Propuesta de implementación: anti-duplicado en alta manual de lead

## Objetivo
Evitar duplicados en **alta manual** de un mismo lead cuando reaparece por más de **15 días sin actividad válida**:
- no crear un nuevo lead,
- **reutilizar** el lead existente,
- dejar el lead disponible para el analista actual,
- conservar trazabilidad del propietario anterior y fecha de vencimiento,
- y mostrar contexto de disponibilidad en la UI.

> Enfoque: aplicar la regla en el flujo de alta manual existente, reutilizando la lógica actual de
> `verificar_disponibilidad_lead`, `crear_lead_si_disponible`, estado `en_bolsa`/`enfriamiento` y migraciones de creación atómica.

---

## Alcance (y fuera de alcance)

### Alcance
- **Solo** alta manual de lead desde `LeadNuevo`.
- Unificar comportamiento para llamadas al RPC de creación atómica.
- Mantener semántica actual de deduplicado, gating de alcance y trazabilidad de auditoría.

### Fuera de alcance (hoy)
- Reparto masivo / rehomologación global de leads.
- Cambios estructurales a la política de cola o distribución automática.
- Reescritura completa de deduplicación (sin tocar el resto de flows).

---

## Estado actual resumido

- Existe precheck de disponibilidad en frontend y backend.
- El RPC atómico ya centraliza reglas de creación (`crear_lead_si_disponible`).
- El estado del lead maneja `libre`, `tomado`, `en_bolsa`, `enfriamiento`, etc.
- `LeadNuevo` ya conserva formulario si la RPC bloquea tras precheck.
- Ya hay guardado de actividad/seguimiento que permite reconstruir quién poseía el lead previamente.

---

## Diseño objetivo (alto nivel)

1. **Detectar disponibilidad “reutilizable”** cuando el contacto existe y su última actividad válida está vencida (>15 días).
2. **Resolver en backend atómicamente**:
   - Si estado = `libre` -> insertar lead nuevo (camino actual).
   - Si estado = `reutilizable_por_inactividad` -> actualizar lead existente dentro de la misma transacción.
3. **Devolver contexto al frontend** (`lead_id`, `estado`, `owner_anterior`, `disponible_desde`, `fecha_ultimo_contacto`).
4. **Actualizar UX** para mostrar contexto y continuar flujo sin bloquear en ese caso.
5. **No duplicar**: si reutilizamos, el ID retornado por RPC debe representar ese lead reutilizado.

---

## Fase 1 — Contrato y tipos (pre-cambios)

### 1.1 Definir nuevo estado en contrato de disponibilidad
- Extender `DisponibilidadLead` para incluir estado reutilizable por inactividad (ej. `reutilizable_por_inactividad`).
- Incluir campos de contexto:
  - `lead_id` (opcional en disponibilidad, requerido al reutilizar),
  - `propietario_anterior` / `propietario_anterior_id`,
  - `fecha_ultimo_contacto`,
  - `disponible_desde`.

### 1.2 Normalizar presentación
- `presentarDisponibilidadLead(...)` debe:
  - Mostrar mensaje **informativo** (no bloqueante) con nombre de asesor previo y fecha límite,
  - NO exponer campos internos de RPC.

### 1.3 Extender contrato de creación atómica
- `ResultadoCreacionLeadAtomica` incluir:
  - `estado: 'creado' | 'reutilizado' | ...`.
- Mantener códigos de rechazo existentes (`CONTACTO_NO_DISPONIBLE`, etc.).

**Criterio de aceptación Fase 1**
- Tests de unidad en `disponibilidad-lead.test.ts` cubren:
  - mensaje de reusable con asesor y fecha.
  - no hay bloqueo UI para este estado.

---

## Fase 2 — Backend DB: verificar + reutilizar

### 2.1 SQL: verificación de disponibilidad
En la función central de verificación (RPC/helper):
- Buscar coincidencia del contacto con alcance activo.
- Calcular fecha de “última interacción válida”.
- Comparar antigüedad con umbral **15 días**.
- Devolver estado:
  - `tomado`/`en_bolsa`/`enfriamiento` según corresponda,
  - `reutilizable_por_inactividad` cuando corresponda el reaprovechamiento.

### 2.2 SQL: creación atómica
- En `crm.crear_lead_si_disponible(...)`:
  - si `verificar` retorna `reutilizable_por_inactividad`, ejecutar reutilización atómica:
    - reasignar `vendedor_id` y/o estados necesarios,
    - registrar actividad de trazabilidad (`lead_reutilizado_por_inactividad` o equivalente),
    - guardar owner previo + fecha de expiración en metadata de actividad,
    - retornar `estado: 'reutilizado'` con `lead_id` existente.
- Si el lead estaba “bloqueado” sin reutilización, seguir retornando rechazo.

### 2.3 Validaciones de integridad
- Reforzar condiciones `WHERE` por ámbito y estado de cierre para no tocar leads cerrados.
- Mantener las barreras de dedup existentes para evitar regresiones.

**Criterio de aceptación Fase 2**
- RPC reutilizable devuelve consistentemente `lead_id` existente y estado `reutilizado`.
- No se crean filas nuevas en condición reutilizable.

---

## Fase 3 — API y Store (integración cliente-servidor)

### 3.1 `app/src/data/crm-api.ts`
- Mapear nuevo estado en tipado/parseo.
- Al recibir `{ estado: 'reutilizado', lead_id }` devolver objeto exitoso al store.

### 3.2 `app/src/lib/store.tsx`
En `crearLead(...)`:
- Hoy se trata como éxito solo `estado !== 'creado'` => error.
- Cambiar para aceptar ambos estados:
  - `'creado'`
  - `'reutilizado'`.
- Cuando `lead_id` cambie del optimista:
  - reconciliar local: reemplazar id temporal por real o re-sincronizar ese registro.
- Mantener revert/rechazo si llega bloqueo (`CONTACTO_NO_DISPONIBLE`, etc.).

### 3.3 Comprobación de trazabilidad local
- Si la API trae contexto de reutilización, guardar en estado local (para notificación y toast/alert). 

**Criterio de aceptación Fase 3**
- La acción de `crearLead` no genera duplicado visual ni toast de error en estado `reutilizado`.
- El lead mostrado en pantalla coincide con `lead_id` devuelto.

---

## Fase 4 — UX en alta manual (`LeadNuevo`)

### 4.1 Precheck con contexto de reutilización
- En precheck, cuando la respuesta sea `reutilizable_por_inactividad`:
  - mostrar aviso amarillo/azul (no rojo)
  - mensaje sugerido:
    - “Lead en recuperación por inactividad. Último owner: `<asesor>`.
      Estará disponible desde `<fecha>` por regla de 15 días.”

### 4.2 Flujo de envío
- Mantener envío habilitado.
- En caso de error de RPC definitivo, conservar formulario (comportamiento actual).
- Si persistencia termina en éxito reutilizable:
  - abrir lead reutilizado (`lead_id` real).

**Criterio de aceptación Fase 4**
- Usuario ve contexto antes de guardar.
- El alta manual continúa si estado reutilizable.

---

## Fase 5 — Pruebas (mínimo viable)

### Unitarias / contrato
1. `app/src/lib/disponibilidad-lead.test.ts`
   - mensaje de estado reutilizable y campos sanitizados.

### API / servicio
2. `app/src/data/crm-api-disponibilidad-msw.test.ts`
   - mock de `disponibilidad` con estado reutilizable.
   - mock de `crear_lead_si_disponible` retornando `reutilizado`.

### Store
3. `app/src/lib/store-real.test.tsx`
   - precheck ok + persistencia devuelve `reutilizado` -> no revert
   - validación que no muestra error de `CONTACTO_NO_DISPONIBLE`.

### UI
4. `app/src/components/app/lead-nuevo.test.tsx`
   - muestra aviso de recuperación por inactividad,
   - botón “Crear lead” sigue habilitado,
   - tras persistencia abre `lead_id` reutilizado.

### SQL/integración
5. Ejecutar pruebas de base si existen (o scripts de migración) y validar función de RPC con casos:
   - contacto inexistente => libre,
   - contacto bloqueado < 15 días => bloqueo,
   - contacto sin actividad 15+ días => reutilizable,
   - contacto en enfriamiento => bloqueo.

---

## Fase 6 — Despliegue seguro y validación

1. Aplicar migración SQL (backend).
2. Ejecutar suite relevante de tests.
3. Smoke manual:
   - alta manual con lead inexistente (crea nuevo),
   - lead vigente (debe bloquearse con contexto correcto),
   - lead vencido por actividad (debe reutilizarse sin duplicado),
   - comprobar que en timeline/actividad quedó traza del reciclaje.
4. Revisar que no se rompe regla previa de “no crear duplicado si recupera en ventana de enfriamiento/vencimiento”.

---

## Orden recomendado de implementación (sin riesgo)

1) **DB**: contrato de verificación y reutilización atómica en RPC.
2) **Tipos/API**: `crm-api.ts` y `disponibilidad-lead.ts`.
3) **Store**: aceptar `estado: 'reutilizado'` como éxito.
4) **UI**: mensaje informativo + continuidad en envío.
5) **Tests**: contrato + store + UI + migración.
6) **Smoke y merge**.

---

## Riesgos y mitigaciones

- **Falso positivo por datos duplicados de contacto**
  - Mitigación: usar la política de dedup actual (telefono/DNI con limpieza normalizada).
- **Ambigüedad de “actividad válida”**
  - Mitigación: definir explícitamente tipos permitidos en nota/actividad en esa regla.
- **Races de concurrencia**
  - Mitigación: ejecución atómica en RPC + transacción/locks que ya usa `crear_lead_si_disponible`.
- **Compatibilidad con flujo de auditoría**
  - Mitigación: actividad de reutilización explícita y campos de contexto en el payload.

---

## Decisiones de implementación a documentar antes de código

- Definir si 15 días se toma sobre `actualizado_en`, `ultima_actividad`, o `creado_en` cuando no haya actividad.
- Definir lista de tipos de actividad “válidos para refrescar cooldown”.
- Decidir nombre final del estado/reason (`reutilizable_por_inactividad`) para no romper traducciones ni logs existentes.
- Confirmar copy final del mensaje en UI.

---

## Resultado esperado

Con este plan, la alta manual deja de generar duplicados en reaparición tardía de un lead:
- respeta la política actual de enfriamiento,
- reutiliza lead con trazabilidad completa,
- no rompe flujo de precheck/rollback existente,
- mantiene UX clara para el usuario.

---

### Entregables recomendados

- `docs/propuesta-implementacion-anti-duplicado-alta-manual.md` (este documento)
- Migración SQL (reutilización)
- Cambios mínimos en:
  - `app/src/lib/disponibilidad-lead.ts`
  - `app/src/data/crm-api.ts`
  - `app/src/lib/store.tsx`
  - `app/src/components/app/lead-nuevo.tsx`
  - pruebas relacionadas
