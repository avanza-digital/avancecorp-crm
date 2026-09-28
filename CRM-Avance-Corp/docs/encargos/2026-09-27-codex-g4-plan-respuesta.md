# Respuesta de Codex (27/09) — plan G4

Incorporado en el plan v2 aprobado por Miguel: rol nulo rechazado explícitamente (G4a); G4b con selector de ámbito explícito ('analista' | 'equipo' | 'fuera' | 'operacion') y roles supervisor/gerencia verificados en el núcleo antes del ámbito.

VERDICT: **CHANGES_REQUESTED**

SUMMARY:

El plan tiene un defecto concreto: G4b no permite distinguir «fuera» del total mediante sus parámetros. También necesita cerrar explícitamente la autorización ante roles nulos y aclarar los roles admitidos por la nueva consulta. La equivalencia entre cifras y listas requiere comprobar la RLS efectiva, además de los filtros SQL.

Revisión estática del plan y de los fragmentos transcritos; sin ejecución.

FINDINGS:

**[P1] G4b no puede representar el ámbito «fuera».**

- **Evidencia:** la firma solo ofrece `p_supervisor_id` y `p_analista_id`; gerencia consulta toda la operación con ambos nulos. G4b.2 también exige consultar «fuera», incluyendo tareas con `vendedor_id` nulo.
- **Problema:** `(NULL, NULL)` ya significa total. Ningún supervisor identifica «fuera», y `p_analista_id = NULL` tampoco distingue ausencia de filtro de tareas sin vendedor. El helper rechaza un supervisor inexistente, por lo que un identificador ficticio tampoco resuelve el contrato actual.
- **Impacto:** el enlace de «fuera» puede abrir toda la operación o perder las tareas sin vendedor. No hay una petición inequívoca para obtener su lista exacta.
- **Recomendación:** introducir un selector explícito de ámbito, calculado y autorizado en servidor. Definir combinaciones válidas con equipo y analista; incluir vendedores nulos únicamente cuando corresponda al ámbito solicitado.

**[P1] G4b deja sin definir una restricción de roles que el helper no proporciona.**

- **Evidencia:** G4a excluye expresamente «directorio/lector global». G4b.2 remite al «mismo canónico», pero `gestion_diaria_equipo_ambito` admite:
  ```sql
  coalesce(v_rol in ('supervisor', 'gerencia'), false)
  or private.es_lector_global()
  ```
- **Problema:** utilizar ese helper como única autorización de G4b admitiría lectores globales. El plan no incluye una comprobación adicional ni autoriza expresamente esa ampliación.
- **Impacto:** acceso adicional a información individual de citas si se implementa únicamente el control descrito. Es una consecuencia condicional del plan, no una exposición ya demostrada.
- **Recomendación:** declarar los roles permitidos y verificarlos en el núcleo antes de resolver el ámbito. Si son supervisor y gerencia, aplicar esa lista explícita. Especificar también las revocaciones y concesiones de puerta y núcleo, siguiendo el patrón transcrito; probar ambos puntos de entrada.

**[P2] La nueva condición de G4a deja pasar un rol SQL nulo en su primera comprobación.**

- **Evidencia:** G4a.1 propone:
  ```sql
  v_uid is null or v_rol not in ('supervisor','gerencia')
  ```
  El cuerpo anterior utiliza `IS DISTINCT FROM 'supervisor'`.
- **Problema:** con usuario no nulo y rol nulo, la nueva expresión resulta `NULL`; un `IF` de PL/pgSQL no lanza la excepción en ese caso.
- **Impacto:** el rechazo queda delegado al helper. Si ese actor satisface `puede_acceder_crm()` y `es_lector_global()`, el helper lo admitiría con ámbito global. **No está demostrado que exista actualmente una identidad con esa combinación.**
- **Recomendación:** usar una condición que rechace explícitamente el nulo:
  ```sql
  v_uid is null
  or not coalesce(v_rol in ('supervisor', 'gerencia'), false)
  ```
  Incorporar esa combinación a las pruebas de autorización.

TEST GAPS:

**NOT RUN:** todos los checks y pruebas de ejecución; este review solo dispone de la transcripción.

- **Cifra frente a RLS efectiva.** La cifra se describe «sin filtrar estado ni activo», pero `tareas_select` contiene `activo = true`. Esto no demuestra una discrepancia: la cifra podría estar sometida a la misma RLS. Falta acreditar su contexto efectivo de ejecución. Comparar conjuntos de identificadores y totales con tareas inactivas, postventa invisible y vendedores nulos; compartir el `WHERE` no basta.
- **Ámbitos de citas.** Probar total, equipo, analista y «fuera» con datos que hagan diferentes esos conjuntos. Verificar que seleccionar un analista de «fuera» no incorpore también todas las tareas sin vendedor.
- **Autorización real.** Ejecutar como `authenticated` con identidad efectiva, incluyendo llamadas directas al núcleo, actores revocados, lectores globales y rol nulo. Pruebas ejecutadas únicamente como propietario no acreditan RLS.
- **Contrato nuevo.** Validar día nulo/no finito, límites, cursor incompleto/no finito, empates en `creado_en` y ambos extremos del día Lima. Comprobar rechazo de combinaciones incompatibles de ámbito.
- **Migraciones.** Demostrar en Docker aplicación, reversa y reaplicación; atomicidad entre cuerpo y sello; aborto sin cambios ante preflight fallido; y ejecución del nuevo assert de citas desde el gate correspondiente. El plan menciona asserts propios, pero no explicita su conexión al gate general. No hay evidencia de una infracción del canal de publicación descrito.

REGRESSION RISKS:

- **Bundles de supervisor:** conservar claves y `supervisor_id = v_uid` preserva el contrato descrito. La comparación propuesta debe ejercitar también el validador estricto del bundle publicado.
- **Cifras entre consultas:** `statement_timestamp()` cambia entre peticiones. Una tarea puede vencer o cambiar de estado entre la cifra y su apertura. La interfaz debe actualizarse con el resumen de la lista y expresar su referencia temporal.
- **Reversa tras publicar el front:** restaurar el núcleo anterior vuelve a producir 42501 para gerencia. La reversa necesita contemplar también la funcionalidad ya expuesta en pantalla.

RECOMMENDED NEXT ACTIONS:

1. Corregir el rechazo de roles nulos en G4a.
2. Completar G4b con un selector inequívoco de ámbito y autorización explícita de roles y funciones.
3. Acreditar equivalencia de conjuntos bajo RLS real y completar las pruebas del ciclo de migración.
4. Mantener G4a antes de G4b, condicionado a sus resultados de verificación.

CONFIDENCE: **MEDIUM**.

Alta sobre la ambigüedad de «fuera» y la semántica de `NULL`; limitada sobre accesos efectivos y paridad de cifras porque no se adjuntan la implementación de G4b, los cuerpos de las métricas ni resultados de pruebas.
