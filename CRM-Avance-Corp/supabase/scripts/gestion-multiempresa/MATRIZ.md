# Gestión integral de la ficha multiempresa

Implementación del plan del 16/09/2026. Candidata local; no instalada ni publicada.

| Acción | Fuente / autoridad | Regla preservada |
| --- | --- | --- |
| Corregir perfil y banca Avance | `cliente_detalle_fn`, `ClienteForm`, RLS de perfiles / `actualizar_cliente_gerencia_con_domicilio` | Perfil real enlazado; analista vigente, creación original < 5 h y ámbito propio; Gerencia/Admin conservan su excepción. PEN/USD y cuentas contractuales conservadas. |
| Documento y correo Avance | RPC administrativa de documento y Edge de correo existentes | Admin/Superadmin; motivo y auditoría. Gerencia sola no recibe estos permisos. |
| Contacto sin perfil Avance | Extensión de datos de la identidad neutral | Responsable actual y autor del registro original, < 5 h; Gerencia/Admin sin límite. No modifica el nombre histórico de cierres ni fabrica Auth/perfiles/leads. |
| Documento neutral | `corregir_documento_inversionista_fn` | Administración, identidad canónica y documento vigente concreto; motivo obligatorio. |
| Corregir contrato Avance | `actualizar_contrato_con_cuenta_pdf_v3` | Autor, cartera y < 5 h; excepciones administrativas del escritor. No cambia moneda. Conserva cuotas pagadas, cotitulares, cuenta y revisión PDF. |
| Corregir inversión COOPAC | `corregir_cierre_externo` + validación de condiciones COOPAC | Solo Gerencia, regla vigente desde agosto. No se amplía al analista. Empresa/moneda/identidad/autor conservados. Anulada no corregible. |
| Cronograma, detalle, PDF | Lectores de contrato, cronograma, titulares y archivo publicados | Lectura de un contrato concreto. Directorio mantiene la redacción y las capacidades existentes. |
| Tasas y autorizaciones | Historial de tasas del cliente | Se reusa el historial y su ámbito. Nueva inversión sigue por `ContratoNuevo`. |
| Desglose económico | `crm.operaciones_cartera` | Sin cálculos alternativos de conversión; históricos incompletos identificados. |
| Atribución y reasignación | `atribucion_contrato` / `reasignar_analista_contrato` | Gerencia/Admin; motivo obligatorio; incluye atribución efectiva y cadena de aumentos. |
| Alta directa | `ClienteForm` / Edge `crear-cliente` | Supervisión/Gerencia con capacidad vigente; analista convierte desde Leads. |

La fecha de la identidad no reemplaza la creación original. Para la identidad
sin perfil se toma el antecedente más antiguo entre sus identidades, leads y
fuentes económicas; una vinculación, fusión o inversión posterior no reinicia
la ventana. Las correcciones neutrales usan versión esperada y recibo idempotente;
las lecturas y escrituras verifican persona canónica, ámbito y banderas.

Las notas y correcciones de contacto actuales tienen una fuente neutral propia.
Si existe un perfil Avance, prevalece ese perfil y se usa su formulario. La
información histórica de inversión se conserva. No se modifican objetos de
`public`, ni se crean accesos directos a las tablas nuevas.

La entrada «Gestión Avance» se retira del módulo habilitado después de verificar
los recorridos. El componente anterior sigue siendo el fallback cuando F5 está
apagado; la reversa web recupera su entrada. El correo de acceso solo existe en
perfiles Avance: no se crea ni ofrece un correo Auth para una identidad neutral.
El escritor PDF actual exige rol analista del portal a los autores no globales;
ser vendedor CRM por sí solo no concede esa corrección. La matriz no amplía ese
permiso. El despliegue requiere el SQL exacto revisado y la publicación del proyecto.
