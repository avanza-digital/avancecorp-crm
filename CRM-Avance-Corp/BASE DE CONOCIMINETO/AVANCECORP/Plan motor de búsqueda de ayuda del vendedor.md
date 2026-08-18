# Plan motor de búsqueda de ayuda del vendedor

Fecha: 2026-08-17.

Relacionado con [[Centro de ayuda del vendedor]].

Estado al 2026-08-18: fases 0 a 5 implementadas, desplegadas y verificadas técnicamente. El backend está en Supabase producción y la interfaz compilada está publicada en Hostinger, según [[Continuidad centro de ayuda 2026-08-18]]. Solo queda la validación de aceptación en una sesión CRM real.

## Objetivo

Reemplazar la búsqueda aproximada del navegador por un motor autoritativo en PostgreSQL/Supabase, sin IA, que entienda expresiones comerciales conocidas y que nunca entregue una guía incorrecta por descarte.

El contrato público tendrá únicamente tres resultados:

- `respuesta`: existe una intención suficientemente segura.
- `aclaracion`: hay dos o más interpretaciones plausibles o falta un objeto necesario.
- `sin_resultado`: no existe evidencia suficiente para recomendar una operación.

## Principio de seguridad funcional

Una respuesta equivocada es peor que no responder. La pantalla actual solo podrá ordenar consultas frecuentes o desempatar candidatos ya válidos; no podrá convertir una coincidencia débil en respuesta.

## Arquitectura

### Datos privados

El contenido vivirá en tablas no expuestas del esquema `private`:

- `ayuda_intenciones`: identidad de la operación, respuesta versionada, vistas relacionadas, términos obligatorios y términos excluidos.
- `ayuda_expresiones`: distintas frases reales del vendedor asociadas a una intención, con texto normalizado y peso editorial.
- `ayuda_reglas_aclaracion`: ambigüedades conocidas y opciones permitidas.
- `ayuda_consultas`: telemetría redactada de resultados, puntuaciones y consultas fallidas; nunca almacenará teléfonos, DNI, correos ni nombres completos sin anonimizar.

### Punto de entrada

La aplicación invocará `crm.consultar_ayuda_vendedor(p_consulta, p_vista)`, una RPC autenticada que devuelve JSONB versionado.

La RPC seguirá el patrón de seguridad del proyecto:

- `security definer` con `search_path = ''`.
- Validación explícita de `auth.uid()` y rol CRM antes de leer o escribir.
- `revoke all` a `public`, `anon`, `authenticated` y `service_role`; después `grant execute` únicamente a `authenticated`.
- Tablas privadas sin acceso directo desde Data API.

## Resolución de una consulta

1. Validar longitud y normalizar mayúsculas, signos y tildes.
2. Redactar posibles datos personales antes de escribir telemetría.
3. Buscar primero una expresión normalizada exacta.
4. Recuperar candidatos con Full Text Search configurado en español y similitud `pg_trgm` para errores tipográficos.
5. Rechazar candidatos que no cumplan sus términos obligatorios o que contengan términos excluidos.
6. Calcular una puntuación normalizada combinando coincidencia exacta, ranking lingüístico, similitud tipográfica y peso editorial.
7. Comparar el mejor candidato con el segundo; no basta con que el primero supere un mínimo.
8. Devolver:
   - `respuesta` si supera el umbral y existe separación suficiente;
   - `aclaracion` si hay candidatos plausibles cercanos o una regla editorial;
   - `sin_resultado` en cualquier otro caso.

Los umbrales se determinarán con el corpus de pruebas; no se elegirán por intuición ni se bajarán para obtener más respuestas.

## Fases de implementación

### Fase 0 — Contención inmediata — completada

- Desactivar la coincidencia difusa del fixture del navegador.
- Permitir temporalmente solo frases exactas, aclaraciones explícitas y `sin_resultado`.
- Agregar regresiones para consultas que actualmente conducen a otra guía.

### Fase 1 — Persistencia, índices y seguridad — completada

- Confirmar `pg_trgm` y habilitar `unaccent` sin fijar una versión de extensión.
- Crear las cuatro tablas privadas, restricciones, llaves foráneas e índices de cobertura.
- Crear índice B-tree para coincidencia exacta, GIN para `tsvector` en español y GIN trigram para similitud.
- Implementar redacción de datos personales y políticas de retención de telemetría.
- Verificar privilegios y ejecutar los advisors de Supabase.

### Fase 2 — Motor de decisión — completada

- Implementar la RPC y el ranking de candidatos.
- Incorporar términos obligatorios, excluidos y reglas de aclaración.
- Mantener el contexto de pantalla como señal secundaria, nunca como autorización para responder.
- Devolver puntuación y motivo de decisión solo para observabilidad interna; el vendedor recibe el resultado limpio.

### Fase 3 — Contenido inicial — completada

- Migrar las 17 guías de la vista previa a contenido versionado del servidor.
- Añadir expresiones positivas, ambiguas y negativas para cada intención.
- Revisar que botones, advertencias y rutas coincidan con el CRM real.
- Publicar una versión inicial inmutable y dejar los cambios posteriores como nuevas versiones.

### Fase 4 — Integración del navegador — completada

- Añadir el método tipado `consultarAyudaVendedor` en `crm-api.ts` con validación de contrato y soporte de cancelación.
- Cambiar el panel para consumir la RPC.
- Diferenciar error de red, aclaración y consulta sin resultado.
- Eliminar del bundle el diccionario, el algoritmo de similitud y las respuestas locales.
- Obtener también las preguntas frecuentes desde el servidor.

### Fase 5 — pruebas y despliegue completados

- Crear un corpus SQL versionado con expresiones exactas, coloquiales, errores de escritura, ambigüedades, negaciones y consultas ajenas.
- Probar permisos, redacción de PII, contrato JSONB y comportamiento del panel.
- Ejecutar `EXPLAIN (ANALYZE, BUFFERS)` para certificar el uso de índices.
- Ejecutar typecheck, pruebas del frontend, build y advisors de Supabase.
- Activar primero en modo sombra, luego para usuarios de demostración y finalmente para vendedores.

## Evidencia de cierre local — 2026-08-18

- Catálogo: 17 intenciones, 112 expresiones publicadas y 3 reglas de aclaración.
- Umbrales aprobados por el corpus: respuesta desde `0.61`, margen mínimo `0.12`; aclaración cuando dos candidatos plausibles desde `0.56` quedan próximos.
- Persistencia: contenido privado, publicación inmutable, telemetría redactada y retención de 90 días.
- Búsqueda: B-tree exacto, GIN de `tsvector` español y GIN de trigramas; `EXPLAIN (ANALYZE, BUFFERS)` confirmó ambos índices GIN.
- Seguridad: RPC `security definer` con `search_path = ''`, rol CRM explícito y sin acceso directo a tablas privadas.
- Servidor/UI: contrato JSONB `version: 1`, validación estricta, cancelación de solicitudes y estados separados para respuesta, aclaración, sin resultado y error.
- Bundle: no contiene fixture, sinónimos, algoritmo difuso ni textos de respuesta del manual.
- Despliegue: backend ejecutado en Supabase remoto mediante la migración `20260818054949_crm_ayuda_vendedor_servidor`; frontend publicado en `crm.miavance.com`, caché limpiada e integridad de los archivos principales verificada contra el ZIP aprobado.

## Criterios de aceptación

- Cero recomendaciones incorrectas en el conjunto de conflictos críticos.
- El 100 % de las consultas ambiguas del corpus devuelve `aclaracion` o `sin_resultado`.
- Todas las expresiones publicadas resuelven su intención correcta, con y sin tildes.
- Los errores tipográficos solo se toleran cuando conservan los términos de negocio obligatorios.
- Una consulta desconocida nunca se resuelve solo por la pantalla actual.
- Ninguna consulta almacenada contiene teléfono, DNI o correo sin redactar.
- Una cuenta sin rol CRM no puede invocar la RPC y el navegador no contiene credenciales privilegiadas.

## Fuera de alcance inicial

- IA, embeddings o búsqueda semántica.
- Un editor administrativo completo; la primera versión se publicará mediante migración revisada.
- Respuestas generadas dinámicamente. Todos los textos continuarán siendo aprobados y versionados.
