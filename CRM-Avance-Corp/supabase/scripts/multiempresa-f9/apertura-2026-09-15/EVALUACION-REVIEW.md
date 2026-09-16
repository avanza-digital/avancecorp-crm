# Evaluación de Codex PRIMARY

Revisión 1 de Claude: **CHANGES_REQUESTED**. Se conserva íntegra en
[revision-1/REVISION-CLAUDE.md](revision-1/REVISION-CLAUDE.md), junto a los SQL y
recibo que revisó. La respuesta de Claude no es una autorización productiva.

- **P1, reversa con operaciones nuevas: aceptado y corregido.** El ensayo crea
  una persona COOPAC y confirma dos inversiones F4 (Prodelco/Qorilazo) con rol
  analista por `preparar_inversion_fn`/`confirmar_inversion_revisada_fn`. Después
  ejecuta REVERTIR y conserva las huellas de 18 superficies, incluidas solicitudes,
  inversiones, titulares, hechos, perfiles y objetos Storage. Cero fuentes sin
  identidad coherente; 24 cuentas deshabilitadas conforme a su rol.
- **P1, inversión de orden de candados: hipótesis refutada.** La definición
  productiva de `private.postventa_modo()` empieza por
  `resolver_en_puertas_bajo_candado()` (F3), después toma filas `FOR SHARE NOWAIT`.
  No empieza por un candado advisory F6. Se conserva el orden F3 exterior.
  Una consulta real de postventa retenida en otra conexión hace abortar REVERTIR
  con 55P03, sin estado parcial; al terminar la consulta la reversa pasa.
- **P2, duración: aceptado y corregido.** Una lectura productiva de las 614
  fuentes tomó 96,188 ms. Se reduce el ensayo previo al COMMIT a un representante
  por cada uno de los cuatro roles; las 24 cuentas completas van en POSTFLIGHT,
  sin candados exclusivos. Banco: 64,267 ms con candados, 40,374 ms en las
  cuatro pruebas. No se extrapola ese tiempo local como medición productiva.
  La apertura aborta si su ventana de candados supera tres segundos.
- **P2, lectores globales: verificado.** `es_lector_global()` corresponde a
  Directorio activo (membresía válida o fallback sin membresía). Producción tiene
  **cero** cuentas en esa población al corte 16/09 01:45 UTC. Se guarda y verifica
  esa población dentro de ACTIVAR. Directorio futuro sigue en su alcance de
  lectura Avance establecido; no recibe escritura ni postventa. Matriz sintética
  de Directorio ya acreditada en G7.
- **P2, reversa de un uso: aceptado/documentado.** Apaga F4/F5/F6; no restaura
  el piloto, no borra operaciones y no permite reabrir con la misma captura.
  Otra apertura requiere revisar el estado nuevo y preparar otro artefacto.
- **P2, venta concurrente: limitación deliberada.** La comparación de fuentes
  es conservadora bajo READ COMMITTED. Una venta legítima entre ambas lecturas
  puede abortar todo. Se revisa la causa y se recaptura; no se elimina la guarda
  ni se repite a ciegas. El tramo se acortó a cuatro representantes.
- **P2, recibo anterior al COMMIT: corregido.** El estado interno se llama
  VALIDADO_ANTES_COMMIT. El recibo PASS se emite únicamente después del COMMIT y
  de releer las banderas/control. La reversa también relee después del COMMIT.
  Luego se exige una lectura productiva independiente, POSTFLIGHT y conciliación.
- **P3, funciones nuevas: corregido.** Guarda de ausencia de firmas fuera del
  catálogo de 608 funciones crm/private; comparación íntegra de 211 funciones
  pertinentes (cuerpo, dueño y permisos). La copia contiene 567 de esas firmas,
  sin firmas extra; no se afirma paridad total de 608 cuerpos. Una función nueva
  introducida en el ensayo aborta la apertura.
- **P3, errores F6: corregido.** Se registra SQLSTATE y actor antes de abortar.
- **P3, autoría y hashes: aclarado.** `actualizado_por` usa a Carlos como
  responsable operativo declarado; el motivo identifica autorización de Miguel
  y ejecución administrativa de Codex. No hubo sesión ni firma de Carlos. Los
  hashes de UUID son identificadores de evidencia, no anonimización irreversible.
- **P3, fixture y alcance: aclarado.** Solo el preparador local omite temporalmente
  validadores para fijar la revisión/fechas y apartar equipo sintético anterior;
  quedan habilitados antes de cada prueba. Metadatos Storage locales no prueban
  una subida HTTP. Las capacidades productivas se comprueban leyendo funciones;
  no se crean inversiones ni se simulan firmas financieras en producción.

Verificación de esta revisión: **13 escenarios SQL PASS**, `check:scripts` PASS,
sintaxis Node de los scripts F9 PASS. El primer postflight local rechazó READ ONLY
porque las funciones usan FOR SHARE (25006); se corrigió a READ COMMITTED con
ROLLBACK, igual que el verificador G7, y se repitió el ensayo completo.

## Revisión final y resolución

Se conserva [el segundo CHANGES_REQUESTED](REVISION-FINAL-CLAUDE.md). Claude
descarta P0/P1 en el SQL; condiciona la operación al canal y verificaciones
productivas que no tenía adjuntos. Revisó las plantillas del commit `b8110e6`
y la primera ampliación de 13 escenarios; el cierre incorpora 17. No se realiza
una tercera consulta para cambiar el dictamen. Codex resuelve con evidencia:

- **Canal:** Supabase MCP `execute_sql`, proyecto fijo `dctqcbznekcyxhjujuci`.
  Prueba inocua sin DML: transacción 174204 → COMMIT → transacción 174205,
  mismo backend, cambio real de transacción. Otra llamada con división por cero
  devuelve ERROR 22012 y no un recibo PASS. El resultado se considera fallido
  ante cualquier error y se exige lectura independiente posterior antes de
  declarar activación. No se presupone un comportamiento del pooler/SDK.
- **Recibo anterior:** ACTIVAR ahora empieza con `SET f9.resultado='{}'`, sin
  depender de sesión nueva ni poder usar el recibo de un intento anterior.
  Se conserva la comprobación de estado posterior al COMMIT.
- **Tiempo:** el preflight productivo de los SELECT de catálogo, equipo, roles,
  lectores, control y triggers mide **35,475 ms**. Las fuentes midieron 96,188 ms.
  `statement_timeout='3s'` limita efectivamente la sentencia crítica; inyectar
  `pg_sleep(4)` después de tomar F3 aborta con 57014 alrededor de los tres
  segundos, conserva estado/datos y no espera a la comprobación final.
- **Frescura:** nuevo preflight 16/09 02:04:26 UTC coincide con config en las
  211 funciones, 608 firmas, 8 triggers, 24 cuentas, miembros/control y lectores.
  Conciliación 01:57:37 UTC: 614 fuentes y cero incoherencias/diferencias.
  Config no se recapturó ni se alargó: vence 03:45:31 UTC. Se reensayaron los
  bytes finales tras endurecer el tiempo/recibo, con huellas SHA256 nuevas.
- **Reversa:** sigue siendo apagado total F4/F5/F6, también para los cuatro
  participantes iniciales. Sus guardas se conservan. No se agrega una reversa
  sin condiciones ni se restaura automáticamente un piloto; ante configuración
  distinta se inspecciona el estado y se prepara una instrucción apropiada.
  REVERTIR no caduca; quien vence el 21/09 es el piloto original.
- **Auditoría de pruebas:** ambas RPC son VOLATILE por defecto; eso no acredita
  escrituras. Sus cuerpos y las llamadas de autorización/control no invocan el
  registro de acceso. Además, el ensayo compara `public.audit_log` completo para
  filas con `usuario_id` antes/después del COMMIT y del postflight: huella idéntica.
  La configuración se audita administrativamente, sin atribuir solicitudes a
  las cuatro cuentas usadas para comprobar capacidades.
- **Postventa ampliada:** un analista fuera del piloto crea una solicitud de
  retiro por la RPC; Coordinación recibe 42501. La reversa conserva esa solicitud
  y dos inversiones F4 confirmadas, junto a las **19 superficies** verificadas.
- **Otros P3:** catálogo de firmas nuevas limitado a crm/private; funciones
  public pertinentes sí comparadas por cuerpo/ACL/dueño. Se rechazan delimitadores
  dollar-quote en el generador. POSTFLIGHT se ejecuta secuencialmente; un conflicto
  de configuración exige leer el estado antes de atribuirlo a permisos. Las ACL
  actuales no contienen nombres con comas; no se generaliza ese parser.

[Evidencia del canal, funciones y preflight](verificacion-final-previa.json).
Frontend publicado cotejado por cuatro recursos HTTP 200 y llamadas de banderas.
**17 escenarios SQL PASS**; scripts generales y sintaxis PASS. Pendiente de
ejecutar en producción y verificar después. G8 sigue abierto.
