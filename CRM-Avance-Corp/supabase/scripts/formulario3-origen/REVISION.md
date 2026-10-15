# Evaluación de revisiones — 15/10/2026

Codex PRIMARY; Claude y los agentes propios actúan como reviewers de solo
lectura. CodeGraph no estaba disponible en esta copia aislada. Se contrastaron
cuerpos vigentes de producción, catálogo de funciones/policies, código, tests
y pruebas de dos conexiones. No se aplicó ningún cambio productivo.

## Claude: implementación (CHANGES_REQUESTED, sin P0)

- **Hipótesis P1: cierres legados conservan el origen del episodio.** La función
  vigente `private.conversion_cierres` usa el origen del lead en la política
  anterior y el de `conversion_acreditaciones` en la actual; no toma el origen
  inmutable del episodio. Se añadió un cierre real de lead legado después de B.
  La nueva evidencia de un cliente convertido antes de B sí exigió ampliar B:
  se traslada también su origen acreditado, sin reconstruir ni recalcular la
  acreditación. Ensayo de tres conversiones previas y reintento posterior PASS.
- **P2: fila F3 vacía antes de activar.** A conserva el catálogo estático anterior
  del ranking. F3 aparece por sus datos reales después de B. Compatibilidad probada.
- **P2: reporte pierde episodios sin lead.** Se utiliza LEFT JOIN; la proyección
  conserva el origen fotografiado cuando falta la fila actual.
- **P2: literales de política sin revisar.** Barrido vivo de `crm/private/public`:
  las 15 funciones con literal SQL `'formulario'` están entre las 22 modificadas;
  cero policies incluyen ese literal. Las puertas genéricas de métricas filtran
  por texto y usan el núcleo compartido. Se probó `metricas_conversiones_fn`
  con filtro F3 y tres cierres. Las reglas de rol/destino de alta manual permanecen.
- **P2: alta manual antes de que se renueven pestañas.** A rechaza temporalmente
  el alta manual F3; las importaciones nuevas se traducen al formato legado.
  B habilita la clave canónica después de publicar y renovar las sesiones.
- **P3: coherencia con campaña.** B impide que un F3 tenga otra campaña mediante
  CHECK. El manual usa origen F3 con campaña NULL, como canal propio; solo el
  importador asigna campaña. Se conserva el candado que impide escribir campañas
  desde una sesión humana. No se amplía este permiso.
- **P3: ventana A/B.** Documentada en LEEME; debe ser breve. La proyección de
  Cartera permite al cliente nuevo encontrar la campaña anterior antes de B.
- **P3: agenda aplazada/cancelada.** La lectura se registra cuando empieza;
  deshacer un borrador al volver recupera la carga pendiente. Un guardado fallido
  tras abortar una lectura no deja «Actualizar» bloqueado. Dos pruebas añadidas.
- **P3: comentarios.** Catálogo documentado actualizado y espacios iniciales
  eliminados de los comentarios de función generados.

## Revisión propia: clientes convertidos y concurrencia

Se aceptó conservar primero la acreditación con solo su origen nuevo, luego el
lead. B fija las huellas de las tres funciones que sincronizan la acreditación;
valida fuente/fecha/confirmación/identidad/episodio y meses abiertos. El analista
se contrasta con el episodio convertido, nunca con un dueño actual posterior.

Tras bloquear leads, los candados mensuales se intentan sin espera y las filas
acreditadas con NOWAIT. Así B no retiene leads esperando un escritor financiero
que necesite ese mismo bloqueo. Probado: rechazo de mes ocupado en 0,05 s y fila
ocupada en 0,04 s; ambos escritores siguieron operativos. Reintento posterior PASS.

Snapshots comparan datos de negocio, fuentes/inversiones/solicitudes, historial,
tareas, ledger y fotos. Acreditación permite cambiar solo `origen`; el lead además
puede actualizar su timestamp técnico. Conversión conserva los totales y la suma
Formulario + Formulario 3, por empresa y analista.

Las revisiones son asesoría; los resultados de pruebas y los gates de publicación
determinan el estado. No se volvió a consultar a Claude para obtener conformidad.
