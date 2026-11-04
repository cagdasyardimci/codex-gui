// Generate offline rendering assets from the root pnpm lockfile.
import * as esbuild from 'esbuild';
import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const templates = resolve(directory, 'Sources/CodexGUI/Resources');
const generated = resolve(templates, 'MarkdownRuntime');
const resources = resolve(generated, 'Mermaid');
// Only generated files live here; clearing them prevents stale assets after upgrades.
await rm(generated, { recursive: true, force: true });
for (const name of ['Mermaid', 'KaTeX']) {
    const destination = resolve(generated, name);
    await mkdir(destination, { recursive: true });
    const integrationFiles = (await readdir(resolve(templates, name)))
        .filter(file => file.endsWith('.html') || file.endsWith('.js'));
    for (const file of integrationFiles) {
        await cp(resolve(templates, name, file), resolve(destination, file));
    }
}
for (const [source, target] of [
    ['mermaid/dist/mermaid.min.js', 'Mermaid/mermaid.min.js'],
    ['mermaid/LICENSE', 'Mermaid/LICENSE'],
    ['katex/dist/katex.min.js', 'KaTeX/katex.min.js'],
    ['katex/dist/katex.min.css', 'KaTeX/katex.min.css'],
    ['katex/dist/fonts', 'KaTeX/fonts'],
    ['katex/LICENSE', 'KaTeX/LICENSE']
]) {
    await cp(resolve(directory, 'node_modules', source), resolve(generated, target), { recursive: true });
}
let adaptedModules = 0;
const result = await esbuild.build({
    absWorkingDir: directory,
    entryPoints: ['node_modules/@mermaid-js/layout-elk/dist/mermaid-layout-elk.core.mjs'],
    bundle: true,
    format: 'iife',
    globalName: 'markdownElkLayouts',
    minify: true,
    target: 'safari17',
    outfile: resolve(resources, 'elk.min.js'),
    metafile: true,
    write: false,
    plugins: [{
        name: 'markdown-elk-root-spacing',
        setup(build) {
            build.onLoad({
                filter: /[/\\]@mermaid-js[/\\]layout-elk[/\\]dist[/\\]chunks[/\\]mermaid-layout-elk\.core[/\\]render-[^/\\]+\.mjs$/
            }, async ({ path }) => {
                const source = await readFile(path, 'utf8');
                const upstream = '"spacing.baseValue": 35';
                if (source.split(upstream).length - 1 !== 1) {
                    throw new Error('Pinned ELK adapter must contain exactly one root spacing value of 35.');
                }
                adaptedModules += 1;
                // Match the reference connector spacing; retain the separate cluster value of 30.
                return {
                    contents: source.replace(upstream, '"spacing.baseValue": 40'),
                    loader: 'js',
                    resolveDir: dirname(path)
                };
            });
        }
    }]
});
if (adaptedModules !== 1) {
    throw new Error(`Expected exactly one pinned ELK layout module; found ${adaptedModules}.`);
}
const packages = new Set(Object.keys(result.metafile.inputs).flatMap(input => {
    const match = input.match(/^(.*node_modules\/(?:@[^/]+\/)?[^/]+)\//);
    return match ? [match[1]] : [];
}));
// Sort by package identity, independent of the package manager's on-disk layout.
const packageRecords = await Promise.all([...packages].map(async name => {
    const path = resolve(directory, name);
    const metadata = JSON.parse(await readFile(resolve(path, 'package.json'), 'utf8'));
    return { path, metadata };
}));
packageRecords.sort((a, b) => {
    for (const key of ['name', 'version']) {
        if (a.metadata[key] < b.metadata[key]) return -1;
        if (a.metadata[key] > b.metadata[key]) return 1;
    }
    return 0;
});
const notices = [];
for (const { path, metadata } of packageRecords) {
    notices.push(`${metadata.name}@${metadata.version}\n${JSON.stringify(metadata.repository ?? '')}\n`);
    for (const file of (await readdir(path)).filter(file => /^(LICENSE|COPYING)/i.test(file)).sort()) {
        notices.push(await readFile(resolve(path, file), 'utf8'));
    }
}
for (const output of result.outputFiles) {
    await writeFile(output.path, output.contents);
}
await writeFile(resolve(resources, 'ELK-LICENSES.txt'), notices.join('\n\n--------------------\n\n'));
