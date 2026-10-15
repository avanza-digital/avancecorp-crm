// Banco exclusivo local. RPC y roles reales; las fixtures terminan en ROLLBACK.
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const contenedor = 'avancecorp-coordinacion-pg-actual';
const base = 'formulario3_fase2_20261014_review';
const carpeta = fileURLToPath(new URL('.', import.meta.url));
execFileSync('docker', ['cp', `${carpeta}.`, `${contenedor}:/tmp/formulario3-fase2`], { stdio: 'inherit' });
execFileSync('docker', ['exec', contenedor, 'psql', '-X', '-U', 'postgres', '-d', base,
  '-v', 'ON_ERROR_STOP=1', '-f', '/tmp/formulario3-fase2/cartera.sql'], { stdio: 'inherit' });
