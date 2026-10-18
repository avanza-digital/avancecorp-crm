# Referidos propios de supervisores

Decisión de Miguel, 16/10/2026: al crear un referido, su responsable siempre es
el supervisor que lo registra. Un destino omitido se convierte en su propio UUID;
un destino explícito distinto se rechaza, incluso si pertenece a su equipo.

El cambio solo amplía el alta de Referido para Supervisión. Los demás orígenes,
la gestión posterior del lead, el origen inmutable, la conversión, las metas y
el ranking conservan sus reglas. No crea una meta individual nueva.

## Ensayo local

Desde la raíz CRM:

```sh
python3 supabase/scripts/supervisores-referidos/ensayar.py
```

Solo acepta la base vacía `supervisores_referidos_20261016` del contenedor
`avancecorp-coordinacion-pg-actual`. Se restauró la estructura productiva sin
datos, leída el 16/10/2026. `semilla.sql` inserta únicamente fixtures sintéticos.
El administrador prepara fixtures/DDL y los metadatos de un comprobante; todas
las operaciones comerciales y pruebas de acceso usan `SET LOCAL ROLE authenticated`
con identidades distintas. Triggers y RLS permanecen activos. Al final revierte
datos y DDL y exige que el banco siga vacío.

`prueba.sql` cubre permisos de roles, autor/dueño, ausencia de bandeja, supervisor
sin equipo, intentos de asignar a terceros, DNI/CE/pasaporte, idempotencia,
duplicados, INSERT directo revocado, lectura ajena, baja de perfil y membresía,
cambio de rol, asignación original de otros canales, conversión cooperativa por
el formulario compartido actual, atribución en Cartera y producción propia,
reversa/reaplicación y paridad de ACL/policies.

`vivo/crear_lead_si_disponible.sql` conserva la definición previa cotejada con
producción. `reversa.sql` solo acepta la huella de esta migración y restaura
exactamente esa definición. No borra los referidos que ya se hubieran registrado.

## Promoción

NO aplicar directamente a producción. Validar sobre rama Supabase, con Auth y
PostgREST reales, comparar advisors y promover primero la migración por merge.
Solo después publicar el frontend
desde main verificado siguiendo el procedimiento de release. Una sesión web
anterior seguirá sin ofrecer la opción hasta recargarse.
