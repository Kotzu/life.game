const { chromium } = require('playwright-core');

(async () => {
  const results = [];
  const check = (name, ok, detail) => {
    results.push({ name, ok, detail });
    console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ' — ' + detail : ''}`);
  };

  for (const reducedMotion of ['no-preference', 'reduce']) {
    const browser = await chromium.launch({
      executablePath: '/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell',
      args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
    });
    const page = await browser.newPage({
      viewport: { width: 900, height: 700 },
      reducedMotion,
    });
    const errors = [];
    page.on('pageerror', (e) => errors.push(String(e)));
    page.on('console', (m) => {
      if (m.type() === 'error' && !/ERR_|Failed to load resource/.test(m.text())) errors.push(m.text());
    });

    await page.goto('file:///tmp/claude-0/-home-user-life-game/b6c8f382-9b58-5d1b-a5f5-cb22015d0a49/scratchpad/roomdemo/trophy-room-3d.html');
    await page.waitForTimeout(2500);

    check(`[${reducedMotion}] no js errors`, errors.length === 0, errors.slice(0,2).join(' | '));
    const hook = await page.evaluate(() => !!window.__ktrDemo);
    check(`[${reducedMotion}] scene booted (hook present)`, hook);
    if (!hook) { await browser.close(); continue; }

    const info = await page.evaluate(() => ({
      displays: window.__ktrDemo.displays.length,
      rotatable: window.__ktrDemo.displays.filter(d => d.rotate).length,
    }));
    check(`[${reducedMotion}] 3 rotatable cases of 7 displays`,
      info.displays === 7 && info.rotatable === 3, JSON.stringify(info));

    // core assertion: items rotate 360° — angle advances over time
    const idx = await page.evaluate(() =>
      window.__ktrDemo.displays.findIndex(d => d.rotate));
    const a0 = await page.evaluate(i => window.__ktrDemo.itemAngle(i), idx);
    await page.waitForTimeout(2000);
    const a1 = await page.evaluate(i => window.__ktrDemo.itemAngle(i), idx);
    const degAdvanced = (a1 - a0) * 180 / Math.PI;
    check(`[${reducedMotion}] case item rotates continuously`,
      degAdvanced > 3, degAdvanced.toFixed(1) + '° in 2s (headless ~4fps + dt clamp; full speed at 60fps)');

    // select the cube case programmatically -> card + controls appear
    await page.evaluate(i => window.__ktrDemo.select(window.__ktrDemo.displays[i]), idx);
    await page.waitForTimeout(400);
    check(`[${reducedMotion}] card visible after select`,
      await page.isVisible('#card.show'));
    check(`[${reducedMotion}] rotate controls visible`,
      await page.isVisible('#rotCtl'));

    // slider drives the speed live
    await page.fill('#rotSlider', '80');
    await page.dispatchEvent('#rotSlider', 'input');
    const b0 = await page.evaluate(i => window.__ktrDemo.itemAngle(i), idx);
    await page.waitForTimeout(1000);
    const b1 = await page.evaluate(i => window.__ktrDemo.itemAngle(i), idx);
    const fastDeg = (b1 - b0) * 180 / Math.PI;
    check(`[${reducedMotion}] slider speeds rotation up (80 vs 12 °/s)`,
      fastDeg > degAdvanced * 1.5, fastDeg.toFixed(1) + '°/s-window vs baseline ' + (degAdvanced/2).toFixed(1));

    // toggle stops it
    await page.click('#rotToggle');
    const c0 = await page.evaluate(i => window.__ktrDemo.itemAngle(i), idx);
    await page.waitForTimeout(700);
    const c1 = await page.evaluate(i => window.__ktrDemo.itemAngle(i), idx);
    check(`[${reducedMotion}] toggle OFF stops rotation`,
      Math.abs(c1 - c0) < 1e-6, ((c1-c0)*180/Math.PI).toFixed(3) + '°');

    // full screenshot for the record
    await page.screenshot({ path: `roomdemo/shot_${reducedMotion}.png` });
    await browser.close();
  }

  const failed = results.filter(r => !r.ok);
  console.log(`\nRESULT: ${results.length - failed.length}/${results.length} passed`);
  process.exit(failed.length ? 1 : 0);
})();
