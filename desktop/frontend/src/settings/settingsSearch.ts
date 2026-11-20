export const settingsSections = [
  { id: 'account', title: 'Account' },
  { id: 'usage', title: 'Usage & Billing' },
  { id: 'configuration', title: 'Configuration' },
  { id: 'personalization', title: 'Personalization' },
  { id: 'appearance', title: 'Appearance' },
  { id: 'notifications', title: 'Notifications' },
  { id: 'mcp', title: 'MCP Servers' },
  { id: 'plugins', title: 'Plugins' },
  { id: 'skills', title: 'Skills' },
  { id: 'hooks', title: 'Hooks' },
  { id: 'browser', title: 'Browser' },
] as const;

export type SettingsSection = typeof settingsSections[number]['id'];
export type SettingsMatch = { section: SettingsSection; label: string; keys?: string; focus?: string };

const controls: SettingsMatch[] = [
  { section: 'account', label: 'Sign Out', keys: 'account email', focus: 'Sign Out…' },
  { section: 'usage', label: 'Daily Token Usage', keys: 'limits tokens rate' },
  { section: 'usage', label: 'Usage Reset Credits', keys: 'usage billing redeem' },
  { section: 'configuration', label: 'Approval Policy', keys: 'permission managed approvals', focus: 'Approval Policy' },
  { section: 'configuration', label: 'Sandbox Mode', keys: 'permissions sandbox safety', focus: 'Sandbox Mode' },
  { section: 'configuration', label: 'Available Reasoning Efforts', keys: 'model thinking reasoning' },
  { section: 'configuration', label: 'Compress Local Chat History', keys: 'history storage compression' },
  { section: 'personalization', label: 'Codex Instructions', keys: 'agents.md global instructions', focus: 'Codex Instructions' },
  { section: 'personalization', label: 'Enable Codex Memories', keys: 'memory personalization' },
  { section: 'appearance', label: 'Appearance Mode', keys: 'system light dark', focus: 'Appearance Mode' },
  { section: 'appearance', label: 'Theme', keys: 'preset appearances export copy', focus: 'Theme' },
  { section: 'appearance', label: 'Colors', keys: 'foreground background accent color', focus: 'Background Hex' },
  ...['UI', 'Content', 'Code'].flatMap((role): SettingsMatch[] => [
    { section: 'appearance', label: `${role} Font`, keys: `${role} typeface typography family`, focus: `${role} Font` },
    { section: 'appearance', label: `${role} Font Size`, keys: `${role} typography size`, focus: `${role} Font Size` },
  ]),
  { section: 'notifications', label: 'Task Completion', keys: 'notifications alerts when unfocused', focus: 'Task Completion' },
  { section: 'notifications', label: 'Permission Requests', keys: 'notifications approvals alert', focus: 'Permission Requests' },
  { section: 'notifications', label: 'Questions', keys: 'notifications prompts alert', focus: 'Questions' },
  { section: 'notifications', label: 'Import Sound…', keys: 'notifications custom sound wav aiff caf', focus: 'Import Sound…' },
  { section: 'mcp', label: 'Add MCP Server', keys: 'stdio http command environment', focus: 'Add MCP Server' },
  { section: 'plugins', label: 'Add Marketplace', keys: 'plugin catalog repository', focus: 'Add Marketplace' },
  { section: 'hooks', label: 'Refresh Hooks', keys: 'hooks trust a hook', focus: 'Refresh Hooks' },
  { section: 'browser', label: 'Browser History Access', keys: 'allow deny permission history' },
  { section: 'browser', label: 'Default Site Permissions', keys: 'browser downloads uploads site tools' },
  { section: 'browser', label: 'Add Site', keys: 'browser origin website permission', focus: 'Add Site' },
];

const entries: SettingsMatch[] = [
  ...settingsSections.map(({ id, title }) => ({ section: id, label: title })),
  ...controls,
];

export function matchSettings(query: string): SettingsMatch[] {
  const terms = query.toLocaleLowerCase().trim().split(/\s+/).filter(Boolean);
  if (!terms.length) return [];
  return entries.filter(({ label, keys }) => {
    const text = `${label} ${keys ?? ''}`.toLocaleLowerCase();
    return terms.every((term) => text.includes(term));
  }).sort((a, b) => {
    const exact = (label: string) => label.toLocaleLowerCase().startsWith(terms.join(' '));
    return Number(exact(b.label)) - Number(exact(a.label)) || a.label.length - b.label.length;
  });
}
