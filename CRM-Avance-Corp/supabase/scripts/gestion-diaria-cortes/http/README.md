# Banco HTTP de Gestión Diaria F4.3

Banco desechable autorizado por Miguel. No es un instalador productivo ni un
comando genérico para cualquier Supabase. El destino, volumen, red, seis servicios
y directorio están fijados en `banco.mjs`; cambiarlo requiere revisar el alcance.
Datos exclusivamente ficticios. No copiar usuarios, secretos ni filas comerciales.

API/Auth: `http://127.0.0.1:59321`; PostgreSQL: 59322; interfaz de prueba: 59323;
correo local: 59324. Directorio privado: `/private/tmp/gestion-diaria-f4-http.WQNCJc`.
Las contraseñas, JWT, dumps y resguardos privados no se imprimen ni versionan.
Las capturas contienen sólo fixtures y nunca son una sesión de producción.

## Aislamiento y preparación ya ejecutada

Los seis servicios pertenecen al proyecto `gestion-diaria-f4-http`, usan sólo
su red y la misma base `postgres` en su contenedor propio. Puertos loopback,
IPv6 deshabilitado y reinicio automático apagado. No hay Cron, pg_net, Edge ni
configuración de proveedores de producción. `enable_ip_masquerade=false` por sí
solo NO fue suficiente: se retiró además la ruta por defecto de cada namespace.
`verificarBanco` exige identidad, salud y ausencia de esas rutas antes de operar.
Tras cualquier reinicio hay que ejecutar `aislar-egreso.mjs --solo-banco-autorizado`.

Se restauró sólo esquema vigente y metadatos técnicos. `paridad.sql` y
`comparar-paridad.mjs` verifican 14 categorías de catálogo, no igualdad de datos
ni una réplica productiva. Los defaults de ACL de la CLI difieren del origen;
se corrigieron sólo en este banco y se cotejaron dueños, permisos y RLS.

`sembrar.mjs` llama al seed canónico con Auth real. Los documentos/teléfonos del
staff son ficticios, necesarios para el snapshot contractual vigente. Las reglas
técnicas y Storage se completaron sin copiar personas. La semilla limpia privada
es `semilla-base.dump`, con checksum y manifiesto; no contiene F4.3.

`reconstruir-fixture.mjs` fue una reparación inicial de la preparación, de un solo
uso: conserva la base anterior en `gd_f4_http_historial_20260922`. No volver a
ejecutarlo. `restaurar-semilla.mjs --solo-banco-autorizado` permite repetir el gate
desde la semilla y conserva cada ensayo anterior en una base renombrada del mismo
contenedor. No trunca historia y **se niega a funcionar con F4.3 instalada**.
Esta restauración de fixtures NO demuestra la reversión de una migración.

## Comandos del ensayo

Desde `CRM-Avance-Corp`, anteponer
`node supabase/scripts/gestion-diaria-cortes/http/` a cada script:

1. `matriz.mjs --baseline`: gate CRM completo antes del candidato. F4.3 ausente
   se informa como NO PROBADO, nunca PASS. La matriz modifica fixtures; no repetir
   encima de sus residuos para inventar una semilla limpia.
2. Restaurar la semilla autorizada. `candidato.mjs --ensayar-atomicidad` fuerza
   una excepción al final de la transacción exacta: cuerpos, negocio y auditoría
   deben quedar intactos, sin F4.3 instalada.
3. `contrato-http.mjs --guardar-baseline`, `candidato.mjs --instalar` y
   `contrato-http.mjs --comparar-instalado`. El instalador exige el SHA-256 exacto
   del SQL aprobado localmente y captura las seis funciones, ACL y comentarios.
4. `matriz.mjs --candidato`: gate completo con `CRM_RLS_EXIGE_CORTES=1`.
   Este modo no permite saltar F4.3 por una migración o caché rota.
5. `navegador.mjs --solo-banco-autorizado`: login de formulario, API real,
   supervisor 1/2 y analista, detalle/registro, errores sin falsos ceros y móvil.
   No MSW, sesión demo, JWT inyectado, traces ni storageState exportado.
6. `contrato-http.mjs --guardar-reversa`, `candidato.mjs --revertir`,
   `contrato-http.mjs --comparar-revertido`, y repetir el navegador. La reversión
   elimina sólo los objetos nuevos y la semilla OFF; conserva historia comercial
   y auditoría. Es recuperable reinstalando el candidato exacto.
7. `compatibilidad-cliente.mjs --solo-capturas-locales`: ejecuta los parsers
   reales del Main anterior y del candidato contra ambas respuestas capturadas.
   Son 28 parseos, no un build completo de cuatro versiones de la aplicación.
8. Capturar nueva baseline, reinstalar y comparar. El banco puede quedar instalado
   OFF para inspección. `sla-activo.mjs --solo-banco-autorizado` publica las cuatro
   reglas SLA sintéticas por su RPC oficial, prueba la interfaz y seguimiento
   persistido con SLA activo y restituye el modo original sin borrar historia.
   **SLA activo no significa cortes activos**. El banco conserva su política F4 OFF.

La comparación HTTP ignora sólo `generado_en`, `pendientes_al` (exige que coincida
con `generado_en`) y las adiciones documentadas `cortes`/`umbrales.politica_version`.
No elimina contadores ni datos de negocio para conseguir igualdad. Se usa un día
terminado; el roster y pendientes siguen teniendo la semántica actual del producto.

Preflight offline: `npm run test:gestion-diaria-cortes:http:preflight`.
E2E existente, aparte del backend real:
`npm --prefix app run test:e2e -- --config ../supabase/scripts/gestion-diaria-cortes/http/e2e.config.mjs gestion-diaria`.
Usa el puerto 59323 y no debe coincidir con el navegador real. Se creó este override
porque el 5199 estaba ocupado; no se detuvo ni reutilizó el proceso ajeno.

## Límites de la evidencia

La matriz general usa el flujo compartido vigente para cooperativas y Avance,
con Auth/PostgREST/Storage reales y rechazo explícito de las puertas legacy.
El handler oficial de alta de acceso Avance corre **en proceso**, no desplegado
como Edge. La service_role sólo participa dentro de ese handler y en preparación/
observación de fixtures; no sustituye al actor en las escrituras económicas.

La Edge de tipo de cambio no está en el banco: la aplicación informa que no está
disponible, sin simular una tasa. No se prueban proveedores externos, correos
productivos, notificaciones, rendimiento representativo ni activación de cortes.
El navegador integrado no estaba disponible; se utilizó Playwright del proyecto.

Los scripts y SQL de reversión de esta carpeta se niegan a operar fuera del banco.
No retirar esas guardas para publicar. El procedimiento de release/recuperación
está en `docs/gestion-diaria/F4-PUBLICACION-RECUPERACION.md`.
