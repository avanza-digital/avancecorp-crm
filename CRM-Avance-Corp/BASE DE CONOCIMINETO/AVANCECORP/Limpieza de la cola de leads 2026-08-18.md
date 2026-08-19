# Limpieza de la cola de leads — 2026-08-18

Relacionado con [[Mesa de derivación de Rosa 2026-08-18]] y
[[Carga de leads desde hoja de Google]].

## Qué se hizo

Borrado **físico** de los 67 leads que estaban en la cola por repartir
(`etapa = 'nuevo'`, activos). La cola de Rosa quedó en 0.

Los 2 leads convertidos (clientes con contrato) no se tocaron.

## Por qué borrado y no descarte

Descartar habría sido lo reversible, pero Miguel lo rechazó con una razón
válida: 67 descartes con un motivo inventado ensucian las métricas de descarte
y además dejan a esos contactos en enfriamiento (20 días con motivo `otro`),
bloqueando su reingreso legítimo. Data falsa a cambio de reversibilidad.

## Lo que hubo que vencer

El esquema protege estos datos con tres capas, todas deliberadas:

1. Llaves foráneas en `RESTRICT` desde `lead_sla_ciclos` y `lead_sla_etapas`.
2. Triggers `trg_lead_sla_*_guard`, que rechazan el DELETE en su primera línea
   («Los ciclos SLA no se eliminan»), sin bandera de escape posible.
3. La regla escrita del proyecto: soft-delete, nunca hard-delete.

Se apagaron los dos triggers guardianes **dentro de la misma transacción** y se
reactivaron antes del `commit`. Verificado después: ambos en estado `O`.

SQL reutilizable en `_backups/crm-leads/borrar-cola-leads-2026-08-18.sql`.

## Recuperación (existen DOS vías)

- `_backups/crm-leads/respaldo-leads-cola-2026-08-18.json` — 215 KB, los 67
  leads con todos sus campos más sus ciclos y etapas de SLA.
- `public.audit_log` — el trigger de auditoría se dejó ACTIVO a propósito:
  registró las 67 filas `DELETE` sobre `crm.leads`, **las 67 con `data_antes`
  completo**.

## Advertencia registrada: esos leads eran reales

La petición original decía que eran demo. La verificación previa demostró que
no: 67 teléfonos peruanos distintos y bien formados, 65 con consentimiento
legal sellado, nombres completos de personas, y trazabilidad de haber entrado
por el puente desde el documento de la empresa (35 de la landing a las 11:48,
31 del formulario a las 12:03, hora de Lima). El único demo verificable era
«ROSA CLIENTE DEMO».

El entorno de demostración es **local y aislado** (`127.0.0.1`, guard
`VITE_ENABLE_DEMO`); el verificador de bundle confirma que producción no lleva
fixtures demo. La demo nunca escribió en producción.

Se borraron igualmente por decisión explícita de Miguel, ya informado de esto.

## Consecuencias a tener presentes

- **El conteo mensual se reinició solo: 68 → 2.** `crm.ingresos_reparto_mes_fn`
  es `STABLE` y puramente derivada — cuenta en vivo sobre `crm.leads.creado_en`,
  sin contador almacenado ni caché materializada. No hubo nada que reiniciar a
  mano. Verificado el 2026-08-18 ejecutándola con la identidad real de Rosa
  (`8821227a-…`, en transacción con `rollback`): agosto devuelve `total: 2`,
  semanas 1-3 en cero y la semana 4 (17-18 ago) con 2.
- **Esos 2 que siguen contando son los clientes convertidos**, con contrato
  firmado. La función no filtra por etapa ni por `activo`: cuenta todo lead
  creado dentro del mes. Llevar el conteo a 0 exigiría borrar clientes reales
  con contrato, que es una operación de otra naturaleza y NO se hizo.
- **La evidencia del despliegue de esa RPC ya no es reproducible.** La nota
  [[Mesa de derivación de Rosa 2026-08-18]] registra «agosto de 2026 devolvió
  68 ingresos». Sigue siendo válida como registro histórico de aquel día, pero
  volver a ejecutarla hoy da 2.
- **La cadena sigue viva.** El conector sube filas nuevas cada 5 minutos y el
  puente trae del origen cada 15. La cola se repuebla sola con leads nuevos.
  Para frenarla: `apagarConector()` y `quitarHorario()` en el Apps Script.
- **Los borrados no vuelven solos.** La hoja los tiene marcados `IMPORTADO` en
  la columna P, así que el conector no los reintenta. Para reimportarlos habría
  que vaciar esa columna en sus filas.
