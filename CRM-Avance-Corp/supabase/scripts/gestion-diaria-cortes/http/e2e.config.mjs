// Gate E2E existente, aislado del 5199 ocupado. NO es evidencia de backend real.
import { fileURLToPath } from 'node:url';
import base from '../../../../app/playwright.config.ts';
import { carpeta } from './banco.mjs';
const app=fileURLToPath(new URL('../../../../app/',import.meta.url));
export default {
  ...base,
  testDir:`${app}e2e`,
  outputDir:`${carpeta}/e2e-resultados`,
  use:{...base.use,baseURL:'http://127.0.0.1:59323'},
  webServer:{...base.webServer,cwd:app,
    command:'npm run dev -- --port 59323 --host 127.0.0.1 --strictPort',
    url:'http://127.0.0.1:59323'},
};
