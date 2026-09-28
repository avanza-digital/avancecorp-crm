# Corrección autorizada de «Otro»

`corregir-otros-confirmados.sql` contiene el mantenimiento DML del 28/09/2026.
No se ejecuta como migración ni forma parte del despliegue de la aplicación.
La corrección de siete casos ya fue aplicada a producción; no volver a correrla
como paso de instalación.

La transacción exige `REPEATABLE READ`, un actor de Gerencia activo y el
manifiesto privado en `crm.correccion_origen_plan`. El manifiesto contiene
`batch`, `periodo`, `motivo` y `filas`; cada fila incluye `lead_id`,
`fuente_tipo`, `fuente_id`, `vendedor_id`, `capital`, `moneda`, `nuevo` y
`evidencia`. `nuevo` admite `landing` o `formulario`; `evidencia` distingue
`confirmacion` de `asignacion_administrativa`. No versionar manifiestos con
datos de clientes. La autorización debe cubrir los casos y sus canales.

Solo cambia origen, nota explicativa y fecha de actualización del lead;
los triggers existentes sincronizan las acreditaciones abiertas. La auditoría
conserva el canal anterior, evidencia, motivo, actor y lote. Las huellas de
tablas financieras, episodios y fotos se verifican antes y después; una
divergencia aborta todo el lote. Una repetición del mismo lote no duplica notas.

## Banco local

El banco Docker exclusivo `ranking_origen_correccion_20260928` se clonó de
`conversion_tipos_v3_20260927`, que contiene solo datos ficticios del banco de
conversión (incluidos `BANCO-A1` y `BANCO CLIENTE A UNO`). Requiere el esquema
vigente y esos fixtures; no usar una copia de clientes de producción.

En el contenedor `supabase_db_crm-avance-corp-local`, crear una copia exclusiva
del banco ficticio antes de cargar la semilla. La semilla comprueba el nombre
de esa base y usa `session_replication_role=replica` solo al preparar fixtures;
los ensayos de corrección corren con todos los triggers activos.

Desde la raíz del repositorio, cargar la semilla una sola vez en la copia:

```sh
node CRM-Avance-Corp/supabase/scripts/ranking-origen/prueba-corregir-otros-confirmados.mjs --seed
```

Ejecutar los ensayos:

```sh
node CRM-Avance-Corp/supabase/scripts/ranking-origen/prueba-corregir-otros-confirmados.mjs
```

Comprueban siete reclasificaciones, sincronización de acreditaciones,
distinción de notas, idempotencia y rechazo de importe divergente, actor sin
Gerencia, duplicados, falta de motivo y mes sellado. Cada ensayo termina con
ROLLBACK. El resumen se escribe en el directorio temporal del sistema como
`ranking-correccion-origen-pruebas.json`.

El acta de negocio y los límites pendientes están en
`BASE DE CONOCIMINETO/AVANCECORP/Ranking - correccion auditada de Otro (2026-09-28).md`.
