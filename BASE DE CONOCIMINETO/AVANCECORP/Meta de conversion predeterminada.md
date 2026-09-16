# Meta de conversión predeterminada

Relacionado con [[Bienvenido]].

- La meta de conversión se establece por vendedor y Gerencia puede editarla.
- Cuando un vendedor todavía no tiene una meta guardada, el CRM muestra `15%` como valor inicial.
- Los totales de supervisor y empresa incluyen ese `15%` para cada vendedor
  activo sin fila guardada; no se promedian únicamente las filas existentes.
- Una meta personalizada guardada siempre tiene prioridad sobre el valor inicial.
- Si la lectura de metas falla, el CRM muestra «No disponible» y ofrece
  reintentar; un error nunca se reemplaza por `15%`.
- La conversión significa clientes que invirtieron, identificados por un contrato formalizado.
- El detalle por vendedor muestra capital confirmado en PEN y USD por separado.

## Ranking gerencial

- La tarjeta «Mejores vendedores» del resumen es una vista previa y abre la
  página completa `#/ranking-vendedores`.
- La página no tiene un máximo fijo: carga a todos los vendedores activos,
  deja «Sin vendedor asignado» fuera de la competencia y coloca al final a
  quienes aún no tienen datos comparables.
- «Conversión general» ordena clientes sobre leads recibidos.
- «Meta de capital» ordena el porcentaje de capital confirmado en PEN sobre la
  meta individual en PEN. Muestra monto logrado, meta y avance; USD permanece
  visible aparte y no se suma ni se convierte.

## Período predeterminado de Gerencia

- Todas las vistas de Inteligencia Gerencial abren con el mes calendario en
  curso según `America/Lima`: desde el día 1 hasta hoy, inclusivos.
- La selección de otro rango solo entra en vigor al pulsar «Aplicar» y se envía
  a las consultas de conversiones, reuniones y distribución que alimentan los
  paneles y rankings.
- El rango aplicado persiste al navegar por Gerencia. Fechas futuras,
  invertidas o con más de 365 días de diferencia se bloquean antes de consultar.
- Al cruzar medianoche en Lima, el rango automático avanza al nuevo mes-a-la-fecha;
  un rango personalizado permanece intacto.
- Solo el MTD vigente se compara con la meta mensual. Para otros rangos se ven
  resultados sin porcentaje de cumplimiento ni prorrateo.
- Este valor inicial alinea la producción y la conversión mostradas con las
  metas mensuales. Los datos llamados «actuales» —por ejemplo capacidad, cola o
  cartera activa— siguen representando la fotografía operativa del momento.
- Relacionado con [[Bienvenido]].

## Producción

- Último frontend liberado el 2026-08-06 en `crm.miavance.com` con el release
  `crm-20260806T192701Z-567cb1fd5e22`. Incluye el rango inicial mensual, los
  ajustes de robustez y la bandeja de pendientes por responsabilidad. Reemplaza
  la primera propuesta gerencial `crm-20260806T185215Z-a0ba40c3cad5`.
- SHA-256 del ZIP:
  `91c40e97d6897262f408beb8cefaad5e88f3318bebc7b05b51aa6af033fcec2c`.
- Resultado final: 1,298 pruebas aprobadas, lint sin advertencias, tipos y build
  correctos.
- Relacionado con [[Deploy a Hostinger]] y [[Bienvenido]].

## Robustez desplegada

- El detalle, ranking y tendencia por vendedor consideran autoritativa la RPC:
  una respuesta ausente o parcial se marca como no disponible, nunca como cero.
- Gerencia inicia con roster y metas, sin descargar leads, tareas ni actividades
  operativas. Esto minimiza datos en el cliente, pero la frontera de seguridad
  sigue siendo RLS/RPC.
- El editor resincroniza los valores autoritativos después de un rollback.
- Esta etapa se liberó primero como `crm-20260806T183526Z-a0ba40c3cad5` y quedó
  incorporada en el release actual. El arnés SQL fue aprobado en PostgreSQL
  16.14 aislado; las migraciones ya estaban en producción y no se reaplicaron.

## Bandeja de pendientes por responsabilidad

- La primera página exclusiva de Gerencia se descartó porque mezclaba trabajo
  operativo con dirección y se comportaba como otro reporte.
- `#/alertas` pasa a ser una bandeja de condiciones activas para Vendedor,
  Supervisor y Gerencia. La campana es su acceso canónico; no aparece también
  en el menú lateral.
- El Vendedor recibe solamente sus tareas vencidas y sus leads que requieren
  respuesta o una próxima acción, con enlace al caso exacto.
- El Supervisor recibe únicamente excepciones escaladas: su bandeja por
  repartir, vencimientos de al menos 24 horas, colas críticas de al menos un día
  y acumulaciones relevantes de leads sin próxima acción por vendedor.
- Gerencia conserva solo desviaciones estratégicas de conversión: vendedor bajo
  meta desde el día 10 con al menos 10 leads y caída general contra el mes
  anterior comparable con al menos 30 leads en cada cohorte.
- Directorio y Coordinador quedan fuera mientras no exista una responsabilidad
  concreta que puedan resolver desde esta bandeja.
- No hay semántica leído/no leído: al corregirse el dato de origen, el pendiente
  desaparece. No se creó tabla, Realtime, RPC ni migración.
- No se generan alertas por inasistencia mientras el agregado no pueda excluir
  reuniones ya reprogramadas. El capital continúa como indicador en Meta y
  Producción hasta que exista una acción y un responsable inequívocos.
- Vendedor y Supervisor trabajan sobre su ámbito ya recortado por RLS; Gerencia
  usa solo métricas agregadas. Toda fuente ausente o inválida falla cerrada.
- Relacionado con [[Bienvenido]] y [[Deploy a Hostinger]].

## Continuidad

- Punto de reanudación: [[Continuidad CRM 2026-08-06]].
