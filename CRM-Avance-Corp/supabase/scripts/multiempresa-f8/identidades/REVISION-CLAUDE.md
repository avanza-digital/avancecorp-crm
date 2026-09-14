# Revisión independiente — enlaces F8

Codex PRIMARY; Claude SECONDARY_REVIEWER por `scripts/claude-review`, sin
herramientas, escritura ni delegación. Riesgo LEVEL 3. Se adjuntaron plantilla,
generador, banco, definiciones SQL relevantes, resultados y evidencia agregada.
Los datos reales permanecieron fuera del prompt y de Git. CodeGraph se consultó
primero; sus resultados no incluyeron las funciones SQL y se complementaron
con el catálogo PostgreSQL y el símbolo Portal concreto.

## Primera consulta: CHANGES_REQUESTED, confianza MEDIUM

El PRIMARY aceptó y corrigió:

- Guardas independientes del generador ante claves ausentes, valores NULL y
  tipos JSON incorrectos. Una operación ausente no puede convertirse en reversa.
- Unicidad explícita de siete documentos y orígenes, diez fuentes y partición
  exacta entre personas. El resolutor no puede reutilizar otra identidad del lote.
- Comprobación posterior de las fuentes exactas de cada persona.
- Conservación literal del JSON al reemplazar marcadores de la plantilla y
  configuración explícita de cadenas SQL estándar.
- Más pruebas de reversa, revisión F2 restaurada, efectos de triggers y tiempos
  con 598 fuentes sintéticas. Banco presentado a la segunda consulta: 31 PASS.

Conclusiones contrastadas con evidencia:

- El índice documental es parcial (`estado='vigente'`), en banco y producción.
  Después de la reversa el resolutor sí admite el DNI; se probó con ROLLBACK.
  No se confirmó la hipótesis de una reserva documental permanente.
- El puente histórico del lead sí exige reconciliación explícita para un futuro
  enlace. El BEFORE ordinario conserva el enlace anterior; una escritura
  administrativa aislada no reconstruye el puente. Ambas vías están probadas y
  esta limitación de la reversa queda explícita en README.
- `resolverAsesor` del Portal solo resuelve el nombre de un asesor en el importador;
  no resuelve identidad ni sesión por DNI. La hipótesis sobre ese símbolo no
  sustentaba una ampliación de permisos. Se aportó su cuerpo exacto tras CodeGraph.
- `postventa_sincronizar` recorre tareas pendientes existentes. Para las siete
  identidades nuevas se comprobaron siete gestiones de responsable, cero tareas
  y actor de creación NULL, sin atribuir la escritura administrativa a una persona.

Decisiones deliberadas del PRIMARY:

- Conservar el censo global estricto para la reversa: un hueco real ajeno obliga
  a preparar otra revisión. Se prefiere abortar a relajar el contrato del lote.
- Mantener la identidad del ejecutor SQL y enlazar la confirmación humana mediante
  la huella del anexo privado; no inventar un UUID de revisor ni suplantar JWT.
- La duración local de aproximadamente medio segundo no es garantía productiva.
  Tres segundos limitan la espera de candados, no su duración total.

## Segunda consulta

**PASS, confianza MEDIUM.** Claude confirmó el cierre de los P2 y no encontró
defectos materiales restantes. Mantuvo límites de paridad productiva completa
y observaciones P3. Ambas invocaciones terminaron correctamente con dictamen.

Después de ese PASS, el PRIMARY incorporó sus mejoras menores: ligó la marca
multirrol a la colisión y al mapa original; añadió `crm.equipo` a los candados;
probó el intercambio de marcas, una revisión F2 cambiada y actividad posterior;
creó los archivos privados con modo 600 desde `open` e incluyó el hash del lote
en el manifiesto del generador. El banco final pasó **34 comprobaciones**, con
sintaxis y paridad verificadas de nuevo. No se pidió una tercera consulta.

La lectura productiva confirma para la cuenta analista multirrol rol Portal
`analista`, rol CRM `vendedor` y ambas membresías activas. Sus accesos siguen
dependiendo del ámbito asignado; una coincidencia de DNI no concede permisos.
El censo de las 21:16 Lima coincide exactamente con el lote congelado.

Miguel aprobó después el SQL exacto y su [aplicación quedó verificada](APLICACION-2026-09-13.md).
La autorización vino del usuario; el review no autoriza por sí solo aplicación,
publicación, encendido F8 ni el tratamiento de las cuatro demos.
