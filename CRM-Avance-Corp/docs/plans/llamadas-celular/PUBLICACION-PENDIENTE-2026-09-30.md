# F1 pendiente durante la publicación de documentos

Miguel autorizó publicar únicamente la corrección DNI/CE/pasaporte y respondió
«Solo documentos; mantener F1 pendiente» al consultar el alcance del PR #148.

Se integró Main completo y se retiró temporalmente la activación de F1 en
`App.tsx`, `contacto.tsx`, `auth.tsx` y `gestion-diaria/analista.tsx`.
Esos cuatro archivos recuperan exactamente el comportamiento anterior al PR;
sus pruebas de contacto y Gestión Diaria corresponden a ese comportamiento.
Los componentes, coordinador, búsqueda, rutas y pruebas unitarias de F1
permanecen versionados. El receptor no se monta, el contacto no arma la cola
compartida y App no conserva el número recibido en el enlace del celular.

La reactivación requiere autorización específica de Miguel, restaurar la
integración de esos archivos (el commit de aplazamiento está separado de la
corrección de documentos), ajustar sus pruebas y superar los gates vigentes.
No revertir todo el release de documentos para reactivar F1.
