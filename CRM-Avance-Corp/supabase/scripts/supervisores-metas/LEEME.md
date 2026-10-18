# Ensayo de ventas propias de supervisores

Migración: `20261016162937_crm_supervisores_ventas_equipo.sql`.
Estado: probada localmente y en la rama cloud autorizada; promovida a producción
el 16/10/2026, frontend publicado y rama eliminada.
[Acta productiva](../../../docs/plans/supervisores-metas/PUBLICACION.md).

## Banco y ejecución

Base exclusiva `supervisores_metas_20261016`, creada desde la plantilla vacía
`coordinacion_f3_20261015` en el contenedor local `avancecorp-coordinacion-pg-actual`.
La plantilla ya debe existir y contener el esquema de CRM. No es un replay desde cero.

Desde `CRM-Avance-Corp`:

```bash
python3 supabase/scripts/supervisores-metas/ensayar.py
```

El runner no admite un destino arbitrario; la semilla exige ese nombre de base,
usuario postgres, triggers activos y tablas de equipo/contratos vacías. Crea
personas ficticias, ventas, metas y una fotografía sintética. Ejecuta las lecturas
con rol `authenticated`, alternando identidades. Migración, reversa, reaplicación
y fixtures ocurren en una transacción que termina con `ROLLBACK`.

`--sql` imprime el guion para inspección. No ejecutarlo contra otro entorno.

## Qué cubre

59 aserciones SQL: 54 lecturas antes/después (9 actores × 3 meses × 2 fases),
paridad JSON global y de analistas, aislamiento entre supervisores, corte de
octubre, PEN/USD, contratos y cooperativas, supervisor sin analistas y sin ventas,
sesiones inválidas, bajas CRM/perfil, cambios de rol, ACL y opciones de la función,
inmutabilidad de ventas/fotos, reversa y reaplicación.

La fotografía cerrada de noviembre copia las ventas de octubre mientras noviembre
no tiene operaciones: así detecta cualquier recálculo accidental. No prueba el
escritor `cerrar_periodo`, que no se modifica; el banco tiene una versión anterior
de ese escritor. Las funciones de lectura y los núcleos usados se contrastaron
con las definiciones productivas leídas sin mutaciones.

## Reversa y promoción

`reversa.sql` restaura la definición revisada guardada en `vivo/`, únicamente si
la huella actual coincide con esta migración. No borra datos ni altera snapshots.
Si otra migración modifica la función, falla antes de sobrescribirla.

La promoción sigue el ciclo del proyecto: rama Supabase autorizada, ensayo con
Auth/PostgREST y advisors, integración y publicación autorizada del frontend.
La rama `olqqhmatdhrasbzxarbz` pasó SQL y Auth/PostgREST; advisors no introduce
hallazgos. Ambos clientes comparten el mismo contrato JSON; la nueva
suma/presentación requiere el frontend actualizado.

El gate HTTP se ejecuta desde esta carpeta raíz con
`node supabase/scripts/test-rls.mjs --supervisores-metas preparar`, luego `antes`,
aplicación de la migración en la rama y `despues`. Requiere el archivo privado de
conexión de esa rama; no admite producción ni destinos arbitrarios. Una repetición
tras eliminarla exige una nueva rama autorizada y revisar explícitamente el destino.

Ver [decisión e implementación](../../../docs/plans/supervisores-metas/PLAN.md) y
[verificación](../../../docs/plans/supervisores-metas/VERIFICACION.md).
