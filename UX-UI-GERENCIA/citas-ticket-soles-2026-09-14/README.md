# Citas: ticket en soles y totales originales

PUBLICADO el 14/09/2026. Artefacto, reversa y comprobación HTTP en [PUBLICACION.md](PUBLICACION.md).

## Regla confirmada

Miguel pidió incluir cualquier moneda en el ticket, convertirla a soles y mantener visibles el total de soles y el total de dólares. El contrato de capital del CRM admite PEN y USD.

- Capital del mes: totales PEN y USD separados en una línea compacta, sujetos a la población y al analista/supervisor de la consulta. Se conservan en el detalle y el CSV.
- Ticket: `(capital PEN + capital USD × TC) / clientes únicos con capital comprobado`. Una identidad con ambas monedas o varios perfiles cuenta una sola vez.
- Fuente: capital real de contratos nuevos de las conversiones del mes; permanece el mes y analista del evento. Sin renovaciones ni montos estimados.
- Proyección: mismo ritmo y tasas del modelo publicado, ahora con ticket y capital unificados en PEN. El total suma las proyecciones individuales y distingue cuando es parcial.
- Cotización: servicio existente `crm-tipo-cambio`, con corte del día consultado o último día del mes cerrado. Es el promedio de las fechas disponibles dentro de la ventana del servicio; no se introduce un promedio mensual ni una tasa por contrato. Fuente y corte visibles.
- Sin TC válido: se mantienen las dos sumas originales y los indicadores de actividad; ticket/proyección que necesitan USD quedan pendientes, con reintento. No se divide un capital parcial PEN entre todos los clientes.
- Exportación: conserva las 18 columnas anteriores en orden, fija PEN para ticket/proyección y añade capital PEN/USD, tasa, fuente, corte y motivos cuando faltan importes.

## Verificación

- `npm run check`: PASS; 244 archivos / 3555 tests, lint, tipos, cobertura, release-config, worker, build, bundle y duplicación. Persisten advertencias de lint previas en componentes fuera del cambio.
- Unitarias focalizadas: PASS; 64 pruebas de avance, unificación y hook de cotización.
- E2E de Citas: 7 PASS finales con caché de Vite propia y dos workers. Hubo una aserción móvil incorrecta (el menú plegado conserva sus iconos) y una corrida con recargas repetidas antes del aislamiento de caché. Se corrigió la aserción según el comportamiento real; no se alteró el menú ni se ampliaron timeouts. Capturas de escritorio y móvil con menú plegado verificadas.
- HTTP real del servicio: 200 para ambos cortes, eco exacto de fecha, promedio positivo. Agosto 31: 3,3491 / 7 fechas. Septiembre 14: 3,362 / 1 fecha disponible (31 de agosto). La etiqueta `al` expresa el corte solicitado, no que exista una cotización de ese día.
- Catálogo productivo: `crm-tipo-cambio` ACTIVE v9, JWT verificado y paquete `694edeec8026de0839dabd1a8e0c85e281338b288c53c2a82bf9c5e9db75dce9`. No se modifica la Edge ni el esquema.
- Matriz RLS general: NOT RUN en este ajuste exclusivamente frontend; se conserva el antecedente de fallos de la publicación anterior, sin atribuirle PASS.
- `gate:realidad` CLI: NOT RUN; no hay `SUPABASE_SERVICE_ROLE_KEY` en el entorno local. La comprobación de la dependencia real de este cambio usa catálogo + HTTP y no solicita credenciales nuevas.
- Sesión de usuario real en producción: NOT RUN. Las pruebas de UI usan datos ficticios y Supabase de loopback.

## Revisión independiente y recuperación

Se recibió una revisión de Claude antes de la pausa, dictamen original CHANGES_REQUESTED sin P0/P1. Su archivo temporal ya no existe. Este registro reconstruye los hallazgos desde el contexto conservado; no es una transcripción ni una nueva revisión.

1. CSV sin motivo cuando falta TC: corregido con estados explícitos y prueba de descarga durante error.
2. Cambio de mes probado solo por solicitud: ahora se prueba retirada de tasa anterior, carga, nuevo importe/etiqueta y descarte de respuesta tardía en el hook.
3. Estado monetario incoherente: ticket, capital y proyección usan `Pendiente de TC` cuando corresponde.
4. Título del total parcial contradictorio: se aclara que suma únicamente analistas calculables.
5. Hipótesis de mes inválido: descartada por evidencia; `TableroCitas` evalúa `errorFiltros` antes de montar `Resultados`/`AvanceMensualCitas`.
6. Precisión de tasa: la Edge publicada redondea a cuatro decimales, coincidiendo con el rótulo; no se cambia la política compartida.

La nueva copia de trabajo persiste bajo `_dev_artifacts/citas-ticket-soles/repo`, ignorada por Git en la raíz. Implementación guardada en commit `78a9a77` antes de preparar la publicación. Se preservan los archivos ajenos de recuperación de terminales y evidencia F7.
