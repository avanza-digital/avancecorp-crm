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
  `crm-20260806T185215Z-a0ba40c3cad5`. Incluye el rango inicial mensual, los
  ajustes de robustez y el Centro de alertas gerenciales.
- SHA-256 del ZIP:
  `3c53cc5c7410ffac917d3dbdd242705205461433c8c6eed335b4b25ed14e5071`.
- Resultado final: 1,277 pruebas aprobadas, lint sin advertencias, tipos y build
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

## Centro de alertas gerenciales

- `#/alertas` es una página propia y exclusiva de Gerencia; también se abre
  desde la campana superior.
- Muestra siempre el mes en curso de `America/Lima`, aunque las demás vistas
  conserven un rango histórico personalizado.
- Incluye tareas vencidas, leads sin próxima acción, inasistencias, conversión
  individual por debajo de la meta y caída global contra el mes anterior
  comparable.
- Permite filtrar por prioridad y tipo, buscar responsable o equipo y abrir el
  módulo gerencial relacionado. Funciona con cualquier cantidad de vendedores.
- Un error parcial se comunica como información incompleta; una fuente ausente
  nunca se interpreta como cero o cumplimiento.
- Usa métricas agregadas existentes y no descarga los leads, tareas o
  actividades que originaron la señal. Un desglose de casos individuales
  requeriría una RPC mínima y protegida en una fase posterior.
- Relacionado con [[Bienvenido]] y [[Deploy a Hostinger]].
