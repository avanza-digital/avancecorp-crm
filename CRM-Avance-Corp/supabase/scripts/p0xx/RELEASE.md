# P-0XX — estado de publicación (25/09/2026)

**No usar el Merge Request del dashboard.** Se cerró sin fusionar. Su SQL
descargado omitía el bloque `DO $backfill$` de S1 y proponía eliminar objetos
ajenos a P-0XX (`crm.periodos_cerrados.ponderacion_renovacion`, dos funciones de
conversión, `private.respaldo_cierre_agosto_2026` y `pg_net`). Rebase no lo
resolvió. Un merge así dejaría los contratos antiguos sin cuenta vinculada y
activaría el bloqueo de pagos de S3.

## Qué está preparado

- Migraciones canónicas, ensayadas en la rama `hhpjiygytwoayxymziqo`, en este
  orden: `20260925153226_p0xx_cuentas_cliente_backfill_lectura.sql` (S1),
  `20260925194026_p0xx_pagos_solo_cuenta_contractual.sql` (S3),
  `20260925202140_p0xx_portal_cliente_mis_cuentas.sql` (S4),
  `20260925210000_p0xx_cuentas_cliente_escritura.sql` (S2). S2 va al final:
  desde su commit, las versiones antiguas de las tres Edge Functions dejan de
  poder registrar cuentas en `perfiles`.
- Las Edge Functions `crear-cliente`, `crm-convertir-lead` e
  `importar-clientes` están desplegadas **solo en la rama** y llaman la RPC de
  S2. Sus versiones productivas antiguas no son compatibles con la guarda de
  S2. El portal nuevo requiere S4 y S2.
- ZIP del portal construido desde el commit `717e4c199f2991e73b4dc00b9e08f0c1acdb040e`
  en `_DEV_NO_SUBIR/releases/portal-p0xx-717e4c199f29.zip`; artefacto de
  reversión del commit anterior en la misma carpeta. No se subieron.
- `backfill-data-only-after-schema.sql` contiene exactamente el bloque de datos
  de S1 y se ensayó en la rama: reejecución con **0 cuentas y 0 vínculos nuevos**.
  Sirve únicamente si se instaló primero un esquema seguro por otra vía; no
  corrige el diff destructivo del Merge Request.

## Ruta de instalación propuesta; requiere cambiar la autorización original

La instrucción vigente limita todo DDL/DML del agente a la rama y reserva el
merge productivo a Miguel. Por eso **ningún paso de esta sección se ejecuta
automáticamente**. Para publicar con migraciones completas, Miguel debe
autorizar explícitamente otra vía de despliegue productivo. La vía propuesta es
aplicar los cuatro archivos canónicos como migraciones, no el diff del MR.

1. Preflight de producción de solo lectura: salud, backup reciente, ausencia
   de las cuatro funciones/migraciones P-0XX, proyección de cuentas/vínculos,
   funciones/columna/tabla de conversión y extensión `pg_net` intactas.
2. Coordinar una ventana breve sin altas de clientes, conversiones,
   importaciones, edición de cuentas ni ejecución de pagos. Guardar las tres
   versiones Edge anteriores y el ZIP del portal actual.
3. Aplicar S1. Confirmar que el ledger recibió las cuentas válidas, se
   vincularon solo contratos con una candidata y que los restantes figuran en
   conciliación. Si falla, detener la publicación.
4. Aplicar S3 y S4. Comprobar que un contrato sin vínculo no puede marcarse
   pagado y que un cliente autenticado solo ve sus propias cuentas enmascaradas.
5. Aplicar S2 al final y desplegar **inmediatamente** las tres Edge Functions
   nuevas. Verificar sus versiones y el contrato de la RPC antes de reabrir
   altas/conversiones/importaciones. El primer alta real se supervisa sin
   introducir clientes ficticios en producción ni enviar datos bancarios a logs.
6. Publicar el ZIP del portal por Hostinger, purgar caché y comprobar HTTP y
   UI con cuentas del cliente y pagos. Luego reabrir pagos solo para contratos
   vinculados. Los pendientes quedan detenidos para Operaciones.

La ejecución de cuatro migraciones es deliberada: cada archivo queda registrado
por separado y se comprueba la versión que asigne el despliegue. S1/S3/S4 son
compatibles con las Edge antiguas; S2 es el
punto de corte. Si algún paso previo a S2 falla, no se activa la guarda que
bloquearía las altas antiguas. Las migraciones no son una reversa automática
de datos ya usados. La reversa de S1 existente está restringida a ramas y
rechaza cuentas/vínculos utilizados por pagos.

## Gates y límites conocidos

- Rama: S1–S4 y modos de contrato `existente`, `nueva`, `perfil` aprobados;
  reejecución del backfill de datos aprobada. La matriz RLS completa no se
  ejecutó por falta de un banco de credenciales limpio.
- Proyección productiva de solo lectura anterior al despliegue: ~241 cuentas
  válidas a migrar, 257 vínculos y 23 contratos activos que seguirían sin
  vínculo: 16 sin cuenta y 7 con varias candidatas. El reporte nominal con
  cliente, DNI, moneda y analista se guardó fuera de Git en
  `_DEV_NO_SUBIR/releases/p0xx-conciliacion-proyeccion-20260925.csv` (permiso
  600). Tres perfiles tienen el mismo CCI que CRM con otros datos y requieren
  decisión humana. Recalcular justo antes de publicar.
- El advisor de seguridad de la rama muestra dos WARN nuevos por las dos RPC
  `SECURITY DEFINER` intencionalmente ejecutables por `authenticated`; ambas
  verifican autorización. Por tanto el criterio literal «sin hallazgos nuevos»
  no se declara cumplido. No se añadieron hallazgos nuevos de rendimiento.
- El backend y portal están en commits locales; el portal Git remoto no es
  accesible desde este entorno. El CRM local difiere de `avancecorp/main` y
  contiene trabajo ajeno sin commitear. No publicar un build CRM desde ese
  estado.

Referencias: [Branching sin Git](https://supabase.com/blog/branching-without-git-is-now-the-default),
[límite de `db diff`](https://supabase.com/docs/guides/local-development/cli-workflows#known-limitations-of-db-diff),
[datos entre ramas](https://supabase.com/docs/guides/deployment/branching/troubleshooting#data-issues).
