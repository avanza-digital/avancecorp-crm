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

## Lo que falta ANTES de implementar

- Confirmar la CADENA con Miguel (¿el upgrade cambia `asesor_perfil_id` del cliente, o solo la
  atribución de esa línea y sus descendientes? ¿cómo se identifica «la renovación DE ese upgrade»
  — por `origen_id`/cadena de contratos?).
- Escribir el contrato técnico (como el de capital F4 / el de leads-y-citas F6).
- Implementar con oráculo de paridad (nadie más cambia de dueño) + auditor RLS + Codex.

Relacionado: [[fase-3-analista-que-cierra]] · [[El núcleo de capital]] ·
[[PLAN MAESTRO del servidor (P-055) - de la deuda a la capa semantica]]
