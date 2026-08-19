# Historial de derivaciones de Coordinación

La vista para el rol **Coordinador** debe mostrar el recorrido completo de una derivación, incluida la entrada desde la bandeja global hacia un supervisor y las reasignaciones posteriores.

La fuente de verdad es `crm.actividades` con `tipo = 'reasignacion'`, no solo `lead_asignaciones`: esta última no registra deliberadamente todos los ingresos a la bandeja de un supervisor.

El acceso se entrega mediante una RPC `security definer` y solo muestra información operativa: nombre, etapa, origen, monto, distrito, responsables anterior y nuevo, quién derivó y fecha. No expone teléfono, correo, DNI ni notas del lead.

Se desplegó a producción el 2026-08-19: migración registrada como `20260819212608` y pantalla publicada en `https://crm.miavance.com`.

## Panel de distribución y navegación compacta

La única vista disponible para el rol **Coordinador** es `Repartir leads`. Desde 2026-08-19 su primera pestaña es el **Panel de distribución**: muestra únicamente el número de leads activos por supervisor (bandeja propia + analistas a cargo) y por analista (asignación directa), sin desglose por etapa ni capacidad.

El panel filtra por supervisor, analista y origen. Sin filtro de origen incluye Referido, Walking (`oficina`) y todos los demás orígenes. La fuente prevista es `crm.panel_distribucion_reparto`, una RPC `security definer` gateada por `private.puede_operar_reparto_crm()` que devuelve solo nombres de responsables y conteos, nunca filas ni PII de leads.

Para evitar pantallas interminables, Cola se pagina de 20 en 20, Historial de 25 en 25 y cada tabla del Panel de 10 en 10. Los botones de “mostrar más” no acumulan resultados en el DOM: se navega con Anterior/Siguiente.

Se desplegó a producción el 2026-08-19: migración `20260819215033_crm_panel_distribucion_coordinacion` y release `crm-20260819T215140Z-3204aaac2910` publicado en `https://crm.miavance.com`. La RPC fue comprobada bajo una sesión simulada de Coordinación; entregó conteos sin PII y su ejecución permanece cerrada para `anon` y `public`.

## Agenda diaria de Landing y Formulario

Desde 2026-08-19, la cabecera de **Historial** incluye una agenda diaria para que Rosa programe únicamente los dos orígenes que se reparten por turno: **Landing** y **Formulario**. Los destinos habilitados son Carmen Jaramillo (alias «Carmen») y Jorge Marzano (alias «Jor»); ambos carriles deben tener supervisoras distintas.

La vista muestra la semana, permite elegir una fecha actual o futura, invertir el turno y guardar ambos carriles juntos. Cada carril presenta el número real de entradas a bandeja de ese origen durante el día; el listado inferior continúa siendo el historial granular y autoritativo de los movimientos.

La configuración vive en tablas privadas y solo se expone a Coordinación/Gerencia mediante `crm.agenda_reparto_diaria` y `crm.guardar_agenda_reparto_diaria`. No devuelve leads ni PII. La agenda anterior es inmutable, y el carril de hoy ya no puede cambiarse si registra derivaciones: el plan no se reescribe sobre la evidencia real. La migración de producción es `20260819220501_crm_agenda_reparto_diaria`.

Relacionado: [[Reparto de Leads]] y [[Seguridad RLS]].
