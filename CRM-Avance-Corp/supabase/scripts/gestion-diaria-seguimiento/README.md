# Banco de cierre de Gestión Diaria F4

Destino autorizado único: `gestion-diaria-f4-http`, API `127.0.0.1:59321`, base
`127.0.0.1:59322`. Los scripts verifican identidad sintética, Docker local, red,
servicios y credenciales locales. No aceptan otro proyecto ni una URL productiva.

Ejecutar desde `CRM-Avance-Corp/`. No restablecer este banco ni otros servicios
para repetir una prueba: conserva evidencia de entregas y versiones inmutables.

## Secuencia ya ejecutada el 22/09/2026

1. `ensayar.mjs --solo-banco-autorizado`: instala los tres candidatos dentro de
   una transacción, prueba gates, 24 mutantes (más BYPASSRLS en el ensayo de correcciones), roles, horarios y grupos SLA, y
   termina en ROLLBACK. **Requiere banco anterior a etapa 4**; no repetir sobre
   la instalación actual.
2. `instalar-local.mjs --solo-banco-autorizado`: verifica el respaldo y aplica
   los tres candidatos juntos. Se ejecutó una vez; rechaza reinstalación.
3. `contrato-http.mjs --solo-banco-autorizado`: Auth/API reales de seis roles,
   cortes OFF y contexto completo. Requiere política inicial v1 OFF. PASS antes
   de preparar los casos de concurrencia.
4. `concurrencia-http.mjs --solo-banco-autorizado`: prepara v2 sintética activa,
   comprueba dos esperas simultáneas en PostgreSQL y libera cada lock. Publica
   v3 OFF futura, entrega popup, pospone y reconoce con dos sesiones. **Ya
   ejecutado; su manifiesto impide repetir la preparación.** No modifica los
   relojes de las RPC instaladas.
5. `navegador.mjs --solo-banco-autorizado`: login y negocio reales. Comprueba
   editor enfocado, popup, registro, foco, reconocimiento, aplazamiento y nueva
   sesión móvil. Las entregas de sup1 ya quedaron registradas.

Los pasos 1–5 se ejecutan con `node supabase/scripts/gestion-diaria-seguimiento/`
como prefijo del archivo. Los tests SQL usan fixtures dentro de transacciones;
las copias de funciones con reloj controlado son privadas de `pg_temp`.

## Comprobaciones repetibles sin escribir negocio

```sh
node supabase/scripts/gestion-diaria-seguimiento/navegador.mjs --solo-banco-autorizado --solo-capturas
node supabase/scripts/gestion-diaria-seguimiento/generar-tipos-local.mjs --solo-banco-autorizado
node supabase/scripts/gestion-diaria-seguimiento/cotejar-tipos.mjs --comprobar
```

Las capturas cancelan la confirmación de configuración. Tipos: imagen oficial
postgres-meta v0.99.0, namespace del contenedor de esta base sin egreso. La CLI
`--local` presupone un alias `db` ausente en el banco; este generador usa el
mismo postgres-meta con `127.0.0.1` interno y no cambia la red del banco.

El archivo completo generado queda en `/private/tmp/gd-f4-tipos-generados.ts`.
`cotejar-tipos.mjs --actualizar` incorpora solo diez contratos afectados por
F4; conserva tipos ajenos y versión PostgREST productiva (el banco usa 16.2).

Manifiestos, credenciales y capturas están fuera de Git, en
`/private/tmp/gestion-diaria-f4-http.WQNCJc`. No publicar esa carpeta ni incluir
credenciales en actas. Resultados y límites: [acta F4](../../../docs/gestion-diaria/F4-CIERRE-EJECUCION-2026-09-22.md).

## Correcciones de la segunda revisión

`correcciones-local.mjs --solo-banco-autorizado` ensayó e instaló el cuarto
candidato de lectura; conserva las tres etapas anteriores y las políticas.
Se ejecutó una vez. `verificar-correcciones.mjs --solo-banco-autorizado` prueba
mutantes, permisos heredados de auth, reglas inválidas por RPC, llamadas no útiles
y escrituras con SLA caído, todo dentro de ROLLBACK. Supabase_admin solo permite
ensayar el mutante BYPASSRLS; las escrituras de negocio se prueban con authenticated.
