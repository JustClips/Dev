const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch({ args: ['--allow-file-access-from-files'] });
  const p = await b.newPage({ viewport: { width: 1024, height: 678 } });
  await p.goto('file://' + __dirname + '/logo.html');
  await p.waitForTimeout(2500);
  await p.screenshot({ path: __dirname + '/../out/ui/Logo.png', omitBackground: true });
  await b.close();
})();
