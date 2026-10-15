// Gate focalizado: SQL real, roles reales, banco local exclusivo y rollback.
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const contenedor = 'avancecorp-coordinacion-pg-actual';
const base = 'formulario3_fase1_20261014_v2';
const carpeta = fileURLToPath(new URL('.', import.meta.url));
execFileSync('docker', ['cp', `${carpeta}fixtures.sql`, `${contenedor}:/tmp/formulario3-fase1/fixtures.sql`], { stdio: 'inherit' });
execFileSync('docker', ['cp', `${carpeta}permisos.sql`, `${contenedor}:/tmp/formulario3-fase1/permisos.sql`], { stdio: 'inherit' });
execFileSync('docker', ['exec', contenedor, 'psql', '-X', '-U', 'postgres', '-d', base, '-v', 'ON_ERROR_STOP=1', '-f', '/tmp/formulario3-fase1/permisos.sql'], { stdio: 'inherit' });
