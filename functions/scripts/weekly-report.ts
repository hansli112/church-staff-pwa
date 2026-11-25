// Writes the 週報 email the weeklyReport function sends on Mondays to a
// file, to look at before it goes out. Only reads.
//
//   scripts/as-owner.sh marthasit npx --prefix functions tsx functions/scripts/weekly-report.ts \
//     --project marthasit --out reports/weekly.html
//
// --end YYYY-MM-DD picks the Sunday the week ends on (default: the last
// one). GA4 and Search Console are read on the prod project only, as
// search-console@ by impersonation (the gcloud account may impersonate it).
import { writeFileSync } from 'node:fs';

import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

import { PROD_PROJECT } from '../src/common.js';
import { collectWeeklyReport, lastSunday, weeklyMail } from '../src/weeklyReport.js';

const args = process.argv.slice(2);
const flag = (name: string) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : undefined;
};
const project = flag('project');
const out = flag('out');
if (!project || !out) throw new Error('Usage: --project <id> --out <file.html> [--end YYYY-MM-DD]');

initializeApp({ projectId: project });
const now = () => new Date();
const report = await collectWeeklyReport(
  {
    db: getFirestore(),
    now,
    fetch,
    analytics: project === PROD_PROJECT
      ? {
          accessToken: async () => (await applicationDefault().getAccessToken()).access_token,
          reader: `search-console@${PROD_PROJECT}.iam.gserviceaccount.com`,
          ga4Property: '557570984',
          gscSite: 'sc-domain:marthasit.com',
          project: PROD_PROJECT,
        }
      : null,
  },
  flag('end') ?? lastSunday(now()),
);
const mail = weeklyMail(report);
writeFileSync(out, mail.html);
console.log(`${mail.subject}\nWrote ${out}`);
