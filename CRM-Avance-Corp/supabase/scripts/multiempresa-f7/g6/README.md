# Preparación reproducible de G6

Lee el [acta y límites](../ACTA-G6.md). Este paquete **no tiene conexión a la
base, credenciales, migraciones ni comandos de despliegue**: genera SQL de solo
lectura, verifica archivos privados y crea un comparativo HTML autónomo. La
ejecución SQL se realiza por el conector administrativo ya autorizado.

## Obtener y verificar un corte

Desde la raíz del repositorio, usando una carpeta privada fuera de Git (0700;
archivos 0600). El consumidor requiere las dependencias existentes del CRM y
Node compatible con su TypeScript; Python solo utiliza la biblioteca estándar.

1. Leer `pg_get_functiondef('crm.metricas_multiempresa_fn(date)'::regprocedure)`
   y su MD5 desde la instalación autorizada. Guardar un array JSON de objetos
   `{ "firma": "crm.metricas_multiempresa_fn(date)", "huella": "...", "definicion": "..." }`.
   Las diez huellas del conjunto se comprueban en la transacción generada: si cambian,
   revisar el contrato; no actualizar constantes solo para conseguir un PASS.
2. Generar la consulta y su postflight con la fecha de Lima y meses concretos:

```sh
g6_dir=CRM-Avance-Corp/supabase/scripts/multiempresa-f7/g6
g6_privado=/private/tmp/avancecorp-g6-conciliacion-20260911
python3 "$g6_dir/generar_consulta.py" --definiciones "$g6_privado/definiciones-productivas.json" --hoy 2026-09-11 --mes 2026-08-01 --mes 2026-09-01 --salida "$g6_privado/consulta-g6-v2.sql"
python3 "$g6_dir/generar_consulta.py" --definiciones "$g6_privado/definiciones-productivas.json" --hoy 2026-09-11 --mes 2026-08-01 --mes 2026-09-01 --postflight --salida "$g6_privado/postflight-v2.sql"
```

3. Ejecutar la consulta generada completa mediante el conector, conservar el
   objeto de la columna `evidencia` como `lectura-productiva-v2.json`. El SQL
   verifica el día vigente, las diez definiciones, el propietario, la bandera
   OFF y Gerencia de referencia. No extraer solo el SELECT saltando las guardias.
4. Ejecutar el postflight completo en una segunda transacción y conservar
   `evidencia` como `postflight-productivo-v2.json`. Ambos usan el mismo fragmento
   `metadatos.sql.in`. El comparador coteja banderas, diez funciones, total de
   migraciones y huellas de fotos cerradas, con orden único por PK.
5. Validar **las capturas exactas** y generar el archivo privado:

```sh
node --experimental-strip-types "$g6_dir/verificar-lectura.mjs" "$g6_privado/lectura-productiva-v2.json" "$g6_privado/verificacion-productiva-v2.json"
node "$g6_dir/verificar-postflight.mjs" "$g6_privado/lectura-productiva-v2.json" "$g6_privado/postflight-productivo-v2.json" "$g6_privado/custodia-v2.json"
node --experimental-strip-types "$g6_dir/probar-verificador.mjs" "$g6_privado/lectura-productiva-v2.json"
python3 "$g6_dir/probar_generador.py" "$g6_privado/definiciones-productivas.json"
python3 "$g6_dir/crear_informe.py" --lectura "$g6_privado/lectura-productiva-v2.json" --verificacion "$g6_privado/verificacion-productiva-v2.json" --postflight "$g6_privado/postflight-productivo-v2.json" --custodia "$g6_privado/custodia-v2.json" --revision 'Consultar REVISION.md; conformidad humana y financiera pendientes.' --salida "$g6_privado/Comparativo G6.html"
```

Un fallo devuelve código no cero y un archivo `FAIL`, reemplazando cualquier
PASS anterior. Diferencias de conversión se conservan como `REVISAR`; no se
genera una página de éxito con ellas. El informe exige las huellas SHA-256 de
ambos archivos y las verificaciones positivas. Las pruebas negativas modifican
copias en memoria, nunca producción. No subir capturas/HTML a Git; los nombres,
referencias, UUID e importes se mantienen en el anexo y respaldo privados.

El HTML se abre directamente desde disco. Si se usa un servidor temporal,
enlazarlo exclusivamente a `127.0.0.1` y servir una carpeta que contenga **solo
el HTML**, nunca el directorio de evidencia privada. No requiere login ni APIs
porque es un archivo local sin solicitudes externas. No es una nueva ruta del CRM.

## Alcance comprobado

Se extrae una proyección SELECT de un cuerpo previamente inspeccionado y
fijado por huella. Solo se sustituyen sus seis variables locales y se retira
`INTO`; no se reimplementa el informe. La extracción no es un parser SQL general.
MD5 detecta cambios de definiciones, SHA-256 identifica archivos; ninguno es
una firma humana. La bandera real OFF y el método se rotulan por separado del
literal `habilitada=true` que forma parte de la proyección interna.

`EXCEPT ALL` compara fuentes/montos/responsables/fechas/tipos en PostgreSQL,
manteniendo NUMERIC exacto y multiplicidad. La comparación del capital publicado
reagrupa ambas cooperativas en su categoría heredada solo para ese control;
el desglose por empresa/moneda permanece separado en la entrega. El lector
publicado también corta capital en hoy+1 Lima. Conversión oficial de un mes
sellado usa su foto; la del mes corriente comparte el núcleo publicado.

La reconstrucción de identidad usa fuentes y relaciones independientemente
del lector F5. El canonizador devuelve el ID de entrada como fallback para
cualquier entrada no nula; se conserva evidencia de fuentes sin identidad.
Oportunidades reutiliza el predicado/helper: es un control de consistencia,
no una demostración independiente del veto. Los casos reales ausentes se
marcan NOT RUN, sin trasladarles el PASS de datos ficticios.

## Verificación de esta entrega

- SQL del corte productivo: PASS; 218 inversiones, sin diferencias observadas.
- SQL del banco sintético: PASS con una única adaptación local documentada:
  `migraciones=null` porque esa copia no tiene `supabase_migrations`. No se
  simuló un PASS del ledger; las guardias y todos los cálculos quedaron iguales.
- Contrato real del frontend y comparador de custodia: PASS.
- Diecinueve controles negativos, dos modos del generador y tres entradas
  inválidas: PASS. Sintaxis JS/Python y `npm run check:scripts`: PASS.
- Navegador: selector de meses y anexos de operaciones/identidad comprobados.
- Build/frontend completo y RLS nuevos: NOT RUN para este paquete de lectura;
  no se modificó runtime, esquema ni permisos. Sus gates F7 previos mantienen
  el alcance registrado en [ACEPTACION.md](../ACEPTACION.md).
- Rendimiento productivo: NOT RUN como benchmark. La duración del conector
  incluye transporte y no sirve como medida de latencia SQL ni escalabilidad.
- Firma humana/financiera, activaciones y piloto F8: NOT RUN.

No repetir las sondas que reinstalan objetos del banco F7 contra producción.
Este paquete se distingue de `banco-local.mjs` y sus pruebas de escritura.
