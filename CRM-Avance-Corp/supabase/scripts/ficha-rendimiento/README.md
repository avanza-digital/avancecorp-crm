# Ficha canónica: lectura individual

**Publicada y verificada el 15/09/2026.** La ficha SQL de Gerencia pasó de 2674,505 a 723,414 ms (−73 %), con los mismos datos y permisos. [Acta de publicación, pruebas remotas y límites](PUBLICACION.md). Banco eliminado, coste estimado US$0,021.

Las secciones de prueba local que siguen documentan la preparación previa. El resultado productivo vigente es el del acta.

## Objetivo y cambio

Bajar la consulta de la ficha de Gerencia de unos 2,7 s a menos de 1 s,
con el mismo diseño, datos canónicos, aislamiento por rol y capacidades.
El objetivo se refiere al tiempo SQL de la ficha; la navegación completa del
navegador quedó fuera de la medición por decisión del usuario.

[Migración exacta](../../migrations/20260915170237_crm_ficha_lectura_individual.sql).
Un único núcleo `private.cartera_f5_personas_visibles(uuid)` admite una persona
o NULL para el conjunto. La firma sin argumentos conserva los lectores de
listado. Solo se sustituyen dos llamadas dentro de la ficha: entrada y salida.
Se conserva el filtro externo por `v_id`, necesario si cambia una fusión durante
la lectura. No hay nueva fuente financiera, caché de datos ni cambio visual.
La sobrecarga no tiene argumento por defecto y queda sin EXECUTE para PUBLIC,
anon, authenticated y service_role. Mantiene SECURITY DEFINER y search_path vacío.

Las guardias comprueban las definiciones previas antes de modificar. Una deriva
se rechaza; no se sobreescriben otras migraciones. [Reversa exacta](REVERSA.sql),
con guardias para las tres definiciones optimizadas. Si fuera necesaria después
de publicar, se convertirá en una migración nueva, sin editar esta versión.

## Evidencia y límites

- [Paridad](evidencias/paridad-local.json): 640 fichas completas y 328 resultados
  del núcleo antes/después; ocho contextos, 40 entradas (incluidas NULL e inexistente) y diez aliases. Incluye
  Directorio, cliente, sin sesión, ambos equipos, demos, mezclas demo/real,
  perfiles fusionados, bandeja sin analista, perfil provisional y dos inactividades.
  Ocho huellas económicas/de identidad conservadas. Firma, propietario, ACL y
  configuración existentes idénticos.
- [Seguridad](evidencias/seguridad-local.json): 15 controles PASS. Instalación
  repetida y deriva rechazadas, reversa exacta, acceso directo privado denegado.
  La bandera, reasignación y fusión revocadas durante la llamada vuelven a
  comprobarse antes de entregar la ficha. Estas seis pruebas instrumentan el
  contexto F4 en una transacción local; **no son carreras entre dos sesiones**.
- [Volumen](evidencias/volumen-local.json): 490 personas, 475 perfiles,
  1.750 leads, 587 fuentes Avance, 49 COOPAC y 7.093 cuotas ficticias.
  Cuatro muestras medidas por grupo después de una de calentamiento. La ficha
  Gerencia pasa de mediana 281,421 a 249,887 ms; Analista 270,834 a 256,300 ms.
  Las huellas completas coinciden y el listado no muestra regresión relevante.
  Estos tiempos son locales; **no acreditan la meta de producción**.
- Diagnóstico de solo lectura del SQL vigente en producción: el cuerpo del
  núcleo devolvió 492 filas en 1.045,347 ms (EXPLAIN ANALYZE, TIMING OFF).
  El lateral de nombres COOPAC recorrió el CTE de fuentes 12.278 veces,
  descartando 611 filas por recorrido. No se instaló la candidata para medirlo.
  El banco local elige otro plan, por lo que no reproduce toda esa penalización.

La prueba inicial con predominio COOPAC no era representativa y no se usa como
acreditación. El primer ensayo del cronograma usó un tipo inválido de fixture;
se corrigió a `cuota`. El test de bandera esperaba un código de autenticación;
la función existente usa P0409 al apagar la disponibilidad y se comprobó ese
contrato en ambas versiones. Ninguno de esos fallos modificó producción.

## Reproducir en la copia aislada

Contenedor `supabase_db_avancecorp-f5-bank`, copia propia
`ficha_rapida_20260915`, creada desde `multiempresa_f8_ajustes_20260914`.
El origen no se modifica. Los scripts tienen el destino fijo y no aceptan
URLs, claves ni nombres de base desde el entorno. Usan PostgreSQL 17.6,
jit off, work_mem 3500kB y random_page_cost 1.1 en la sesión de prueba.

Desde la raíz del repositorio:

```sh
node CRM-Avance-Corp/supabase/scripts/ficha-rendimiento/pruebas-locales.mjs
node CRM-Avance-Corp/supabase/scripts/ficha-rendimiento/seguridad-local.mjs
node CRM-Avance-Corp/supabase/scripts/ficha-rendimiento/volumen-local.mjs
```

Los tres scripts anteriores terminan en ROLLBACK. Las fuentes no pueden ser de producción:
se usan exclusivamente registros sintéticos de la copia local. Replica se usa
solo para preparar estados históricos/artificiales dentro de esas transacciones.

## Publicación y trabajo siguiente

SQL y banco autorizados por Miguel, ensayo remoto y merge completados. Registro
productivo `20260915185535`, nueve segmentos literales; 294 entradas anteriores
intactas. 649 funciones y 20 Edge verificadas. La ficha permanece visualmente igual.

La meta SQL productiva de menos de un segundo está cumplida. La apertura general
solicitada para los 18 analistas se organiza en [ESTADO.md](ESTADO.md); conserva
los pendientes reales de G7 y no se declara aprobada por estas pruebas sintéticas.

## Cierre local y revisión

[Dictamen íntegro de Claude](REVISION-CLAUDE.md): CHANGES_REQUESTED, sin P0/P1,
seguridad y equivalencia con confianza alta; rendimiento con confianza baja.
[Evaluación del PRIMARY](EVALUACION-REVIEW.md). Codex añadió poscondiciones de
MD5/owner/configuración/ACL, documentó NULL y amplió la paridad. Los controles
rechazan ACL inesperadas y un mutante que elimina el filtro. Se volvió a ejecutar
el paquete final. No se afirma PASS del revisor ni cierre productivo.
[Definición final resultante](evidencias/ficha-resultante.sql) para trazabilidad;
la única fuente de instalación es la migración.

[Concurrencia real local](evidencias/concurrencia-local.json): 12 lecturas,
oleadas de 1/2/3 sesiones con tres roles sobre la misma persona operable.
Intervalos superpuestos, hashes/capacidades iguales y restauración de funciones,
ACL y banderas. Banco sintético pequeño; no sustituye HTTP ni concurrencia
productiva. Reproducción adicional:

```sh
node CRM-Avance-Corp/supabase/scripts/ficha-rendimiento/concurrencia-local.mjs
```

Este cuarto script confirma temporalmente el SQL en la copia propia para que
las sesiones lo compartan. Su finally restaura funciones y banderas, comprueba
las huellas y que no queden sesiones de la prueba. Si se interrumpe el proceso
externamente, verificar ese estado antes de reutilizar la copia; no toca el
banco original ni acepta otro destino.

PASS: sintaxis de los scripts, check:scripts, seed:preflight,
test:rls:preflight y test:edge-preflight. Los preflights seed/RLS iniciales usaron
valores ficticios de loopback; posteriormente pasó la matriz remota específica:
640 fichas, 328 resultados de núcleo, 15 controles de seguridad, 154 comparaciones
Auth/API y seis solicitudes HTTP en oleadas 1/2/3. Tipos public/crm idénticos y
advisors revisados. Los [adaptadores](ensayo-remoto/README.md) y evidencias
permiten distinguir el alcance SQL, Auth/API y de concurrencia.

Matriz RLS general heredada y Build/E2E visuales NOT RUN en esta tarea: no hay
cambios de frontend. Banco propio eliminado el 15/09 a las 19:33:48 UTC; estimación
US$0,021 frente al máximo de US$1. La rama ajena banco-f7 permanece intacta.
