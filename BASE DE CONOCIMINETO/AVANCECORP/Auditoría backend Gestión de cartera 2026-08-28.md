---
tags: [crm, gestion-cartera, backend, autorizacion, rls, auditoria]
actualizado: 2026-08-29
estado: candidata-corregida-verificada-no-desplegada
migracion: 20260828210351_crm_gestion_cartera_autorizacion_integral.sql
---

# Auditoría backend de Gestión de cartera — 2026-08-28

**Estado: CANDIDATA CORREGIDA, AUDITADA Y VERIFICADA EN ENTORNO DESECHABLE · NO
DESPLEGADA.** Producción permanece intacta sobre
[[Checkpoint C0.1 nucleo unico 2026-08-28 R5]]. La migración nueva no se ha
aplicado ni registrado en el historial remoto y el frontend productivo no se
ha sustituido. Esta nota continúa [[Cierre Mi cartera operativa 2026-08-25]] y
no constituye autorización de despliegue.

## Motivo y alcance

La auditoría encontró una diferencia entre la semántica de negocio y algunas
rutas de autorización del backend: una cuenta Portal Directorio podía quedar
modelada como Gerencia en `crm.equipo`; Supervisor podía listar su árbol pero
fallar al abrir detalle o crear una tarea por dependencias indirectas de la
RLS de `public.perfiles`; y un cliente todavía no asignado podía desaparecer
del ámbito aunque hubiese sido creado por un Analista autorizado. La numeración
automática de contratos también usaba `max() + 1`, vulnerable a carreras. Una
pasada formal de seguridad detectó además que Directorio recibía el domicilio
legal en la nueva RPC de detalle; el candidato quedó corregido para entregar a
ese rol únicamente identidad y contacto mínimos.

El candidato corrige esos límites sin ampliar capacidades comerciales. Está
relacionado con [[Acceso y roles del CRM]], [[Rol Directorio]],
[[Cuentas bancarias - ledger vs casillas del perfil]] y [[Número de contrato]].

## Invariantes que deben permanecer verdaderas

- **Analista:** ve y gestiona únicamente su cartera; el fallback por
  `creado_por` solo recupera clientes no asignados dentro de su ámbito.
- **Supervisor:** ve y gestiona únicamente la cartera de su árbol, puede abrir
  el detalle y crear tareas de esos clientes, y no ve clientes de otro árbol.
- **Gerencia:** conserva el alcance global operativo vigente.
- **Directorio:** lee identidad y contacto comercial mínimos globales; no
  recibe domicilio ni banca, no crea tareas, contratos ni gestiones, y no puede ser promovido
  accidentalmente a Gerencia por una desalineación entre Portal y CRM.
- **Coordinador, usuario inactivo y anónimo:** no adquieren acceso de cartera
  por este cambio.
- **Banca:** solo se consulta después de recibir una capacidad fresca del
  detalle seguro; una caché anterior del navegador no habilita la llamada.
- **Fuera de ámbito:** el detalle devuelve cero filas, sin distinguir entre un
  cliente inexistente y uno no autorizado.
- **Contratos:** la numeración conserva el formato y unicidad actuales, pero las
  altas concurrentes se serializan en el servidor.

## Controles del candidato

1. `private.rol_crm(uuid)` queda fail-closed ante combinaciones Portal/CRM
   incompatibles y el trigger de `crm.equipo` mantiene el invariante en las
   escrituras futuras.
2. `private.cliente_ids_visibles_crm()` concentra el alcance de clientes para
   lista, detalle y tareas, evitando reglas paralelas que puedan divergir.
3. `crm.cliente_detalle_fn(uuid)` es la única puerta nueva del frontend al
   detalle: aplica ámbito, redacta domicilio y banca para Directorio y evita
   consultar directamente `public.perfiles`.
4. `private.puede_gestionar_tarea_cliente(...)` valida cliente y ámbito de
   escritura; `private.puede_asignar_destino_tarea(...)` autoriza la pareja
   técnica Analista/Supervisor que el trigger deriva antes de evaluar la policy.
5. `private.siguiente_numero_contrato(integer)` usa advisory lock por año; la
   restricción única sigue siendo el último candado.
6. Las funciones privilegiadas fijan `search_path = ''`; los helpers privados
   permanecen fuera de la API y `PUBLIC`/`anon` no reciben ejecución sobre la
   RPC de detalle.
7. El preflight fija las huellas de los cuerpos productivos relevantes y la
   policy `tareas_insert` en sus dos formas históricas conocidas; la migración
   aborta ante drift o una normalización de roles ambigua.

## Evidencia obtenida sin modificar producción

- Se leyó el catálogo productivo y se fijaron huellas de las funciones que la
  migración reemplaza. La inspección fue de solo lectura.
- La migración exacta se aplicó sobre un esquema completo temporal y cerró su
  postflight. El replay convergió desde la forma versionada de 10 columnas y la
  captura viva de 12 columnas de `crm.clientes_basicos_fn`; también aceptó las
  dos formas conocidas de `tareas_insert`. Un mutante de esa policy fue
  rechazado por el preflight antes de ejecutar DDL.
- Gate integral nuevo: `GESTION_CARTERA_AUTORIZACION_TX_OK`.
- Compatibilidad: `CREAR_CONTRATO_CARTERA_OK`,
  `GESTION_CLIENTES_RENOVACIONES_OK`, `TAREAS_TX_OK`,
  `CARTERA_KEYSET_TX_OK`, `PERIODO_COMERCIAL_CONTRATOS_OK` y
  `REPORTE_DERIVACIONES_TX_OK`.
- Las pruebas reales de concurrencia usan únicamente bases cuyo nombre cumple
  el token estricto `gcar_*`, rechazan query/hash en la URL y neutralizan las
  variables de entorno de libpq. Cada terminación forzada exige simultáneamente
  PID, aplicación, base, usuario y tipo `client backend`; nunca mata por un
  nombre compartido.
- El runner de contratos creó dos números automáticos distintos y consecutivos,
  observó explícitamente el mutex y su espera, y limpia solo los UUID devueltos
  por sus RPC. Los runners de tareas y derivaciones fabrican sondas UUID propias;
  la limpieza de cada uno se limita a esos identificadores y falla en cerrado
  ante una identidad desconocida, en vez de ampliar un `DELETE`.
- La carrera de tareas no acepta una espera de lock cualquiera: comprueba que
  `pg_blocking_pids(S2)` contiene el PID exacto de S1 antes de considerar
  ejercitada la serialización tarea/reasignación.
- Los tres runners ejercitaron primero una falla inyectada y luego su carrera
  positiva sobre un clon desechable, bajo variables `PG*` deliberadamente
  hostiles. El vector integrado de 19 conteos globales fue idéntico antes y
  después (`13|13|40|18|59|0|28|28|41|56|0|0|1|0|2|0|4|4|604`) y quedaron
  cero sesiones rastreadas; el clon fue eliminado.
- La matriz completa por Data API/PostgREST cerró **1.192/1.192** aserciones:
  Analista, Supervisor, Gerencia, Directorio, Coordinador, inactivo y anónimo.
- `db lint` sobre `crm`, `private` y `public` terminó con código 0 y sin errores;
  los avisos restantes pertenecen a funciones históricas no modificadas. El
  lint global también informa un error dentro de la extensión administrada
  `realtime`, fuera del candidato.
- Rendimiento observado con RLS real en el clon: lista de Supervisor 1,924 ms,
  detalle de Supervisor 3,443 ms, lista de Directorio 0,802 ms y detalle de
  Directorio 1,511 ms.
- Verificación del frontend candidato: lint, typecheck y build verdes; 182/182
  archivos y 2.439/2.439 pruebas unitarias; Playwright completo con 110
  aprobadas, 26 omitidas por diseño y 0 fallas.
- El gate de scripts pasó 12/12 pruebas Edge de importación, 71/71 unitarias y
  63/63 E2E del bridge, y mató 32/32 mutantes; el preflight de domicilio/banca
  pasó 30/30.
- El escaneo formal `0e12f638-1ff3-4e08-a49d-5606320c3159` encontró un MEDIUM
  de privacidad: Directorio podía recibir el domicilio por
  `crm.cliente_detalle_fn`. Se corrigió con redacción server-side y una
  verificación independiente lo clasificó **fixed**: Directorio obtuvo una fila
  con domicilio y banca nulos; Supervisor y Gerencia conservaron domicilio y
  banca; un Analista ajeno obtuvo cero filas.
- Las revisiones adversarias posteriores también cerraron falsos verdes en los
  runners de concurrencia y en el fixture de renovaciones. La selección vacía
  del fixture ahora falla con `GCAR-F01` y todos sus efectos se prueban y
  revierten.
- Huella final de la migración:
  `18df2b2a048b7404a857f743874294dddad589724ae55c9aa5c2e13e585a1af8`.
- Advisors productivos de línea base: 0 errores. Sus avisos son preexistentes y
  no sustituyen una lectura posterior al despliegue.

## Orden de despliegue obligatorio

Este cambio es **server-first** porque el frontend nuevo llama a
`crm.cliente_detalle_fn`:

1. Capturar dry-run e historial remoto y comprobar que solo se propone la
   migración autorizada.
2. Aplicar la migración al servidor y leer de vuelta versión, cuerpos, ACL,
   RLS e invariantes del postflight.
3. Ejecutar `notify pgrst, 'reload schema'` y comprobar que la RPC resuelve por
   API; un anónimo debe llegar al muro de permisos, nunca a `PGRST202`.
4. Repetir advisors y los smokes de backend por rol.
5. Solo entonces compilar/publicar el frontend exacto del candidato.
6. Ejecutar smokes autenticados de Analista, Supervisor, Gerencia y Directorio,
   incluida redacción bancaria y ausencia de escrituras para Directorio.

Publicar el frontend antes del servidor dejaría el detalle apuntando a una RPC
inexistente y se considera un orden inválido.

## Pendiente para publicación

El cierre técnico local está completo. Con autorización explícita futura aún
corresponden: dry-run remoto, aplicación server-first, readback/postflight,
advisors posteriores, publicación del frontend y smokes productivos.

El estado correcto sigue siendo **candidata auditada, no desplegada**. Nada de
esta nota afirma que el arreglo ya esté operativo en producción.
