---
fecha: 2026-09-14
estado: reanudado-publicacion-en-preparacion
tags: [crm, citas, gerencia, metas, release]
---

# Citas Gerencia — decisiones finales para publicar

Miguel autorizó el deploy («ok hagamos deploy»), sustituyendo la instrucción
previa de preparar sin publicar. Después confirmó las tres reglas pendientes de
[[Citas Gerencia - avance integrado sin deploy 2026-09-13]].

- **Clientes / personas distintas entrevistadas.** La meta del 70% significa
  que, de cada 10 personas entrevistadas, 7 se conviertan en clientes. Aunque esas
  personas sumen 15 entrevistas por visitas repetidas, el resultado es 70%.
  Las 15 entrevistas siguen contando como actividad. Miguel confirmó «ok sii
  asi es» después de explicar este ejemplo comercial. Configuración:
  `base_depositos = personas_entrevistadas`.
- **Mes del evento.** Si la entrevista o conversión ocurre en octubre, cuenta
  en octubre aunque el lead se haya asignado en septiembre.
  `mes_resultado = evento`.
- **Analista del evento.** El resultado corresponde al analista que lo obtuvo,
  aunque otro haya recibido inicialmente el lead.
  `analista_resultado = evento`.

Se mantienen la meta interna 1,25 citas por lead, los objetivos 70/70, manuales
incluidos, cada cita atendida como entrevista, conversión nativa como cliente y
ticket real por analista y mes. Véase
[[Citas Gerencia - reglas confirmadas y propuesta revisada 2026-09-13]].

Los valores iniciales del editor incorporan las tres respuestas. Esto no aplica
automáticamente una versión: el mes de vigencia y la aplicación auditada siguen
en el servidor. La vigencia de septiembre de 2026 se prepara para este deploy;
no se presenta como una respuesta adicional de Miguel.

La tabla y la exportación muestran todos los clientes del periodo, incluso si
su entrevista fue en otro mes o la realizó otro analista. La tasa del 70%
mantiene su base comparable de personas entrevistadas por el analista en el
periodo; los otros cierres se distinguen en el detalle. Si varios leads están
vinculados a una misma persona canónica (o perfil cuando no hay ese vínculo), esa identidad cuenta una sola vez en las
personas entrevistadas y en los clientes; las entrevistas siguen sumándose.

La publicación permanece en preparación hasta verificar el banco, los gates,
la configuración aplicada y el artefacto del mismo commit que `avancecorp/main`.
Esta nota no acredita que se haya desplegado.

## Pausa solicitada el 14/09/2026

Miguel pidió «pon en pausa el trabajo e un momento seguro». **Trabajo pausado**:
no continuar ni publicar hasta que solicite retomarlo. No hubo cambios de
producción, deploy, push ni commit en esta sesión. Los cambios están guardados
en disco, pendientes de commit. Las comprobaciones en curso terminaron y el
PostgreSQL local desechable se cerró mediante el `finally` del test.

Main local y la última referencia consultada de `avancecorp/main` están en
`b5ca1eb92110dc997ec491ef1ff177aa195daaf5`. Al retomar, volver a hacer fetch y
conciliar cambios remotos antes de preparar el artefacto. Conservar los dos
archivos ajenos sin incorporar: la propuesta de rentabilidades menores a 15 y
la evidencia F7 `2026-09-11T20-20-59-444Z.json`.

Verificación completada:

- `npm run check`: **PASS**, 243 archivos / 3518 tests, lint, tipos, build,
  bundle y duplicación. Log privado `check-definitivo.log`.
- E2E integral anterior: **179 PASS / 26 SKIP** (`check-entrega.log`). La última
  corrección de identidad y el orden de las columnas CSV son posteriores al
  arranque de esa corrida; queda repetir únicamente los E2E afectados.
- SQL mensual nativo e identidad canónica: **PASS**, transacciones revertidas.
  El segundo prueba un estado histórico de fusión sintético, preparado con la
  válvula interna sólo en el banco; la lectura se verifica con la válvula cerrada.
- Configuración local/concurrencia: **PASS**. Auth/PostgREST: **48 PASS**,
  configuración de prueba con vigencia 2099-01 y Superadmin sintético inactivo.
- `check:scripts`, `seed:preflight`, `test:rls:preflight` y
  `test:edge-preflight`: **PASS**. Los dos preflights usan el entorno del banco.
- Matriz RLS general: **FAIL** en referencia y candidato, ambos 49/1827.
  La referencia se contrastó con el esquema de producción y se restauró la misma
  semilla. La comparación textual conserva dos diferencias en fechas relativas
  por cruzar medianoche, en los mismos casos R2; documentar la comparación por
  caso antes de decidir el gate de publicación. No presentar el RLS global como PASS.

Estado de la rama Supabase propia `citas-validacion-20260912`
(`xhgsjtzpmwlqfkninphl`, id `07531654-e80e-47ef-ac36-02ce61d93d41`):
las cuatro migraciones previas y la nueva
`20260914044939_crm_citas_identidad_personas.sql` están ensayadas. Huella final
del lector `4ad2b90baf96b11b63a626122bd5d64b`; censo **34 declarados / 30 sujetos al
techo / 4 auxiliares / 0 sin declarar**. Capital conserva
`c9e58c1da9dd7a5d52991c9e47dc19d5`. La rama tiene 294 registros de migración:
279 iguales a producción y **15 registros de ensayos**. **No fusionar así**:
respaldar y normalizar sólo el historial de la rama con `migration repair`,
conservando los 279 originales y registrando únicamente las cinco migraciones
canónicas. Esta normalización NO se ejecutó antes de la pausa.

Dos revisiones de Claude fueron evaluadas. Sus hallazgos de identidad,
deduplicación de clientes/ticket y colaboración entre analistas se corrigieron
y probaron; sus dictámenes originales siguen siendo `CHANGES_REQUESTED`.
No generar una tercera consulta automática para buscar un PASS.

Para retomar faltan: cerrar la evidencia de no regresión RLS, E2E afectados y
advisors; normalizar el historial del banco; documentar la resolución de las
revisiones; commit y sincronización con Main; artefacto desde un clon limpio;
merge de rama Supabase, aplicación auditada de reglas y deploy Hostinger con
verificación HTTP. El control productivo sigue sin tablas ni versión aplicada.
La última versión pública comprobada es `build-20260913T230629516Z` / `9bd86c3`.

Evidencia y helpers privados (no contienen material que deba subirse al repo):
`/private/tmp/citas-deploy-20260914/` y
`/private/tmp/citas-publicacion-20260912/`. El helper `banco.py` impide escrituras
al padre. `hostinger.mjs` usa el conector de hosting existente, ya verificado
en lectura para `crm.miavance.com`; no se llamó a deploy. Las credenciales
permanecen sólo en archivos privados, nunca en esta nota ni en logs compartidos.

Relacionado: [[Main unico - sincronizacion y publicacion 2026-09-04]],
[[Citas Gerencia - control de Superadmin en borrador 2026-09-11]].

## Reanudación posterior del 14/09

Miguel indicó «sigue» y confirmó que la sesión F8 sigue trabajando. Citas se
prepara en `/private/tmp/citas-reanudacion-20260914/repo`, clon de Main, para no
interferir con ese PRIMARY. La publicación final espera su cierre operativo.
El historial del banco se normalizó: cinco candidatas canónicas y las 279
entradas anteriores intactas. Tras instalarse F8 en el padre, se alinea el banco
con F3 ON (su semilla estaba OFF) y se rebasean sus dos migraciones nuevas.
No se modifican banderas ni datos productivos desde la sesión Citas.

El gate frontend tras integrar Main pasó: 243 archivos y 3519 tests. Nueve E2E
afectados PASS. Comparación RLS por nombre/multiconjunto: mismos 49 casos,
cero aserciones nuevas, sin presentar la matriz general como PASS. La evidencia
vigente está en `UX-UI-GERENCIA/citas-publicacion-2026-09-14/`.
