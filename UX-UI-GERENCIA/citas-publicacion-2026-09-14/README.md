# Citas: reglas finales y preparación de publicación

Estado: preparado y verificado; publicación pendiente de cerrar la instalación
paralela F8. Miguel reanudó y mantiene su autorización de deploy de Citas.

## Comportamiento

Meta interna 1,25 citas/lead y objetivos 70% entrevistas / 70% clientes. Incluye
registros manuales. Cada cita atendida suma entrevista; cada persona vinculada
cuenta una vez en la conversión, incluso si tiene varios leads o perfiles.
Diez personas, quince entrevistas y siete clientes representan 70%.

Las entrevistas y conversiones cuentan en el mes del evento y para quien
obtuvo el resultado. La tabla conserva todos los clientes del periodo; su
detalle explica cuáles vienen de las entrevistas comparadas en esa tasa.
El total del equipo reconoce colaboraciones entre analistas. Capital y ticket
permanecen separados por moneda y mes. El editor trae las respuestas aprobadas,
pero sólo una versión aplicada en el servidor activa las reglas.

## Verificación

- PASS `npm run check`: 243 archivos, 3519 tests, lint, tipos, cobertura, build,
  configuración, bundle y duplicación. Base integrada `8c185f6`.
- PASS 9 E2E afectados. Corrida integral anterior: 179 PASS / 26 SKIP.
- PASS SQL mensual: asignación sin citas, manuales, fechas de registro,
  entrevista/conversión nativa, capital real USD, roles y anulación.
- PASS SQL identidad: persona canónica sin perfil, alias con perfil, lead con
  perfil directo, perfil sin inversionista y lead sin vínculo. No crea clientes.
- Los dos SQL se repitieron con F3 ON y F8 instalado OFF, igual que producción.
- PASS configuración local: permisos, historial, auditoría, aplicación explícita,
  conflictos concurrentes, mes anterior y mes sellado.
- PASS 48 verificaciones Auth/PostgREST de Superadmin y rechazo de otros roles.
- PASS ensayo de aplicación administrativa con Superadmin sintético, lectura de
  vigencia y auditoría comprobadas; transacción revertida al terminar.
- PASS `check:scripts`, `seed:preflight`, `test:rls:preflight`, `test:edge-preflight`.
- RLS general: **FAIL** en ambos lados, 49/1827; mismos 49 casos por multiconjunto,
  cero aserciones nuevas. La referencia usó el esquema previo a Citas contrastado
  con producción y la misma semilla. Dos diagnósticos R2 varían sólo por el día al
  cruzar medianoche. Esa comparación antecede a F8; la integración posterior con
  F8 se comprueba mediante los SQL de dominio, huellas y permisos, sin atribuirle
  un PASS general a la matriz. Véase `rls-comparacion-por-caso.json`.

## Revisiones resueltas por PRIMARY

Los dos dictámenes originales fueron CHANGES_REQUESTED; se conservan, no se
reescriben como PASS. No hubo una tercera consulta automática.

1. Identidad independiente de conversiones: el servidor entrega la identidad
   canónica; prioriza persona sobre perfiles distintos. SQL de alias y pruebas
   de una conversión/no conversión verifican el denominador estable.
2. Clientes y ticket usan la misma identidad que las personas entrevistadas:
   prueba de dos perfiles vinculados evita 200% y verifica ticket 1500.
3. Ana entrevista/Luis cierra: resultado para Luis, total conjunto vinculado,
   tasa individual sin entrevista propia sin base. Cubierto en `avance.test.ts`.
4. Defaults sin aplicación: se exige versión positiva y vigencia aplicada;
   tests frontend y servidor conservan versión cero sin activación automática.
5. Detalle «sin cita»: usa la base pendiente; los cierres e entrevistas añadidos
   al detalle no se presentan como leads asignados sin cita.
6. CSV: nuevas columnas al final, conserva el orden de las existentes.

## Base e instalación

Banco propio `xhgsjtzpmwlqfkninphl`. Se respaldaron y retiraron 15 registros de
ensayos del historial mediante CLI `migration repair`, sin cambiar el schema.
Se registraron los cinco archivos canónicos de `migraciones.json`. Las 279
entradas anteriores permanecieron intactas. Después se incorporaron por rebase
las dos nuevas migraciones productivas F8: 281 entradas iguales al padre y sólo
cinco candidatas adicionales, 286 en total. Véase `historial-tras-f8.json`.

La primera incorporación F8 se detuvo porque la semilla tenía F3 OFF. Se alineó
esa bandera únicamente en el banco, con F4–F8 OFF, y el rebase completó. No se
alteraron banderas ni datos de producción desde esta tarea.

637 funciones productivas contrastadas: sólo cambia el lector de Citas; se
añaden seis funciones de configuración. No faltan funciones ni cambian los
permisos/propietarios de las existentes. Capital conserva
`c9e58c1da9dd7a5d52991c9e47dc19d5`; lector candidato
`4ad2b90baf96b11b63a626122bd5d64b`. Censo 34 declarados, 30 sujetos al techo,
cuatro auxiliares, cero sin declarar. Las 19 Edge conservan paquetes y JWT.

Advisors: dos INFO de tablas RLS cerradas intencionalmente y tres WARN de RPC
DEFINER exclusivas de Superadmin, verificadas con Auth real. Dos índices de
autoría todavía sin uso. No se abren políticas para eliminar avisos intencionales.
Las otras diferencias de uso de índices corresponden a la actividad del banco.

## Publicación y reversión

1. Conciliar Main y `avancecorp/main`, preservar trabajo ajeno y cerrar el otro
   despliegue. El artefacto debe salir de ese mismo commit, con árbol limpio.
2. Construir y verificar ZIP/manifiesto usando `npm run release:crm` y `verify`.
3. Revalidar las 281 entradas del padre y las cinco candidatas; merge de la rama
   propia. No aplicar SQL de esquema directamente a producción.
4. Ejecutar `activar-reglas.sql` por la vía administrativa autorizada. Usa las RPC
   existentes, el único Superadmin activo, versión inicial cero, mes abierto y
   nota explícita de ejecución asistida; lee y comprueba auditoría y vigencia.
5. Deploy del ZIP verificado por `hosting_deployStaticWebsite` a `crm.miavance.com`.
6. Verificar versión HTTP, hashes de todos los recursos y lectura de métricas.

`rollback-lector.sql` restaura el lector anterior bajo su huella exacta y conserva
historial/configuración. Requiere restaurar el ZIP anterior verificado. Se prepara
como compensación administrativa, no como borrado del historial de migraciones.
No ejecutar una reversión sobre una función que haya cambiado desde la candidata.

Los logs completos y accesos del banco quedan privados. Esta carpeta conserva
evidencia saneada, contratos, hashes y decisiones; no contiene claves ni sesiones.
