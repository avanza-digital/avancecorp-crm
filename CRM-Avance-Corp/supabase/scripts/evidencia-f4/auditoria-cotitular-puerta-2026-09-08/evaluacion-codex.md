# Evaluación PRIMARY — cierre del auxiliar de cotitulares

La primera consulta terminó sin un VERDICT válido; se conserva el error, no se
considera una revisión completada. La segunda devolvió CHANGES_REQUESTED. Ambas
entradas y el informe están archivados. No se pidió una tercera opinión.

## Resultado y decisiones

**Defecto confirmado en copia del banco:** anon sin JWT pudo sustituir
cotitulares de un contrato aún no congelado. El ensayo hizo rollback. El
auxiliar SECURITY DEFINER no autorizaba por sí mismo y tenía EXECUTE explícito
para los tres roles de API. No se probó ni se modificó producción.

- **P1 aceptado:** el módulo ahora exige como postcondición que no quede EXECUTE
  explícito para nadie salvo su propietario ni efectivo para los roles API.
  Se ensayaron un grantee adicional (`crm_metricas_bridge`) y un ejecutor con
  EXECUTE pero sin derecho a revocar: ambos hacen fallar la transacción. Precisión
  sobre el informe: un ejecutor sin ningún privilegio ya recibe error de REVOKE;
  el caso que puede advertir sin cerrar es el que tiene privilegio sin grant option.
  El primer intento de fixture usó el primero y se corrigió para probar el segundo.
- **P2-a aceptado en alcance:** `verificar-estructura.mjs` conserva la comprobación
  de los tres roles en el gate permanente. El catálogo local confirma privilegios
  predeterminados de funciones en public para esos roles, tanto para postgres
  como para supabase_admin. No se cambian globalmente: también soportan RPC
  públicas legítimas. Cualquier recreación del auxiliar debe cerrar su ACL en
  la misma transacción. La auditoría de otros auxiliares es otro alcance.
- **P2-b parcialmente aceptado:** se mantiene el MD5 de la definición completa,
  coherente con todas las guardas de la candidata F4. Esta candidata exige la
  base revisada y reconstrucción final sobre el motor autorizado; no promete
  portabilidad a otro motor sin revisar. El mensaje ahora muestra MD5 observado
  y menciona cuerpo, atributos y versión PostgreSQL. Comparar solo prosrc sería
  insuficiente sin todas las guardas de atributos; no se debilitó el control.
- **P2-c comprobado:** `pg_depend` no devuelve dependientes del helper. Eso no
  demuestra que carezca de llamadores: PL/pgSQL no registra todas sus llamadas
  textuales allí. El inventario de cuerpos encuentra crear/actualizar contrato;
  la búsqueda ampliada en app, portal, edges, scripts y automatización encuentra
  definiciones históricas, stubs de test, comentarios y tipos, sin otro cliente
  directo. No hay telemetría de clientes externos; revisión previa al despliegue
  sigue pendiente, sin tratar la ausencia en pg_stat_statements como prueba total.
- **P3-a:** se añadió prueba HTTP real local para los tres roles, con denegaciones
  42501/PGRST202 aceptadas según cómo exponga PostgREST el catálogo. Usa UUID
  inexistente, de modo que un fallo de la prueba no cambia un contrato. No se
  eliminan manualmente tipos generados: la función sigue en pg_proc, y revocar
  ACL no cambia su firma ni garantiza que desaparezca de la introspección hecha
  como propietario. La regeneración integral de tipos pertenece al cierre G4.
- **P3-b/c aceptados:** aserción de denegación por SQLSTATE/nombre y comprobación
  de `creado_por` con el actor Gerencia, tanto en alta como en corrección.
- **P3-d verificado:** el auxiliar tiene `search_path=public, pg_temp`, propietario
  postgres y SECURITY DEFINER. Se conserva su cuerpo/atributos; esta modificación
  no es un rediseño del auxiliar ni de su búsqueda de nombres.

## Verificación y límites

PASS: nueve grupos SQL después de la corrección, tres denegaciones HTTP locales,
instalación ACL local y comparación de 37 cuerpos con la candidata, nueve módulos
y cinco tablas cerradas al acceso API. Alta/corrección autorizadas siguen usando
el auxiliar internamente; PDF congelado sigue rechazando la edición. Cuerpos
del auxiliar y sus dos puertas conservados; no se cambió contenido PDF.

La instalación inicial y sus pruebas de siete grupos se conservan como evidencia
anterior. Las capturas posteriores identifican el módulo con postcondición y
nueve grupos. No se atribuye a Claude aprobación de cambios posteriores.

NOT RUN: despliegue, telemetría productiva, reconstrucción final y tipos de toda
F4. No se implementa con esto la cotitularidad neutral: este cierre de permiso
es su prerrequisito. G4 permanece abierto.
