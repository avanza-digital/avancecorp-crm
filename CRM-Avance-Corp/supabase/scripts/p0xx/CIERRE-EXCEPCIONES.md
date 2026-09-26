# P-0XX — cierre de excepciones, ensayo del 26/09/2026

## Estado

El CRM y el portal ya estan publicados. Este ajuste posterior permanece
**solo en la rama** `p0xx-cuentas-unificadas-20260925`, proyecto
`hhpjiygytwoayxymziqo`. La autorizacion productiva anterior cubria cuatro
migraciones concretas; no cubre este nuevo ajuste.

Miguel autorizo probar SECURITY INVOKER exclusivamente en las dos entradas de
pantalla. Tambien confirmo conservar el beneficiario corregido en la ficha del
caso de titularidad. No se cambiaron datos bancarios reales en este ensayo.

## Permisos

`20260926145330_p0xx_cuentas_wrappers_invoker.sql` conserva cuerpos, firmas y
search_path de las dos RPC. Solo las entradas `crm.registrar_cuenta_cliente`
y `public.mis_cuentas_bancarias_fn` pasan a SECURITY INVOKER. Sus autorizadores
privados mantienen SECURITY DEFINER y reciben EXECUTE para authenticated.
Hechos y tablas siguen sin acceso directo. La API rechaza el esquema private
con HTTP 406/PGRST106, incluso con una sesion autenticada.

- Security advisors: 230 → 228 avisos de funciones privilegiadas; desaparecen
  exactamente los dos introducidos por P-0XX. Comparacion de hallazgos: 0 nuevos.
- Performance advisors: comparacion de hallazgos: 0 nuevos.
- SQL S2, S4 y `verify-permisos-invoker.sql`: PASS.
- HTTP de cuentas propias, cuenta vacia, mascara, anon y esquema privado:
  **10 PASS**.
- Matriz real HTTP/RLS `test-rls.mjs --contratos`: **287 PASS**.

El primer intento de la matriz encontro seis fallos debidos a la semilla
reutilizada: domicilio ya completado y cuentas activas de anteriores pruebas
de idempotencia. Se restauro unicamente ese fixture en la rama, conservando
sus contratos y enlaces, y se repitio el gate completo con exito.

El caso SQL positivo del analista usa ahora un cliente creado en su propia
transaccion. La fecha de alta de perfiles es inmutable: asi el ensayo no
depende de que la semilla tenga menos de cinco horas. El cliente antiguo se
versiona como Gerencia; no se amplio el permiso del analista.

## Conciliacion propuesta

- **Formato:** mismos digitos y CCI; crear una version con el numero sin guiones.
- **Titular:** conservar el beneficiario confirmado mediante una nueva version.
- **Banco:** el CCI empieza por 002 y el contrato registra BCP; el perfil legado
  dice Interbank. Propuesta: reparar una unica celda `perfiles.banco` a BCP.
  Esta operacion requiere una excepcion expresa a la regla de solo lectura.

Las dos versiones se crean usando la RPC oficial, con origen portal y actor
administrador identificable. Sus IDs y la referencia a la version anterior
quedan en `private.backfill_cuentas_p0xx`, marca `conciliacion:p0xx:*`.
Los contratos conservan sus versiones originales; no se cambia su instruccion
contractual ni se religa ningun pago. Los digitos de las cuentas y los CCI se conservan.

La reparacion excepcional del banco bloquea la tabla durante la transaccion,
suspende solo el trigger bancario y lo restaura antes del commit. La auditoria
sigue activa y debe registrar exactamente una modificacion de la clave banco.
No se instala ninguna sincronizacion ni excepcion permanente al trigger.

Los parametros reales y sus huellas estan fuera del repo. Los scripts abortan
si el estado difiere del revisado. La propuesta productiva comprueba cero
perfiles validos sin equivalente y revierte toda la conciliacion si no se cumple.

## Ensayo reproducible

```bash
node CRM-Avance-Corp/supabase/scripts/p0xx/preparar-verificacion-conciliacion.mjs /tmp/p0xx-conciliacion-test.sql
# Ejecutar el archivo resultante SOLO en la rama con la semilla S1.
```

El generador incorpora los scripts reales; no mantiene copias de su logica.
El SQL generado crea personas y cuentas ficticias y termina en ROLLBACK.

Resultado: `P0XX_CONCILIACION_ATOMICA_IDEMPOTENTE_REVERSIBLE_OK`.

- Una huella incorrecta en el segundo caso revierte tambien el primero.
- Primera ejecucion: 2 cuentas nuevas y 1 nombre de banco corregido.
- Segunda ejecucion: 0 cuentas nuevas y 0 cambios de banco.
- Los tres casos tienen equivalente activo despues de conciliar.
- La reversa recupera los valores originales creando versiones, sin reactivar
  ni editar cuentas historicas.
- Si un contrato nuevo utiliza una version corregida, la reversa se rechaza
  y no deja cambios parciales en el otro caso.
- Los enlaces contractuales y el trigger de proteccion quedan intactos.

La reversa de versiones rechaza cuentas reutilizadas o cambiadas posteriormente.
Usar `revertir-versiones-conciliadas.sql` y `revertir-banco-legado.sql` con los
mismos parametros. El rollback original de S1 no es la reversa de este ajuste.

## Revision y limites

Revision propia del diff y `git diff --check`: PASS. Sintaxis Node del generador:
PASS. `npm run check:scripts`, `npm run seed:preflight` y
`npm run test:rls:preflight`: PASS en la copia limpia de Main, con dependencias
del lockfile y variables ficticias para los preflights sin conexion.
Dos intentos del wrapper de Claude no entregaron un VERDICT valido;
revision independiente: **NO COMPLETADA**. No se declara PASS.

No hay cambios de frontend en esta correccion. Se conserva la evidencia de
la publicacion anterior: 4.440 tests, 274 E2E aprobados y 26 omisiones previstas.
No se atribuyen esos resultados a una nueva ejecucion.

Pendientes: autorizacion productiva para el ajuste y la reparacion excepcional,
verificacion productiva final y actualizacion de los reportes de conciliacion.
El retiro de columnas/trigger legados y del modo perfil sigue fuera de alcance.
