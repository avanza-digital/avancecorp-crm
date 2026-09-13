VERDICT: CHANGES_REQUESTED

Revisor independiente auditor_rls (sólo lectura). Claude no completó dos intentos del wrapper.

Recomienda conservar el censo completo de 34 candidatos y descontar del techo sólo cuatro auxiliares de firma, definición, propietario y ACL exactos. Cambia de forma explícita la semántica del techo: 30 candidatos sujetos al control más cuatro falsos positivos auditados; no es una reducción de consultas crudas. No modificar runtime financiero para sortear el detector.

Requisitos: conjunto fijo de cuatro identidades, helper privado con integridad/permisos comprobados, declaración y sello para todos los candidatos, rechazo de deriva en cuerpo/configuración/propietario/ACL, auxiliares ausentes o duplicados, sobrecargas o funciones nuevas, exenciones alteradas y subida de tope. Preservar todos los mutantes anteriores y rollback.

Evidencia del revisor: historial_decisiones_tasa líneas19–45 y56 cuenta solicitudes; inversion_historica_estado79–96/124–140 valida identidad y titulares; inversion_historica_aplicar40–44/95–105 deduplica JSON y bloquea filas; metricas_multiempresa41–94/117–124 usa el núcleo para conversión, leads sólo para veto.

El PRIMARY acepta los requisitos. Las dos huellas caducadas se auditan aparte mediante comparación exacta con las migraciones que originaron la declaración y con la versión F4 instalada; no fueron aprobadas en esta revisión. RLS/ensayo/advisors pendientes de ejecución.
