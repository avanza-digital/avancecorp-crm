# Matriz RLS vigente y activación F8 serializada

## Estado

**SQL INSTALADO Y VERIFICADO el 16/09/2026 a las 10:31 Lima.**
La rama temporal fue eliminada; coste estimado US$0,01632 (no factura).

La reparación local pasa **1.867 aserciones**. La única modificación de producto
es `20260916040442_crm_piloto_f8_activacion_serializada.sql`, **autorizada por
Miguel e instalada como `20260916153100`**. No cambia tablas, firmas, permisos,
banderas, miembros ni datos de clientes. La eliminación auditada de contratos
ya está publicada (backend y web, 78 recursos HTTP verificados); este trabajo
cierra su deuda de validación global. La publicación de Cartera integró el
frontend de eliminación desde `a09ecad`; no se volvió a desplegar en esta sesión.

## Instalación productiva completada

Miguel autorizó «siiii» después de recibir el enlace al SQL concreto. Se promovió
únicamente ese archivo, SHA-256
`e8940bc632e2aa96ff40a0a3ea18eeafac73ac9430f39f3052fba50bc7cd07cf`,
desde Main verificado `bc7a5a8`. [Recibo de producción](PRODUCCION.json).

Solo cambió el cuerpo del trigger privado. Las otras 652 funciones y los 298
registros anteriores del historial conservaron sus huellas. Permanecieron
idénticos 594 contratos, 5.320 cuotas, 26 inversiones neutrales, 496 identidades,
la auditoría de eliminaciones, las banderas y los cuatro miembros del piloto.
F8 conserva OFF; F4/F5/F6 y F3 siguen ON; F7 OFF. Owner, ACL y search_path intactos.

Cartera: estado y lista v1 correctos para **23 cuentas activas** (2 Gerencia,
3 supervisores, 18 vendedores), bajo contexto SQL authenticated y ROLLBACK.
No es navegación humana autenticada ni una eliminación real en producción.
Advisors antes/después: seguridad 272/272 y rendimiento 114/114, sin altas ni
bajas. Se conservan avisos heredados. CI del código `bc7a5a8`: PASS.

## Resultados finales

- **PASS local:** 1.867 aserciones de la matriz completa.
- **Remoto:** 1.865 PASS y un ETIMEDOUT en D-5. El bloque D-5 se repitió completo
  con las mismas expectativas: **28 PASS remoto y 28 PASS local**. La salida
  original conserva exit 1; no se presenta como una corrida completa verde.
- **PASS:** 8 pruebas de concurrencia, 3 de guardas/reversa, 3.632 unitarias,
  194 E2E (26 omisiones existentes), lint, tipos, build y preflights.
- **PASS convivencia con Cartera:** 17 grupos SQL de su suite original en una
  copia local aislada con F8 corregido; mismas funciones de Cartera que producción.
- **Advisors revisados:** ningún hallazgo nuevo atribuible al SQL F8. El aviso
  Auth de contraseñas filtradas también existe en producción antes del cambio;
  no se modifica esa configuración. Persisten advertencias heredadas.

[Acta y huellas](verificacion.json), [salida local](matriz-local.txt),
[salida remota original](matriz-remota.txt), [repetición D-5](d5-remoto.txt),
[compatibilidad Cartera](compatibilidad-cartera.json), [advisors](advisors-delta.json).

La matriz global probó el corte de 651 funciones anterior a la publicación
concurrente de Cartera (producción pasó a 653). Su cambio posterior se cubrió
con los 17 grupos combinados y con la evidencia SQL/Auth/HTTP de
[la publicación de Cartera](../cartera-filtros/PUBLICACION.md). No se afirma
haber repetido la matriz global remota sobre ese segundo corte.

## Qué se corrigió

- Firmas actuales de conversión externa y reserva por persona; reintento idéntico
  idempotente y conflicto si cambia el contenido.
- Permisos administrativos actuales para DNI/correo. La antigua corrección de
  DNI sigue denegada incluso para service_role; no se amplían grants.
- La prueba de correo usa la API vigente y una auditoría ficticia existente;
  ya no omite todo el bloque porque una propuesta retirada nunca se instaló.
- Campos exactos de métricas, llegadas automáticas, referidos con peso 0,15,
  analistas fuera del roster, exclusión de demo y normalización del mes.
- Fixtures explícitos de lead borrado y cliente bancario con identidad canónica;
  reglas SLA, empresas y sello de auditoría presentes en el banco.
- Contraseña del banco pasada por variables PG, para evitar que aparezca en el
  comando de una excepción de psql.

No se sustituyen errores por aprobación ni se excluye el diagnóstico D-19.
D-19 detectó una carrera real: una activación F8 podía leer F3 ON mientras otra
transacción lo apagaba. La activación toma ahora el candado compartido F3
mediante el helper vigente, antes del control F8. Valida el estado confirmado. Si F3 o el control F8 están ocupados, devuelve
P0409 sin esperar: evita el ciclo entre candados y la fila de control ya tomada
por BEFORE ROW. El operador reintenta la activación cuando termina el cambio. El orden coincide con las puertas operativas.

F3 conserva su función de apagado general. Apagarlo después de confirmar una
activación F8 cierra F4/F5/F6. Apagar F8 continúa permitido con F3 OFF y con
REPEATABLE READ. La función sigue privada, SECURITY DEFINER, owner postgres,
search_path vacío y sin EXECUTE para anon/authenticated/service_role/PUBLIC.

## Verificación reproducible

La matriz se ejecuta únicamente en una instancia propia, desechable y con
clientes ficticios. Nunca utilizar las credenciales productivas.

**Cada ejecución comienza con esquema/configuración restaurados y seed nuevo.**
No ejecutar la matriz dos veces sobre el estado final de la primera: deja
historial inmutable y fixtures auxiliares por diseño (ver `../LEEME-seed.md`).
La precondición global comprueba ahora el censo de leads activos y falla de inmediato
si quedaron restos, antes de ejecutar la matriz o cambiar banderas.

1. Exportar **solo esquema** de la base vigente (`public,crm,private`); conservar
   comentarios con `supabase db dump --keep-comments`. No restaurar datos de
   clientes. El replay histórico de ramas nuevas falla; reconstruir el esquema
   actual exclusivamente en la rama propia vacía.
2. Copiar configuración sin personas: empresas, SLA y etapas/operación,
   enfriamiento, rentabilidad vigente/hitos, producto legacy, pesos de conversión,
   control SLA, banderas sintéticas y catálogos/sello de auditoría. Contrastar
   funciones, ACL y search_path. Este ensayo comparó 651 funciones; dos MD5
   difieren solo por comentarios omitidos por el exportador (ver paridad).
3. Aplicar la candidata. Preparar `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
   `SUPABASE_SERVICE_ROLE_KEY`, `CRM_DEMO_PASSWORD`, `CRM_BANCO_PSQL_URL` en un
   archivo privado. La clave de servicio solo prepara/limpia fixtures y prueba
   su frontera de actor; los permisos de usuarios se miden con sesiones reales.
4. Ejecutar `seed-demo.mjs`. El seed requiere lectura de `crm.periodos_cerrados`:
   concederla a service_role únicamente durante la preparación y revocarla antes
   de las aserciones. Construir la baja histórica de vendInactive según
   `../LEEME-seed.md`, con su trigger de jerarquía restaurado antes de probar.
   Restaurar también el trigger diferido vigente de Auth para correo, ausente
   de una exportación limitada a los tres esquemas.
5. Desde `CRM-Avance-Corp`, con las variables del banco cargadas:

```sh
npm run seed:preflight
npm run test:rls:preflight
npm run check:scripts
npm run test:edge-preflight
npm run test:rls
```

La sonda de borrados restaura solo su fixture fuera de las aserciones. Ninguna
policy, candado ni trigger queda desactivado durante las pruebas de permisos.
El banco sintético no contiene meses cerrados; esa rama de metas retroactivas
no se ejercita en esta matriz. No se interpreta como evidencia de ese escenario.
La prueba positiva completa de correo con Auth vive en `../correo-admin/`.

Para repetir exclusivamente D-5 tras un problema de transporte:
`node supabase/scripts/test-rls.mjs --identidad-d5`. Este alcance crea su propio
lead y restaura el estado F3 previo; admite un banco usado sin omitir las demás
precondiciones de usuarios/fixtures. Su resultado no sustituye la matriz global.
No hay reintentos automáticos de peticiones mutantes.

## Regresión de concurrencia

Preparar dos bases **locales vacías** con el esquema vigente, incluido Auth,
llamadas `rls_f8_locks_<identificador>`. En una conservar la función original;
en otra aplicar la candidata. No reutilizar una base ya sembrada por esta suite.
Con `CRM_BANCO_PSQL_URL` apuntando a cada una:

```sh
node --test supabase/scripts/rls-vigente/f8-candado.test.mjs
```

Original: **3 PASS / 5 FAIL**; candidata: **8 PASS / 0 FAIL**. La suite coordina
dos conexiones por `pg_locks`, no infiere concurrencia de una pausa fija.
Cubre activación válida, apagado F3 concurrente, apagado posterior, desactivación
F8 con aislamiento superior, colisión F4, dos transacciones mixtas y bloqueo
de DELETE. `guardas.test.mjs` añade reversa/reinstalación, deriva de configuración
y trigger deshabilitado; cada ensayo se revierte. `npm run test:rls:f8` ejecuta
las dos suites; `check:scripts` también comprueba su sintaxis.

## Instalación y reversa

El [SQL autorizado](../../migrations/20260916040442_crm_piloto_f8_activacion_serializada.sql) ya está instalado; no repetirlo.
La instalación exige MD5 de la definición previa completa
`47585a27b991a442bb09b3477be5f224` y comprueba
el nuevo cuerpo `201a4b2fd6d062d7930e673d9986f5de`, owner, configuración y ACL.
No requiere regenerar tipos: solo cambia el cuerpo de un trigger privado.

`reversa.sql` exige el MD5 de la candidata y restaura literalmente el cuerpo
anterior. Reintroduce la carrera conocida; solo usar por una regresión confirmada.
No fusionar la rama de ensayo completa: contiene reconstrucción y datos ficticios.
Promover exclusivamente la migración revisada, conforme al procedimiento del
proyecto, y comprobar que ninguna bandera ni dato de negocio cambió.
