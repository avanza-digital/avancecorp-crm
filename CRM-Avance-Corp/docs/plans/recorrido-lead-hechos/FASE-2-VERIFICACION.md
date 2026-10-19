# Fase 2 · Evaluación central

Evaluador y configuración implementados en las migraciones candidatas `20261019001500–01`. La regla obligatoria es asistencia real y entrevista con resultado explícito, de la misma cita y del ciclo vigente. Contacto y gestión son guía. Esta fase consulta y conserva evidencia; las puertas de conversión se protegen en la fase 5.

## Revisión Codex y correcciones

El auditor RLS independiente devolvió CHANGES_REQUESTED con dos P1 sustentados. Codex aceptó ambos y verificó las correcciones:

1. Las nuevas FK hacían rechazar la eliminación oficial incluso sin filas de contexto. Se amplió su lista cerrada, la copia auditada a versión 3 y el borrado explícito con comprobación de filas. Casos con y sin contexto: PASS.
2. Una base que nace dormida no tiene ciclo SLA; su primer intento podía fallar. Ahora se conserva el hecho previo como `base_sin_ciclo`, sin crear ni retroasignar un ciclo. No contestó y reactivación por reunión: PASS.

Codex añadió bloqueo BEFORE INSERT para evitar conversión circular de KEY SHARE a UPDATE entre escritores internos, y NOWAIT en invalidaciones que lleguen en orden inverso. Cuatro pruebas con conexiones PostgreSQL simultáneas comprobaron serialización, reapertura, rechazo sin efectos y lectura de invalidación confirmada. No se solicitó otro dictamen para sustituir las pruebas.

## Evidencia ejecutada

| Comprobación | Resultado | Evidencia |
|---|---|---|
| Baseline limpio contra catálogo capturado | PASS · 1.168 funciones idénticas, cero extras | evidencia/fase2-paridad.json |
| Migración y hardening íntegros desde baseline | PASS · propietario postgres y preflight de versión vigente | evidencia/fase2-replay.log |
| Contexto, asistencia/entrevista, ciclos, historia y bases | PASS | evidencia/fase2-sql.log |
| Permisos reales authenticated/anon/service_role | PASS · vendedor, supervisor, otro árbol, coordinación, directorio, gerencia, revocado e inactivo | evidencia/fase2-sql.log |
| Observación, corte de nuevos ciclos y reversión | PASS · corte inmutable; antiguos excluidos de exigencia automática | evidencia/fase2-sql.log |
| Concurrencia | PASS · cuatro escenarios | evidencia/fase2-concurrencia.log |
| Rendimiento sobre 4.000 leads, 60.000 actividades y 4.000 citas | PASS · p95 12,59 ms/50 IDs y 37,60 ms/100 IDs; 40 muestras por tamaño | evidencia/fase2-rendimiento.log |
| Generación de tipos desde banco candidato | PASS · salida del CLI válida | evidencia/fase2-tipos.log |
| TypeScript y sintaxis de los dos runners | PASS · `npm run typecheck` y `node --check` | evidencia/fase2-typecheck.log |
| Activación/migración productiva | NOT RUN · fuera de autorización | Modo inicial observación |
| E2E de interfaz y guard financiero | NOT RUN · fases 4–6 pendientes | No se declara protección de conversión instalada |

Rendimiento medido en Apple M5 Pro, 24 GiB de memoria física, PostgreSQL 17.6.1.167 dentro de Docker. No se limita CPU/memoria por contenedor; no se midió la cuota de la VM. Estas cifras no predicen producción. El banco usa configuración copiada por lectura y actores/datos sintéticos; los oráculos funcionales y de carga revierten sus datos. Los escritores y triggers de producto se ejecutaron sin reemplazos para conseguir PASS.

## Historia y despliegue

El censo READ ONLY sobre 1.965 leads operativos encontró 78 ambiguos y 1.887 incompletos respecto del nuevo sello de asistencia. No demuestra que nunca fueran atendidos: señala evidencia histórica insuficiente bajo el contrato nuevo. No se fabrican hechos ni se aplica exigencia retroactiva. Se necesita política comercial explícita para antiguos antes de una activación que los incluya.

El aislamiento local se reconstruyó únicamente en `avancecorp-recorrido-lead-20261018`. El gate remoto de rama/advisors queda para fase 6 y requiere resolver la confirmación de costo del servicio; no se modificaron ramas remotas compartidas.

## Reproducción

Tras restaurar el esquema capturado en el stack propio y cargar configuración/actores sintéticos, ejecutar desde CRM:

```sh
node supabase/scripts/recorrido-lead/banco.mjs instalar
node supabase/scripts/recorrido-lead/banco.mjs test
node supabase/scripts/recorrido-lead/concurrencia.mjs
node supabase/scripts/recorrido-lead/banco.mjs rendimiento
supabase gen types typescript --local --workdir /private/tmp/recorrido-lead-hechos-20261018/stack --schema public,crm
```

El generador local no añade `__InternalSupabase.PostgrestVersion`. Se conservó ese bloque ya versionado (`14.5`) y se reemplazó el resto por la generación local. No se ejecutó `npm run gen:types` contra producción, porque borraría del archivo las RPC candidatas. La advertencia MaxListeners del CLI no alteró la salida ni su código de éxito.

Cierre Codex: PASS local de esta fase. Las dos observaciones P1 aceptadas están corregidas y probadas; no quedan hallazgos obligatorios abiertos en el bloque de evaluación. SQL/RLS integral, advisors, interfaz y protección final se vuelven a comprobar en sus fases correspondientes.
