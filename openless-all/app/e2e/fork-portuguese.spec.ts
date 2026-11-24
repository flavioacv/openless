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
