import { click, clickByLabel, waitFor } from '../fixtureControls';

export async function verifyIntegrationSettings(window: () => HTMLDialogElement | null) {
  const press = (label: string) => click(label, window()!);
  const section = (name: string) => window()?.querySelector<HTMLElement>(`section[aria-label="${name}"]`);
  const action = (label: string) => window()?.querySelector<HTMLButtonElement>(`button[aria-label="${CSS.escape(label)}"]`);
  const button = (text: string) => [...(window()?.querySelectorAll<HTMLButtonElement>('button') ?? [])]
    .find((item) => item.textContent?.trim() === text);
  const settled = () => button('Refresh Settings')?.disabled === false;

  await press('MCP Servers');
  const mcp = () => section('MCP Servers');
  if (field<HTMLInputElement>(mcp(), 'locked-fixture')?.disabled !== true || action('Edit locked-fixture')) {
    throw new Error('Settings could edit a managed MCP server');
  }
  await press('Add MCP Server');
  setText(mcp(), 'Server Name', 'fixture.local');
  setText(mcp(), 'Command', 'fixture-stdio');
  setText(mcp(), 'Arguments', '--one\nargument with spaces');
  setText(mcp(), 'Environment Variables (Name=Value)', 'FIXTURE_TEST=isolated');
  setText(mcp(), 'Environment Variable Names', 'FIXTURE_ENV');
  await press('Save MCP Server');
  await waitFor('The failed MCP save discarded the form or reported a confirmed write', () =>
    settled() && field<HTMLInputElement>(mcp(), 'Command')?.value === 'fixture-stdio' &&
    field<HTMLTextAreaElement>(mcp(), 'Environment Variables (Name=Value)')?.value === 'FIXTURE_TEST=isolated');
  await press('Save MCP Server');
  await waitFor('The MCP save did not create the stdio server', () => settled() && !!action('Edit fixture.local'));
  await clickByLabel('Edit fixture.local');
  await waitFor('The stdio edit did not reopen its captured data', () =>
    field<HTMLTextAreaElement>(mcp(), 'Arguments')?.value === '--one\nargument with spaces');
  select(mcp(), 'Transport', 'http');
  await waitFor('Changing MCP transport did not expose the HTTP form', () => !!field(mcp(), 'Server URL'));
  setText(mcp(), 'Server URL', 'https://example.invalid/fixture/mcp');
  setText(mcp(), 'HTTP Headers (Name=Value)', 'X-Fixture=isolated');
  setText(mcp(), 'Environment Headers (Name=Variable)', 'X-Token=FIXTURE_TOKEN');
  setText(mcp(), 'Bearer Token Variable', 'FIXTURE_TOKEN');
  await press('Save MCP Server');
  await waitFor('The HTTP server did not expose its OAuth action', () =>
    settled() && action('Authenticate fixture.local')?.disabled === false);
  await clickByLabel('Authenticate fixture.local');
  await waitFor('MCP authentication did not return to the captured server', () => settled());
  field<HTMLInputElement>(mcp(), 'fixture.local')!.click();
  await waitFor('The MCP server did not disable after refresh', () =>
    settled() && field<HTMLInputElement>(mcp(), 'fixture.local')?.checked === false && !action('Authenticate fixture.local'));
  await clickByLabel('Remove fixture.local');
  await press('Remove MCP Server');
  await waitFor('Removing the MCP server also removed the managed server or left the local row', () =>
    settled() && !action('Edit fixture.local') && !!field(mcp(), 'locked-fixture'));

  await press('Plugins');
  const plugins = () => section('Plugins');
  await waitFor('The plugin catalog was missing', () => !!action('Install Fixture Plugin'));
  if (window()?.querySelector<HTMLInputElement>('input[aria-label="Enable Managed Plugin"]')?.disabled !== true) {
    throw new Error('The workspace-managed plugin could be changed');
  }
  await clickByLabel('Install Fixture Plugin');
  await press('Install Plugin');
  await waitFor('A new plugin did not replace the cached install control', () =>
    settled() && action('Uninstall Fixture Plugin')?.disabled === false);
  const toggle = () => window()?.querySelector<HTMLInputElement>('input[aria-label="Enable Fixture Plugin"]');
  toggle()!.click();
  await waitFor('The plugin policy did not update after toggling', () =>
    settled() && toggle()?.checked === false && toggle()?.disabled === false);
  await clickByLabel('Uninstall Fixture Plugin');
  await press('Uninstall Plugin');
  await waitFor('The plugin catalog did not remove the installed instance', () =>
    settled() && action('Install Fixture Plugin')?.disabled === false && !toggle());
  await press('Add Marketplace');
  setText(plugins(), 'Marketplace Source', 'https://example.invalid/marketplace.git');
  setText(plugins(), 'Git Reference', 'fixture-main');
  await press('Save Marketplace');
  await waitFor('The added marketplace did not appear after its save', () =>
    settled() && action('Upgrade Workshop v1')?.disabled === false);
  await clickByLabel('Upgrade Workshop v1');
  await waitFor('An upgraded catalog retained its former marketplace', () =>
    settled() && action('Upgrade Workshop v2')?.disabled === false && !action('Upgrade Workshop v1'));
  await clickByLabel('Remove Workshop v2');
  await press('Remove Marketplace');
  await waitFor('The removed marketplace remained in the refreshed catalog', () =>
    settled() && button('Refresh Plugins')?.disabled === false && !action('Remove Workshop v2'));

  await press('Skills');
  const skills = () => section('Skills');
  await waitFor('The profile skill did not appear in its own catalog', () => !!field(skills(), 'Fixture Skill'));
  if (field(skills(), 'Bundled Skill') || field(skills(), 'Project Skill')) throw new Error('A skill crossed profile ownership');
  field<HTMLInputElement>(skills(), 'Fixture Skill')!.click();
  await waitFor('The skill catalog did not reflect the new configuration', () =>
    settled() && field<HTMLInputElement>(skills(), 'Fixture Skill')?.checked === false);

  await press('Hooks');
  const hooks = () => section('Hooks');
  await waitFor('The hook list did not publish trust controls', () =>
    action('Trust preToolUse')?.disabled === false && field<HTMLInputElement>(hooks(), 'postToolUse')?.disabled === true);
  await clickByLabel('Trust preToolUse');
  await press('Trust Hook');
  await waitFor('A changed hook was trusted without another review', () => settled() && action('Trust preToolUse')?.disabled === false);
  await clickByLabel('Trust preToolUse');
  await press('Trust Hook');
  await waitFor('The confirmed hook trust did not persist', () =>
    settled() && button('Refresh Hooks')?.disabled === false && !action('Trust preToolUse'));
  field<HTMLInputElement>(hooks(), 'preToolUse')!.click();
  await waitFor('The hook activation did not update', () =>
    settled() && field<HTMLInputElement>(hooks(), 'preToolUse')?.checked === false);

  await press('Browser');
  const browser = () => section('Browser');
  const defaults = () => browser()?.querySelector('fieldset');
  if (field<HTMLInputElement>(browser(), 'Browser Site Tools')?.disabled !== true ||
      field<HTMLSelectElement>(browser(), 'Browser History Access')?.value !== 'deny' ||
      field<HTMLSelectElement>(browser(), 'Browser History Access')?.disabled !== true ||
      field<HTMLSelectElement>(defaults(), 'Downloads')?.disabled !== true) {
    throw new Error('Managed browser requirements were editable or missing');
  }
  field<HTMLInputElement>(browser(), 'Browser Use')!.click();
  await waitFor('Browser use did not follow the confirmed setting', () =>
    settled() && field<HTMLInputElement>(browser(), 'Browser Use')?.checked === true);
  select(defaults(), 'Browse', 'allow');
  await waitFor('The default site policy did not refresh', () =>
    settled() && field<HTMLSelectElement>(defaults(), 'Browse')?.value === 'allow');
  await press('Add Site');
  const siteForm = () => browser()?.querySelector('form');
  setText(siteForm(), 'Site Origin', 'HTTPS://One.Mixed.Test:443/');
  select(siteForm(), 'Browse', 'allow');
  await press('Save Site');
  const site = 'https://one.mixed.test:443';
  await waitFor('The browser setting changed the origin boundary', () => settled() && !!action(`Edit ${site}`));
  await clickByLabel(`Edit ${site}`);
  select(siteForm(), 'Uploads', 'deny');
  await press('Save Site');
  await waitFor('The edited site did not refresh', () => settled() && !!action(`Edit ${site}`));
  await clickByLabel(`Edit ${site}`);
  if (field<HTMLSelectElement>(siteForm(), 'Uploads')?.value !== 'deny') throw new Error('A site value did not save');
  await press('Cancel Site');
  await clickByLabel(`Remove ${site}`);
  await press('Remove Site');
  await waitFor('Removing a site lost an unrelated origin', () =>
    settled() && !action(`Edit ${site}`) && !!action('Edit https://preserve.some.test:443') &&
    browser()?.textContent?.includes('https://strict.some.test') === true);
}

function field<Element extends HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>(
  root: ParentNode | undefined | null, title: string,
): Element | undefined {
  const label = [...(root?.querySelectorAll('label') ?? [])].find((item) => [...item.childNodes]
    .some((node) => node.nodeType === Node.TEXT_NODE && node.textContent?.trim() === title));
  return label?.querySelector<Element>('input, select, textarea') ?? undefined;
}

function setText(root: ParentNode | undefined | null, label: string, value: string) {
  const control = field<HTMLInputElement | HTMLTextAreaElement>(root, label);
  if (!control) throw new Error(`Missing setting field ${label}`);
  control.value = value;
  control.dispatchEvent(new Event('input', { bubbles: true }));
}

function select(root: ParentNode | undefined | null, label: string, value: string) {
  const control = field<HTMLSelectElement>(root, label);
  if (!control) throw new Error(`Missing setting choice ${label}`);
  control.value = value;
  control.dispatchEvent(new Event('change', { bubbles: true }));
}
