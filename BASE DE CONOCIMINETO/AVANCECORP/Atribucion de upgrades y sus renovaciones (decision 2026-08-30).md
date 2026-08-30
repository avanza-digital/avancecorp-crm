# Atribución de upgrades y sus renovaciones — decisión de Miguel (2026-08-30)

Decisión de negocio tomada mientras se cerraba la Fase 5.c. **Pendiente de escribir el
contrato técnico y de implementar con su propia auditoría** — NO va dentro de la F5.c
(que es «quién puede registrar»), esto es «a quién le cuenta».

## La regla (a confirmar la cadena con Miguel antes de codear)

1. **Venta nueva** → cuenta a **quien la registra** (ya es así: `analista_cierre` = quien digita).
2. **Renovación de un cliente normal** → cuenta al **analista DUEÑO del cliente**
   (`asesor_perfil_id`), aunque otro la digite. (Ya es así.) — «las renovaciones sí de cada analista».
3. **🆕 Upgrade** → cuenta al **analista que lo HACE** (María), NO al dueño original del cliente.
   Hoy el sistema lo atribuye al dueño (`asesor_perfil_id`) igual que la renovación → **cambia**.
4. **🆕 La renovación de ESE upgrade** (cuando el upgrade vence y se renueva) → cuenta al
   **mismo analista que hizo el upgrade** (María), NO al dueño original. Es decir: hacer un
   upgrade «adopta» esa línea del cliente y sus renovaciones futuras.

## Dónde vive el cambio (medido el 30/08)

NO en `public.crear_contrato` (ahí `analista_cierre_id` ya es quien digita). La atribución de
producción de las operaciones de cartera (renovación/upgrade al dueño del cliente) vive en la
capa de métricas/cierre:
- `private.produccion_mes_por_vendedor` (menciona upgrade)
- `crm.metricas_cartera_fn` / `private.metricas_cartera_por_vendedor` (ops de cartera)
- `crm.cerrar_periodo` · `crm.cumplimiento_metas_sin_cartera_fn`

## ✅ Las preguntas quedaron respondidas (30/08 noche, 4 respuestas de Miguel)

1. Adopción por **LÍNEA** (el `asesor_perfil_id` del cliente NO cambia).
2. «Quien lo hace» = **el del selector** «Analista de la venta» (`analista_cierre_id`).
3. **Incluye agosto** (se re-atribuye por lectura antes del sello del 10/09).
4. El **Directorio del Portal se queda** con la regla vieja (dos podios, a propósito).

El contrato técnico está escrito: [[Contrato de la atribucion por cadena de upgrade (2026-08-30)]].
El plan de implementación va en 4 fases (F1 conversión/cartera + agosto · F2 capital por cadena,
tras el sello · F3 el formulario dice la verdad · F4 diferida: la sanción de anulación).

Relacionado: [[fase-3-analista-que-cierra]] · [[El núcleo de capital]] ·
[[PLAN MAESTRO del servidor (P-055) - de la deuda a la capa semantica]]
