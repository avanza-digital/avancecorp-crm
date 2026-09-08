# Evaluación del PRIMARY — mantenimiento F2 e históricos F4

Revisión secundaria acotada a la carrera reproducida del mapa F2, la corrección
y sus oráculos. Dictamen original: **CHANGES_REQUESTED**. No es aprobación de G4.
Se conservan prompt exacto (dentro de JSON), informe y huellas en este directorio.

## Decisiones y evidencia posterior

- **Mapa F2: defecto confirmado y corregido.** El hallazgo `b19459de` demuestra
  un lote confirmado mientras había un INSERT del mapa sin confirmar. El cuerpo
  anterior era `81f9115…`; el actual es `a33595d4ac8c2c12ad6fcf9463db605e`.
  SHARE NOWAIT estabiliza también las filas ausentes. Los ocho cruces del
  informe `historicos-mantenimiento-c014fd65…` pasan sobre ese cuerpo.
- **P1 sobre duplicados en otras tablas: hipótesis descartada en el esquema y
  caminos ensayados.** Existen índices únicos de contrato/cierre, pareja de
  titulares, principal por inversión y documento vigente. Las FK son reales:
  un INSERT de inversión o identificador obtiene KEY SHARE sobre la persona;
  un cotitular lo obtiene sobre su inversión. El lote adquiere FOR UPDATE NOWAIT
  sobre esas filas padre y rechaza con 55P03 sin acta. Se reprodujeron los tres
  casos; tras ROLLBACK se puede reintentar. En el orden inverso, el INSERT legado
  de inversión espera al lote y termina con 23505 en `inversiones_cierre_uidx`;
  queda una sola inversión. No hacen falta bloqueos SHARE globales adicionales.
  `private.inversionista_resolver` devuelve sin escribir cuando ya existe el
  documento vigente verificado; no actualiza los documentos de esa persona.
  Esto no demuestra cobertura de DML arbitrario como superusuario ni de futuros
  escritores. El corpus F2 completo sigue pendiente y F2 global no se reejecuta.
- **P2 de huellas:** el paquete inicial de revisión era insuficiente. La captura
  estructural posterior `estructura-2026-09-08T15-13-41.744Z.json` conserva MD5 de
  las 37 funciones y verifica módulos → candidata → base. La consulta adicional
  a las copias conservadas confirma el mismo MD5, pero se identifica como
  consulta posterior, no como captura durante el ensayo. Los oráculos previos
  exigen cuerpo exacto al inicio; censo/lote/concurrencia también guardan SHA de
  módulos. No se modificaron sus informes antiguos para añadir datos nuevos.
- **P2 de dos copias:** los ocho módulos son fuentes del generador; la candidata
  se ensambla con ellos. Ahora `verificar-estructura.mjs` exige también igualdad
  de los cuerpos módulo/candidata. Las 37 funciones instaladas coinciden.
  La candidata sigue sin versionar hasta completar F4.
- **P2 de escala:** añadido `--sin-vinculo`: 100 conversiones cooperativas reales
  en copia SQL, con el enlace de persona retirado solo en la fixture. Los 100
  UPDATE privilegiados se completan, el GUC vuelve a `off`, y el resto de cada
  fuente económica queda igual. Resultado: 112.545 ms; reintento 0.559 ms. El
  caso con enlace previo tardó 93.132 ms. Son mediciones locales, no una promesa
  productiva; 100 contratos o un lote mixto de tamaño máximo quedan NOT RUN.
- **P3 del iterador:** exige una firma por nombre y rechaza solicitadas repetidas.
  Conserva guardas MD5 dentro de la transacción, banderas y orden de candados.
  Evidencia con fecha y UUID/creación exclusiva. Una avería al escribir el informe
  después del commit sigue siendo posible: comprobar estado antes de repetir.
- **P3 de error ambiguo:** el oráculo comprueba SQLSTATE 55P03 y relación concreta;
  incluye DELETE del mapa. La captura de fallo `a9bea754…` corresponde al primer
  regex del oráculo, que omitía el prefijo `crm.` de un error correcto; no es una
  regresión SQL. Se conserva, identificada aquí, junto al ensayo corregido.
- **Plazos:** `lock_timeout=5s` limita cada espera. El límite total lo fija el
  llamador con `statement_timeout`; 4s en escala, que puede dar 57014. 55P03,
  40001, 23505, 40P01 o 57014 requieren rollback y comprobar/recensar antes de
  repetir; ninguno prueba por sí solo que una respuesta perdida no se confirmó.

## Cobertura de entradas y exclusión

| Entrada del censo | Protección y límite |
| --- | --- |
| Mapa F2, incluso fila ausente | SHARE NOWAIT de tabla; INSERT/UPDATE/DELETE ensayados |
| Persona y documentos | Bandera de identidad para F3; FOR UPDATE de persona y FK para INSERT administrativos; corrección/fusión reales ensayadas |
| Fuentes contrato/cierre | FOR UPDATE NOWAIT; carreras de anulación y eliminación ensayadas anteriormente |
| Inversión/titulares | FK de padres, FOR UPDATE de filas existentes, unicidad de fuente/principal |
| Perfil/lead | FOR SHARE NOWAIT, relectura de huella y bandera de identidad |
| Catálogo empresas | Solo lectura del catálogo preexistente; administración concurrente arbitraria no ensayada |
| Otra aplicación histórica | Candados exclusivos de identidad y F4, no el SHARE del mapa |

PASS: regresión de históricos (7 censo + 19 lote + 7 concurrencia + 6 identidad),
8 cruces administrativos, dos lotes de 100, estructura de 37 funciones/5 tablas
y `npm run check:scripts`. La revisión evaluó evidencia anterior y estas
comprobaciones son del PRIMARY; no se atribuye a Claude aprobación posterior.

NOT RUN en este bloque: corpus F2 completo, escala máxima mixta/Avance,
advisory timeout explícito, todas las tareas productivas, reconstrucción y
reversa de la candidata completa, matriz final RLS/financiera y gate G4.
No hubo publicación, activación ni cambios productivos.
