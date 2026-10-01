**VERDICT: CHANGES_REQUESTED**

**SUMMARY:** No identifico una fuga de RLS en la puerta transcrita con sus permisos actuales. El espejo, la admisión y la vinculación del actor a la sesión son coherentes. Solicito cambios en las verificaciones: admiten estados que contradicen las restricciones declaradas. `baja_el` cumple la decisión 5 como fecha de elegibilidad; no garantiza cuándo se ejecutará la bajada.

**FINDINGS**

1. **P2 — El postflight admite configuración y permisos adicionales.**  
   Evidencia: `$postflight$` de [la migración](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead/supabase/migrations/20261001151704_crm_potencial_lead_lectura.sql) comprueba `proconfig @> array['search_path=""']` y los destinatarios de la ACL, pero no `is_grantable`.

   Dos contraejemplos:
   
   - `EXECUTE TO authenticated WITH GRANT OPTION` pasa: el destinatario sigue siendo `authenticated`.
   - Añadir un `SET request.jwt.claims = ...` conserva el `search_path` requerido y pasa ese postflight, aunque puede alterar la identidad que obtiene `auth.uid()`.

   Son falsos verdes del verificador, **no estados presentes en el SQL entregado**. Comparar la configuración completa esperada, rechazar grant options para `authenticated` y comprobar también los permisos efectivos de los roles API.

2. **P2 — La verificación independiente interpreta una ACL implícita como ausencia de permisos ajenos.**  
   Evidencia: [verificar-lectura.sql](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead/supabase/scripts/potencial-lead/verificar-lectura.sql), cálculo de `v_nucleo` mediante `aclexplode(p.proacl)`.

   Si `proacl IS NULL`, `aclexplode` no produce filas y el resultado anunciado es `0`. Sin embargo, para funciones esa ACL implícita incluye `EXECUTE` para `PUBLIC`. El postflight de instalación rechaza ese estado, pero este verificador posterior lo informaría incorrectamente.

   Rechazar explícitamente una ACL nula o expandir `coalesce(proacl, acldefault('f', proowner))`; complementar con `has_function_privilege` para comprobar permisos efectivos.

3. **P3 — El gate oculta duplicados en los ítems.**  
   Evidencia: [test-rls.mjs](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/wt-potencial-lead/supabase/scripts/test-rls.mjs), `new Set(data.items.map((item) => item.lead_id))`.

   Una respuesta con cada lead visible repetido dos veces pasa la comparación. Añadir una comprobación de unicidad y comparar también las cantidades. La prueba sintética de IDs repetidos cubre otro caso: duplicados en la entrada.

**Riesgos y test gaps**

- **a. Visibilidad, NULL y actor.** `IN (SELECT ...)` y `= ANY(array(SELECT ...))` conservan aquí la misma aceptación de filas, incluidos NULL y conjuntos vacíos. Un resultado desconocido no concede acceso; el gate usa `IS NOT TRUE`. No encuentro exposición por `puede_marcar`, orden o errores explícitos.  
  El núcleo sí mezcla identidades si recibe otro `p_actor`: por ejemplo, una sesión de vendedor y un parámetro de gerencia activan la rama `v_rol = 'gerencia'`. Actualmente la API no puede invocarlo y la puerta siempre pasa `auth.uid()`. Es una precondición protegida por la arquitectura, no comprobada dentro del núcleo.

- **b. Preflight.** `polcmd IN ('r','*')` incluye todas las policies pertinentes para este SELECT; omitir las de UPDATE es correcto. El cast a `regrole[]` evita depender de los OID concretos de los roles. Con la misma versión y configuración de deparsing, el `search_path` vacío resulta coherente.  
  La huella no es completamente independiente de la sesión: `quote_all_identifiers` puede cambiar el texto de `pg_get_expr`; también puede cambiar entre versiones de PostgreSQL. Fijaría esa opción y verificaría las huellas en producción antes de aplicar. El sellado tampoco protege frente a cambios de policies **posteriores** a la instalación.

- **c. Calendario.** La fórmula coincide con la fase 2 bajo el mismo estado, fecha y corte. El domingo puede ser la fecha correcta porque el sábado ya terminó y la tarea corre diariamente.  
  **No coincide siempre con la ejecución real.** Contraejemplo: una Estrella marcada el 05/10, reabierta el viernes 16/10 después de las 05:40, tiene nueve días completos. La lectura devuelve `tibio@2026-10-16`; la siguiente corrida, el sábado 17, contará diez y bajará directamente a Frío. No hace falta ningún contacto intermedio. El límite y los candados también pueden retrasarla; un contacto posterior puede evitarla. Documentar esta semántica antes de que la pantalla prometa una madrugada concreta.

- **d. Costo.** La medición no representa un subárbol grande: el fixture crea un supervisor y un vendedor. `potencial_rechazo` vuelve a resolver el subárbol por cada ítem; `STABLE` no implica memorizar ese resultado entre llamadas. Además, `dias_lunes_a_sabado` genera días y se repite dentro de la búsqueda de fechas: el costo crece con la antigüedad de la marca. Hay riesgo de crecimiento, pero no evidencia suficiente para afirmar una latencia inaceptable. Medir con el tamaño de equipo, antigüedad e historial máximos esperados.

- **e. Zona horaria.** El contrato es utilizable: interpretar `marcado_en` respetando su offset y mostrarlo en Lima. Tratar `baja_el` como fecha de calendario. `new Date('2026-10-11')` representa medianoche UTC y, al mostrarla en Lima, puede terminar como **10/10**.

- **f. Reversa.** Los dos `DROP FUNCTION`, dentro de una transacción y sin `CASCADE`, eliminan también sus comentarios y permisos. Permanecen intencionalmente las tablas y el registro de migración. El manejo de “función inexistente” en la pantalla está declarado, pero no está demostrado por esta evidencia.

- **g. Cobertura pendiente.** Añadiría directorio histórico sin membresía, perfil inactivo con equipo activo, roles desalineados y los mutantes de verificación anteriores. Con la bandera apagada, el gate omite la comparación contra RLS; `CRM_RLS_EXIGE_POTENCIAL=1` no obliga a ejecutarla. Debe quedar visible que esa comprobación está **NOT RUN** en ese estado. El fragmento tampoco permite comprobar que el runner invoque `testPotencialLectura`.

**NEXT ACTIONS:** Corregir ambos verificadores y la comprobación de unicidad; añadir sus mutantes. Explicitar que `baja_el` es elegibilidad y cubrir el caso posterior a la última corrida. Ejecutar el gate con sesiones reales y bandera encendida en un banco autorizado, y medir el caso de equipo grande.

**CONFIDENCE:** Alta en el análisis estático de autorización y los falsos verdes descritos; limitada para rendimiento y ejecución real. Los PASS citados son evidencia aportada. Pruebas ejecutadas por este revisor: **NOT RUN**. El gate con sesiones reales sigue **NOT RUN**.
