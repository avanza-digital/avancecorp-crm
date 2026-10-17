---
fecha: 2026-10-17
estado: publicada-verificada
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

La implementación publicada obtiene la fecha del núcleo `conversion_cierres`.
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

Publicada el 17/10/2026: SQL por merge nativo 06:46 UTC, frontend fuente
`bc3c43034f20dc60eb5fa575c66b5c28e4a866ce`, build `build-20261017T064501541Z`.
ZIP `crm-20261017T064502Z-bc3c43034f20.zip`, SHA256
`fc86828104b1886cb7346b5866e9603fe29400260367dc892f28fcaf9c35f593`.
Conciliación de producción 06:47 UTC confirma los mismos valores Sep/Oct y
todas las filas. Chrome confirma ambos meses sin aviso y con exportación activa.
124 archivos HTTP/bytes PASS. Rama temporal de pago eliminada y ausencia verificada.
La integración preservó el TC por venta ya publicado y las 24 Edge intactas.
El censo analítico conserva sus incidencias previas sin ocultarlas ni añadir otras.
Acta vigente: `CRM-Avance-Corp/docs/plans/citas-fecha-comercial/PUBLICACION.md`;
la evidencia local histórica permanece en `RESULTADO.md`.

Relacionadas: [[Citas Gerencia - reglas confirmadas y propuesta revisada 2026-09-13]],
[[Citas Gerencia - deposito acreditado por conversion a cliente 2026-09-08]],
[[Citas Gerencia - ticket con todo el capital del mes 2026-09-15]],
[[Citas Gerencia - Supervisión por equipo 2026-09-27]].
