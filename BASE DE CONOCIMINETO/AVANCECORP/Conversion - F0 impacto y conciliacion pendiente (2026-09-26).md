---
tags: [crm, conversion, diagnostico, conciliacion]
fecha: 2026-09-26
estado: diagnostico preliminar; regla temporal y conciliaciones aprobadas; sin cambios de producto
---

# Conversión — F0, impacto y conciliación

Continúa [[Conversion - fecha comercial y plazo de registro (propuesta 2026-09-26)]].
No es el objetivo de pagos. No se modificaron producción, contratos, inversiones,
capital, Cron ni fotos mensuales. Las consultas se ejecutaron en transacciones
de solo lectura. El diagnóstico no es una migración ni autoriza un despliegue.

## Decisiones ratificadas

- Cierre comercial determina el mes; confirmación y vínculo deben existir
  antes de las 00:00 del día 11 siguiente en Lima. Pendiente no reserva crédito.
- Vigencia desde septiembre de 2026, recalculando septiembre y conservando
  agosto y anteriores. Un registro tardío no se traslada a otro mes.
- Cuatro reemplazos por corrección confirmados por Miguel: Ricardo Cama,
  Mónica Vegas, Elia Palomino y Tracy Pacual. Preparar conciliación exacta de
  vínculos, una sola conversión por caso; no crear inversiones adicionales.
- Marco Antonio (Antonella): Miguel eligió pendiente sin crédito hasta acreditar
  una inversión. Hoy no se encontró fuente ni inversión de su identidad activa.
- Fidel Cuba: tras comparar ambos contratos, Miguel confirmó «conversión solo
  cuenta el de septiembre». Vincular el contrato 2026-01-001448 (S/20000), sin
  tocar el de mayo ni transformar ninguno en upgrade.

## Corte y simulación preliminar

Consulta inicial 26/09/2026 22:33 Lima. 133 episodios convertidos, 114 contratos
existentes candidatos y 33 cierres externos asociados. Cero meses sellados;
Cron de cierre apagado. Copia de trabajo aislada existente:
`/private/tmp/ranking-cartera.AfQUSa`, Main y remoto verificados en
`98be5666abc7b36652b838f00b09ee760c3633bf`. No mezclar con la raíz sucia.

| Mes actual del episodio | Mismo mes/a tiempo, provisional | Fuera de plazo, provisional | Sin fuente existente | Ambiguo | Anulado | Total |
|---|---:|---:|---:|---:|---:|---:|
| Agosto | 17 | 2 | 5 | 0 | 1 | 25 |
| Septiembre | 92 | 9 | 6 | 1 | 0 | 108 |

Agosto se inventarió, pero NO se propone recalcularlo. No se encontraron entradas
a otro mes dentro del plazo en esta simulación. Esta tabla NO prueba que todos
los vínculos estén acreditados: identifica candidatos para la conciliación.

Método diagnóstico: solicitud confirmada con inversión → actividad de conversión
con ID exacto → vínculo directo → candidato único del perfil excluyendo demo y
operaciones de cartera. El último paso es una HIPÓTESIS, no un permiso para
enlazar ni un resolver productivo aprobado. No escoger arbitrariamente entre
contratos de un perfil. La cota temporal usa como mínimo el resultado del
episodio, la creación de la fuente y evidencia explícita de vínculo disponible;
todavía falta completar la acreditación histórica de todos los enlaces legados.

De los 9 posibles tardíos de septiembre, 5 tienen solicitud confirmada exacta
y 4 dependen del candidato legado por perfil. No se debe presentar el impacto
como un recálculo final verificado ni tratar los 7 pendientes como tardíos.

| Analista | Posibles cierres fuera de plazo | Reducción ponderada simulada |
|---|---:|---:|
| Adelayda | 2 Landing | 2 |
| Fiorella | 1 Formulario | 1 |
| Astrid | 1 Formulario | 1 |
| Betzabeth | 1 Landing, 1 Formulario, 1 Referido | 2,15 |
| Kelly | 1 Formulario | 1 |
| Nayra | 1 Oficina | 0 en oficial; sí cambia canal |

Total simulado 7,15 de numerador, no puntos porcentuales. Divisores y aportes de
cartera se conservan. Betzabeth actualmente: divisor 71, numerador 5,9, tasa
8,31 %. No publicar un porcentaje futuro final mientras falte conciliar fuentes.

## Excepciones de septiembre

- Cuatro fuentes originales fueron realmente insertadas y luego eliminadas,
  según `public.audit_log`. Sus solicitudes quedaron canceladas y los leads
  conservan el ID eliminado; existen contratos vigentes de los mismos clientes.
  Miguel confirmó reemplazos. La reparación será trazable y separada del capital.
- Marco Antonio: sin inversión en la identidad activa y no fusionada; pendiente
  sin crédito por decisión expresa.
- Lead denominado `demo demo demo`: sin contrato/inversión encontrada. Su nombre
  no es por sí solo prueba de una bandera demo. Sin fuente no se inventa crédito.
- Fidel Cuba tiene dos contratos Avance distintos, ambos activos y `nuevo`, sin
  operación de cartera registrada para ninguno. Ambos fueron digitados el 21/09:

| Contrato | Capital | Inicio y cierre comercial | Registro |
|---|---:|---|---|
| 2026-01-000623 | S/50000 | 21/05/2026 | 21/09/2026 13:14 Lima |
| 2026-01-001448 | S/20000 | 17/09/2026 | 21/09/2026 13:15 Lima |

Son registros distintos. Miguel seleccionó expresamente el de septiembre como
fuente de la conversión. No se fusionaron, anularon ni reclasificaron. El de mayo
no obtiene crédito en septiembre. La conciliación exacta queda autorizada en
negocio y pendiente de migración/ensayo/SQL aprobado. No generalizar esta decisión
como autorización para seleccionar cualquier contrato reciente de un perfil.

## Inventario técnico y riesgos para F2

Núcleo actual `private.conversion_cierres`: mes del resultado del episodio, sin
comprobar operación confirmada/vinculada. Conserva al analista del episodio.
`private.conversion_episodios` agrega llegadas y cartera: no alterar esas ramas.

Consumidores encontrados: mensual/oficial → neta → Metas; Ranking por origen;
Conversiones/equipo, Distribución, reuniones/Citas, series, multiempresa y
resumen de cartera; cierre mensual, anulaciones/deuda y vigías. Inventario
lexical: 47 funciones candidatas (no es un grafo runtime definitivo: contiene
comentarios/autorreferencias que hay que filtrar). CodeGraph se consultó primero;
para SQL vivo insuficiente se complementó con catálogo y `pg_get_functiondef`.

Puntos concretos:

1. `private.registrar_ajuste_si_mes_cerrado` comprueba primero el mes de
   `leads.convertido_en` y puede retornar antes de resolver el mes del episodio.
   Con mes comercial diferente, debe resolver crédito/mes canónicos ANTES de
   comprobar el sello. Una conversión nunca abonada no genera deuda ficticia.
2. `crm.cerrar_periodo` ya usa candado global y mensual de
   `crm.periodos_cerrados`; no crear un cerrojo independiente. Corte/sello salen
   de una misma función temporal. Cron sigue apagado.
3. Cooperativas: capital lee imputación (o creación legada). Hoy las fechas
   comercial/imputación pobladas coinciden, pero el escritor puede separarlas
   al registrar sobre un mes sellado. No cambiar capital para igualar conversión.
4. Las confirmaciones modernas contienen solicitud/inversión/fuente exactas y
   reintento idempotente. El legado no siempre tiene esos enlaces. No usar un
   JOIN por cliente como prueba permanente de fecha de vínculo.
5. `RankingOrigenVendedorSchema` usa objetos estrictos en raíz y filas. Metas
   tiene antecedentes documentados de rotura por herencia de payloads. No añadir
   campos sin inspeccionar todos los envoltorios y sus validadores publicados.
6. La vigencia aprobada se aplica a eventos de septiembre en adelante: no debe
   reintroducir en agosto la conversión tardía de un contrato comercial de agosto.

Las decisiones humanas de F1 y de conciliación nominal están resueltas. Falta
completar la prueba técnica de enlaces legados y su reloj de vínculo. F2/F3 aún
no implementadas; no afirmar migración lista ni gates de producto aprobados.

## Evidencia y verificaciones

Directorio local privado: `/private/tmp/conversion-fecha-f0.ANVNe4`.
Contiene consultas reproducibles read-only, snapshot saneado sin credenciales,
definiciones vivas, simulación preliminar, auditoría y verificador de consistencia.
Los UUID técnicos permanecen en ese directorio, no en un artefacto público.

- Consultas de lectura: PASS (un intento de auditoría falló por comparar text
  con uuid; se corrigió el casteo, sin escrituras).
- `node /private/tmp/conversion-fecha-f0.ANVNe4/verificar-evidencia.mjs`: PASS.
  Comprueba 133 episodios, 108 de septiembre, fechas/cortes, ausencia de fuentes
  duplicadas entre los resueltos y conteos. NO valida un backend implementado.
- SQL/RLS/Auth, concurrencia, E2E y release del cambio: NOT RUN; aún no existe
  implementación y la conciliación indicada sigue pendiente.
- Revisión Claude de diseño ya recibida e incorporada en la nota principal;
  no se repitió para buscar conformidad. Diff implementado pendiente.

La guía Supabase mantuvo el trabajo en diagnóstico verificado y sin DDL sobre
producción. La aprobación de negocio no sustituye coste/ensayo/SQL exacto/release.
