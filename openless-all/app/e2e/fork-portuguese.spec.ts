import { expect, test } from '@playwright/test';

test.use({ locale: 'pt-BR' });

test('the fork retains meetings and translates the new usage screen', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('ol.locale', 'pt'));
  await page.goto('/');
  await expect(page.getByRole('button', { name: 'Reuniões', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Uso', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Uso', exact: true })).toBeVisible();
  await expect(
    page.getByText('Registros de reconhecimento de fala', { exact: true }),
  ).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Registros diários', exact: true })).toBeVisible();
  await page
    .getByRole('navigation', { name: 'Páginas de uso' })
    .getByRole('button', { name: 'Serviços e finalidades', exact: true })
    .click();
  await expect(
    page.getByRole('heading', { name: 'Serviços e finalidades', exact: true }),
  ).toBeVisible();
  await expect(page.getByText('Usage', { exact: true })).toHaveCount(0);
});

test('the new desktop guide honors the Portuguese preference', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('ol.locale', 'pt'));
  await page.goto('/?onboarding=1&os=mac');
  await expect(page.getByRole('button', { name: 'Vamos começar', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Explorar primeiro', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Reuniões', exact: true })).toBeVisible();
});

test('Android setup permissions and overlay controls render in Portuguese', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 740 });
  await page.addInitScript(() => localStorage.setItem('ol.locale', 'pt'));
  await page.goto(
    'http://127.0.0.1:5326/e2e/fixtures/android-onboarding.html?os=android&locale=pt',
  );
  const titles = [
    'Permissão de microfone',
    'Serviço de acessibilidade',
    'Permissão de sobreposição',
    'Configurações da sobreposição',
    'Serviço em nuvem de ASR',
    'Serviço de LLM',
  ];
  for (let step = 0; step < titles.length; step++) {
    await expect(page.getByText(`Etapa ${step + 1} de 6`, { exact: true })).toBeVisible();
    await expect(page.getByText(titles[step], { exact: true }).first()).toBeVisible();
    const copy = await page.locator('body').innerText();
    expect(copy).not.toMatch(/[\u4e00-\u9fff]/);
    if (step < titles.length - 1) {
      await page.getByRole('button', { name: 'Avançar', exact: true }).click();
    }
  }
  await page.getByRole('button', { name: 'Concluir e entrar', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Guide completed' })).toBeVisible();
});
