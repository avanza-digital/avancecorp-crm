---
fecha: 2026-10-17
estado: candidata-local-sin-publicar
tags: [crm, citas, fecha-comercial, conversion, conciliacion]
---

# Citas — fecha comercial y carga tardía

Miguel confirmó que las ventas pertenecen al mes de su fecha comercial, aunque
se registren después. Esta decisión sustituye el uso del mes de carga para los
clientes de Citas descrito en las notas históricas. Las entrevistas conservan
su configuración; `mes_resultado=asignacion` no cambia el mes de las ventas.
La fecha de registro permanece en auditoría. No modificar contratos ni
acreditaciones para corregir una discrepancia de lectura.

El aviso de octubre no se resolvía sumando solo tres contratos: el censo completo
identificó 17 ventas comerciales de septiembre cargadas en octubre. Los contratos
001379, 001428 y 001481 tienen fecha comercial 05/09, 14/09 y 21/09/2026,
respectivamente. Registros en CRM: 06/10, 05/10 y 01/10.

Conciliación al 17/10/2026 05:06 UTC: septiembre 116 clientes, 10 vinculados sobre
62 personas entrevistadas (16,13 %); octubre 43 clientes, 15 sobre 79 (18,99 %).
Cada fila de analista coincide con SQL independiente. Son resultados al corte,
no valores que deban fijarse en el programa.

La implementación candidata obtiene la fecha del núcleo `conversion_cierres`.
La fecha comercial no tiene hora: una entrevista del mismo día local se considera
compatible y una posterior se excluye. Esto no prueba el orden dentro del día.
No se usa `convertido_en` como sustituto si falta una fecha acreditada.

Servidor aditivo: conserva campos/testigo anteriores; añade fecha comercial y
`testigo.comercial`. La nueva pantalla aplica la regla a totales, detalle,
recuperación, estados de cita, proyección, ayuda y CSV. El aviso indica diferencias
concretas junto al total y mantiene el bloqueo de indicadores/exportación incluso
al filtrar. Supervisión conserva solo su equipo, sin testigo global.

Trabajo en copia aislada autorizada `/private/tmp/crm-citas-fecha-comercial-20261017`;
no altera la carpeta original con tareas concurrentes. Candidata SQL
`20261017043000_crm_citas_fecha_comercial.sql`. Si coincide con la valoración por
operación, integrar e instalar esa tarea primero: su preflight espera aún la
huella anterior del lector. Compatibilidad probada localmente con cortes y
meses sellados; no se reabren ni reescriben sellos monetarios.

Evidencia y límites: `CRM-Avance-Corp/docs/plans/citas-fecha-comercial/RESULTADO.md`.
Sin aplicación en producción ni publicación. Gates remotos de publicación
pendientes; el censo analítico global conserva 11 incidencias previas ajenas,
sin ocultarlas ni añadir otras. No presentar la candidata como ya publicada.

Relacionadas: [[Citas Gerencia - reglas confirmadas y propuesta revisada 2026-09-13]],
[[Citas Gerencia - deposito acreditado por conversion a cliente 2026-09-08]],
[[Citas Gerencia - ticket con todo el capital del mes 2026-09-15]],
[[Citas Gerencia - Supervisión por equipo 2026-09-27]].
