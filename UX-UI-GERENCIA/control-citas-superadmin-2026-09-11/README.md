# Control de Citas para Superadmin

[Probar el panel local](http://127.0.0.1:4180/prototypes/control-citas.html).

El panel está implementado en el CRM, ruta `#/config-citas`, exclusivo de Superadmin. En esta entrega guarda **borradores**; la instalación del guardado compartido y la aplicación de las reglas al tablero siguen pendientes. La vista local permite probar el formulario y conserva sus ejemplos sólo en la pestaña, sin sesión ni llamadas al servidor del CRM.

## Qué permite configurar

- Meta interna de citas por lead: valor inicial 1,25, no visible como meta para el cliente.
- Objetivos de entrevistas y depósitos: 70% inicialmente.
- Incluir o excluir los leads registrados manualmente por el propio analista; todos los demás asignados del mes cuentan, incluso sin cita.
- Actividad de los manuales, conteo de entrevistas, base del avance y de depósitos, mes y analista de atribución, y mes de inicio previsto. Las siete decisiones pendientes empiezan en «Por definir».
- Nota e historial de versiones, sin activación automática. El objetivo se configura para todos los analistas; no hay excepciones individuales en esta entrega.

## Cómo probarlo

1. Cambia 1,25 o los dos porcentajes y revisa el ejemplo de citas.
2. Abre «Reglas de avance» para elegir cómo contar. Puedes guardar un borrador incompleto.
3. Guarda y recarga. En la vista de prueba se conserva en esta pestaña.
4. «Cargar último borrador» solicita descartar expresamente si hay cambios; cancelar conserva la edición.

En el CRM real, Superadmin sin Gerencia entra desde el menú «Control de Citas». Superadmin con Gerencia lo encuentra en Configuración. Otros roles no tienen esta pantalla. Mientras el servidor no tenga el SQL, se muestra el estado de guardado no habilitado y no se finge una configuración guardada.

## Diseño y evidencia

Se reutilizan Sidebar, ConfiguracionShell, Card, Input, Select, Button y Dialog del CRM. IBM Plex Sans y colores/variables existentes; tres metas en horizontal y reglas desplegables. Sin dependencias nuevas.

- [Escritorio](escritorio.png), [reglas abiertas](reglas.png), [móvil](movil.png).
- [Verificación](verificacion.json), [check final](check-final.log), [E2E general](e2e-general.log), [captura sin red ni desbordamiento](visual.json).
- [Review de Claude](revision-claude.txt), [evaluación y correcciones de Codex](evaluacion-codex.md).

PASS: `npm run check` final (3.426 pruebas); PostgreSQL 17 aislado; cinco E2E finales de Control de Citas/Superadmin, incluidos conflicto, persistencia, teclado, móvil y servidor sin migración. La suite E2E completa previa a los ajustes del review pasó 175 pruebas y omitió 26; después se repitieron los cinco flujos afectados.

NOT RUN: `gate:realidad` (falta SUPABASE_URL en ese comando), aplicación en rama de Supabase, matriz RLS completa y advisors de esa rama, regeneración completa de tipos del catálogo nuevo, instalación y navegador autenticado en producción. El banco SQL mínimo no sustituye esos pasos. Se leyeron sólo los dos helpers existentes en producción para verificar su contrato.

## SQL listo para revisar

[Candidato SQL](../../CRM-Avance-Corp/supabase/migrations/20260911212756_crm_control_citas_superadmin_borradores.sql). Crea una tabla de borradores y dos funciones de lectura/guardado, con autorización de Superadmin activo, validación, auditoría e historial protegido. No modifica los lectores ni cálculos actuales de Citas, ni las tablas operativas. El autor se retiene con FK NO ACTION; la desactivación de perfiles está soportada y probada.

La regla de `BASE DE CONOCIMINETO/AVANCECORP/Inicio.md` pide mostrar el SQL y esperar confirmación antes de cambios en la base. Tras autorización: ensayo en rama, gates, regeneración de tipos y circuito de instalación/publicación desde Main verificado. No se publicó ni se hizo commit de este trabajo.
