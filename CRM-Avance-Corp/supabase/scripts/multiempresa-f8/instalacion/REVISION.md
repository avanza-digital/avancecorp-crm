# F8 — revisión del procedimiento de instalación

Codex PRIMARY; Claude SECONDARY_REVIEWER mediante `scripts/claude-review`, sin
herramientas, modificaciones ni delegación. Dos consultas acotadas. Se adjuntó
el protocolo, evidencia saneada, notas de CodeGraph, código y resultados reales.

## Dictámenes y decisiones

[Primera revisión](revision-claude.txt): **CHANGES_REQUESTED**. Se aceptaron:

- Limpieza verificable del replay parcial solo en la rama desechable y ledger
  vacío antes de restaurar; error fatal ante fallos de restauración. No ejecutar
  `DROP SCHEMA CASCADE` a ciegas ni afectar schemas administrados.
- Inventario F8 nuevo, conservando los scripts históricos F5: default ACL,
  estado de triggers, política restrictiva, tipos/precisión, dueños, enums,
  secuencias, extensiones, publicaciones y event triggers.
- Precondiciones F8 automáticas y recientes; 14 ACL exigidas, incluida la ACL
  NULL preexistente del trigger. Marca demo NULL rechazada.
- Procedencia del campo `proyecto` declarada: lo añade el ejecutor desde el ref
  usado en MCP; no es una atestación PostgreSQL ni criptográfica.
- Modo de publicación explícito, comparación del artefacto efectivo de Edge y
  configuración, conservación de dumps fuera de Git y cierre de temporales.

Se aceptó detenerse ante avance del historial, pero **se rechazó renombrar
migraciones comprometidas como solución automática**. El proyecto exige
inmutabilidad. El ciclo anterior F5 documenta versiones asignadas por MCP
distintas del nombre local: registrar el mapeo y comprobar el orden remoto real;
si se necesita otro SQL, prepararlo y presentarlo antes de aplicarlo.

[Segunda revisión](revision-claude-2.txt): **CHANGES_REQUESTED**. Claude no encontró
un falso PASS del padre ni un bloqueo para presentar el SQL. Señaló dos P2 antes
del ensayo de paridad, corregidos por el PRIMARY:

- `comprobarParidad`/`--paridad-rama` comparan automáticamente las 15 categorías,
  comprueban ambos destinos y su ventana, y registran SHA de los JSON. La base
  del ensayo se define como el JSON del padre ligado a ese recibo. La captura
  actual debe ser posterior a esa base; se prueba el rechazo del mismo archivo.
- `--consulta-detalle` permite localizar diferencias por categoría/clave/MD5,
  con el mismo search_path y transacción de lectura. No se aceptan por defecto
  diferencias de objetos administrados; requieren una revisión concreta.

P3: se precisan **siete mutaciones** del catálogo más el contenedor, no ocho
escenarios distintos. La cobertura no es exhaustiva de los 15 grupos. Se
conserva el rechazo estricto de relojes adelantados: no hay evidencia de un
desfase que justifique relajar la ventana. La paridad usa arrays ACL literales;
un reordenamiento equivalente produce rechazo y análisis, nunca aceptación
automática. El envoltorio siempre fija `search_path=''` y UTC. La captura final
se toma después del inventario Edge/Main, inmediatamente antes del merge; las
comprobaciones no eliminan carreras con despliegues concurrentes.

No se pidió un tercer dictamen. Las correcciones finales las verificó Codex;
**no se atribuye un PASS final a Claude**.

## Verificación del PRIMARY

- [32 pruebas de preparación PASS](pruebas-preinstalacion.txt): 24 offline del
  verificador y ocho del banco (siete mutaciones con rollback). Cada mutación
  deja idéntico el catálogo inicial. No generan ventas ni configuran el piloto.
- Salidas de paridad/detalle ejecutadas en banco: 15 categorías y 4.656 objetos,
  solo claves/MD5. La comparación padre/rama pasa sus casos offline; **NOT RUN
  sobre una rama F8 real**, todavía no creada.
- [Check general de scripts PASS](check-scripts.log). Sin cambio de frontend,
  Edge ni esquema instalado: build/tipos/matriz HTTP no se ejecutan en esta
  preparación. Esos gates del ciclo remoto siguen pendientes.
- Consulta combinada ejecutada en producción como READ ONLY, con las 14
  definiciones/ACL/propietarios coincidentes. [Captura viva](preflight-vivo-2026-09-13.json)
  comprobada a las `2026-09-14T04:40:06.855Z`: `PASS_PRECONDICIONES_PADRE`,
  `autoriza_merge=false`, 279 migraciones. No se usa un reloj de prueba en esa
  comprobación; la captura comienza antes y tiene menos de 60 segundos.
- Las dos migraciones candidatas conservan su SHA del commit `e188c0a` y sus
  31 pruebas SQL previas. No se repite el lote de identidades aplicado.

Fallos de preparación resueltos: cast explícito de `defaclobjtype` para evitar
ambigüedad `text || char`; permiso CREATE del nuevo dueño añadido únicamente a
la fixture local y dentro del mismo rollback. El primer intento local fue
bloqueado por el sandbox de Docker y se repitió con escalación autorizada.

Pendientes reales: aprobación de los SQL, rama nueva equivalente, pruebas del
paquete combinado por Auth/Data API y advisors, mapeo de versiones remotas,
merge/publicación desde Main verificado. Después, equipo nominal, ventana,
activación autorizada y evidencia G7. Ningún recibo de esta preparación autoriza
un merge o el encendido.

Referencias consultadas para las nuevas comprobaciones:
[privilegios por defecto](https://www.postgresql.org/docs/17/catalog-pg-default-acl.html),
[estado de triggers](https://www.postgresql.org/docs/17/catalog-pg-trigger.html),
[políticas](https://www.postgresql.org/docs/17/catalog-pg-policy.html) y
[publicaciones](https://www.postgresql.org/docs/17/catalog-pg-publication.html).
