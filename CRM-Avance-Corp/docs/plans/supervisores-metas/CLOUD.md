# Banco cloud de supervisores

16/10/2026. Rama autorizada `supervisores-ventas-equipo-20261016`, proyecto
`olqqhmatdhrasbzxarbz`, ID `e0a51be1-f897-4970-a6f1-6c2d9dd5ff54`.
Costo aceptado por Miguel: US$0,01344/h; eliminación al terminar.

El replay automático falló en el historial antiguo, con 86 migraciones. Se
reprodujeron los esquemas actuales `public`, `private`, `crm`, los roles internos,
dos triggers de Auth y los 484 registros de migración íntegros, sin datos reales.
Las dos tareas cron se desactivaron antes de crear identidades de prueba.
Las 1.110 funciones coincidieron exactamente en definición, propietario y ACL.
La restauración no replica los defaults de futuros objetos de `supabase_admin`
(rol administrado) ni las policies dependientes de Storage: quedan fuera de esta
prueba, que no crea objetos productivos ni cambia Storage. No se debilitaron las
huellas del preflight. Los intentos de restauración fallidos se revirtieron.

La matriz SQL completa pasó 59 comprobaciones en una transacción con rollback.
La matriz HTTP creó diez identidades ficticias mediante Auth Admin, sin correos.
Las aserciones usan anon key y JWT humanos: 27 respuestas de referencia y 27
posteriores, diez inicios de sesión, denegación anon/cliente, bajas de perfil y
CRM, cambio de rol con el mismo JWT, septiembre intacto, PEN/USD, cooperativas,
supervisor sin analistas, supervisor sin ventas y fotografía de mes sellado.
Resultado: 37 comprobaciones PASS. Contratos, cooperativas y sellos idénticos.

Advisors antes/después: seguridad 382 → 380, rendimiento 336 → 334, sin hallazgos
nuevos. Las 23 Edge Functions coinciden entre producción y rama en slug, versión,
SHA-256 del bundle, configuración JWT, import map y estado.

Supabase asignó la versión `20261016162937` al aplicar el SQL en la rama. El
archivo preparado como `20261016180000` se renombró sin cambiar bytes; las
referencias antiguas de los encargos/dictámenes de Claude se conservan como
evidencia histórica. SHA-256: `47927095eb7dcdcd9bcbfcc9c9fc0e44f9c1ba14f121d4569f2cb709431df53c`.
El SQL registrado coincide íntegramente con el archivo (MD5
`bc53e8cf6aa92504739c082ca7e1707f`). La única diferencia entre las 1.110 funciones
es `crm.cumplimiento_metas_fn(date)`; conserva propietario y ACL. La única
diferencia de historial es esta nueva migración.

Promoción productiva y eliminación de rama pendientes de ejecución.
