# Resultado — Citas por fecha comercial

**Publicada y verificada el 17/10/2026.** Fuente `bc3c4303`, build
`build-20261017T064501541Z`; acta vigente: [PUBLICACION.md](PUBLICACION.md).
El resto de esta nota conserva la evidencia de la etapa local original, basada
en `e4ded65d`. Copia autorizada: `/private/tmp/crm-citas-fecha-comercial-20261017`.
La carpeta original conserva el trabajo de otras tareas.

## Regla aplicada

Cada cliente elegible de Citas pertenece al mes de la fecha comercial del núcleo
`conversion_cierres`; `convertido_en` conserva el registro de carga para auditoría.
Las entrevistas conservan su fecha/configuración, incluyendo seguimiento por
asignación. La asociación exige entrevista del mismo día comercial o anterior
en Lima; no se afirma el orden dentro del día. No hay fallback a fecha de carga
si falta una fecha comercial acreditada. Identidades, anulaciones, manuales y
atribución siguen sus reglas actuales. Los movimientos bancarios con hora
conservan su comparación temporal estricta.

La consulta es aditiva: versión anterior compatible; la nueva pantalla exige
el marcador comercial y selecciona `testigo.comercial`. Si el servidor anterior
no entrega el contrato, falla explícitamente. Los duplicados de lead siguen
rechazados; la fecha para recuperación no se elige arbitrariamente cuando la
fuente es ambigua. No se modifican ventas ni sellos monetarios.

El aviso aparece junto al total mensual, enumera campo/pantalla/servidor y deja
porcentaje, proyección y exportación pendientes. Mantiene la comparación global
aunque se filtre por analista, equipo o persona. El detalle no atribuye a un
analista una discrepancia global. Tabla, detalle, recuperación, estados de cita,
ayuda y CSV usan la misma regla comercial y conservan el registro para auditoría.

## Conciliación completa

Lecturas de solo lectura del 17/10/2026, 05:06 UTC. Son resultados al corte,
no constantes futuras. La conciliación compara el cálculo real del frontend
contra SQL independiente; todas las filas de analistas coinciden.

| Mes | Clientes | Entrevistas | Personas | Vinculados | Depósito % | Filas de analistas |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Septiembre | 116 | 74 | 62 | 10 | 16,13 % | 26 |
| Octubre | 43 | 84 | 79 | 15 | 18,99 % | 28 |

El censo completo detectó 17 ventas comerciales de septiembre cargadas en octubre.
Los tres casos consultados están acreditados en septiembre:
001379: 05/09 (registro 06/10); 001428: 14/09 (registro 05/10);
001481: 21/09 (registro 01/10). Ver `contratos-verificados.json` y `conciliacion.json`.
No se versionan nombres, teléfonos ni payloads productivos. La evidencia local
pseudonimiza UUID y elimina campos de contacto/notas antes de escribirla.

## Verificación

- PASS: `npm run check`: 436 archivos, 7.014 tests; lint, tipos, cobertura, configuración de release, build, bundle y duplicación. Avisos de lint preexistentes ajenos.
- PASS: 94 casos de Citas incluidos en la suite final tras la corrección del estado de cierre.
- PASS: 14 E2E Docker de Citas/control/avance, incluida venta tardía en tabla, detalle y CSV; aviso concreto, bloqueo y filtros.
- PASS: 22 pruebas de conciliación: Sep/Oct completos, cuatro payloads del lector instalado (incluida renovación) y 16 combinaciones de configuración.
- PASS: 15 aserciones SQL de datos y permisos sobre esquema completo restaurado, sin reemplazar núcleos. La semilla simula postestados y omite triggers de escritura; no acredita el flujo de alta.
- PASS: 71 aserciones de compatibilidad con las nueve migraciones de valoración paralela: corte vigente/pendiente/ausente, sellado, roles y capital. Solo en base propia, rollback completo. No implica que esa tarea esté publicada.
- PASS: reversa transaccional exacta de funciones, owners, ACL, configuración, declaraciones y sello.
- PASS: inspección visual de Citas móvil y anchos 390/768/1280/1440, sin desbordamiento de página en E2E.
- NOT RUN: `gate:realidad`, `seed:preflight`, `test:rls:preflight`, matriz RLS HTTP integral y advisors remotos: no hay entorno candidato con credenciales configuradas (`SUPABASE_URL` ausente). La matriz local de autorizaciones y el contrato RPC sí se ejecutaron.
- FAIL PREEXISTENTE: `assert_analitica_leads_citas` global: 8 contadores no declarados y 3 huellas caducadas, medidos en producción antes del cambio. El sello general sí coincide. No se modifica ni relaja ese control. La migración conserva exactamente el censo anterior y exige declaraciones correctas para sus funciones.
- Tipos generados: no aplica; no cambian firmas de RPC ni objetos tabulares. Sí se actualizó el esquema runtime de la respuesta.
- Revisión independiente final: CHANGES_REQUESTED sin P0/P1. PRIMARY resolvió los puntos con pruebas; ver `REVISION-CLAUDE.md` y `DECISION-REVISION.md`. Sin tercera consulta.
- Medición local: veinte muestras, medianas anterior 5,44 ms/comercial 7,44 ms. No representa carga productiva.

## Publicación y reversa

1. Actualizar desde `avancecorp/main`, integrar concurrentes y revalidar el diff. No sobrescribir la tarea paralela de TC.
2. Si TC se publica en el mismo lote, integrar/instalar sus migraciones primero; esta candidata modifica aditivamente ambos lectores. Su instalación posterior sin conciliación sería rechazada por su huella anterior. La compatibilidad fue ensayada en ese orden.
3. Ensayar el SQL exacto en la rama/instancia de publicación autorizada y ejecutar RLS/advisors/gates de ese entorno. Los NOT RUN anteriores siguen pendientes de publicación; no se presentan como aprobados.
4. Con el flujo humano de publicación autorizado, instalar primero la migración y después el frontend construido desde el commit verificado de Main. Comprobar marcador, testigo comercial y cifras Sep/Oct al mismo corte.
5. Ante un problema del frontend, volver al artefacto anterior: el servidor conserva el contrato y testigo heredados. La reversa preferida conserva la extensión aditiva en la base. No reescribir contratos ni fechas.
6. Si se requiere retirar SQL, preparar una nueva migración compensatoria desde las definiciones previas verificadas, con guardas de cuerpos/ACL y restauración de las dos huellas. No ejecutar un DROP o restauración ciega sobre cambios posteriores. Se ensayó el rollback transaccional local; no se ha ejecutado reversa en producción.

## Reproducción local

Banco propio `avancecorp-citas-fecha-20261017`, PostgreSQL sin red ni puertos.
`fixture.sql` carga seis casos sintéticos en esquema real; las pruebas se ejecutan
con `CITAS_EVIDENCIA` apuntando al directorio local de evidencia.

```
CITAS_EVIDENCIA=/private/tmp/citas-fecha-comercial-evidencia node supabase/scripts/citas-fecha-comercial/probar-local.mjs
cd app
CITAS_EVIDENCIA=/private/tmp/citas-fecha-comercial-evidencia npm run test:run -- --config scripts/citas-fecha-comercial/vitest.config.mjs
npm run check
npm run test:e2e:docker -- e2e/citas-avance-mensual.spec.ts e2e/citas-gerencia.spec.ts e2e/control-citas.spec.ts --workers=2
```

El primer comando requiere las definiciones anteriores verificadas en el directorio
de evidencia; falla si faltan. No descarga credenciales ni accede a producción.

SQL final SHA256: `e719b2b57008fa63e6d4f13eba1cb2c8bf256cc85159aebd9b24787b0478c883`. Resumen estructurado: `verificacion.json`.
